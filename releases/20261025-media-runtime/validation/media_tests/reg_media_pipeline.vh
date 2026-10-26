media_runtime_ctrl #(.DEFAULT_VIDEO(RAW_VIDEO_MODE)) u_media_runtime(
    .sd_clk(sd_card_clk),.mem_clk(ext_mem_clk),.video_clk(video_clk),
    .rst_sd(rst_sd),.rst_mem(rst_mem),.rst_video(rst_video),
    .requested_video(media_requested_sd),.requested_pause(media_pause_requested_sd),
    .source_idle(media_source_idle),.storage_idle(media_storage_idle),
    .pipeline_idle(!resize_busy_sync_sd[1] && !display_submit_pending_sd && !tr_hold_sync_sd[1]),
    .vs_rise(vs_rise_v),.active_video(media_active_sd),.busy(media_busy_sd),.hold_source(media_hold_sd),
    .media_rst_sd(media_rst_sd),.media_rst_mem(media_rst_mem),.media_rst_video(media_rst_video),
    .drain_mem(media_drain_mem),.blank_video(media_blank_v),.video_mode(media_mode_v),.pause_video(media_pause_v));
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

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge media_rst_mem) begin
    if (media_rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// writer完成toggle转SD域单拍，送完整页事务隔离门。
reg [2:0] fw_tgl_sync;
always @(posedge sd_card_clk or posedge media_rst_sd) begin
    if (media_rst_sd) fw_tgl_sync <= 3'b000;
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
always @(posedge sd_card_clk or posedge media_rst_sd) begin
    if(media_rst_sd) begin resize_busy_sync_sd<=0; resize_error_sync_sd<=0; end
    else begin
        resize_busy_sync_sd<={resize_busy_sync_sd[0],resize_busy_mem};
        resize_error_sync_sd<={resize_error_sync_sd[1:0],resize_error_mem};
    end
end
always @(posedge ext_mem_clk or posedge media_rst_mem) begin
    if(media_rst_mem) resize_card_ready_mem<=0;
    else resize_card_ready_mem<={resize_card_ready_mem[0],sd_init_done};
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


// 同一稳定ACK同时供解析器接收握手；raw ACK仍送gate内部相同两级同步。
reg [1:0] source_write_ack_sync_sd;
always @(posedge sd_card_clk or posedge media_rst_sd) begin
    if (media_rst_sd) source_write_ack_sync_sd <= 0;
    else source_write_ack_sync_sd <= {source_write_ack_sync_sd[0], sd_card_write_req_ack};
end

media_source #(.CLK_FREQ_HZ(100_000_000)) u_media_source(
    .clk(sd_card_clk),.rst(media_rst_sd),.global_rst(rst_sd),.video_mode(media_active_sd),
    .sd_init_done(sd_init_done),.sd_abort(bmp_sd_timeout | (resize_error_sync_sd[1] & ~resize_error_sync_sd[2])),
    .hold_load(media_hold_sd | display_submit_pending_sd | tr_hold_sync_sd[1] | resize_busy_sync_sd[1]),
    .key_next_event(monitor_key_next_pulse_sd),.key_auto_event(monitor_key_auto_pulse_sd),
    .auto_period_sel(monitor_period_active_sd),
    .write_finish_toggle(scaler_commit_toggle),.write_req_ack(source_write_ack_sync_sd[1]),
    .state_code(state_code),.debug_status(tf_bmp_debug),.img_count(img_count),
    .cur_img_w(cur_img_w),.cur_img_h(cur_img_h),.load_img_w(bmp_load_img_w),.load_img_h(bmp_load_img_h),
    .display_valid(display_valid),.display_commit_toggle(bmp_display_commit_toggle),.display_commit_pulse(bmp_display_commit_pulse),
    .write_buf_idx(write_buf_idx),.disp_buf_idx(disp_buf_idx),.source_restart(bmp_source_restart),
    .load_done(bmp_load_done),.write_req(sd_card_write_req),.pixel_valid(bmp_wr_en),.pixel_rgb(bmp_wr_data),
    .sd_req(bmp_sd_sec_read),.sd_addr(bmp_sd_sec_read_addr),.sd_data(bmp_sd_sec_read_data),
    .sd_valid(bmp_sd_sec_read_data_valid),.sd_done(bmp_sd_sec_read_end),
    .wav_found(wav_index_found),.wav_sector(wav_index_sector),.quiescent(media_source_idle),
    .video_error(media_error_sd),.video_frame(media_frame_sd));
