// HDMI-A menu renderer.
// The logical canvas is 640x480. Card titles use the generated native32 CJK font;
// Values remain ASCII; menu pages deliberately omit footer instructions.
module monitor_menu_renderer(
    input  wire       clk,
    input  wire       de,
    input  wire [9:0] x,
    input  wire [8:0] y,
    input  wire       page,
    input  wire       screen_page,
    input  wire       screen_edit,
    input  wire [9:0] screen_shadow,
    input  wire [9:0] screen_active,
    input  wire       subtitle_page,
    input  wire       subtitle_edit,
    input  wire [4:0] subtitle_shadow,
    input  wire [4:0] subtitle_active,
    input  wire       cfg_busy,
    input  wire       menu_active,
    input  wire [2:0] cursor,
    input  wire [3:0] cfg_shadow,
    input  wire [3:0] cfg_active,
    input  wire [1:0] period_shadow,
    input  wire [1:0] period_active,
    input  wire       cfg_dirty,
    input  wire       commit_seen,
    input  wire       buzzer_test,
    input  wire [2:0] key_state,
    input  wire [15:0] key_events,
    input  wire        sd_init_done,
    input  wire [3:0]  img_count,
    input  wire [3:0]  led_state,
    output wire [23:0] rgb
);
    localparam [23:0] BG       = 24'h07131D;
    localparam [23:0] HEADER   = 24'h124E70;
    localparam [23:0] CARD     = 24'h102A3A;
    localparam [23:0] CARD_SEL = 24'h075E78;
    localparam [23:0] FG       = 24'hF5FBFF;
    localparam [23:0] MUTED    = 24'h9BB8C4;
    localparam [23:0] ON       = 24'h4BE38A;
    localparam [23:0] OFF      = 24'hFF756C;
    localparam [23:0] ACCENT   = 24'hFFD166;
    localparam [23:0] WARN     = 24'hFF756C;
    localparam [23:0] FOOTER   = 24'h0D2633;

    localparam [8*16-1:0] STR_PROG  = "PROGRAM CONTROL ";
    localparam [8*16-1:0] STR_PERI  = "PERIPHERAL TEST ";
    localparam [8*16-1:0] STR_PLAY  = "PLAYBACK KEYS   ";
    localparam [8*16-1:0] STR_SCREEN= "HDMI-B SETTINGS ";
    localparam [8*16-1:0] STR_SUBTITLE= "HDMI-B SUBTITLE ";
    localparam [8*32-1:0] STR_PLAY_KEYS = "K2 NEXT IMAGE   K3 AUTO         ";
    localparam [8*32-1:0] STR_PLAY_HINT = "HOLD K3 MENU                    ";

    // Indices are generated from scripts/osd_strings.txt. Keeping the mapping
    // local avoids relying on Unicode source support in the TD Verilog parser.
    localparam [4:0] CJK_TU=5'd0, CJK_PIAN=5'd1;
    localparam [4:0] CJK_BO=5'd2, CJK_XING=5'd3;
    localparam [4:0] CJK_SHI=5'd4, CJK_JIAN=5'd5;
    localparam [4:0] CJK_CENG=5'd6, CJK_ZHOU=5'd7, CJK_QI=5'd8;
    localparam [4:0] CJK_WAI=5'd9, CJK_SHE=5'd10;
    localparam [4:0] CJK_FENG=5'd11, CJK_MING=5'd12, CJK_QI2=5'd13;
    localparam [4:0] CJK_AN=5'd14, CJK_JIAN3=5'd15;
    localparam [4:0] CJK_BAN=5'd16, CJK_ZAI=5'd17, CJK_DENG=5'd18;
    localparam [4:0] CJK_PING=19, CJK_MU=20, CJK_LIANG=21, CJK_DU=22;
    localparam [4:0] CJK_DUI=23, CJK_BI=24, CJK_SE=25, CJK_WEN=26;
    localparam [4:0] CJK_HUI=27, CJK_FU=28, CJK_MO=29, CJK_REN=30;
    localparam [5:0] CJK_ZI=32, CJK_NEI=33, CJK_RONG=34, CJK_SU=35;

    function [7:0] hex;
        input [3:0] d;
        begin hex = (d < 4'd10) ? (8'h30 + d) : (8'h37 + d); end
    endfunction

    function [7:0] value_char;
        input       p;
        input [2:0] idx;
        input [3:0] pos;
        begin
            value_char = 8'h20;
            if (!p) begin
                if (idx == 3'd3) begin
                    case (pos)
                        0:value_char="O"; 1:value_char="P"; 2:value_char="E"; 3:value_char="N";
                        default:value_char=" ";
                    endcase
                end else if (idx == 3'd5) begin
                    case (pos)
                        0: value_char="H"; 1: value_char="D"; 2: value_char="M";
                        3: value_char="I"; 4: value_char="-"; 5: value_char="B";
                        default: value_char=" ";
                    endcase
                end else if (idx == 3'd4) begin
                    case (period_shadow)
                        2'd0: case (pos) 4'd0:value_char="1"; 4'd1:value_char="S"; 4'd2:value_char="E"; 4'd3:value_char="C"; default:value_char=8'h20; endcase
                        2'd1: case (pos) 4'd0:value_char="2"; 4'd1:value_char="S"; 4'd2:value_char="E"; 4'd3:value_char="C"; default:value_char=8'h20; endcase
                        2'd2: case (pos) 4'd0:value_char="5"; 4'd1:value_char="S"; 4'd2:value_char="E"; 4'd3:value_char="C"; default:value_char=8'h20; endcase
                        default: case (pos) 4'd0:value_char="1"; 4'd1:value_char="0"; 4'd2:value_char="S"; 4'd3:value_char="E"; 4'd4:value_char="C"; default:value_char=8'h20; endcase
                    endcase
                    if (pos == 4'd6 && period_shadow != period_active) value_char = "*";
                end else begin
                    case (pos)
                        4'd0: value_char = "O";
                        4'd1: value_char = cfg_shadow[idx] ? "N" : "F";
                        4'd2: value_char = cfg_shadow[idx] ? 8'h20 : "F";
                        4'd3: value_char = (cfg_shadow[idx] != cfg_active[idx]) ? "*" : 8'h20;
                        default: value_char = 8'h20;
                    endcase
                end
            end else begin
                case (idx)
                    2'd0: begin
                        case (pos)
                            4'd0: value_char = sd_init_done ? "R" : "W";
                            4'd1: value_char = sd_init_done ? "E" : "A";
                            4'd2: value_char = sd_init_done ? "A" : "I";
                            4'd3: value_char = sd_init_done ? "D" : "T";
                            4'd4: value_char = sd_init_done ? "Y" : " ";
                            default: value_char = 8'h20;
                        endcase
                    end
                    2'd1: begin
                        case (pos)
                            4'd0: value_char = buzzer_test ? "T" : "I";
                            4'd1: value_char = buzzer_test ? "E" : "D";
                            4'd2: value_char = buzzer_test ? "S" : "L";
                            4'd3: value_char = buzzer_test ? "T" : "E";
                            default: value_char = 8'h20;
                        endcase
                    end
                    2'd2: begin
                        case (pos)
                            4'd0: value_char = "C";
                            4'd1: value_char = "N";
                            4'd2: value_char = "T";
                            4'd3: value_char = hex(key_events[15:12]);
                            4'd4: value_char = hex(key_events[11:8]);
                            default: value_char = 8'h20;
                        endcase
                    end
                    default: begin
                        // LED 状态按 [3:0] 显示为十六进制，便于快速确认四灯组合。
                        case (pos)
                            4'd0: value_char = "L";
                            4'd1: value_char = "E";
                            4'd2: value_char = "D";
                            4'd3: value_char = hex(led_state);
                            default: value_char = 8'h20;
                        endcase
                    end
                endcase
            end
        end
    endfunction

    function [7:0] subtitle_value_char;
        input [2:0] idx;
        input [3:0] pos;
        reg [79:0] label;
        reg changed;
        begin
            changed=1'b0;
            case(idx)
                0:begin label=subtitle_shadow[0] ? "ON        " : "OFF       ";
                    changed=subtitle_shadow[0]!=subtitle_active[0]; end
                1:begin
                    case(subtitle_shadow[2:1])
                        0:label="01WELCOME "; 1:label="02 EVENT  ";
                        2:label="03 MEDIA  "; default:label="ERR       ";
                    endcase
                    changed=subtitle_shadow[2:1]!=subtitle_active[2:1];
                end
                2:begin
                    case(subtitle_shadow[4:3])
                        0:label="SLOW 30   "; 1:label="NORM 60   ";
                        2:label="FAST 120  "; default:label="ERR       ";
                    endcase
                    changed=subtitle_shadow[4:3]!=subtitle_active[4:3];
                end
                default:begin label=cfg_shadow[3] ? "ON        " : "OFF       ";
                    changed=cfg_shadow[3]!=cfg_active[3]; end
            endcase
            subtitle_value_char=label[(4'd9-pos)*8 +: 8];
            if(pos==9 && changed) subtitle_value_char="*";
        end
    endfunction

    // 固定档位文本避免视频像素路径上的除法/BCD 转换。
    function [7:0] screen_value_char;
        input [2:0] idx;
        input [3:0] pos;
        input editing_this;
        reg [39:0] label;
        reg changed;
        begin
            label = "     ";
            changed = 1'b0;
            case (idx)
                0: begin
                    case (screen_shadow[3:0])
                        0:label="-64  "; 1:label="-48  "; 2:label="-32  ";
                        3:label="-16  "; 4:label=" 00  "; 5:label="+16  ";
                        6:label="+32  "; 7:label="+48  "; 8:label="+64  ";
                        default:label="ERR  ";
                    endcase
                    changed = screen_shadow[3:0] != screen_active[3:0];
                end
                1: begin
                    case (screen_shadow[7:4])
                        0:label="050% "; 1:label="063% "; 2:label="075% ";
                        3:label="088% "; 4:label="100% "; 5:label="113% ";
                        6:label="125% "; 7:label="138% "; 8:label="150% ";
                        default:label="ERR  ";
                    endcase
                    changed = screen_shadow[7:4] != screen_active[7:4];
                end
                2: begin
                    case (screen_shadow[9:8])
                        0:label="COOL "; 1:label="NORM "; 2:label="WARM ";
                        default:label="ERR  ";
                    endcase
                    changed = screen_shadow[9:8] != screen_active[9:8];
                end
                3: label = editing_this ? "RESET" : "OPEN ";
                default: label = "ERR  ";
            endcase
            screen_value_char = (pos < 5) ? label[(4-pos)*8 +: 8] :
                                ((pos == 6 && changed) ? "*" : " ");
        end
    endfunction

    // 参数是低速状态。提前生成四卡状态行，像素路径只取字符，避免
    // 坐标译码后再串接档位查表和多级字符选择；不增加视频输出延迟。
    reg [79:0] screen_text0, screen_text1, screen_text2, screen_text3;
    integer screen_char_index;
    always @(posedge clk) begin
        for (screen_char_index=0; screen_char_index<10; screen_char_index=screen_char_index+1) begin
            screen_text0[(9-screen_char_index)*8 +: 8] <= subtitle_page ? subtitle_value_char(3'd0,screen_char_index) : screen_value_char(3'd0, screen_char_index, screen_edit && cursor==0);
            screen_text1[(9-screen_char_index)*8 +: 8] <= subtitle_page ? subtitle_value_char(3'd1,screen_char_index) : screen_value_char(3'd1, screen_char_index, screen_edit && cursor==1);
            screen_text2[(9-screen_char_index)*8 +: 8] <= subtitle_page ? subtitle_value_char(3'd2,screen_char_index) : screen_value_char(3'd2, screen_char_index, screen_edit && cursor==2);
            screen_text3[(9-screen_char_index)*8 +: 8] <= subtitle_page ? subtitle_value_char(3'd3,screen_char_index) : screen_value_char(3'd3, screen_char_index, screen_edit && cursor==3);
        end
    end

    function [5:0] cjk_title_char;
        input       p;
        input [2:0] idx;
        input [1:0] pos;
        input is_screen, is_subtitle;
        begin
            cjk_title_char = 8'd0;
            if (is_subtitle) begin
                case(idx)
                    0:cjk_title_char=(pos==0) ? CJK_ZI : {1'b0,CJK_MU};
                    1:cjk_title_char=(pos==0) ? CJK_NEI : CJK_RONG;
                    2:cjk_title_char=(pos==0) ? CJK_SU : {1'b0,CJK_DU};
                    default:cjk_title_char=(pos==0) ? {1'b0,CJK_TU} : {1'b0,CJK_CENG};
                endcase
            end else if (is_screen) begin
                case (idx)
                    0: cjk_title_char = (pos == 0) ? CJK_LIANG : CJK_DU;
                    1: cjk_title_char = (pos == 0) ? CJK_DUI : ((pos == 1) ? CJK_BI : CJK_DU);
                    2: cjk_title_char = (pos == 0) ? CJK_SE : CJK_WEN;
                    3: case (pos)
                        0:cjk_title_char=CJK_HUI; 1:cjk_title_char=CJK_FU;
                        2:cjk_title_char=CJK_MO; 3:cjk_title_char=CJK_REN;
                    endcase
                endcase
            end else if (!p) begin
                case (idx)
                    3'd0: cjk_title_char = (pos == 0) ? CJK_TU : CJK_PIAN;
                    3'd1: cjk_title_char = (pos == 0) ? CJK_BO : CJK_XING;
                    3'd2: cjk_title_char = (pos == 0) ? CJK_SHI : CJK_JIAN;
                    3'd3: cjk_title_char = (pos == 0) ? CJK_ZI : {1'b0,CJK_MU};
                    3'd4: cjk_title_char = (pos == 0) ? CJK_ZHOU : CJK_QI;
                    default: cjk_title_char = (pos == 0) ? CJK_PING : CJK_MU;
                endcase
            end else begin
                case (idx)
                    3'd0: cjk_title_char = (pos == 0) ? CJK_WAI : ((pos == 1) ? CJK_SHE : 5'd31);
                    3'd1: cjk_title_char = (pos == 0) ? CJK_FENG : ((pos == 1) ? CJK_MING : CJK_QI2);
                    3'd2: cjk_title_char = (pos == 0) ? CJK_AN : ((pos == 1) ? CJK_JIAN3 : 5'd31);
                    default: cjk_title_char = (pos == 0) ? CJK_BAN : ((pos == 1) ? CJK_ZAI : CJK_DENG);
                endcase
            end
        end
    endfunction

    // 节目页严格两行三列；外设和 HDMI-B 设置页两行两列。
    wire wide_cards = page || screen_page || subtitle_page;
    wire program_top = y < 9'd260;
    wire [1:0] program_col = (x < 10'd220) ? 2'd0 : ((x < 10'd424) ? 2'd1 : 2'd2);
    wire [2:0] card_idx = wide_cards ?
        ((x < 10'd320) ? ((y < 9'd260) ? 3'd0 : 3'd2) : ((y < 9'd260) ? 3'd1 : 3'd3)) :
        ({1'b0,program_col} + (program_top ? 3'd0 : 3'd3));
    wire [9:0] card_x0 = wide_cards ? ((x < 10'd320) ? 10'd32 : 10'd336) :
                        ((program_col == 0) ? 10'd24 : ((program_col == 1) ? 10'd228 : 10'd432));
    wire [8:0] card_y0 = program_top ? 9'd88 : 9'd272;
    wire [9:0] card_w = wide_cards ? 10'd272 : 10'd184;
    wire [9:0] local_x = x - card_x0;
    wire [8:0] local_y = y - card_y0;
    // 二级页文字直接用2x2坐标选行，避免借道六卡编号译码和页面mux。
    wire [79:0] screen_card_text = (y<9'd260) ?
                                  ((x<10'd320) ? screen_text0 : screen_text1) :
                                  ((x<10'd320) ? screen_text2 : screen_text3);
    wire card_area = wide_cards ? ((((x >= 10'd32) && (x < 10'd304)) ||
                              ((x >= 10'd336) && (x < 10'd608))) &&
                             (((y >= 9'd88) && (y < 9'd248)) ||
                              ((y >= 9'd272) && (y < 9'd432)))) :
                      ((((x >= 10'd24) && (x < 10'd208)) ||
                                      ((x >= 10'd228) && (x < 10'd412)) ||
                                      ((x >= 10'd432) && (x < 10'd616))) &&
                                     (((y >= 9'd88) && (y < 9'd248)) ||
                                      ((y >= 9'd272) && (y < 9'd432))));
    wire selected = menu_active && card_area && (card_idx == cursor);

    wire header_hit = (x >= 10'd32) && (x < 10'd288) &&
                      (y >= 9'd16) && (y < 9'd48);
    // Native 32x32 glyphs retain the previous title footprint and pixel latency.
    wire cjk_three_chars = page && !subtitle_page && ((card_idx == 3'd1) || (card_idx == 3'd3));
    wire [9:0] title_end = screen_page ? ((card_idx == 3) ? 10'd144 : ((card_idx == 1) ? 10'd112 : 10'd80)) :
                          (cjk_three_chars ? 10'd112 : 10'd80);
    wire cjk_title_hit = card_area && (local_x >= 10'd16) &&
                         (local_x < title_end) &&
                         (local_y >= 9'd16) && (local_y < 9'd48);
    wire card_value_hit = card_area && (local_x >= 10'd16) &&
                          (local_x < 10'd176) && (local_y >= 9'd72) &&
                          (local_y < 9'd104);
    wire footer_hit = !menu_active && (x >= 10'd32) && (x < 10'd288) &&
                      (y >= 9'd444) && (y < 9'd476);
    wire [4:0] footer_pos = (x - 10'd32) >> 3;
    wire footer_second = y >= 9'd460;
    wire [255:0] footer_text = footer_second ? STR_PLAY_HINT : STR_PLAY_KEYS;
    wire status_hit = (screen_page || subtitle_page) && menu_active && x >= 10'd432 && x < 10'd592 && y >= 9'd16 && y < 9'd48;
    wire [79:0] status_text = cfg_busy ? "WAIT      " : ((screen_edit || subtitle_edit) ? "EDIT      " : "READY     ");
    // Bound character indices before subtraction. Unsized integer subtraction
    // in an indexed part-select otherwise infers a 32-bit pixel-path carry chain.
    wire [3:0] header_pos = x[7:4] - 4'd2;
    wire [3:0] status_pos = x[7:4] - 4'd11;
    wire [3:0] value_pos = local_x[7:4] - 4'd1;
    wire [3:0] header_rev = 4'd15 - header_pos;
    wire [3:0] status_rev = 4'd9 - status_pos;
    wire [3:0] value_rev = 4'd9 - value_pos;
    wire [3:0] detail_pos = x[7:4] - ((x<10'd320) ? 4'd3 : 4'd6);
    wire [3:0] detail_rev = 4'd9 - detail_pos;
    wire [4:0] footer_rev = 5'd31 - footer_pos;

    // 中文地址只由绝对字格边界决定，不串接 card_x0/local_x 的减法。
    // 字库持续读取；真正的绘制仍由同拍 cjk_d/glyph_hit_d 限定。
    // 因而不必把卡片命中、页眉优先级再串入 BRAM 地址关键路径。
    wire [1:0] wide_left_pos = x<10'd80 ? 2'd0 : x<10'd112 ? 2'd1 : x<10'd144 ? 2'd2 : 2'd3;
    wire [1:0] wide_right_pos = x<10'd384 ? 2'd0 : x<10'd416 ? 2'd1 : x<10'd448 ? 2'd2 : 2'd3;
    wire [5:0] wide_left_glyph = cjk_title_char(page, program_top ? 3'd0 : 3'd2, wide_left_pos, screen_page, subtitle_page);
    wire [5:0] wide_right_glyph = cjk_title_char(page, program_top ? 3'd1 : 3'd3, wide_right_pos, screen_page, subtitle_page);
    wire [5:0] program_left_glyph = cjk_title_char(1'b0, program_top ? 3'd0 : 3'd3, x<10'd72 ? 2'd0 : 2'd1, 1'b0, 1'b0);
    wire [5:0] program_mid_glyph = cjk_title_char(1'b0, program_top ? 3'd1 : 3'd4, x<10'd276 ? 2'd0 : 2'd1, 1'b0, 1'b0);
    wire [5:0] program_right_glyph = cjk_title_char(1'b0, program_top ? 3'd2 : 3'd5, x<10'd480 ? 2'd0 : 2'd1, 1'b0, 1'b0);
    wire [5:0] cjk_pixel_glyph = wide_cards ? (x<10'd320 ? wide_left_glyph : wide_right_glyph) :
                               x<10'd220 ? program_left_glyph : x<10'd424 ? program_mid_glyph : program_right_glyph;

    reg [7:0] req_char;
    reg [3:0] req_row;
    reg [2:0] req_col;
    reg [1:0] req_kind;
    reg       req_cjk;
    reg [5:0] req_cjk_idx;
    reg [4:0] req_cjk_row;
    always @* begin
        req_char = 8'h20;
        req_row  = 4'd0;
        req_col  = 3'd0;
        req_kind = 2'd0;
        req_cjk = 1'b0;
        req_cjk_idx = cjk_pixel_glyph;
        req_cjk_row = local_y[4:0] - 5'd16;
        if (header_hit) begin
            req_kind = 2'd0;
            req_col  = (x - 10'd32) >> 1;
            req_row  = (y - 9'd16) >> 1;
            req_char = !menu_active ? STR_PLAY[{header_rev,3'b000} +: 8] :
                       subtitle_page ? STR_SUBTITLE[{header_rev,3'b000} +: 8] :
                       screen_page ? STR_SCREEN[{header_rev,3'b000} +: 8] :
                       page ? STR_PERI[{header_rev,3'b000} +: 8] :
                              STR_PROG[{header_rev,3'b000} +: 8];
        end else if (status_hit) begin
            req_kind = 2'd0;
            req_col = (x - 10'd432) >> 1;
            req_row = (y - 9'd16) >> 1;
            req_char = status_text[{status_rev,3'b000} +: 8];
        end else if (cjk_title_hit) begin
            req_kind = 2'd1;
            req_cjk = 1'b1;
        end else if (card_value_hit) begin
            req_kind = 2'd2;
            req_col  = (local_x - 10'd16) >> 1;
            req_row  = (local_y - 9'd72) >> 1;
            req_char = (screen_page || subtitle_page) ? screen_card_text[{detail_rev,3'b000} +: 8] :
                                     value_char(page, card_idx, {1'b0,value_pos});
        end else if (footer_hit) begin
            req_kind = 2'd3;
            req_col  = x - 10'd32;
            req_row  = footer_second ? (y - 9'd460) : (y - 9'd444);
            req_char = footer_text[{footer_rev,3'b000} +: 8];
        end
    end

    wire [7:0] glyph_bits;
    font_rom_ascii u_font(
        .I_clk  (clk),
        .I_char (req_char),
        .I_row  (req_row),
        .O_bits (glyph_bits)
    );

    wire [31:0] cjk_glyph_bits;
    monitor_cjk_rom u_font_cjk(
        .I_clk   (clk),
        .I_index (req_cjk_idx),
        .I_row   (req_cjk_row),
        .O_bits  (cjk_glyph_bits)
    );

    reg [9:0] local_x_d;
    reg [8:0] local_y_d;
    reg [9:0] x_d;
    reg [8:0] y_d;
    reg       de_d;
    reg       card_area_d;
    reg       selected_d;
    reg [2:0] card_idx_d;
    reg [9:0] card_w_d;
    reg [1:0] kind_d;
    reg [2:0] glyph_col_d;
    reg       glyph_hit_d;
    reg       page_d;
    reg       cjk_d;
    reg [4:0] cjk_col_d;
    always @(posedge clk) begin
        x_d          <= x;
        y_d          <= y;
        de_d         <= de;
        card_area_d  <= card_area;
        selected_d   <= selected;
        card_idx_d   <= card_idx;
        card_w_d     <= card_w;
        kind_d       <= req_kind;
        glyph_col_d  <= req_col;
        glyph_hit_d  <= header_hit || status_hit || cjk_title_hit || card_value_hit || footer_hit;
        page_d       <= page;
        cjk_d        <= req_cjk;
        cjk_col_d    <= local_x[4:0] - 5'd16;
        local_x_d    <= local_x;
        local_y_d    <= local_y;
    end

    // 选中卡片右侧的黄色圆点。圆点使用 8x8 常量位图，每个逻辑像素
    // 覆盖 4x4 画布像素。区域边界只比较坐标高位，避免把长减法器和
    // 多组范围比较器放进 74.25MHz 视频关键路径。
    reg [7:0] dot_row_mask;
    always @* begin
        case (local_y_d[4:2])
            3'd0: dot_row_mask = 8'b00111100;
            3'd1: dot_row_mask = 8'b01111110;
            3'd2: dot_row_mask = 8'b11111111;
            3'd3: dot_row_mask = 8'b11111111;
            3'd4: dot_row_mask = 8'b11111111;
            3'd5: dot_row_mask = 8'b11111111;
            3'd6: dot_row_mask = 8'b01111110;
            3'd7: dot_row_mask = 8'b00111100;
            default: dot_row_mask = 8'd0;
        endcase
    end
    wire dot_hit = selected_d &&
                   (local_x_d >= (card_w_d - 10'd48)) &&
                   (local_x_d < (card_w_d - 10'd16)) &&
                   (local_y_d >= 9'd64) &&
                   (local_y_d < 9'd96) &&
                   dot_row_mask[(local_x_d - card_w_d + 10'd48) >> 2];
    wire card_border = card_area_d && ((local_x_d < 3) || (local_x_d >= (card_w_d - 3)) ||
                                       (local_y_d < 3) || (local_y_d >= 9'd157));
    wire footer_area = (y_d >= 9'd440) && (y_d < 9'd480);
    wire header_area = (y_d < 9'd64);
    wire glyph_on = glyph_hit_d && (cjk_d ? cjk_glyph_bits[31 - cjk_col_d] :
                                            glyph_bits[7 - glyph_col_d]);
    wire [23:0] card_fill = selected_d ? CARD_SEL : CARD;
    wire [23:0] value_fg = subtitle_page ? ((subtitle_edit && card_idx_d == cursor) ? ACCENT : ON) :
                          screen_page ? ((screen_edit && card_idx_d == cursor) ? ACCENT : ON) :
                          ((!page_d && card_idx_d >= 3) ? ACCENT :
                          (!page_d && (card_idx_d < 3'd4) && cfg_shadow[card_idx_d]) ? ON :
                           (!page_d ? OFF :
                            ((card_idx_d == 2'd1 && buzzer_test) ? ON : ACCENT)));
    wire [23:0] text_fg = (kind_d == 2'd2) ? value_fg : FG;
    wire [23:0] base = header_area ? HEADER :
                       footer_area ? FOOTER :
                       card_area_d ? card_fill : BG;
    wire [23:0] border = selected_d ? ACCENT : (cfg_dirty ? WARN : MUTED);
    assign rgb = !de_d ? 24'd0 :
                 dot_hit ? ACCENT :
                 card_border ? border :
                 glyph_on ? text_fg : base;
endmodule
