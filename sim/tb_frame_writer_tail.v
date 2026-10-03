`timescale 1ns/1ps
// 尾突发必须完整结束，后续新事务继续可接受；同时核对逐字地址和读写仲裁。
module tb_frame_writer_tail;
 reg clk=0,rst=1,req=0,rd_busy=0;reg [20:0] len=0;reg [9:0] used=0;
 wire ack,finish,busy,wr;wire [20:0]addr;integer i,writes=0,cycles;
 always #5 clk=~clk;
 frame_fifo_write #(.WRITE_V_FLIP(0),.BURST_SIZE(16)) dut(.rst(rst),.mem_clk(clk),
 .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(rd_busy),
 .O_wr_busy(busy),.App_wr_en(wr),.App_wr_addr(addr),.write_req(req),.write_req_ack(ack),
 .write_finish(finish),.write_addr_0(21'd100),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(2'd0),.write_len(len),.fifo_aclr(),.rdusedw(used));
 always @(posedge clk)if(!rst&&wr)begin
   if(used==0 || addr!==100+writes || rd_busy)$fatal(1,"FAIL writer word/address/reservation");
   used<=used-1;writes<=writes+1;
 end
 task transaction;input integer length;
 begin @(negedge clk);len=length;used=length;writes=0;req=1;rd_busy=1;
 wait(ack);@(negedge clk);req=0;repeat(8)@(negedge clk);
 if(writes!=0)$fatal(1,"FAIL writer started during read reservation");rd_busy=0;
 cycles=0;while(!finish)begin @(negedge clk);cycles=cycles+1;
 if(cycles>1000)$fatal(1,"FAIL tail deadlock length=%0d writes=%0d",length,writes);end
 if(writes!=length || used!=0)$fatal(1,"FAIL tail length accounting");
 repeat(8)@(negedge clk);end endtask
 initial begin repeat(3)@(negedge clk);rst=0;
 transaction(1);transaction(16);transaction(17);transaction(31);transaction(129);
 $display("TB_FRAME_WRITER_TAIL PASS lengths=1,16,17,31,129");$finish;end
 initial begin #100000;$fatal(1,"FAIL writer timeout");end
endmodule
