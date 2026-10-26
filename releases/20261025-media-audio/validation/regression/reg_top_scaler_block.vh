wire scaler_start_tgl;
source_scaler_gate u_source_scaler_gate (
    .clk(sd_card_clk), .rst(rst_sd), .sd_init_done(sd_init_done),
    .source_restart(bmp_source_restart), .source_done(bmp_load_done),
    .write_req(sd_card_write_req), .write_req_ack(sd_card_write_req_ack),
    .frame_write_finish_pulse(frame_write_finish_pulse),
    .scaler_start_toggle(scaler_start_tgl), .scaler_start_pulse()
);
// 缩放器内部已经完成持久 toggle 的跨时钟域同步和边沿检测。
// 配置在同一个启动事件被锁存，必须使用本次装载的尺寸和写页。
// 装载管理器在缩放完成前保持 busy，宽高和写页在启动同步期间保持稳定。
// pending_buf_idx 与 write_buf_idx 在装载启动时同步更新，完成提交时也使用同一页。
wire [20:0] scaler_dst_base = (write_buf_idx == 2'd0) ? 21'h0_0000 : 21'h8_0000;

scaler #(
    .OUT_W(640),
    .OUT_H(480)
) u_scaler (
    .clk            (ext_mem_clk),
    .rst            (rst_mem),
    .start_toggle   (scaler_start_tgl),
    .cfg_w          (bmp_load_img_w[10:0]),
    .cfg_h          (bmp_load_img_h[10:0]),
    .cfg_src_base   (21'hC_B000),        // MEM_BUF_SRC_BASE
    .cfg_dst_base   (scaler_dst_base),   // 首图与后续图均写入本次待提交页
    // mem_mpu 请求方 C
    .cmd_valid      (mpu_C_cv),
    .cmd_addr       (mpu_C_ca),
    .cmd_len        (mpu_C_cl),
    .cmd_ready      (mpu_C_cr),
    .rsp_valid      (mpu_C_rv),
    .rsp_data       (mpu_C_rd),
    .rsp_last       (mpu_C_rl),
    .write_request  (scaler_write_request),
    .write_ready    (memory_write_ready),
    // mem_mpu 写方 2
    .wr_en          (scaler_wr_en),
    .wr_addr        (scaler_wr_addr),
    .wr_din         (scaler_wr_din),
    .wr_dm          (),
    .busy           (scaler_busy),
    .done_toggle    (scaler_done_toggle),
    .debug_state    (scaler_debug_state)
);

// TF-D3：将 scaler 状态和 C 口握手同步到 SD 诊断域。
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        scaler_state_sd <= 4'd0;
        scaler_busy_sd <= 1'b0;
        scaler_cmd_valid_sd <= 1'b0;
        scaler_cmd_ready_sd <= 1'b0;
        scaler_done_sd <= 1'b0;
    end else begin
        scaler_state_sd <= scaler_debug_state;
        scaler_busy_sd <= scaler_busy;
        scaler_cmd_valid_sd <= mpu_C_cv;
        scaler_cmd_ready_sd <= mpu_C_cr;
        scaler_done_sd <= scaler_done_toggle;
    end
end

// ---- W6: 装载写路径 → SRC_BUF（RGB565 打包，scaler 读取源） ----
