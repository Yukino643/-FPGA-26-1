// 参考老师第十讲：只在完整帧边界执行直切、淡出到黑/淡入或方向揭示。
// commit_toggle 是已同步的单拍事件；commit_buf 在事件前必须稳定。
module transition_ctrl #(
    parameter [20:0] PAGE0_BASE = 21'h0_0000,
    parameter [20:0] PAGE1_BASE = 21'h8_0000,
    parameter [7:0] ALPHA_STEP = 8'd16,
    parameter [9:0] SOFT_EDGE = 10'd16
)(
    input wire clk, rst, vs_rise,
    input wire [9:0] x,
    input wire [8:0] y,
    input wire commit_toggle,
    input wire [1:0] commit_buf, tr_mode,
    output reg tr_active,
    output reg [7:0] alpha,
    output reg [9:0] boundary,
    output reg [1:0] slide_axis,
    output wire [20:0] page_a_base, page_b_base,
    output reg page_upd_a, page_upd_b, hold_load,
    output wire fade_black
);
    localparam S_IDLE=3'd0, S_OUT=3'd1, S_BLACK=3'd2,
               S_IN=3'd3, S_SLIDE=3'd4, S_SETTLE=3'd5;
    reg [2:0] state;
    reg [1:0] cur_buf, pend_buf, mode_pending;
    reg commit_pend;
    wire [8:0] alpha_sum = {1'b0, alpha} + {1'b0, ALPHA_STEP};
    wire [9:0] slide_limit = (slide_axis == 2'd2) ? 10'd480 : 10'd640;

    assign page_a_base = cur_buf[0] ? PAGE1_BASE : PAGE0_BASE;
    assign page_b_base = pend_buf[0] ? PAGE1_BASE : PAGE0_BASE;
    assign fade_black = (state == S_OUT || state == S_BLACK || state == S_IN);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            cur_buf <= 0; pend_buf <= 1; mode_pending <= 0;
            commit_pend <= 0;
            tr_active <= 0; alpha <= 255; boundary <= 0; slide_axis <= 0;
            page_upd_a <= 0; page_upd_b <= 0; hold_load <= 0;
        end else begin
            page_upd_a <= 0;
            page_upd_b <= 0;
            if (commit_toggle && state == S_IDLE && !commit_pend) begin
                pend_buf <= commit_buf;
                mode_pending <= tr_mode;
                commit_pend <= 1;
                hold_load <= 1;
            end
            // 帧中只接收事件；所有可见输出及页地址在消隐起始更新。
            if (vs_rise) begin
                case (state)
                    S_IDLE: if (commit_pend) begin
                        if (pend_buf == cur_buf || mode_pending == 0) begin
                            cur_buf <= pend_buf;
                            page_upd_a <= 1;
                            commit_pend <= 0;
                            hold_load <= 0;
                        end else if (mode_pending == 1) begin
                            state <= S_OUT;
                            tr_active <= 1;
                            alpha <= 255;
                        end else begin
                            state <= S_SLIDE;
                            tr_active <= 1;
                            slide_axis <= (mode_pending == 3) ? 2 : 1;
                            boundary <= 0;
                            alpha <= 0;
                            page_upd_b <= 1;
                        end
                    end
                    S_OUT: begin
                        if (alpha <= ALPHA_STEP) begin
                            alpha <= 0;
                            cur_buf <= pend_buf;
                            page_upd_a <= 1;
                            state <= S_BLACK;
                        end else alpha <= alpha - ALPHA_STEP;
                    end
                    // 换页后保持一帧全黑，让预取引擎从新页首字开始。
                    S_BLACK: begin state <= S_IN; alpha <= 0; end
                    S_IN: begin
                        // 9 位饱和加法：禁止满亮时从 255 回绕到旧图/黑屏。
                        if (alpha_sum >= 255) begin
                            alpha <= 255;
                            state <= S_IDLE;
                            tr_active <= 0;
                            commit_pend <= 0;
                            hold_load <= 0;
                        end else alpha <= alpha_sum[7:0];
                    end
                    S_SLIDE: begin
                        if (boundary + 10'd32 >= slide_limit) begin
                            cur_buf <= pend_buf;
                            page_upd_a <= 1;
                            slide_axis <= 0;
                            alpha <= 255;
                            state <= S_SETTLE;
                        end else boundary <= boundary + 10'd32;
                    end
                    // 此帧只输出目标 B 页；下一帧 A 预取数据已对应目标页。
                    S_SETTLE: begin
                        state <= S_IDLE;
                        tr_active <= 0;
                        commit_pend <= 0;
                        hold_load <= 0;
                    end
                    default: begin
                        state <= S_IDLE; tr_active <= 0;
                        commit_pend <= 0; hold_load <= 0;
                    end
                endcase
            end
        end
    end
endmodule
