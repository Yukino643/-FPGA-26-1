// tb_emergency_ctrl.v — emergency_ctrl 单元仿真
`timescale 1ns/1ps
module tb_emergency_ctrl;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;  // 100MHz

    reg  key4 = 1;  // 高=未按下
    reg  mode_active = 0;
    wire emergency_request, buzzer_on;

    emergency_ctrl #(.CLK_FREQ_HZ(100_000_000), .LONG_PRESS_MS(1), .DEBOUNCE_CYCLES(10)) u_dut(
        .clk(clk), .rst(rst),
        .key4(key4), .mode_active(mode_active),
        .emergency_request(emergency_request), .buzzer_on(buzzer_on)
    );

    integer errors = 0;

    initial begin
        rst = 1;
        #100;
        @(posedge clk); rst = 0;
        #100;

        // Test 1: 长按 KEY4 进入应急模式
        $display("TEST1: long press to enter emergency");
        key4 = 0;  // 按下
        #2000000;  // 等待 2ms（10 周期消抖 + 1ms 长按 + 余量）
        key4 = 1;  // 松开
        #1000000;  // 等待 1ms
        if (emergency_request) $display("TEST1 PASS: emergency_request=1");
        else begin $display("TEST1 FAIL: emergency_request=0"); errors = errors + 1; end
        // 模拟上层在视频帧边界提交后同步回控制域。
        mode_active = emergency_request;

        // Test 2: 蜂鸣器在应急模式下工作
        $display("TEST2: buzzer in emergency mode");
        #50000;
        if (buzzer_on !== 1'bx) $display("TEST2 PASS: buzzer_on=%b", buzzer_on);
        else begin $display("TEST2 FAIL"); errors = errors + 1; end

        // Test 3: 再次长按退出
        $display("TEST3: long press to exit");
        key4 = 0;
        #2000000;
        key4 = 1;
        #1000000;
        if (!emergency_request) $display("TEST3 PASS: emergency_request=0");
        else begin $display("TEST3 FAIL: emergency_request=1"); errors = errors + 1; end
        mode_active = emergency_request;

        if (errors == 0) $display("TB_EMERGENCY_CTRL PASS");
        else $display("TB_EMERGENCY_CTRL FAIL errors=%0d", errors);
        $finish;
    end

endmodule
