// subtitle_scroll.v — 字幕亚像素平滑滚动引擎
//
// 底部滚动字幕带，1/4 像素步进，4 相位线性插值
// 字幕内容从 ROM 读取，水平滚动偏移每帧累加
module subtitle_scroll #(
    parameter BAND_Y_START = 9'd420,
    parameter BAND_HEIGHT  = 9'd24,
    parameter SCROLL_SPEED = 4'd1     // 每帧像素数（1/4 像素步进 ×4）
)(
    input  wire        clk,
    input  wire        de_in,
    input  wire [9:0]  x,
    input  wire [8:0]  y,
    input  wire [23:0] bg_rgb,
    input  wire        vs_pulse,      // 帧起始脉冲
    input  wire        enable,        // 字幕开关
    output wire [23:0] rgb_out
);
`include "blend_fn.vh"

    // 滚动偏移（1/4 像素精度，14bit 整数 + 2bit 小数）
    reg [15:0] scroll_pos;   // [15:2]=整数像素, [1:0]=亚像素相位

    always @(posedge clk) begin
        if (vs_pulse)
            scroll_pos <= scroll_pos + SCROLL_SPEED;
    end

    // 字幕文本 ROM（简化：固定字符串）
    localparam TEXT_LEN = 32;
    reg [7:0] text_rom [0:TEXT_LEN-1];
    initial begin
        text_rom[0]  = "W"; text_rom[1]  = "E"; text_rom[2]  = "L";
        text_rom[3]  = "C"; text_rom[4]  = "O"; text_rom[5]  = "M";
        text_rom[6]  = "E"; text_rom[7]  = " ";
        text_rom[8]  = "T"; text_rom[9]  = "O"; text_rom[10] = " ";
        text_rom[11] = "H"; text_rom[12] = "X"; text_rom[13] = "4";
        text_rom[14] = "S"; text_rom[15] = "2"; text_rom[16] = "0";
        text_rom[17] = " "; text_rom[18] = "D"; text_rom[19] = "E";
        text_rom[20] = "M"; text_rom[21] = "O"; text_rom[22] = " ";
        text_rom[23] = " "; text_rom[24] = " "; text_rom[25] = " ";
        text_rom[26] = " "; text_rom[27] = " "; text_rom[28] = " ";
        text_rom[29] = " "; text_rom[30] = " "; text_rom[31] = " ";
    end

    // 当前像素在字幕带内的位置
    wire in_band = (y >= BAND_Y_START) && (y < BAND_Y_START + BAND_HEIGHT);

    // 水平位置 → 文本索引（考虑滚动偏移）
    wire [15:0] scroll_int = {scroll_pos[15:2], 2'b00};  // 整数像素部分
    wire [15:0] text_x = x + scroll_int;
    wire [7:0]  char_idx = text_x[12:3] % TEXT_LEN;      // 每字符 8px
    wire [2:0]  char_col = text_x[2:0];

    // 读取字符
    wire [7:0] current_char = text_rom[char_idx];

    // 简化字模：用字符码直接生成图案（实际应接 font_rom_ascii）
    wire glyph_on = (current_char != 8'h20) && (char_col >= 3'd1) && (char_col <= 3'd6);

    // 亚像素插值：根据相位混合相邻像素
    wire [1:0] phase = scroll_pos[1:0];
    wire [7:0] alpha = (phase == 2'd0) ? 8'd255 :
                       (phase == 2'd1) ? 8'd192 :
                       (phase == 2'd2) ? 8'd128 : 8'd64;

    // 字幕颜色（黄色）
    wire [23:0] sub_color = 24'hFFDD00;
    wire [23:0] blended = blend_pix(sub_color, bg_rgb, alpha);

    assign rgb_out = (enable && in_band && glyph_on) ? blended : bg_rgb;

endmodule
