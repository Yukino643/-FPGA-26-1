// 参考老师第十讲 frame_blend：双页淡化、横向推移及纵向揭示只在 VS 推进。
// commit_toggle 是已同步的单拍事件；commit_buf 在事件前必须稳定。
module transition_ctrl #(
    parameter [20:0] PAGE0_BASE = 21'h0_0000,
    parameter [20:0] PAGE1_BASE = 21'h8_0000,
    parameter [7:0] ALPHA_STEP = 8'd8,
    parameter [9:0] SLIDE_STEP = 10'd16,
    parameter X_BITS=10, Y_BITS=9
)(
    input wire clk, rst, vs_rise,
    input wire [X_BITS-1:0] x,
    input wire [Y_BITS-1:0] y,
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
    localparam S_IDLE=2'd0, S_BLEND=2'd1, S_SLIDE=2'd2, S_SETTLE=2'd3;
    reg [1:0] state;
    reg [1:0] cur_buf, pend_buf, mode_pending;
    reg commit_pend;
    wire [8:0] alpha_sum = {1'b0, alpha} + {1'b0, ALPHA_STEP};
    wire [10:0] slide_sum = {1'b0, boundary} + {1'b0, SLIDE_STEP};
    wire [9:0] slide_limit = (slide_axis == 2'd2) ? 10'd480 : 10'd640;

    assign page_a_base = cur_buf[0] ? PAGE1_BASE : PAGE0_BASE;
    assign page_b_base = pend_buf[0] ? PAGE1_BASE : PAGE0_BASE;
    assign fade_black = 1'b0;

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
                            // 老师 frame_blend 的双页交叉淡化；目标页先预取，
                            // alpha 在完整帧边界从 0 饱和递增到 255，不插入黑场。
                            state <= S_BLEND;
                            tr_active <= 1;
                            alpha <= 0;
                            page_upd_b <= 1;
                        end else begin
                            state <= S_SLIDE;
                            tr_active <= 1;
                            slide_axis <= (mode_pending == 3) ? 2 : 1;
                            boundary <= 0;
                            alpha <= 0;
                            page_upd_b <= 1;
                        end
                    end
                    S_SLIDE: begin
                        if (slide_sum >= {1'b0, slide_limit}) begin
                            cur_buf <= pend_buf;
                            page_upd_a <= 1;
                            boundary <= 0;
                            slide_axis <= 0;
                            alpha <= 255;
                            state <= S_SETTLE;
                        end else boundary <= slide_sum[9:0];
                    end
                    S_BLEND: begin
                        if (alpha_sum >= 255) begin
                            alpha <= 255;
                            cur_buf <= pend_buf;
                            page_upd_a <= 1;
                            state <= S_SETTLE;
                        end else alpha <= alpha_sum[7:0];
                    end
                    // 此帧只输出目标 B 页；下一帧 A 预取已对应目标页，才释放装载。
                    S_SETTLE: begin
                        state <= S_IDLE;
                        tr_active <= 0;
                        commit_pend <= 0;
                        hold_load <= 0;
                    end
                    default: begin
                        state <= S_IDLE; tr_active <= 0; alpha <= 255;
                        boundary <= 0; slide_axis <= 0;
                        commit_pend <= 0; hold_load <= 0;
                    end
                endcase
            end
        end
    end
    // synthesis translate_off
    initial if (ALPHA_STEP == 0 || SLIDE_STEP == 0 || SLIDE_STEP > 640)
        $fatal(1, "Invalid transition step");
    // synthesis translate_on
endmodule
