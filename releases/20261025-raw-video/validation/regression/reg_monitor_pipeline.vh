wire mon_hs, mon_vs, mon_de;
wire [10:0] mon_x_full;
wire [9:0] mon_y_full;
reg [9:0] mon_x;
reg [8:0] mon_y;
reg mon_de_view_q;
// HDMI-A 采用640x360逻辑画布，2x整数映射铺满1280x720。
// 位切片取坐标，不画侧边黑栏；坐标/ROM/输出三级相位保持。
wire mon_de_view = mon_de;
wire [9:0] mon_x_logical = mon_x_full[10:1];
wire [8:0] mon_y_logical = mon_y_full[9:1];
wire [23:0] mon_menu_rgb;
reg [23:0] mon_rgb;
wire mon_menu_active_v = mon_menu_active_sync[1];
wire mon_menu_page_v   = mon_menu_page_sync[1];
wire [2:0] mon_cursor_v = mon_cursor_sync1;
wire [1:0] mon_period_shadow_v = mon_period_shadow_sync1;
wire [1:0] mon_period_active_v = mon_period_active_sync1;
wire mon_cfg_dirty_v = mon_dirty_sync[1];
wire mon_buzzer_test_v = mon_buzzer_sync[1];
wire mon_sd_init_v = mon_sd_init_sync[1];
wire [2:0] mon_key_state_v = mon_key_state_sync1;
wire [15:0] mon_key_events_v = mon_key_events_sync1;
wire [3:0] mon_img_count_v = mon_img_count_sync1;
wire [3:0] mon_led_state_v = mon_led_state_sync1;
reg mon_hs_d1, mon_de_d1, mon_vs_d1;
reg mon_hs_d2, mon_de_d2, mon_vs_d2;
reg mon_hs_d3, mon_de_d3, mon_vs_d3;

video_timing_gen #(
    .HTOTAL(1650), .HSA(40), .HFP(110), .HBP(220), .HACTIVE(1280),
    .VTOTAL(750), .VSA(5), .VFP(5), .VBP(20), .VACTIVE(720),
    .X_BITS(11), .Y_BITS(10)
) u_mon_timing_gen(
    .I_clk(video_clk), .I_rst(rst_video),
    .O_hs(mon_hs), .O_vs(mon_vs), .O_de(mon_de),
    .O_x(mon_x_full), .O_y(mon_y_full)
);

// 坐标映射与字符选择分拍，保持字库和输出同步信号原有相位。
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) begin mon_x<=0; mon_y<=0; mon_de_view_q<=0; end
    else begin
        mon_x<=mon_x_logical[9:0]; mon_y<=mon_y_logical[8:0]; mon_de_view_q<=mon_de_view;
    end
end

monitor_menu_renderer u_mon_menu_renderer(
    .clk(video_clk), .de(mon_de_view_q), .x(mon_x), .y(mon_y),
    .menu_active(mon_menu_active_v),
    .page(mon_menu_page_v), .cursor(mon_cursor_v),
    .audio_page(mon_audio_page_sync[1]), .audio_edit(mon_audio_edit_sync[1]),
    .audio_shadow(audio_preview_video), .audio_active(audio_active_video),
    .screen_page(mon_screen_page_sync[1]), .screen_edit(mon_screen_edit_sync[1]),
    .screen_shadow(screen_preview_video), .screen_active(screen_active_video),
    .subtitle_page(mon_subtitle_page_sync[1]), .subtitle_edit(mon_subtitle_edit_sync[1]),
    .subtitle_shadow(subtitle_preview_video), .subtitle_active(subtitle_active_video),
    .cfg_busy(mon_cfg_busy_sync[1]),
    .cfg_shadow(cfg_preview_video), .cfg_active(cfg_active_video),
    .period_shadow(mon_period_shadow_v), .period_active(mon_period_active_v),
    .cfg_dirty(mon_cfg_dirty_v), .commit_seen(cfg_commit_seen_video),
    .buzzer_test(mon_buzzer_test_v), .key_state(mon_key_state_v),
    .key_events(mon_key_events_v), .sd_init_done(mon_sd_init_v),
    .img_count(mon_img_count_v), .led_state(mon_led_state_v),
    .rgb(mon_menu_rgb)
);

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        mon_hs_d1 <= 1'b0;
        mon_de_d1 <= 1'b0;
        mon_vs_d1 <= 1'b0;
        mon_hs_d2 <= 1'b0;
        mon_de_d2 <= 1'b0;
        mon_vs_d2 <= 1'b0;
        mon_hs_d3 <= 1'b0;
        mon_de_d3 <= 1'b0;
        mon_vs_d3 <= 1'b0;
        mon_rgb <= 24'd0;
    end else begin
        mon_hs_d1 <= mon_hs;
        mon_de_d1 <= mon_de;
        mon_vs_d1 <= mon_vs;
        mon_hs_d2 <= mon_hs_d1;
        mon_de_d2 <= mon_de_d1;
        mon_vs_d2 <= mon_vs_d1;
        mon_hs_d3 <= mon_hs_d2;
        mon_de_d3 <= mon_de_d2;
        mon_vs_d3 <= mon_vs_d2;
        // 隔离菜单组合绘图和 TMDS 统计/直流平衡链，同步信号同样延迟一拍。
        mon_rgb <= mon_menu_rgb;
    end
end
// 播放按键模式继续显示卡片和操作提示，不再恢复旧参数页。

