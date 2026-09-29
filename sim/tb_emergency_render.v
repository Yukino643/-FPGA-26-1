// tb_emergency_render.v — emergency_render 单元仿真
`timescale 1ns/1ps
module tb_emergency_render;

    reg clk = 0, rst = 1;
    always #20 clk = ~clk;  // 25MHz

    reg         de_in = 0;
    reg  [9:0]  x = 0;
    reg  [8:0]  y = 0;
    reg         emergency_mode = 0;
    reg  [23:0] normal_rgb = 24'h123456;
    wire [23:0] rgb_out;

    emergency_render u_dut(
        .clk(clk), .de_in(de_in),
        .x(x), .y(y),
        .emergency_mode(emergency_mode),
        .normal_rgb(normal_rgb),
        .rgb_out(rgb_out)
    );

    integer errors = 0;

    initial begin
        rst = 1;
        #100;
        @(posedge clk); rst = 0;
        #100;

        // Test 1: 正常模式直通
        $display("TEST1: normal mode passthrough");
        emergency_mode = 0;
        @(posedge clk); de_in <= 1; x <= 100; y <= 100;
        @(posedge clk);
        if (rgb_out === 24'h123456) $display("TEST1 PASS");
        else begin $display("TEST1 FAIL: got=%h", rgb_out); errors = errors + 1; end

        // Test 2: 应急模式 - 标题区
        $display("TEST2: emergency title area");
        emergency_mode = 1;
        @(posedge clk); x <= 320; y <= 200;  // 标题区 y∈[180,219]
        @(posedge clk);
        if (rgb_out === 24'hFFFFFF) $display("TEST2 PASS");  // 白色标题
        else begin $display("TEST2 FAIL: got=%h", rgb_out); errors = errors + 1; end

        // Test 3: 应急模式 - 背景
        $display("TEST3: emergency background");
        @(posedge clk); x <= 100; y <= 100;  // 非标题非告警区
        @(posedge clk);
        if (rgb_out === 24'hC00000) $display("TEST3 PASS");  // 红底
        else begin $display("TEST3 FAIL: got=%h", rgb_out); errors = errors + 1; end

        if (errors == 0) $display("TB_EMERGENCY_RENDER PASS");
        else $display("TB_EMERGENCY_RENDER FAIL errors=%0d", errors);
        $finish;
    end

endmodule
