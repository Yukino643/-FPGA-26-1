// 参考老师第十二讲 promax_audio_waveform.v：抽取、32点双缓冲、帧边界交换。
// 采集窗口跨视频帧保持，避免 32 点只覆盖几毫秒导致波形快速扫动。
// 适配当前链路的正极性 VS 事件和显式 y 坐标；相邻样本之间做定点线性插值，
// 避免每个采样点保持一段水平矩形造成台阶状波形。
module promax_audio_waveform #(
    parameter integer WAVE_X = 64,
    parameter integer WAVE_Y = 384,
    parameter integer WAVE_WIDTH = 512,
    parameter integer WAVE_HEIGHT = 64,
    parameter integer DECIMATE = 12
)(
    input wire clk, rst, vs_pulse, de, enable,
    input wire [9:0] pixel_x,
    input wire [8:0] pixel_y,
    input wire [23:0] rgb_in,
    input wire pcm_tap_valid,
    input wire signed [15:0] pcm_tap_left,
    output wire [23:0] rgb_out,
    output wire waveform_active
);
    localparam integer SAMPLE_COUNT = 32;
    localparam integer SAMPLE_SPACING = WAVE_WIDTH / SAMPLE_COUNT;
    localparam integer CENTER_Y = WAVE_Y + WAVE_HEIGHT/2;
    localparam integer SAMPLE_BITS = 10;
    localparam integer MAX_OFFSET = WAVE_HEIGHT/2 - 2;
    reg signed [7:0] sample_bank0 [0:31];
    reg signed [7:0] sample_bank1 [0:31];
    reg write_bank, display_bank, display_valid;
    reg [5:0] capture_count;
    reg [7:0] decimate_count;
    reg [7:0] peak_bank0, peak_bank1, display_peak;
    wire [7:0] sample_abs = pcm_tap_left[15] ?
                            (~pcm_tap_left[15:8] + 1'b1) : pcm_tap_left[15:8];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_bank <= 0; display_bank <= 1; display_valid <= 0;
            capture_count <= 0; decimate_count <= 0;
            peak_bank0 <= 0; peak_bank1 <= 0; display_peak <= 0;
        end else if (vs_pulse) begin
            // 仅完整的 32 点采样组可在帧边界发布；未采满时保留采集状态跨帧继续。
            if (capture_count == SAMPLE_COUNT) begin
                display_bank <= write_bank;
                display_valid <= 1;
                display_peak <= write_bank ? peak_bank1 : peak_bank0;
                write_bank <= ~write_bank;
                capture_count <= 0;
                decimate_count <= 0;
                // 清理下一组将写入 bank 的峰值累积器。
                if (write_bank) peak_bank0 <= 0;
                else peak_bank1 <= 0;
            end
        end else if (pcm_tap_valid && capture_count < SAMPLE_COUNT) begin
            if (decimate_count == 0) begin
                if (write_bank) sample_bank1[capture_count[4:0]] <= pcm_tap_left[15:8];
                else sample_bank0[capture_count[4:0]] <= pcm_tap_left[15:8];
                capture_count <= capture_count + 1'b1;
                decimate_count <= DECIMATE-1;
                if (write_bank) begin
                    if (sample_abs > peak_bank1) peak_bank1 <= sample_abs;
                end else begin
                    if (sample_abs > peak_bank0) peak_bank0 <= sample_abs;
                end
            end else decimate_count <= decimate_count - 1'b1;
        end
    end

    wire in_wave = enable && de && pixel_x >= WAVE_X && pixel_x < WAVE_X+WAVE_WIDTH
                   && pixel_y >= WAVE_Y && pixel_y < WAVE_Y+WAVE_HEIGHT;
    wire in_wave_x = pixel_x >= WAVE_X && pixel_x < WAVE_X+WAVE_WIDTH;
    // 窗口外固定访问 0 号点，避免坐标减法回绕后产生无效 RAM 索引。
    wire [9:0] local_x = in_wave_x ? pixel_x - WAVE_X : 10'd0;
    wire [4:0] sample_index = local_x / SAMPLE_SPACING;
    wire [4:0] next_index = (sample_index == SAMPLE_COUNT-1) ? sample_index : sample_index + 1'b1;
    wire [9:0] sample_remainder = local_x % SAMPLE_SPACING;
    wire signed [10:0] sample_frac = $signed({1'b0, sample_remainder});
    wire signed [7:0] selected_sample = !display_valid ? 8'sd0 :
                                        display_bank ? sample_bank1[sample_index] : sample_bank0[sample_index];
    wire signed [7:0] next_sample = !display_valid ? 8'sd0 :
                                    display_bank ? sample_bank1[next_index] : sample_bank0[next_index];
    wire signed [SAMPLE_BITS-1:0] sample_ext = {{2{selected_sample[7]}}, selected_sample};
    wire signed [SAMPLE_BITS-1:0] next_ext = {{2{next_sample[7]}}, next_sample};
    // 和老师例程一样使用有符号除法；负值向零取整，不用算术移位改变曲线偏置。
    // 提高显示增益；输出窗口保留两像素边距并对超范围样本饱和裁剪。
    wire signed [SAMPLE_BITS-1:0] offset_raw = sample_ext / 2;
    wire signed [SAMPLE_BITS-1:0] next_offset_raw = next_ext / 2;
    // 负满幅 -128 也保留两像素边距，避免曲线越出窗口盖住右下时钟。
    wire signed [SAMPLE_BITS-1:0] offset_clipped = (offset_raw > MAX_OFFSET) ? MAX_OFFSET :
                                        (offset_raw < -MAX_OFFSET) ? -MAX_OFFSET : offset_raw;
    wire signed [SAMPLE_BITS-1:0] next_offset_clipped = (next_offset_raw > MAX_OFFSET) ? MAX_OFFSET :
                                             (next_offset_raw < -MAX_OFFSET) ? -MAX_OFFSET : next_offset_raw;
    // 全部乘除操作数显式有符号；分数保留坐标位宽，不能按默认步长截短。
    // 多计算下一列的端点，以两列间线段范围补齐陡坡；末点保持自身避免右边界回跳。
    wire signed [SAMPLE_BITS:0] offset_delta = next_offset_clipped - offset_clipped;
    wire signed [21:0] offset_product = offset_delta * sample_frac;
    wire signed [10:0] following_frac = sample_frac + 11'sd1;
    wire signed [21:0] following_product = offset_delta * following_frac;
    wire signed [SAMPLE_BITS:0] offset_interp = offset_clipped + offset_product / SAMPLE_SPACING;
    wire signed [SAMPLE_BITS:0] following_interp = offset_clipped + following_product / SAMPLE_SPACING;
    wire signed [15:0] sample_y = CENTER_Y - offset_interp;
    wire signed [15:0] following_y = CENTER_Y - following_interp;
    wire signed [15:0] line_top = (sample_y < following_y) ? sample_y : following_y;
    wire signed [15:0] line_bottom = (sample_y > following_y) ? sample_y : following_y;
    wire signed [15:0] pixel_y_signed = $signed({1'b0, pixel_y});
    wire wave_pixel = in_wave && display_valid &&
                      pixel_y_signed >= line_top-16'sd1 && pixel_y_signed <= line_bottom+16'sd1;
    wire axis_pixel = in_wave && (pixel_y == CENTER_Y);
    wire [7:0] peak_height = display_peak >> 2;
    wire peak_pixel = enable && de &&
                      pixel_x >= WAVE_X+WAVE_WIDTH+8 &&
                      pixel_x < WAVE_X+WAVE_WIDTH+16 &&
                      pixel_y >= WAVE_Y+WAVE_HEIGHT-peak_height &&
                      pixel_y < WAVE_Y+WAVE_HEIGHT;
    assign waveform_active = wave_pixel || peak_pixel || axis_pixel;
    // 主图显示时域波形；右侧窄条只表示老师例程中的单点峰值，不是频谱柱。
    assign rgb_out = wave_pixel ? 24'h20FF90 :
                     peak_pixel ? 24'hFFB020 :
                     axis_pixel ? 24'h406060 : rgb_in;

    // synthesis translate_off
    initial begin
        if (WAVE_WIDTH < SAMPLE_COUNT || WAVE_WIDTH % SAMPLE_COUNT != 0 ||
            WAVE_X < 0 || WAVE_X+WAVE_WIDTH > 640 || WAVE_HEIGHT < 4 ||
            WAVE_Y < 0 || WAVE_Y+WAVE_HEIGHT > 480 || DECIMATE < 1 || DECIMATE > 256)
            $fatal(1, "Invalid waveform geometry or decimation");
    end
    // synthesis translate_on
endmodule
