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
            if (!wav_scan_kicked && wav_ready && display_valid) begin
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

wav_read u_wav_read(
    .clk                   (sd_card_clk),
    .rst                   (wav_rst),
    .ready                 (wav_ready),
    .scan_start            (wav_scan_start_r),
    .scan_start_sector     (32'd0),
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

