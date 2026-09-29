`timescale 1ns/1ps
// scaler.v — 定点双线性缩放引擎（W6，计划书 5.9）
//
// 从 SRC_BUF 读 RGB565 打包源图（≤1024×768，2 像素/32bit 字），
// 双线性插值缩放到 OUT_W×OUT_H RGB888，写入目标显示页。
// 全程 ext_mem_clk(125M) 单时钟域。
//
// 坐标数学（与 tb_scaler 参考模型逐位一致）:
//   dx = (W << 14) / OUT_W，dy = (H << 14) / OUT_H（启动时迭代除法求出）
//   acc(0) = (dx >> 1) - (FR_FULL >> 1)（有符号半像素中心对齐）
//   每像素 acc += dx；每行 yacc += dy
//   x_int = acc<0 ? 0 : min(acc>>14, W-1)
//   xf8 = acc<0 ? 0 : acc[13:6]（14 位小数取高 8 位）
//   源行翻转（BMP 自底向上装载）: 内存行 s0 = (H-1) - y_int
//   行间: 下邻行 s1 = (y_int+1 <= H-1) ? s0 - 1 : s0（边界钳位）
//
// 插值（两级 >>8 归一，8 位权重）:
//   行内: h = p0 * (256 - xf8) + p1 * xf8
//   行间: o = (h_top * (256 - yf8) + h_bot * yf8) >> 16
//
// 行缓冲: 4 片 EG_LOGIC_BRAM（512×32，IMPLEMENT="32K"）。
//   每源行存双份（A/B 内容相同）→ 同拍读 word[x_int>>1] 与 word[(x_int+1)>>1]。
//   写: 同拍写两份（r0a+r0b 或 r1a+r1b），无需分拍复制。
//
// 像素流水线（3 级寄存，1 像素/拍）:
//   N: 发 BRAM 读地址; 登记元数据
//   N+1: BRAM dout 有效; 拆 RGB565→RGB888; 行内插值 h
//   N+2: 行间插值 o; 写 SDRAM
module scaler #(
    parameter OUT_W = 640,
    parameter OUT_H = 480,
    parameter FRAC  = 14
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start_toggle,
    input  wire [10:0]              cfg_w,
    input  wire [10:0]              cfg_h,
    input  wire [20:0]              cfg_src_base,
    input  wire [20:0]              cfg_dst_base,
    // mem_mpu 请求方 C
    output reg                      cmd_valid,
    output reg  [20:0]              cmd_addr,
    output reg  [7:0]               cmd_len,
    input  wire                     cmd_ready,
    input  wire                     rsp_valid,
    input  wire [31:0]              rsp_data,
    input  wire                     rsp_last,
    // mem_mpu 写方 2
    output reg                      wr_en,
    output reg  [20:0]              wr_addr,
    output reg  [31:0]              wr_din,
    output wire [3:0]               wr_dm,
    output wire                     busy,
    output reg                      done_toggle
);
    localparam FR_FULL = 1 << FRAC;

    // ---- 状态编码 ----
    localparam S_IDLE  = 4'd0;
    localparam S_DIV   = 4'd1;
    localparam S_LINE  = 4'd2;
    localparam S_FWR   = 4'd3;    // 取数：发簇
    localparam S_FDA   = 4'd4;    // 取数：收数据
    localparam S_RUN   = 4'd5;
    localparam S_DONE  = 4'd6;

    // ---- start 同步 ----
    reg [2:0]  st_sync;
    wire       st_pulse = st_sync[1] ^ st_sync[2];
    always @(posedge clk or posedge rst) begin
        if (rst) st_sync <= 3'b000;
        else     st_sync <= {st_sync[1:0], start_toggle};
    end

    // ---- FSM ----
    reg [3:0]  state;
    reg        busy_r;
    assign busy = busy_r;
    assign wr_dm = 4'hF;

    // ---- 配置锁存 ----
    reg [10:0] src_w, src_h;
    reg [20:0] src_base, dst_base;
    reg [25:0] dx, dy;
    reg [9:0]  row_words;

    // ---- 除法器 ----
    reg        div_doing;
    reg [5:0]  div_cnt;
    reg [25:0] div_rem, div_quo, div_work, divisor;
    wire [26:0] rem_cand = {div_rem[24:0], div_work[25]};
    wire        rem_ge   = (rem_cand >= {1'b0, divisor});

    // ---- 行坐标 ----
    reg [25:0] yacc;
    wire       yacc_neg = yacc[25];
    reg [9:0]  out_y;
    reg [9:0]  s0, s1;
    reg [7:0]  yf8;
    reg        row_pair_valid;
    reg [9:0]  cache_s0, cache_s1;
    reg        pair_hit;

    // ---- 行 RAM 接口 ----
    reg        ram_we;
    reg [8:0]  ram_waddr;
    reg [31:0] ram_wdata;
    reg        ram_wsel;          // 0=s0 行, 1=s1 行（同拍写 A+B 两份）
    reg        ram_rd;
    reg [8:0]  ram_r0a, ram_r0b, ram_r1a, ram_r1b;
`ifdef SIMULATION
    reg  [31:0] dout_r0a, dout_r0b, dout_r1a, dout_r1b;
