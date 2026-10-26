`timescale 1ns/1ps
// 尾突发必须完整结束，后续新事务继续可接受；同时核对逐字地址和读写仲裁。
module tb_frame_writer_tail;
 reg clk=0,rst=1,req=0,rd_busy=0,sdr_busy=0;reg [20:0] len=0;reg [9:0] used=0;
 wire ack,finish,busy,wr;wire [20:0]addr;integer i,writes=0,cycles;
 always #5 clk=~clk;
 frame_fifo_write #(.WRITE_V_FLIP(0),.BURST_SIZE(16)) dut(.rst(rst),.mem_clk(clk),
 .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(sdr_busy),.App_rd_busy(rd_busy),
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
 // 分批到达的数据与当拍读/刷新阻塞：旧资格不得跨突发残留。
 task streamed_transaction;input integer length;
 integer supplied;
 begin
 @(negedge clk);len=length;used=0;writes=0;req=1;rd_busy=0;sdr_busy=0;supplied=0;
 wait(ack);@(negedge clk);req=0;
 wait(!ack);cycles=0;
 while(!finish)begin
   @(negedge clk);cycles=cycles+1;
   if(cycles%3==0 && supplied<length)begin used=used+1;supplied=supplied+1;end
   // 只在尚未授予写事务时模拟另一个主机和刷新抢占。
   if(dut.state==2)begin rd_busy=(cycles%11)<4;sdr_busy=(cycles%17)<3;end
   else begin rd_busy=0;sdr_busy=0;end
   #1; // 组合仲裁须先传播，随后在下一上升沿采样。
   if((rd_busy || sdr_busy) && dut.state==2 && busy)
      $fatal(1,"FAIL registered eligibility bypassed current reservation");
   if(cycles>10000)$fatal(1,"FAIL streamed writer deadlock");
 end
 if(writes!=length || used!=0 || supplied!=length)$fatal(1,"FAIL streamed length accounting");
 rd_busy=0;sdr_busy=0;repeat(8)@(negedge clk);
 end endtask
 initial begin repeat(3)@(negedge clk);rst=0;
 transaction(1);transaction(16);transaction(17);transaction(31);transaction(129);
 streamed_transaction(129);streamed_transaction(513);
 $display("TB_FRAME_WRITER_TAIL PASS tails/streaming/read-refresh-reservation/restart");$finish;end
 initial begin #200000;$fatal(1,"FAIL writer timeout");end
endmodule
