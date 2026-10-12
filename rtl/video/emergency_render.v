// emergency_render.v — W9: 应急模式渲染器
//
// 高对比红底 #C00000 + 白字警示标题 + 黄字滚动告警条
// 纯组合逻辑 + 字库 ROM，不访问 SDRAM
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
    reg [9:0] scroll_off = 10'd0;
    reg       vs_d;
    always @(posedge clk) begin
        vs_d <= de_in;  // 简化: 用 de 下降沿当帧边界
        if (de_in && !vs_d)  // de 上升沿 = 新行开始
            scroll_off <= scroll_off + 10'd2;
    end

    // 标题区域: y∈[180,220]，居中显示 "紧急疏散"
    wire in_title = (y >= 9'd180) && (y <= 9'd219);
    // 告警条: y∈[280,300]，滚动
    wire in_warn  = (y >= 9'd280) && (y <= 9'd299);

    // 简化文字渲染（用色块模拟，实际应接字库 ROM）
    wire [23:0] title_color = in_title ? EMG_TITLE : EMG_BG;
    wire [23:0] warn_color  = in_warn  ? EMG_WARN  : title_color;

    // 告警条滚动效果（水平条纹）
    wire [9:0] warn_x = (x + scroll_off) % 10'd40;
    wire       warn_stripe = in_warn && (warn_x < 10'd20);
    wire [23:0] warn_final = warn_stripe ? EMG_WARN : EMG_BG;

    // 最终输出
    wire [23:0] emg_rgb = in_warn ? warn_final :
                          in_title ? EMG_TITLE :
                          EMG_BG;

    assign rgb_out = emergency_mode ? emg_rgb : normal_rgb;

endmodule
