// tb_scaler.v — W6 缩放引擎单元仿真
// 小尺寸 OUT（160×120）加速；源图渐变图案，恒等测试逐像素比对。
`timescale 1ns/1ps
module tb_scaler;

    localparam OUT_W = 160;
    localparam OUT_H = 120;
    localparam SRC_BASE = 21'hC_B000;
    localparam DST_BASE = 21'h0_0000;

    reg clk125 = 0, rst = 1;
    always #4 clk125 = ~clk125;

    // ---- DUT ----
    reg         start_toggle = 0;
    reg  [10:0] cfg_w = 11'd160, cfg_h = 11'd120;
    wire        cmd_valid, cmd_ready;
    wire [20:0] cmd_addr;
    wire [7:0]  cmd_len;
    reg         rsp_valid = 0;
    reg  [31:0] rsp_data = 0;
    wire        wr_en;
    wire [20:0] wr_addr;
    wire [31:0] wr_din;
    wire        busy, done_toggle;

    scaler #(.OUT_W(OUT_W), .OUT_H(OUT_H)) u_scaler (
        .clk(clk125), .rst(rst),
        .start_toggle(start_toggle),
        .cfg_w(cfg_w), .cfg_h(cfg_h),
        .cfg_src_base(SRC_BASE), .cfg_dst_base(DST_BASE),
        .cmd_valid(cmd_valid), .cmd_addr(cmd_addr), .cmd_len(cmd_len),
        .cmd_ready(cmd_ready), .rsp_valid(rsp_valid), .rsp_data(rsp_data),
        .rsp_last(), .wr_en(wr_en), .wr_addr(wr_addr), .wr_din(wr_din),
        .wr_dm(), .busy(busy), .done_toggle(done_toggle)
    );

    assign cmd_ready = 1'b1;

    // ---- 行为级 SDRAM（真存储） ----
    reg [31:0] sdram [0:2*1024*768];

    // ---- SDRAM 读响应模型 ----
    // 命令接受后 2 拍开始逐拍返回恰好 cmd_len 个字
    reg [20:0] rsp_addr;
    reg [7:0]  rsp_len_latched;
    reg [7:0]  rsp_idx;
    reg [1:0]  rsp_delay;
    reg        rsp_active;

    always @(posedge clk125) begin
        if (rst) begin
            rsp_valid <= 0;
            rsp_data  <= 0;
            rsp_active <= 0;
            rsp_delay <= 0;
            rsp_idx   <= 0;
        end else begin
            rsp_valid <= 0;
            if (cmd_valid && cmd_ready && !rsp_active) begin
                rsp_addr        <= cmd_addr;
                rsp_len_latched <= cmd_len;
                rsp_idx         <= 0;
                rsp_delay       <= 2;
                rsp_active      <= 1;
            end else if (rsp_active) begin
                if (rsp_delay > 0) begin
                    rsp_delay <= rsp_delay - 1;
                end else begin
                    rsp_valid <= 1;
                    rsp_data  <= sdram[rsp_addr + rsp_idx];
                    if (rsp_idx == rsp_len_latched - 1) begin
                        rsp_active <= 0;
                    end else begin
                        rsp_idx <= rsp_idx + 1;
                    end
                end
            end
        end
    end

    // ---- 写入捕获 ----
    always @(posedge clk125) begin
        if (!rst && wr_en) begin
            sdram[wr_addr] <= wr_din;
        end
    end

    // ---- RGB565 打包 ----
    function [15:0] make_565;
        input [7:0] r, g, b;
        begin
            make_565 = {r[7:3], g[7:2], b[7:3]};
        end
    endfunction

    // ---- 源图预载（BMP 自底向上: 内存第 0 行 = 图像最底行） ----
    integer i, j, n, wi, row, col;
    task preload_src;
        input integer W, H;
        reg [15:0] p565;
        reg [7:0] r8, g8, b8;
        begin
            for (i = 0; i < 16384; i = i + 1) sdram[SRC_BASE + i] = 32'h0;
            for (row = 0; row < H; row = row + 1) begin
                for (col = 0; col < W; col = col + 1) begin
                    r8 = col * 255 / (W > 1 ? W - 1 : 1);
                    g8 = (H - 1 - row) * 255 / (H > 1 ? H - 1 : 1);
                    b8 = 128;
                    p565 = make_565(r8, g8, b8);
                    n = row * W + col;
                    wi = n >> 1;
                    if (n[0]) sdram[SRC_BASE + wi][31:16] = p565;
                    else      sdram[SRC_BASE + wi][15:0]  = p565;
                end
            end
        end
    endtask

    // ---- 恒等验证 ----
    integer errors = 0;
    integer done_count = 0;
    reg prev_done = 0;
    integer check_en = 0;

    task verify_identity;
        integer px, py, src_idx, wi, mem_row;
        reg [31:0] src_word, dst_word;
        reg [15:0] src_565;
        reg [7:0] exp_r, exp_g, exp_b, act_r, act_g, act_b;
        begin
            for (py = 0; py < OUT_H; py = py + 1) begin
                for (px = 0; px < OUT_W; px = px + 1) begin
                    // BMP 自底向上: 输出行 py 对应内存行 (H-1-py)
                    mem_row = OUT_H - 1 - py;
                    src_idx = mem_row * OUT_W + px;
                    wi = src_idx >> 1;
                    src_word = sdram[SRC_BASE + wi];
                    src_565 = src_idx[0] ? src_word[31:16] : src_word[15:0];
                    exp_r = {src_565[15:11], src_565[15:13]};
                    exp_g = {src_565[10:5],  src_565[10:9]};
                    exp_b = {src_565[4:0],   src_565[4:2]};
                    dst_word = sdram[DST_BASE + py * OUT_W + px];
                    act_r = dst_word[31:24];
                    act_g = dst_word[23:16];
                    act_b = dst_word[15:8];
                    if (act_r !== exp_r || act_g !== exp_g || act_b !== exp_b) begin
                        errors = errors + 1;
                        if (errors <= 10)
                            $display("ERR(%0d,%0d): got(%h,%h,%h) exp(%h,%h,%h)",
                                     px, py, act_r, act_g, act_b, exp_r, exp_g, exp_b);
                    end
                end
            end
        end
    endtask

    always @(posedge clk125) begin
        if (!rst) begin
            prev_done <= done_toggle;
            // done_toggle 是持久电平翻转，0→1 和 1→0 都代表一次完成事件。
            if (done_toggle !== prev_done) begin
                done_count = done_count + 1;
                $display("=== Done #%0d (t=%0t) ===", done_count, $time);
                if (check_en && (cfg_w == OUT_W) && (cfg_h == OUT_H)) begin
                    verify_identity;
                    $display("Identity check: errors=%0d", errors);
                end
            end
        end
    end

    // ---- 激励 ----
    initial begin
        rst = 1;
        #100;
        @(posedge clk125); rst = 0;
        #100;

        // Test 1: 160×120 → 160×120 恒等
        $display("TEST1: identity 160x120");
        test_id = 1; check_en = 1;
        cfg_w = 11'd160; cfg_h = 11'd120;
        preload_src(160, 120);
        errors = 0;
        @(negedge clk125); start_toggle = ~start_toggle;
        wait(done_count >= 1);
        #200;
        if (errors == 0) $display("TEST1 PASS");
        else $display("TEST1 FAIL errors=%0d", errors);

        // Test 2: 200×150 → 160×120 缩小
        $display("TEST2: downscale 200x150");
        check_en = 0;
        cfg_w = 11'd200; cfg_h = 11'd150;
        preload_src(200, 150);
        @(negedge clk125); start_toggle = ~start_toggle;
        wait(done_count >= 2);
        #200;
        $display("TEST2 done (no crash)");

        // Test 3: 80×60 → 160×120 放大
        $display("TEST3: upscale 80x60");
        cfg_w = 11'd80; cfg_h = 11'd60;
        preload_src(80, 60);
        @(negedge clk125); start_toggle = ~start_toggle;
        wait(done_count >= 3);
        #200;
        $display("TEST3 done (no crash)");

        if (errors == 0) $display("TB_SCALER PASS");
        else $display("TB_SCALER FAIL errors=%0d", errors);
        $finish;
    end

    integer test_id = 0;

    initial begin
        #200_000_000;
        $display("TB_SCALER TIMEOUT state=%0d busy=%b", u_scaler.state, busy);
        $finish;
    end

endmodule
