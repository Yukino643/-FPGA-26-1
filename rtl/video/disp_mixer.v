// disp_mixer.v — 双页显示混合器（video_clk 域，计划书 5.2.4）
// 消费两路行预取 FIFO；DE 期间每拍必出一像素：
//   非转场: 直通 A
//   淡入淡出: blend(A, B, alpha)
//   滑动: 边界后取 B，边界前 16px 软边渐变
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
    input  wire [7:0]  alpha,          // FADE: B 权重
    input  wire [9:0]  boundary,       // SLIDE: 边界
    input  wire [1:0]  slide_axis,     // 0 无 1 左(按x) 2 上(按y)

    output wire [23:0] rgb,            // 与 de_al 同拍（组合，供 OSD/AXIS 同拍采样）
    output reg  [31:0] underflow_cnt
);
`include "blend_fn.vh"

    wire pop_a = de_al;
    wire pop_b = de_al && tr_active;
    assign a_rd_en = pop_a;
    assign b_rd_en = pop_b;

    wire a_droppd = de_al && a_empty;
    wire b_droppd = de_al && tr_active && b_empty;

    // 像素数据取 RGB24（FIFO 字低 24 位）
    wire [23:0] pa = a_rd_data[23:0];
    wire [23:0] pb = b_rd_data[23:0];

    // 滑动软边 α: 距边界 16px 内线性 0→255
    wire in_slide_x = (slide_axis == 2'd1);
    wire in_slide_y = (slide_axis == 2'd2);
    wire [9:0] pos   = in_slide_y ? {1'b0, y} : x;
    wire from_b_hard = (in_slide_x || in_slide_y) && (pos >= boundary);
    wire [9:0] dist  = (pos >= boundary) ? 10'd0 : (boundary - pos);
    wire [8:0] alpha_slide = from_b_hard ? 9'd256 :
                             (dist >= 10'd16) ? 9'd0 :
                             {1'b0, (dist[3:0] << 4)};     // 16px 软边 0..240

    wire [7:0] a_eff = (slide_axis != 2'd0) ? (alpha_slide[8] ? 8'd255 : alpha_slide[7:0])
                                          : alpha;

    wire use_b   = tr_active && !a_droppd && !b_droppd;
    // α=0/255 快速直通: 免乘法且结果精确（255 混合有 (fg*255+127)>>8 的 -1 舍入）
    wire [23:0] blended = (a_eff == 8'd255) ? pb :
                          (a_eff == 8'd0)   ? pa :
                          blend_pix(pb, pa, a_eff);
    wire [23:0] mixed = use_b ? blended : pa;
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
