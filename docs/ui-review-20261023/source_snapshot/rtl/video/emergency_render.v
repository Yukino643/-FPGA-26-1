// emergency_render.v — W9: 应急模式渲染器
//
// 高对比红底 + 白色标题占位条 + 黄色滚动警示条，不访问 SDRAM。
// 当前标题仍为色块，尚未接入应急文字字库。
module emergency_render #(parameter X_BITS=10, Y_BITS=9)(
    input  wire        clk,
    input  wire        de_in,
    input  wire [X_BITS-1:0] x,
    input  wire [Y_BITS-1:0] y,
    input  wire        emergency_mode,
    input  wire [23:0] normal_rgb,     // 正常模式输出
    output wire [23:0] rgb_out
);

    // 应急配色
    localparam [23:0] EMG_BG    = 24'hC00000;  // 深红底
    localparam [23:0] EMG_TITLE = 24'hFFFFFF;  // 白色标题
    localparam [23:0] EMG_WARN  = 24'hFFDD00;  // 黄色告警

    // 滚动偏移（每帧 +2px）
    reg [4:0] scroll_off = 5'd0;
    reg       origin_d = 1'b0;
    wire frame_origin = de_in && (x == 0) && (y == 0);
    always @(posedge clk) begin
        // 坐标和 DE 已处于相同流水级。只在帧首推进一次，禁止逐行移动。
        origin_d <= frame_origin;
        if (frame_origin && !origin_d)
            scroll_off <= scroll_off + 5'd2;
    end

    // 标题区域: y∈[180,220]，居中显示 "紧急疏散"
    wire in_title = (y >= 9'd180) && (y <= 9'd219);
    // 告警条: y∈[280,300]，滚动
    wire in_warn  = (y >= 9'd280) && (y <= 9'd299);

    // 32 像素周期仅需低位加法，不引入逐像素除法器；720p 全宽均可覆盖。
    wire [4:0] warn_x = x[4:0] + scroll_off;
    wire       warn_stripe = in_warn && !warn_x[4];
    wire [23:0] warn_final = warn_stripe ? EMG_WARN : EMG_BG;

    // 最终输出
    wire [23:0] emg_rgb = in_warn ? warn_final :
                          in_title ? EMG_TITLE :
                          EMG_BG;

    assign rgb_out = emergency_mode ? emg_rgb : normal_rgb;

endmodule
