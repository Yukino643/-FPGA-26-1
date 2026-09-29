#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""W5 顶层集成补丁 part2: 显示读出路径重构"""
p = r'D:\FPGA\code\example\rtl\top\top_tf_hdmi_audio.v'
s = open(p, encoding='utf-8').read()

old = '''// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
assign vout_data = display_valid ? vout_data_raw : 24'd0;

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);'''

new = '''// ===================== W5 显示读出路径重构 =====================
// 官方整帧 FIFO 流读出 → mem_mpu 多主仲裁 + 双行预取引擎 + 双异步 FIFO + 转场混合器
// 装载写路径保持官方 frame_read_write（其读端口闲置: read_req 恒 0）
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

reg vs_d_v;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) vs_d_v <= 1'b0;
    else         vs_d_v <= vs;
end
wire vs_rise_v = vs & ~vs_d_v;

// ---- 转场控制（video 域） ----
wire        tr_active, tr_hold_load;
wire [7:0]  tr_alpha;
wire [9:0]  tr_boundary;
wire [1:0]  tr_slide_axis;
wire [20:0] page_a_base, page_b_base;

transition_ctrl #(
    .PAGE0_BASE (21'h0_0000),
    .PAGE1_BASE (21'h8_0000),
    .ALPHA_STEP (8'd8)
) u_transition(
    .clk           (video_clk),
    .rst           (rst_all),
    .vs_rise       (vs_rise_v),
    .x             (main_x),
    .y             (main_y),
    .commit_toggle (commit_toggle_v),
    .commit_buf    (commit_buf_v),
    .tr_mode       (2'd1),            // W9: KEY3 循环切换
    .tr_active     (tr_active),
    .alpha         (tr_alpha),
    .boundary      (tr_boundary),
    .slide_axis    (tr_slide_axis),
    .page_a_base   (page_a_base),
    .page_b_base   (page_b_base),
    .page_upd_a    (),
    .page_upd_b    (),
    .hold_load     (tr_hold_load)
);

// ---- mem_mpu: 读口双请求方 + 写口直通 ----
wire        mpu_A_cv, mpu_A_cr, mpu_A_rv, mpu_A_rl;
wire [20:0] mpu_A_ca;
wire [31:0] mpu_A_rd;
wire [7:0]  mpu_A_cl;
wire        mpu_B_cv, mpu_B_cr, mpu_B_rv, mpu_B_rl;
wire [20:0] mpu_B_ca;
wire [31:0] mpu_B_rd;
wire [7:0]  mpu_B_cl;
wire        sdram_wr_en;
wire [20:0] sdram_wr_addr;
wire [31:0] sdram_wr_din;
wire [3:0]  sdram_wr_dm;

mem_mpu #(.MAX_A_RUN(2)) u_mem_mpu(
    .clk            (ext_mem_clk),
    .rst            (rst_all),
    .A_cmd_valid    (mpu_A_cv), .A_cmd_addr(mpu_A_ca), .A_cmd_len(mpu_A_cl),
    .A_cmd_ready    (mpu_A_cr), .A_rsp_valid(mpu_A_rv), .A_rsp_data(mpu_A_rd), .A_rsp_last(mpu_A_rl),
    .B_cmd_valid    (mpu_B_cv), .B_cmd_addr(mpu_B_ca), .B_cmd_len(mpu_B_cl),
    .B_cmd_ready    (mpu_B_cr), .B_rsp_valid(mpu_B_rv), .B_rsp_data(mpu_B_rd), .B_rsp_last(mpu_B_rl),
    .App_rd_en      (App_rd_en),
    .App_rd_addr    (App_rd_addr),
    .Sdr_rd_en      (Sdr_rd_en),
    .Sdr_rd_dout    (Sdr_rd_dout),
    .App_wr_en_u    (App_wr_en),
    .App_wr_addr_u  (App_wr_addr),
    .App_wr_din_u   (App_wr_din),
    .App_wr_dm_u    (App_wr_dm),
    .App_wr_en      (sdram_wr_en),
    .App_wr_addr    (sdram_wr_addr),
    .App_wr_din     (sdram_wr_din),
    .App_wr_dm      (sdram_wr_dm)
);

// ---- 双行预取引擎 + 双异步 FIFO ----
wire        fa_we, fb_we;
wire [31:0] fa_wd, fb_wd;
wire [10:0] fa_wu, fb_wu;
wire        fa_re, fb_re;
wire [31:0] fa_dd, fb_dd;
wire        fa_e, fb_e;
wire [10:0] fa_ru, fb_ru;

disp_read_engine u_eng_a(
    .clk         (ext_mem_clk),
    .rst         (rst_all),
    .vs_toggle   (vs_toggle_r),
    .page_base   (page_a_base),
    .fifo_we     (fa_we),
    .fifo_wdata  (fa_wd),
    .fifo_wusedw (fa_wu),
    .cmd_valid   (mpu_A_cv),
    .cmd_addr    (mpu_A_ca),
    .cmd_len     (mpu_A_cl),
    .cmd_ready   (mpu_A_cr),
    .rsp_valid   (mpu_A_rv),
    .rsp_data    (mpu_A_rd),
    .rsp_last    (mpu_A_rl)
);
disp_read_engine u_eng_b(
    .clk         (ext_mem_clk),
    .rst         (rst_all),
    .vs_toggle   (vs_toggle_r),
    .page_base   (page_b_base),
    .fifo_we     (fb_we),
    .fifo_wdata  (fb_wd),
    .fifo_wusedw (fb_wu),
    .cmd_valid   (mpu_B_cv),
    .cmd_addr    (mpu_B_ca),
    .cmd_len     (mpu_B_cl),
    .cmd_ready   (mpu_B_cr),
    .rsp_valid   (mpu_B_rv),
    .rsp_data    (mpu_B_rd),
    .rsp_last    (mpu_B_rl)
);

afifo_simple #(.DW(32), .AW(10)) u_fifo_a(
    .wr_clk(ext_mem_clk), .wr_rst(rst_all), .wr_en(fa_we), .wr_data(fa_wd),
    .wr_full(), .wr_usedw(fa_wu),
    .rd_clk(video_clk), .rd_rst(rst_all), .rd_en(fa_re), .rd_data(fa_dd),
    .rd_empty(fa_e), .rd_usedw(fa_ru)
);
afifo_simple #(.DW(32), .AW(10)) u_fifo_b(
    .wr_clk(ext_mem_clk), .wr_rst(rst_all), .wr_en(fb_we), .wr_data(fb_wd),
    .wr_full(), .wr_usedw(fb_wu),
    .rd_clk(video_clk), .rd_rst(rst_all), .rd_en(fb_re), .rd_data(fb_dd),
    .rd_empty(fb_e), .rd_usedw(fb_ru)
);

// ---- 双流混合器（下溢计数供监视台 W10） ----
wire [23:0] mix_rgb;
wire [31:0] disp_underflow;

disp_mixer u_disp_mixer(
    .clk        (video_clk),
    .rst        (rst_all),
    .de_al      (main_de_al),
    .x          (main_x),
    .y          (main_y),
    .a_rd_en    (fa_re),
    .a_rd_data  (fa_dd),
    .a_empty    (fa_e),
    .b_rd_en    (fb_re),
    .b_rd_data  (fb_dd),
    .b_empty    (fb_e),
    .tr_active  (tr_active),
    .alpha      (tr_alpha),
    .boundary   (tr_boundary),
    .slide_axis (tr_slide_axis),
    .rgb        (mix_rgb),
    .underflow_cnt (disp_underflow)
);

// 首图提交前黑屏；提交后显示转场混合器输出
assign vout_data = display_valid ? mix_rgb : 24'd0;

// ---- 官方装载写路径保留（读端口闲置） ----
wire video_read_en_unused;
wire [31:0] video_read_data_unused;
wire video_read_req = 1'b0;

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (),
    .App_rd_addr       (),
    .Sdr_rd_en         (1'b0),
    .Sdr_rd_dout       (32'd0),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en_unused),
    .read_data         (video_read_data_unused),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (sdram_wr_en),
    .App_wr_addr       (sdram_wr_addr),
    .App_wr_dm         (sdram_wr_dm),
    .App_wr_din        (sdram_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);'''

assert old in s, 'display path pattern not found'
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('top part2 done')
