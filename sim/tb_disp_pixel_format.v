`timescale 1ns/1ps
module tb_disp_pixel_format;
    reg clk=0, rst=1, de=0;
    reg transition=0;
    reg [7:0] alpha=0;
    always #5 clk=~clk;
    wire a_rd_en, b_rd_en;
    wire [23:0] rgb;
    wire [31:0] underflow;

    disp_mixer dut(
        .clk(clk), .rst(rst), .de_al(de), .x(10'd0), .y(9'd0),
        .a_rd_en(a_rd_en), .a_rd_data(32'h12_34_56_00), .a_empty(1'b0),
        .b_rd_en(b_rd_en), .b_rd_data(32'hA1_B2_C3_00), .b_empty(1'b0),
        .tr_active(transition), .fade_black(1'b0), .alpha(alpha), .boundary(10'd0), .slide_axis(2'd0),
        .rgb(rgb), .underflow_cnt(underflow));

    initial begin
        #12; rst=0; de=1; #1;
        if (rgb !== 24'h12_34_56 || !a_rd_en || !b_rd_en) begin
            $display("FAIL RGB lane got=%h a_re=%b b_re=%b",rgb,a_rd_en,b_rd_en);
            $fatal(1);
        end
        // B 路转场端点也必须使用高 24 位，不能只修正当前显示页。
        transition=1; alpha=255; #1;
        if (rgb !== 24'hA1_B2_C3 || !a_rd_en || !b_rd_en)
            $fatal(1,"FAIL RGB B lane got=%h",rgb);
        de=0; #1;
        if (rgb !== 24'd0) begin $display("FAIL blanking rgb=%h",rgb); $fatal(1); end
        $display("TB_DISP_PIXEL_FORMAT PASS");
        $finish;
    end
endmodule
