// video_timing_gen.v — 参数化视频时序发生器（含有效区像素坐标计数）
// 输出 de 拉高期间 x/y 为有效区内坐标（0 基），hs/vs 为正极性脉冲
// （TMDS 发送核内部自带时序源，本模块极性只影响自家读出逻辑）
module video_timing_gen #(
    parameter integer HTOTAL  = 800,   // 640x480@60: 800
    parameter integer HSA     = 96,
    parameter integer HFP     = 16,
    parameter integer HBP     = 48,
    parameter integer HACTIVE = 640,
    parameter integer VTOTAL  = 525,   // 525
    parameter integer VSA     = 2,
    parameter integer VFP     = 10,
    parameter integer VBP     = 33,
    parameter integer VACTIVE = 480
)(
    input  wire        I_clk,
    input  wire        I_rst,
    output reg         O_hs,
    output reg         O_vs,
    output reg         O_de,
    output reg  [9:0]  O_x,    // 有效区 x: 0..HACTIVE-1
    output reg  [8:0]  O_y     // 有效区 y: 0..VACTIVE-1
);

    localparam integer H_SYNC_START = HFP + HACTIVE + HBP;
    localparam integer V_SYNC_START = VFP + VACTIVE + VBP;

    reg [10:0] S_xc;   // 0..HTOTAL-1
    reg [10:0] S_yc;   // 0..VTOTAL-1

    wire S_x_last = (S_xc == HTOTAL - 1);
    wire S_y_last = (S_yc == VTOTAL - 1);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            S_xc <= 11'd0;
            S_yc <= 11'd0;
        end else begin
            if (S_x_last) begin
                S_xc <= 11'd0;
                S_yc <= S_y_last ? 11'd0 : S_yc + 11'd1;
            end else begin
                S_xc <= S_xc + 11'd1;
            end
        end
    end

    // hs/vs: 同步脉冲期间为高；de: 有效显示期
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            O_hs <= 1'b0;
            O_vs <= 1'b0;
            O_de <= 1'b0;
            O_x  <= 10'd0;
            O_y  <= 9'd0;
        end else begin
            O_hs <= (S_xc >= H_SYNC_START) && (S_xc < H_SYNC_START + HSA);
            O_vs <= (S_yc >= V_SYNC_START) && (S_yc < V_SYNC_START + VSA);
            O_de <= (S_xc < HACTIVE) && (S_yc < VACTIVE);
            O_x  <= S_xc[9:0];
            O_y  <= S_yc[8:0];
        end
    end

endmodule
