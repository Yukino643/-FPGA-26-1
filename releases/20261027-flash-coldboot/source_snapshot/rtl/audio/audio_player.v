// audio_player.v — PCM FIFO、精确 48kHz 节拍与音视频同步观测
// 输入 PCM 位于 clk_sd 域，输出 HDMI 音频样本位于 clk_video 域。
module audio_player #(
    parameter integer VIDEO_CLK_HZ   = 25_000_000,
    parameter integer SAMPLE_RATE_HZ = 48_000,
    parameter integer NOMINAL_SAMPLES_PER_FRAME = 806,
    parameter CONTROL_ENABLE=0
)(
    input  wire        clk_sd,
    input  wire        clk_video,
    input  wire        rst_sd,
    input  wire        rst_video,
    input wire fifo_rst_sd, fifo_rst_video,
    input wire consume_enable, frame_mode, frame_start,
    output wire frame_done, buffer_ready,
    input  wire        pcm_valid,
    input  wire [15:0] pcm_left,
    input  wire [15:0] pcm_right,
    input  wire        vs_pulse,
    output reg         audio_valid,
    output reg         sample_data_valid,
    output reg  [23:0] audio_left,
    output reg  [23:0] audio_right,
    output reg signed [15:0] sync_dev,
    output reg  [31:0] sample_cnt,
    output reg  [31:0] frame_cnt,
    output wire        sample_tick,
    output wire        fifo_empty,
    output wire        fifo_full
);

    wire        fifo_rd_en;
    wire [31:0] fifo_rd_data;
    wire        fifo_rd_empty;
    wire [9:0] fifo_level;
    wire flush_sd=rst_sd | (CONTROL_ENABLE && fifo_rst_sd);
    wire flush_video=rst_video | (CONTROL_ENABLE && fifo_rst_video);
    reg [12:0] frame_samples;
    reg frame_running;
    // 最后一个旧帧样本恰与VS同拍时也可提交，不能多等一整个60Hz帧。
    // 此表达式不反向控制rd_en，避免组合环；frame_start同拍消费的仍是旧帧末样本。
    assign frame_done=(frame_samples>=13'd4800) ||
        (frame_samples==13'd4799 && fifo_rd_en);
    assign buffer_ready=fifo_level>=10'd256;
    wire [31:0] fifo_wr_data = {pcm_right, pcm_left};
    wire        fifo_wr_en   = pcm_valid && !fifo_full;

    afifo_simple #(.DW(32), .AW(9)) u_audio_fifo(
        .wr_clk  (clk_sd), .wr_rst(flush_sd), .wr_en(fifo_wr_en),
        .wr_data (fifo_wr_data), .wr_full(fifo_full), .wr_usedw(),
        .rd_clk  (clk_video), .rd_rst(flush_video), .rd_en(fifo_rd_en),
        .rd_data (fifo_rd_data), .rd_empty(fifo_rd_empty), .rd_usedw(fifo_level)
    );
    assign fifo_empty = fifo_rd_empty;

    // 采用分数累加器而不是整数 525 分频：平均频率严格为 48kHz。
    reg [31:0] sample_phase;
    wire [32:0] sample_phase_sum = {1'b0, sample_phase} + SAMPLE_RATE_HZ;
    assign sample_tick = (sample_phase_sum >= VIDEO_CLK_HZ);

    always @(posedge clk_video or posedge rst_video) begin
        if (rst_video)
            sample_phase <= 32'd0;
        else if (sample_tick)
            sample_phase <= sample_phase_sum - VIDEO_CLK_HZ;
        else
            sample_phase <= sample_phase_sum[31:0];
    end

    // 25MHz 下 640x480@800x525 的相邻帧样本数为 806/807 交替。
    // tick 与视频同源，不允许监视算法反向修改采样时基。
    // 720p60 配置为每帧800样本。
    reg [15:0] samples_in_frame;
    assign fifo_rd_en = sample_tick && !fifo_rd_empty && !flush_video &&
        (!CONTROL_ENABLE || (consume_enable &&
         (!frame_mode || (frame_running && frame_samples<13'd4800))));
    // 只对真正出FIFO的样本计数；停顿和欠载不会推进音轨位置。
    always @(posedge clk_video or posedge flush_video) begin
        if(flush_video) begin frame_samples<=0;frame_running<=0;end
        else if(frame_start) begin frame_samples<=0;frame_running<=1;end
        else if(fifo_rd_en && frame_mode) frame_samples<=frame_samples+1'b1;
    end

    always @(posedge clk_video or posedge rst_video) begin
        if (rst_video) begin
            samples_in_frame <= 16'd0;
            sample_cnt       <= 32'd0;
            frame_cnt        <= 32'd0;
            sync_dev         <= 16'sd0;
            audio_valid      <= 1'b0;
            sample_data_valid <= 1'b0;
            audio_left       <= 24'd0;
            audio_right      <= 24'd0;
        end else begin
            audio_valid <= 1'b0;
            sample_data_valid <= 1'b0;

            if (vs_pulse) begin
                frame_cnt        <= frame_cnt + 32'd1;
                sync_dev         <= $signed({1'b0, samples_in_frame}) - NOMINAL_SAMPLES_PER_FRAME;
                samples_in_frame <= 16'd0;
            end

            if (sample_tick) begin
                audio_valid      <= 1'b1;
                sample_cnt       <= sample_cnt + 32'd1;
                // VS同拍的sample属于新帧，禁止覆盖VS清零并累积旧帧。
                samples_in_frame <= vs_pulse ? 16'd1 : samples_in_frame + 16'd1;
                if (fifo_rd_en) begin
                    sample_data_valid <= 1'b1;
                    audio_left  <= {fifo_rd_data[15:0], 8'd0};
                    audio_right <= {fifo_rd_data[31:16], 8'd0};
                end else begin
                    // SD/WAV 暂时没有样本时仍维持 HDMI 音频包节拍，输出静音。
                    audio_left  <= 24'd0;
                    audio_right <= 24'd0;
                end
            end
        end
    end
endmodule
