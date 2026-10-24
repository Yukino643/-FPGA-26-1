// HDMI-A menu renderer.
// The logical canvas is 640x480. Card titles use the generated native32 CJK font;
// Values remain ASCII; menu pages deliberately omit footer instructions.
module monitor_menu_renderer(
    input  wire       clk,
    input  wire       de,
    input  wire [9:0] x,
    input  wire [8:0] y,
    input  wire       page,
    input  wire       audio_page, audio_edit,
    input  wire [4:0] audio_shadow, audio_active,
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
    localparam [23:0] BG=24'h07131D, HEADER=24'h0B1D28, RULE=24'h2A5A70;
    localparam [23:0] SURF=24'h142F40, SEL=24'h1B4658, FRAME=24'h3A6478;
    localparam [23:0] FG=24'hE9F4FA, VALUE=24'hC9DBE5, MUTED=24'h8FA9B8;
    localparam [23:0] FOCUS=24'h38BDF8, ON=24'h5BE39B, OFF=24'hFF7B72;
    localparam [23:0] AMBER=24'hFFB84D, DIS=24'h6E8593, CHIP=24'h16394A;
    localparam [23:0] WAIT_FG=24'h16232B;
    localparam [2:0] PAGE_PROGRAM=0, PAGE_PERIPHERAL=1, PAGE_SCREEN=2, PAGE_SUBTITLE=3, PAGE_AUDIO=4;
    localparam [2:0] VALUE_NORMAL=0, VALUE_ON=1, VALUE_OFF=2, VALUE_WAIT=3, VALUE_ERROR=4;
    localparam [2:0] KIND_HEADER=0, KIND_CJK=1, KIND_VALUE=2, KIND_FOOTER=3,
                     KIND_STATUS=4, KIND_ARROW=5;

    localparam [8*16-1:0] STR_PROG  = "PROGRAM CONTROL ";
    localparam [8*16-1:0] STR_PERI  = "PERIPHERAL TEST ";
    localparam [8*16-1:0] STR_PLAY  = "PLAYBACK KEYS   ";
    localparam [8*16-1:0] STR_AUDIO = "HDMI-B AUDIO    ";
    localparam [8*16-1:0] STR_SCREEN= "HDMI-B SETTINGS ";
    localparam [8*16-1:0] STR_SUBTITLE= "HDMI-B SUBTITLE ";
    localparam [8*32-1:0] STR_PLAY_KEYS = "K2 NEXT K3 AUTO HOLD K3 MENU    ";

    // Indices are generated from scripts/gen_monitor_cjk.py. Keeping the mapping
    // local avoids relying on Unicode source support in the TD Verilog parser.
    localparam [4:0] CJK_TU=5'd0, CJK_PIAN=5'd1;
    localparam [4:0] CJK_BO=5'd2, CJK_XING=5'd3;
    localparam [4:0] CJK_SHI=5'd4, CJK_JIAN=5'd5;
    localparam [4:0] CJK_BIAO=5'd6, CJK_ZHOU=5'd7, CJK_QI=5'd8;
    localparam [4:0] CJK_TI=5'd31;
    localparam [4:0] CJK_WAI=5'd9, CJK_SHE=5'd10;
    localparam [4:0] CJK_FENG=5'd11, CJK_MING=5'd12, CJK_QI2=5'd13;
    localparam [4:0] CJK_AN=5'd14, CJK_JIAN3=5'd15;
    localparam [4:0] CJK_BAN=5'd16, CJK_ZAI=5'd17, CJK_DENG=5'd18;
    localparam [4:0] CJK_PING=19, CJK_MU=20, CJK_LIANG=21, CJK_DU=22;
    localparam [4:0] CJK_DUI=23, CJK_BI=24, CJK_SE=25, CJK_WEN=26;
    localparam [4:0] CJK_HUI=27, CJK_FU=28, CJK_MO=29, CJK_REN=30;
    localparam [5:0] CJK_ZI=32, CJK_NEI=33, CJK_RONG=34, CJK_SU=35;
    localparam [5:0] CJK_YIN=36, CJK_PIN=37, CJK_VOLUME=38, CJK_JING=39;

    function [7:0] hex;
        input [3:0] d;
        begin hex = (d < 4'd10) ? (8'h30 + d) : (8'h37 + d); end
    endfunction

    // 以下函数仅在状态寄存器前执行，与像素坐标无关。文本、pending、
    // 编辑态与值色类别在同一拍采样，像素路径不再串入参数档位查表。
    wire [2:0] state_page = audio_page ? PAGE_AUDIO : subtitle_page ? PAGE_SUBTITLE : screen_page ? PAGE_SCREEN :
                            page ? PAGE_PERIPHERAL : PAGE_PROGRAM;
    function card_pending;
        input [2:0] p;
        input [2:0] idx;
        begin
            card_pending=1'b0;
            case(p)
                PAGE_PROGRAM: case(idx)
                    0,2:card_pending=cfg_shadow[idx]!=cfg_active[idx];
                    3:card_pending=subtitle_shadow[0]!=subtitle_active[0];
                    4:card_pending=period_shadow!=period_active;
                    default:card_pending=1'b0;
                endcase
                PAGE_AUDIO: case(idx)
                    0:card_pending=audio_shadow[3:0]!=audio_active[3:0];
                    1:card_pending=audio_shadow[4]!=audio_active[4];
                    2:card_pending=cfg_shadow[1]!=cfg_active[1];
                    default:card_pending=1'b0;
                endcase
                PAGE_SUBTITLE: case(idx)
                    0:card_pending=subtitle_shadow[0]!=subtitle_active[0];
                    1:card_pending=subtitle_shadow[2:1]!=subtitle_active[2:1];
                    2:card_pending=subtitle_shadow[4:3]!=subtitle_active[4:3];
                    3:card_pending=cfg_shadow[3]!=cfg_active[3];
                    default:card_pending=1'b0;
                endcase
                PAGE_SCREEN: case(idx)
                    0:card_pending=screen_shadow[3:0]!=screen_active[3:0];
                    1:card_pending=screen_shadow[7:4]!=screen_active[7:4];
                    2:card_pending=screen_shadow[9:8]!=screen_active[9:8];
                    // RESET是动作，不是第四个独立参数；变化由前三卡表达。
                    default:card_pending=1'b0;
                endcase
                default:card_pending=1'b0;
            endcase
        end
    endfunction

    function [2:0] card_value_kind;
        input [2:0] p;
        input [2:0] idx;
        begin
            card_value_kind=VALUE_NORMAL;
            case(p)
                PAGE_PROGRAM: case(idx)
                    0,2:card_value_kind=cfg_shadow[idx] ? VALUE_ON : VALUE_OFF;
                    3:card_value_kind=subtitle_shadow[0] ? VALUE_ON : VALUE_OFF;
                    default:card_value_kind=VALUE_NORMAL;
                endcase
                PAGE_AUDIO: case(idx)
                    0:if(audio_shadow[3:0]>10) card_value_kind=VALUE_ERROR;
                    1:card_value_kind=audio_shadow[4] ? VALUE_ON : VALUE_OFF;
                    2:card_value_kind=cfg_shadow[1] ? VALUE_ON : VALUE_OFF;
                    default:card_value_kind=VALUE_NORMAL;
                endcase
                PAGE_SUBTITLE: case(idx)
                    0:card_value_kind=subtitle_shadow[0] ? VALUE_ON : VALUE_OFF;
                    1:if(subtitle_shadow[2:1]>2) card_value_kind=VALUE_ERROR;
                    2:if(subtitle_shadow[4:3]>2) card_value_kind=VALUE_ERROR;
                    3:card_value_kind=cfg_shadow[3] ? VALUE_ON : VALUE_OFF;
                    default:card_value_kind=VALUE_ERROR;
                endcase
                PAGE_SCREEN: case(idx)
                    0:if(screen_shadow[3:0]>8) card_value_kind=VALUE_ERROR;
                    1:if(screen_shadow[7:4]>8) card_value_kind=VALUE_ERROR;
                    2:if(screen_shadow[9:8]>2) card_value_kind=VALUE_ERROR;
                    3:card_value_kind=VALUE_NORMAL;
                    default:card_value_kind=VALUE_ERROR;
                endcase
                PAGE_PERIPHERAL: case(idx)
                    0:card_value_kind=sd_init_done ? VALUE_ON : VALUE_WAIT;
                    1:card_value_kind=buzzer_test ? VALUE_ON : VALUE_NORMAL;
                    default:card_value_kind=VALUE_NORMAL;
                endcase
            endcase
        end
    endfunction

    function [79:0] volume_label;
        input [3:0] level;
        begin
            if(level==10) volume_label="100%      ";
            else if(level<10) volume_label={hex(level),"0%       "};
            else volume_label="ERR       ";
            if(level==0) volume_label="0%        ";
        end
    endfunction

    function [79:0] card_value_label;
        input [2:0] p;
        input [2:0] idx;
        input editing_this;
        begin
            card_value_label="ERR       ";
            case(p)
                PAGE_PROGRAM: case(idx)
                    0,2:card_value_label=cfg_shadow[idx] ? "ON        " : "OFF       ";
                    1:card_value_label=audio_shadow[4] ? "MUTE      " : volume_label(audio_shadow[3:0]);
                    3:card_value_label=subtitle_shadow[0] ? "ON        " : "OFF       ";
                    4:case(period_shadow)
                        0:card_value_label="2S        "; 1:card_value_label="3S        ";
                        2:card_value_label="5S        "; 3:card_value_label="10S       ";
                    endcase
                    5:card_value_label="HDMI-B    ";
                endcase
                PAGE_AUDIO: case(idx)
                    0:card_value_label=volume_label(audio_shadow[3:0]);
                    1:card_value_label=audio_shadow[4] ? "ON        " : "OFF       ";
                    2:card_value_label=cfg_shadow[1] ? "ON        " : "OFF       ";
                    3:card_value_label=editing_this ? "CONFIRM   " : "RESET     ";
                endcase
                PAGE_SUBTITLE: case(idx)
                    0:card_value_label=subtitle_shadow[0] ? "ON        " : "OFF       ";
                    1:case(subtitle_shadow[2:1])
                        0:card_value_label="1/3       "; 1:card_value_label="2/3       ";
                        2:card_value_label="3/3       "; default:card_value_label="ERR       ";
                    endcase
                    2:case(subtitle_shadow[4:3])
                        0:card_value_label="SLOW      "; 1:card_value_label="NORM      ";
                        2:card_value_label="FAST      "; default:card_value_label="ERR       ";
                    endcase
                    3:card_value_label=cfg_shadow[3] ? "ON        " : "OFF       ";
                endcase
                PAGE_SCREEN: case(idx)
                    0:case(screen_shadow[3:0])
                        0:card_value_label="-64       "; 1:card_value_label="-48       ";
                        2:card_value_label="-32       "; 3:card_value_label="-16       ";
                        4:card_value_label="0         "; 5:card_value_label="+16       ";
                        6:card_value_label="+32       "; 7:card_value_label="+48       ";
                        8:card_value_label="+64       "; default:card_value_label="ERR       ";
                    endcase
                    1:case(screen_shadow[7:4])
                        0:card_value_label="50%       "; 1:card_value_label="63%       ";
                        2:card_value_label="75%       "; 3:card_value_label="88%       ";
                        4:card_value_label="100%      "; 5:card_value_label="113%      ";
                        6:card_value_label="125%      "; 7:card_value_label="138%      ";
                        8:card_value_label="150%      "; default:card_value_label="ERR       ";
                    endcase
                    2:case(screen_shadow[9:8])
                        0:card_value_label="COOL      "; 1:card_value_label="NORM      ";
                        2:card_value_label="WARM      "; default:card_value_label="ERR       ";
                    endcase
                    3:card_value_label=editing_this ? "CONFIRM   " : "RESET     ";
                endcase
                PAGE_PERIPHERAL: case(idx)
                    0:card_value_label=sd_init_done ? "READY     " : "WAIT      ";
                    1:card_value_label=buzzer_test ? "TEST      " : "IDLE      ";
                    // 仅调整展示层；沿用既有事件计数高字节口径。
                    2:card_value_label={"CNT",hex(key_events[15:12]),hex(key_events[11:8]),40'h2020202020};
                    3:card_value_label={"LED",hex(led_state),48'h202020202020};
                endcase
            endcase
        end
    endfunction

    function [79:0] pending_label;
        input [79:0] label;
        input pending;
        integer col;
        reg [3:0] length;
        reg [3:0] star_col;
        reg [3:0] reverse_col;
        begin
            length=0;
            for(col=0;col<10;col=col+1)
                if(label[(9-col)*8 +: 8]!=8'h20) length=col+1;
            pending_label=label;
            star_col=length+4'd1;
            reverse_col=4'd9-star_col;
            // 保留一格空白后标记，不允许长度加法溢出窗口。
            if(pending && length<8)
                pending_label[{reverse_col,3'b000} +: 8]="*";
        end
    endfunction

    reg [8:0] volume_bar_end;
    always @(posedge clk) begin
        case(audio_shadow[3:0])
            0:volume_bar_end<=16; 1:volume_bar_end<=36; 2:volume_bar_end<=56;
            3:volume_bar_end<=76; 4:volume_bar_end<=96; 5:volume_bar_end<=116;
            6:volume_bar_end<=136; 7:volume_bar_end<=156; 8:volume_bar_end<=176;
            9:volume_bar_end<=196; 10:volume_bar_end<=216;
            default:volume_bar_end<=16;
        endcase
    end
    reg [79:0] value_text [0:5];
    reg [5:0] state_selected, state_editing, state_pending, state_action;
    reg [2:0] value_kind [0:5];
    reg [39:0] header_status_text;
    reg [1:0] header_status; // 0 READY, 1 EDIT, 2 WAIT
    integer state_index;
    always @(posedge clk) begin
        for(state_index=0;state_index<6;state_index=state_index+1) begin
            state_selected[state_index]<=menu_active && cursor==state_index;
            state_editing[state_index]<=menu_active && cursor==state_index &&
                ((audio_page && audio_edit) || (subtitle_page && subtitle_edit) || (screen_page && screen_edit));
            state_pending[state_index]<=card_pending(state_page,state_index);
            state_action[state_index]<=(state_page!=PAGE_PERIPHERAL || state_index==1);
            value_kind[state_index]<=card_value_kind(state_page,state_index);
            value_text[state_index]<=pending_label(
                card_value_label(state_page,state_index,menu_active && cursor==state_index &&
                    ((audio_page && audio_edit) || (subtitle_page && subtitle_edit) || (screen_page && screen_edit))),
                card_pending(state_page,state_index));
        end
        // 页眉只反映当前聚焦卡或二级编辑态，避免全局dirty泄漏到其他卡。
        // 与各卡pending同拍计算，不能用上一拍state_pending配当前cursor。
        // 不改变控制器、不冻结后续预览，也不延长WAIT的实际持续时间。
        header_status<=cfg_busy ? 2'd2 :
            ((audio_edit || screen_edit || subtitle_edit || card_pending(state_page,cursor)) ? 2'd1 : 2'd0);
        header_status_text<=cfg_busy ? "WAIT " :
            ((audio_edit || screen_edit || subtitle_edit || card_pending(state_page,cursor)) ? "EDIT " : "READY");
    end

    function [5:0] cjk_title_char;
        input       p;
        input [2:0] idx;
        input [1:0] pos;
        input is_screen, is_subtitle, is_audio;
        begin
            cjk_title_char = 8'd0;
            if(is_audio) begin
                case(idx)
                    0:cjk_title_char=(pos==0) ? CJK_YIN : CJK_VOLUME;
                    1:cjk_title_char=(pos==0) ? CJK_JING : CJK_YIN;
                    2:cjk_title_char=(pos==0) ? {1'b0,CJK_BO} : {1'b0,CJK_XING};
                    3:case(pos)
                        0:cjk_title_char=CJK_HUI; 1:cjk_title_char=CJK_FU;
                        2:cjk_title_char=CJK_MO; 3:cjk_title_char=CJK_REN;
                    endcase
                endcase
            end else if (is_subtitle) begin
                case(idx)
                    0:cjk_title_char=(pos==0) ? CJK_ZI : {1'b0,CJK_MU};
                    1:cjk_title_char=(pos==0) ? CJK_NEI : CJK_RONG;
                    2:cjk_title_char=(pos==0) ? CJK_SU : {1'b0,CJK_DU};
                    default:cjk_title_char=(pos==0) ? {1'b0,CJK_BIAO} : {1'b0,CJK_TI};
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
                    3'd1: cjk_title_char = (pos == 0) ? CJK_YIN : CJK_PIN;
                    3'd2: cjk_title_char = (pos == 0) ? CJK_SHI : CJK_JIAN;
                    3'd3: cjk_title_char = (pos == 0) ? CJK_ZI : {1'b0,CJK_MU};
                    3'd4: cjk_title_char = (pos == 0) ? CJK_ZHOU : CJK_QI;
                    default: cjk_title_char = (pos == 0) ? CJK_PING : CJK_MU;
                endcase
            end else begin
                case (idx)
                    3'd0: cjk_title_char = (pos == 0) ? CJK_WAI : CJK_SHE;
                    3'd1: cjk_title_char = (pos == 0) ? CJK_FENG : ((pos == 1) ? CJK_MING : CJK_QI2);
                    3'd2: cjk_title_char = (pos == 0) ? CJK_AN : CJK_JIAN3;
                    default: cjk_title_char = (pos == 0) ? CJK_BAN : ((pos == 1) ? CJK_ZAI : CJK_DENG);
                endcase
            end
        end
    endfunction

    // 节目页严格两行三列；外设和 HDMI-B 设置页两行两列。
    wire wide_cards = page || screen_page || subtitle_page || audio_page;
    wire program_top = y < 9'd272;
    wire [1:0] program_col = (x < 10'd220) ? 2'd0 : ((x < 10'd424) ? 2'd1 : 2'd2);
    wire [2:0] card_idx = wide_cards ?
        ((x < 10'd320) ? ((y < 9'd272) ? 3'd0 : 3'd2) : ((y < 9'd272) ? 3'd1 : 3'd3)) :
        ({1'b0,program_col} + (program_top ? 3'd0 : 3'd3));
    wire [9:0] card_x0 = wide_cards ? ((x < 10'd320) ? 10'd32 : 10'd336) :
                        ((program_col == 0) ? 10'd24 : ((program_col == 1) ? 10'd228 : 10'd432));
    wire [8:0] card_y0 = program_top ? 9'd96 : 9'd288;
    wire [9:0] card_w = wide_cards ? 10'd272 : 10'd184;
    wire [9:0] local_x = x - card_x0;
    wire [8:0] local_y = y - card_y0;
    // 每卡先按绝对字格独立选8位字符，再选择行/列；避免80位文本
    // 先经卡片译码，再串入动态位选。低位偏移仅用必要位宽。
    wire [4:0] left_grid = x[7:3]-5'd1;
    wire [5:0] mid_grid = x[7:2]-6'd1;
    wire [3:0] left_rev = 4'd11-left_grid[4:1];
    wire [3:0] mid_rev = 4'd8-mid_grid[5:2];
    wire [3:0] right_rev = 4'd5-x[7:4];
    wire [3:0] wide_left_rev = 4'd12-x[7:4];
    wire [3:0] wide_right_rev = 4'd15-x[7:4];
    wire [7:0] p0=value_text[0][{left_rev,3'b000} +: 8];
    wire [7:0] p1=value_text[1][{mid_rev,3'b000} +: 8];
    wire [7:0] p2=value_text[2][{right_rev,3'b000} +: 8];
    wire [7:0] p3=value_text[3][{left_rev,3'b000} +: 8];
    wire [7:0] p4=value_text[4][{mid_rev,3'b000} +: 8];
    wire [7:0] p5=value_text[5][{right_rev,3'b000} +: 8];
    wire [7:0] w0=value_text[0][{wide_left_rev,3'b000} +: 8];
    wire [7:0] w1=value_text[1][{wide_right_rev,3'b000} +: 8];
    wire [7:0] w2=value_text[2][{wide_left_rev,3'b000} +: 8];
    wire [7:0] w3=value_text[3][{wide_right_rev,3'b000} +: 8];
    wire [7:0] pixel_value_char=wide_cards ?
        (program_top ? ((x[9:6]<4'd5) ? w0 : w1) : ((x[9:6]<4'd5) ? w2 : w3)) :
        (program_top ? ((x[9:2]<8'd55) ? p0 : (x[9:3]<7'd53) ? p1 : p2) :
                       ((x[9:2]<8'd55) ? p3 : (x[9:3]<7'd53) ? p4 : p5));
    wire selected=state_selected[card_idx];
    wire editing=state_editing[card_idx];
    wire pending=state_pending[card_idx];
    wire actionable=state_action[card_idx];
    wire [2:0] pixel_value_kind=value_kind[card_idx];
    wire card_area = wide_cards ? ((((x >= 10'd32) && (x < 10'd304)) ||
                              ((x >= 10'd336) && (x < 10'd608))) &&
                             (((y >= 9'd96) && (y < 9'd256)) ||
                              ((y >= 9'd288) && (y < 9'd448)))) :
                      ((((x >= 10'd24) && (x < 10'd208)) ||
                                      ((x >= 10'd228) && (x < 10'd412)) ||
                                      ((x >= 10'd432) && (x < 10'd616))) &&
                                     (((y >= 9'd96) && (y < 9'd256)) ||
                                      ((y >= 9'd288) && (y < 9'd448))));

    wire header_hit = (x >= 10'd32) && (x < 10'd288) &&
                      (y >= 9'd16) && (y < 9'd48);
    // Native 32x32 glyphs retain the previous title footprint and pixel latency.
    wire cjk_three_chars = page && !subtitle_page && !audio_page && ((card_idx == 3'd1) || (card_idx == 3'd3));
    wire [9:0] title_end = audio_page ? ((card_idx==3) ? 10'd144 : 10'd80) : screen_page ? ((card_idx == 3) ? 10'd144 : ((card_idx == 1) ? 10'd112 : 10'd80)) :
                          (cjk_three_chars ? 10'd112 : 10'd80);
    wire cjk_title_hit = card_area && (local_x >= 10'd16) &&
                         (local_x < title_end) &&
                         (local_y >= 9'd16) && (local_y < 9'd48);
    wire card_value_hit = card_area && (local_x >= 10'd16) &&
                          (local_x < 10'd176) && (local_y >= 9'd104) &&
                          (local_y < 9'd136);
    wire arrow_hit=card_area && selected && actionable &&
                   (local_x >= (wide_cards ? 10'd236 : 10'd148)) &&
                   (local_x < (wide_cards ? 10'd252 : 10'd164)) &&
                   (local_y >= 9'd16) && (local_y < 9'd48);
    wire footer_hit = !menu_active && (x >= 10'd32) && (x < 10'd288) &&
                      (y >= 9'd456) && (y < 9'd472);
    wire [4:0] footer_pos = (x - 10'd32) >> 3;
    wire status_area = menu_active && x>=10'd496 && x<10'd608 && y>=9'd16 && y<9'd48;
    wire status_hit = status_area && x>=10'd512 && x<10'd592;
    wire [3:0] header_pos = x[7:4] - 4'd2;
    wire [2:0] status_pos = x[6:4];
    wire [3:0] value_pos = local_x[7:4] - 4'd1;
    wire [3:0] header_rev = 4'd15 - header_pos;
    wire [2:0] status_rev = 3'd4 - status_pos;
    wire [3:0] value_rev = 4'd9 - value_pos;
    // 二级页用绝对字格边界；避免local_x减法串入常见状态字路径。
    wire [3:0] detail_pos = x[7:4] - ((x<10'd320) ? 4'd3 : 4'd6);
    wire [3:0] detail_rev = 4'd9 - detail_pos;
    wire [4:0] footer_rev = 5'd31 - footer_pos;

    // 中文地址只由绝对字格边界决定，不串接 card_x0/local_x 的减法。
    // 字库持续读取；真正的绘制仍由同拍 cjk_d/glyph_hit_d 限定。
    // 因而不必把卡片命中、页眉优先级再串入 BRAM 地址关键路径。
    wire [1:0] wide_left_pos = x<10'd80 ? 2'd0 : x<10'd112 ? 2'd1 : x<10'd144 ? 2'd2 : 2'd3;
    wire [1:0] wide_right_pos = x<10'd384 ? 2'd0 : x<10'd416 ? 2'd1 : x<10'd448 ? 2'd2 : 2'd3;
    wire [5:0] wide_left_glyph = cjk_title_char(page, program_top ? 3'd0 : 3'd2, wide_left_pos, screen_page, subtitle_page, audio_page);
    wire [5:0] wide_right_glyph = cjk_title_char(page, program_top ? 3'd1 : 3'd3, wide_right_pos, screen_page, subtitle_page, audio_page);
    wire [5:0] program_left_glyph = cjk_title_char(1'b0, program_top ? 3'd0 : 3'd3, x<10'd72 ? 2'd0 : 2'd1, 1'b0, 1'b0, 1'b0);
    wire [5:0] program_mid_glyph = cjk_title_char(1'b0, program_top ? 3'd1 : 3'd4, x<10'd276 ? 2'd0 : 2'd1, 1'b0, 1'b0, 1'b0);
    wire [5:0] program_right_glyph = cjk_title_char(1'b0, program_top ? 3'd2 : 3'd5, x<10'd480 ? 2'd0 : 2'd1, 1'b0, 1'b0, 1'b0);
    wire [5:0] cjk_pixel_glyph = wide_cards ? (x<10'd320 ? wide_left_glyph : wide_right_glyph) :
                               x<10'd220 ? program_left_glyph : x<10'd424 ? program_mid_glyph : program_right_glyph;

    reg [7:0] req_char;
    // 字符ROM允许在非文字区读取无关字符，输出仍由同拍glyph_hit_d屏蔽。
    // ASCII值区、箭头区、页眉和提示按绝对行带选字，避免卡片命中/
    // 中文优先级/焦点判断串入ASCII BRAM地址，像素延迟保持不变。
    always @* begin
        req_char = pixel_value_char;
        if(y<9'd64) begin
            if(x<10'd496)
                req_char = !menu_active ? STR_PLAY[{header_rev,3'b000} +: 8] :
                           audio_page ? STR_AUDIO[{header_rev,3'b000} +: 8] :
                           subtitle_page ? STR_SUBTITLE[{header_rev,3'b000} +: 8] :
                           screen_page ? STR_SCREEN[{header_rev,3'b000} +: 8] :
                           page ? STR_PERI[{header_rev,3'b000} +: 8] :
                                  STR_PROG[{header_rev,3'b000} +: 8];
            else req_char = header_status_text[{status_rev,3'b000} +: 8];
        end else if((y>=9'd112 && y<9'd144) || (y>=9'd304 && y<9'd336))
            req_char = ">";
        else if(!menu_active && y>=9'd456)
            req_char = STR_PLAY_KEYS[{footer_rev,3'b000} +: 8];
    end
    reg [3:0] req_row;
    reg [2:0] req_col;
    reg [2:0] req_kind;
    reg       req_cjk;
    reg [5:0] req_cjk_idx;
    reg [4:0] req_cjk_row;
    always @* begin
        // ASCII字模行只依赖绝对y行带，不能经x/卡片命中再选行地址。
        // 非文字区读出的无关行由glyph_hit_d屏蔽，不改变可见像素。
        if(y<9'd64 || (y>=9'd112 && y<9'd144) || (y>=9'd304 && y<9'd336))
            req_row=y[4:1]-4'd8;
        else if(!menu_active && y>=9'd456) req_row=y[3:0]-4'd8;
        else req_row=y[4:1]-4'd4;
        req_col  = 3'd0;
        req_kind = KIND_HEADER;
        req_cjk = 1'b0;
        req_cjk_idx = cjk_pixel_glyph;
        req_cjk_row = local_y[4:0] - 5'd16;
        if (header_hit) begin
            req_kind = KIND_HEADER;
            req_col  = (x - 10'd32) >> 1;
        end else if (status_hit) begin
            req_kind = KIND_STATUS;
            req_col = x[3:1];
        end else if (cjk_title_hit) begin
            req_kind = KIND_CJK;
            req_cjk = 1'b1;
        end else if (arrow_hit) begin
            req_kind = KIND_ARROW;
            req_col = local_x[3:1] - (wide_cards ? 3'd6 : 3'd2);
        end else if (card_value_hit) begin
            req_kind = KIND_VALUE;
            req_col  = (local_x - 10'd16) >> 1;
        end else if (footer_hit) begin
            req_kind = KIND_FOOTER;
            req_col  = x - 10'd32;
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
    reg volume_bar_d, volume_bar_on_d, audio_muted_d;
    reg de_d, card_area_d, selected_d, editing_d, pending_d, wide_d, status_area_d;
    reg [2:0] kind_d, value_kind_d;
    reg [1:0] status_d;
    reg [2:0] glyph_col_d;
    reg glyph_hit_d, cjk_d;
    reg [4:0] cjk_col_d;
    always @(posedge clk) begin
        volume_bar_d<=audio_page && card_idx==0 && card_area &&
                      local_x>=16 && local_x<216 && local_y>=72 && local_y<84 &&
                      !((local_x>=32 && local_x<36) || (local_x>=52 && local_x<56) ||
                        (local_x>=72 && local_x<76) || (local_x>=92 && local_x<96) ||
                        (local_x>=112 && local_x<116) || (local_x>=132 && local_x<136) ||
                        (local_x>=152 && local_x<156) || (local_x>=172 && local_x<176) ||
                        (local_x>=192 && local_x<196) || local_x>=212);
        volume_bar_on_d<=local_x<volume_bar_end;
        audio_muted_d<=audio_shadow[4];
        x_d<=x; y_d<=y; de_d<=de;
        card_area_d<=card_area;
        selected_d<=selected; editing_d<=editing; pending_d<=pending;
        wide_d<=wide_cards; status_area_d<=status_area;
        kind_d<=req_kind; value_kind_d<=pixel_value_kind; status_d<=header_status;
        glyph_col_d<=req_col;
        glyph_hit_d<=header_hit || status_hit || cjk_title_hit || arrow_hit || card_value_hit || footer_hit;
        cjk_d<=req_cjk; cjk_col_d<=local_x[4:0]-5'd16;
        local_x_d<=local_x; local_y_d<=local_y;
    end

    // 两种宽度、两种偶数线宽均用常量比较，1.5倍映射后恰为3/6像素。
    wire thin_border=(local_x_d<10'd2) ||
                     (local_x_d >= (wide_d ? 10'd270 : 10'd182)) ||
                     (local_y_d<9'd2) || (local_y_d>=9'd158);
    wire thick_border=(local_x_d<10'd4) ||
                      (local_x_d >= (wide_d ? 10'd268 : 10'd180)) ||
                      (local_y_d<9'd4) || (local_y_d>=9'd156);
    wire card_border=card_area_d && (selected_d ? thick_border : thin_border);
    wire header_area=y_d<9'd64;
    wire header_rule=y_d>=9'd62 && y_d<9'd64;
    wire glyph_on=glyph_hit_d && (cjk_d ? cjk_glyph_bits[31-cjk_col_d] : glyph_bits[7-glyph_col_d]);
    wire [23:0] card_fill=selected_d ? SEL : SURF;
    wire [23:0] value_fg=(value_kind_d==VALUE_ERROR) ? OFF :
                         (editing_d || pending_d) ? AMBER :
                         (value_kind_d==VALUE_ON) ? ON :
                         (value_kind_d==VALUE_OFF) ? OFF :
                         (value_kind_d==VALUE_WAIT) ? AMBER : VALUE;
    wire [23:0] status_fg=(status_d==2) ? WAIT_FG : (status_d==1) ? AMBER : MUTED;
    wire [23:0] text_fg=(kind_d==KIND_VALUE) ? value_fg :
                        (kind_d==KIND_STATUS) ? status_fg :
                        (kind_d==KIND_ARROW) ? (editing_d ? AMBER : FOCUS) :
                        (kind_d==KIND_HEADER || kind_d==KIND_FOOTER) ? MUTED : FG;
    wire [23:0] base=status_area_d ? ((status_d==2) ? AMBER : CHIP) :
                     header_area ? HEADER : card_area_d ? card_fill : BG;
    wire [23:0] border=selected_d ? (editing_d ? AMBER : FOCUS) : (pending_d ? AMBER : FRAME);
    assign rgb=!de_d ? 24'd0 : header_rule ? RULE :
               card_border ? border : glyph_on ? text_fg :
               volume_bar_d ? (volume_bar_on_d ? (audio_muted_d ? MUTED : ON) : FRAME) : base;
endmodule
