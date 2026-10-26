reg de_d1, vs_d1;
reg de_d2, de_d3, vs_d2, vs_d3;
reg [10:0] x_d1, x_d2, x_d3;
reg [9:0] y_d1, y_d2, y_d3;
// 波形模块的同步查表已经包含一拍，直接交给下一拍字库层。
wire [23:0] waveform_q = vout_waveform;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        de_d1 <= 0; de_d2 <= 0; de_d3 <= 0;
        vs_d1 <= 0; vs_d2 <= 0; vs_d3 <= 0;
        x_d1 <= 0; x_d2 <= 0; x_d3 <= 0;
        y_d1 <= 0; y_d2 <= 0; y_d3 <= 0;
    end else begin
        // 两拍混合器之后：颜色、波形、字库各一拍；RGB/坐标/DE同拍推进。
        de_d1 <= mix_de; de_d2 <= de_d1; de_d3 <= de_d2;
        vs_d1 <= mix_vs; vs_d2 <= vs_d1; vs_d3 <= vs_d2;
        x_d1 <= mix_x; x_d2 <= x_d1; x_d3 <= x_d2;
        y_d1 <= mix_y; y_d2 <= y_d1; y_d3 <= y_d2;
    end
end


osd_engine_720 u_osd(
    .I_clk        (video_clk),
    .I_rst        (rst_video),
    .I_vs_pulse   (vs_rise_v),
    .I_subtitle_cfg(subtitle_active_video),
    .I_x          (x_d2),
    .I_y          (y_d2),
    .I_bg_rgb     (waveform_q),
    .I_uptime_bcd ({clk_hh, clk_mm, clk_ss}),
    .I_mode       (mode_v1),
    .I_clock_enable(cfg_clock_enable),
    .I_text_enable (cfg_text_enable),
    .O_rgb        (vout_osd)
);
promax_audio_waveform #(
    .WAVE_X(128),.WAVE_Y(576),.WAVE_WIDTH(1024),.WAVE_HEIGHT(88),.DECIMATE(120),
    .VIDEO_WIDTH(1280),.VIDEO_HEIGHT(720),.X_BITS(11),.Y_BITS(10),.PIPELINED_GEOMETRY(1)
) u_promax_audio_waveform(
    .clk           (video_clk),
    .rst           (rst_video),
    .vs_pulse      (vs_rise_v),
    .de            (de_d1),
    .pixel_x       (x_d1),
    .pixel_y       (y_d1),
    .rgb_in        (vout_color),
    .enable        (cfg_wave_enable !== 1'b0),
    .pcm_tap_valid (waveform_pcm_valid),
    .pcm_tap_left  (audio_left_final[23:8]),
    .rgb_out       (vout_waveform),
    .waveform_active()
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
emergency_render #(.X_BITS(11),.Y_BITS(10)) u_emergency_render(
    .clk            (video_clk),
    .de_in          (de_d3),
    .x              (x_d3),
    .y              (y_d3),
    .emergency_mode (emergency_mode),
    .normal_rgb     (vout_osd),
    .rgb_out        (vout_final)
);
video_rgb_to_axis_640x480 #(.ACTIVE_WIDTH(1280)) u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (vs_d3),
    .I_de          (de_d3),
    .I_rgb         (vout_final),      // W8: 色彩调节后输出
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);