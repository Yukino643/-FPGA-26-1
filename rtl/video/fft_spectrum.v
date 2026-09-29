// fft_spectrum.v — W8: 音频频谱分析（256 点 DFT → 32 bin 条形图）
//
// 输入: audio_player 的 48kHz 样本（video_clk 域）
// 输出: 32 个频段的幅度值（0~255），供 spectrum_layer 渲染
//
// 简化实现: 32 点 Goertzel 滤波器组（比完整 FFT 省资源）
// 每个 bin 对应一个频率: bin_k = k * 48000 / 256 ≈ k * 187.5Hz
// bin 0~31 覆盖 0~6kHz（人声/音乐主要频段）
module fft_spectrum(
    input  wire        clk,
    input  wire        rst,
    input  wire        audio_valid,
    input  wire [23:0] audio_left,
    input  wire [23:0] audio_right,
    // 频谱输出（32 bin × 8bit = 256bit 打包向量）
    output reg  [255:0] bin_magnitude,
    output reg         spectrum_ready
);

    // ---- 样本缓冲（256 点滑动窗口） ----
    reg signed [15:0] sample_buf [0:255];
    reg [7:0] wr_ptr;
    reg [8:0] sample_count;      // 累计样本数（用于触发计算）

    // L/R 均值
    wire signed [15:0] sample_avg = (audio_left[23:8] + audio_right[23:8]) >>> 1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 8'd0;
            sample_count <= 9'd0;
        end else if (audio_valid) begin
            sample_buf[wr_ptr] <= sample_avg;
            wr_ptr <= wr_ptr + 8'd1;
            if (sample_count < 9'd256)
                sample_count <= sample_count + 9'd1;
        end
    end

    // ---- Goertzel 滤波器组（32 bin） ----
    // 每个 bin 用一个二阶 IIR: y[n] = x[n] + 2*cos(w)*y[n-1] - y[n-2]
    // 完成 256 点后取 |y[255]| 作为幅度
    //
    // 为省资源，串行计算: 每个时钟处理 1 个 bin 的 1 个样本
    // 32 bin × 256 样本 = 8192 个时钟周期 ≈ 0.33ms @ 25MHz

    localparam NUM_BINS = 32;
    localparam BUF_LEN  = 256;

    // Goertzel 系数预计算: coeff[k] = 2*cos(2*pi*k/256)
    // 用定点 Q14 表示
    reg signed [15:0] coeff [0:31];
    initial begin
        // 2*cos(2*pi*k/256) for k=0..31, Q14 格式
        coeff[0]  = 16'sd16384;  // 2*cos(0) = 2.0
        coeff[1]  = 16'sd16374;  // 2*cos(2*pi/256)
        coeff[2]  = 16'sd16346;
        coeff[3]  = 16'sd16298;
        coeff[4]  = 16'sd16231;
        coeff[5]  = 16'sd16144;
        coeff[6]  = 16'sd16038;
        coeff[7]  = 16'sd15913;
        coeff[8]  = 16'sd15768;
        coeff[9]  = 16'sd15604;
        coeff[10] = 16'sd15422;
        coeff[11] = 16'sd15221;
        coeff[12] = 16'sd15001;
        coeff[13] = 16'sd14764;
        coeff[14] = 16'sd14509;
        coeff[15] = 16'sd14237;
        coeff[16] = 16'sd13948;
        coeff[17] = 16'sd13643;
        coeff[18] = 16'sd13322;
        coeff[19] = 16'sd12985;
        coeff[20] = 16'sd12633;
        coeff[21] = 16'sd12267;
        coeff[22] = 16'sd11887;
        coeff[23] = 16'sd11494;
        coeff[24] = 16'sd11088;
        coeff[25] = 16'sd10671;
        coeff[26] = 16'sd10241;
        coeff[27] = 16'sd9800;
        coeff[28] = 16'sd9348;
        coeff[29] = 16'sd8886;
        coeff[30] = 16'sd8414;
        coeff[31] = 16'sd7933;
    end

    // 计算状态机
    localparam S_IDLE  = 2'd0;
    localparam S_CALC  = 2'd1;
    localparam S_DONE  = 2'd2;

    reg [1:0]  state;
    reg [4:0]  bin_idx;          // 当前 bin (0~31)
    reg [8:0]  sample_idx;       // 当前样本 (0~255)
    reg signed [31:0] y1, y2;    // Goertzel 状态
    reg signed [31:0] mag_acc;   // 幅度累加

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= S_IDLE;
            bin_idx       <= 5'd0;
            sample_idx    <= 9'd0;
            y1            <= 32'sd0;
            y2            <= 32'sd0;
            mag_acc       <= 32'sd0;
            spectrum_ready<= 1'b0;
            bin_magnitude <= 256'd0;
        end else begin
            spectrum_ready <= 1'b0;

            case (state)
                S_IDLE: begin
                    // 样本缓冲满 256 后开始计算
                    if (sample_count >= 9'd256) begin
                        bin_idx    <= 5'd0;
                        sample_idx <= 9'd0;
                        y1         <= 32'sd0;
                        y2         <= 32'sd0;
                        state      <= S_CALC;
                    end
                end

                S_CALC: begin
                    // Goertzel 递推: y = x + coeff*y1 - y2
                    // 每拍处理 1 个样本
                    if (sample_idx < BUF_LEN) begin
                        // y_new = sample + (coeff * y1 >> 14) - y2
                        y2 <= y1;
                        y1 <= $signed(sample_buf[sample_idx[7:0]])
                              + ((coeff[bin_idx] * y1) >>> 14)
                              - y2;
                        sample_idx <= sample_idx + 9'd1;
                    end else begin
                        // 本 bin 计算完成，取 |y1| 作为幅度
                        // log2 近似压缩: mag = |y1| >> 10，clamp 0~255
                        mag_acc = y1[31] ? -y1 : y1;
                        bin_magnitude[bin_idx*8 +: 8] <= (mag_acc > 32'sd262143) ? 8'd255
                                                          : mag_acc[17:10];
                        // 下一个 bin
                        if (bin_idx == NUM_BINS - 1) begin
                            state         <= S_DONE;
                            spectrum_ready<= 1'b1;
                        end else begin
                            bin_idx    <= bin_idx + 5'd1;
                            sample_idx <= 9'd0;
                            y1         <= 32'sd0;
                            y2         <= 32'sd0;
                        end
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
