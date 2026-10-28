`timescale 1ns/1ps
module tb_afifo_fwft;
    reg wc=0, rc=0, rst=1, we=0, re=0;
    reg [31:0] din=0;
    wire [31:0] dout;
    wire empty, full;
    integer i, round;
    always #5 wc=~wc;
    always #7 rc=~rc;
    afifo_simple #(.DW(32), .AW(3)) dut(
        .wr_clk(wc), .wr_rst(rst), .wr_en(we), .wr_data(din),
        .wr_full(full), .wr_usedw(),
        .rd_clk(rc), .rd_rst(rst), .rd_en(re), .rd_data(dout),
        .rd_empty(empty), .rd_usedw());
    initial begin
        #50; rst=0;
        // 连续消费、带停顿消费、排空后重填，覆盖读写指针绕回。
        for(round=0;round<3;round=round+1) begin
            for(i=0;i<8;i=i+1) begin
                @(negedge wc); we=1; din=32'h12340000+round*8+i;
            end
            @(negedge wc); we=0;
            wait(!empty);
            @(negedge rc); re=1;
            // 消费方在上升沿采样队头，必须在 NBA 更新之前校验。
            for(i=0;i<8;i=i+1) begin
                @(posedge rc);
                if(empty || dout !== 32'h12340000+round*8+i) begin
                    $display("FAIL FWFT round=%0d index=%0d got=%h empty=%b",round,i,dout,empty);
                    $fatal(1);
                end
                @(negedge rc);
                if(round==1) begin
                    re=0;
                    repeat(2) @(negedge rc);
                    re=1;
                end
            end
            re=0;
            if(!empty) $fatal(1,"FAIL FIFO did not drain");
            // 写域需等待读指针同步，不能误将重填当成满写。
            wait(!full);
        end
        $display("TB_AFIFO_FWFT PASS"); $finish;
    end
    initial begin #10000; $fatal(1,"FAIL FIFO timeout"); end
endmodule
