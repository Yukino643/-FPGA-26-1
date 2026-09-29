// disp_read_engine.v — 显示帧预取引擎（mem_clk 域，mem_mpu 的读请求方）
// 帧门控式: video 域在 vs 翻转 toggle，本域 2FF 后置 go_pend；仅在当前突发
// 完全收尾后应用（重启 word_cnt/换页基址）—— 绝不打断突发，杜绝 rsp 丢拍死锁。
// 每帧恰好预取 FRAME_WORDS 字，与显示端逐帧精确排空配对，FIFO 帧尾自然清空，
// 行相位每帧重新对齐。反压: FIFO 水位 < HIGH_WATER 才发新簇。
module disp_read_engine #(
    parameter ADDR_BITS   = 21,
    parameter FRAME_WORDS = 307200,   // 640*480
    parameter BURST       = 128,      // mem_mpu 单簇上限
    parameter HIGH_WATER  = 256       // A1: 适配官方 FIFO 深度 512（余量 2×BURST）
)(
    input  wire                     clk,        // mem_clk 125M
    input  wire                     rst,

    // 帧起始 toggle（video 域 vs_rise 翻转）；page_base 与其同拍更新（准静态）
    input  wire                     vs_toggle,
    input  wire [ADDR_BITS-1:0]     page_base,

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
    reg [31:0]          word_cnt;
    reg [7:0]           burst_left;
    reg                 in_burst;      // 0=待发 1=已发命令待收数
    reg                 frame_act;

    wire [31:0] remaining = FRAME_WORDS - word_cnt;
    wire [7:0]  this_len  = (remaining >= BURST) ? BURST[7:0] : remaining[7:0];
    wire frame_done = (word_cnt >= FRAME_WORDS);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            base_r     <= {ADDR_BITS{1'b0}};
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
            if (vs_pulse)
                go_pend <= 1'b1;          // 帧起始请求挂起

            // 帧起始挂起: 只在无在途突发时应用（突发最多 ~270 拍，消隐期足够）
            if (go_pend && !in_burst) begin
                base_r    <= page_base;
                word_cnt  <= 32'd0;
                frame_act <= 1'b1;
                go_pend   <= 1'b0;
            end

            if (!frame_act) begin
                cmd_valid <= 1'b0;
            end else if (frame_done && !in_burst) begin
                frame_act <= 1'b0;                    // 本帧读完，等下一帧
                cmd_valid <= 1'b0;
            end else if (!in_burst) begin
                if (fifo_wusedw < HIGH_WATER) begin
                    cmd_addr  <= base_r + word_cnt[ADDR_BITS-1:0];
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
                        in_burst <= 1'b0;
                end
            end
        end
    end

endmodule
