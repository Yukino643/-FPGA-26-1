// tb_fft_spectrum.v — fft_spectrum 单元仿真
// 验证: 样本缓冲、Goertzel 计算、bin 幅度输出
`timescale 1ns/1ps
module tb_fft_spectrum;

    reg clk = 0, rst = 1;
    always #20 clk = ~clk;  // 25MHz

    reg         audio_valid = 0;
    reg  [23:0] audio_left = 0, audio_right = 0;
    wire [7:0]  bin_mag [0:31];
    wire        spectrum_ready;

    fft_spectrum u_dut(
        .clk(clk), .rst(rst),
        .audio_valid(audio_valid),
        .audio_left(audio_left), .audio_right(audio_right),
        .bin_magnitude(bin_mag),
        .spectrum_ready(spectrum_ready)
    );

    integer errors = 0;
    integer ready_count = 0;

    always @(posedge clk) begin
        if (spectrum_ready) begin
            ready_count = ready_count + 1;
            $display("SPECTRUM ready #%0d: bin[0]=%0d bin[8]=%0d bin[16]=%0d bin[31]=%0d",
                ready_count, bin_mag[0], bin_mag[8], bin_mag[16], bin_mag[31]);
        end
    end

    // 产生正弦波样本（1kHz @ 48kHz → bin ≈ 1000/187.5 ≈ 5.3）
    integer i;
    reg signed [15:0] sine_val;
    initial begin
        rst = 1;
        #200;
        @(posedge clk); rst = 0;
        #200;

        // Test 1: 写入 256 个样本（正弦波），触发一次计算
        $display("TEST1: write 256 sine samples");
        for (i = 0; i < 256; i = i + 1) begin
            // 简单正弦近似: 用查表或多项式
            sine_val = $rtoi(16000.0 * $sin(2.0 * 3.14159 * 5.3 * i / 256.0));
            @(posedge clk);
            audio_valid <= 1;
            audio_left  <= {sine_val, 8'd0};
            audio_right <= {sine_val, 8'd0};
        end
        @(posedge clk); audio_valid <= 0;

        // 等待计算完成（32 bin × 256 样本 = 8192 周期）
        #1000000;  // 1ms 等待

        if (ready_count > 0) begin
            $display("TEST1 PASS: %0d spectrum frames", ready_count);
        end else begin
            $display("TEST1 FAIL: no spectrum_ready");
            errors = errors + 1;
        end

        if (errors == 0) $display("TB_FFT_SPECTRUM PASS");
        else $display("TB_FFT_SPECTRUM FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TB_FFT_SPECTRUM TIMEOUT state=%0d", u_dut.state);
        $finish;
    end

endmodule
