reg de_d1, vs_d1;
reg de_d2, de_d3, vs_d2, vs_d3;
reg [9:0] x_d1, x_d2, x_d3;
reg [8:0] y_d1, y_d2, y_d3;
// 波形模块的同步查表已经包含一拍，直接交给下一拍字库层。
wire [23:0] waveform_q = vout_waveform;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        de_d1 <= 0; de_d2 <= 0; de_d3 <= 0;
        vs_d1 <= 0; vs_d2 <= 0; vs_d3 <= 0;
        x_d1 <= 0; x_d2 <= 0; x_d3 <= 0;
        y_d1 <= 0; y_d2 <= 0; y_d3 <= 0;
    end else begin
        // 颜色调整、波形、字库各一拍；RGB、坐标和 DE 必须同拍推进。
        de_d1 <= main_de_al; de_d2 <= de_d1; de_d3 <= de_d2;
        vs_d1 <= vs; vs_d2 <= vs_d1; vs_d3 <= vs_d2;
        x_d1 <= main_x; x_d2 <= x_d1; x_d3 <= x_d2;
        y_d1 <= main_y; y_d2 <= y_d1; y_d3 <= y_d2;
    end
end


osd_engine u_osd(
    .I_clk        (video_clk),
    .I_x          (x_d2),
    .I_y          (y_d2),
    .I_bg_rgb     (waveform_q),
    .I_uptime_bcd ({clk_hh, clk_mm, clk_ss}),
    .I_mode       (mode_v1),
    .O_rgb        (vout_osd)
);
promax_audio_waveform #(
    .WAVE_X      (64), .WAVE_Y(376), .WAVE_WIDTH(512), .WAVE_HEIGHT(72), .DECIMATE(120)
) u_promax_audio_waveform(
    .clk           (video_clk),
    .rst           (rst_video),
    .vs_pulse      (vs_rise_v),
    .de            (de_d1),
    .pixel_x       (x_d1),
    .pixel_y       (y_d1),
    .rgb_in        (vout_color),
    .enable        (1'b1),
    .pcm_tap_valid (waveform_pcm_valid),
    .pcm_tap_left  (audio_left_final[23:8]),
    .rgb_out       (vout_waveform),
    .waveform_active()
);
color_adjust u_color_adjust(
    .clk        (video_clk),
    .rst        (rst_video),
    .de_in      (main_de_al),
    .rgb_in     (vout_data),
    .contrast   (sw[1] ? 8'd192 : 8'd128),   // SW2: 对比度增强
    .brightness (sw[2] ? 8'sd30 : 8'sd0),    // SW3: 亮度提升
    .color_temp (sw[3] ? 8'sd20 : 8'sd0),    // SW4: 色温偏暖
    .de_out     (),
    .rgb_out    (vout_color)
);
emergency_render u_emergency_render(
    .clk            (video_clk),
    .de_in          (de_d3),
    .x              (x_d3),
    .y              (y_d3),
    .emergency_mode (emergency_mode),
    .normal_rgb     (vout_osd),
    .rgb_out        (vout_final)
);
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
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