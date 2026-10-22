// Generated preset cells; 32 cells per cycle, blank-padded.
module subtitle_text_720(input wire [1:0] preset, input wire [4:0] col, output reg [5:0] glyph);
always @* begin
case ({preset,col})
    {2'd0,5'd0}: glyph=6'd1; // 炬
    {2'd0,5'd1}: glyph=6'd2; // 屏
    {2'd0,5'd2}: glyph=6'd3; // —
    {2'd0,5'd3}: glyph=6'd4; // 双
    {2'd0,5'd4}: glyph=6'd5; // 模
    {2'd0,5'd5}: glyph=6'd6; // H
    {2'd0,5'd6}: glyph=6'd7; // D
    {2'd0,5'd7}: glyph=6'd8; // M
    {2'd0,5'd8}: glyph=6'd9; // I
    {2'd0,5'd9}: glyph=6'd10; // 多
    {2'd0,5'd10}: glyph=6'd11; // 媒
    {2'd0,5'd11}: glyph=6'd12; // 体
    {2'd0,5'd12}: glyph=6'd13; // 系
    {2'd0,5'd13}: glyph=6'd14; // 统
    {2'd1,5'd0}: glyph=6'd4; // 双
    {2'd1,5'd1}: glyph=6'd2; // 屏
    {2'd1,5'd2}: glyph=6'd33; // 协
    {2'd1,5'd3}: glyph=6'd34; // 作
    {2'd1,5'd4}: glyph=6'd0; //  
    {2'd1,5'd5}: glyph=6'd35; // 一
    {2'd1,5'd6}: glyph=6'd2; // 屏
    {2'd1,5'd7}: glyph=6'd36; // 操
    {2'd1,5'd8}: glyph=6'd34; // 作
    {2'd1,5'd9}: glyph=6'd0; //  
    {2'd1,5'd10}: glyph=6'd35; // 一
    {2'd1,5'd11}: glyph=6'd2; // 屏
    {2'd1,5'd12}: glyph=6'd37; // 呈
    {2'd1,5'd13}: glyph=6'd38; // 现
    {2'd2,5'd0}: glyph=6'd39; // 图
    {2'd2,5'd1}: glyph=6'd40; // 片
    {2'd2,5'd2}: glyph=6'd0; //  
    {2'd2,5'd3}: glyph=6'd41; // 音
    {2'd2,5'd4}: glyph=6'd42; // 乐
    {2'd2,5'd5}: glyph=6'd0; //  
    {2'd2,5'd6}: glyph=6'd43; // 字
    {2'd2,5'd7}: glyph=6'd44; // 幕
    {2'd2,5'd8}: glyph=6'd0; //  
    {2'd2,5'd9}: glyph=6'd45; // 精
    {2'd2,5'd10}: glyph=6'd46; // 彩
    {2'd2,5'd11}: glyph=6'd47; // 同
    {2'd2,5'd12}: glyph=6'd2; // 屏
default: glyph=0;
endcase
end
endmodule
