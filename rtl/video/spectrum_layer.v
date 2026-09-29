// spectrum_layer.v — W8: 频谱条形图图层（底部 32 条）
//
// 输入: fft_spectrum 的 32 bin 幅度值
// 输出: 与背景 alpha 混合的 RGB
//
// 布局: 底部 y∈[400,479]，32 条等宽条形（每条 20px 宽）
// 颜色: 绿→黄→红 渐变（低→高幅度）
module spectrum_layer(
    input  wire        clk,
    input  wire        de_in,
    input  wire [9:0]  x,
    input  wire [8:0]  y,
    input  wire [23:0] bg_rgb,
    input  wire [255:0] bin_mag,    // 32 bin × 8bit 打包向量
    output wire [23:0] rgb_out
);
`include "blend_fn.vh"

    localparam BAR_BOTTOM = 9'd479;
    localparam BAR_MAX_H  = 9'd80;
    localparam BAR_WIDTH  = 10'd20;

    // 当前像素属于哪条 bar
    wire [4:0] bar_idx = x / BAR_WIDTH;   // 0~31
    wire in_bar_area = (y >= BAR_BOTTOM - BAR_MAX_H) && (y <= BAR_BOTTOM);

    // 从打包向量中提取当前 bin 的幅度
    wire [7:0] mag = bin_mag[bar_idx*8 +: 8];

    // 该 bar 的高度（0~80）
    wire [8:0] bar_h = (mag * BAR_MAX_H) >> 8;

    // 当前像素是否在 bar 内
    wire [8:0] bar_top = BAR_BOTTOM - bar_h;
    wire in_bar = in_bar_area && (y >= bar_top) && (bar_idx < 32);

    // 颜色渐变: 低→绿，中→黄，高→红
    wire [7:0] r = (mag > 8'd170) ? 8'd255 : (mag > 8'd85) ? {mag[6:0], 1'b0} : 8'd0;
    wire [7:0] g = (mag > 8'd170) ? {8'd255 - mag[6:0], 1'b0} : 8'd255;
    wire [7:0] b = 8'd0;

    // alpha 混合（bar 半透明）
    wire [23:0] bar_color = {r, g, b};
    wire [7:0]  bar_alpha = 8'd180;
    wire [23:0] blended = blend_pix(bar_color, bg_rgb, bar_alpha);

    assign rgb_out = in_bar ? blended : bg_rgb;

endmodule
