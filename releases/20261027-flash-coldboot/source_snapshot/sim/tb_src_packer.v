// tb_src_packer.v — src_packer 单元仿真
// 验证: RGB888→RGB565 转换、2 像素/字打包、奇数像素排空
`timescale 1ns/1ps
module tb_src_packer;

    reg clk = 0, rst = 1;
    always #4 clk = ~clk;

    reg         px_valid = 0;
    reg  [23:0] px_rgb = 0;
    reg         load_done = 0;
    reg         frame_restart = 0;
    reg  [15:0] row_width = 16'd4;
    wire        out_valid;
    wire [31:0] out_data;

    src_packer u_packer(
        .clk(clk), .rst(rst), .frame_restart(frame_restart),
        .px_valid(px_valid), .px_rgb(px_rgb),
        .row_width(row_width),
        .load_done(load_done),
        .out_valid(out_valid), .out_data(out_data)
    );

    // RGB888 → RGB565 参考
    function [15:0] ref_565;
        input [23:0] rgb;
        begin
            ref_565 = {rgb[23:19], rgb[15:10], rgb[7:3]};
        end
    endfunction

    integer errors = 0;
    integer out_count = 0;
    reg [31:0] captured [0:15];

    always @(posedge clk) begin
        if (out_valid) begin
            captured[out_count] = out_data;
            out_count = out_count + 1;
        end
    end

    task send_px;
        input [23:0] rgb;
        begin
            @(posedge clk); px_valid <= 1; px_rgb <= rgb;
            @(posedge clk); px_valid <= 0;
        end
    endtask

    initial begin
        rst = 1;
        #100;
        @(posedge clk); rst = 0;
        #100;

        // Test 1: 4 个像素 → 2 个字
        $display("TEST1: 4 pixels → 2 words");
        out_count = 0;
        send_px(24'hFF0000);  // 红
        send_px(24'h00FF00);  // 绿
        send_px(24'h0000FF);  // 蓝
        send_px(24'hFFFFFF);  // 白
        #200;

        if (out_count != 2) begin
            $display("FAIL: expected 2 words, got %0d", out_count);
            errors = errors + 1;
        end else begin
            // word0 = {green_565, red_565}
            if (captured[0] !== {ref_565(24'h00FF00), ref_565(24'hFF0000)}) begin
                $display("FAIL word0: got %h exp %h", captured[0], {ref_565(24'h00FF00), ref_565(24'hFF0000)});
                errors = errors + 1;
            end
            // word1 = {white_565, blue_565}
            if (captured[1] !== {ref_565(24'hFFFFFF), ref_565(24'h0000FF)}) begin
                $display("FAIL word1: got %h exp %h", captured[1], {ref_565(24'hFFFFFF), ref_565(24'h0000FF)});
                errors = errors + 1;
            end
            if (errors == 0) $display("TEST1 PASS");
        end

        // Test 2: 3 个像素 + load_done 排空
        $display("TEST2: 3 pixels + load_done flush");
        out_count = 0;
        send_px(24'h112233);
        send_px(24'h445566);
        send_px(24'h778899);
        #100;
        @(posedge clk); load_done <= 1;
        @(posedge clk); load_done <= 0;
        #200;

        if (out_count != 2) begin
            $display("FAIL: expected 2 words, got %0d", out_count);
            errors = errors + 1;
        end else begin
            if (captured[0] !== {ref_565(24'h445566), ref_565(24'h112233)}) begin
                $display("FAIL word0: got %h exp %h", captured[0], {ref_565(24'h445566), ref_565(24'h112233)});
                errors = errors + 1;
            end
            // 排空: {16'd0, ref_565(24'h778899)}
            if (captured[1] !== {16'd0, ref_565(24'h778899)}) begin
                $display("FAIL flush: got %h exp %h", captured[1], {16'd0, ref_565(24'h778899)});
                errors = errors + 1;
            end
            if (errors == 0) $display("TEST2 PASS");
        end

        // Test 3: 奇数宽的两行必须各自补齐，禁止跨行配对。
        $display("TEST3: odd row width padding");
        row_width = 16'd3;
        out_count = 0;
        send_px(24'h010203);
        send_px(24'h040506);
        send_px(24'h070809);
        send_px(24'h0A0B0C);
        send_px(24'h0D0E0F);
        send_px(24'h101112);
        #100;
        if (out_count != 4 ||
            captured[0] !== {ref_565(24'h040506), ref_565(24'h010203)} ||
            captured[1] !== {16'd0, ref_565(24'h070809)} ||
            captured[2] !== {ref_565(24'h0D0E0F), ref_565(24'h0A0B0C)} ||
            captured[3] !== {16'd0, ref_565(24'h101112)}) begin
            $display("FAIL odd row padding count=%0d words=%h %h %h %h", out_count,
                     captured[0], captured[1], captured[2], captured[3]);
            errors = errors + 1;
        end else begin
            $display("TEST3 PASS");
        end

        // Test 4: 唯一像素与 load_done 同拍，必须直接形成半字并清空状态。
        $display("TEST4: last pixel and load_done in same cycle");
        row_width = 16'd1;
        out_count = 0;
        @(posedge clk);
        px_valid <= 1'b1;
        px_rgb <= 24'hABCDEF;
        load_done <= 1'b1;
        @(posedge clk);
        px_valid <= 1'b0;
        load_done <= 1'b0;
        #100;
        if (out_count != 1 || captured[0] !== {16'd0, ref_565(24'hABCDEF)}) begin
            $display("FAIL same-cycle flush: count=%0d got=%h", out_count, captured[0]);
            errors = errors + 1;
        end else begin
            $display("TEST4 PASS");
        end

        // Test 5: 偶数宽多行，行间存在气泡时仍按行独立配对。
        $display("TEST5: even multi-row with inter-row gap");
        row_width = 16'd4;
        out_count = 0;
        send_px(24'h201000);
        send_px(24'h402000);
        send_px(24'h603000);
        send_px(24'h804000);
        repeat (5) @(posedge clk);
        send_px(24'hA05000);
        send_px(24'hC06000);
        send_px(24'hE07000);
        send_px(24'hF08000);
        #100;
        if (out_count != 4 ||
            captured[0] !== {ref_565(24'h402000), ref_565(24'h201000)} ||
            captured[1] !== {ref_565(24'h804000), ref_565(24'h603000)} ||
            captured[2] !== {ref_565(24'hC06000), ref_565(24'hA05000)} ||
            captured[3] !== {ref_565(24'hF08000), ref_565(24'hE07000)}) begin
            $display("FAIL even multi-row count=%0d words=%h %h %h %h", out_count,
                     captured[0], captured[1], captured[2], captured[3]);
            errors = errors + 1;
        end else begin
            $display("TEST5 PASS");
        end

        // 失败留下半像素时，新事务不能与其配对。
        row_width = 4; out_count = 0;
        send_px(24'hff0000);
        @(negedge clk); frame_restart = 1;
        @(negedge clk); frame_restart = 0;
        send_px(24'h00ff00); send_px(24'h0000ff);
        send_px(24'hffffff); send_px(24'h000000);
        #100;
        if (out_count != 2 || captured[0] !== {ref_565(24'h0000ff), ref_565(24'h00ff00)} ||
            captured[1] !== {ref_565(24'h000000), ref_565(24'hffffff)}) begin
            $display("FAIL retry stale half pixel"); errors = errors+1;
        end
        if (errors == 0) $display("TB_SRC_PACKER PASS");
        else $display("TB_SRC_PACKER FAIL errors=%0d", errors);
        $finish;
    end

endmodule
