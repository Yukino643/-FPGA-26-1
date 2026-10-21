// 原生32像素字模同步读；只覆盖黑色笔画，保留背景图片。
module osd_engine_720(
    input wire I_clk,
    input wire I_rst,
    input wire I_vs_pulse,
    input wire [4:0] I_subtitle_cfg,
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    input wire [23:0] I_bg_rgb,I_uptime_bcd,
    input wire [1:0] I_mode,
    input wire I_clock_enable,
    input wire I_text_enable,
    output wire [23:0] O_rgb
);
`include "font_720_map.vh"
    // 兼容旧 testbench/封装：未连接的新开关在仿真中为 X 时保持原有图层开启。
    // 实际硬件只有 0/1，不改变正常综合逻辑。
    wire text_enable_i  = (I_text_enable  !== 1'b0);
    wire clock_enable_i = (I_clock_enable !== 1'b0);
    wire title_y=text_enable_i && I_y>=32 && I_y<64;
    wire subtitle_enable = (I_subtitle_cfg[0] === 1'b1);
    wire clock_y=clock_enable_i && (subtitle_enable ? (I_y>=80 && I_y<112) : (I_y>=656 && I_y<688));
    wire title_x=I_x>=32 && I_x<480;
    wire mode_x=I_x>=1120 && I_x<1248;
    wire clock_x=I_x>=896 && I_x<1248;
    // 三组文字并行译码，Y区域只在最后选字；避免clock_y先选列号，
    // 再串入整套文字/数字查表。三者仍共用下面唯一的同步字模ROM。
    wire [5:0] title_col = I_x[10:5]-6'd1;
    wire [5:0] mode_col = I_x[10:5]-6'd35;
    wire [5:0] clock_col = I_x[10:5]-6'd28;
    wire [5:0] title_glyph, mode_glyph, clock_static_glyph;
    osd_text_720 u_text(.win(2'd0),.col(title_col),.glyph(title_glyph));
    osd_text_720 u_mode_text(.win(I_mode==2 ? 2'd2:2'd1),.col(mode_col),.glyph(mode_glyph));
    osd_text_720 u_clock_text(.win(2'd3),.col(clock_col),.glyph(clock_static_glyph));
    function [5:0] digit;
        input [3:0] number;
        begin
            case(number)
                0:digit=DIGIT_0; 1:digit=DIGIT_1; 2:digit=DIGIT_2; 3:digit=DIGIT_3;
                4:digit=DIGIT_4; 5:digit=DIGIT_5; 6:digit=DIGIT_6; 7:digit=DIGIT_7;
                8:digit=DIGIT_8; 9:digit=DIGIT_9; default:digit=0;
            endcase
        end
    endfunction
    reg [5:0] clock_glyph;
    always @(*) begin
        case(clock_col)
            3:clock_glyph=digit(I_uptime_bcd[23:20]);
            4:clock_glyph=digit(I_uptime_bcd[19:16]);
            5,8:clock_glyph=COLON;
            6:clock_glyph=digit(I_uptime_bcd[15:12]);
            7:clock_glyph=digit(I_uptime_bcd[11:8]);
            9:clock_glyph=digit(I_uptime_bcd[7:4]);
            10:clock_glyph=digit(I_uptime_bcd[3:0]);
            default:clock_glyph=clock_static_glyph;
        endcase
    end
    wire text_hit=(title_y && (title_x || mode_x)) || (clock_y && clock_x);
    // 与老师字幕例程一样，仅在帧消隐推进。1024像素循环天然回绕，
    // 不在像素路径使用除法/取模；内容变更后从完整可读的起点重启。
    reg [9:0] scroll_origin;
    reg slow_phase;
    reg [4:0] subtitle_seen;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            scroll_origin <= 10'd864; // -160 modulo 1024
            slow_phase <= 1'b0;
            subtitle_seen <= 5'h08;
        end else if (!subtitle_enable || I_subtitle_cfg != subtitle_seen) begin
            scroll_origin <= 10'd864;
            slow_phase <= 1'b0;
            subtitle_seen <= I_subtitle_cfg;
        end else if (I_vs_pulse) begin
            slow_phase <= ~slow_phase;
            case (I_subtitle_cfg[4:3])
                0: if (slow_phase) scroll_origin <= scroll_origin + 10'd1;
                1: scroll_origin <= scroll_origin + 10'd1;
                default: scroll_origin <= scroll_origin + 10'd2;
            endcase
        end
    end
    wire subtitle_band = subtitle_enable && I_x>=32 && I_x<1248 && I_y>=672 && I_y<712;
    wire subtitle_badge = subtitle_band && I_x<144;
    wire subtitle_line = subtitle_band && (I_y==672 || I_x<36);
    wire subtitle_y = I_y>=676 && I_y<708;
    wire subtitle_badge_text = subtitle_band && subtitle_y && I_x>=48 && I_x<112;
    wire subtitle_message_text = subtitle_band && subtitle_y && I_x>=160 && I_x<1232;
    wire [9:0] subtitle_source_x = I_x[9:0] + scroll_origin;
    wire [5:0] subtitle_glyph;
    subtitle_text_720 u_subtitle_text(.preset(I_subtitle_cfg[2:1]), .col(subtitle_source_x[9:5]), .glyph(subtitle_glyph));
    wire [5:0] glyph = subtitle_badge_text ? ((I_x<80) ? NOTICE_TONG : NOTICE_ZHI) :
                       subtitle_message_text ? subtitle_glyph :
                       clock_y ? clock_glyph : mode_x ? mode_glyph : title_glyph;
    // 命中标志在输出处屏蔽，ROM地址不必经过完整区域优先级。
    // 80和656模32都为16，676模32为4，只需五位减法。
    wire [4:0] row = (subtitle_enable && I_y>=672) ? I_y[4:0]-5'd4 :
                     clock_y ? I_y[4:0]-5'd16 : I_y[4:0];
    wire [31:0] bits;
    font_rom_720 u_font(.clk(I_clk),.glyph(glyph),.row(row),.bits(bits));
    reg [4:0] cell_x;
    reg [23:0] background;
    reg band_q, badge_q, line_q, subtitle_text_q, glyph_hit_q;
    always @(posedge I_clk) begin
        cell_x <= subtitle_badge_text ? I_x[4:0]-5'd16 :
                  subtitle_message_text ? subtitle_source_x[4:0] : I_x[4:0];
        background <= I_bg_rgb;
        band_q <= subtitle_band;
        badge_q <= subtitle_badge;
        line_q <= subtitle_line;
        subtitle_text_q <= subtitle_badge_text || subtitle_message_text;
        glyph_hit_q <= text_hit || subtitle_badge_text || subtitle_message_text;
    end
    wire [23:0] dim_background = {1'b0,background[23:17],1'b0,background[15:9],1'b0,background[7:1]};
    wire [23:0] base = badge_q ? 24'h124E70 : band_q ? dim_background : background;
    assign O_rgb = line_q ? 24'h38BDF8 :
                   (glyph_hit_q && bits[31-cell_x]) ? (subtitle_text_q ? 24'hF5FBFF : 24'h000000) : base;
endmodule
