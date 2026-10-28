// 原生32像素字模同步读；文字颜色与字模同拍，笔画外保留背景图片。
module osd_engine_720(
    input wire I_clk,
    input wire I_rst,
    input wire I_vs_pulse,
    input wire [4:0] I_subtitle_cfg,
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    input wire [23:0] I_bg_rgb,I_uptime_bcd,
    input wire I_clock_enable,
    input wire I_text_enable,
    // 尺寸总线沿用完整页提交邮箱：发送端锁住直到转场释放，事件同步后采样。
    input wire I_picture_commit,
    input wire I_picture_buf,
    input wire [10:0] I_picture_width,
    input wire [9:0] I_picture_height,
    input wire I_picture_front,
    input wire I_picture_enable,
    output wire [23:0] O_rgb
);
`include "font_720_map.vh"
    // 兼容旧 testbench/封装：未连接的新开关在仿真中为 X 时保持原有图层开启。
    // 实际硬件只有 0/1，不改变正常综合逻辑。
    wire text_enable_i  = (I_text_enable  !== 1'b0);
    wire clock_enable_i = (I_clock_enable !== 1'b0);
    localparam [23:0] TITLE_FG=24'hF2FAFF,
                      CLOCK_FG=24'hC9DBE5, BADGE_BG=24'h0E3A4C;
    wire title_y=text_enable_i && I_y>=24 && I_y<56;
    wire subtitle_enable = (I_subtitle_cfg[0] === 1'b1);
    wire clock_y=clock_enable_i && I_y>=672 && I_y<704;
    wire title_x=I_x>=32 && I_x<480;
    wire clock_x=I_x>=896 && I_x<1248;
    wire title_plate=text_enable_i && I_y>=16 && I_y<64 &&
                     (I_x>=16 && I_x<496);
    wire clock_plate=clock_enable_i && I_x>=880 && I_x<1264 && I_y>=664 && I_y<712;
    // 标题和时间共用下面唯一的同步字模ROM。
    wire [5:0] title_col = I_x[10:5]-6'd1;
    wire [5:0] clock_col = I_x[10:5]-6'd28;
    wire [5:0] title_glyph, clock_static_glyph;
    osd_text_720 u_text(.win(2'd0),.col(title_col),.glyph(title_glyph));
    osd_text_720 u_clock_text(.win(2'd1),.col(clock_col),.glyph(clock_static_glyph));
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
    // 尺寸换算在提交后逐位减去1000/100/10完成，不在像素路径做除法。
    // 只保存一份8格文字（F=空格、A=X）。装入目标页后暂隐，
    // 待前台页匹配且转场结束才显示，避免三份字符串及逐像素页选择器。
    reg [10:0] resolution_work;
    reg [9:0] resolution_height;
    reg [3:0] resolution_stage,resolution_digit;
    reg resolution_started,resolution_busy, resolution_buf;
    reg [31:0] resolution_pending;
    reg resolution_pending_valid;
    reg resolution_valid;
    // 1..4 为宽度千/百/十/个，5为X，6..8为高度百/十/个。
    wire [10:0] resolution_divisor=(resolution_stage==1) ? 11'd1000 :
        ((resolution_stage==2)||(resolution_stage==6)) ? 11'd100 : 11'd10;
    // 无符号减法多留一位，最高位同时给出借位，避免再综合一套宽比较器。
    wire [11:0] resolution_difference={1'b0,resolution_work}-{1'b0,resolution_divisor};
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            resolution_work<=0;resolution_height<=0;resolution_digit<=0;
            resolution_stage<=0;resolution_started<=0;resolution_busy<=0;resolution_buf<=0;
            resolution_pending<=32'hFFFFFFFF;
            resolution_pending_valid<=0;resolution_valid<=0;
        end else begin
            if(I_vs_pulse && resolution_pending_valid) begin
                resolution_valid<=1;
                resolution_pending_valid<=0;
            end
            if(I_picture_commit === 1'b1) begin
                resolution_work<=I_picture_width;
                resolution_height<=I_picture_height;
                resolution_stage<=1;resolution_digit<=0;resolution_started<=0;
                resolution_busy<=1;resolution_buf<=I_picture_buf;
                resolution_pending<=32'hFFFFFFFF;
                resolution_pending_valid<=0;
                resolution_valid<=0;
            end else if(resolution_busy) begin
                if(resolution_stage==5) begin
                    resolution_pending<={resolution_pending[27:0],4'hA};
                    resolution_work<={1'b0,resolution_height};
                    resolution_stage<=6;resolution_started<=0;
                end else if((resolution_stage==4)||(resolution_stage==8)) begin
                    resolution_pending<={resolution_pending[27:0],resolution_work[3:0]};
                    resolution_stage<=5;
                    if(resolution_stage==8) begin
                        resolution_pending_valid<=1;resolution_busy<=0;
                    end
                end else if(!resolution_difference[11]) begin
                    resolution_work<=resolution_difference[10:0];
                    resolution_digit<=resolution_digit+1'b1;
                end else begin
                    if(resolution_digit!=0 || resolution_started) begin
                        resolution_pending<={resolution_pending[27:0],resolution_digit};
                        resolution_started<=1;
                    end
                    resolution_digit<=0;
                    resolution_stage<=resolution_stage+1'b1;
                end
            end
        end
    end
    wire [31:0] resolution_chars=resolution_pending;
    wire resolution_enable=(I_picture_enable === 1'b1) && resolution_valid &&
                           (resolution_buf==I_picture_front);
    wire resolution_plate=resolution_enable && I_x>=976 && I_x<1264 && I_y>=80 && I_y<128;
    wire resolution_x=I_x>=992 && I_x<1248;
    wire resolution_hit=resolution_enable && resolution_x && I_y>=88 && I_y<120;
    wire [2:0] resolution_col=I_x[7:5]-3'd7;
    wire [3:0] resolution_char=resolution_chars[31-4*resolution_col -: 4];
    // 先选4位BCD，再共用数字字模译码；不为时间六位各复制一份6位字模查表。
    reg [3:0] clock_number;
    reg clock_number_hit,clock_colon_hit;
    always @(*) begin
        clock_number=0;clock_number_hit=1;clock_colon_hit=0;
        case(clock_col)
            3:clock_number=I_uptime_bcd[23:20];
            4:clock_number=I_uptime_bcd[19:16];
            5,8:begin clock_number_hit=0;clock_colon_hit=1;end
            6:clock_number=I_uptime_bcd[15:12];
            7:clock_number=I_uptime_bcd[11:8];
            9:clock_number=I_uptime_bcd[7:4];
            10:clock_number=I_uptime_bcd[3:0];
            default:clock_number_hit=0;
        endcase
    end
    // 时间在下半屏、尺寸在上半屏，两个区域共用一次数字译码。
    wire [5:0] number_glyph=digit(I_y[9] ? clock_number : resolution_char);
    wire [5:0] resolution_glyph=(resolution_char==4'hA) ? RESOLUTION_X : number_glyph;
    wire [5:0] clock_glyph=clock_number_hit ? number_glyph : clock_colon_hit ? COLON : clock_static_glyph;
    wire text_hit=(title_y && title_x) || (clock_y && clock_x);
    // 64格只增加文本索引位，不扩字模ROM。仅VS推进位置，离场留白后重启。
    reg [10:0] scroll_position;
    reg slow_phase;
    reg [4:0] subtitle_seen;
    reg clock_seen;
    wire [10:0] scroll_base=clock_enable_i ? 11'd1184 : 11'd896;
    // 最长正文19格=608px：窗口宽736/1024 + 正文608 + 离场留白64。
    // 不能沿用14格的结束位置，否则加长的欢迎语会在句尾离场前重启。
    wire [10:0] scroll_limit=clock_enable_i ? 11'd1408 : 11'd1696;
    wire [10:0] scroll_origin=scroll_base+scroll_position;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            scroll_position<=11'd0;
            slow_phase<=1'b0;
            subtitle_seen<=5'h08;
            clock_seen<=1'b1;
        end else if (!subtitle_enable || I_subtitle_cfg!=subtitle_seen || clock_enable_i!=clock_seen) begin
            scroll_position<=11'd0;
            slow_phase<=1'b0;
            subtitle_seen<=I_subtitle_cfg;
            clock_seen<=clock_enable_i;
        end else if (I_vs_pulse) begin
            slow_phase<=~slow_phase;
            if (scroll_position>=scroll_limit) scroll_position<=11'd0;
            else case (I_subtitle_cfg[4:3])
                0:if (slow_phase) scroll_position<=scroll_position+11'd1;
                1:scroll_position<=scroll_position+11'd1;
                default:scroll_position<=scroll_position+11'd2;
            endcase
        end
    end
    wire subtitle_band = subtitle_enable && I_x>=16 && I_x<1264 && I_y>=664 && I_y<712;
    wire subtitle_badge = subtitle_band && I_x<112;
    wire subtitle_line = subtitle_band && I_y<666;
    wire subtitle_y = I_y>=672 && I_y<704;
    wire subtitle_badge_text = subtitle_band && subtitle_y && I_x>=32 && I_x<96;
    // 右端严格排除；正文在2048周期内单次经过窗口，不两端分段。
    wire subtitle_message_text = subtitle_enable && subtitle_y && I_x>=128 &&
                                 I_x<(clock_enable_i ? 11'd864 : 11'd1152);
    wire [10:0] subtitle_source_x = I_x + scroll_origin;
    wire [5:0] subtitle_glyph;
    subtitle_text_720 u_subtitle_text(.preset(I_subtitle_cfg[2:1]), .col(subtitle_source_x[10:5]), .glyph(subtitle_glyph));
    // 地址只用分区选择，完整命中在输出屏蔽，避免矩形比较串入ROM地址。
    // 顶部和底部互斥，共享一个同步ROM；时间只在开启时占用正文右侧。
    wire [5:0] bottom_glyph = (I_x<112) ? ((I_x<64) ? BADGE_SHI : BADGE_JIE) :
                              (clock_enable_i && I_x>=896) ? clock_glyph : subtitle_glyph;
    wire [5:0] glyph = I_y[9] ? bottom_glyph : I_y[6] ? resolution_glyph : title_glyph;
    wire [4:0] row = I_y[9] ? I_y[4:0] : I_y[4:0]-5'd24;
    wire [31:0] bits;
    font_rom_720 u_font(.clk(I_clk),.glyph(glyph),.row(row),.bits(bits));
    reg [4:0] cell_x;
    reg [23:0] background;
    reg band_q, badge_q, line_q, glyph_hit_q;
    reg clock_text_q,resolution_text_q;
    always @(posedge I_clk) begin
        cell_x <= subtitle_badge_text ? I_x[4:0] :
                  subtitle_message_text ? subtitle_source_x[4:0] : I_x[4:0];
        background <= I_bg_rgb;
        // 所有底板取并集，从原背景只压暗一次；不对已压暗像素再处理。
        band_q <= subtitle_band || clock_plate || title_plate || resolution_plate;
        badge_q <= subtitle_badge;
        line_q <= subtitle_line;
        glyph_hit_q <= text_hit || subtitle_badge_text || subtitle_message_text || resolution_hit;
        // ROM延迟一拍，颜色选择也必须寄存，防止行边界串色。
        clock_text_q <= clock_y && clock_x;
        resolution_text_q <= resolution_hit;
    end
    wire [23:0] dim_background = {2'b0,background[23:18],2'b0,background[15:10],2'b0,background[7:2]};
    wire [23:0] base = badge_q ? BADGE_BG : band_q ? dim_background : background;
    assign O_rgb = line_q ? 24'h38BDF8 :
                   (glyph_hit_q && bits[31-cell_x]) ?
                   (resolution_text_q ? 24'hD8B4FE : clock_text_q ? CLOCK_FG : TITLE_FG) : base;
endmodule
