reg [2:0] commit_sync;
reg [1:0] commit_buf_sync1, commit_buf_sync2;
reg [1:0] tr_mode_sync1_v, tr_mode_sync2_v;
always @(posedge video_clk or posedge media_rst_video) begin
    if (media_rst_video) begin
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
always @(posedge video_clk or posedge media_rst_video) begin
    if (media_rst_video) begin
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
always @(posedge video_clk or posedge media_rst_video) begin
    if (media_rst_video) begin
        tr_hold_prev_v <= 0;
        display_release_toggle_v <= 0;
    end else begin
        tr_hold_prev_v <= tr_hold_load;
        if (tr_hold_prev_v && !tr_hold_load)
            display_release_toggle_v <= ~display_release_toggle_v;
    end
end
always @(posedge sd_card_clk or posedge media_rst_sd) begin
    if (media_rst_sd) begin
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


// 两种提交策略共用显示双页；未选调度器保持复位。
wire [20:0] video_page_base,picture_page_a,picture_page_b;
wire video_hold,picture_hold,picture_tr_active,picture_fade_black;
wire [7:0] picture_alpha;
wire [9:0] picture_boundary;
wire [1:0] picture_slide_axis;
video_frame_commit #(.PAUSE_ENABLE(1)) u_frame_commit(
    .clk(video_clk),.rst(media_rst_video | !media_mode_v),.vs_rise(vs_rise_v),.pause(media_pause_v),
    .ready_pulse(commit_pulse_v),.ready_buf(commit_buf_v),
    .page_base(video_page_base),.hold_load(video_hold),.displayed(),.applied_pulse());
transition_ctrl #(.PAGE0_BASE(21'h0_0000),.PAGE1_BASE(21'h8_0000),
    .ALPHA_STEP(8'd8),.SLIDE_STEP(10'd16),.X_BITS(11),.Y_BITS(10)) u_transition(
    .clk(video_clk),.rst(media_rst_video | media_mode_v),.vs_rise(vs_rise_v),.x(main_x),.y(main_y),
    .commit_toggle(commit_pulse_v),.commit_buf(commit_buf_v),.tr_mode(tr_mode_sync2_v),
    .tr_active(picture_tr_active),.fade_black(picture_fade_black),.alpha(picture_alpha),
    .boundary(picture_boundary),.slide_axis(picture_slide_axis),
    .page_a_base(picture_page_a),.page_b_base(picture_page_b),.page_upd_a(),.page_upd_b(),.hold_load(picture_hold));
assign page_a_base=media_mode_v ? video_page_base : picture_page_a;
assign page_b_base=media_mode_v ? video_page_base : picture_page_b;
assign tr_hold_load=media_mode_v ? video_hold : picture_hold;
assign tr_active=!media_mode_v && picture_tr_active;
assign tr_fade_black=!media_mode_v && picture_fade_black;
assign tr_alpha=media_mode_v ? 8'd255 : picture_alpha;
assign tr_boundary=media_mode_v ? 10'd0 : picture_boundary;
assign tr_slide_axis=media_mode_v ? 2'd0 : picture_slide_axis;

