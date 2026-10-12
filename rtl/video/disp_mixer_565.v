// RGB565双像素字解包；参考老师第十讲frame_blend的帧级互补权重。
// 两级寄存流水保证74.25MHz下RGB、坐标和DE严格同拍。
module disp_mixer_565(
    input wire clk, rst, de_in, vs_in,
    input wire [10:0] x,
    input wire [9:0] y,
    input wire [31:0] a_data, b_data,
    input wire a_empty, b_empty, tr_active,
    input wire [7:0] alpha,
    output wire a_pop, b_pop,
    output reg de_out, vs_out,
    output reg [10:0] x_out,
    output reg [9:0] y_out,
    output reg [23:0] rgb_out,
    output reg [31:0] underflow_cnt
);
    function [23:0] expand565;
        input [15:0] pixel;
        begin
            expand565 = {pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
        end
    endfunction
    // FWFT队头连续提供偶/奇半字；奇列消费后才弹出下一个字。
    assign a_pop = de_in && x[0];
    assign b_pop = de_in && x[0] && tr_active;
    wire [23:0] pa = expand565(x[0] ? a_data[31:16] : a_data[15:0]);
    wire [23:0] pb = expand565(x[0] ? b_data[31:16] : b_data[15:0]);
    wire missing = de_in && ((!tr_active || alpha != 255) && a_empty ||
                             (tr_active && alpha != 0 && b_empty));
    wire [8:0] wb = tr_active ? {1'b0,alpha} : 9'd0;
    wire [8:0] wa = 9'd256-wb;
    reg [16:0] ar, ag, ab, br, bg, bb;
    reg [23:0] direct_rgb;
    reg direct_on, missing_q, de_q, vs_q;
    reg [10:0] x_q;
    reg [9:0] y_q;
    wire [17:0] sum_r = {1'b0,ar}+{1'b0,br}+18'd128;
    wire [17:0] sum_g = {1'b0,ag}+{1'b0,bg}+18'd128;
    wire [17:0] sum_b = {1'b0,ab}+{1'b0,bb}+18'd128;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ar<=0; ag<=0; ab<=0; br<=0; bg<=0; bb<=0;
            de_q<=0; vs_q<=0; x_q<=0; y_q<=0; direct_on<=0; direct_rgb<=0; missing_q<=0;
            rgb_out<=0; de_out<=0; vs_out<=0; x_out<=0; y_out<=0; underflow_cnt<=0;
        end else begin
            ar <= pa[23:16]*wa; ag <= pa[15:8]*wa; ab <= pa[7:0]*wa;
            br <= pb[23:16]*wb; bg <= pb[15:8]*wb; bb <= pb[7:0]*wb;
            direct_on <= !tr_active || alpha==0 || alpha==255;
            direct_rgb <= tr_active && alpha==255 ? pb : pa;
            missing_q<=missing; de_q<=de_in; vs_q<=vs_in; x_q<=x; y_q<=y;
            de_out<=de_q; vs_out<=vs_q; x_out<=x_q; y_out<=y_q;
            rgb_out <= !de_q || missing_q ? 24'd0 : direct_on ? direct_rgb :
                       {sum_r[15:8], sum_g[15:8], sum_b[15:8]};
            if (missing) underflow_cnt<=underflow_cnt+1'b1;
        end
    end
endmodule
