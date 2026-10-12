// sd_card_bmp_g.v — TF 卡 BMP 扫描/轮播时序控制（泛化版，W3）
// 基于官方 sd_card_bmp：双缓冲提交/页翻转握手逻辑保持一致；
//   1. 通过 FAT32 根目录索引图片，按文件簇链读取，避免全卡原始扇区扫描
//   2. bmp_read_g 继续负责 BMP 头校验、行 padding 剥离与 RGB 解码
//   3. 保留双缓冲提交和最多 8 张图片的轮播控制
module sd_card_bmp_g #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [3:0]   SCAN_TARGET_COUNT = 4'd8,
    parameter EXACT_WIDTH = 0, EXACT_HEIGHT = 0
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        key_next,
    input  wire        key_auto,
    input  wire        hold_load,     // 转场期间暂缓新装载（W5 transition_ctrl）
    output [3:0]       state_code,
    output reg  [3:0]  img_count,      // 扫描到的图片数
    output reg  [15:0] cur_img_w,      // 当前显示图宽
    output reg  [15:0] cur_img_h,      // 当前显示图高
    output reg         display_valid,   // 首图提交前置 0（黑屏防花）
    output wire        load_done,
    output wire [15:0] load_img_w,
    output wire [15:0] load_img_h,
    output reg         display_commit_toggle, // 仅成功事务翻转，供视频域同步
    output wire        display_commit_pulse,  // SD同域成功事件，立即锁住装载
    output wire        source_restart, // 新事务或错误时清空像素打包残留
    output wire [31:0] debug_status,  // 只读状态总线，供板级诊断使用

    input  wire        write_finish_toggle,
    output reg  [1:0]  write_buf_idx,
    output reg  [1:0]  disp_buf_idx,

    output             write_req,
    input  wire        write_req_ack,
    output             write_en,
    output [23:0]      write_data,
    input  wire        sd_init_done,
    input  wire        sd_sec_read_abort,
    output wire        sd_sec_read,
    output wire [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end
);

    assign source_restart = load_start_pulse | bmp_load_error;

    wire key_next_press;
    wire key_auto_press;

    wire             bmp_data_wr_en;
    wire [23:0]      bmp_data;
    wire             bmp_ready;
    wire             bmp_load_error;
    wire [3:0]       bmp_error_code;
    wire             scan_done;
    wire             scan_found_valid;
    wire [31:0]      scan_found_cluster;
    wire [31:0]      scan_found_size;
    wire [3:0]       scan_found_total;
    wire             fs_scan_busy;
    wire [7:0]       fs_scan_error;
    wire [7:0]       fs_sectors_per_cluster;
    wire [2:0]       fs_spc_shift;
    wire [31:0]      fs_fat_start_lba;
    wire [31:0]      fs_data_start_lba;
    wire [31:0]      fs_max_cluster;
    wire [3:0]       bmp_state_code;
    wire             bmp_client_req;
    wire [31:0]      bmp_client_sector;
    wire [7:0]       bmp_client_data;
    wire             bmp_client_data_valid;
    wire             bmp_client_done;
    wire             bmp_client_error;
    wire             fs_sector_req;
    wire [31:0]      fs_sector_lba;
    wire             map_sector_req;
    wire [31:0]      map_sector_lba;
    wire             fs_sector_done;
    wire             map_sector_done;
    wire             fs_sector_valid;
    wire             map_sector_valid;
    wire [7:0]       fs_sector_error;
    wire [7:0]       map_sector_error;

    reg              scan_start_pulse;
    reg              load_start_pulse;
    reg [31:0]       load_sector;
    reg [31:0]       load_cluster;
    reg [31:0]       load_file_size;
    reg              physical_read_active;
    reg              physical_read_owner_map;
    reg [31:0]       physical_read_lba;
    reg [8:0]        physical_read_byte_index;
    reg              scan_kicked;
    reg              first_image_committed;
    reg              auto_play_en;
    reg [31:0]       auto_cnt;
    reg [3:0]        img_found_count;
    reg [3:0]        img_idx;             // 当前显示中的图片编号
    reg [3:0]        load_idx;            // 当前正在装载的图片编号
    reg [1:0]        pending_buf_idx;
    reg [31:0]       img_cluster0, img_cluster1, img_cluster2, img_cluster3;
    reg [31:0]       img_cluster4, img_cluster5, img_cluster6, img_cluster7;
    reg [31:0]       img_size0, img_size1, img_size2, img_size3;
    reg [31:0]       img_size4, img_size5, img_size6, img_size7;
    reg [7:0]        next_req_count;     // KEY2 待处理请求计数，饱和避免连续按键丢失
    reg              load_busy;
    reg              source_done_seen;
    reg              write_finish_seen;
    reg              load_retry_used;
    reg              load_fault;
    reg [7:0]        failed_mask;        // 已重试仍失败的图片，避免轮播反复卡在坏图

    reg [2:0]        wrfin_tgl_sync;
    wire             write_finish_pulse;

    wire auto_tick;
    wire [3:0] next_from_current;
    wire [3:0] first_good_image;
    wire        any_good_image;

    // [27:20]坏图掩码，[19:16]状态，[15:12]错误，[11:8]发现数，[7:0]阶段标志。
    assign debug_status = {4'd0, failed_mask, state_code,
                           (fs_scan_error != 0) ? scan_error_display_code : bmp_error_code,
                           img_found_count,
                           any_good_image, first_image_committed, display_valid,
                           load_retry_used, load_fault, source_done_seen, load_busy, scan_done};
    assign write_en   = bmp_data_wr_en;
    // bmp_read_g 已按 {R,G,B} 输出；保持 24 位接口，禁止 32→24 位截断丢失 R 分量。
    assign write_data = bmp_data;
    assign state_code = fs_scan_busy ? 4'd2 :
                        ((fs_scan_error != 0) ? 4'he : bmp_state_code);
    assign scan_done = fat_index_done;
    assign sd_sec_read = physical_read_active;
    assign sd_sec_read_addr = physical_read_lba;

    wire fat_index_done;
    wire [31:0] selected_cluster;
    wire [31:0] selected_file_size;
    wire [3:0]  scan_error_display_code =
        (fs_scan_error == 8'h10) ? 4'd1 :
        (fs_scan_error == 8'h20) ? 4'd2 :
        (fs_scan_error == 8'h21) ? 4'd3 :
        (fs_scan_error == 8'h22) ? 4'd4 :
        (fs_scan_error == 8'h24) ? 4'd5 :
        (fs_scan_error == 8'h25) ? 4'd6 :
        (fs_scan_error == 8'h30) ? 4'd7 : 4'hf;
    assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));
    assign next_from_current = next_good_index(img_idx, img_found_count, failed_mask);
    assign first_good_image  = first_good_index(img_found_count, failed_mask);
    assign any_good_image    = has_good_image(img_found_count, failed_mask);
    // 手动切图事件独立于装载/转场状态；请求先入饱和计数器，空闲时逐个消费。
    wire manual_next_press = key_next_press && scan_done && (img_found_count > 4'd0);
    wire manual_next_start = scan_done && bmp_ready && display_valid && !load_busy
                           && (next_req_count != 8'd0)
                           && (img_found_count != 4'd0) && any_good_image && !hold_load;
    assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
    assign display_commit_pulse = sd_init_done && scan_kicked && load_busy && !bmp_load_error
                                  && (source_done_seen || load_done)
                                  && (write_finish_seen || write_finish_pulse);

    key_press_debounce #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .DEBOUNCE_MS (20)
    ) u_key_next (
        .clk        (clk),
        .rst        (rst),
        .button_in  (key_next),
        .press_pulse(key_next_press)
    );

    key_press_debounce #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .DEBOUNCE_MS (20)
    ) u_key_auto (
        .clk        (clk),
        .rst        (rst),
        .button_in  (key_auto),
        .press_pulse(key_auto_press)
    );

    function [3:0] next_index_limited;
        input [3:0] cur;
        input [3:0] count;
        begin
            if (count < 4'd2)          next_index_limited = 4'd0;
            else if (cur >= count - 4'd1) next_index_limited = 4'd0;
            else                       next_index_limited = cur + 4'd1;
        end
    endfunction

    // 从当前图之后循环寻找未被标记为坏图的候选。
    // 使用显式 case 而不是可变下标 + for 循环，避免 TD 将搜索展开成
    // 深层加法/比较链，影响 100 MHz SD 时钟域 setup。
    function [3:0] next_good_index;
        input [3:0] cur;
        input [3:0] count;
        input [7:0] bad;
        begin
            // 没有其他好图时保留当前有效图，禁止回退到被屏蔽的0号图。
            next_good_index = first_good_index(count, bad);
            case (cur)
                4'd0: begin
                    if ((count > 4'd1) && !bad[1]) next_good_index = 4'd1;
                    else if ((count > 4'd2) && !bad[2]) next_good_index = 4'd2;
                    else if ((count > 4'd3) && !bad[3]) next_good_index = 4'd3;
                    else if ((count > 4'd4) && !bad[4]) next_good_index = 4'd4;
                    else if ((count > 4'd5) && !bad[5]) next_good_index = 4'd5;
                    else if ((count > 4'd6) && !bad[6]) next_good_index = 4'd6;
                    else if ((count > 4'd7) && !bad[7]) next_good_index = 4'd7;
                end
                4'd1: begin
                    if ((count > 4'd2) && !bad[2]) next_good_index = 4'd2;
                    else if ((count > 4'd3) && !bad[3]) next_good_index = 4'd3;
                    else if ((count > 4'd4) && !bad[4]) next_good_index = 4'd4;
                    else if ((count > 4'd5) && !bad[5]) next_good_index = 4'd5;
                    else if ((count > 4'd6) && !bad[6]) next_good_index = 4'd6;
                    else if ((count > 4'd7) && !bad[7]) next_good_index = 4'd7;
                    else if (!bad[0]) next_good_index = 4'd0;
                end
                4'd2: begin
                    if ((count > 4'd3) && !bad[3]) next_good_index = 4'd3;
                    else if ((count > 4'd4) && !bad[4]) next_good_index = 4'd4;
                    else if ((count > 4'd5) && !bad[5]) next_good_index = 4'd5;
                    else if ((count > 4'd6) && !bad[6]) next_good_index = 4'd6;
                    else if ((count > 4'd7) && !bad[7]) next_good_index = 4'd7;
                    else if (!bad[0]) next_good_index = 4'd0;
                    else if (!bad[1]) next_good_index = 4'd1;
                end
                4'd3: begin
                    if ((count > 4'd4) && !bad[4]) next_good_index = 4'd4;
                    else if ((count > 4'd5) && !bad[5]) next_good_index = 4'd5;
                    else if ((count > 4'd6) && !bad[6]) next_good_index = 4'd6;
                    else if ((count > 4'd7) && !bad[7]) next_good_index = 4'd7;
                    else if (!bad[0]) next_good_index = 4'd0;
                    else if (!bad[1]) next_good_index = 4'd1;
                    else if (!bad[2]) next_good_index = 4'd2;
                end
                4'd4: begin
                    if ((count > 4'd5) && !bad[5]) next_good_index = 4'd5;
                    else if ((count > 4'd6) && !bad[6]) next_good_index = 4'd6;
                    else if ((count > 4'd7) && !bad[7]) next_good_index = 4'd7;
                    else if (!bad[0]) next_good_index = 4'd0;
                    else if (!bad[1]) next_good_index = 4'd1;
                    else if (!bad[2]) next_good_index = 4'd2;
                    else if (!bad[3]) next_good_index = 4'd3;
                end
                4'd5: begin
                    if ((count > 4'd6) && !bad[6]) next_good_index = 4'd6;
                    else if ((count > 4'd7) && !bad[7]) next_good_index = 4'd7;
                    else if (!bad[0]) next_good_index = 4'd0;
                    else if (!bad[1]) next_good_index = 4'd1;
                    else if (!bad[2]) next_good_index = 4'd2;
                    else if (!bad[3]) next_good_index = 4'd3;
                    else if (!bad[4]) next_good_index = 4'd4;
                end
                4'd6: begin
                    if ((count > 4'd7) && !bad[7]) next_good_index = 4'd7;
                    else if (!bad[0]) next_good_index = 4'd0;
                    else if (!bad[1]) next_good_index = 4'd1;
                    else if (!bad[2]) next_good_index = 4'd2;
                    else if (!bad[3]) next_good_index = 4'd3;
                    else if (!bad[4]) next_good_index = 4'd4;
                    else if (!bad[5]) next_good_index = 4'd5;
                end
                default: begin
                    if (!bad[0]) next_good_index = 4'd0;
                    else if (!bad[1]) next_good_index = 4'd1;
                    else if (!bad[2]) next_good_index = 4'd2;
                    else if (!bad[3]) next_good_index = 4'd3;
                    else if (!bad[4]) next_good_index = 4'd4;
                    else if (!bad[5]) next_good_index = 4'd5;
                    else if (!bad[6]) next_good_index = 4'd6;
                end
            endcase
        end
    endfunction

    function [3:0] first_good_index;
        input [3:0] count;
        input [7:0] bad;
        begin
            if ((count > 4'd0) && !bad[0]) first_good_index = 4'd0;
            else if ((count > 4'd1) && !bad[1]) first_good_index = 4'd1;
            else if ((count > 4'd2) && !bad[2]) first_good_index = 4'd2;
            else if ((count > 4'd3) && !bad[3]) first_good_index = 4'd3;
            else if ((count > 4'd4) && !bad[4]) first_good_index = 4'd4;
            else if ((count > 4'd5) && !bad[5]) first_good_index = 4'd5;
            else if ((count > 4'd6) && !bad[6]) first_good_index = 4'd6;
            else first_good_index = 4'd7;
        end
    endfunction

    function has_good_image;
        input [3:0] count;
        input [7:0] bad;
        integer i;
        begin
            has_good_image = 1'b0;
            for (i = 0; i < 8; i = i + 1)
                if ((i < count) && !bad[i])
                    has_good_image = 1'b1;
        end
    endfunction

    function [31:0] cluster_lut;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: cluster_lut = img_cluster0;
                4'd1: cluster_lut = img_cluster1;
                4'd2: cluster_lut = img_cluster2;
                4'd3: cluster_lut = img_cluster3;
                4'd4: cluster_lut = img_cluster4;
                4'd5: cluster_lut = img_cluster5;
                4'd6: cluster_lut = img_cluster6;
                default: cluster_lut = img_cluster7;
            endcase
        end
    endfunction

    function [31:0] size_lut;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: size_lut = img_size0;
                4'd1: size_lut = img_size1;
                4'd2: size_lut = img_size2;
                4'd3: size_lut = img_size3;
                4'd4: size_lut = img_size4;
                4'd5: size_lut = img_size5;
                4'd6: size_lut = img_size6;
                default: size_lut = img_size7;
            endcase
        end
    endfunction

    assign selected_cluster = load_cluster;
    assign selected_file_size = load_file_size;

    function [1:0] next_buf_lut;
        input [1:0] cur_disp_buf;
        input       valid_now;
        begin
            if (!valid_now)           next_buf_lut = 2'd0;
            else if (cur_disp_buf == 2'd0) next_buf_lut = 2'd1;
            else                      next_buf_lut = 2'd0;
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wrfin_tgl_sync        <= 3'b000;
            scan_start_pulse      <= 1'b0;
            load_start_pulse      <= 1'b0;
            load_sector           <= 32'd0;
            load_cluster          <= 32'd0;
            load_file_size        <= 32'd0;
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            display_commit_toggle <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 4'd0;
            img_idx               <= 4'd0;
            load_idx              <= 4'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_cluster0          <= 32'd0; img_cluster1 <= 32'd0;
            img_cluster2          <= 32'd0; img_cluster3 <= 32'd0;
            img_cluster4          <= 32'd0; img_cluster5 <= 32'd0;
            img_cluster6          <= 32'd0; img_cluster7 <= 32'd0;
            img_size0             <= 32'd0; img_size1 <= 32'd0;
            img_size2             <= 32'd0; img_size3 <= 32'd0;
            img_size4             <= 32'd0; img_size5 <= 32'd0;
            img_size6             <= 32'd0; img_size7 <= 32'd0;
            img_count             <= 4'd0;
            cur_img_w             <= 16'd0;
            cur_img_h             <= 16'd0;
            next_req_count        <= 8'd0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            write_finish_seen <= 1'b0;
            load_retry_used       <= 1'b0;
            load_fault            <= 1'b0;
            failed_mask           <= 8'd0;
            display_valid         <= 1'b0;
        end else begin
            wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
            scan_start_pulse <= 1'b0;
            load_start_pulse <= 1'b0;

            if (!sd_init_done) begin
                scan_kicked           <= 1'b0;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 4'd0;
                img_idx               <= 4'd0;
                load_idx              <= 4'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                img_count             <= 4'd0;
                cur_img_w             <= 16'd0;
                cur_img_h             <= 16'd0;
                next_req_count        <= 8'd0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_finish_seen <= 1'b0;
                load_retry_used       <= 1'b0;
                load_fault            <= 1'b0;
                failed_mask           <= 8'd0;
                display_valid         <= 1'b0;
            end else begin
                // 扫描阶段缓存根目录项给出的首簇与文件长度。
                if (scan_found_valid && (img_found_count < SCAN_TARGET_COUNT)) begin
                    case (img_found_count)
                        4'd0: begin img_cluster0 <= scan_found_cluster; img_size0 <= scan_found_size; end
                        4'd1: begin img_cluster1 <= scan_found_cluster; img_size1 <= scan_found_size; end
                        4'd2: begin img_cluster2 <= scan_found_cluster; img_size2 <= scan_found_size; end
                        4'd3: begin img_cluster3 <= scan_found_cluster; img_size3 <= scan_found_size; end
                        4'd4: begin img_cluster4 <= scan_found_cluster; img_size4 <= scan_found_size; end
                        4'd5: begin img_cluster5 <= scan_found_cluster; img_size5 <= scan_found_size; end
                        4'd6: begin img_cluster6 <= scan_found_cluster; img_size6 <= scan_found_size; end
                        default: begin img_cluster7 <= scan_found_cluster; img_size7 <= scan_found_size; end
                    endcase
                    img_found_count <= img_found_count + 4'd1;
                end

                // 错误事务必须有界：自动重试一次，仍失败则放弃本次装载并保留当前显示。
                if (load_busy && bmp_load_error) begin
                    source_done_seen <= 1'b0;
                    write_finish_seen <= 1'b0;
                    if (!load_retry_used) begin
                        load_retry_used  <= 1'b1;
                        load_start_pulse <= 1'b1;
                    end else begin
                        load_retry_used <= 1'b0;
                        load_busy       <= 1'b0;
                        load_fault      <= 1'b1;
                        failed_mask[load_idx] <= 1'b1;
                        // 失败事务不提交目标页；下一拍自动寻找下一张可用图片，
                        // 若当前正处于转场则由 hold_load 暂挂该请求。
                        if (next_req_count == 8'd0) next_req_count <= 8'd1;
                    end
                end

                // 只锁存本次装载的真实完成事件；ready 只是空闲状态，不能替代事务完成。
                if (load_busy && !bmp_load_error && load_done)
                    source_done_seen <= 1'b1;
                if (load_busy && !bmp_load_error && write_finish_pulse)
                    write_finish_seen <= 1'b1;

                // 收到 write_finish_toggle 脉冲才提交新图并切换显示缓冲
                // 两端完成事件均锁存，容许先后或同拍；错误不得提交半成品页。
                if (display_commit_pulse) begin
                    display_commit_toggle <= ~display_commit_toggle;
                    load_busy             <= 1'b0;
                    source_done_seen      <= 1'b0;
                    write_finish_seen <= 1'b0;
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    cur_img_w             <= load_img_w;
                    cur_img_h             <= load_img_h;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                    load_fault            <= 1'b0;
                end

                // FAT32 扫描错误也保留在诊断状态中，避免无图/坏 BPB 只呈现为黑屏。
                if (scan_done && (fs_scan_error != 0))
                    load_fault <= 1'b1;

                if (!scan_kicked && bmp_ready) begin
                    scan_start_pulse      <= 1'b1;
                    scan_kicked           <= 1'b1;
                    first_image_committed <= 1'b0;
                    auto_play_en          <= 1'b0;
                    auto_cnt              <= 32'd0;
                    img_found_count       <= 4'd0;
                    img_idx               <= 4'd0;
                    load_idx              <= 4'd0;
                    pending_buf_idx       <= 2'd0;
                    write_buf_idx         <= 2'd0;
                    disp_buf_idx          <= 2'd0;
                    next_req_count        <= 8'd0;
                    display_valid         <= 1'b0;
                    load_busy             <= 1'b0;
                    source_done_seen      <= 1'b0;
                    write_finish_seen <= 1'b0;
                    load_retry_used       <= 1'b0;
                    load_fault            <= 1'b0;
                    failed_mask           <= 8'd0;
                end else begin
                    // 即使正在读卡、缩放或转场，也缓存按键请求（最多积压255次，累计切图次数不限）。
                    // manual_next_start 分支在本拍消费一个请求，因此同拍按键已单独合并处理。
                    if (manual_next_press && !manual_next_start && (next_req_count < 8'd255))
                        next_req_count <= next_req_count + 8'd1;

                    // 全部图片被本轮错误屏蔽后，新的手动按键开启一次有界重试。
                    // 自动积压请求不清屏蔽，避免无卡/坏图导致无限自动重读。
                    if (manual_next_press && !load_busy && !any_good_image)
                        failed_mask <= 8'd0;

                    if (key_auto_press && scan_done && (img_found_count > 4'd1)) begin
                        auto_play_en <= ~auto_play_en;
                        auto_cnt     <= 32'd0;
                    end

                    if (scan_done && auto_play_en && display_valid && !load_busy && first_image_committed && (img_found_count > 4'd1)) begin
                        if (auto_tick)
                            auto_cnt <= 32'd0;
                        else
                            auto_cnt <= auto_cnt + 32'd1;
                    end else begin
                        auto_cnt <= 32'd0;
                    end

                    if (scan_done && !first_image_committed && bmp_ready && !load_busy
                        && (img_found_count != 4'd0) && any_good_image) begin
                        load_idx         <= first_good_image;
                        load_sector      <= 32'd0;
                        load_cluster     <= cluster_lut(first_good_image);
                        load_file_size   <= size_lut(first_good_image);
                        pending_buf_idx  <= 2'd0;
                        write_buf_idx    <= 2'd0;
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        write_finish_seen <= 1'b0;
                        load_retry_used  <= 1'b0;
                        // 首图装载期间仍允许缓存 KEY2 请求，不能在这里清空计数。
                        auto_cnt         <= 32'd0;
                        img_count        <= img_found_count;
                    end
                    else if (manual_next_start) begin
                        load_idx         <= next_from_current;
                        load_sector      <= 32'd0;
                        load_cluster     <= cluster_lut(next_from_current);
                        load_file_size   <= size_lut(next_from_current);
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        write_finish_seen <= 1'b0;
                        load_retry_used  <= 1'b0;
                        // 本次启动消费一个请求；同拍的新按键与消费合并，计数不回退。
                        if (!manual_next_press)
                            next_req_count <= next_req_count - 8'd1;
                        else if (next_req_count < 8'd255)
                            next_req_count <= next_req_count;
                        auto_cnt         <= 32'd0;
                    end
                    else if (scan_done && bmp_ready && display_valid && !load_busy && auto_play_en && auto_tick
                             && (img_found_count > 4'd1) && any_good_image && !hold_load) begin
                        load_idx         <= next_from_current;
                        load_sector      <= 32'd0;
                        load_cluster     <= cluster_lut(next_from_current);
                        load_file_size   <= size_lut(next_from_current);
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        write_finish_seen <= 1'b0;
                        load_retry_used  <= 1'b0;
                        auto_cnt         <= 32'd0;
                    end
                end
            end
        end
    end

    bmp_read_g #(
        .EXACT_WIDTH(EXACT_WIDTH), .EXACT_HEIGHT(EXACT_HEIGHT),
        .MAX_IMAGES (8),
        .MAX_DIM    (2047)
    ) bmp_read_g_m0 (
        .clk                    (clk),
        .rst                    (rst),
        .ready                  (bmp_ready),

        .scan_start             (1'b0),
        .scan_start_sector      (32'd0),
        .scan_max_sector        (32'd0),
        .scan_target_count      (4'd0),
        .scan_done              (),
        .scan_found_valid       (),
        .scan_found_sector      (),
        .scan_found_total       (),
        .scan_found_w           (),
        .scan_found_h           (),

        .load_start             (load_start_pulse),
        .load_sector            (load_sector),
        .load_done              (load_done),
        .load_error             (bmp_load_error),
        .error_code             (bmp_error_code),
        .load_active            (),
        .load_img_w             (load_img_w),
        .load_img_h             (load_img_h),

        .sd_init_done           (sd_init_done),
        .state_code             (bmp_state_code),

        .write_req              (write_req),
        .write_req_ack          (write_req_ack),

        .sd_sec_read            (bmp_client_req),
        .sd_sec_read_addr       (bmp_client_sector),
        .sd_sec_read_data       (bmp_client_data),
        .sd_sec_read_data_valid (bmp_client_data_valid),
        .sd_sec_read_end        (bmp_client_done),
        .sd_sec_read_error      (bmp_client_error),

        .bmp_data_wr_en         (bmp_data_wr_en),
        .bmp_data               (bmp_data)
    );

    fat32_bmp_index #(
        .MAX_IMAGES (8),
        .MAX_ROOT_CLUSTERS (256)
    ) u_fat32_bmp_index (
        .clk (clk),
        .rst (rst | ~sd_init_done),
        .scan_start (scan_start_pulse),
        .target_count (SCAN_TARGET_COUNT),
        .busy (fs_scan_busy),
        .scan_done (fat_index_done),
        .error_code (fs_scan_error),
        .partition_lba (),
        .sectors_per_cluster (fs_sectors_per_cluster),
        .sectors_per_cluster_shift (fs_spc_shift),
        .fat_start_lba (fs_fat_start_lba),
        .data_start_lba (fs_data_start_lba),
        .max_cluster (fs_max_cluster),
        .found_total (scan_found_total),
        .found_valid (scan_found_valid),
        .found_cluster (scan_found_cluster),
        .found_size (scan_found_size),
        .sector_req (fs_sector_req),
        .sector_lba (fs_sector_lba),
        .sector_busy (physical_read_active),
        .sector_valid (fs_sector_valid),
        .sector_byte_index (physical_read_byte_index),
        .sector_byte (sd_sec_read_data),
        .sector_done (fs_sector_done),
        .sector_error (fs_sector_error)
    );

    fat32_file_sector_mapper u_fat32_file_sector_mapper (
        .clk (clk),
        .rst (rst | ~sd_init_done),
        .file_start (load_start_pulse),
        .first_cluster (selected_cluster),
        .file_size (selected_file_size),
        .sectors_per_cluster (fs_sectors_per_cluster),
        .sectors_per_cluster_shift (fs_spc_shift),
        .fat_start_lba (fs_fat_start_lba),
        .data_start_lba (fs_data_start_lba),
        .max_cluster (fs_max_cluster),
        .client_req (bmp_client_req),
        .client_sector_index (bmp_client_sector),
        .busy (),
        .client_done (bmp_client_done),
        .client_error (bmp_client_error),
        .client_data (bmp_client_data),
        .client_data_valid (bmp_client_data_valid),
        .sector_req (map_sector_req),
        .sector_lba (map_sector_lba),
        .sector_busy (physical_read_active),
        .sector_valid (map_sector_valid),
        .sector_byte_index (physical_read_byte_index),
        .sector_byte (sd_sec_read_data),
        .sector_done (map_sector_done),
        .sector_error (map_sector_error)
    );

    assign fs_sector_valid = physical_read_active &&
                             !physical_read_owner_map && sd_sec_read_data_valid;
    assign map_sector_valid = physical_read_active &&
                              physical_read_owner_map && sd_sec_read_data_valid;
    assign fs_sector_done = physical_read_active && !physical_read_owner_map &&
                            (sd_sec_read_end || sd_sec_read_abort);
    assign map_sector_done = physical_read_active && physical_read_owner_map &&
                             (sd_sec_read_end || sd_sec_read_abort);
    assign fs_sector_error = sd_sec_read_abort ? 8'h01 : 8'h00;
    assign map_sector_error = sd_sec_read_abort ? 8'h01 : 8'h00;

    // 目录扫描和文件装载串行使用 SD 卡；事务期间锁存 owner 与 LBA。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            physical_read_active <= 1'b0;
            physical_read_owner_map <= 1'b0;
            physical_read_lba <= 32'd0;
            physical_read_byte_index <= 9'd0;
        end else if (!sd_init_done) begin
            physical_read_active <= 1'b0;
            physical_read_owner_map <= 1'b0;
            physical_read_lba <= 32'd0;
            physical_read_byte_index <= 9'd0;
        end else if (physical_read_active) begin
            if (sd_sec_read_data_valid)
                physical_read_byte_index <= physical_read_byte_index + 9'd1;
            if (sd_sec_read_end || sd_sec_read_abort)
                physical_read_active <= 1'b0;
        end else if (fs_sector_req) begin
            physical_read_active <= 1'b1;
            physical_read_owner_map <= 1'b0;
            physical_read_lba <= fs_sector_lba;
            physical_read_byte_index <= 9'd0;
        end else if (map_sector_req) begin
            physical_read_active <= 1'b1;
            physical_read_owner_map <= 1'b1;
            physical_read_lba <= map_sector_lba;
            physical_read_byte_index <= 9'd0;
        end
    end

endmodule
