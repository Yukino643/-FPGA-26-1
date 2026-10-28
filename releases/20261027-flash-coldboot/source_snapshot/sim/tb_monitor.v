// tb_monitor.v — 监视台渲染链仿真：跑一帧，把有效区像素写成 PPM 图片
// 用法: iverilog -o tb_monitor.vvp tb_monitor.v ../rtl/video/video_timing_gen.v ../rtl/video/monitor_compositor.v ../rtl/ctrl/font_rom_ascii.v && vvp tb_monitor.vvp
`timescale 1ns/1ps
module tb_monitor;

    reg clk = 0;
    reg rst = 1;
    always #10 clk = ~clk;   // 50MHz（仿真频率与逻辑无关，时序发生器参数化）

    wire        mon_hs, mon_vs, mon_de;
    wire [9:0]  mon_x;
    wire [8:0]  mon_y;
    wire [23:0] mon_rgb;

    // 固定状态值便于核对: uptime=1234s(0x4D2), frame=0x00123456, dev=+42, mode=AD
    reg  [31:0] uptime_sec = 32'h000004D2;
    reg  [31:0] frame_cnt  = 32'h00123456;
    reg  [15:0] sync_dev   = 16'h002A;
    reg  [1:0]  mode       = 2'd1;

    video_timing_gen #(
        .HTOTAL(800), .HSA(96), .HFP(16), .HBP(48), .HACTIVE(640),
        .VTOTAL(525), .VSA(2),  .VFP(10), .VBP(33), .VACTIVE(480)
    ) u_timing (
        .I_clk(clk), .I_rst(rst),
        .O_hs(mon_hs), .O_vs(mon_vs), .O_de(mon_de),
        .O_x(mon_x), .O_y(mon_y)
    );

    monitor_compositor u_comp (
        .I_clk(clk),
        .I_de(mon_de), .I_x(mon_x), .I_y(mon_y),
        .I_uptime_sec(uptime_sec), .I_frame_cnt(frame_cnt),
        .I_sync_dev(sync_dev), .I_mode(mode),
        .I_disp_underflow(32'h00012345), .I_fifo_a_used(10'd256),
        .I_tf_diag({16'h1883,16'h0130,32'h00008e30,32'h00020000,16'h0000,32'h424d3610,32'h0004b000,8'h01,8'h01}),
        .O_rgb(mon_rgb)
    );

    // A2: 渲染流水线输出延迟 1 拍，采集坐标同步打 1 拍
    reg        de_cap;
    reg [9:0]  px_cap;
    reg [8:0]  py_cap;
    always @(posedge clk) begin
        de_cap <= mon_de;
        px_cap <= mon_x;
        py_cap <= mon_y;
    end

    // 帧缓存 640x480（哨兵初值，用于覆盖完整性自检）
    reg [23:0] fb [0:640*480-1];
    integer si, nbad;
    integer fd, r, c;
    reg [31:0] idx;
    integer frames_done = 0;

    always @(posedge clk) begin
        if (de_cap)
            fb[py_cap * 640 + px_cap] <= mon_rgb;
        if (mon_vs && frames_done == 0) begin
            frames_done <= 1;
            fd = $fopen("monitor_frame.ppm", "w");
            $fwrite(fd, "P3\n640 480\n255\n");
            for (r = 0; r < 480; r = r + 1)
                for (c = 0; c < 640; c = c + 1) begin
                    idx = r * 640 + c;
                    $fwrite(fd, "%0d %0d %0d\n", fb[idx][23:16], fb[idx][15:8], fb[idx][7:0]);
                end
            $fclose(fd);
            nbad = 0;
            for (si = 0; si < 640*480; si = si + 1)
                if (fb[si] === 24'hFF00FF || fb[si] === 24'hxxxxxx) nbad = nbad + 1;
            if (nbad == 0) $display("TB_MONITOR PASS");
            else $display("TB_MONITOR FAIL nbad=%0d", nbad);
            $finish;
        end
    end

    initial begin
        for (si = 0; si < 640*480; si = si + 1) fb[si] = 24'hFF00FF;   // 哨兵
        rst = 1;
        #100;
        rst = 0;
        #10_000_000;   // 10ms 上限保护
        $display("TIMEOUT");
        $finish;
    end

endmodule
