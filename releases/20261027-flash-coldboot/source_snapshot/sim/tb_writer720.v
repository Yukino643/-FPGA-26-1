`timescale 1ns/1ps
// 原生writer全帧：逐字检查底向上BMP到顶向下页地址，不依赖scaler。
module tb_writer720;
    reg clk=0,rst=1,req=0;
    always #4 clk=~clk;
    wire ack,finish,busy,wr;
    wire [20:0] addr;
    integer count=0,expected,pass_number;
    reg [1:0] page=0;
    frame_fifo_write #(.WRITE_V_FLIP(1),.BURST_SIZE(256),.FRAME_WIDTH(640),.FRAME_HEIGHT(720)) dut(
        .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),
        .O_wr_busy(busy),.App_wr_en(wr),.App_wr_addr(addr),.write_req(req),.write_req_ack(ack),.write_finish(finish),
        .write_addr_0(21'd0),.write_addr_1(21'h80000),.write_addr_2(21'd0),.write_addr_3(21'd0),
        .write_addr_index(page),.write_len(21'd460800),.fifo_aclr(),.rdusedw(10'd511));
    always @(posedge clk) if(!rst && wr) begin
        expected=(page==0 ? 0:524288)+(719-count/640)*640+count%640;
        if(addr!==expected || count>=460800) $fatal(1,"FAIL 720 writer page%d word%d addr%d expected%d",page,count,addr,expected);
        count=count+1;
    end
    initial begin
        repeat(4) @(negedge clk);rst=0;
        for(pass_number=0;pass_number<2;pass_number=pass_number+1) begin
            @(negedge clk);page=pass_number;count=0;req=1;
            wait(ack);@(negedge clk);req=0;
            wait(finish);@(negedge clk);
            if(count!=460800) $fatal(1,"FAIL incomplete 720 writer %d",count);
            repeat(12) @(negedge clk);
        end
        $display("TB_WRITER720 PASS 2 pages, 921600 exact word addresses, bottom-up mapped");$finish;
    end
    initial begin #20000000;$fatal(1,"FAIL 720 writer timeout");end
endmodule
