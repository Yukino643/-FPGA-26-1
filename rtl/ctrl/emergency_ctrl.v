// emergency_ctrl.v — KEY4 长按模式请求与蜂鸣器控制
// 本模块只在 clk 所属控制域检测按键。模式真正生效由上层在 video 帧边界提交。
module emergency_ctrl #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer LONG_PRESS_MS = 2000,
    parameter integer DEBOUNCE_CYCLES = 999_999
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        key4,
    input  wire        mode_active,
    output reg         emergency_request,
    output reg         buzzer_on
);
    localparam integer LONG_PRESS_CNT = LONG_PRESS_MS * (CLK_FREQ_HZ / 1000);

    reg key4_meta, key4_sync, key4_debounced;
    reg [31:0] debounce_cnt;
    reg [31:0] press_cnt;
    reg        press_armed;
    reg [26:0] buzzer_cnt;

    // 两级输入同步 + 稳定计数消抖。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key4_meta      <= 1'b1;
            key4_sync      <= 1'b1;
            key4_debounced <= 1'b1;
            debounce_cnt   <= 32'd0;
        end else begin
            key4_meta <= key4;
            key4_sync <= key4_meta;
            if (key4_sync != key4_debounced) begin
                if (debounce_cnt >= DEBOUNCE_CYCLES) begin
                    key4_debounced <= key4_sync;
                    debounce_cnt   <= 32'd0;
                end else begin
                    debounce_cnt <= debounce_cnt + 32'd1;
                end
            end else begin
                debounce_cnt <= 32'd0;
            end
        end
    end

    // 每次按下只允许产生一个翻转请求；松开后重新 arm。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            press_cnt         <= 32'd0;
            press_armed       <= 1'b1;
            emergency_request <= 1'b0;
        end else if (!key4_debounced) begin
            if (press_armed && press_cnt >= LONG_PRESS_CNT - 1) begin
                emergency_request <= ~emergency_request;
                press_armed       <= 1'b0;
                press_cnt         <= 32'd0;
            end else if (press_armed) begin
                press_cnt <= press_cnt + 32'd1;
            end
        end else begin
            press_cnt   <= 32'd0;
            press_armed <= 1'b1;
        end
    end

    // 蜂鸣器只跟随已经在视频帧边界提交并同步回来的模式。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            buzzer_cnt <= 27'd0;
            buzzer_on  <= 1'b0;
        end else if (mode_active) begin
            buzzer_cnt <= buzzer_cnt + 27'd1;
            buzzer_on  <= buzzer_cnt[26];
        end else begin
            buzzer_cnt <= 27'd0;
            buzzer_on  <= 1'b0;
        end
    end
endmodule
