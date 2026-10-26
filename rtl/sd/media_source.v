// 图片与RV16解析器共用FAT索引/簇链服务和下游writer/scaler。
// mode仅在media_rst期间更新；未选解析器保持复位，不会抢占扇区或提交页。
module media_source # (parameter CLK_FREQ_HZ=100_000_000)(
    input wire clk,rst,global_rst,video_mode,sd_init_done,sd_abort,hold_load,
    input wire initial_write_buf,
    input wire key_next_event,key_auto_event,
    input wire [1:0] auto_period_sel,
    input wire write_finish_toggle,write_req_ack,
    output wire [3:0] state_code,img_count,
    output wire [31:0] debug_status,
    output wire [15:0] cur_img_w,cur_img_h,load_img_w,load_img_h,
    output wire display_valid,display_commit_toggle,display_commit_pulse,
    output wire [1:0] write_buf_idx,disp_buf_idx,
    output wire source_restart,load_done,write_req,pixel_valid,
    output wire [23:0] pixel_rgb,
    output wire sd_req,
    output wire [31:0] sd_addr,
    input wire [7:0] sd_data,
    input wire sd_valid,sd_done,
    output reg wav_found,
    output reg [31:0] wav_sector,
    output wire quiescent,
    output wire [7:0] video_error,
    output wire [15:0] video_frame
    ,output wire video_metadata_ready,video_audio_present
    ,output wire [31:0] video_audio_sector,video_audio_samples,video_file_cluster,video_file_size
    ,output wire [7:0] audio_spc
    ,output wire [2:0] audio_shift
    ,output wire [31:0] audio_fat_lba,audio_data_lba,audio_max_cluster
);
    wire [1:0] scan,file_open,client_req,source_idle;
    wire [31:0] cluster[0:1],size[0:1],sector[0:1];
    wire fs_busy,fs_done,fs_found,client_valid,client_done,client_error,fs_idle;
    wire [7:0] fs_error,client_data;
    wire [3:0] fs_total;
    wire [31:0] found_cluster,found_size;
    wire fs_wav_found;
    wire [31:0] fs_wav_sector;
    assign video_file_cluster=cluster[1];assign video_file_size=size[1];
    media_fat_service fs(
        .clk(clk),.rst(rst),.sd_init_done(sd_init_done),.video_mode(video_mode),.sd_abort(sd_abort),
        .scan_start(scan[video_mode]),.file_start(file_open[video_mode]),.client_req(client_req[video_mode]),
        .first_cluster(cluster[video_mode]),.file_size(size[video_mode]),.client_sector(sector[video_mode]),
        .fs_busy(fs_busy),.fs_done(fs_done),.fs_found(fs_found),.fs_error(fs_error),.fs_total(fs_total),
        .found_cluster(found_cluster),.found_size(found_size),.client_data(client_data),
        .client_valid(client_valid),.client_done(client_done),.client_error(client_error),
        .wav_found(fs_wav_found),.wav_sector(fs_wav_sector),.idle(fs_idle),
        .audio_spc(audio_spc),.audio_shift(audio_shift),.audio_fat_lba(audio_fat_lba),
        .audio_data_lba(audio_data_lba),.audio_max_cluster(audio_max_cluster),
        .sd_req(sd_req),.sd_addr(sd_addr),.sd_data(sd_data),.sd_valid(sd_valid),.sd_done(sd_done));
    // WAV播放器不随视频切换复位。候选保留至TF重新初始化，防止切换扫描清除它。
    always @(posedge clk or posedge global_rst) begin
        if(global_rst) begin wav_found<=0;wav_sector<=0;end
        else if(!sd_init_done) begin wav_found<=0;wav_sector<=0;end
        else if(fs_wav_found && !wav_found) begin wav_found<=1;wav_sector<=fs_wav_sector;end
    end
    wire [3:0] code[0:1];
    wire [31:0] dbg[0:1];
    wire [1:0] valid,commit_toggle,commit_pulse,restart,done,wr_req,px_valid;
    wire [1:0] wr_buf[0:1],disp_buf[0:1];
    wire [23:0] px[0:1];
    wire [3:0] bmp_count;
    wire [15:0] bmp_w,bmp_h,load_w,load_h;
    sd_card_bmp_g #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.SCAN_TARGET_COUNT(8),
        .MAX_WIDTH(1280),.MAX_HEIGHT(720),.PREFETCH_NEXT(1),.EXTERNAL_FS(1),.SEED_ENABLE(1)) picture(
        .clk(clk),.rst(rst | video_mode),.key_next(1'b1),.key_auto(1'b1),
        .key_event_override(1'b1),.key_next_event(key_next_event),.key_auto_event(key_auto_event),
        .auto_period_sel(auto_period_sel),.hold_load(hold_load),.initial_write_buf(initial_write_buf),
        .write_finish_toggle(write_finish_toggle),.write_req_ack(write_req_ack),
        .state_code(code[0]),.img_count(bmp_count),.cur_img_w(bmp_w),.cur_img_h(bmp_h),
        .display_valid(valid[0]),.display_commit_toggle(commit_toggle[0]),.display_commit_pulse(commit_pulse[0]),
        .source_restart(restart[0]),.load_done(done[0]),.load_img_w(load_w),.load_img_h(load_h),
        .debug_status(dbg[0]),.wav_index_found(),.wav_index_sector(),
        .write_buf_idx(wr_buf[0]),.disp_buf_idx(disp_buf[0]),.write_req(wr_req[0]),
        .write_en(px_valid[0]),.write_data(px[0]),.sd_init_done(sd_init_done),.sd_sec_read_abort(sd_abort),
        .sd_sec_read(),.sd_sec_read_addr(),.sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0),
        .fs_scan_start_o(scan[0]),.fs_file_start_o(file_open[0]),.fs_client_req_o(client_req[0]),
        .fs_cluster_o(cluster[0]),.fs_size_o(size[0]),.fs_sector_o(sector[0]),.quiescent(source_idle[0]),
        .fs_busy_i(fs_busy),.fs_done_i(fs_done),.fs_found_i(fs_found),.fs_error_i(fs_error),.fs_total_i(fs_total),
        .fs_cluster_i(found_cluster),.fs_size_i(found_size),.fs_data_i(client_data),
        .fs_valid_i(client_valid),.fs_client_done_i(client_done),.fs_client_error_i(client_error));
    raw_video_player #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.EXTERNAL_FS(1),.SEED_ENABLE(1)) video(
        .clk(clk),.rst(rst | !video_mode),.sd_init_done(sd_init_done),.sd_abort(sd_abort),.hold_load(hold_load),
        .write_finish_toggle(write_finish_toggle),.write_req_ack(write_req_ack),
        .state_code(code[1]),.debug_status(dbg[1]),.display_valid(valid[1]),
        .display_commit_toggle(commit_toggle[1]),.display_commit_pulse(commit_pulse[1]),
        .write_buf_idx(wr_buf[1]),.disp_buf_idx(disp_buf[1]),.source_restart(restart[1]),
        .load_done(done[1]),.write_req(wr_req[1]),.pixel_valid(px_valid[1]),.pixel_rgb(px[1]),
        .sd_req(),.sd_addr(),.sd_data(8'd0),.sd_valid(1'b0),.sd_done(1'b0),
        .initial_write_buf(initial_write_buf),.error_code(video_error),.frame_index(video_frame),.read_cycles_last(),
        .metadata_ready(video_metadata_ready),.audio_present(video_audio_present),
        .audio_sector(video_audio_sector),.audio_samples(video_audio_samples),
        .fs_scan_start_o(scan[1]),.fs_file_start_o(file_open[1]),.fs_client_req_o(client_req[1]),
        .fs_cluster_o(cluster[1]),.fs_size_o(size[1]),.fs_sector_o(sector[1]),.quiescent(source_idle[1]),
        .fs_busy_i(fs_busy),.fs_done_i(fs_done),.fs_found_i(fs_found),.fs_error_i(fs_error),.fs_total_i(fs_total),
        .fs_cluster_i(found_cluster),.fs_size_i(found_size),.fs_data_i(client_data),
        .fs_valid_i(client_valid),.fs_client_done_i(client_done),.fs_client_error_i(client_error));
    assign quiescent=source_idle[video_mode] && fs_idle;
    assign state_code=code[video_mode];
    assign debug_status=dbg[video_mode];
    assign display_valid=valid[video_mode];
    assign display_commit_toggle=commit_toggle[video_mode];
    assign display_commit_pulse=commit_pulse[video_mode];
    assign write_buf_idx=wr_buf[video_mode];
    assign disp_buf_idx=disp_buf[video_mode];
    assign source_restart=restart[video_mode];
    assign load_done=done[video_mode];
    assign write_req=wr_req[video_mode];
    assign pixel_valid=px_valid[video_mode];
    assign pixel_rgb=px[video_mode];
    assign img_count=video_mode ? 4'd1 : bmp_count;
    assign cur_img_w=video_mode ? 16'd320 : bmp_w;
    assign cur_img_h=video_mode ? 16'd180 : bmp_h;
    assign load_img_w=video_mode ? 16'd320 : load_w;
    assign load_img_h=video_mode ? 16'd180 : load_h;
endmodule
