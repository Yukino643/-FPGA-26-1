`timescale 1ns/1ps
// 直接测试顶层原文：首图未提交、异步启动、三次交替页、仲裁停顿。
module tb_top_scaler;
    reg sd_card_clk = 0, ext_mem_clk = 0;
    always #11 sd_card_clk = ~sd_card_clk;
    always #4 ext_mem_clk = ~ext_mem_clk;
    reg rst_sd = 1, rst_mem = 1;
    reg frame_write_finish_pulse = 0;
    reg [15:0] bmp_load_img_w = 640, bmp_load_img_h = 480;
    reg [15:0] cur_img_w = 0, cur_img_h = 0;
    reg [1:0] write_buf_idx = 0, disp_buf_idx = 0;
    wire mpu_C_cv, mpu_C_cr;
    wire [20:0] mpu_C_ca;
    wire [7:0] mpu_C_cl;
    reg mpu_C_rv = 0, mpu_C_rl = 0;
    reg [31:0] mpu_C_rd = 0;
    wire scaler_wr_en, scaler_busy, scaler_done_toggle;
    wire [20:0] scaler_wr_addr;
    wire [31:0] scaler_wr_din;
    wire [3:0] scaler_debug_state;
    reg [3:0] scaler_state_sd = 0;
    reg scaler_busy_sd = 0, scaler_cmd_valid_sd = 0, scaler_cmd_ready_sd = 0, scaler_done_sd = 0;
    wire [7:0] scaler_debug_status = {scaler_state_sd, scaler_busy_sd,
        scaler_cmd_valid_sd, scaler_cmd_ready_sd, scaler_done_sd};
    `include "reg_top_scaler_block.vh"

    integer cycle = 0, remaining = 0, beat = 0;
    integer writes = 0, completions = 0, starts = 0, job = 0;
    reg [20:0] read_addr;
    reg prev_done = 0;
    reg [20:0] expected_base = 0;
    reg [15:0] expected_565;
    reg [31:0] expected_rgb;
    integer px, py;

    // 行为内存按源地址生成横纵渐变，覆盖 x>=512 的 BRAM 地址高位。
    function [15:0] pixel565;
        input integer x, y;
        begin pixel565 = {x[9:5], y[8:3], x[4:0]}; end
    endfunction
    function [31:0] source_word;
        input [20:0] addr;
        integer offset, row, col, words;
        begin
            offset = addr - 21'hC_B000;
            words = (bmp_load_img_w + 1) / 2;
            row = offset / words;
            col = (offset % words) * 2;
            source_word = {pixel565(col+1, row), pixel565(col, row)};
        end
    endfunction
    assign mpu_C_cr = remaining == 0 && cycle % 7 != 0;
    always @(posedge ext_mem_clk) begin
        if (!rst_mem) begin
            cycle = cycle + 1;
            mpu_C_rv <= 0;
            mpu_C_rl <= 0;
            if (mpu_C_cv && mpu_C_cr) begin
                if (mpu_C_cl == 0 || mpu_C_cl > 128) begin
                    $display("FAIL zero/invalid read length job=%0d len=%0d", job, mpu_C_cl);
                    $finish;
                end
                if (mpu_C_ca < 21'hC_B000 ||
                    mpu_C_ca + mpu_C_cl > 21'hC_B000 + ((bmp_load_img_w+1)/2)*bmp_load_img_h) begin
                    $display("FAIL source read out of bounds"); $finish;
                end
                read_addr = mpu_C_ca;
                remaining = mpu_C_cl;
                beat = 0;
            end else if (remaining > 0 && cycle % 5 != 0) begin
                mpu_C_rv <= 1;
                mpu_C_rd <= source_word(read_addr + beat);
                mpu_C_rl <= remaining == 1;
                remaining = remaining - 1;
                beat = beat + 1;
            end
            if (u_scaler.st_pulse) begin
                starts = starts + 1;
                if (starts != job) begin
                    $display("FAIL duplicate start event starts=%0d job=%0d", starts, job); $finish;
                end
            end
            if (scaler_wr_en) begin
                if (scaler_wr_addr !== expected_base + writes || writes >= 640*480) begin
                    $display("FAIL target address job=%0d count=%0d addr=%h expected=%h",
                        job, writes, scaler_wr_addr, expected_base + writes); $finish;
                end
                if (bmp_load_img_w == 640 && bmp_load_img_h == 480) begin
                    px = writes % 640; py = 479 - writes / 640;
                    expected_565 = pixel565(px, py);
                    expected_rgb = {{expected_565[15:11],expected_565[15:13]},
                        {expected_565[10:5],expected_565[10:9]},
                        {expected_565[4:0],expected_565[4:2]},8'd0};
                    if (scaler_wr_din !== expected_rgb) begin
                        $display("FAIL identity pixel x=%0d y=%0d got=%h expected=%h",
                            px, py, scaler_wr_din, expected_rgb); $finish;
                    end
                end
                writes = writes + 1;
            end
            if (scaler_done_toggle != prev_done) begin
                completions = completions + 1;
                if (writes != 640*480 || completions != job) begin
                    $display("FAIL premature/duplicate completion writes=%0d", writes); $finish;
                end
            end
            prev_done = scaler_done_toggle;
        end
    end
    task run_job;
        input integer width, height, page;
        begin
            @(negedge sd_card_clk);
            job = job + 1; writes = 0;
            bmp_load_img_w = width; bmp_load_img_h = height;
            write_buf_idx = page;
            expected_base = page == 0 ? 21'h0_0000 : 21'h8_0000;
            // 模拟 BMP 头先锁存，像素写完后才翻转启动事件。
            repeat (10) @(negedge sd_card_clk);
            frame_write_finish_pulse = 1;
            @(negedge sd_card_clk); frame_write_finish_pulse = 0;
            wait(scaler_busy);
            @(negedge ext_mem_clk);
            if (u_scaler.src_w != width || u_scaler.src_h != height) begin
                $display("FAIL stale dimensions"); $finish;
            end
            wait(completions == job);
            repeat (30) @(negedge ext_mem_clk);
            if (scaler_busy || starts != job || completions != job) begin
                $display("FAIL scaler not idle after completion"); $finish;
            end
            cur_img_w = width; cur_img_h = height; disp_buf_idx = page;
            $display("JOB %0d complete, %0dx%0d page=%0d writes=%0d",job,width,height,page,writes);
        end
    endtask
    initial begin
        #103; rst_sd = 0; rst_mem = 0;
        run_job(640,480,0);
        run_job(320,240,1);
        run_job(640,480,0);
        $display("TB_TOP_SCALER PASS"); $finish;
    end
    initial begin
        #200_000_000;
        $display("FAIL timeout job=%0d state=%0d",job,u_scaler.state); $finish;
    end
endmodule