`else
    wire [31:0] dout_r0a, dout_r0b, dout_r1a, dout_r1b;
`endif

    // ---- 行取数跟踪 ----
    reg [31:0] fetch_left;        // 剩余 SDRAM 字数
    reg [10:0] fetch_wi;          // 当前行内字下标
    reg        fetch_row;         // 0=s1 行, 1=s0 行
    reg        fetch_active;
    reg [7:0]  fetch_burst_left;  // 当前簇剩余响应拍数

    // ---- 像素生成 ----
    reg [9:0]  px_x;
    reg [25:0] xacc;
    wire       xacc_neg = xacc[25];
    reg [11:0] x_int_c;
    reg [7:0]  xf8_c;
    reg [8:0]  bram_a_addr, bram_b_addr;

    // ---- 流水线寄存器 ----
    // BRAM 同步读有 1 拍延迟 → raw 级在发地址时锁存，d1 级与 dout 对齐
    reg        pxv_raw;
    reg [11:0] x_int_raw;
    reg [7:0]  xf8_raw, yf8_raw;
    reg [11:0] x_int_d1;
    reg [7:0]  xf8_d1, yf8_d1;
    reg        pxv_d1;
    reg [7:0]  xf8_d2, yf8_d2;
    reg        pxv_d2;
    reg [7:0]  yf8_d3;
    reg        pxv_d3;
    reg [7:0]  t0r, t0g, t0b, t1r, t1g, t1b;
    reg [7:0]  b0r, b0g, b0b, b1r, b1g, b1b;
    reg [15:0] h0r, h0g, h0b, h1r, h1g, h1b;

    // ---- 写出跟踪 ----
    reg [20:0] wr_cnt;

    // ---- 组合: x 坐标提取与钳位 ----
    always @(*) begin
        if (xacc_neg) begin
            x_int_c = 12'd0;
            xf8_c   = 8'd0;
        end else if ({1'b0, xacc[25:14]} >= {1'b0, src_w}) begin
            x_int_c = {1'b0, src_w} - 12'd1;
            xf8_c   = 8'd0;
        end else begin
            x_int_c = xacc[25:14];
            xf8_c   = xacc[13:6];
        end
    end

    // ---- 组合: BRAM 读地址 ----
    always @(*) begin
        bram_a_addr = {1'b0, x_int_c[8:1]};
        bram_b_addr = x_int_c[0] ? ({1'b0, x_int_c[8:1]} + 9'd1)
                                  : {1'b0, x_int_c[8:1]};
        if (bram_b_addr >= row_words[8:0] && row_words[8:0] != 9'd0)
            bram_b_addr = row_words[8:0] - 9'd1;
    end

    // ---- 组合: RGB565→RGB888 拆包与偶奇半字选择 ----
    // word = {odd_px, even_px}: 偶数下标取 [15:0]，奇数下标取 [31:16]
    wire [15:0] hw_p0_t = x_int_d1[0] ? dout_r0a[31:16] : dout_r0a[15:0];
    wire [15:0] hw_p1_t = x_int_d1[0] ? dout_r0b[15:0]  : dout_r0b[31:16];
    wire [15:0] hw_p0_b = x_int_d1[0] ? dout_r1a[31:16] : dout_r1a[15:0];
    wire [15:0] hw_p1_b = x_int_d1[0] ? dout_r1b[15:0]  : dout_r1b[31:16];
    wire [7:0] ext_t0r = {hw_p0_t[15:11], hw_p0_t[15:13]};
    wire [7:0] ext_t0g = {hw_p0_t[10:5],  hw_p0_t[10:9]};
    wire [7:0] ext_t0b = {hw_p0_t[4:0],   hw_p0_t[4:2]};
    wire [7:0] ext_t1r = {hw_p1_t[15:11], hw_p1_t[15:13]};
    wire [7:0] ext_t1g = {hw_p1_t[10:5],  hw_p1_t[10:9]};
    wire [7:0] ext_t1b = {hw_p1_t[4:0],   hw_p1_t[4:2]};
    wire [7:0] ext_b0r = {hw_p0_b[15:11], hw_p0_b[15:13]};
    wire [7:0] ext_b0g = {hw_p0_b[10:5],  hw_p0_b[10:9]};
    wire [7:0] ext_b0b = {hw_p0_b[4:0],   hw_p0_b[4:2]};
    wire [7:0] ext_b1r = {hw_p1_b[15:11], hw_p1_b[15:13]};
    wire [7:0] ext_b1g = {hw_p1_b[10:5],  hw_p1_b[10:9]};
    wire [7:0] ext_b1b = {hw_p1_b[4:0],   hw_p1_b[4:2]};

    // ---- 行间插值（S4 组合，DSP 优化: h*(256-y)+k*y = (h<<8)+(k-h)*y） ----
    wire signed [16:0] diff_r = $signed({1'b0, h1r}) - $signed({1'b0, h0r});
    wire signed [16:0] diff_g = $signed({1'b0, h1g}) - $signed({1'b0, h0g});
    wire signed [16:0] diff_b = $signed({1'b0, h1b}) - $signed({1'b0, h0b});
    wire [25:0] mix_r = {h0r, 8'd0} + diff_r * $signed({1'b0, yf8_d3});
    wire [25:0] mix_g = {h0g, 8'd0} + diff_g * $signed({1'b0, yf8_d3});
    wire [25:0] mix_b = {h0b, 8'd0} + diff_b * $signed({1'b0, yf8_d3});
    wire [7:0] out_r = mix_r[23:16];
    wire [7:0] out_g = mix_g[23:16];
    wire [7:0] out_b = mix_b[23:16];

    // ---- 行 RAM 例化（同拍写两份: r?a+r?b 共享写信号） ----
    wire we_s0 = ram_we && !ram_wsel;
    wire we_s1 = ram_we &&  ram_wsel;

`ifdef SIMULATION
    reg [31:0] mem_r0a [0:511];
    reg [31:0] mem_r0b [0:511];
    reg [31:0] mem_r1a [0:511];
    reg [31:0] mem_r1b [0:511];
    always @(posedge clk) begin
        if (we_s0) begin
            mem_r0a[ram_waddr] <= ram_wdata;
            mem_r0b[ram_waddr] <= ram_wdata;
        end
        if (we_s1) begin
            mem_r1a[ram_waddr] <= ram_wdata;
            mem_r1b[ram_waddr] <= ram_wdata;
        end
        if (ram_rd) begin
            dout_r0a <= mem_r0a[ram_r0a];
            dout_r0b <= mem_r0b[ram_r0b];
            dout_r1a <= mem_r1a[ram_r1a];
            dout_r1b <= mem_r1b[ram_r1b];
        end
    end
`else
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32), .DATA_WIDTH_B(32), .ADDR_WIDTH_A(9),
        .ADDR_WIDTH_B(9), .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .RESETMODE("ASYNC"), .IMPLEMENT("32K")) u_r0a (
        .dia(ram_wdata), .addra(ram_waddr), .cea(we_s0), .ocea(1'b0), .clka(clk),
        .wea(we_s0), .rsta(1'b0), .bea(1'b0),
        .dib(32'b0), .addrb(ram_r0a), .ceb(ram_rd), .oceb(1'b1), .clkb(clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .doa(), .dob(dout_r0a));
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32), .DATA_WIDTH_B(32), .ADDR_WIDTH_A(9),
        .ADDR_WIDTH_B(9), .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .RESETMODE("ASYNC"), .IMPLEMENT("32K")) u_r0b (
        .dia(ram_wdata), .addra(ram_waddr), .cea(we_s0), .ocea(1'b0), .clka(clk),
        .wea(we_s0), .rsta(1'b0), .bea(1'b0),
        .dib(32'b0), .addrb(ram_r0b), .ceb(ram_rd), .oceb(1'b1), .clkb(clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .doa(), .dob(dout_r0b));
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32), .DATA_WIDTH_B(32), .ADDR_WIDTH_A(9),
        .ADDR_WIDTH_B(9), .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .RESETMODE("ASYNC"), .IMPLEMENT("32K")) u_r1a (
        .dia(ram_wdata), .addra(ram_waddr), .cea(we_s1), .ocea(1'b0), .clka(clk),
        .wea(we_s1), .rsta(1'b0), .bea(1'b0),
        .dib(32'b0), .addrb(ram_r1a), .ceb(ram_rd), .oceb(1'b1), .clkb(clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .doa(), .dob(dout_r1a));
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32), .DATA_WIDTH_B(32), .ADDR_WIDTH_A(9),
        .ADDR_WIDTH_B(9), .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .RESETMODE("ASYNC"), .IMPLEMENT("32K")) u_r1b (
        .dia(ram_wdata), .addra(ram_waddr), .cea(we_s1), .ocea(1'b0), .clka(clk),
        .wea(we_s1), .rsta(1'b0), .bea(1'b0),
        .dib(32'b0), .addrb(ram_r1b), .ceb(ram_rd), .oceb(1'b1), .clkb(clk),
        .web(1'b0), .rstb(1'b0), .beb(1'b0), .doa(), .dob(dout_r1b));
`endif

    // ================= 组合: 下一行对参数 =================
    wire        yacc_neg_w = yacc[25];
    wire [7:0]  yf8_w = yacc_neg_w ? 8'd0 :
                        ({1'b0, yacc[25:14]} >= {1'b0, src_h}) ? 8'd0 : yacc[13:6];
    wire [9:0]  s0_w = yacc_neg_w ? (src_h - 10'd1) :
                       ({1'b0, yacc[25:14]} >= {1'b0, src_h}) ? 10'd0 :
                       (src_h - 10'd1 - yacc[25:14]);
    wire [9:0]  s1_w = yacc_neg_w ? (src_h - 10'd1) :
                       ({1'b0, yacc[25:14]} >= {1'b0, src_h}) ? 10'd0 :
                       (yacc[25:14] == src_h - 10'd1) ? (src_h - 10'd1 - yacc[25:14]) :
                       (src_h - 10'd2 - yacc[25:14]);

    // ================= 主 FSM =================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= S_IDLE;
            busy_r         <= 1'b0;
            // st_sync 在独立 always 块中驱动，此处不重复
            src_w          <= 11'd1;
            src_h          <= 11'd1;
            src_base       <= 21'd0;
            dst_base       <= 21'd0;
            dx             <= 26'd0;
            dy             <= 26'd0;
            row_words      <= 10'd1;
            div_doing      <= 1'b0;
            div_cnt        <= 6'd0;
            div_rem        <= 26'd0;
            div_quo        <= 26'd0;
            div_work       <= 26'd0;
            divisor        <= 26'd0;
            yacc           <= 26'd0;
            out_y          <= 10'd0;
            yf8            <= 8'd0;
            s0             <= 10'd0;
            s1             <= 10'd0;
            row_pair_valid <= 1'b0;
            cache_s0       <= 10'h3FF;
            cache_s1       <= 10'h3FF;
            fetch_left     <= 32'd0;
            fetch_wi       <= 11'd0;
            fetch_row      <= 1'b0;
            fetch_active   <= 1'b0;
            fetch_burst_left <= 8'd0;
            cmd_valid      <= 1'b0;
            cmd_addr       <= 21'd0;
            cmd_len        <= 8'd0;
            ram_we         <= 1'b0;
            ram_waddr      <= 9'd0;
            ram_wdata      <= 32'd0;
            ram_wsel       <= 1'b0;
            ram_rd         <= 1'b0;
            ram_r0a        <= 9'd0;
            ram_r0b        <= 9'd0;
            ram_r1a        <= 9'd0;
            ram_r1b        <= 9'd0;
            px_x           <= 10'd0;
            xacc           <= 26'd0;
            pxv_raw        <= 1'b0;
            x_int_raw      <= 12'd0;
            xf8_raw        <= 8'd0;
            yf8_raw        <= 8'd0;
            x_int_d1       <= 12'd0;
            xf8_d1         <= 8'd0;
            yf8_d1         <= 8'd0;
            pxv_d1         <= 1'b0;
            xf8_d2         <= 8'd0;
            yf8_d2         <= 8'd0;
            pxv_d2         <= 1'b0;
            yf8_d3         <= 8'd0;
            pxv_d3         <= 1'b0;
            wr_en          <= 1'b0;
            wr_addr        <= 21'd0;
            wr_din         <= 32'd0;
            wr_cnt         <= 21'd0;
            done_toggle    <= 1'b0;
        end else begin
            // 完成事件是跨时钟域的持久 toggle；不能每拍清零，否则接收域可能漏采样。
            ram_we      <= 1'b0;
            ram_rd      <= 1'b0;
            wr_en       <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (st_pulse) begin
                        busy_r    <= 1'b1;
                        src_w     <= (cfg_w == 0) ? 11'd1 : cfg_w;
                        src_h     <= (cfg_h == 0) ? 11'd1 : cfg_h;
                        src_base  <= cfg_src_base;
                        dst_base  <= cfg_dst_base;
                        row_words <= (cfg_w + 11'd1) >> 1;
                        div_doing <= 1'b0;
                        div_cnt   <= 6'd26;
                        div_rem   <= 26'd0;
                        div_quo   <= 26'd0;
                        div_work  <= {15'd0, cfg_w} << FRAC;
                        divisor   <= OUT_W;
                        state     <= S_DIV;
                    end
                end

                S_DIV: begin
                    div_rem  <= rem_ge ? (rem_cand[25:0] - divisor) : rem_cand[25:0];
                    div_quo  <= {div_quo[24:0], rem_ge};
                    div_work <= {div_work[24:0], 1'b0};
                    if (div_cnt == 6'd1) begin
                        if (!div_doing) begin
                            dx        <= {div_quo[24:0], rem_ge};
                            div_doing <= 1'b1;
                            div_cnt   <= 6'd26;
                            div_rem   <= 26'd0;
                            div_quo   <= 26'd0;
                            div_work  <= {15'd0, src_h} << FRAC;
                            divisor   <= OUT_H;
                        end else begin
                            dy             <= {div_quo[24:0], rem_ge};
                            yacc           <= 26'd0;
                            out_y          <= 10'd0;
                            row_pair_valid <= 1'b0;
                            state          <= S_LINE;
                        end
                    end else begin
                        div_cnt <= div_cnt - 6'd1;
                    end
                end

                S_LINE: begin
                    if (out_y == OUT_H) begin
                        state <= S_DONE;
                    end else begin
                        yf8 <= yf8_w;
                        s0  <= s0_w;
                        s1  <= s1_w;
                        yacc <= yacc + dy;
                        out_y <= out_y + 10'd1;
                        pair_hit = row_pair_valid && (cache_s0 == s0_w) && (cache_s1 == s1_w);
                        if (pair_hit) begin
                            // cache 命中: 重置像素坐标，直接进 S_RUN
                            px_x <= 10'd0;
                            xacc <= (dx >> 1) - (FR_FULL >> 1);
                            pxv_raw <= 1'b0;
                            pxv_d1  <= 1'b0;
                            pxv_d2  <= 1'b0;
                            pxv_d3  <= 1'b0;
                            state   <= S_RUN;
                        end else begin
                            state <= S_FWR;
                        end
                    end
                end

                S_FWR: begin
                    if (!fetch_active) begin
                        fetch_active   <= 1'b1;
                        fetch_row      <= 1'b0;
                        fetch_wi       <= 11'd0;
                        // 总字数: s0==s1 只取 1 行
                        fetch_left     <= (s0 == s1) ? {22'd0, row_words}
                                                     : {21'd0, row_words, 1'b0};
                        cmd_valid      <= 1'b1;
                        cmd_addr       <= src_base + s1 * row_words;
                        cmd_len        <= ({22'd0, row_words} > 32'd128) ? 8'd128
                                                                         : row_words[7:0];
                        state          <= S_FDA;
                    end
                end

                S_FDA: begin
                    if (cmd_valid && cmd_ready) begin
                        cmd_valid        <= 1'b0;
                        fetch_burst_left <= cmd_len;
                    end else if (rsp_valid) begin
                        // 同拍写两份到行 RAM
                        // fetch_row=0 → s1 行 → r1a/r1b; fetch_row=1 → s0 行 → r0a/r0b
                        ram_we     <= 1'b1;
                        ram_waddr  <= fetch_wi[8:0];
                        ram_wdata  <= rsp_data;
                        ram_wsel   <= ~fetch_row;
                        fetch_wi   <= fetch_wi + 11'd1;
                        fetch_left <= fetch_left - 32'd1;
                        // 行完成 → 切下一行
                        if (fetch_wi[10:0] == {1'b0, row_words} - 11'd1) begin
                            fetch_row <= 1'b1;
                            fetch_wi  <= 11'd0;
                        end
                        // 突发排空且还有剩余 → 发下一簇
                        fetch_burst_left <= fetch_burst_left - 8'd1;
                        if (fetch_burst_left == 8'd1 && fetch_left > 32'd1) begin
                            cmd_valid <= 1'b1;
                            cmd_addr  <= cmd_addr + {13'd0, cmd_len};  // 按实际簇长推进
                            cmd_len   <= (fetch_left - 32'd1 > 32'd128) ? 8'd128
                                                                         : (fetch_left - 32'd1);
                        end
                        // 最后一个字 → 进入 S_RUN
                        if (fetch_left == 32'd1) begin
                            fetch_active   <= 1'b0;
                            row_pair_valid <= 1'b1;
                            cache_s0       <= s0;
                            cache_s1       <= s1;
                            px_x           <= 10'd0;
                            xacc           <= (dx >> 1) - (FR_FULL >> 1);
                            cmd_valid      <= 1'b0;
                            state          <= S_RUN;
                        end
                    end
                end

                S_RUN: begin
                    if (px_x < OUT_W) begin
                        ram_rd  <= 1'b1;
                        ram_r0a <= {1'b0, x_int_c[8:1]};
                        ram_r0b <= bram_b_addr;
                        ram_r1a <= {1'b0, x_int_c[8:1]};
                        ram_r1b <= bram_b_addr;
                        pxv_raw   <= 1'b1;
                        x_int_raw <= x_int_c;
                        xf8_raw   <= xf8_c;
                        yf8_raw   <= yf8;
                        xacc     <= xacc + dx;
                        px_x     <= px_x + 10'd1;
                    end else begin
                        pxv_raw <= 1'b0;
                        if (!pxv_raw && !pxv_d1 && !pxv_d2 && !pxv_d3 && !wr_en) begin
                            state <= S_LINE;
                        end
                    end
                end

                S_DONE: begin
                    done_toggle <= ~done_toggle;
                    busy_r      <= 1'b0;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase

            // ---- 流水线 S1→S2 延迟: raw → d1（对齐 BRAM dout 的 1 拍延迟） ----
            pxv_d1   <= pxv_raw;
            x_int_d1 <= x_int_raw;
            xf8_d1   <= xf8_raw;
            yf8_d1   <= yf8_raw;

            // ---- 流水线 S2: BRAM dout → 拆包 RGB888 ----
            if (pxv_d1) begin
                t0r <= ext_t0r; t0g <= ext_t0g; t0b <= ext_t0b;
                t1r <= ext_t1r; t1g <= ext_t1g; t1b <= ext_t1b;
                b0r <= ext_b0r; b0g <= ext_b0g; b0b <= ext_b0b;
                b1r <= ext_b1r; b1g <= ext_b1g; b1b <= ext_b1b;
                xf8_d2 <= xf8_d1;
                yf8_d2 <= yf8_d1;
                pxv_d2 <= 1'b1;
            end else begin
                pxv_d2 <= 1'b0;
            end

            // ---- 流水线 S3: 行内插值 h（DSP 优化: p*(256-w)+q*w = (p<<8)+(q-p)*w） ----
            if (pxv_d2) begin
                h0r <= {t0r, 8'd0} + ($signed({1'b0, t1r}) - $signed({1'b0, t0r})) * $signed({1'b0, xf8_d2});
                h0g <= {t0g, 8'd0} + ($signed({1'b0, t1g}) - $signed({1'b0, t0g})) * $signed({1'b0, xf8_d2});
                h0b <= {t0b, 8'd0} + ($signed({1'b0, t1b}) - $signed({1'b0, t0b})) * $signed({1'b0, xf8_d2});
                h1r <= {b0r, 8'd0} + ($signed({1'b0, b1r}) - $signed({1'b0, b0r})) * $signed({1'b0, xf8_d2});
                h1g <= {b0g, 8'd0} + ($signed({1'b0, b1g}) - $signed({1'b0, b0g})) * $signed({1'b0, xf8_d2});
                h1b <= {b0b, 8'd0} + ($signed({1'b0, b1b}) - $signed({1'b0, b0b})) * $signed({1'b0, xf8_d2});
                yf8_d3 <= yf8_d2;
                pxv_d3 <= 1'b1;
            end else begin
                pxv_d3 <= 1'b0;
            end

            // ---- 流水线 S4: 行间插值 + 写出 ----
            if (pxv_d3) begin
                wr_en   <= 1'b1;
                wr_addr <= dst_base + wr_cnt;
                wr_din  <= {out_r, out_g, out_b, 8'd0};
                wr_cnt  <= wr_cnt + 21'd1;
            end else begin
                wr_en <= 1'b0;
            end
        end
    end

endmodule
