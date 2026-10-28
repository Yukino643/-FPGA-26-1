// tb_color_adjust.v — color_adjust 单元仿真
// 验证: 亮度/对比度/色温公式、clamp、流水延迟
`timescale 1ns/1ps
module tb_color_adjust;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg         de_in = 0;
    reg  [23:0] rgb_in = 0;
    reg  [7:0]  contrast = 128;
    reg  signed [7:0] brightness = 0;
    reg  signed [7:0] color_temp = 0;
    wire        de_out;
    wire [23:0] rgb_out;

    color_adjust u_dut(
        .clk(clk), .rst(rst),
        .de_in(de_in), .rgb_in(rgb_in),
        .contrast(contrast), .brightness(brightness), .color_temp(color_temp),
        .de_out(de_out), .rgb_out(rgb_out)
    );

    integer errors = 0;

    task check;
        input [23:0] in_rgb;
        input [7:0] c;
        input signed [7:0] b, t;
        input [23:0] exp_rgb;
        begin
            @(posedge clk); de_in <= 1; rgb_in <= in_rgb;
            contrast <= c; brightness <= b; color_temp <= t;
            @(posedge clk); de_in <= 0;
            @(posedge clk);
            if (rgb_out !== exp_rgb) begin
                $display("FAIL: in=%h c=%0d b=%0d t=%0d got=%h exp=%h",
                    in_rgb, c, b, t, rgb_out, exp_rgb);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst = 1;
        #100;
        @(posedge clk); rst = 0;
        #100;

        // Test 1: 直通（contrast=128 → 1.0x, brightness=0, color_temp=0）
        $display("TEST1: passthrough");
        check(24'h808080, 128, 0, 0, 24'h808080);
        check(24'hFF0000, 128, 0, 0, 24'hFF0000);
        check(24'h00FF00, 128, 0, 0, 24'h00FF00);
        if (errors == 0) $display("TEST1 PASS");

        // Test 2: 亮度 +50
        $display("TEST2: brightness +50");
        check(24'h808080, 128, 50, 0, 24'hB2B2B2);  // 128+50=178=0xB2
        if (errors == 0) $display("TEST2 PASS");

        // Test 3: 对比度 255（~2x）
        $display("TEST3: contrast 2x");
        check(24'h808080, 255, 0, 0, 24'h808080);
        check(24'hFFFFFF, 255, 0, 0, 24'hFFFFFF);
        if (errors == 0) $display("TEST3 PASS");

        // Test 4: 色温 +30（R+30, B-30）
        $display("TEST4: color_temp +30");
        // R: 128+30=158, G:128, B:128-30=98
        check(24'h808080, 128, 0, 30, 24'h9E8062);
        if (errors == 0) $display("TEST4 PASS");

        // Test 5: clamp 边界
        $display("TEST5: clamp");
        // (0-128)*128>>7 + 128 + 127 = -128+128+127 = 127
        check(24'h000000, 128, 127, 0, 24'h7F7F7F);
        // (255-128)*128>>7 + 128 + (-128) = 127+128-128 = 127
        check(24'hFFFFFF, 128, -128, 0, 24'h7F7F7F);
        // 真正的 clamp: contrast=255, brightness=+127
        // (0-128)*255>>7 + 128 + 127 = -255+128+127 = 0
        check(24'h000000, 255, 127, 0, 24'h000000);
        // (255-128)*255>>7 + 128 + 127 = 253+128+127 = 508 → clamp 255
        check(24'hFFFFFF, 255, 127, 0, 24'hFFFFFF);
        if (errors == 0) $display("TEST5 PASS");

        if (errors == 0) $display("TB_COLOR_ADJUST PASS");
        else $display("TB_COLOR_ADJUST FAIL errors=%0d", errors);
        $finish;
    end

endmodule
