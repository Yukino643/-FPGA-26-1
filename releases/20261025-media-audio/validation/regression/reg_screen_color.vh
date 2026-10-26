// HDMI-B 专用参数；不作用于 HDMI-A 菜单。
wire [7:0] screen_contrast_video = 8'd64 + {screen_active_video[7:4], 4'b0000};
wire signed [7:0] screen_brightness_video = {screen_active_video[3:0], 4'b0000} - 8'd64;
wire signed [7:0] screen_temp_video = (screen_active_video[9:8] == 0) ? -8'sd20 :
                                    (screen_active_video[9:8] == 2) ? 8'sd20 : 8'sd0;

monitor_config_regs u_monitor_config_regs(
    .video_clk              (video_clk),
    .video_rst              (rst_video),
    .vs_rise                (vs_rise_v),
    .cfg_shadow_sd          (cfg_shadow_sd),
    .cfg_payload_sd         (cfg_payload_sd),
    .screen_shadow_sd       (screen_shadow_sd),
    .screen_payload_sd      (screen_payload_sd),
    .audio_shadow_sd        (audio_shadow_sd),
    .audio_payload_sd       (audio_payload_sd),
    .audio_active_video     (audio_active_video),
    .audio_preview_video    (audio_preview_video),
    .subtitle_shadow_sd     (subtitle_shadow_sd),
    .subtitle_payload_sd    (subtitle_payload_sd),
    .cfg_commit_toggle_sd   (cfg_commit_toggle_sd),
    .cfg_active_video       (cfg_active_video),
    .cfg_preview_video      (cfg_preview_video),
    .screen_active_video    (screen_active_video),
    .screen_preview_video   (screen_preview_video),
    .subtitle_active_video  (subtitle_active_video),
    .subtitle_preview_video (subtitle_preview_video),
    .cfg_commit_seen_video  (cfg_commit_seen_video),
    .cfg_applied_toggle_video(cfg_applied_toggle_video)
);
color_adjust u_color_adjust(
    .clk        (video_clk),
    .rst        (rst_video),
    .de_in      (mix_de),
    .rgb_in     ((cfg_image_enable !== 1'b0) ? vout_data : 24'h07131D),
    .contrast   (screen_contrast_video),
    .brightness (screen_brightness_video),
    .color_temp (screen_temp_video),
    .de_out     (),
    .rgb_out    (vout_color)
);