// sd_card_bmp_g.v — TF 卡 BMP 扫描/轮播时序控制（泛化版，W3）
// 基于官方 sd_card_bmp：双缓冲提交/页翻转握手逻辑保持一致；
//   1. 轮播图数 4 → 8（img_idx 扩到 4bit）
//   2. 底层换 bmp_read_g（任意分辨率 + padding 剥离 + 元数据）
//   3. 对外暴露 img_count / cur_img_w / cur_img_h 给监视台
module sd_card_bmp_g #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [3:0]   SCAN_TARGET_COUNT = 4'd8
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
    output wire [31:0] debug_status,  // 只读状态总线，供板级诊断使用

    input  wire        write_finish_toggle,
    output reg  [1:0]  write_buf_idx,
    output reg  [1:0]  disp_buf_idx,

    output             write_req,
    input  wire        write_req_ack,
    output             write_en,
    output [23:0]      write_data,
    input  wire        sd_init_done,
    output wire        sd_sec_read,
    output wire [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end
);

    wire key_next_press;
    wire key_auto_press;

    wire             bmp_data_wr_en;
    wire [23:0]      bmp_data;
    wire             bmp_ready;
    wire             bmp_load_error;
    wire [3:0]       bmp_error_code;
    wire             scan_done;
    wire             scan_found_valid;
    wire [31:0]      scan_found_sector;
    wire [3:0]       scan_found_total;
    wire [15:0]      scan_found_w;
    wire [15:0]      scan_found_h;

    reg              scan_start_pulse;
    reg              load_start_pulse;
    reg [31:0]       load_sector;
    reg              scan_kicked;
    reg              first_image_committed;
    reg              auto_play_en;
    reg [31:0]       auto_cnt;
    reg [3:0]        img_found_count;
    reg [3:0]        img_idx;             // 当前显示中的图片编号
    reg [3:0]        load_idx;            // 当前正在装载的图片编号
    reg [1:0]        pending_buf_idx;
    reg [31:0]       img_sector0;
    reg [31:0]       img_sector1;
    reg [31:0]       img_sector2;
    reg [31:0]       img_sector3;
    reg [31:0]       img_sector4;
    reg [31:0]       img_sector5;
    reg [31:0]       img_sector6;
    reg [31:0]       img_sector7;
    reg              next_req_pending;
    reg              load_busy;
    reg              source_done_seen;
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
    assign debug_status = {4'd0, failed_mask, state_code, bmp_error_code, img_found_count,
                           any_good_image, first_image_committed, display_valid,
                           load_retry_used, load_fault, source_done_seen, load_busy, scan_done};
    assign write_en   = bmp_data_wr_en;
    // bmp_read_g 已按 {R,G,B} 输出；保持 24 位接口，禁止 32→24 位截断丢失 R 分量。
    assign write_data = bmp_data;
    assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));
    assign next_from_current = next_good_index(img_idx, img_found_count, failed_mask);
    assign first_good_image  = first_good_index(img_found_count, failed_mask);
    assign any_good_image    = has_good_image(img_found_count, failed_mask);
    assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

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
            next_good_index = 4'd0;
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

    function [31:0] sector_lut;
        input [3:0] idx;
        begin
            case (idx)
                4'd0: sector_lut = img_sector0;
                4'd1: sector_lut = img_sector1;
                4'd2: sector_lut = img_sector2;
                4'd3: sector_lut = img_sector3;
                4'd4: sector_lut = img_sector4;
                4'd5: sector_lut = img_sector5;
                4'd6: sector_lut = img_sector6;
                default: sector_lut = img_sector7;
            endcase
        end
    endfunction

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
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            img_sector4           <= 32'd0;
            img_sector5           <= 32'd0;
            img_sector6           <= 32'd0;
            img_sector7           <= 32'd0;
            img_count             <= 4'd0;
            cur_img_w             <= 16'd0;
            cur_img_h             <= 16'd0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
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
                next_req_pending      <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                load_retry_used       <= 1'b0;
                load_fault            <= 1'b0;
                failed_mask           <= 8'd0;
                display_valid         <= 1'b0;
            end else begin
                // 扫描阶段缓存图片起始扇区（最多 8 张）
                if (scan_found_valid && (img_found_count < SCAN_TARGET_COUNT)) begin
                    case (img_found_count)
                        4'd0: img_sector0 <= scan_found_sector;
                        4'd1: img_sector1 <= scan_found_sector;
                        4'd2: img_sector2 <= scan_found_sector;
                        4'd3: img_sector3 <= scan_found_sector;
                        4'd4: img_sector4 <= scan_found_sector;
                        4'd5: img_sector5 <= scan_found_sector;
                        4'd6: img_sector6 <= scan_found_sector;
                        default: img_sector7 <= scan_found_sector;
                    endcase
                    img_found_count <= img_found_count + 4'd1;
                end

                // 错误事务必须有界：自动重试一次，仍失败则放弃本次装载并保留当前显示。
                if (load_busy && bmp_load_error) begin
                    source_done_seen <= 1'b0;
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
                        next_req_pending <= 1'b1;
                    end
                end

                // 只锁存本次装载的真实完成事件；ready 只是空闲状态，不能替代事务完成。
                if (load_busy && load_done)
                    source_done_seen <= 1'b1;

                // 收到 write_finish_toggle 脉冲才提交新图并切换显示缓冲
                if (load_busy && source_done_seen && write_finish_pulse) begin
                    load_busy             <= 1'b0;
                    source_done_seen      <= 1'b0;
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    cur_img_w             <= load_img_w;
                    cur_img_h             <= load_img_h;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                    load_fault            <= 1'b0;
                end

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
                    next_req_pending      <= 1'b0;
                    display_valid         <= 1'b0;
                    load_busy             <= 1'b0;
                    source_done_seen      <= 1'b0;
                    load_retry_used       <= 1'b0;
                    load_fault            <= 1'b0;
                    failed_mask           <= 8'd0;
                end else begin
                    if (key_next_press && scan_done && (img_found_count > 4'd0))
                        next_req_pending <= 1'b1;

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
                        load_sector      <= sector_lut(first_good_image);
                        pending_buf_idx  <= 2'd0;
                        write_buf_idx    <= 2'd0;
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        load_retry_used  <= 1'b0;
                        next_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                        img_count        <= img_found_count;
                    end
                    else if (scan_done && bmp_ready && display_valid && !load_busy && next_req_pending
                             && (img_found_count != 4'd0) && any_good_image && !hold_load) begin
                        load_idx         <= next_from_current;
                        load_sector      <= sector_lut(next_from_current);
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        load_retry_used  <= 1'b0;
                        next_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                    end
                    else if (scan_done && bmp_ready && display_valid && !load_busy && auto_play_en && auto_tick
                             && (img_found_count > 4'd1) && any_good_image && !hold_load) begin
                        load_idx         <= next_from_current;
                        load_sector      <= sector_lut(next_from_current);
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        load_retry_used  <= 1'b0;
                        auto_cnt         <= 32'd0;
                    end
                end
            end
        end
    end

    bmp_read_g #(
        .MAX_IMAGES (8),
        .MAX_DIM    (2047)
    ) bmp_read_g_m0 (
        .clk                    (clk),
        .rst                    (rst),
        .ready                  (bmp_ready),

        .scan_start             (scan_start_pulse),
        .scan_start_sector      (SCAN_START_SECTOR),
        .scan_max_sector        (SCAN_MAX_SECTOR),
        .scan_target_count      (SCAN_TARGET_COUNT),
        .scan_done              (scan_done),
        .scan_found_valid       (scan_found_valid),
        .scan_found_sector      (scan_found_sector),
        .scan_found_total       (scan_found_total),
        .scan_found_w           (scan_found_w),
        .scan_found_h           (scan_found_h),

        .load_start             (load_start_pulse),
        .load_sector            (load_sector),
        .load_done              (load_done),
        .load_error             (bmp_load_error),
        .error_code             (bmp_error_code),
        .load_active            (),
        .load_img_w             (load_img_w),
        .load_img_h             (load_img_h),

        .sd_init_done           (sd_init_done),
        .state_code             (state_code),

        .write_req              (write_req),
        .write_req_ack          (write_req_ack),

        .sd_sec_read            (sd_sec_read),
        .sd_sec_read_addr       (sd_sec_read_addr),
        .sd_sec_read_data       (sd_sec_read_data),
        .sd_sec_read_data_valid (sd_sec_read_data_valid),
        .sd_sec_read_end        (sd_sec_read_end),

        .bmp_data_wr_en         (bmp_data_wr_en),
        .bmp_data               (bmp_data)
    );

endmodule
