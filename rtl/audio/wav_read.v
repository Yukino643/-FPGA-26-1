// wav_read.v — W7: WAV 文件解析器（RIFF/WAVE → PCM 样本流）
//
// 输入: 扇区读接口（接 sd_card_sec_read_write）
// 输出: 16bit L/R PCM 样本流
//
// WAV 假设: PCM(format=1)、48kHz、16bit、双声道、标准 44 字节头
// 简化: 头部解析在第一个扇区完成（44 字节 < 512），data 从偏移 44 开始
module wav_read #(
    parameter integer SCAN_MAX_SECTORS = 65536
)(
    input  wire        clk,
    input  wire        rst,
    output wire        ready,

    // 扫描
    input  wire        scan_start,
    input  wire [31:0] scan_start_sector,
    output reg         scan_done,
    output reg         scan_found_valid,
    output reg  [31:0] scan_found_sector,

    // 装载
    input  wire        load_start,
    input  wire [31:0] load_sector,
    output reg         load_done,
    output wire        load_active,
    output reg  [31:0] load_pcm_bytes,

    // 扇区读接口
    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,

    // PCM 样本输出
    output reg         pcm_valid,
    output reg  [15:0] pcm_left,
    output reg  [15:0] pcm_right,
    input  wire        pcm_ready
);

    localparam S_IDLE      = 4'd0;
    localparam S_SCAN_RD   = 4'd1;
    localparam S_SCAN_CHK  = 4'd2;
    localparam S_LOAD_RD   = 4'd3;   // 读扇区
    localparam S_LOAD_WAIT = 4'd4;   // 等扇区数据到齐
    localparam S_LOAD_PCM  = 4'd5;   // 流式输出 PCM
    localparam S_DONE      = 4'd6;
    localparam S_PCM_PREF  = 4'd7;

    reg [3:0]  state;
    reg        ready_r;
    assign ready = ready_r;
    assign load_active = (state == S_LOAD_RD) || (state == S_LOAD_WAIT) ||
                         (state == S_LOAD_PCM) || (state == S_PCM_PREF);

    // 扇区缓冲按 32 位字组织。原先按字节动态索引 512 项数组，
    // TD 会展开成很深的多路选择器；按字预取可把关键路径缩短到 128 项。
    reg [23:0] byte_pack;
    reg [8:0]  byte_cnt;
    reg        sec_ready;      // 扇区数据到齐

    // 扫描/头解析只需要这些字段，不再从整扇区数组组合读取。
    reg [7:0]  riff0, riff1, riff2, riff3;
    reg [7:0]  wave8, wave9, wave10, wave11;
    reg [31:0] wav_data_size;
    reg riff_match, wave_match;
    // 固定签名分组寄存，避免64位比较与扫描提交控制串成高扇出路径。
    // 扇区结束经sec_ready进入S_SCAN_CHK，采到末字节后仍留有一拍让匹配结果稳定。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            riff_match <= 1'b0;
            wave_match <= 1'b0;
        end else begin
            riff_match <= (riff0=="R" && riff1=="I" && riff2=="F" && riff3=="F");
            wave_match <= (wave8=="W" && wave9=="A" && wave10=="V" && wave11=="E");
        end
    end

    // WAV 元数据
    reg [31:0] data_bytes_left;
    reg [31:0] load_sec;
    reg [9:0]  pcm_idx;        // 当前样本组起始字节偏移
    reg [6:0]  pcm_word_idx;    // pcm_word 对应的扇区字索引
    wire [31:0] pcm_word;       // 同步 BRAM 读出的 L_lo/L_hi/R_lo/R_hi
    wire ram_we = sd_sec_read_data_valid && (byte_cnt[1:0] == 2'd3);
    wire [31:0] ram_wdata = {sd_sec_read_data,byte_pack};
`ifdef SIMULATION
    reg [31:0] sec_words [0:127];
    reg [31:0] ram_q;
    always @(posedge clk) begin
        if (ram_we) sec_words[byte_cnt[8:2]] <= ram_wdata;
        ram_q <= sec_words[pcm_word_idx];
    end
    assign pcm_word = ram_q;
`else
    // 四字节先组整字再写 BRAM，避免 4096 个 FF 和动态读 mux 挤满 MSlice。
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(7),
        .ADDR_WIDTH_B(7),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .RESETMODE("ASYNC"),.IMPLEMENT("9K")) u_sector_ram(
        .dia(ram_wdata),.addra(byte_cnt[8:2]),.cea(1'b1),.ocea(1'b0),.clka(clk),
        .wea(ram_we),.rsta(1'b0),.bea(1'b0),
        .dib(32'd0),.addrb(pcm_word_idx),.ceb(1'b1),.oceb(1'b1),.clkb(clk),
        .web(1'b0),.rstb(1'b0),.beb(1'b0),.doa(),.dob(pcm_word));
`endif

    // 扫描
    reg [31:0] scan_sec, scan_cnt;

    // PCM 组装
    reg [1:0]  ph;             // 0=L_lo 1=L_hi 2=R_lo 3=R_hi
    reg [7:0]  b0, b1, b2;     // 暂存字节
    reg        sec_req_sent;   // 已发扇区读请求

    // 超时保护（防 SD 卡死锁）
    reg [23:0] timeout_cnt;
    localparam TIMEOUT_MAX = 24'd10_000_000;  // 100ms @ 100MHz

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= S_IDLE;
            ready_r          <= 1'b0;
            scan_done        <= 1'b0;
            scan_found_valid <= 1'b0;
            scan_found_sector<= 32'd0;
            load_done        <= 1'b0;
            load_pcm_bytes   <= 32'd0;
            pcm_valid        <= 1'b0;
            pcm_left         <= 16'd0;
            pcm_right        <= 16'd0;
            sd_sec_read      <= 1'b0;
            sd_sec_read_addr <= 32'd0;
            byte_cnt         <= 9'd0;
            sec_ready        <= 1'b0;
            riff0            <= 8'd0;
            riff1            <= 8'd0;
            riff2            <= 8'd0;
            riff3            <= 8'd0;
            wave8            <= 8'd0;
            wave9            <= 8'd0;
            wave10           <= 8'd0;
            wave11           <= 8'd0;
            wav_data_size    <= 32'd0;
            data_bytes_left  <= 32'd0;
            load_sec         <= 32'd0;
            pcm_idx          <= 10'd0;
            pcm_word_idx     <= 7'd0;
            byte_pack        <= 24'd0;
            scan_sec         <= 32'd0;
            scan_cnt         <= 32'd0;
            ph               <= 2'd0;
            b0 <= 8'd0; b1 <= 8'd0; b2 <= 8'd0;
            sec_req_sent     <= 1'b0;
            timeout_cnt      <= 24'd0;
        end else begin
            pcm_valid   <= 1'b0;
            load_done   <= 1'b0;
            sd_sec_read <= 1'b0;

            // 扇区数据写入缓冲（byte_cnt 9bit 最大 511，自然覆盖 512 字节）
                if (sd_sec_read_data_valid) begin
                    // 4 个连续字节在同一个 32 位字中按小端序组装。
                    case (byte_cnt[1:0])
                        2'd0: byte_pack[7:0]   <= sd_sec_read_data;
                        2'd1: byte_pack[15:8]  <= sd_sec_read_data;
                        2'd2: byte_pack[23:16] <= sd_sec_read_data;
                        default: ;
                    endcase
                    // 仅锁存扫描和 WAV 头所需的字段，避免头检查再次遍历 RAM。
                    case (byte_cnt)
                        9'd0:  riff0 <= sd_sec_read_data;
                        9'd1:  riff1 <= sd_sec_read_data;
                        9'd2:  riff2 <= sd_sec_read_data;
                        9'd3:  riff3 <= sd_sec_read_data;
                        9'd8:  wave8 <= sd_sec_read_data;
                        9'd9:  wave9 <= sd_sec_read_data;
                        9'd10: wave10 <= sd_sec_read_data;
                        9'd11: wave11 <= sd_sec_read_data;
                        9'd40: wav_data_size[7:0]   <= sd_sec_read_data;
                        9'd41: wav_data_size[15:8]  <= sd_sec_read_data;
                        9'd42: wav_data_size[23:16] <= sd_sec_read_data;
                        9'd43: wav_data_size[31:24] <= sd_sec_read_data;
                        default: ;
                    endcase
                    byte_cnt <= byte_cnt + 9'd1;
            end
            if (sd_sec_read_end) begin
                sec_ready <= 1'b1;
                byte_cnt  <= 9'd0;
            end

            case (state)
                S_IDLE: begin
                    ready_r <= 1'b1;
                    if (scan_start) begin
                        scan_sec <= scan_start_sector;
                        scan_cnt <= 32'd0;
                        scan_done<= 1'b0;
                        ready_r  <= 1'b0;
                        byte_cnt <= 9'd0;
                        scan_found_valid <= 1'b0;
                        sec_req_sent <= 1'b0;
                        state    <= S_SCAN_RD;
                    end else if (load_start) begin
                        load_sec        <= load_sector;
                        data_bytes_left <= 32'd0;
                        pcm_idx         <= 10'd0;
                        ph              <= 2'd0;
                        ready_r         <= 1'b0;
                        byte_cnt        <= 9'd0;
                        sec_req_sent    <= 1'b0;
                        state           <= S_LOAD_RD;
                    end
                end

                // ---- 扫描 ----
                S_SCAN_RD: begin
                    if (!sec_req_sent) begin
                        sd_sec_read      <= 1'b1;
                        sd_sec_read_addr <= scan_sec;
                        sec_req_sent     <= 1'b1;
                        sec_ready        <= 1'b0;
                        timeout_cnt      <= 24'd0;
                    end else if (sec_ready) begin
                        sec_req_sent <= 1'b0;
                        state        <= S_SCAN_CHK;
                    end else begin
                        // 仲裁器可能暂时服务 BMP；请求必须保持到扇区完成，不能只脉冲一拍。
                        sd_sec_read <= 1'b1;
                        timeout_cnt <= timeout_cnt + 24'd1;
                        if (timeout_cnt >= TIMEOUT_MAX) begin
                            sec_req_sent <= 1'b0;
                            scan_done    <= 1'b1;   // 超时视为扫描结束
                            state        <= S_IDLE;
                            ready_r      <= 1'b1;
                        end
                    end
                end

                S_SCAN_CHK: begin
                    if (riff_match && wave_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sec;
                        scan_done         <= 1'b1;
                        state             <= S_IDLE;
                    end else begin
                        scan_sec <= scan_sec + 32'd1;
                        scan_cnt <= scan_cnt + 32'd1;
                        if (scan_cnt >= SCAN_MAX_SECTORS - 1) begin
                            scan_done <= 1'b1;
                            state     <= S_IDLE;
                        end else
                            state <= S_SCAN_RD;
                    end
                end

                // ---- 装载 ----
                S_LOAD_RD: begin
                    if (!sec_req_sent) begin
                        sd_sec_read      <= 1'b1;
                        sd_sec_read_addr <= load_sec;
                        sec_req_sent     <= 1'b1;
                        sec_ready        <= 1'b0;
                        timeout_cnt      <= 24'd0;
                    end else if (sec_ready) begin
                        sec_req_sent <= 1'b0;
                        if (data_bytes_left == 32'd0) begin
                            // 第一个扇区: 解析头
                            data_bytes_left <= wav_data_size;
                            load_pcm_bytes  <= wav_data_size;
                            pcm_idx         <= 10'd44;   // data 从偏移 44 开始
                            pcm_word_idx    <= 7'd11;
                        end else begin
                            // 后续扇区从字 0 开始，进入 PCM 状态前先预取。
                            pcm_idx         <= 10'd0;
                            pcm_word_idx    <= 7'd0;
                        end
                        state <= S_PCM_PREF;
                    end else begin
                        // FIFO/仲裁背压期间保持扇区请求，保证轮到 WAV 时请求仍可见。
                        sd_sec_read <= 1'b1;
                        timeout_cnt <= timeout_cnt + 24'd1;
                        if (timeout_cnt >= TIMEOUT_MAX) begin
                            sec_req_sent <= 1'b0;
                            load_done    <= 1'b1;   // 超时视为装载结束
                            state        <= S_IDLE;
                            ready_r      <= 1'b1;
                        end
                    end
                end

                // 地址登记后留一拍给同步 BRAM，phase 0 才能采样新字。
                S_PCM_PREF: state <= S_LOAD_PCM;

                S_LOAD_PCM: begin
                    if (data_bytes_left == 32'd0) begin
                        load_done <= 1'b1;
                        state     <= S_IDLE;
                        ready_r   <= 1'b1;
                    end else if ((ph != 2'd3) || pcm_ready) begin
                        // 一个预取字包含一整组立体声样本，四拍内不再访问大数组。
                        case (ph)
                            2'd0: begin b0 <= pcm_word[7:0];   ph <= 2'd1; end
                            2'd1: begin b1 <= pcm_word[15:8];  ph <= 2'd2; end
                            2'd2: begin b2 <= pcm_word[23:16]; ph <= 2'd3; end
                            2'd3: begin
                                pcm_left   <= {b1, b0};
                                pcm_right  <= {pcm_word[31:24], b2};
                                pcm_valid  <= 1'b1;
                                ph          <= 2'd0;
                                data_bytes_left <= data_bytes_left - 32'd4;
                                if (data_bytes_left <= 32'd4) begin
                                    // 最后一组样本已送出，下一拍报告完成。
                                    pcm_idx <= 10'd512;
                                end else if (pcm_idx >= 10'd508) begin
                                    // 当前扇区末尾不足下一组，切换到下一扇区。
                                    load_sec      <= load_sec + 32'd1;
                                    pcm_idx       <= 10'd0;
                                    pcm_word_idx  <= 7'd0;
                                    ph            <= 2'd0;
                                    state         <= S_LOAD_RD;
                                end else begin
                                    pcm_idx      <= pcm_idx + 10'd4;
                                    pcm_word_idx <= pcm_word_idx + 7'd1;
                                    state <= S_PCM_PREF;
                                end
                            end
                        endcase
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
