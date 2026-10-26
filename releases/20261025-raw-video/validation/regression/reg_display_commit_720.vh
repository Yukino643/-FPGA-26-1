reg [2:0] commit_sync;
reg [1:0] commit_buf_sync1, commit_buf_sync2;
reg [1:0] tr_mode_sync1_v, tr_mode_sync2_v;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        commit_sync <= 3'b000;
        commit_buf_sync1 <= 2'd0;
        commit_buf_sync2 <= 2'd0;
        tr_mode_sync1_v <= 2'd0;
        tr_mode_sync2_v <= 2'd0;
    end else begin
        commit_sync <= {commit_sync[1:0], bmp_display_commit_toggle};
        commit_buf_sync1 <= write_buf_idx;
        commit_buf_sync2 <= commit_buf_sync1;
        tr_mode_sync1_v <= tr_mode_reg;
        tr_mode_sync2_v <= tr_mode_sync1_v;
    end
end
wire commit_toggle_v = commit_sync[1] ^ commit_sync[2];
reg [1:0] commit_buf_v;
reg commit_pulse_v;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        commit_buf_v <= 2'd0;
        commit_pulse_v <= 1'b0;
    end else begin
        commit_pulse_v <= commit_toggle_v;
        if (commit_toggle_v) commit_buf_v <= commit_buf_sync2;
    end
end

// 显示提交握手：源与目标均成功完成才锁住下一次装载，视频完成转场才释放。
// 只同步持久电平和 toggle；不跨域传递单拍脉冲。
reg display_submit_pending_sd;
reg [1:0] tr_hold_sync_sd;
reg tr_hold_prev_v, display_release_toggle_v;
reg [2:0] display_release_sync_sd;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        tr_hold_prev_v <= 0;
        display_release_toggle_v <= 0;
    end else begin
        tr_hold_prev_v <= tr_hold_load;
        if (tr_hold_prev_v && !tr_hold_load)
            display_release_toggle_v <= ~display_release_toggle_v;
    end
end
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        display_submit_pending_sd <= 0;
        tr_hold_sync_sd <= 0;
        display_release_sync_sd <= 0;
    end else begin
        tr_hold_sync_sd <= {tr_hold_sync_sd[0], tr_hold_load};
        display_release_sync_sd <= {display_release_sync_sd[1:0], display_release_toggle_v};
        if (bmp_display_commit_pulse)
            display_submit_pending_sd <= 1;
        else if (display_release_sync_sd[2] ^ display_release_sync_sd[1])
            display_submit_pending_sd <= 0;
    end
end


transition_ctrl #(
    .PAGE0_BASE (21'h0_0000),
    .PAGE1_BASE (21'h8_0000),
    .ALPHA_STEP (8'd8),
    .SLIDE_STEP (10'd16), .X_BITS(11), .Y_BITS(10)
) u_transition(
    .clk           (video_clk),
    .rst           (rst_video),
    .vs_rise       (vs_rise_v),
    .x             (main_x),
    .y             (main_y),
    .commit_toggle (commit_pulse_v),
    .commit_buf    (commit_buf_v),
    .tr_mode       (tr_mode_sync2_v), // KEY4配置在提交时锁存，转场途中不可变
    .tr_active     (tr_active),
    .fade_black    (tr_fade_black),
    .alpha         (tr_alpha),
    .boundary      (tr_boundary),
    .slide_axis    (tr_slide_axis),
    .page_a_base   (page_a_base),
    .page_b_base   (page_b_base),
    .page_upd_a    (),
    .page_upd_b    (),
    .hold_load     (tr_hold_load)
);