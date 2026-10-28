// tb_siren_gen.v — siren_gen 单元仿真
`timescale 1ns/1ps
module tb_siren_gen;

    reg clk = 0, rst = 1;
    always #20 clk = ~clk;  // 25MHz

    reg         enable = 0;
    reg         sample_tick = 0;
    wire        audio_valid;
    wire [23:0] audio_left, audio_right;

    siren_gen u_dut(
        .clk(clk), .rst(rst),
        .enable(enable), .sample_tick(sample_tick),
        .audio_valid(audio_valid),
        .audio_left(audio_left), .audio_right(audio_right)
    );

    integer errors = 0;
    integer valid_count = 0;

    always @(posedge clk) begin
        if (audio_valid) valid_count = valid_count + 1;
    end

    // 48kHz sample_tick（每 525 周期）
    integer div = 0;
    always @(posedge clk) begin
        if (rst) begin div <= 0; sample_tick <= 0; end
        else begin
            div <= div + 1;
            if (div == 524) begin sample_tick <= 1; div <= 0; end
            else sample_tick <= 0;
        end
    end

    initial begin
        rst = 1;
        #100;
        @(posedge clk); rst = 0;
        #100;

        // Test 1: 禁用时无输出
        $display("TEST1: disabled - no output");
        enable = 0;
        valid_count = 0;
        #100000;
        if (valid_count == 0) $display("TEST1 PASS");
        else begin $display("TEST1 FAIL: %0d samples", valid_count); errors = errors + 1; end

        // Test 2: 启用后有输出
        $display("TEST2: enabled - produces output");
        enable = 1;
        valid_count = 0;
        #200000;  // 等待多个 sample_tick
        if (valid_count > 0) $display("TEST2 PASS: %0d samples", valid_count);
        else begin $display("TEST2 FAIL: no samples"); errors = errors + 1; end

        if (errors == 0) $display("TB_SIREN_GEN PASS");
        else $display("TB_SIREN_GEN FAIL errors=%0d", errors);
        $finish;
    end

endmodule
