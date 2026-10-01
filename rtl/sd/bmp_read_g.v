// bmp_read_g.v — 泛化 BMP 解析器（计划书 5.1，替代官方 bmp_read）
// 相比官方 bmp_read 的增强：
//   1. 扫描记录每张图的 宽/高/长度 元数据（最多 MAX_IMAGES 张），不再锁死 640x480
//   2. 装载时剥离行尾 4 字节对齐 padding（官方 mod-3 打包在 W%4!=0 时会错位）
//   3. 宽高合法性检查（<=MAX_DIM，bit_count=24，无压缩），坏图跳过不炸
//   4. load_done 脉冲 + load_active 状态 + 装载图宽高输出（给监视台/缩放器用）
// 像素流与官方完全兼容：按源图自底向上行序输出 24bit {R,G,B}（BMP 存储序 B,G,R 拼包），
// 640x480 素材下与官方逐字节一致，frame_read_write(WRITE_V_FLIP=1) 无需改动。
module bmp_read_g #(
    parameter MAX_IMAGES = 8,
    parameter MAX_DIM    = 2047,
    parameter CLK_FREQ_HZ = 100_000_000,
    parameter SD_READ_TIMEOUT_MS = 500
)(
    input  wire        clk,
    input  wire        rst,
    output wire        ready,

    // 扫描
    input  wire        scan_start,
    input  wire [31:0] scan_start_sector,
    input  wire [31:0] scan_max_sector,
    input  wire [3:0]  scan_target_count,
    output reg         scan_done,
    output reg         scan_found_valid,
    output reg  [31:0] scan_found_sector,
    output reg  [3:0]  scan_found_total,
    output reg  [15:0] scan_found_w,
    output reg  [15:0] scan_found_h,

    // 装载
    input  wire        load_start,
    input  wire [31:0] load_sector,
    output reg         load_done,
    output reg         load_error,
    output reg  [3:0]  error_code,
    output wire        load_active,
    output reg  [15:0] load_img_w,
    output reg  [15:0] load_img_h,

    input  wire        sd_init_done,
    output reg  [3:0]  state_code,

    output wire        write_req,
    input  wire        write_req_ack,

    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    input  wire        sd_sec_read_error,

    output reg         bmp_data_wr_en,
    output reg  [23:0] bmp_data
);

    localparam ST_IDLE       = 4'd0;
    localparam ST_SCAN       = 4'd1;
    localparam ST_LOAD_HDR   = 4'd2;
    localparam ST_LOAD_WAIT  = 4'd3;
    localparam ST_LOAD_DATA  = 4'd4;
    localparam ST_HDR_PREP   = 4'd5;
    localparam ST_HDR_MUL    = 4'd6;
    localparam ST_HDR_RESULT = 4'd7;

    localparam [3:0] ERR_NONE      = 4'd0;
    localparam [3:0] ERR_HEADER    = 4'd1;
    localparam [3:0] ERR_TIMEOUT   = 4'd2;
    localparam [3:0] ERR_TRUNCATED = 4'd3;
    localparam [3:0] ERR_SD_READ   = 4'd4;
    localparam integer TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * SD_READ_TIMEOUT_MS;

    reg [3:0]  state;

    // BMP 头字段
    reg [7:0]  header_0, header_1;
    reg [31:0] file_len, pixel_offset, width, height, compression, dib_size;
    reg [15:0] bit_count, planes;

    // 基础字段只做比较；像素区长度在后续状态中用移位累加计算，避免把乘法
    // 和多级比较串在 SD 读结束到状态寄存器的单周期路径上。
    wire header_basic_match = (header_0 == "B") && (header_1 == "M")
                           && (dib_size    >= 32'd40)
                           && (planes      == 16'd1)
                           && (bit_count   == 16'd24)
                           && (compression == 32'd0)
                           && (width  != 32'd0) && (width  <= MAX_DIM)
                           && (height != 32'd0) && (height[31] == 1'b0) && (height <= MAX_DIM)
                           && (pixel_offset >= 32'd54)
                           && (file_len >= pixel_offset);
    wire [31:0] next_if_miss  = scan_sector + 32'd1;

    assign ready       = (state == ST_IDLE);
    assign load_active = (state == ST_LOAD_WAIT) || (state == ST_LOAD_DATA);
    assign write_req   = (state == ST_LOAD_WAIT);

    // 元数据表
    reg [31:0] meta_sector [0:MAX_IMAGES-1];
    reg [15:0] meta_w      [0:MAX_IMAGES-1];
    reg [15:0] meta_h      [0:MAX_IMAGES-1];

    reg [3:0]  found_cnt;
    reg [31:0] scan_sector;
    reg [31:0] load_sector_latched;
    reg [3:0]  load_meta_idx;
    reg [31:0] pixel_count;
    reg [31:0] timeout_cnt;

    // 头校验流水：一拍锁存基础合法性，随后用移位累加计算
    // row_bytes_pad * height，最后统一提交扫描或装载结果。
    reg        header_basic_ok;
    reg        header_check_load;
    reg        header_result_ok;
    reg [31:0] header_row_bytes;
    reg [31:0] header_expected_bytes;
    reg [31:0] header_sector_count;
    reg [31:0] hdr_mul_a;
    reg [31:0] hdr_mul_b;
    reg [31:0] hdr_product;
    reg [31:0] hdr_pixel_a;
    reg [31:0] hdr_pixel_product;
    reg [31:0] header_expected_pixels;
    reg [5:0]  hdr_mul_count;
    reg [31:0] row_bytes_pad_reg;

    wire read_state = (state == ST_SCAN) || (state == ST_LOAD_HDR) ||
                      (state == ST_LOAD_DATA);
    wire timeout_hit = read_state && (timeout_cnt >= TIMEOUT_CYCLES);

    // ---- 头部字节采样 ----
    reg [9:0] hdr_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hdr_cnt <= 10'd0;
            header_0 <= 8'd0; header_1 <= 8'd0;
            file_len <= 32'd0; pixel_offset <= 32'd54;
            width <= 32'd0; height <= 32'd0;
            bit_count <= 16'd0; planes <= 16'd0;
            dib_size <= 32'd0; compression <= 32'd0;
        end else if (!sd_init_done) begin
            hdr_cnt <= 10'd0;
        end else if ((state == ST_SCAN || state == ST_LOAD_HDR) && sd_sec_read_data_valid) begin
            // 34 是头字段采样结束哨兵；停在 33 会让后续像素反复覆盖 compression[31:24]。
            hdr_cnt <= (hdr_cnt >= 10'd34) ? 10'd34 : hdr_cnt + 10'd1;
            case (hdr_cnt)
                10'd0 : header_0 <= sd_sec_read_data;
                10'd1 : header_1 <= sd_sec_read_data;
                10'd2 : file_len[7:0]    <= sd_sec_read_data;
                10'd3 : file_len[15:8]   <= sd_sec_read_data;
                10'd4 : file_len[23:16]  <= sd_sec_read_data;
                10'd5 : file_len[31:24]  <= sd_sec_read_data;
                10'd10: pixel_offset[7:0]  <= sd_sec_read_data;
                10'd11: pixel_offset[15:8] <= sd_sec_read_data;
                10'd12: pixel_offset[23:16]<= sd_sec_read_data;
                10'd13: pixel_offset[31:24]<= sd_sec_read_data;
                10'd14: dib_size[7:0]   <= sd_sec_read_data;
                10'd15: dib_size[15:8]  <= sd_sec_read_data;
                10'd16: dib_size[23:16] <= sd_sec_read_data;
                10'd17: dib_size[31:24] <= sd_sec_read_data;
                10'd18: width[7:0]   <= sd_sec_read_data;
                10'd19: width[15:8]  <= sd_sec_read_data;
                10'd20: width[23:16] <= sd_sec_read_data;
                10'd21: width[31:24] <= sd_sec_read_data;
                10'd22: height[7:0]  <= sd_sec_read_data;
                10'd23: height[15:8] <= sd_sec_read_data;
                10'd24: height[23:16]<= sd_sec_read_data;
                10'd25: height[31:24]<= sd_sec_read_data;
                10'd28: bit_count[7:0]  <= sd_sec_read_data;
                10'd29: bit_count[15:8] <= sd_sec_read_data;
                10'd26: planes[7:0]  <= sd_sec_read_data;
                10'd27: planes[15:8] <= sd_sec_read_data;
                10'd30: compression[7:0]  <= sd_sec_read_data;
                10'd31: compression[15:8] <= sd_sec_read_data;
                10'd32: compression[23:16]<= sd_sec_read_data;
                10'd33: compression[31:24]<= sd_sec_read_data;
                default: ;
            endcase
        end else if ((state == ST_SCAN || state == ST_LOAD_HDR) && sd_sec_read_end) begin
            hdr_cnt <= 10'd0;          // 每个扇区读毕复位，跨扇区扫描时逐扇区重建头字段
        end else if (state == ST_IDLE) begin
            hdr_cnt <= 10'd0;
        end
    end

    // SD 读超时保护：错误路径必须有界，不能让状态机永久等待卡响应。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            timeout_cnt <= 32'd0;
        end else if (!sd_init_done || !read_state || sd_sec_read_end) begin
            timeout_cnt <= 32'd0;
        end else if (timeout_cnt < TIMEOUT_CYCLES) begin
            timeout_cnt <= timeout_cnt + 32'd1;
        end
    end

    // ---- 装载数据通路：文件内字节位置计数 + padding 剥离 + 3 字节拼像素 ----
    // byte_pos: 自文件第 0 字节（含 54B 头）计数的已收字节数（终止条件沿用官方）
    // row_pos : 像素区内"下一字节"在源图行内的位置（无除法实现 padding 剥离）
    reg [31:0] byte_pos;
    reg [31:0] row_pos;
    wire [31:0] w3            = width + width + width;             // W*3
    wire [31:0] row_bytes_pad = row_bytes_pad_reg;                 // 已锁存行字节数
    wire       in_pixel_data  = (state == ST_LOAD_DATA)
                             && (byte_pos >= pixel_offset) && (byte_pos < file_len);
    wire       byte_is_pixel  = in_pixel_data && (row_pos < w3);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            byte_pos <= 32'd0;
            row_pos  <= 32'd0;
        end else if (state == ST_LOAD_HDR || state == ST_LOAD_WAIT) begin
            byte_pos <= 32'd0;
            row_pos  <= 32'd0;
        end else if (state == ST_LOAD_DATA && sd_sec_read_data_valid) begin
            byte_pos <= byte_pos + 32'd1;
            if (byte_pos >= pixel_offset)
                row_pos <= (row_pos == row_bytes_pad - 32'd1) ? 32'd0 : row_pos + 32'd1;
        end
    end

    reg [1:0] byte_idx;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            byte_idx      <= 2'd0;
            bmp_data_wr_en <= 1'b0;
            bmp_data       <= 24'd0;
        end else if (state == ST_LOAD_DATA) begin
            // SD 接口按有效脉冲提供字节；空拍保持拼包状态，写使能始终只打一拍。
            bmp_data_wr_en <= 1'b0;
            if (sd_sec_read_data_valid) begin
                if (byte_is_pixel) begin
                    case (byte_idx)
                        2'd0: bmp_data[7:0]  <= sd_sec_read_data;
                        2'd1: bmp_data[15:8] <= sd_sec_read_data;
                        default: begin
                            bmp_data_wr_en  <= 1'b1;
                            bmp_data[23:16] <= sd_sec_read_data;
                        end
                    endcase
                    byte_idx <= (byte_idx == 2'd2) ? 2'd0 : byte_idx + 2'd1;
                end else if (in_pixel_data) begin
                    byte_idx <= 2'd0;      // 仅实际收到 padding 字节时复位拼包序
                end
            end
        end else begin
            bmp_data_wr_en <= 1'b0;
            byte_idx       <= 2'd0;
        end
    end

    // ---- 主状态机 ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= ST_IDLE;
            state_code       <= 4'd0;
            sd_sec_read      <= 1'b0;
            sd_sec_read_addr <= 32'd0;
            scan_done        <= 1'b0;
            scan_found_valid <= 1'b0;
            scan_found_sector<= 32'd0;
            scan_found_total <= 4'd0;
            scan_found_w     <= 16'd0;
            scan_found_h     <= 16'd0;
            load_done        <= 1'b0;
            load_error       <= 1'b0;
            error_code       <= ERR_NONE;
            load_img_w       <= 16'd0;
            load_img_h       <= 16'd0;
            found_cnt        <= 4'd0;
            scan_sector      <= 32'd0;
            load_sector_latched <= 32'd0;
            load_meta_idx    <= 4'd0;
            header_basic_ok  <= 1'b0;
            header_check_load <= 1'b0;
            header_result_ok  <= 1'b0;
            header_row_bytes  <= 32'd0;
            header_expected_bytes <= 32'd0;
            header_sector_count <= 32'd1;
            hdr_mul_a        <= 32'd0;
            hdr_mul_b        <= 32'd0;
            hdr_product      <= 32'd0;
            hdr_pixel_a      <= 32'd0;
            hdr_pixel_product <= 32'd0;
            header_expected_pixels <= 32'd0;
            hdr_mul_count    <= 6'd0;
            row_bytes_pad_reg <= 32'd0;
        end else if (!sd_init_done) begin
            state            <= ST_IDLE;
            state_code       <= 4'd0;
            sd_sec_read      <= 1'b0;
            scan_done        <= 1'b0;
            scan_found_valid <= 1'b0;
            load_done        <= 1'b0;
            load_error       <= 1'b0;
            found_cnt        <= 4'd0;
            header_basic_ok  <= 1'b0;
            header_result_ok <= 1'b0;
            row_bytes_pad_reg <= 32'd0;
        end else begin
            scan_found_valid <= 1'b0;
            load_done        <= 1'b0;
            load_error       <= 1'b0;

            if (timeout_hit) begin
                sd_sec_read <= 1'b0;
                error_code  <= ERR_TIMEOUT;
                if (state == ST_LOAD_HDR || state == ST_LOAD_DATA) begin
                    load_error <= 1'b1;
                    state      <= ST_IDLE;
                end else begin
                    scan_done <= 1'b1;
                    state     <= ST_IDLE;
                end
            end else case (state)
                ST_IDLE: begin
                    state_code <= 4'd1;
                    sd_sec_read <= 1'b0;
                    if (scan_start) begin
                        scan_done        <= 1'b0;
                        scan_found_total <= 4'd0;
                        found_cnt        <= 4'd0;
                        scan_sector      <= scan_start_sector;
                        sd_sec_read_addr <= scan_start_sector;
                        state            <= ST_SCAN;
                    end else if (load_start) begin
                        load_sector_latched <= load_sector;
                        sd_sec_read_addr    <= load_sector;
                        load_done           <= 1'b0;
                        load_error          <= 1'b0;
                        error_code          <= ERR_NONE;
                        state               <= ST_LOAD_HDR;
                    end
                end

                ST_SCAN: begin
                    state_code  <= 4'd2;
                    sd_sec_read <= 1'b1;
                    if (sd_sec_read_end) begin
                        sd_sec_read <= 1'b0;
                        header_basic_ok   <= header_basic_match;
                        header_check_load <= 1'b0;
                        state             <= ST_HDR_PREP;
                    end
                end

                ST_LOAD_HDR: begin
                    state_code  <= 4'd2;
                    sd_sec_read <= 1'b1;
                    if (sd_sec_read_end) begin
                        sd_sec_read <= 1'b0;
                        if (sd_sec_read_error) begin
                            error_code <= ERR_SD_READ;
                            load_error <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            header_basic_ok   <= header_basic_match;
                            header_check_load <= 1'b1;
                            state             <= ST_HDR_PREP;
                        end
                    end
                end

                // 头字段已经稳定，准备移位累加器；不在读结束拍做宽乘法。
                ST_HDR_PREP: begin
                    state_code <= 4'd2;
                    if (!header_basic_ok) begin
                        header_result_ok <= 1'b0;
                        state            <= ST_HDR_RESULT;
                    end else begin
                        header_row_bytes <= (width + (width << 1) + 32'd3) & ~32'd3;
                        hdr_mul_a        <= (width + (width << 1) + 32'd3) & ~32'd3;
                        hdr_mul_b        <= height;
                        hdr_product      <= 32'd0;
                        hdr_pixel_a      <= width;
                        hdr_pixel_product <= 32'd0;
                        hdr_mul_count    <= 6'd0;
                        state            <= ST_HDR_MUL;
                    end
                end

                // 固定 32 拍的 shift-and-add 乘法，避免工具把可变乘法展开成深组合路径。
                ST_HDR_MUL: begin
                    state_code <= 4'd2;
                    if (hdr_mul_count == 6'd31) begin
                        header_expected_bytes <= hdr_product + (hdr_mul_b[0] ? hdr_mul_a : 32'd0);
                        header_expected_pixels <= hdr_pixel_product + (hdr_mul_b[0] ? hdr_pixel_a : 32'd0);
                        header_sector_count   <= (file_len == 32'd0) ? 32'd1
                                                   : ((file_len + 32'd511) >> 9);
                        header_result_ok      <= (file_len >= pixel_offset)
                                              && (file_len >= pixel_offset
                                                  + hdr_product
                                                  + (hdr_mul_b[0] ? hdr_mul_a : 32'd0));
                        state <= ST_HDR_RESULT;
                    end else begin
                        if (hdr_mul_b[0])
                            hdr_product <= hdr_product + hdr_mul_a;
                        if (hdr_mul_b[0])
                            hdr_pixel_product <= hdr_pixel_product + hdr_pixel_a;
                        hdr_mul_a     <= hdr_mul_a << 1;
                        hdr_pixel_a   <= hdr_pixel_a << 1;
                        hdr_mul_b     <= hdr_mul_b >> 1;
                        hdr_mul_count <= hdr_mul_count + 6'd1;
                    end
                end

                // 扫描和装载都只使用已寄存的校验结果。
                ST_HDR_RESULT: begin
                    state_code <= 4'd2;
                    if (header_result_ok) begin
                        if (header_check_load) begin
                            load_img_w        <= width[15:0];
                            load_img_h        <= height[15:0];
                            row_bytes_pad_reg <= header_row_bytes;
                            load_meta_idx     <= 4'd0;
                            state             <= ST_LOAD_WAIT;
                        end else begin
                            scan_found_valid  <= 1'b1;
                            scan_found_sector <= scan_sector;
                            scan_found_w      <= width[15:0];
                            scan_found_h      <= height[15:0];
                            if (found_cnt < MAX_IMAGES) begin
                                meta_sector[found_cnt[2:0]] <= scan_sector;
                                meta_w[found_cnt[2:0]]      <= width[15:0];
                                meta_h[found_cnt[2:0]]      <= height[15:0];
                            end
                            found_cnt        <= found_cnt + 4'd1;
                            scan_found_total <= found_cnt + 4'd1;
                            scan_sector      <= scan_sector + header_sector_count;
                            sd_sec_read_addr <= scan_sector + header_sector_count;
                            if ((found_cnt + 4'd1 >= scan_target_count)
                                 || (scan_sector + header_sector_count > scan_max_sector)) begin
                                scan_done <= 1'b1;
                                state     <= ST_IDLE;
                            end else begin
                                state     <= ST_SCAN;
                            end
                        end
                    end else if (header_check_load) begin
                        error_code <= ERR_HEADER;
                        load_error <= 1'b1;
                        state      <= ST_IDLE;
                    end else if (scan_sector >= scan_max_sector) begin
                        scan_done <= 1'b1;
                        state     <= ST_IDLE;
                    end else begin
                        scan_sector      <= next_if_miss;
                        sd_sec_read_addr <= next_if_miss;
                        state            <= ST_SCAN;
                    end
                end

                ST_LOAD_WAIT: begin
                    state_code <= 4'd3;
                    if (write_req_ack)
                        state <= ST_LOAD_DATA;
                end

                ST_LOAD_DATA: begin
                    state_code  <= 4'd4;
                    sd_sec_read <= 1'b1;
                    if (sd_sec_read_end) begin
                        sd_sec_read <= 1'b0;
                        if (sd_sec_read_error) begin
                            error_code <= ERR_SD_READ;
                            load_error <= 1'b1;
                            state <= ST_IDLE;
                        end else if (byte_pos >= file_len) begin
                            if (pixel_count == header_expected_pixels) begin
                                load_done <= 1'b1;
                                state     <= ST_IDLE;
                            end else begin
                                error_code <= ERR_TRUNCATED;
                                load_error <= 1'b1;
                                state      <= ST_IDLE;
                            end
                        end else begin
                            sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                        end
                    end
                end

                default: begin
                    state       <= ST_IDLE;
                    state_code  <= 4'd1;
                    sd_sec_read <= 1'b0;
                end
            endcase
        end
    end

    // 像素完整性计数与 bmp_data_wr_en 使用同一输出条件，避免把“读完文件”误当成“写完整帧”。
    always @(posedge clk or posedge rst) begin
        if (rst || !sd_init_done) begin
            pixel_count <= 32'd0;
        end else if ((state == ST_IDLE && load_start) ||
                     state == ST_LOAD_HDR || state == ST_LOAD_WAIT) begin
            pixel_count <= 32'd0;
        end else if (state == ST_LOAD_DATA && sd_sec_read_data_valid &&
                     byte_is_pixel && (byte_idx == 2'd2)) begin
            pixel_count <= pixel_count + 32'd1;
        end
    end

endmodule
