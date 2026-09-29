// siren_gen.v — W9: 警笛音频发生器
//
// 频扫 400→1200Hz 锯齿波，帧边界无缝切换
// 输出: 24bit L/R @ 48kHz
module siren_gen(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,        // 应急模式使能
    input  wire        sample_tick,   // 48kHz 采样脉冲
    output reg         audio_valid,
    output reg  [23:0] audio_left,
    output reg  [23:0] audio_right
);

    // 相位累加器（DDS）
    reg [31:0] phase;
    reg [31:0] freq_step;     // 当前频率步进
    reg [31:0] sweep_cnt;     // 频扫计数器
    reg        sweep_dir;     // 0=升频, 1=降频

    // 频率范围: 400Hz ~ 1200Hz
    // freq_step = freq * 2^32 / 48000
    // 400Hz: 400 * 2^32 / 48000 ≈ 35,791,394
    // 1200Hz: 1200 * 2^32 / 48000 ≈ 107,374,182
    localparam [31:0] FREQ_LO  = 32'd35791394;   // 400Hz
    localparam [31:0] FREQ_HI  = 32'd107374182;  // 1200Hz
    localparam [31:0] FREQ_STEP_INC = 32'd100000;  // 频扫步进

    // 锯齿波查表（简化: 用相位高位直接输出）
    wire [7:0] saw_val = phase[31:24];  // 0~255

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            phase     <= 32'd0;
            freq_step <= FREQ_LO;
            sweep_cnt <= 32'd0;
            sweep_dir <= 1'b0;
            audio_valid <= 1'b0;
            audio_left  <= 24'd0;
            audio_right <= 24'd0;
        end else begin
            audio_valid <= 1'b0;

            if (enable && sample_tick) begin
                // 相位累加
                phase <= phase + freq_step;

                // 锯齿波输出（有符号，中心 0）
                audio_left   <= {saw_val, 16'd0} - 24'sd8388608;
                audio_right  <= {saw_val, 16'd0} - 24'sd8388608;
                audio_valid  <= 1'b1;

                // 频扫: 每 48000 样本（1 秒）扫一个来回
                sweep_cnt <= sweep_cnt + 32'd1;
                if (sweep_cnt >= 32'd47999) begin
                    sweep_cnt <= 32'd0;
                    if (!sweep_dir) begin
                        // 升频
                        if (freq_step >= FREQ_HI)
                            sweep_dir <= 1'b1;
                        else
                            freq_step <= freq_step + FREQ_STEP_INC;
                    end else begin
                        // 降频
                        if (freq_step <= FREQ_LO)
                            sweep_dir <= 1'b0;
                        else
                            freq_step <= freq_step - FREQ_STEP_INC;
                    end
                end
            end
        end
    end

endmodule