src_packer u_src_packer(
    .clk       (sd_card_clk),
    .rst       (media_rst_sd),
    .frame_restart (bmp_source_restart),
    .px_valid  (bmp_wr_en),
    .px_rgb    (bmp_wr_data),
    .row_width (bmp_load_img_w),
    .load_done (bmp_load_done),
    .out_valid (packed_wr_en),
    .out_data  (packed_wr_data)
);
source_scaler_gate u_source_scaler_gate (
    .clk(sd_card_clk), .rst(media_rst_sd), .sd_init_done(sd_init_done),
    .source_restart(bmp_source_restart), .source_done(bmp_load_done),
    .write_req(sd_card_write_req), .write_req_ack(sd_card_write_req_ack),
    .frame_write_finish_pulse(frame_write_finish_pulse),
    .scaler_start_toggle(scaler_start_tgl), .scaler_start_pulse()
);
resize_frame_720 u_resize_frame(
    .clk(ext_mem_clk), .rst(media_rst_mem), .cancel(~resize_card_ready_mem[1]),
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
    .rst               (media_rst_mem),
    .Sdr_init_done     (Sdr_init_done && !media_drain_mem),
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


wire        mpu_A_cv, mpu_A_cr, mpu_A_rv, mpu_A_rl;
wire [20:0] mpu_A_ca;
wire [31:0] mpu_A_rd;
wire [7:0]  mpu_A_cl;
wire        mpu_B_cv, mpu_B_cr, mpu_B_rv, mpu_B_rl;
wire [20:0] mpu_B_ca;
wire [31:0] mpu_B_rd;
wire [7:0]  mpu_B_cl;
// 源写入与缩放写入互斥，C口在源帧完成后读取暂存区。
wire source_write_busy, memory_read_busy, memory_write_ready;
wire resize_cmd_valid, resize_cmd_ready, resize_rsp_valid, resize_rsp_last;
wire [20:0] resize_cmd_addr, resize_wr_addr;
wire [7:0] resize_cmd_len;
wire [31:0] resize_rsp_data, resize_wr_data;
wire resize_write_request, resize_wr_en;
wire sdram_wr_en;
wire [20:0] sdram_wr_addr;
wire [31:0] sdram_wr_din;
wire [3:0] sdram_wr_dm;

mem_mpu #(.MAX_A_RUN(8), .MAX_B_RUN(8), .MAX_C_RUN(4)) u_mem_mpu(
    .clk            (ext_mem_clk),
    .rst            (rst_mem),
    .A_cmd_valid    (mpu_A_cv), .A_cmd_addr(mpu_A_ca), .A_cmd_len(mpu_A_cl),
    .A_cmd_ready    (mpu_A_cr), .A_rsp_valid(mpu_A_rv), .A_rsp_data(mpu_A_rd), .A_rsp_last(mpu_A_rl),
    .B_cmd_valid    (mpu_B_cv), .B_cmd_addr(mpu_B_ca), .B_cmd_len(mpu_B_cl),
    .B_cmd_ready    (mpu_B_cr), .B_rsp_valid(mpu_B_rv), .B_rsp_data(mpu_B_rd), .B_rsp_last(mpu_B_rl),
    .C_cmd_valid    (resize_cmd_valid), .C_cmd_addr(resize_cmd_addr), .C_cmd_len(resize_cmd_len),
    .C_cmd_ready    (resize_cmd_ready), .C_rsp_valid(resize_rsp_valid), .C_rsp_data(resize_rsp_data), .C_rsp_last(resize_rsp_last),
    .App_rd_en      (App_rd_en),
    .App_rd_addr    (App_rd_addr),
    .Sdr_rd_en      (Sdr_rd_en),
    .Sdr_rd_dout    (Sdr_rd_dout),
    .Sdr_init_done  (Sdr_init_done && !media_drain_mem),
    .Sdr_busy       (Sdr_busy),
    .source_write_busy(source_write_busy),
    .scaler_write_request(resize_write_request),
    .read_busy      (memory_read_busy),
    .write_ready    (memory_write_ready), .idle(media_storage_idle),
    .App_wr_en_u    (App_wr_en),
    .App_wr_addr_u  (App_wr_addr),
    .App_wr_din_u   (App_wr_din),
    .App_wr_dm_u    (App_wr_dm),
    .App_wr2_en_u   (resize_wr_en),
    .App_wr2_addr_u (resize_wr_addr),
    .App_wr2_din_u  (resize_wr_data),
    .App_wr2_dm_u   (4'h0),
    .wr2_active     (resize_busy_mem),
    .App_wr_en      (sdram_wr_en),
    .App_wr_addr    (sdram_wr_addr),
    .App_wr_din     (sdram_wr_din),
    .App_wr_dm      (sdram_wr_dm)
);

// ---- RGB565双页预取与两拍混合流水 ----
wire [23:0] mix_rgb;
wire mix_de,mix_vs;
wire [10:0] mix_x;
wire [9:0] mix_y;
wire [31:0] disp_underflow;
display_stream_720 u_display_stream(
    .mem_clk(ext_mem_clk),.mem_rst(media_rst_mem),.video_clk(video_clk),.video_rst(media_rst_video),
    .vs_toggle(vs_toggle_r),.de_in(main_de_al),.vs_in(vs),.x(main_x),.y(main_y),
    .tr_active(tr_active),.alpha(tr_alpha),.page_a_base(page_a_base),.page_b_base(page_b_base),
    .a_cmd_valid(mpu_A_cv),.a_cmd_addr(mpu_A_ca),.a_cmd_len(mpu_A_cl),.a_cmd_ready(mpu_A_cr),
    .a_rsp_valid(mpu_A_rv),.a_rsp_data(mpu_A_rd),.a_rsp_last(mpu_A_rl),
    .b_cmd_valid(mpu_B_cv),.b_cmd_addr(mpu_B_ca),.b_cmd_len(mpu_B_cl),.b_cmd_ready(mpu_B_cr),
    .b_rsp_valid(mpu_B_rv),.b_rsp_data(mpu_B_rd),.b_rsp_last(mpu_B_rl),
    .rgb_out(mix_rgb),.de_out(mix_de),.vs_out(mix_vs),.x_out(mix_x),.y_out(mix_y),
    .underflow_cnt(disp_underflow)
);


reg [1:0] display_valid_sync_v;
reg display_visible_v;
always @(posedge video_clk or posedge media_rst_video) begin
    if (media_rst_video) begin display_valid_sync_v <= 0; display_visible_v <= 0; end
    else begin
        display_valid_sync_v <= {display_valid_sync_v[0], display_valid};
        if (vs_rise_v) display_visible_v <= display_valid_sync_v[1];
    end
end
assign vout_data = (display_visible_v && !media_blank_v) ? mix_rgb : 24'd0;


sd_arbiter #(.TIMEOUT_CYCLES(10_000_000)) u_sd_arbiter(
    .clk(sd_card_clk), .rst(rst_sd),
    .a_req(bmp_sd_sec_read), .a_addr(bmp_sd_sec_read_addr), .a_ack(),
    .a_data(bmp_sd_sec_read_data), .a_data_valid(bmp_sd_sec_read_data_valid),
    .a_done(bmp_sd_sec_read_end), .a_timeout(bmp_sd_timeout),
    .b_req(wav_sd_sec_read), .b_addr(wav_sd_sec_read_addr), .b_ack(),
    .b_data(wav_sd_sec_read_data), .b_data_valid(wav_sd_sec_read_data_valid),
    .b_done(wav_sd_sec_read_end), .b_timeout(wav_sd_timeout),
    .sd_sec_read(sd_phy_sec_read), .sd_sec_read_addr(sd_phy_sec_read_addr),
    .sd_sec_read_data(sd_phy_sec_read_data),
    .sd_sec_read_data_valid(sd_phy_sec_read_data_valid),
    .sd_sec_read_end(sd_phy_sec_read_end),
    .controller_reset_req(sd_controller_reset), .owner(sd_owner)
);
reg wav_scan_start_r, wav_load_start_r;
reg wav_scan_kicked, wav_load_running;
wire wav_rst = rst_sd | ~sd_init_done;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        wav_scan_start_r <= 1'b0;
        wav_load_start_r <= 1'b0;
        wav_scan_kicked  <= 1'b0;
        wav_load_running <= 1'b0;
    end else begin
        wav_scan_start_r <= 1'b0;
        wav_load_start_r <= 1'b0;
        if (!sd_init_done) begin
            wav_scan_kicked  <= 1'b0;
            wav_load_running <= 1'b0;
        end else begin
            if (!wav_scan_kicked && wav_ready && wav_index_found) begin
                wav_scan_start_r <= 1'b1;
                wav_scan_kicked  <= 1'b1;
            end
            if (wav_scan_done && wav_scan_found && wav_ready && !wav_load_running) begin
                wav_load_start_r <= 1'b1;
                wav_load_running <= 1'b1;
            end
            if (wav_load_done)
                wav_load_running <= 1'b0;
        end
    end
