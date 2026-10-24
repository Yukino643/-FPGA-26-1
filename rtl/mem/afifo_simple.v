// afifo_simple.v — 通用双时钟异步 FIFO（FWFT 读：rd_data 常显队头，rd_en 弹出）
// 采用 Cummings Gray 指针结构。空/满标志在各自时钟域注册，读写指针只在
// `enable && !empty/full` 时推进，避免空读、满写和 full->enable->next->full 组合环。
//
// A1 存储体双视图: TD 6.2/EG4 不支持 ram_style 推断属性，双时钟阵列会被映射成
// LUT/mux 树（实测 1.7K LUT/FIFO）。故走 EG_LOGIC_BRAM 原语:
//   综合视图（默认）  : EG_LOGIC_BRAM 原语黑盒，TD 自动落到 BRAM9K
//   仿真视图(-DSIMULATION): 行为模型（约定与官方 sdram.v 的 `ifdef SIMULATION 一致）
// 原语 dob 同步装入 rbin_next 队头；消费者在弹出沿采样旧队头，下一拍可连续读取。
module afifo_simple #(
    parameter DW = 32,
    parameter AW = 10                // 深度 = 2^AW
)(
    input  wire          wr_clk,
    input  wire          wr_rst,
    input  wire          wr_en,
    input  wire [DW-1:0] wr_data,
    output wire          wr_full,
    output wire [AW:0]   wr_usedw,

    input  wire          rd_clk,
    input  wire          rd_rst,
    input  wire          rd_en,
    output wire [DW-1:0] rd_data,
    output wire          rd_empty,
    output wire [AW:0]   rd_usedw
);

    function [AW:0] bin2gray;
        input [AW:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    function [AW:0] gray2bin;
        input [AW:0] g;
        integer i;
        begin
            for (i = AW; i >= 0; i = i - 1)
                gray2bin[i] = ^(g >> i);
        end
    endfunction

    // ---- 指针与握手（指针多一位用于区分空/满） ----
    reg [AW:0] wbin;
    reg [AW:0] rbin;
    reg [AW:0] wgray;
    reg [AW:0] rgray;
    reg        wr_full_r;
    reg        rd_empty_r;

    wire       wr_act = wr_en && !wr_full_r;
    wire       rd_act = rd_en && !rd_empty_r;
    wire [AW:0] wbin_next  = wbin + {{AW{1'b0}}, wr_act};
    wire [AW:0] rbin_next  = rbin + {{AW{1'b0}}, rd_act};
    wire [AW:0] wgray_next = bin2gray(wbin_next);
    wire [AW:0] rgray_next = bin2gray(rbin_next);

    // 灰码指针跨域 2FF 同步
    reg [AW:0] rgray_s1 = 0, rgray_s2 = 0;      // 读指针 → 写域
    reg [AW:0] wgray_s1 = 0, wgray_s2 = 0;      // 写指针 → 读域

    wire [AW:0] rbin_in_w = gray2bin(rgray_s2); // 写域看到的读指针
    wire [AW:0] wbin_in_r = gray2bin(wgray_s2); // 读域看到的写指针

    // 满：下一写 Gray 指针等于同步读指针的最高两位取反版本。
    wire wr_full_next = (wgray_next == {~rgray_s2[AW:AW-1], rgray_s2[AW-2:0]});
    // 空：下一读 Gray 指针追上同步后的写指针。
    wire rd_empty_next = (rgray_next == wgray_s2);

    assign wr_full  = wr_full_r;
    assign wr_usedw = wbin - rbin_in_w;
    assign rd_empty = rd_empty_r;
    assign rd_usedw = wbin_in_r - rbin;
    assign rd_data  = rd_data_int;

    // ---- 存储体（双视图） ----
    wire [DW-1:0] rd_data_int;

`ifdef SIMULATION
    reg [DW-1:0] mem [0:(1<<AW)-1];
    reg [DW-1:0] dob = 0;

    always @(posedge rd_clk) begin
        if (rd_rst) dob <= 0;
        // 同步读提前装入消费后的队头，保证下一拍可连续弹出。
        else        dob <= mem[rbin_next[AW-1:0]];
    end
    assign rd_data_int = dob;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A (DW),
        .DATA_WIDTH_B (DW),
        .ADDR_WIDTH_A (AW),
        .ADDR_WIDTH_B (AW),
        .MODE         ("DP"),
        .REGMODE_A    ("NOREG"),
        .REGMODE_B    ("NOREG"),
        .RESETMODE    ("ASYNC"),
        .IMPLEMENT    ("9K")
    ) u_bram (
        .dia   (wr_data),
        .addra (wbin[AW-1:0]),
        .cea   (1'b1),
        .ocea  (1'b0),
        .clka  (wr_clk),
        .wea   (wr_act),
        .rsta  (1'b0),
        .bea   (1'b0),
        .dib   ({DW{1'b0}}),
        .addrb (rbin_next[AW-1:0]),
        .ceb   (1'b1),
        .oceb  (1'b1),
        .clkb  (rd_clk),
        .web   (1'b0),
        .rstb  (1'b0),
        .beb   (1'b0),
        .doa   (),
        .dob   (rd_data_int)
    );
`endif

    // ---- 时序逻辑 ----
    always @(posedge wr_clk) begin
        if (wr_rst) begin
            wbin     <= 0;
            wgray    <= 0;
            wr_full_r <= 1'b0;
            rgray_s1 <= 0;
            rgray_s2 <= 0;
        end else begin
`ifdef SIMULATION
            if (wr_act) mem[wbin[AW-1:0]] <= wr_data;
`endif
            wbin      <= wbin_next;
            wgray     <= wgray_next;
            wr_full_r <= wr_full_next;
            rgray_s1 <= rgray;
            rgray_s2 <= rgray_s1;
        end
    end

    always @(posedge rd_clk) begin
        if (rd_rst) begin
            rbin     <= 0;
            rgray    <= 0;
            rd_empty_r <= 1'b1;
            wgray_s1 <= 0;
            wgray_s2 <= 0;
        end else begin
            rbin       <= rbin_next;
            rgray      <= rgray_next;
            rd_empty_r <= rd_empty_next;
            wgray_s1 <= wgray;
            wgray_s2 <= wgray_s1;
        end
    end

endmodule
