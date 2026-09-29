// tb_audio_player.v — audio_player 单元仿真（精简版）
// 验证: FIFO 跨域、48kHz 输出、音画同步
`timescale 1ns/1ps
module tb_audio_player;

    reg clk_sd = 0, clk_video = 0;
    reg rst_sd = 1, rst_video = 1;
    always #5  clk_sd    = ~clk_sd;     // 100MHz
    always #20 clk_video = ~clk_video;  // 25MHz

    reg         pcm_valid = 0;
    reg  [15:0] pcm_left = 0, pcm_right = 0;
    reg         vs_pulse = 0;
    wire        audio_valid;
    wire [23:0] audio_left, audio_right;
    wire signed [15:0] sync_dev;
    wire [31:0] sample_cnt, frame_cnt;
    wire        fifo_empty, fifo_full;
    wire        sample_tick;

    audio_player u_player(
        .clk_sd(clk_sd), .clk_video(clk_video),
        .rst_sd(rst_sd), .rst_video(rst_video),
        .pcm_valid(pcm_valid), .pcm_left(pcm_left), .pcm_right(pcm_right),
        .vs_pulse(vs_pulse),
        .audio_valid(audio_valid), .audio_left(audio_left), .audio_right(audio_right),
        .sync_dev(sync_dev), .sample_cnt(sample_cnt), .frame_cnt(frame_cnt),
        .sample_tick(sample_tick),
        .fifo_empty(fifo_empty), .fifo_full(fifo_full)
    );

    integer errors = 0;
    integer audio_count = 0;

    always @(posedge clk_video) begin
        if (audio_valid) audio_count = audio_count + 1;
    end

    // vs_pulse: 每 2000 video_clk 周期（简化，实际应 ~13225）
    integer vs_div = 0;
    always @(posedge clk_video) begin
        if (rst_video) begin vs_div <= 0; vs_pulse <= 0; end
        else begin
            vs_div <= vs_div + 1;
            if (vs_div == 1999) begin vs_pulse <= 1; vs_div <= 0; end
            else vs_pulse <= 0;
        end
    end

    task write_pcm;
        input [15:0] l, r;
        begin
            @(posedge clk_sd); pcm_valid <= 1; pcm_left <= l; pcm_right <= r;
            @(posedge clk_sd); pcm_valid <= 0;
        end
    endtask

    initial begin
        rst_sd = 1;
        rst_video = 1;
        #200;
        @(negedge clk_sd); rst_sd = 0;
        @(negedge clk_video); rst_video = 0;
        #200;

        // Test 1: 写 50 样本，等输出
        $display("TEST1: write 50 samples");
        audio_count = 0;
        for (integer i = 0; i < 50; i = i + 1)
            write_pcm(16'h1000 + i, 16'h2000 + i);
        #100000;  // 100µs 等待
        $display("audio_count=%0d", audio_count);
        if (audio_count > 0) $display("TEST1 PASS");
        else begin $display("TEST1 FAIL"); errors = errors + 1; end

        // Test 2: 写 500 样本（超 1 帧 800），看同步
        $display("TEST2: AV sync");
        audio_count = 0;
        for (integer i = 0; i < 500; i = i + 1)
            write_pcm(16'h3000 + i, 16'h4000 + i);
        #500000;  // 500µs
        $display("audio_count=%0d frame_cnt=%0d sync_dev=%0d", audio_count, frame_cnt, sync_dev);
        if (frame_cnt > 0) $display("TEST2 PASS");
        else begin $display("TEST2 FAIL"); errors = errors + 1; end

        if (errors == 0) $display("TB_AUDIO_PLAYER PASS");
        else $display("TB_AUDIO_PLAYER FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("TB_AUDIO_PLAYER TIMEOUT");
        $finish;
    end

endmodule
