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

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// writer完成toggle转SD域单拍，送完整页事务隔离门。
reg [2:0] fw_tgl_sync;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) fw_tgl_sync <= 3'b000;
    else         fw_tgl_sync <= {fw_tgl_sync[1:0], frame_write_toggle_mem};
end
wire frame_write_finish_pulse = fw_tgl_sync[2] ^ fw_tgl_sync[1];

// 源帧完整后启动缩放；管理器只接受目标显示页写完后的事件。
wire scaler_start_tgl;
wire scaler_commit_toggle;
wire resize_busy_mem, resize_error_mem;
reg [1:0] resize_busy_sync_sd;
reg [2:0] resize_error_sync_sd;
reg [1:0] resize_card_ready_mem;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if(rst_sd) begin resize_busy_sync_sd<=0; resize_error_sync_sd<=0; end
    else begin
        resize_busy_sync_sd<={resize_busy_sync_sd[0],resize_busy_mem};
        resize_error_sync_sd<={resize_error_sync_sd[1:0],resize_error_mem};
    end
end
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if(rst_mem) resize_card_ready_mem<=0;
    else resize_card_ready_mem<={resize_card_ready_mem[0],sd_init_done};
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


// 同一稳定ACK同时供解析器接收握手；raw ACK仍送gate内部相同两级同步。
reg [1:0] source_write_ack_sync_sd;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) source_write_ack_sync_sd <= 0;
    else source_write_ack_sync_sd <= {source_write_ack_sync_sd[0], sd_card_write_req_ack};
end

raw_video_player #(.CLK_FREQ_HZ(100_000_000)) player(
        .clk(sd_card_clk),.rst(rst_sd),.sd_init_done(sd_init_done),
        .sd_abort(bmp_sd_timeout | (resize_error_sync_sd[1] & ~resize_error_sync_sd[2])),
        .hold_load(display_submit_pending_sd | tr_hold_sync_sd[1] | resize_busy_sync_sd[1]),
        .write_finish_toggle(scaler_commit_toggle),.write_req_ack(source_write_ack_sync_sd[1]),
        .state_code(state_code),.debug_status(tf_bmp_debug),.display_valid(display_valid),
        .display_commit_toggle(bmp_display_commit_toggle),.display_commit_pulse(bmp_display_commit_pulse),
        .write_buf_idx(write_buf_idx),.disp_buf_idx(disp_buf_idx),.source_restart(bmp_source_restart),
        .load_done(bmp_load_done),.write_req(sd_card_write_req),.pixel_valid(bmp_wr_en),.pixel_rgb(bmp_wr_data),
        .sd_req(bmp_sd_sec_read),.sd_addr(bmp_sd_sec_read_addr),.sd_data(bmp_sd_sec_read_data),
        .sd_valid(bmp_sd_sec_read_data_valid),.sd_done(bmp_sd_sec_read_end),
        .error_code(raw_error),.frame_index(raw_frame),.read_cycles_last());
src_packer u_src_packer(
    .clk       (sd_card_clk),
    .rst       (rst_sd),
    .frame_restart (bmp_source_restart),
    .px_valid  (bmp_wr_en),
    .px_rgb    (bmp_wr_data),
    .row_width (bmp_load_img_w),
    .load_done (bmp_load_done),
    .out_valid (packed_wr_en),
    .out_data  (packed_wr_data)
);
source_scaler_gate u_source_scaler_gate (
    .clk(sd_card_clk), .rst(rst_sd), .sd_init_done(sd_init_done),
    .source_restart(bmp_source_restart), .source_done(bmp_load_done),
    .write_req(sd_card_write_req), .write_req_ack(sd_card_write_req_ack),
    .frame_write_finish_pulse(frame_write_finish_pulse),
    .scaler_start_toggle(scaler_start_tgl), .scaler_start_pulse()
);
resize_frame_720 u_resize_frame(
    .clk(ext_mem_clk), .rst(rst_mem), .cancel(~resize_card_ready_mem[1]),
    .start_toggle(scaler_start_tgl), .cfg_w(bmp_load_img_w[10:0]), .cfg_h(bmp_load_img_h[10:0]),
    .cfg_src_base(21'h100000), .cfg_dst_base(write_buf_idx[0] ? BUF1_ADDR : BUF0_ADDR),
    .cmd_valid(resize_cmd_valid), .cmd_addr(resize_cmd_addr), .cmd_len(resize_cmd_len),
    .cmd_ready(resize_cmd_ready), .rsp_valid(resize_rsp_valid), .rsp_last(resize_rsp_last), .rsp_data(resize_rsp_data),
    .write_request(resize_write_request), .write_ready(memory_write_ready),
    .wr_en(resize_wr_en), .wr_addr(resize_wr_addr), .wr_data(resize_wr_data),
    .busy(resize_busy_mem), .done_toggle(scaler_commit_toggle), .error(resize_error_mem)
);
wire video_read_en_unused;
wire [31:0] video_read_data_unused;
// 解析器已检查宽<=1280、高<=720；收窄乘法输入，避免为未支持的16bit尺寸保留DSP。
wire [9:0] source_row_words = ({1'b0,bmp_load_img_w[10:0]}+12'd1)>>1;
wire [20:0] source_frame_words = source_row_words*bmp_load_img_h[9:0];

// 先写完整紧凑源图，不能用固定460800字等待640素材的后续像素。
frame_read_write #(
    .WRITE_V_FLIP     (0),
    .EXTERNAL_READ    (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (720)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (),
    .App_rd_addr       (),
    .Sdr_rd_en         (1'b0),
    .Sdr_rd_dout       (32'd0),

    .read_clk          (video_clk),
    .read_req          (1'b0),
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
    .external_rd_busy   (memory_read_busy),
    .source_write_busy  (source_write_busy),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    // 显示双页以外的源图暂存区，最大源图末地址0x1707ff < 0x200000。
    .write_addr_0      (21'h100000),
    .write_addr_1      (21'h100000),
    .write_addr_2      (21'd0),
    .write_addr_3      (21'd0),
    .write_addr_index  (2'd0),
    .write_len         (source_frame_words),
    .write_en          (packed_wr_en),    // W6: 来自 src_packer
    .write_data        (packed_wr_data)   // W6: RGB565 打包
);


video_frame_commit u_frame_commit(
        .clk(video_clk),.rst(rst_video),.vs_rise(vs_rise_v),
        .ready_pulse(commit_pulse_v),.ready_buf(commit_buf_v),
        .page_base(page_a_base),.hold_load(tr_hold_load),.displayed(displayed),.applied_pulse(applied));