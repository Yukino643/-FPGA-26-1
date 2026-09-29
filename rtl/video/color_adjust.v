// color_adjust.v — W8: 亮度/对比度/色温硬件像素管线
//
// 公式（计划书 5.10）:
//   R' = clamp(((R-128)*C)>>8 + 128 + Br + T)
//   G' = clamp(((G-128)*C)>>8 + 128 + Bg)
//   B' = clamp(((B-128)*C)>>8 + 128 + Bb - T)
//
// C = 对比度 0~255（128=1.0）
// B = 亮度偏移 -128~+127
// T = 色温偏移 -128~+127（暖屏 R+ B-，冷屏反向）
//
// 全流水 1 级，位于混合之后、HDMI 核 AXIS 之前
module color_adjust(
    input  wire        clk,
    input  wire        rst,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    // 参数（准静态，按键/拨码调节）
    input  wire [7:0]  contrast,     // 0~255, 128=1.0
    input  wire signed [7:0] brightness,  // -128~+127
    input  wire signed [7:0] color_temp,  // -128~+127
    // 输出（延迟 1 拍）
    output reg         de_out,
    output reg  [23:0] rgb_out
);

    wire [7:0] r_in = rgb_in[23:16];
    wire [7:0] g_in = rgb_in[15:8];
    wire [7:0] b_in = rgb_in[7:0];

    // (pixel - 128) * contrast，有符号 16bit
    wire signed [15:0] r_diff = $signed({8'd0, r_in}) - 16'sd128;
    wire signed [15:0] g_diff = $signed({8'd0, g_in}) - 16'sd128;
    wire signed [15:0] b_diff = $signed({8'd0, b_in}) - 16'sd128;

    wire signed [23:0] r_prod = r_diff * $signed({8'd0, contrast});
    wire signed [23:0] g_prod = g_diff * $signed({8'd0, contrast});
    wire signed [23:0] b_prod = b_diff * $signed({8'd0, contrast});

    // >>7 + 128 + offset（C=128 → 1.0x）
    wire signed [15:0] r_adj = (r_prod >>> 7) + 16'sd128 + $signed(brightness) + $signed(color_temp);
    wire signed [15:0] g_adj = (g_prod >>> 7) + 16'sd128 + $signed(brightness);
    wire signed [15:0] b_adj = (b_prod >>> 7) + 16'sd128 + $signed(brightness) - $signed(color_temp);

    // clamp 0~255
    wire [7:0] r_clamped = r_adj[15] ? 8'd0 : (r_adj > 16'sd255) ? 8'd255 : r_adj[7:0];
    wire [7:0] g_clamped = g_adj[15] ? 8'd0 : (g_adj > 16'sd255) ? 8'd255 : g_adj[7:0];
    wire [7:0] b_clamped = b_adj[15] ? 8'd0 : (b_adj > 16'sd255) ? 8'd255 : b_adj[7:0];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            de_out  <= 1'b0;
            rgb_out <= 24'd0;
        end else begin
            de_out  <= de_in;
            rgb_out <= {r_clamped, g_clamped, b_clamped};
        end
    end

endmodule
