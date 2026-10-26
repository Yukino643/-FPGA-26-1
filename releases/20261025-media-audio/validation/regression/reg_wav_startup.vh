reg wav_scan_start_r, wav_load_start_r;
reg wav_scan_kicked, wav_load_running;
wire wav_rst = rst_sd | media_rst_sd | ~sd_init_done;
wire pcm_sd_req,pcm_sd_valid,pcm_sd_done,pcm_sd_error;
wire [31:0] pcm_sd_sector;
wire [7:0] pcm_sd_data;
media_audio_router u_media_audio_router(
    .clk(sd_card_clk),.rst(wav_rst),.video_mode(media_active_sd),.metadata_ready(video_metadata_ready),
    .first_cluster(video_file_cluster),.file_size(video_file_size),.fat_lba(audio_fat_lba),
    .data_lba(audio_data_lba),.max_cluster(audio_max_cluster),.spc(audio_spc),.spc_shift(audio_shift),
    .reader_req(pcm_sd_req),.reader_sector(pcm_sd_sector),.reader_data(pcm_sd_data),
    .reader_valid(pcm_sd_valid),.reader_done(pcm_sd_done),.reader_error(pcm_sd_error),.idle(audio_router_idle),
    .physical_req(wav_sd_sec_read),.physical_addr(wav_sd_sec_read_addr),.physical_data(wav_sd_sec_read_data),
    .physical_valid(wav_sd_sec_read_data_valid),.physical_done(wav_sd_sec_read_end),.physical_error(wav_sd_timeout));
always @(posedge sd_card_clk or posedge wav_rst) begin
    if (wav_rst) begin
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
        end else if(!media_hold_sd) begin
            if(media_active_sd) begin
                if(video_metadata_ready && video_audio_present && wav_ready && !wav_scan_kicked) begin
                    wav_load_start_r<=1;wav_scan_kicked<=1;wav_load_running<=1;
                end
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
end

wav_read #(.SCAN_MAX_SECTORS(1),.RAW_ENABLE(1)) u_wav_read(
    .clk                   (sd_card_clk),
    .rst                   (wav_rst),
    .raw_mode(media_active_sd),.halt(media_hold_sd),.raw_sector_error(pcm_sd_error),
    .raw_start_sector(video_audio_sector),.raw_sample_count(video_audio_samples),
    .quiescent(audio_quiescent),.load_error(audio_load_error),
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
    .sd_sec_read           (pcm_sd_req),
    .sd_sec_read_addr      (pcm_sd_sector),
    .sd_sec_read_data      (pcm_sd_data),
    .sd_sec_read_data_valid(pcm_sd_valid),
    .sd_sec_read_end       (pcm_sd_done),
    .pcm_valid             (wav_pcm_valid),
    .pcm_left              (wav_pcm_left),
    .pcm_right             (wav_pcm_right),
    .pcm_ready             (!wav_fifo_full)
);

