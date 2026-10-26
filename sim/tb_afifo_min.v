`timescale 1ns/1ps
module tb_afifo_min;
    reg wclk=0, rclk=0, rst=1;
    always #4 wclk=~wclk;
    always #8 rclk=~rclk;
    reg we=0; reg [31:0] di=0;
    wire full; wire [9:0] wu;
    reg re=0; wire [31:0] dout; wire empty; wire [9:0] ru;
    afifo_simple #(.DW(32), .AW(9)) u(.wr_clk(wclk), .wr_rst(rst), .wr_en(we), .wr_data(di),
        .wr_full(full), .wr_usedw(wu), .rd_clk(rclk), .rd_rst(rst), .rd_en(re),
        .rd_data(dout), .rd_empty(empty), .rd_usedw(ru));
    integer i;
    initial begin
        rst=1; #50; @(posedge wclk); rst=0;
        for (i=0;i<4;i=i+1) begin @(posedge wclk); we=1; di=i*100+7; end
        @(posedge wclk); we=0;
        #200;
        $display("wu=%0d empty=%b u.rd_data=%h rd_int=%h dob=%h mem0..3=%h %h %h %h rbin=%0d wbin=%0d",
                 wu, empty, u.rd_data, u.rd_data_int, u.dob, u.mem[0], u.mem[1], u.mem[2], u.mem[3], u.rbin, u.wbin);
        for (i=0;i<4;i=i+1) begin
            @(posedge rclk); re=1;
            #1 $display("pop%0d: dout=%h empty=%b", i, dout, empty);
        end
        @(posedge rclk); re=0;
        #100 $finish;
    end
endmodule