end

wav_read #(.SCAN_MAX_SECTORS(1)) u_wav_read(
    .clk                   (sd_card_clk),
    .rst                   (wav_rst),
    .ready                 (wav_ready),
    .scan_start            (wav_scan_start_r),
    .scan_start_sector     (wav_index_sector),
    .scan_done             (wav_scan_done),
    .scan_found_valid      (wav_scan_found),
    .scan_found_sector     (wav_scan_sector),
    .load_start            (wav_load_start_r),
    .load_sector           (wav_scan_sector),
    .load_done             (wav_load_done),
    .load_active           (wav_load_active),
    .load_pcm_bytes        (wav_pcm_bytes),
    .sd_sec_read           (wav_sd_sec_read),
    .sd_sec_read_addr      (wav_sd_sec_read_addr),
    .sd_sec_read_data      (wav_sd_sec_read_data),
    .sd_sec_read_data_valid(wav_sd_sec_read_data_valid),
    .sd_sec_read_end       (wav_sd_sec_read_end),
    .pcm_valid             (wav_pcm_valid),
    .pcm_left              (wav_pcm_left),
    .pcm_right             (wav_pcm_right),
    .pcm_ready             (!wav_fifo_full)
);


audio_player #(.VIDEO_CLK_HZ(74_250_000),.NOMINAL_SAMPLES_PER_FRAME(800)) u_audio_player(
    .clk_sd       (sd_card_clk),
    .clk_video    (video_clk),
    .rst_sd       (rst_sd),
    .rst_video    (rst_video),
    .pcm_valid    (wav_pcm_valid),
    .pcm_left     (wav_pcm_left),
    .pcm_right    (wav_pcm_right),
    .vs_pulse     (vs_rise_v),
    .audio_valid  (audio_valid),
    .sample_data_valid (audio_sample_data_valid),
    .audio_left   (audio_left_data),
    .audio_right  (audio_right_data),
    .sync_dev     (sync_dev_real),   // W10: 接监视台
    .sample_cnt   (),
    .frame_cnt    (),
    .sample_tick  (audio_sample_tick),
    .fifo_empty   (wav_fifo_empty),
    .fifo_full    (wav_fifo_full)
);