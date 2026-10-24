// osd_engine.v — 主通道 OSD 引擎 v2（A2: BRAM 字库同步读，1 级流水线）
// 地址路径（字库 BRAM 寻址）用原始 I_x/I_y；混合路径（窗口命中/混色）用打 1 拍的
// x_d/y_d/bg_d —— 与 BRAM 输出同拍。O_rgb 为寄存器输入的组合输出，顶层需将
// de/vs 再打 1 拍送 AXIS。
// 透明黑色文字：左上标题、右上模式、右下运行时钟；在颜色调整后叠加。
module osd_engine(
    input  wire        I_clk,
    input  wire [9:0]  I_x,
    input  wire [8:0]  I_y,
    input  wire [23:0] I_bg_rgb,
    input  wire [23:0] I_uptime_bcd,   // {HH,MM,SS} 各 2 位 BCD
    input  wire [1:0]  I_mode,         // 0:启动 1:广告 2:应急
    output wire [23:0] O_rgb
);

    // ================= 地址路径（原始坐标，组合） =================
    // 640x480 原生光栅：标题左对齐，模式与运行时间距右边 16 像素。
    wire in_title_txt = (I_y >= 9'd4)  && (I_y <= 9'd19);
    wire in_info_txt  = (I_y >= 9'd456)&& (I_y <= 9'd471);

    wire        t_in_x  = (I_x >= 10'd16) && (I_x < 10'd240);
    wire        m_in_x  = (I_x >= 10'd560) && (I_x < 10'd624);
    wire [5:0]  t_col   = I_x[9:4] - 6'd1;                    // 标题内列 (x-16)/16
    wire [5:0]  m_col   = I_x[9:4] - 6'd35;                   // 模式内列
    wire [3:0]  t_win   = (I_mode == 2'd2) ? 4'd2 : 4'd1;

    wire [15:0] title_cell;
    wire [15:0] mode_cell;
    osd_text_rom u_txt_title(.I_win(4'd0),       .I_col(t_col), .O_cell(title_cell));
    osd_text_rom u_txt_mode (.I_win(t_win),      .I_col(m_col), .O_cell(mode_cell));

    wire [15:0] t_cell = !in_title_txt      ? 16'hFFFF :
                         t_in_x             ? title_cell :
                         m_in_x             ? mode_cell : 16'hFFFF;

    wire        i_in_x = (I_x >= 10'd448) && (I_x < 10'd448 + 16*11);
    wire [5:0]  i_col  = I_x[9:4] - 6'd28;
    wire [15:0] clock_static;
    osd_text_rom u_txt_clock(.I_win(4'd3), .I_col(i_col), .O_cell(clock_static));
    reg  [15:0] i_cell;
    always @(*) begin
        case (i_col)
            6'd3:  i_cell = 16'h0130 + {8'd0, I_uptime_bcd[23:20]};  // HH hi
            6'd4:  i_cell = 16'h0130 + {8'd0, I_uptime_bcd[19:16]};  // HH lo
            6'd5:  i_cell = 16'h0100 + ":";
            6'd6:  i_cell = 16'h0130 + {8'd0, I_uptime_bcd[15:12]};
            6'd7:  i_cell = 16'h0130 + {8'd0, I_uptime_bcd[11:8]};
            6'd8:  i_cell = 16'h0100 + ":";
            6'd9:  i_cell = 16'h0130 + {8'd0, I_uptime_bcd[7:4]};
            6'd10: i_cell = 16'h0130 + {8'd0, I_uptime_bcd[3:0]};
            default: i_cell = clock_static;                          // "运行 " 静态部分
        endcase
    end
    wire [15:0] osd_cell = in_info_txt ? (i_in_x ? i_cell : 16'hFFFF)
                                   : t_cell;
    wire [3:0] crow = in_info_txt ? (I_y - 9'd456) : (I_y - 9'd4);

    // ---- BRAM 字库（同步读，1 拍后有效） ----
    wire [15:0] cjk_bits;
    font_rom_cjk u_cjk(
        .I_clk  (I_clk),
        .I_index(osd_cell[7:0]),
        .I_row  (crow),
        .O_bits (cjk_bits)
    );
    wire [7:0] a_bits;
    font_rom_ascii u_ascii(
        .I_clk (I_clk),
        .I_char(osd_cell[7:0]),
        .I_row (crow),
        .O_bits(a_bits)
    );

    // ================= 混合路径（延迟 1 拍，与 BRAM 输出同拍） =================
    reg [9:0]  x_d;
    reg [23:0] bg_d;
    reg [15:0] osd_cell_d;
    always @(posedge I_clk) begin
        x_d        <= I_x;
        bg_d       <= I_bg_rgb;
        osd_cell_d <= osd_cell;
    end

    wire [3:0] cellx = x_d[3:0];
    wire cell_is_ascii = (osd_cell_d[15:8] == 8'h01);
    wire glyph_on =
        cell_is_ascii ? (cellx >= 4'd4 && cellx <= 4'd11 && a_bits[7 - (cellx - 4'd4)])
                      : (osd_cell_d != 16'hFFFF && cjk_bits[15 - cellx]);

    // 所有非字形像素原样透传图片，禁止整行铺底色。
    assign O_rgb = glyph_on ? 24'h000000 : bg_d;

endmodule
