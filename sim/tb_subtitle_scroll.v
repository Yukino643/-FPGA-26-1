// tb_subtitle_scroll.v — subtitle_scroll 单元仿真
`timescale 1ns/1ps
module tb_subtitle_scroll;

    reg clk = 0, rst = 1;
    always #20 clk = ~clk;

    reg         de_in = 0;
    reg  [9:0]  x = 0;
    reg  [8:0]  y = 0;
    reg  [23:0] bg_rgb = 24'h000000;
    reg         vs_pulse = 0;
    reg         enable = 1;
    wire [23:0] rgb_out;

    subtitle_scroll u_dut(
        .clk(clk), .de_in(de_in),
        .x(x), .y(y), .bg_rgb(bg_rgb),
        .vs_pulse(vs_pulse), .enable(enable),
        .rgb_out(rgb_out)
    );

    integer errors = 0;

    initial begin
        rst = 1;
        #100;
        @(posedge clk); rst = 0;
        #100;

        // Test 1: 字幕带外直通
        $display("TEST1: outside band passthrough");
        enable = 1;
        @(posedge clk); de_in <= 1; x <= 100; y <= 100;
        @(posedge clk);
        if (rgb_out === 24'h000000) $display("TEST1 PASS");
        else begin $display("TEST1 FAIL: got=%h", rgb_out); errors = errors + 1; end

        // Test 2: 字幕带内有内容
        $display("TEST2: inside band has content");
        @(posedge clk); x <= 10; y <= 9'd430;  // 字幕带内
        @(posedge clk);
        if (rgb_out !== 24'h000000) $display("TEST2 PASS: got=%h", rgb_out);
        else begin $display("TEST2 FAIL: no content"); errors = errors + 1; end

        // Test 3: 禁用时直通
        $display("TEST3: disabled passthrough");
        enable = 0;
        @(posedge clk);
        if (rgb_out === 24'h000000) $display("TEST3 PASS");
        else begin $display("TEST3 FAIL: got=%h", rgb_out); errors = errors + 1; end

        if (errors == 0) $display("TB_SUBTITLE_SCROLL PASS");
        else $display("TB_SUBTITLE_SCROLL FAIL errors=%0d", errors);
        $finish;
    end

endmodule
