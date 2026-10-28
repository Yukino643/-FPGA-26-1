// FAT32 根目录索引：按目录项扩展名查找 BMP，不扫描卡上任意数据扇区。
module fat32_bmp_index #(
    parameter integer MAX_IMAGES = 8,
    parameter integer MAX_ROOT_CLUSTERS = 256,
    parameter integer TIMEOUT_CYCLES = 11_000_000,
    parameter integer INDEX_WAV = 0,
    parameter [23:0] FILE_EXT = "BMP",
    parameter RUNTIME_EXT = 0
) (
    input  wire [23:0] file_ext, // runtime extension stays fixed until next reset
    input  wire        clk,
    input  wire        rst,
    input  wire        scan_start,
    input  wire [3:0]  target_count,
    output wire        busy,
    output reg         scan_done,
    output reg  [7:0]  error_code,
    output reg  [31:0] partition_lba,
    output reg  [7:0]  sectors_per_cluster,
    output reg  [2:0]  sectors_per_cluster_shift,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] max_cluster,
    output reg  [3:0]  found_total,
    output reg         found_valid,
    output reg  [31:0] found_cluster,
    output reg  [31:0] found_size,
    output reg         wav_found,
    output reg  [31:0] wav_sector,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [8:0]  sector_byte_index,
    input  wire [7:0]  sector_byte,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);
    wire [23:0] selected_ext=RUNTIME_EXT ? file_ext : FILE_EXT;
    localparam [7:0] ERR_NONE       = 8'h00;
    localparam [7:0] ERR_SECTOR     = 8'h10;
    localparam [7:0] ERR_SIGNATURE = 8'h20;
    localparam [7:0] ERR_BPB        = 8'h21;
    localparam [7:0] ERR_NO_BMP     = 8'h22;
    localparam [7:0] ERR_CLUSTER    = 8'h24;
    localparam [7:0] ERR_CHAIN      = 8'h25;
    localparam [7:0] ERR_TIMEOUT    = 8'h30;

    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_MBR_REQ    = 4'd1;
    localparam [3:0] ST_MBR_WAIT   = 4'd2;
    localparam [3:0] ST_BPB_REQ    = 4'd3;
    localparam [3:0] ST_BPB_WAIT   = 4'd4;
    localparam [3:0] ST_BPB_PARSE  = 4'd5;
    localparam [3:0] ST_ROOT_REQ   = 4'd6;
    localparam [3:0] ST_ROOT_WAIT  = 4'd7;
    localparam [3:0] ST_FAT_REQ    = 4'd8;
    localparam [3:0] ST_FAT_WAIT   = 4'd9;
    localparam [3:0] ST_FAT_PARSE  = 4'd10;
    localparam [3:0] ST_MBR_CHECK  = 4'd11;
    localparam [3:0] ST_BPB_CHECK  = 4'd12;
    localparam [3:0] ST_BPB_GEOM1  = 4'd13;
    localparam [3:0] ST_BPB_GEOM2  = 4'd14;
    localparam [3:0] ST_BPB_GEOM3  = 4'd15;

    reg [3:0] state;
    reg [31:0] timeout_count;
    reg timeout_due;
    reg [31:0] root_cluster;
    reg [31:0] root_lba;
    reg [1:0]  root_address_phase;
    reg [31:0] root_cluster_base, root_sector_offset;
    reg [7:0]  root_sector_index;
    reg [8:0]  fat_entry_offset;
    reg [31:0] root_chain_steps;
    reg        dir_end_marker;
    reg        bpb_parse_final;

    reg [7:0]  mbr_jump;
    reg [7:0]  mbr_bps_lo, mbr_bps_hi;
    reg [7:0]  mbr_sig_lo, mbr_sig_hi;
    reg [7:0]  mbr_type0, mbr_type1, mbr_type2, mbr_type3;
    reg [31:0] mbr_start0, mbr_start1, mbr_start2, mbr_start3;

    reg [7:0]  bpb_sig_lo, bpb_sig_hi;
    reg [7:0]  bpb_bps_lo, bpb_bps_hi;
    reg [7:0]  bpb_spc;
    reg [7:0]  bpb_reserved_lo, bpb_reserved_hi;
    reg [7:0]  bpb_fat_count;
    reg [7:0]  bpb_root_entries_lo, bpb_root_entries_hi;
    reg [7:0]  bpb_total16_lo, bpb_total16_hi;
    reg [7:0]  bpb_fat16_lo, bpb_fat16_hi;
    reg [7:0]  bpb_total32_0, bpb_total32_1, bpb_total32_2, bpb_total32_3;
    reg [7:0]  bpb_fat32_0, bpb_fat32_1, bpb_fat32_2, bpb_fat32_3;
    reg [7:0]  bpb_root_0, bpb_root_1, bpb_root_2, bpb_root_3;
    reg [32:0] bpb_total_sectors_r, bpb_fat_span_r;
    reg [15:0] bpb_reserved_r;
    reg [31:0] bpb_fat32_r, bpb_root_cluster_r;
    reg [2:0]  bpb_spc_shift_r;
    reg [33:0] bpb_overhead_r, bpb_data_sectors_r;
    reg [33:0] bpb_volume_end_r, bpb_data_start_r;
    reg [39:0] bpb_fat_entries_r;
    reg [32:0] bpb_max_cluster_candidate;
    reg        bpb_total_overhead_ok_r;

    reg [7:0]  fat_byte0, fat_byte1, fat_byte2, fat_byte3;
    reg [7:0]  dir_name0, dir_ext0, dir_ext1, dir_ext2, dir_attr;
    reg [15:0] dir_cluster_hi, dir_cluster_lo;
    reg        dir_cluster_valid;
    reg [31:0] dir_size_23_0;
    reg        wav_candidate_valid;
    reg [31:0] wav_candidate_cluster;
    reg [31:0] wav_cluster_base, wav_sector_offset;
    reg        wav_publish_d1, wav_publish_d2;

    // 与扫描器同一时钟域；减法、移位和加法分拍，不延长目录项判定路径。
    // 扫描成功后才发布地址，失败扇区/超时不能把部分元数据交给播放器。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wav_cluster_base <= 0;
            wav_sector_offset <= 0;
            wav_sector <= 0;
            wav_publish_d1 <= 0;
            wav_publish_d2 <= 0;
            wav_found <= 0;
        end else if ((state == ST_IDLE) && scan_start) begin
            wav_cluster_base <= 0;
            wav_sector_offset <= 0;
            wav_sector <= 0;
            wav_publish_d1 <= 0;
            wav_publish_d2 <= 0;
            wav_found <= 0;
        end else begin
            wav_cluster_base <= wav_candidate_cluster - 32'd2;
            wav_sector_offset <= wav_cluster_base << sectors_per_cluster_shift;
            wav_sector <= data_start_lba + wav_sector_offset;
            wav_publish_d1 <= INDEX_WAV && scan_done && wav_candidate_valid &&
                              ((error_code == ERR_NONE) || (error_code == ERR_NO_BMP));
            wav_publish_d2 <= wav_publish_d1;
            wav_found <= wav_publish_d2;
        end
    end

    wire wait_sector = (state == ST_MBR_WAIT) || (state == ST_BPB_WAIT) ||
                       (state == ST_ROOT_WAIT) || (state == ST_FAT_WAIT);
    // 提前一拍比较，仅把单比特到期标志送入高扇出状态使能。
    // 与原计数阈值同拍超时，sector_done始终优先；兼容1拍超时参数。
    wire timeout_hit = wait_sector && !sector_done && timeout_due;
    wire mbr_direct_volume = ((mbr_jump == 8'he9) || (mbr_jump == 8'heb)) &&
                             ({mbr_bps_hi, mbr_bps_lo} == 16'd512);
    wire mbr_has_fat32 = (mbr_type0 == 8'h0b) || (mbr_type0 == 8'h0c) ||
                         (mbr_type1 == 8'h0b) || (mbr_type1 == 8'h0c) ||
                         (mbr_type2 == 8'h0b) || (mbr_type2 == 8'h0c) ||
                         (mbr_type3 == 8'h0b) || (mbr_type3 == 8'h0c);
    wire [31:0] mbr_first_partition =
        ((mbr_type0 == 8'h0b) || (mbr_type0 == 8'h0c)) ? mbr_start0 :
        ((mbr_type1 == 8'h0b) || (mbr_type1 == 8'h0c)) ? mbr_start1 :
        ((mbr_type2 == 8'h0b) || (mbr_type2 == 8'h0c)) ? mbr_start2 : mbr_start3;

    wire [15:0] bpb_bytes_per_sector = {bpb_bps_hi, bpb_bps_lo};
    wire [15:0] bpb_reserved = {bpb_reserved_hi, bpb_reserved_lo};
    wire [15:0] bpb_root_entries = {bpb_root_entries_hi, bpb_root_entries_lo};
    wire [15:0] bpb_total16 = {bpb_total16_hi, bpb_total16_lo};
    wire [15:0] bpb_fat16 = {bpb_fat16_hi, bpb_fat16_lo};
    wire [31:0] bpb_total32 = {bpb_total32_3, bpb_total32_2,
                               bpb_total32_1, bpb_total32_0};
    wire [31:0] bpb_fat32 = {bpb_fat32_3, bpb_fat32_2,
                             bpb_fat32_1, bpb_fat32_0};
    wire [31:0] bpb_root_cluster = {bpb_root_3, bpb_root_2,
                                    bpb_root_1, bpb_root_0};
    wire [32:0] bpb_total_sectors = (bpb_total16 != 0) ?
                                    {17'd0, bpb_total16} : {1'b0, bpb_total32};
    wire [32:0] bpb_fat_span = (bpb_fat_count == 2) ?
                               ({1'b0, bpb_fat32} << 1) : {1'b0, bpb_fat32};
    wire bpb_geometry_basic_check = (bpb_bytes_per_sector == 16'd512) &&
                                    valid_spc(bpb_spc) && (bpb_reserved != 0) &&
                                    ((bpb_fat_count == 1) || (bpb_fat_count == 2)) &&
                                    (bpb_root_entries == 0) && (bpb_fat16 == 0) &&
                                    (bpb_total_sectors != 0) && (bpb_fat32 != 0) &&
                                    (|bpb_root_cluster[31:1]);
    // BPB字段在WAIT收齐，CHECK检查签名，PARSE才消费基础校验。
    // 独立寄存隔离32位字段校验与finish_scan的状态/错误写使能。
    reg bpb_geometry_basic_valid;
    always @(posedge clk or posedge rst) begin
        if (rst) bpb_geometry_basic_valid <= 1'b0;
        else bpb_geometry_basic_valid <= bpb_geometry_basic_check;
    end
    wire bpb_geometry_derived_valid = bpb_total_overhead_ok_r &&
                                      (bpb_max_cluster_candidate <= 33'h0fffffff) &&
                                      (bpb_fat_entries_r > bpb_max_cluster_candidate) &&
                                      (bpb_volume_end_r <= 34'd4294967295) &&
                                      (bpb_data_start_r <= 34'd4294967295) &&
                                      (bpb_root_cluster_r <= bpb_max_cluster_candidate[31:0]);

    assign busy = (state != ST_IDLE);

    function valid_spc;
        input [7:0] value;
        begin
            valid_spc = (value != 0) && ((value & (value - 1'b1)) == 0);
        end
    endfunction

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case (value)
                8'd2: spc_shift = 3'd1;
                8'd4: spc_shift = 3'd2;
                8'd8: spc_shift = 3'd3;
                8'd16: spc_shift = 3'd4;
                8'd32: spc_shift = 3'd5;
                8'd64: spc_shift = 3'd6;
                8'd128: spc_shift = 3'd7;
                default: spc_shift = 3'd0;
            endcase
        end
    endfunction

    task finish_scan;
        input [7:0] error_value;
        begin
            error_code <= error_value;
            scan_done <= 1'b1;
            state <= ST_IDLE;
        end
    endtask

    // MBR采集独立于扫描完成/超时状态机；字节捕获与新扫描清零互斥，
    // 避免finish_scan的深层控制译码驱动整个分区表的清零/保持mux。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mbr_jump <= 8'd0;
            mbr_bps_lo <= 8'd0; mbr_bps_hi <= 8'd0;
            mbr_sig_lo <= 8'd0; mbr_sig_hi <= 8'd0;
            mbr_type0 <= 8'd0; mbr_type1 <= 8'd0;
            mbr_type2 <= 8'd0; mbr_type3 <= 8'd0;
            mbr_start0 <= 32'd0; mbr_start1 <= 32'd0;
            mbr_start2 <= 32'd0; mbr_start3 <= 32'd0;
        end else if ((state == ST_IDLE) && scan_start) begin
            mbr_jump <= 8'd0;
            mbr_bps_lo <= 8'd0;
            mbr_bps_hi <= 8'd0;
            mbr_sig_lo <= 8'd0;
            mbr_sig_hi <= 8'd0;
            mbr_type0 <= 8'd0; mbr_type1 <= 8'd0;
            mbr_type2 <= 8'd0; mbr_type3 <= 8'd0;
            mbr_start0 <= 32'd0; mbr_start1 <= 32'd0;
            mbr_start2 <= 32'd0; mbr_start3 <= 32'd0;
        end else if ((state == ST_MBR_WAIT) && sector_valid) begin
            case (sector_byte_index)
                9'd0:   mbr_jump <= sector_byte;
                9'd11:  mbr_bps_lo <= sector_byte;
                9'd12:  mbr_bps_hi <= sector_byte;
                9'd450: mbr_type0 <= sector_byte;
                9'd454: mbr_start0[7:0] <= sector_byte;
                9'd455: mbr_start0[15:8] <= sector_byte;
                9'd456: mbr_start0[23:16] <= sector_byte;
                9'd457: mbr_start0[31:24] <= sector_byte;
                9'd466: mbr_type1 <= sector_byte;
                9'd470: mbr_start1[7:0] <= sector_byte;
                9'd471: mbr_start1[15:8] <= sector_byte;
                9'd472: mbr_start1[23:16] <= sector_byte;
                9'd473: mbr_start1[31:24] <= sector_byte;
                9'd482: mbr_type2 <= sector_byte;
                9'd486: mbr_start2[7:0] <= sector_byte;
                9'd487: mbr_start2[15:8] <= sector_byte;
                9'd488: mbr_start2[23:16] <= sector_byte;
                9'd489: mbr_start2[31:24] <= sector_byte;
                9'd498: mbr_type3 <= sector_byte;
                9'd502: mbr_start3[7:0] <= sector_byte;
                9'd503: mbr_start3[15:8] <= sector_byte;
                9'd504: mbr_start3[23:16] <= sector_byte;
                9'd505: mbr_start3[31:24] <= sector_byte;
                9'd510: mbr_sig_lo <= sector_byte;
                9'd511: mbr_sig_hi <= sector_byte;
                default: ;
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            timeout_count <= 32'd0;
            timeout_due <= (TIMEOUT_CYCLES <= 1);
            scan_done <= 1'b0;
            error_code <= ERR_NONE;
            partition_lba <= 32'd0;
            sectors_per_cluster <= 8'd0;
            sectors_per_cluster_shift <= 3'd0;
            fat_start_lba <= 32'd0;
            data_start_lba <= 32'd0;
            max_cluster <= 32'd0;
            found_total <= 4'd0;
            found_valid <= 1'b0;
            found_cluster <= 32'd0;
            found_size <= 32'd0;
            wav_candidate_valid <= 1'b0;
            wav_candidate_cluster <= 32'd0;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            root_cluster <= 32'd0;
            root_lba <= 32'd0;
            root_address_phase <= 2'd0;
            root_cluster_base <= 32'd0;
            root_sector_offset <= 32'd0;
            root_sector_index <= 8'd0;
            fat_entry_offset <= 9'd0;
            root_chain_steps <= 32'd0;
            dir_end_marker <= 1'b0;
            bpb_parse_final <= 1'b0;
            bpb_sig_lo <= 8'd0; bpb_sig_hi <= 8'd0;
            bpb_bps_lo <= 8'd0; bpb_bps_hi <= 8'd0;
            bpb_spc <= 8'd0;
            bpb_reserved_lo <= 8'd0; bpb_reserved_hi <= 8'd0;
            bpb_fat_count <= 8'd0;
            bpb_root_entries_lo <= 8'd0; bpb_root_entries_hi <= 8'd0;
            bpb_total16_lo <= 8'd0; bpb_total16_hi <= 8'd0;
            bpb_fat16_lo <= 8'd0; bpb_fat16_hi <= 8'd0;
            bpb_total32_0 <= 8'd0; bpb_total32_1 <= 8'd0;
            bpb_total32_2 <= 8'd0; bpb_total32_3 <= 8'd0;
            bpb_fat32_0 <= 8'd0; bpb_fat32_1 <= 8'd0;
            bpb_fat32_2 <= 8'd0; bpb_fat32_3 <= 8'd0;
            bpb_root_0 <= 8'd0; bpb_root_1 <= 8'd0;
            bpb_root_2 <= 8'd0; bpb_root_3 <= 8'd0;
            bpb_total_sectors_r <= 33'd0;
            bpb_fat_span_r <= 33'd0;
            bpb_reserved_r <= 16'd0;
            bpb_fat32_r <= 32'd0;
            bpb_root_cluster_r <= 32'd0;
            bpb_spc_shift_r <= 3'd0;
            bpb_overhead_r <= 34'd0;
            bpb_data_sectors_r <= 34'd0;
            bpb_volume_end_r <= 34'd0;
            bpb_data_start_r <= 34'd0;
            bpb_fat_entries_r <= 40'd0;
            bpb_max_cluster_candidate <= 33'd0;
            bpb_total_overhead_ok_r <= 1'b0;
            fat_byte0 <= 8'd0; fat_byte1 <= 8'd0;
            fat_byte2 <= 8'd0; fat_byte3 <= 8'd0;
            dir_name0 <= 8'd0; dir_ext0 <= 8'd0;
            dir_ext1 <= 8'd0; dir_ext2 <= 8'd0;
            dir_attr <= 8'd0;
            dir_cluster_hi <= 16'd0; dir_cluster_lo <= 16'd0;
            dir_cluster_valid <= 1'b0;
            dir_size_23_0 <= 32'd0;
        end else begin
            sector_req <= 1'b0;
            found_valid <= 1'b0;

            if (wait_sector && !sector_done) begin
                timeout_due <= (TIMEOUT_CYCLES <= 1) || (timeout_count >= TIMEOUT_CYCLES - 2);
                if (!timeout_due)
                    timeout_count <= timeout_count + 1'b1;
            end else begin
                timeout_count <= 32'd0;
                timeout_due <= (TIMEOUT_CYCLES <= 1);
            end

            if (sector_valid) begin
                case (state)
                    ST_BPB_WAIT: begin
                        case (sector_byte_index)
                            9'd13: bpb_spc <= sector_byte;
                            9'd11: bpb_bps_lo <= sector_byte;
                            9'd12: bpb_bps_hi <= sector_byte;
                            9'd14: bpb_reserved_lo <= sector_byte;
                            9'd15: bpb_reserved_hi <= sector_byte;
                            9'd16: bpb_fat_count <= sector_byte;
                            9'd17: bpb_root_entries_lo <= sector_byte;
                            9'd18: bpb_root_entries_hi <= sector_byte;
                            9'd19: bpb_total16_lo <= sector_byte;
                            9'd20: bpb_total16_hi <= sector_byte;
                            9'd22: bpb_fat16_lo <= sector_byte;
                            9'd23: bpb_fat16_hi <= sector_byte;
                            9'd32: bpb_total32_0 <= sector_byte;
                            9'd33: bpb_total32_1 <= sector_byte;
                            9'd34: bpb_total32_2 <= sector_byte;
                            9'd35: bpb_total32_3 <= sector_byte;
                            9'd36: bpb_fat32_0 <= sector_byte;
                            9'd37: bpb_fat32_1 <= sector_byte;
                            9'd38: bpb_fat32_2 <= sector_byte;
                            9'd39: bpb_fat32_3 <= sector_byte;
                            9'd44: bpb_root_0 <= sector_byte;
                            9'd45: bpb_root_1 <= sector_byte;
                            9'd46: bpb_root_2 <= sector_byte;
                            9'd47: bpb_root_3 <= sector_byte;
                            9'd510: bpb_sig_lo <= sector_byte;
                            9'd511: bpb_sig_hi <= sector_byte;
                            default: ;
                        endcase
                    end
                    ST_ROOT_WAIT: begin
                        case (sector_byte_index[4:0])
                            5'd0: begin
                                dir_name0 <= sector_byte;
                                if (sector_byte == 8'd0)
                                    dir_end_marker <= 1'b1;
                            end
                            5'd8: dir_ext0 <= sector_byte;
                            5'd9: dir_ext1 <= sector_byte;
                            5'd10: dir_ext2 <= sector_byte;
                            5'd11: dir_attr <= sector_byte;
                            5'd20: dir_cluster_hi[7:0] <= sector_byte;
                            5'd21: dir_cluster_hi[15:8] <= sector_byte;
                            5'd26: dir_cluster_lo[7:0] <= sector_byte;
                            5'd27: dir_cluster_lo[15:8] <= sector_byte;
                            // 簇号在字节27接收完成。字节28提前比较，字节31才
                            // 发布目录项，切断宽比较到found_*写使能的组合路径。
                            // 即使sector_valid连续每拍有效，也有三个完整周期。
                            5'd28: begin
                                dir_size_23_0[7:0] <= sector_byte;
                                dir_cluster_valid <=
                                    ({dir_cluster_hi[11:0], dir_cluster_lo} >= 28'd2) &&
                                    ({dir_cluster_hi[11:0], dir_cluster_lo} <= max_cluster);
                            end
                            5'd29: dir_size_23_0[15:8] <= sector_byte;
                            5'd30: dir_size_23_0[23:16] <= sector_byte;
                            5'd31: begin
                                dir_size_23_0[31:24] <= sector_byte;
                                // 只索引根目录中的首个真实短文件项；遇00后的残留项无效。
                                if (INDEX_WAV && !wav_candidate_valid && !dir_end_marker &&
                                    (dir_name0 != 8'd0) && (dir_name0 != 8'he5) &&
                                    (dir_attr != 8'h0f) && !dir_attr[4] && !dir_attr[3] &&
                                    ((dir_ext0 == "W") || (dir_ext0 == "w")) &&
                                    ((dir_ext1 == "A") || (dir_ext1 == "a")) &&
                                    ((dir_ext2 == "V") || (dir_ext2 == "v")) &&
                                    dir_cluster_valid &&
                                    ({sector_byte, dir_size_23_0[23:0]} >= 32'd44)) begin
                                    wav_candidate_valid <= 1'b1;
                                    wav_candidate_cluster <= {4'd0, dir_cluster_hi[11:0], dir_cluster_lo};
                                end
                                if ((dir_name0 != 8'd0) && (dir_name0 != 8'he5) &&
                                    (dir_attr != 8'h0f) && !dir_attr[4] && !dir_attr[3] &&
                                    ((dir_ext0 == selected_ext[23:16]) || (dir_ext0 == (selected_ext[23:16] | 8'h20))) &&
                                    ((dir_ext1 == selected_ext[15:8]) || (dir_ext1 == (selected_ext[15:8] | 8'h20))) &&
                                    ((dir_ext2 == selected_ext[7:0]) || (dir_ext2 == (selected_ext[7:0] | 8'h20))) &&
                                    dir_cluster_valid &&
                                    ({sector_byte, dir_size_23_0[23:0]} != 0) &&
                                    (found_total < MAX_IMAGES)) begin
                                    found_cluster <= {dir_cluster_hi[11:0], dir_cluster_lo};
                                    found_size <= {sector_byte, dir_size_23_0[23:0]};
                                    found_total <= found_total + 1'b1;
                                    found_valid <= 1'b1;
                                end
                            end
                            default: ;
                        endcase
                    end
                    ST_FAT_WAIT: begin
                        if (sector_byte_index == fat_entry_offset)
                            fat_byte0 <= sector_byte;
                        else if (sector_byte_index == fat_entry_offset + 9'd1)
                            fat_byte1 <= sector_byte;
                        else if (sector_byte_index == fat_entry_offset + 9'd2)
                            fat_byte2 <= sector_byte;
                        else if (sector_byte_index == fat_entry_offset + 9'd3)
                            fat_byte3 <= sector_byte;
                    end
                    default: ;
                endcase
            end

            // 超时仅可能出现在四个WAIT态；不要让它参与所有解析寄存器的CE。
            // 末尾只覆盖状态/错误/完成标志，保持到期拍与sector_done优先级。
            begin
                case (state)
                    ST_IDLE: if (scan_start) begin
                        scan_done <= 1'b0;
                        error_code <= ERR_NONE;
                        found_total <= 4'd0;
                        wav_candidate_valid <= 1'b0;
                        wav_candidate_cluster <= 32'd0;
                        partition_lba <= 32'd0;
                        bpb_parse_final <= 1'b0;
                        sector_lba <= 32'd0;
                        state <= ST_MBR_REQ;
                    end
                    ST_MBR_REQ: if (!sector_busy) begin
                        sector_lba <= 32'd0;
                        sector_req <= 1'b1;
                        state <= ST_MBR_WAIT;
                    end
                    ST_MBR_WAIT: if (sector_done) begin
                        if (sector_error != 0)
                            finish_scan(ERR_SECTOR);
                        else
                            state <= ST_MBR_CHECK;
                    end
                    ST_MBR_CHECK: begin
                        if ((mbr_sig_lo != 8'h55) || (mbr_sig_hi != 8'haa))
                            finish_scan(ERR_SIGNATURE);
                        else if (mbr_direct_volume) begin
                            partition_lba <= 32'd0;
                            sector_lba <= 32'd0;
                            state <= ST_BPB_REQ;
                        end else if (mbr_has_fat32) begin
                            partition_lba <= mbr_first_partition;
                            sector_lba <= mbr_first_partition;
                            state <= ST_BPB_REQ;
                        end else
                            finish_scan(ERR_BPB);
                    end
                    ST_BPB_REQ: if (!sector_busy) begin
                        sector_req <= 1'b1;
                        state <= ST_BPB_WAIT;
                    end
                    ST_BPB_WAIT: if (sector_done) begin
                        if (sector_error != 0)
                            finish_scan(ERR_SECTOR);
                        else
                            state <= ST_BPB_CHECK;
                    end
                    ST_BPB_CHECK: begin
                        if (bpb_parse_final) begin
                            bpb_parse_final <= 1'b0;
                            if (!bpb_geometry_derived_valid) begin
                                finish_scan(ERR_BPB);
                            end else begin
                                data_start_lba <= bpb_data_start_r[31:0];
                                max_cluster <= bpb_max_cluster_candidate[31:0];
                                root_cluster <= bpb_root_cluster_r;
                                root_address_phase <= 2'd0;
                                root_sector_index <= 8'd0;
                                root_chain_steps <= 32'd1;
                                state <= ST_ROOT_REQ;
                            end
                        end else if ((bpb_sig_lo != 8'h55) || (bpb_sig_hi != 8'haa)) begin
                            finish_scan(ERR_SIGNATURE);
                        end else begin
                            state <= ST_BPB_PARSE;
                        end
                    end
                    ST_BPB_PARSE: begin
                        if (!bpb_geometry_basic_valid) begin
                            finish_scan(ERR_BPB);
                        end else begin
                            bpb_total_sectors_r <= bpb_total_sectors;
                            bpb_fat_span_r <= bpb_fat_span;
                            bpb_reserved_r <= bpb_reserved;
                            bpb_fat32_r <= bpb_fat32;
                            bpb_root_cluster_r <= bpb_root_cluster;
                            bpb_spc_shift_r <= spc_shift(bpb_spc);
                            sectors_per_cluster <= bpb_spc;
                            sectors_per_cluster_shift <= spc_shift(bpb_spc);
                            fat_start_lba <= partition_lba + bpb_reserved;
                            state <= ST_BPB_GEOM1;
                        end
                    end
                    ST_BPB_GEOM1: begin
                        bpb_overhead_r <= {18'd0, bpb_reserved_r} + {1'b0, bpb_fat_span_r};
                        bpb_volume_end_r <= {2'b0, partition_lba} + {1'b0, bpb_total_sectors_r};
                        bpb_fat_entries_r <= {8'd0, bpb_fat32_r} << 7;
                        state <= ST_BPB_GEOM2;
                    end
                    ST_BPB_GEOM2: begin
                        bpb_data_sectors_r <= {1'b0, bpb_total_sectors_r} - bpb_overhead_r;
                        bpb_data_start_r <= {2'b0, partition_lba} + bpb_overhead_r;
                        bpb_total_overhead_ok_r <=
                            ({1'b0, bpb_total_sectors_r} > bpb_overhead_r);
                        state <= ST_BPB_GEOM3;
                    end
                    ST_BPB_GEOM3: begin
                        bpb_max_cluster_candidate <=
                            (bpb_data_sectors_r >> bpb_spc_shift_r) + 33'd1;
                        bpb_parse_final <= 1'b1;
                        state <= ST_BPB_CHECK;
                    end
                    ST_ROOT_REQ: begin
                        // 根目录跨簇与WAV地址一样分拍；新簇在phase3前不得发请求。
                        // 同簇后续扇区复用已计算的root_lba，不重复计算。
                        case (root_address_phase)
                            2'd0: begin
                                root_cluster_base <= root_cluster - 32'd2;
                                root_address_phase <= 2'd1;
                            end
                            2'd1: begin
                                root_sector_offset <= root_cluster_base << sectors_per_cluster_shift;
                                root_address_phase <= 2'd2;
                            end
                            2'd2: begin
                                root_lba <= data_start_lba + root_sector_offset;
                                root_address_phase <= 2'd3;
                            end
                            default: if (!sector_busy) begin
                                dir_end_marker <= 1'b0;
                                sector_lba <= root_lba + root_sector_index;
                                sector_req <= 1'b1;
                                state <= ST_ROOT_WAIT;
                            end
                        endcase
                    end
                    ST_ROOT_WAIT: if (sector_done) begin
                        if (sector_error != 0)
                            finish_scan(ERR_SECTOR);
                        else if (dir_end_marker ||
                                 ((target_count != 0) && (found_total >= target_count) &&
                                  (!INDEX_WAV || wav_candidate_valid))) begin
                            finish_scan((found_total == 0) ? ERR_NO_BMP : ERR_NONE);
                        end else if (root_sector_index + 1'b1 < sectors_per_cluster) begin
                            root_sector_index <= root_sector_index + 1'b1;
                            state <= ST_ROOT_REQ;
                        end else begin
                            fat_entry_offset <= {root_cluster[6:0], 2'b00};
                            sector_lba <= fat_start_lba + (root_cluster >> 7);
                            state <= ST_FAT_REQ;
                        end
                    end
                    ST_FAT_REQ: if (!sector_busy) begin
                        sector_req <= 1'b1;
                        state <= ST_FAT_WAIT;
                    end
                    ST_FAT_WAIT: if (sector_done) begin
                        if (sector_error != 0)
                            finish_scan(ERR_SECTOR);
                        else
                            state <= ST_FAT_PARSE;
                    end
                    ST_FAT_PARSE: begin
                        if ({fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} >= 28'hffffff8) begin
                            finish_scan((found_total == 0) ? ERR_NO_BMP : ERR_NONE);
                        end else if ({fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} < 28'd2 ||
                                     {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} > max_cluster ||
                                     {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} == root_cluster ||
                                     root_chain_steps >= MAX_ROOT_CLUSTERS) begin
                            finish_scan(ERR_CHAIN);
                        end else begin
                            root_cluster <= {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
                            root_address_phase <= 2'd0;
                            root_sector_index <= 8'd0;
                            root_chain_steps <= root_chain_steps + 1'b1;
                            state <= ST_ROOT_REQ;
                        end
                    end
                    default: state <= ST_IDLE;
                endcase
            end
            if (timeout_hit)
                finish_scan(ERR_TIMEOUT);
        end
    end

endmodule
