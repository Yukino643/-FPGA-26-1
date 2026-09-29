// blend_fn.vh — 通用 alpha 混合函数（计划书 5.4 多图层混合共用）
// out = (fg*a + bg*(255-a) + 127) >> 8,  a∈[0,255]
// 25MHz 像素域，8x8 常量乘由综合器映射 LUT/DSP
function [7:0] blend_ch;
    input [7:0] fg;
    input [7:0] bg;
    input [7:0] a;
    reg [17:0] tmp;
    begin
        // 注意: 必须先在 ≥18bit 中间量里完成乘加，再移位
        // （直接写 8bit 赋值会把整条表达式按 8bit 截断，结果恒 0）
        tmp = fg * a + bg * (9'd255 - {1'b0, a}) + 9'd127;
        blend_ch = tmp >> 8;
    end
endfunction

function [23:0] blend_pix;
    input [23:0] fg;
    input [23:0] bg;
    input [7:0]  a;
    begin
        blend_pix = {blend_ch(fg[23:16], bg[23:16], a),
                     blend_ch(fg[15:8], bg[15:8],  a),
                     blend_ch(fg[7:0],  bg[7:0],   a)};
    end
endfunction
