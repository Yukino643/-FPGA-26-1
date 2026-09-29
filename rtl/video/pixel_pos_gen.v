// pixel_pos_gen.v — 从 hs/vs 派生有效区像素坐标（用于在既有视频路径上插入逐像素处理）
// 注意: O_x/O_y/O_de 三者严格同拍 —— O_de 是 I_de 打一拍的相位对齐版，
//       消费方(混合器/抓帧)必须用 O_de，不能用原始 I_de（否则错位 1 像素）
module pixel_pos_gen(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    output wire        O_de,       // 与 O_x/O_y 同拍的有效指示
    output reg  [9:0]  O_x,        // 有效区 x: 0..639
    output reg  [8:0]  O_y,        // 有效区 y: 0..479
    output reg  [31:0] O_frame_cnt
);

    reg        de_d;
    reg [31:0] line_cnt;

    reg  vs_d;
    wire vs_rise_w = I_vs & ~vs_d;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d        <= 1'b0;
            vs_d        <= 1'b0;
            O_x         <= 10'd0;
            O_y         <= 9'd0;
            line_cnt    <= 32'd0;
            O_frame_cnt <= 32'd0;
        end else begin
            de_d <= I_de;
            vs_d <= I_vs;

            if (vs_rise_w) begin
                line_cnt    <= 32'd0;
                O_frame_cnt <= O_frame_cnt + 32'd1;
            end

            if (I_de && !de_d) begin          // de 上升沿（在本拍锁存，下一拍与 O_de 同现）
                O_x      <= 10'd0;
                O_y      <= line_cnt[8:0];
                line_cnt <= line_cnt + 32'd1;
            end else if (I_de) begin
                O_x <= O_x + 10'd1;
            end
        end
    end

    assign O_de = de_d;

endmodule
