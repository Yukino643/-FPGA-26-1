// mem_mpu.v — SDRAM 读口多主仲裁器（计划书 5.2 "伪双端口"核心）
// 三个读请求方共享 sdr_as_ram 的单读口；写口双写方互斥选择（装载写 / 缩放写，
// 二者由装载流程状态机保证不同时工作）。
//
// 协议（对齐官方 frame_fifo_read 的用法）：
//   命令期: 拉高 App_rd_en 共 len 拍，地址每拍自增（控制器按拍采样）；
//   返回期: 控制器稍后以 Sdr_rd_en 逐拍返还恰好 len 拍数据（不可暂停）；
//   间隔期: 末个命令拍后至少 GAP=10 拍不再发新命令（对齐官方 rd_delay 习惯）。
//
// 仲裁：A(显示) > B(转场) > C(缩放) 固定优先级 + 防饿死:
//   A 连续 MAX_A_RUN 簇且有低优先方在等 → 让位；B 连续 MAX_B_RUN 簇且 C 在等 → C。
//   带宽核算（125M×4B=500MB/s 峰值，55% 有效 ≈275MB/s）:
//     默认 8/8/4 → A≥8/12×275≈165MB/s(显示需 ~100)，C≥4/12×275≈83MB/s(缩放读足用)。
// 请求方契约：cmd 被 ready 接收后，必须能无反压地收满 len 拍 rsp（请求方自带 FIFO/缓冲）。
module mem_mpu #(
    parameter ADDR_BITS = 21,
    parameter MAX_A_RUN = 4,     // A 连续簇数上限（B/C 等待时）
    parameter MAX_B_RUN = 8,     // B 连续簇数上限（C 等待时）
    parameter MAX_C_RUN = 4,     // C 连续簇数上限
    parameter GAP       = 10     // 簇间静默拍数（对齐官方 rd_delay=10）
)(
    input  wire                      clk,
    input  wire                      rst,

    // 读请求方 A（显示读出，最高优先级）
    input  wire                      A_cmd_valid,
    input  wire [ADDR_BITS-1:0]      A_cmd_addr,
    input  wire [7:0]                A_cmd_len,      // 1..128 拍
    output wire                      A_cmd_ready,
    output wire                      A_rsp_valid,
    output wire [31:0]               A_rsp_data,
    output wire                      A_rsp_last,

    // 读请求方 B（转场第二页读）
    input  wire                      B_cmd_valid,
    input  wire [ADDR_BITS-1:0]      B_cmd_addr,
    input  wire [7:0]                B_cmd_len,
    output wire                      B_cmd_ready,
    output wire                      B_rsp_valid,
    output wire [31:0]               B_rsp_data,
    output wire                      B_rsp_last,

    // 读请求方 C（缩放源图读，W6 新增）
    input  wire                      C_cmd_valid,
    input  wire [ADDR_BITS-1:0]      C_cmd_addr,
    input  wire [7:0]                C_cmd_len,
    output wire                      C_cmd_ready,
    output wire                      C_rsp_valid,
    output wire [31:0]               C_rsp_data,
    output wire                      C_rsp_last,

    // 控制器读口
    output reg                       App_rd_en,
    output reg   [ADDR_BITS-1:0]     App_rd_addr,
    input  wire                      Sdr_rd_en,
    input  wire [31:0]               Sdr_rd_dout,
    input  wire                      Sdr_init_done,
    input  wire                      Sdr_busy,
    input  wire                      source_write_busy,
    input  wire                      scaler_write_request,
    output wire                      read_busy,
    output wire                      write_ready,
    output wire                      idle,

    // 写方 1（素材装载 frame_read_write）
    input  wire                      App_wr_en_u,
    input  wire [ADDR_BITS-1:0]      App_wr_addr_u,
    input  wire [31:0]               App_wr_din_u,
    input  wire [3:0]                App_wr_dm_u,
    // 写方 2（缩放引擎，W6 新增；wr2_active=1 时接管写口）
    input  wire                      App_wr2_en_u,
    input  wire [ADDR_BITS-1:0]      App_wr2_addr_u,
    input  wire [31:0]               App_wr2_din_u,
    input  wire [3:0]                App_wr2_dm_u,
    input  wire                      wr2_active,
    // 控制器写口
    output wire                      App_wr_en,
    output wire [ADDR_BITS-1:0]      App_wr_addr,
    output wire [31:0]               App_wr_din,
    output wire [3:0]                App_wr_dm
);

    localparam S_IDLE  = 2'd0;
    localparam S_CMD   = 2'd1;   // 发命令拍
    localparam S_DRAIN = 2'd2;   // 等数据返还 + 簇间静默

    localparam G_A = 2'd0, G_B = 2'd1, G_C = 2'd2;

    reg [1:0]  state;
    reg [1:0]  grant_sel;         // 当前簇归属
    reg [ADDR_BITS-1:0] cmd_addr;
    reg [7:0]  cmd_len;
    reg [7:0]  cmd_beats;         // 已发命令拍
    reg [7:0]  rsp_beats;         // 已收数据拍
    reg [3:0]  gap_cnt;           // 距末个命令拍的静默计数
    reg [3:0]  a_run, b_run, c_run;   // 各口连续簇计数
    reg [3:0]  write_gap;

    wire a_wants = A_cmd_valid;
    wire b_wants = B_cmd_valid;
    wire c_wants = C_cmd_valid;

    // 让位条件
    wire a_yield = (a_run >= MAX_A_RUN) && (b_wants || c_wants);
    wire b_yield = (b_run >= MAX_B_RUN) && c_wants;

    wire a_allow = a_wants && !a_yield;
    wire b_allow = b_wants && !a_allow && !b_yield;
    wire c_allow = c_wants && !a_allow && !b_allow;

    // 初始化或刷新期间硬核可能丢弃 App 读命令，禁止仲裁器提前接收。
    // 官方接口为单端口：写方先声明占用，读方保持占用到返回和静默期结束。
    assign read_busy = (state != S_IDLE);
    assign write_ready = !read_busy && Sdr_init_done && !Sdr_busy &&
                         !source_write_busy && (write_gap == 0);
    wire mem_accept_window = write_ready && !scaler_write_request && !App_wr_en;
    // 实际读返回和写尾拍保护间隔全部结束，才允许媒体管线清空FIFO。
    assign idle = !read_busy && !Sdr_busy && !source_write_busy && (write_gap==0) &&
                  !scaler_write_request && !App_wr_en && !wr2_active;
    assign A_cmd_ready = mem_accept_window && a_allow;
    assign B_cmd_ready = mem_accept_window && b_allow;
    assign C_cmd_ready = mem_accept_window && c_allow;

    wire [1:0] grant_now = a_allow ? G_A : b_allow ? G_B : G_C;
    wire cmd_accept = A_cmd_ready || B_cmd_ready || C_cmd_ready;

    // 返回数据可能与命令拍重叠，S_CMD 期间也必须路由和计数。
    wire rsp_window = (state == S_CMD) || (state == S_DRAIN);
    assign A_rsp_valid = rsp_window && (grant_sel == G_A) && Sdr_rd_en;
    assign B_rsp_valid = rsp_window && (grant_sel == G_B) && Sdr_rd_en;
    assign C_rsp_valid = rsp_window && (grant_sel == G_C) && Sdr_rd_en;
    assign A_rsp_data  = Sdr_rd_dout;
    assign B_rsp_data  = Sdr_rd_dout;
    assign C_rsp_data  = Sdr_rd_dout;
    wire rsp_last_beat = Sdr_rd_en && (rsp_beats == cmd_len - 8'd1);
    assign A_rsp_last  = rsp_window && (grant_sel == G_A) && rsp_last_beat;
    assign B_rsp_last  = rsp_window && (grant_sel == G_B) && rsp_last_beat;
    assign C_rsp_last  = rsp_window && (grant_sel == G_C) && rsp_last_beat;

    // 写口二选一（协议互斥: 缩放期间装载写方必须空闲）
    assign App_wr_en   = wr2_active ? App_wr2_en_u   : App_wr_en_u;
    assign App_wr_addr = wr2_active ? App_wr2_addr_u : App_wr_addr_u;
    assign App_wr_din  = wr2_active ? App_wr2_din_u  : App_wr_din_u;
    assign App_wr_dm   = wr2_active ? App_wr2_dm_u   : App_wr_dm_u;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_IDLE;
            grant_sel   <= G_A;
            cmd_addr    <= {ADDR_BITS{1'b0}};
            cmd_len     <= 8'd0;
            cmd_beats   <= 8'd0;
            rsp_beats   <= 8'd0;
            gap_cnt     <= 4'd0;
            a_run       <= 4'd0;
            b_run       <= 4'd0;
            c_run       <= 4'd0;
            App_rd_en   <= 1'b0;
            App_rd_addr <= {ADDR_BITS{1'b0}};
            write_gap   <= 4'd0;
        end else begin
            if (App_wr_en) write_gap <= GAP;
            else if (write_gap != 0) write_gap <= write_gap - 4'd1;
            case (state)
                S_IDLE: begin
                    App_rd_en <= 1'b0;
                    if (cmd_accept) begin
                        grant_sel   <= grant_now;
                        cmd_addr    <= A_cmd_ready ? A_cmd_addr :
                                       B_cmd_ready ? B_cmd_addr : C_cmd_addr;
                        cmd_len     <= A_cmd_ready ? A_cmd_len  :
                                       B_cmd_ready ? B_cmd_len  : C_cmd_len;
                        cmd_beats   <= 8'd0;
                        rsp_beats   <= 8'd0;
                        gap_cnt     <= 4'd0;
                        // 连续计数: 中选者饱和递增，其余清零
                        a_run <= (grant_now == G_A) ? ((a_run < 4'd15) ? a_run + 4'd1 : a_run) : 4'd0;
                        b_run <= (grant_now == G_B) ? ((b_run < 4'd15) ? b_run + 4'd1 : b_run) : 4'd0;
                        c_run <= (grant_now == G_C) ? ((c_run < 4'd15) ? c_run + 4'd1 : c_run) : 4'd0;
                        App_rd_addr <= grant_now == G_A ? A_cmd_addr :
                                       grant_now == G_B ? B_cmd_addr : C_cmd_addr;
                        App_rd_en   <= 1'b1;           // 首个命令拍（寄存输出，下一拍生效）
                        state       <= S_CMD;
                    end
                end

                S_CMD: begin
                    // 本拍之后是否还有命令拍：有则保持 en，无则拉低（避免多出一拍）
                    App_rd_en   <= (cmd_beats != cmd_len - 8'd1);
                    App_rd_addr <= App_rd_addr + {{(ADDR_BITS-1){1'b0}}, 1'b1};
                    cmd_beats   <= cmd_beats + 8'd1;
                    gap_cnt     <= 4'd0;
                    if (Sdr_rd_en)
                        rsp_beats <= rsp_beats + 8'd1;
                    if (cmd_beats == cmd_len - 8'd1)       // 末个命令拍
                        state <= S_DRAIN;
                end

                S_DRAIN: begin
                    App_rd_en <= 1'b0;
                    if (Sdr_rd_en)
                        rsp_beats <= rsp_beats + 8'd1;
                    if (gap_cnt < GAP)
                        gap_cnt <= gap_cnt + 4'd1;

                    if ((rsp_beats == cmd_len) && (gap_cnt >= GAP))
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
