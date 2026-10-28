// disp_mixer.v — 双页显示混合器（video_clk 域，计划书 5.2.4）
// 消费两路行预取 FIFO；DE 期间每拍必出一像素：
//   非转场: 直通 A
//   淡入淡出: A/B 页交叉混合（不经过黑帧）
//   推移: 两流逐行循环位移后，左侧旧图、右侧新图无缝拼接
// 下溢仍显式计数；不能用错误源列掩盖读流丢拍。
module disp_mixer(
    input  wire        clk,
    input  wire        rst,
    input  wire        de_al,          // pixel_pos_gen 输出的对齐 de
    input  wire [9:0]  x,
    input  wire [8:0]  y,

    // A 流（afifo_simple 读侧, FWFT）
    output wire        a_rd_en,
    input  wire [31:0] a_rd_data,
    input  wire        a_empty,
    // B 流
    output wire        b_rd_en,
    input  wire [31:0] b_rd_data,
    input  wire        b_empty,

    // 转场控制（transition_ctrl）
    input  wire        tr_active,
    input  wire        fade_black,    // 兼容旧模式；当前默认转场不使用黑场
    input  wire [7:0]  alpha,          // 淡变模式中 B 页权重
    input  wire [9:0]  boundary,       // SLIDE: 边界
    input  wire [1:0]  slide_axis,     // 0 无 1 左(按x) 2 上(按y)

    output wire [23:0] rgb,            // 与 de_al 同拍（组合，供 OSD/AXIS 同拍采样）
    output reg  [31:0] underflow_cnt
);
`include "blend_fn.vh"

    wire pop_a = de_al;
    // 两个引擎每帧都预取整帧；即使未混合，也必须同步排空备用页。
    // 否则 B FIFO 残留旧帧前缀，转场时从错误地址开始消费。
    wire pop_b = de_al;
    assign a_rd_en = pop_a;
    assign b_rd_en = pop_b;

    // SDRAM 页与学长的 TF→HDMI 例程一致，RGB 位于 [31:8]，低字节留空。
    wire [23:0] pa = a_rd_data[31:8];
    wire [23:0] pb = b_rd_data[31:8];

    wire horizontal = (slide_axis == 2'd1);
    wire vertical = (slide_axis == 2'd2);
    // 接缝两边来自两图不同源列，禁止用软边混合制造重影。
    wire select_b = horizontal ? ({1'b0,x} >= 11'd640 - {1'b0,boundary}) :
                    vertical ? ({2'b0,y} >= 11'd480 - {1'b0,boundary}) : 1'b0;
    wire [7:0] a_eff = (horizontal || vertical) ? (select_b ? 8'd255 : 8'd0) : alpha;
    wire need_a = !tr_active || fade_black || a_eff != 255;
    wire need_b = tr_active && !fade_black && a_eff != 0;
    wire missing = de_al && ((need_a && a_empty) || (need_b && b_empty));
    // α=0/255 快速直通: 免乘法且结果精确（255 混合有 (fg*255+127)>>8 的 -1 舍入）
    wire [23:0] blended = (a_eff == 8'd255) ? pb :
                          (a_eff == 8'd0)   ? pa :
                          blend_pix(pb, pa, a_eff);
    wire [23:0] faded = (alpha == 8'd255) ? pa :
                        (alpha == 8'd0) ? 24'd0 : blend_pix(pa, 24'd0, alpha);
    wire [23:0] mixed = fade_black ? faded : (tr_active ? blended : pa);
    wire [23:0] out_c = missing ? 24'd0 : mixed;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            underflow_cnt <= 32'd0;
        end else begin
            if (missing)
                underflow_cnt <= underflow_cnt + 32'd1;
        end
    end

    assign rgb = de_al ? out_c : 24'd0;

endmodule
