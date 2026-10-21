// Generated preset cells; 32 cells per cycle, blank-padded.
module subtitle_text_720(input wire [1:0] preset, input wire [4:0] col, output reg [5:0] glyph);
always @* begin
case ({preset,col})
    {2'd0,5'd0}: glyph=6'd33; // 欢
    {2'd0,5'd1}: glyph=6'd34; // 迎
    {2'd0,5'd2}: glyph=6'd12; // 体
    {2'd0,5'd3}: glyph=6'd35; // 验
    {2'd0,5'd4}: glyph=6'd4; // 双
    {2'd0,5'd5}: glyph=6'd2; // 屏
    {2'd0,5'd6}: glyph=6'd10; // 多
    {2'd0,5'd7}: glyph=6'd11; // 媒
    {2'd0,5'd8}: glyph=6'd12; // 体
    {2'd0,5'd9}: glyph=6'd13; // 系
    {2'd0,5'd10}: glyph=6'd14; // 统
    {2'd1,5'd0}: glyph=6'd36; // 活
    {2'd1,5'd1}: glyph=6'd37; // 动
    {2'd1,5'd2}: glyph=6'd38; // 正
    {2'd1,5'd3}: glyph=6'd39; // 在
    {2'd1,5'd4}: glyph=6'd40; // 进
    {2'd1,5'd5}: glyph=6'd21; // 行
    {2'd1,5'd6}: glyph=6'd0; //  
    {2'd1,5'd7}: glyph=6'd33; // 欢
    {2'd1,5'd8}: glyph=6'd34; // 迎
    {2'd1,5'd9}: glyph=6'd41; // 参
    {2'd1,5'd10}: glyph=6'd42; // 与
    {2'd1,5'd11}: glyph=6'd12; // 体
    {2'd1,5'd12}: glyph=6'd35; // 验
    {2'd2,5'd0}: glyph=6'd43; // 图
    {2'd2,5'd1}: glyph=6'd44; // 片
    {2'd2,5'd2}: glyph=6'd0; //  
    {2'd2,5'd3}: glyph=6'd45; // 音
    {2'd2,5'd4}: glyph=6'd46; // 乐
    {2'd2,5'd5}: glyph=6'd0; //  
    {2'd2,5'd6}: glyph=6'd47; // 字
    {2'd2,5'd7}: glyph=6'd48; // 幕
    {2'd2,5'd8}: glyph=6'd0; //  
    {2'd2,5'd9}: glyph=6'd49; // 精
    {2'd2,5'd10}: glyph=6'd50; // 彩
    {2'd2,5'd11}: glyph=6'd51; // 呈
    {2'd2,5'd12}: glyph=6'd52; // 现
default: glyph=0;
endcase
end
endmodule
