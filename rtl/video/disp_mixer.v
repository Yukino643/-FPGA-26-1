// disp_mixer.v — 双页显示混合器（video_clk 域，计划书 5.2.4）
// 消费两路行预取 FIFO；DE 期间每拍必出一像素：
//   非转场: 直通 A
//   淡入淡出: A 页乘亮度，中间黑帧换页
//   滑动: 边界前取 B，边界前 16px 软边渐变
// 下溢检测: de 期间 FIFO 空则计黑并累加 underflow_cnt（供监视台 W10）
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
    input  wire        fade_black,    // 淡出到黑/淡入：只使用 A 页亮度
    input  wire [7:0]  alpha,          // 淡出到黑时为 A 亮度；揭示沉降帧为 B 权重
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

    wire a_droppd = de_al && a_empty;
    wire b_droppd = de_al && tr_active && !fade_black && b_empty;

    // SDRAM 页与学长的 TF→HDMI 例程一致，RGB 位于 [31:8]，低字节留空。
    wire [23:0] pa = a_rd_data[31:8];
    wire [23:0] pb = b_rd_data[31:8];

    // 滑动软边 α: 距边界 16px 内线性 0→255
    wire in_slide_x = (slide_axis == 2'd1);
    wire in_slide_y = (slide_axis == 2'd2);
    wire [9:0] pos   = in_slide_y ? {1'b0, y} : x;
    wire [9:0] dist = (pos < boundary) ? (boundary - pos) : 10'd0;
    wire [8:0] alpha_slide = (dist >= 10'd16) ? 9'd256 :
                             {1'b0, dist[3:0], 4'b0000};

    wire [7:0] a_eff = (slide_axis != 2'd0) ? (alpha_slide[8] ? 8'd255 : alpha_slide[7:0])
                                          : alpha;

    wire use_b   = tr_active && !a_droppd && !b_droppd;
    // α=0/255 快速直通: 免乘法且结果精确（255 混合有 (fg*255+127)>>8 的 -1 舍入）
    wire [23:0] blended = (a_eff == 8'd255) ? pb :
                          (a_eff == 8'd0)   ? pa :
                          blend_pix(pb, pa, a_eff);
    wire [23:0] faded = (alpha == 8'd255) ? pa :
                        (alpha == 8'd0) ? 24'd0 : blend_pix(pa, 24'd0, alpha);
    wire [23:0] mixed = fade_black ? faded : (use_b ? blended : pa);
    wire [23:0] out_c = (a_droppd || (tr_active && b_droppd)) ? 24'd0 : mixed;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            underflow_cnt <= 32'd0;
        end else begin
            if (a_droppd || (tr_active && b_droppd))
                underflow_cnt <= underflow_cnt + 32'd1;
        end
    end

    assign rgb = de_al ? out_c : 24'd0;

endmodule
