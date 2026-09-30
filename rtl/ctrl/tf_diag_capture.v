// 只读 TF 诊断：计数不参与播放控制；192 位状态以握手快照跨时钟域。
module tf_diag_capture #(
    parameter integer SNAPSHOT_CYCLES = 1_000_000,
    parameter [31:0] PROBE_LBA = 32'd32784
)(
    input wire sd_clk, sd_rst, video_clk, video_rst,
    input wire sd_init_done,
    input wire [31:0] bmp_status,
    input wire sd_req,
    input wire [31:0] sd_addr,
    input wire [7:0] sd_data,
    input wire sd_data_valid, sd_end,
    input wire controller_reset, bmp_timeout, wav_timeout,
    input wire pixel_valid, write_req,
    input wire frame_write_finish_pulse, scaler_commit_toggle,
    output reg [191:0] video_snapshot
);
    reg [31:0] last_lba, sector_ends, pixel_count, probe_header;
    reg [15:0] controller_resets;
    reg [7:0] write_finishes, scaler_commits;
    reg [2:0] probe_count;
    reg sticky_reset, sticky_bmp_timeout, sticky_wav_timeout;
    reg write_req_prev, scaler_toggle_prev;

    // PROBE_LBA 是本轮实测草莓起始扇区；仅观察已有读事务，不额外访问卡。
    always @(posedge sd_clk or posedge sd_rst) begin
        if (sd_rst) begin
            last_lba <= 0; sector_ends <= 0; pixel_count <= 0;
            probe_header <= 0; probe_count <= 0; controller_resets <= 0;
            write_finishes <= 0; scaler_commits <= 0;
            sticky_reset <= 0; sticky_bmp_timeout <= 0; sticky_wav_timeout <= 0;
            write_req_prev <= 0; scaler_toggle_prev <= 0;
        end else begin
            write_req_prev <= write_req;
            scaler_toggle_prev <= scaler_commit_toggle;
            if (sd_req) begin
                last_lba <= sd_addr;
                if (sd_addr == PROBE_LBA) begin
                    probe_count <= 0;
                    probe_header <= 0;
                end
            end
            if (sd_data_valid && last_lba == PROBE_LBA && probe_count < 4) begin
                probe_header <= {probe_header[23:0], sd_data};
                probe_count <= probe_count + 1'b1;
            end
            if (sd_end) sector_ends <= sector_ends + 1'b1;
            // 物理控制器软复位不清除诊断计数，防止复位把故障证据擦掉。
            if (controller_reset) begin
                controller_resets <= controller_resets + 1'b1;
                sticky_reset <= 1'b1;
            end
            if (bmp_timeout) sticky_bmp_timeout <= 1'b1;
            if (wav_timeout) sticky_wav_timeout <= 1'b1;
            if (write_req && !write_req_prev) pixel_count <= 0;
            else if (pixel_valid) pixel_count <= pixel_count + 1'b1;
            if (frame_write_finish_pulse) write_finishes <= write_finishes + 1'b1;
            if (scaler_commit_toggle != scaler_toggle_prev) scaler_commits <= scaler_commits + 1'b1;
        end
    end

    // 标志位：0=初始化，1=扫描完成，2=装载忙，3=源数据完成，4=显示提交，
    // 5=装载故障，6=重试，7=存在可用图，8..10=历史复位/超时，11=读完成，12=探针完整。
    wire [15:0] flags = {3'd0, (probe_count == 4), (sector_ends != 0),
        sticky_wav_timeout, sticky_bmp_timeout, sticky_reset,
        bmp_status[7], bmp_status[4], bmp_status[3], bmp_status[5],
        bmp_status[2], bmp_status[1], bmp_status[0], sd_init_done};
    wire [15:0] bmp_sne = {4'd0, bmp_status[19:16], bmp_status[11:8], bmp_status[15:12]};
    wire [191:0] current_snapshot = {flags, bmp_sne, last_lba, sector_ends,
        controller_resets, probe_header, pixel_count, write_finishes, scaler_commits};

    reg [191:0] mailbox;
    reg request_toggle, ack_toggle;
    reg [2:0] ack_sync, request_sync;
    reg [31:0] snapshot_timer;
    // 发送方从发布到接收方 ACK 全程保持 mailbox；两级以上同步保证总线稳定后采样。
    always @(posedge sd_clk or posedge sd_rst) begin
        if (sd_rst) begin
            mailbox <= 0; request_toggle <= 0; ack_sync <= 0; snapshot_timer <= 0;
        end else begin
            ack_sync <= {ack_sync[1:0], ack_toggle};
            if (snapshot_timer < SNAPSHOT_CYCLES - 1)
                snapshot_timer <= snapshot_timer + 1'b1;
            else if (ack_sync[2] == request_toggle) begin
                mailbox <= current_snapshot;
                request_toggle <= ~request_toggle;
                snapshot_timer <= 0;
            end
        end
    end
    always @(posedge video_clk or posedge video_rst) begin
        if (video_rst) begin
            request_sync <= 0; ack_toggle <= 0; video_snapshot <= 0;
        end else begin
            request_sync <= {request_sync[1:0], request_toggle};
            if (request_sync[2] != ack_toggle) begin
                video_snapshot <= mailbox;
                ack_toggle <= request_sync[2];
            end
        end
    end
endmodule
