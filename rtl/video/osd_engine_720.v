// 原生32像素字模同步读；只覆盖黑色笔画，保留背景图片。
module osd_engine_720(
    input wire I_clk,
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    input wire [23:0] I_bg_rgb,I_uptime_bcd,
    input wire [1:0] I_mode,
    output wire [23:0] O_rgb
);
`include "font_720_map.vh"
    wire title_y=I_y>=32 && I_y<64;
    wire clock_y=I_y>=656 && I_y<688;
    wire title_x=I_x>=32 && I_x<480;
    wire mode_x=I_x>=1120 && I_x<1248;
    wire clock_x=I_x>=896 && I_x<1248;
    wire [5:0] col = clock_y ? I_x[10:5]-6'd28 : mode_x ? I_x[10:5]-6'd35 : I_x[10:5]-6'd1;
    wire [1:0] win = clock_y ? 2'd3 : mode_x ? (I_mode==2 ? 2'd2:2'd1) : 2'd0;
    wire [5:0] static_glyph;
    osd_text_720 u_text(.win(win),.col(col),.glyph(static_glyph));
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
        case(col)
            3:clock_glyph=digit(I_uptime_bcd[23:20]);
            4:clock_glyph=digit(I_uptime_bcd[19:16]);
            5,8:clock_glyph=COLON;
            6:clock_glyph=digit(I_uptime_bcd[15:12]);
            7:clock_glyph=digit(I_uptime_bcd[11:8]);
            9:clock_glyph=digit(I_uptime_bcd[7:4]);
            10:clock_glyph=digit(I_uptime_bcd[3:0]);
            default:clock_glyph=static_glyph;
        endcase
    end
    wire text_hit=(title_y && (title_x || mode_x)) || (clock_y && clock_x);
    wire [5:0] glyph = text_hit ? (clock_y ? clock_glyph : static_glyph) : 6'd0;
    wire [4:0] row=clock_y ? I_y-656 : I_y-32;
    wire [31:0] bits;
    font_rom_720 u_font(.clk(I_clk),.glyph(glyph),.row(row),.bits(bits));
    reg [4:0] cell_x;
    reg [23:0] background;
    always @(posedge I_clk) begin cell_x<=I_x[4:0]; background<=I_bg_rgb; end
    assign O_rgb=bits[31-cell_x] ? 24'h000000:background;
endmodule
