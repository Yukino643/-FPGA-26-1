// transition_ctrl.v — 转场控制状态机（video_clk 域，计划书 5.2.4）
// 模式: 0=直切 1=淡入淡出(32帧) 2=滑动左(8px软边) 3=滑动上
// 提交协议: 装载器完成 toggle(video域已同步) → 捕获目标页 → 下一个帧起始进入转场
//           → 逐帧推进 α/边界 → 结束时提交 disp 页并撤销 hold_load
// 页选通仅发生在帧起始（vs 上升沿），显示读出恒取当前页 —— 无撕裂页翻转
module transition_ctrl #(
    parameter [20:0] PAGE0_BASE = 21'h0_0000,   // mem_map: bank0 钉扎
    parameter [20:0] PAGE1_BASE = 21'h8_0000,   // mem_map: bank1 钉扎
    parameter [7:0]  ALPHA_STEP = 8'd8,         // 每帧 α 步进 (32 帧淡入淡出)
    parameter [9:0]  SOFT_EDGE  = 10'd16        // 滑动软边宽（像素）
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        vs_rise,          // 帧起始
    input  wire [9:0]  x,                // 有效区坐标（滑动边界判定）
    input  wire [8:0]  y,

    // 装载器提交（video 域同步后的脉冲 + 目标缓冲号，准静态）
    input  wire        commit_toggle,
    input  wire [1:0]  commit_buf,       // 0/1 → PAGE0/PAGE1

    input  wire [1:0]  tr_mode,          // 转场样式

    // 给混合器/引擎
    output reg         tr_active,        // B 流使能
    output reg  [7:0]  alpha,            // B 权重（FADE 全屏；SLIDE 为软边内插值）
    output reg  [9:0]  boundary,         // 滑动边界（x 或 y）
    output reg  [1:0]  slide_axis,       // 0:无 1:左(按x) 2:上(按y)
    output wire [20:0] page_a_base,      // 当前显示页（读引擎 A）
    output wire [20:0] page_b_base,      // 转场目标页（读引擎 B）
    output reg         page_upd_a,       // 页基址更新脉冲（给引擎 A，1 拍）
    output reg         page_upd_b,
    // 给装载器
    output reg         hold_load         // 转场期间暂缓新装载
);

    reg [1:0]  cur_buf;                   // 当前显示缓冲号
    reg [1:0]  pend_buf;                  // 转场目标缓冲号
    reg        commit_pend;               // 有待转场提交
    reg [8:0]  fade_cnt;                  // 已推进帧数（0..256/ALPHA_STEP）
    reg        settle;                    // 沉降期: 完成后再以 α=255 混一帧，
                                          // 把 A 引擎残留的旧页数据混掉后再切直通
    wire [20:0] base_of [0:3];
    assign base_of[0] = PAGE0_BASE;
    assign base_of[1] = PAGE1_BASE;
    assign base_of[2] = PAGE0_BASE;       // 2 位缓冲号只用 0/1
    assign base_of[3] = PAGE1_BASE;

    assign page_a_base = base_of[cur_buf];
    assign page_b_base = base_of[pend_buf];

    wire [8:0] fade_total = 9'd256 / ALPHA_STEP;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cur_buf     <= 2'd0;
            pend_buf    <= 2'd1;
            commit_pend <= 1'b0;
            tr_active   <= 1'b0;
            alpha       <= 8'd0;
            boundary    <= 10'd0;
            slide_axis  <= 2'd0;
            page_upd_a  <= 1'b0;
            page_upd_b  <= 1'b0;
            hold_load   <= 1'b0;
            fade_cnt    <= 9'd0;
            settle      <= 1'b0;
        end else begin
            page_upd_a <= 1'b0;
            page_upd_b <= 1'b0;

            // 装载完成: 记录待转场页
            if (commit_toggle && !tr_active) begin
                pend_buf    <= commit_buf;
                commit_pend <= 1'b1;
                hold_load   <= 1'b1;
            end

            if (vs_rise) begin
                if (!tr_active && commit_pend) begin
                    // 帧起始进入转场: B 引擎切到目标页，下帧起混合
                    tr_active  <= 1'b1;
                    fade_cnt   <= 9'd0;
                    alpha      <= 8'd0;
                    boundary   <= 10'd0;
                    slide_axis <= (tr_mode == 2'd2) ? 2'd1 :
                                  (tr_mode == 2'd3) ? 2'd2 : 2'd0;
                    page_upd_b <= 1'b1;
                end else if (tr_active && !settle) begin
                    // 帧起始推进转场
                    fade_cnt <= fade_cnt + 9'd1;
                    if (slide_axis == 2'd0) begin
                        alpha <= (fade_cnt >= fade_total) ? 8'd255 : alpha + ALPHA_STEP;
                    end else begin
                        boundary <= boundary + 10'd32;   // 每帧推进 32 像素
                    end
                end
            end

            // 转场完成判定（与推进同帧尾提交，下一帧起始生效）
            if (tr_active && vs_rise) begin
                if (settle) begin
                    // 沉降帧结束: 切直通
                    tr_active   <= 1'b0;
                    settle      <= 1'b0;
                    alpha       <= 8'd0;
                    commit_pend <= 1'b0;
                    hold_load   <= 1'b0;
                end else if ((slide_axis == 2'd0 && (fade_cnt >= fade_total)) ||
                             (slide_axis != 2'd0 && (boundary + 10'd32 >= 10'd640))) begin
                    cur_buf     <= pend_buf;
                    slide_axis  <= 2'd0;
                    boundary    <= 10'd0;
                    alpha       <= 8'd255;   // 沉降期 α=255（输出恒为新页内容）
                    settle      <= 1'b1;
                    page_upd_a  <= 1'b1;
                end
            end
        end
    end

endmodule
