// monitor_compositor.v — 副通道（HDMI_A）监视台渲染器 v2（A2: BRAM 字库同步读，1 级流水线）
// 纯 BRAM/逻辑直渲染，不访问 SDRAM：8x16 字符网格 80x30。
// 地址路径（字库寻址）用原始 I_x/I_y；混合路径用打 1 拍的 x_d/y_d/de_d。
// 顶层须将监视台 AXIS 的 de/vs 打 1 拍对齐。
//  版本状态: 显示 UPTIME / FRAMES / AV-SYNC / MODE / LAYER 色块 / 底部活动彩条
//  W7 接入真实 sync_dev，W9 接入真实 mode，W10 完善
module monitor_compositor(
    input  wire        I_clk,
    input  wire        I_de,
    input  wire [9:0]  I_x,        // 有效区坐标 0..639
    input  wire [8:0]  I_y,        // 0..479
    input  wire [31:0] I_uptime_sec,
    input  wire [31:0] I_frame_cnt,
    input  wire [15:0] I_sync_dev,
    input  wire [1:0]  I_mode,     // 0:启动 1:广告 2:应急
    input  wire [191:0] I_tf_diag, // 握手快照：TF 板级只读诊断
    output wire [23:0] O_rgb
);

    // ---------------- 配色 ----------------
    localparam [23:0] BG        = 24'h0A1420;   // 深蓝黑底
    localparam [23:0] TITLE_BG  = 24'h134A8A;   // 标题条蓝
    localparam [23:0] TITLE_FG  = 24'hFFFFFF;
    localparam [23:0] TXT_FG    = 24'h7FD4FF;   // 标签淡蓝
    localparam [23:0] VAL_FG    = 24'hFFD75A;   // 数值黄
    localparam [23:0] OK_GREEN  = 24'h33CC55;
    localparam [23:0] EMG_RED   = 24'hFF4444;

    // ---------------- 工具函数（先声明后使用） ----------------
    function [7:0] hex2ascii;
        input [3:0] d;
        begin
            hex2ascii = (d < 4'd10) ? (8'h30 + {4'd0, d}) : (8'h37 + {4'd0, d});
        end
    endfunction

    function [15:0] abs16;
        input [15:0] v;
        begin
            abs16 = v[15] ? (~v + 16'd1) : v;
        end
    endfunction

    wire [15:0] DEV_ABS = abs16(I_sync_dev);

    // ---------------- 标签字符串（定长 localparam，防左填充错位） ----------------
    localparam [8*21-1:0] STR_TITLE = "SYS MONITOR TF-D1    ";
    localparam [8*8-1:0]  STR_UP    = "UPTIME  ";
    localparam [8*8-1:0]  STR_FRM   = "FRAMES  ";
    localparam [8*8-1:0]  STR_SYN   = "AV-SYNC ";
    localparam [8*8-1:0]  STR_MOD   = "MODE    ";

    localparam [8*8-1:0] STR_TF = "TF F/SNE";
    localparam [8*8-1:0] STR_LBA = "TF LBA  ";
    localparam [8*8-1:0] STR_IO = "RD/RESET";
    localparam [8*8-1:0] STR_HEAD = "BMP HEAD";
    localparam [8*8-1:0] STR_PIX = "PIXELS  ";
    localparam [8*8-1:0] STR_COM = "WR/SCALE";

    function [7:0] label_char;
        input [3:0] ln;
        input [6:0] c;
        begin
            case (ln)
                4'd0: label_char = (c < 7'd21) ? STR_TITLE[(20 - c)*8 +: 8] : 8'h20;
                4'd1: label_char = (c < 7'd8)  ? STR_UP[(7 - c)*8 +: 8]    : 8'h20;
                4'd2: label_char = (c < 7'd8)  ? STR_FRM[(7 - c)*8 +: 8]   : 8'h20;
                4'd3: label_char = (c < 7'd8)  ? STR_SYN[(7 - c)*8 +: 8]   : 8'h20;
                4'd4: label_char = (c < 7'd8)  ? STR_MOD[(7 - c)*8 +: 8]   : 8'h20;
                4'd6: label_char = (c < 8) ? STR_TF[(7-c)*8 +: 8] : 8'h20;
                4'd7: label_char = (c < 8) ? STR_LBA[(7-c)*8 +: 8] : 8'h20;
                4'd8: label_char = (c < 8) ? STR_IO[(7-c)*8 +: 8] : 8'h20;
                4'd9: label_char = (c < 8) ? STR_HEAD[(7-c)*8 +: 8] : 8'h20;
                4'd10: label_char = (c < 8) ? STR_PIX[(7-c)*8 +: 8] : 8'h20;
                4'd11: label_char = (c < 8) ? STR_COM[(7-c)*8 +: 8] : 8'h20;
                default: label_char = 8'h20;
            endcase
        end
    endfunction

    // 值字符: 8'hFF 表示该列不由值渲染接管（回退到标签/空格）
    function [7:0] value_char;
        input [3:0] ln;
        input [6:0] c;
        begin
            case (ln)
                4'd1: value_char = (c >= 9 && c < 17)
                        ? hex2ascii(I_uptime_sec[(7 - (c - 9)) * 4 +: 4]) : 8'hFF;
                4'd2: value_char = (c >= 9 && c < 17)
                        ? hex2ascii(I_frame_cnt[(7 - (c - 9)) * 4 +: 4]) : 8'hFF;
                4'd3: begin // 符号 + 4 位 hex
                    if (c == 9)
                        value_char = I_sync_dev[15] ? "N" : "P";
                    else if (c >= 10 && c < 14)
                        value_char = hex2ascii(DEV_ABS[(3 - (c - 10)) * 4 +: 4]);
                    else
                        value_char = 8'hFF;
                end
                4'd4: begin
                    if (c == 9)       value_char = (I_mode == 2'd2) ? "E" :
                                                   (I_mode == 2'd1) ? "A" : "B";
                    else if (c == 10) value_char = (I_mode == 2'd2) ? "M" :
                                                   (I_mode == 2'd1) ? "D" : "O";
                    else              value_char = 8'hFF;
                end
                4'd6: begin
                    if (c >= 9 && c < 13) value_char = hex2ascii(I_tf_diag[176 + (12-c)*4 +: 4]);
                    else if (c == 13) value_char = "/";
                    else if (c >= 14 && c < 17) value_char = hex2ascii(I_tf_diag[160 + (16-c)*4 +: 4]);
                    else value_char = 8'hFF;
                end
                4'd7: value_char = (c >= 9 && c < 17) ? hex2ascii(I_tf_diag[128 + (16-c)*4 +: 4]) : 8'hFF;
                4'd8: begin
                    if (c >= 9 && c < 17) value_char = hex2ascii(I_tf_diag[96 + (16-c)*4 +: 4]);
                    else if (c == 17) value_char = "/";
                    else if (c >= 18 && c < 22) value_char = hex2ascii(I_tf_diag[80 + (21-c)*4 +: 4]);
                    else value_char = 8'hFF;
                end
                4'd9: value_char = (c >= 9 && c < 17) ? hex2ascii(I_tf_diag[48 + (16-c)*4 +: 4]) : 8'hFF;
                4'd10: value_char = (c >= 9 && c < 17) ? hex2ascii(I_tf_diag[16 + (16-c)*4 +: 4]) : 8'hFF;
                4'd11: begin
                    if (c >= 9 && c < 11) value_char = hex2ascii(I_tf_diag[8 + (10-c)*4 +: 4]);
                    else if (c == 11) value_char = "/";
                    else if (c >= 12 && c < 14) value_char = hex2ascii(I_tf_diag[(13-c)*4 +: 4]);
                    else value_char = 8'hFF;
                end
                default: value_char = 8'hFF;
            endcase
        end
    endfunction

    // ================= 地址路径（原始坐标，组合） =================
    wire [6:0] col  = I_x[9:3];     // 0..79
    wire [4:0] line = I_y[8:4];     // 0..29
    wire [3:0] crow = I_y[3:0];

    wire [3:0] ln3 = (line == 0) ? 4'd0 :
                     (line == 3) ? 4'd1 : (line == 5) ? 4'd2 :
                     (line == 7) ? 4'd3 : (line == 9) ? 4'd4 :
                     (line == 13) ? 4'd6 : (line == 15) ? 4'd7 :
                     (line == 17) ? 4'd8 : (line == 19) ? 4'd9 :
                     (line == 21) ? 4'd10 : (line == 23) ? 4'd11 : 4'd5;
    wire is_text_line = (ln3 != 4'd5);
    wire [7:0] vch = value_char(ln3, col);
    wire [7:0] ch = !is_text_line ? 8'h20 : (vch != 8'hFF) ? vch : label_char(ln3, col);

    // 字模: 标题行文字带垂直居中(y∈[4,19] → row=y-4)，其余行 row=y[3:0]
    wire [3:0] font_row = (line == 5'd0) ? (I_y - 9'd4) : {1'b0, crow};

    // ---- BRAM 字库（同步读，1 拍后有效） ----
    wire [7:0] glyph_bits;
    font_rom_ascii u_font(
        .I_clk  (I_clk),
        .I_char (ch),
        .I_row  (font_row),
        .O_bits (glyph_bits)
    );

    // ================= 混合路径（延迟 1 拍，与 BRAM 输出同拍） =================
    reg [9:0]  x_d;
    reg [8:0]  y_d;
    reg        de_d;
    reg [7:0]  ch_d;
    reg [3:0]  ln3_d;
    reg        is_text_line_d;
    reg        line0_d;
    always @(posedge I_clk) begin
        x_d           <= I_x;
        y_d           <= I_y;
        de_d          <= I_de;
        ch_d          <= ch;
        ln3_d         <= ln3;
        is_text_line_d<= is_text_line;
        line0_d       <= (line == 5'd0);
    end

    wire [2:0] ccol = x_d[2:0];
    wire title_band  = line0_d && (y_d >= 9'd4) && (y_d <= 9'd19);
    wire glyph_on    = is_text_line_d && (title_band || !line0_d)
                       && glyph_bits[7 - ccol];

    // LAYER 色块: line11 (y 176..191), 4 块 16x12, 起点 x=72, 间距 24
    wire in_sq_row = (y_d[8:4] == 5'd11) && (y_d[3:0] >= 4'd2) && (y_d[3:0] <= 4'd13);
    wire [9:0] sqx = x_d - 10'd72;
    wire in_sq_col = (sqx < 10'd16) | ((sqx >= 10'd24) & (sqx < 10'd40)) |
                     ((sqx >= 10'd48) & (sqx < 10'd64)) |
                     ((sqx >= 10'd72) & (sqx < 10'd88));

    // 底部活动彩条 (y>=456): 三通道相位错开随帧滚动，证明视频是活的
    wire [7:0] ph = x_d[7:0] + I_frame_cnt[7:0];
    wire [23:0] strip_col = {ph, ph + 8'd85, ph + 8'd170};

    // ---------------- 像素输出（与延迟坐标同拍） ----------------
    wire in_strip = (y_d >= 9'd456);
    wire in_title = line0_d && (y_d < 9'd24);
    wire in_sq    = in_sq_row && in_sq_col;

    wire [23:0] rgb_c =
        in_strip                                ? strip_col :
        in_title                                ? (glyph_on ? TITLE_FG : TITLE_BG) :
        in_sq                                   ? ((I_mode == 2'd2) ? EMG_RED : OK_GREEN) :
        glyph_on                                ? (((ch_d != 8'hFF) && (ch_d != 8'h20)) ? VAL_FG : TXT_FG) :
                                                  BG;

    assign O_rgb = de_d ? rgb_c : 24'd0;

endmodule
