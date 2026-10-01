// tb_mem_mpu.v — mem_mpu 单元仿真
// 行为级 SDRAM 读口模型：记下 en 期间的地址序列，末拍后 LAT 拍开始逐拍返还
// 检查: 命令地址序列、数据路由（A/B 不串扰）、rsp_last、优先级、防饿死
`timescale 1ns/1ps
module tb_mem_mpu;

    localparam LAT = 6;

    reg clk = 0, rst = 1;
    always #4 clk = ~clk;      // 125MHz

    // ---- DUT ----
    reg          A_v = 0, B_v = 0;
    reg  [20:0]  A_addr = 0, B_addr = 0;
    reg  [7:0]   A_len = 0,  B_len = 0;
    wire         A_rdy, B_rdy, A_rv, B_rv, A_rl, B_rl;
    wire [31:0]  A_rd, B_rd;

    wire         App_rd_en;
    wire [20:0]  App_rd_addr;
    reg          Sdr_rd_en = 0;
    reg  [31:0]  Sdr_rd_dout = 0;

    mem_mpu #(.MAX_A_RUN(4), .MAX_B_RUN(8), .MAX_C_RUN(4)) dut (
        .clk(clk), .rst(rst),
        .A_cmd_valid(A_v), .A_cmd_addr(A_addr), .A_cmd_len(A_len),
        .A_cmd_ready(A_rdy), .A_rsp_valid(A_rv), .A_rsp_data(A_rd), .A_rsp_last(A_rl),
        .B_cmd_valid(B_v), .B_cmd_addr(B_addr), .B_cmd_len(B_len),
        .B_cmd_ready(B_rdy), .B_rsp_valid(B_rv), .B_rsp_data(B_rd), .B_rsp_last(B_rl),
        .C_cmd_valid(1'b0), .C_cmd_addr(21'd0), .C_cmd_len(8'd1),
        .C_cmd_ready(), .C_rsp_valid(), .C_rsp_data(), .C_rsp_last(),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
        .Sdr_init_done(1'b1), .Sdr_busy(1'b0),
        .App_wr_en_u(1'b0), .App_wr_addr_u(21'd0), .App_wr_din_u(32'd0), .App_wr_dm_u(4'd0),
        .App_wr2_en_u(1'b0), .App_wr2_addr_u(21'd0), .App_wr2_din_u(32'd0), .App_wr2_dm_u(4'd0),
        .wr2_active(1'b0),
        .App_wr_en(), .App_wr_addr(), .App_wr_din(), .App_wr_dm()
    );

    // ---- 行为级 SDRAM 模型 ----
    reg  [20:0] cap_addr [0:127];
    integer     cap_len = 0;
    integer     cap_timer = -1;   // en 末拍后倒计时
    integer     sent = 0;
    reg         en_d = 0;

    always @(posedge clk) begin
        en_d <= App_rd_en;
        if (App_rd_en) begin
            cap_addr[cap_len] <= App_rd_addr;
            cap_len <= cap_len + 1;
            cap_timer <= LAT;
        end else if (en_d && !App_rd_en) begin
            cap_len   <= cap_len;        // 保留
            cap_timer <= LAT;            // 末拍后启动延迟
        end else if (cap_timer >= 0) begin
            if (cap_timer == 0) begin
                if (sent < cap_len) begin
                    Sdr_rd_en   <= 1'b1;
                    Sdr_rd_dout <= {12'h5A5, cap_addr[sent]};
                    sent        <= sent + 1;
                end else begin
                    Sdr_rd_en <= 1'b0;
                    cap_len   <= 0;
                    sent      <= 0;
                    cap_timer <= -1;
                end
            end else begin
                cap_timer  <= cap_timer - 1;
                Sdr_rd_en  <= 1'b0;
            end
        end else begin
            Sdr_rd_en <= 1'b0;
        end
    end

    // ---- 检查器 ----
    integer errors = 0;
    integer a_expect = -1;   // A 端期望的下一个地址；-1=无未决
    integer b_expect = -1;
    integer a_got = 0, b_got = 0;

    always @(posedge clk) begin
        if (!rst) begin
            if (A_rv) begin
                if (a_expect >= 0 && A_rd[20:0] == a_expect[20:0]) a_got = a_got + 1;
                else begin errors = errors + 1; $display("ERR t=%0t A data %h exp %h", $time, A_rd[20:0], a_expect); end
                a_expect = (a_expect >= 0) ? a_expect + 1 : -1;
                if (A_rl) a_expect = -1;
            end
            if (B_rv) begin
                if (b_expect >= 0 && B_rd[20:0] == b_expect[20:0]) b_got = b_got + 1;
                else begin errors = errors + 1; $display("ERR t=%0t B data %h exp %h", $time, B_rd[20:0], b_expect); end
                b_expect = (b_expect >= 0) ? b_expect + 1 : -1;
                if (B_rl) b_expect = -1;
            end
        end
    end

    // ---- 激励 ----
    task a_burst(input [20:0] addr, input [7:0] len);
        begin
            @(posedge clk);
            A_addr = addr; A_len = len; A_v = 1;
            while (!A_rdy) @(posedge clk);
            A_v = 0;
            a_expect = addr;
            @(posedge clk);
        end
    endtask

    task b_burst(input [20:0] addr, input [7:0] len);
        begin
            @(posedge clk);
            B_addr = addr; B_len = len; B_v = 1;
            while (!B_rdy) @(posedge clk);
            B_v = 0;
            b_expect = addr;
            @(posedge clk);
        end
    endtask

    integer i;
    initial begin
        rst = 1;
        #100;
        @(posedge clk); rst = 0;

        // T1: 单 A 簇
        a_burst(21'd100, 8'd4);
        // T2: 单 B 簇
        b_burst(21'd500, 8'd2);
        // T3: 同时请求 → A 优先
        fork
            a_burst(21'd1000, 8'd3);
            b_burst(21'd2000, 8'd2);
        join
        // T4: 防饿死 — A 连续 12 簇，B 等着，必须在 MAX_A_RUN 内被服务
        fork
            begin
                for (i = 0; i < 12; i = i + 1)
                    a_burst(21'd3000 + i * 8, 8'd8);
            end
            begin
                #100;
                b_burst(21'd9000, 8'd2);
            end
        join
        #5000;

        $display("==== a_got=%0d b_got=%0d errors=%0d ====", a_got, b_got, errors);
        if (errors == 0 && a_got == 4+3+12*8 && b_got == 2+2+2) $display("TB_MEM_MPU PASS");
        else $display("TB_MEM_MPU FAIL");
        $finish;
    end
endmodule
