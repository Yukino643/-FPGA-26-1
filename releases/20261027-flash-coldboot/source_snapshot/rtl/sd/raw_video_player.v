// RV16 v1：一次目录索引，逐帧顺序读，复用FAT簇链与既有源writer/scaler。
// 所有输出同属SD域；图像发布/旧页释放沿用顶层toggle邮箱。
module raw_video_player #(
    parameter integer CLK_FREQ_HZ=100_000_000,
    parameter EXTERNAL_FS=0,
    parameter SEED_ENABLE=0
)(
    output wire fs_scan_start_o, fs_file_start_o, fs_client_req_o,
    output wire [31:0] fs_cluster_o, fs_size_o, fs_sector_o,
    input wire fs_busy_i, fs_done_i, fs_found_i,
    input wire [7:0] fs_error_i,
    input wire [3:0] fs_total_i,
    input wire [31:0] fs_cluster_i, fs_size_i,
    input wire [7:0] fs_data_i,
    input wire fs_valid_i, fs_client_done_i, fs_client_error_i,
    output wire quiescent,
    input wire initial_write_buf,
    input wire clk, rst, sd_init_done, sd_abort,
    input wire hold_load, write_finish_toggle, write_req_ack,
    output wire [3:0] state_code,
    output wire [31:0] debug_status,
    output reg display_valid, display_commit_toggle, display_commit_pulse,
    output reg [1:0] write_buf_idx, disp_buf_idx,
    output reg source_restart, load_done, write_req, pixel_valid,
    output reg [23:0] pixel_rgb,
    output wire sd_req,
    output wire [31:0] sd_addr,
    input wire [7:0] sd_data,
    input wire sd_valid, sd_done,
    output reg [7:0] error_code,
    output reg [15:0] frame_index,
    output reg [31:0] read_cycles_last
    ,output reg metadata_ready, audio_present
    ,output wire [31:0] audio_sector, audio_samples
);
    localparam START=0, SCAN=1, FILE_OPEN=2, HEADER_REQ=3, HEADER_WAIT=4,
               HEADER_CHECK=5, SIZE_CHECK=6, FRAME_PREP=7, WR_ACK=8,
               DATA_REQ=9, DATA_WAIT=10, SCALE_WAIT=11, RELEASE=12, REARM=13, SIZE_PREP=14, FAILED=15,
               SIZE_FACTOR=16, SIZE_VIDEO=17, SIZE_AUDIO=18, SIZE_TOTAL=19;
    reg [4:0] state;
    reg scan_start, file_start, client_req;
    reg [31:0] file_cluster, file_size, client_sector;
    reg [31:0] frame_first_sector;
    reg [31:0] header [0:10];
    wire version2=header[1][15:0]==16'd2;
    assign audio_sector=header[7];
    assign audio_samples=header[8];
    // N*225 和 N*4800 共享 N*15；每拍只有一次有界加减。
    // 所有派生长度取自已验证帧数，坏音轨字段不能驱动长度加法器。
    reg [19:0] frames15;
    reg [23:0] frames225, video_sectors;
    reg [22:0] samples75, audio_sectors;
    wire [31:0] required_samples={3'd0,samples75,6'd0};
    reg [24:0] total_sectors;
    reg [33:0] expected_size;
    reg [15:0] frame_count;
    reg [9:0] byte_count;
    reg [7:0] frame_sector;
    reg [7:0] pixel_low;
    reg [31:0] watchdog, read_cycles;
    reg release_seen;
    reg [2:0] rearm_count;
    reg [2:0] finish_sync;
    wire finish_pulse=finish_sync[2]^finish_sync[1];
    wire fs_busy, fs_done, fs_found;
    wire [7:0] fs_error, spc;
    wire [2:0] spc_shift;
    wire [31:0] fat_lba, data_lba, max_cluster, found_cluster, found_size;
    wire fs_req, map_req, client_done, client_error, client_valid;
    wire [31:0] fs_addr, map_addr;
    wire [7:0] client_data;
    reg owner_map;
    reg [8:0] physical_byte;
    wire ended=sd_done || sd_abort;
    wire fs_valid=sd_req && !owner_map && sd_valid;
    wire fs_end=sd_req && !owner_map && ended;
    wire map_valid=sd_req && owner_map && sd_valid;
    wire map_end=sd_req && owner_map && ended;
    assign state_code=state[3:0];
    assign debug_status={error_code,frame_index,state[3:0],4'd0};

    assign fs_scan_start_o=scan_start;
    assign fs_file_start_o=file_start;
    assign fs_client_req_o=client_req;
    assign fs_cluster_o=file_cluster;
    assign fs_size_o=file_size;
    assign fs_sector_o=client_sector;
    assign quiescent=(state==FRAME_PREP || state==RELEASE || state==FAILED) && !client_req && !sd_req;
    generate if(EXTERNAL_FS) begin : g_external_fs
        assign fs_busy=fs_busy_i;
        assign fs_done=fs_done_i;
        assign fs_error=fs_error_i;
        assign fs_found=fs_found_i;
        assign found_cluster=fs_cluster_i;
        assign found_size=fs_size_i;
        assign client_data=fs_data_i;
        assign client_valid=fs_valid_i;
        assign client_done=fs_client_done_i;
        assign client_error=fs_client_error_i;
        assign sd_req=1'b0;
        assign sd_addr=32'd0;
    end else begin : g_internal_fs
    reg req_r; reg [31:0] addr_r;
    assign sd_req=req_r; assign sd_addr=addr_r;
    fat32_bmp_index #(.MAX_IMAGES(1),.FILE_EXT("R16")) indexer(
        .clk(clk),.rst(rst || !sd_init_done),.scan_start(scan_start),.target_count(4'd1),
        .busy(fs_busy),.scan_done(fs_done),.error_code(fs_error),.partition_lba(),
        .sectors_per_cluster(spc),.sectors_per_cluster_shift(spc_shift),
        .fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
        .found_total(),.found_valid(fs_found),.found_cluster(found_cluster),.found_size(found_size),
        .wav_found(),.wav_sector(),.sector_req(fs_req),.sector_lba(fs_addr),.sector_busy(sd_req),
        .sector_valid(fs_valid),.sector_byte_index(physical_byte),.sector_byte(sd_data),
        .sector_done(fs_end),.sector_error(sd_abort ? 8'd1 : 8'd0));
    fat32_file_sector_mapper mapper(
        .clk(clk),.rst(rst || !sd_init_done),.file_start(file_start),
        .first_cluster(file_cluster),.file_size(file_size),.sectors_per_cluster(spc),
        .sectors_per_cluster_shift(spc_shift),.fat_start_lba(fat_lba),
        .data_start_lba(data_lba),.max_cluster(max_cluster),
        .client_req(client_req),.client_sector_index(client_sector),.busy(),
        .client_done(client_done),.client_error(client_error),.client_data(client_data),
        .client_data_valid(client_valid),.sector_req(map_req),.sector_lba(map_addr),
        .sector_busy(sd_req),.sector_valid(map_valid),.sector_byte_index(physical_byte),
        .sector_byte(sd_data),.sector_done(map_end),.sector_error(sd_abort ? 8'd1 : 8'd0));

    // 请求保持到物理扇区结束；owner和LBA在整个事务中不变。
    always @(posedge clk or posedge rst) begin
        if(rst) begin req_r<=0; addr_r<=0; physical_byte<=0; owner_map<=0; end
        else if(!sd_init_done) begin req_r<=0; physical_byte<=0; end
        else if(sd_req) begin
            if(sd_valid) physical_byte<=physical_byte+1'b1;
            if(ended) req_r<=0;
        end else if(fs_req || map_req) begin
            req_r<=1; owner_map<=!fs_req; addr_r<=fs_req ? fs_addr : map_addr; physical_byte<=0;
        end
    end

    end endgenerate

    task fail;
        input [7:0] code;
        begin
            state<=FAILED; error_code<=code; client_req<=0; write_req<=0;
            source_restart<=1; // 不产生load_done/commit，保持上一完整显示页。
        end
    endtask
    integer i;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=START; scan_start<=0; file_start<=0; client_req<=0;
            file_cluster<=0; file_size<=0; client_sector<=0; frame_first_sector<=1;
            frame_count<=0; frame_index<=0; frame_sector<=0; byte_count<=0;
            pixel_low<=0; pixel_valid<=0; pixel_rgb<=0; source_restart<=0; load_done<=0;
            write_req<=0; write_buf_idx<=0; disp_buf_idx<=0;
            display_valid<=0; display_commit_toggle<=0; display_commit_pulse<=0;
            finish_sync<=0; error_code<=0; watchdog<=0; release_seen<=0;
            expected_size<=0; frames15<=0; frames225<=0; video_sectors<=0;
            samples75<=0; audio_sectors<=0; total_sectors<=0;
            read_cycles<=0; read_cycles_last<=0; rearm_count<=0;
            metadata_ready<=0;audio_present<=0;
            for(i=0;i<11;i=i+1) header[i]<=0;
        end else begin
            scan_start<=0; file_start<=0; source_restart<=0; load_done<=0;
            pixel_valid<=0; display_commit_pulse<=0;
            finish_sync<={finish_sync[1:0],write_finish_toggle};
            if(state==DATA_REQ || state==DATA_WAIT) read_cycles<=read_cycles+1'b1;
            if(state==WR_ACK || state==SCALE_WAIT || state==HEADER_WAIT || state==DATA_WAIT)
                watchdog<=watchdog+1'b1;
            else watchdog<=0;
            if(fs_found) begin file_cluster<=found_cluster; file_size<=found_size; end
            if(!sd_init_done && state!=START && state!=FAILED) fail(8'h50);
            else if(sd_abort && state!=START && state!=FAILED) fail(8'h51);
            else if(watchdog>=CLK_FREQ_HZ/2) fail(8'h52);
            else case(state)
                START: if(sd_init_done) begin scan_start<=1; state<=SCAN; end
                SCAN: if(fs_done) begin
                    if(fs_error!=0 || file_size<512) fail(8'h40);
                    else state<=FILE_OPEN;
                end
                FILE_OPEN: begin file_start<=1; client_sector<=0; state<=HEADER_REQ; end
                HEADER_REQ: begin client_req<=1; byte_count<=0; state<=HEADER_WAIT; end
                HEADER_WAIT: begin
                    if(client_valid) begin
                        if(byte_count<44) header[byte_count[5:2]][{byte_count[1:0],3'b000} +: 8]<=client_data;
                        byte_count<=byte_count+1'b1;
                    end
                    if(client_done) begin
                        client_req<=0;
                        if(client_error || byte_count!=512) fail(8'h41);
                        else state<=HEADER_CHECK;
                    end
                end
                HEADER_CHECK: begin
                    if(header[0]!=32'h36315652 || header[1][31:16]!=16'd320 ||
                       (header[1][15:0]!=1 && !version2) ||
                       header[2]!={16'd10,16'd180} || header[3]==0 || header[3]>65535 ||
                       header[4]!=115200 || header[5]!=512 || header[6]!=1) fail(8'h42);
                    else begin
                        frame_count<=header[3][15:0];
                        state<=SIZE_FACTOR;
                    end
                end
                SIZE_FACTOR: begin
                    frames15<={frame_count,4'd0}-{4'd0,frame_count};
                    state<=SIZE_VIDEO;
                end
                SIZE_VIDEO: begin
                    frames225<={frames15,4'd0}-{4'd0,frames15};
                    samples75<=({3'd0,frames15}<<2)+{3'd0,frames15};
                    state<=SIZE_AUDIO;
                end
                SIZE_AUDIO: begin
                    video_sectors<=frames225+24'd1;
                    audio_sectors<={1'b0,samples75[22:1]}+samples75[0];
                    state<=SIZE_TOTAL;
                end
                SIZE_TOTAL: begin
                    total_sectors<={1'b0,video_sectors}+(version2 ? {2'd0,audio_sectors} : 25'd0);
                    state<=SIZE_PREP;
                end
                SIZE_PREP: begin
                    expected_size<={total_sectors,9'b0};
                    state<=SIZE_CHECK;
                end
                SIZE_CHECK: begin
                    if(expected_size!={2'b0,file_size} ||
                       (version2 && (header[7]!={8'd0,video_sectors} ||
                        header[8]!=required_samples || header[9]!=48000 || header[10]!=32'h00020010))) fail(8'h43);
                    else begin state<=FRAME_PREP;metadata_ready<=1;audio_present<=version2;end
                end
                FRAME_PREP: if(!hold_load && !write_req_ack) begin
                    // 完成门在restart后要求请求/旧ACK均低；不可同拍重启并请求。
                    source_restart<=1; write_req<=0; rearm_count<=7; state<=REARM;
                    if(SEED_ENABLE && !display_valid) write_buf_idx<={1'b0,initial_write_buf};
                    client_sector<=frame_first_sector; frame_sector<=0; read_cycles<=0;
                end
                REARM: if(rearm_count!=0) rearm_count<=rearm_count-1'b1;
                       else if(!write_req_ack) begin write_req<=1; state<=WR_ACK; end
                WR_ACK: if(write_req_ack) begin write_req<=0; state<=DATA_REQ; end
                DATA_REQ: begin client_req<=1; byte_count<=0; state<=DATA_WAIT; end
                DATA_WAIT: begin
                    if(client_valid) begin
                        byte_count<=byte_count+1'b1;
                        if(!byte_count[0]) pixel_low<=client_data;
                        else begin
                            // 位复制展开565；原src_packer截高位后逐位恢复原值。
                            pixel_rgb<={client_data[7:3],client_data[7:5],
                                       client_data[2:0],pixel_low[7:5],client_data[2:1],
                                       pixel_low[4:0],pixel_low[4:2]};
                            pixel_valid<=1;
                        end
                    end
                    if(client_done) begin
                        client_req<=0;
                        if(client_error || byte_count!=512) fail(8'h44);
                        else if(frame_sector==224) begin
                            load_done<=1; state<=SCALE_WAIT; read_cycles_last<=read_cycles;
                        end else begin
                            client_sector<=client_sector+1'b1; frame_sector<=frame_sector+1'b1;
                            state<=DATA_REQ;
                        end
                    end
                end
                SCALE_WAIT: if(finish_pulse) begin
                    display_valid<=1; display_commit_toggle<=~display_commit_toggle;
                    display_commit_pulse<=1; release_seen<=0; state<=RELEASE;
                end
                RELEASE: begin
                    if(hold_load) release_seen<=1;
                    if(release_seen && !hold_load) begin
                        disp_buf_idx<=write_buf_idx; write_buf_idx<={1'b0,~write_buf_idx[0]};
                        if(frame_index==frame_count-1'b1) begin
                            frame_index<=0; frame_first_sector<=1;
                            file_start<=1; // 回绕从簇链起点重新定位，不能假设文件连续。
                        end else begin frame_index<=frame_index+1'b1; frame_first_sector<=frame_first_sector+225; end
                        state<=FRAME_PREP;
                    end
                end
                FAILED: begin client_req<=0; write_req<=0; end
                default: fail(8'h5f);
            endcase
        end
    end
endmodule
