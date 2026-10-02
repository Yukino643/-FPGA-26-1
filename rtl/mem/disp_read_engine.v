// disp_read_engine.v — 显示帧预取引擎（mem_clk 域，mem_mpu 的读请求方）
// 帧门控式: video 域在 vs 翻转 toggle，本域 2FF 后置 go_pend；仅在当前突发
// 完全收尾后应用（重启 word_cnt/换页基址）—— 绝不打断突发，杜绝 rsp 丢拍死锁。
// 每帧恰好预取 FRAME_WORDS 字，与显示端逐帧精确排空配对，FIFO 帧尾自然清空，
// 行相位每帧重新对齐。反压: FIFO 水位 < HIGH_WATER 才发新簇。
module disp_read_engine #(
    parameter ADDR_BITS   = 21,
    parameter FRAME_WORDS = 307200,   // 640*480
    parameter BURST       = 128,      // mem_mpu 单簇上限
    parameter HIGH_WATER  = 256,      // A1: 适配官方 FIFO 深度 512（余量 2×BURST）
    parameter ENABLE_SCROLL = 0
)(
    input  wire                     clk,        // mem_clk 125M
    input  wire                     rst,

    // 帧起始 toggle（video 域 vs_rise 翻转）；page_base 与其同拍更新（准静态）
    input  wire                     vs_toggle,
    input  wire [ADDR_BITS-1:0]     page_base,
    // 水平推移偏移；每行从 scroll_x 列开始读取并在行尾回绕。
    // 输入跨域后只在帧重启时采纳，保证一帧内地址序列稳定。
    input  wire [9:0]               scroll_x,

    // FIFO 接口（afifo_simple 写侧，同域）
    output reg                      fifo_we,
    output reg  [31:0]              fifo_wdata,
    input  wire [9:0]               fifo_wusedw, // A1: 深度512 → 10 位

    // mem_mpu 请求方接口
    output reg                      cmd_valid,
    output reg  [ADDR_BITS-1:0]     cmd_addr,
    output reg  [7:0]               cmd_len,
    input  wire                     cmd_ready,
    input  wire                     rsp_valid,
    input  wire [31:0]              rsp_data,
    input  wire                     rsp_last
);

    // ---- vs toggle 跨域（vs_sync/go_pend 均只在下方 FSM 块内驱动，避免多驱动） ----
    reg [2:0]  vs_sync;
    reg        go_pend;
    wire       vs_pulse = vs_sync[1] ^ vs_sync[2];

    reg [ADDR_BITS-1:0] base_r;
    reg [ADDR_BITS-1:0] row_base;
    reg [9:0]            src_col, out_col, scroll_r;
    reg [9:0]            scroll_sync1, scroll_sync2;
    reg [31:0]          word_cnt;
    reg [7:0]           burst_left;
    reg                 in_burst;      // 0=待发 1=已发命令待收数
    reg                 frame_act;

    wire [31:0] remaining = FRAME_WORDS - word_cnt;
    wire [10:0] source_remaining = 11'd640 - {1'b0, src_col};
    wire [10:0] output_remaining = 11'd640 - {1'b0, out_col};
    wire [10:0] line_remaining = (source_remaining < output_remaining) ? source_remaining : output_remaining;
    wire [10:0] burst_cap = ENABLE_SCROLL && line_remaining < BURST ? line_remaining : BURST;
    wire [7:0]  this_len  = (remaining < burst_cap) ? remaining[7:0] : burst_cap[7:0];
    wire frame_done = (word_cnt >= FRAME_WORDS);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            base_r     <= {ADDR_BITS{1'b0}};
            row_base   <= {ADDR_BITS{1'b0}};
            src_col    <= 10'd0;
            out_col    <= 10'd0;
            scroll_r   <= 10'd0;
            scroll_sync1 <= 10'd0;
            scroll_sync2 <= 10'd0;
            word_cnt   <= 32'd0;
            burst_left <= 8'd0;
            in_burst   <= 1'b0;
            frame_act  <= 1'b0;
            fifo_we    <= 1'b0;
            fifo_wdata <= 32'd0;
            cmd_valid  <= 1'b0;
            cmd_addr   <= {ADDR_BITS{1'b0}};
            cmd_len    <= 8'd0;
            go_pend    <= 1'b0;
            vs_sync    <= 3'b000;
        end else begin
            fifo_we <= 1'b0;
            vs_sync <= {vs_sync[1:0], vs_toggle};
            scroll_sync1 <= (ENABLE_SCROLL && scroll_x < 10'd640) ? scroll_x : 10'd0;
            scroll_sync2 <= scroll_sync1;
            if (vs_pulse)
                go_pend <= 1'b1;          // 帧起始请求挂起

            // 帧起始挂起: 只在无在途突发时应用（突发最多 ~270 拍，消隐期足够）
            if (go_pend && !in_burst) begin
                base_r    <= page_base;
                row_base  <= {ADDR_BITS{1'b0}};
                src_col   <= scroll_sync2;
                scroll_r  <= scroll_sync2;
                out_col   <= 10'd0;
                word_cnt  <= 32'd0;
                frame_act <= 1'b1;
                go_pend   <= 1'b0;
                // 重启和请求旧页互斥，不能用本拍更新前的 base_r 发首突发。
                cmd_valid <= 1'b0;
            end else if (!frame_act) begin
                cmd_valid <= 1'b0;
            end else if (frame_done && !in_burst) begin
                frame_act <= 1'b0;                    // 本帧读完，等下一帧
                cmd_valid <= 1'b0;
            end else if (!in_burst) begin
                if (fifo_wusedw < HIGH_WATER) begin
                    cmd_addr  <= ENABLE_SCROLL ? base_r + row_base + src_col : base_r + word_cnt[ADDR_BITS-1:0];
                    cmd_len   <= this_len;
                    cmd_valid <= 1'b1;
                    in_burst  <= 1'b1;
                end
            end else if (cmd_valid && cmd_ready) begin
                cmd_valid  <= 1'b0;
                burst_left <= cmd_len;
            end else if (!cmd_valid && burst_left != 8'd0) begin
                if (rsp_valid) begin
                    fifo_we    <= 1'b1;
                    fifo_wdata <= rsp_data;
                    // 保留 FRAME_WORDS 终值，下一拍才能可靠命中 frame_done。
                    // 新一帧由 go_pend 分支显式清零，禁止末字同拍清零吞掉完成事件。
                    word_cnt   <= word_cnt + 32'd1;
                    burst_left <= burst_left - 8'd1;
                    if (burst_left == 8'd1)
                        begin
                            in_burst <= 1'b0;
                            // 源列回绕仍属同一行；输出满 640 字后才推进行。
                            if (out_col + cmd_len >= 10'd640) begin
                                src_col  <= scroll_r;
                                out_col  <= 10'd0;
                                row_base <= row_base + 10'd640;
                            end else begin
                                out_col <= out_col + cmd_len;
                                src_col <= (src_col + cmd_len >= 10'd640) ? 10'd0 : src_col + cmd_len;
                            end
                        end
                end
            end
        end
    end

endmodule
