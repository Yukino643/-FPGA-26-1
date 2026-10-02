`timescale 1ns/1ps
// 检查老师方案的采样抽取、双 bank 发布，以及有符号满幅和透明背景。
module tb_audio_waveform;
    reg clk=0, rst=1, vs=0, de=1, enable=1, valid=0;
    reg [9:0] x=0;
    reg [8:0] y=0;
    reg signed [15:0] pcm=0;
    wire [23:0] rgb;
    wire active;
    integer samples[0:31];
    integer n, xx, yy, idx, interp, offset, sy, checks=0;
    reg [23:0] expected;
    always #5 clk=~clk;
    promax_audio_waveform dut(.clk(clk), .rst(rst), .vs_pulse(vs), .de(de), .enable(enable),
        .pixel_x(x), .pixel_y(y), .rgb_in(24'h876543), .pcm_tap_valid(valid),
        .pcm_tap_left(pcm), .rgb_out(rgb), .waveform_active(active));

    task frame_boundary;
        begin
            @(negedge clk); vs=1;
            @(negedge clk); vs=0;
        end
    endtask
    task pcm_word;
        input integer value;
        begin
            @(negedge clk); valid=1; pcm=value*256;
            @(negedge clk); valid=0;
            // 有效脉冲间的空拍不能推进抽取计数。
            @(negedge clk);
        end
    endtask
    task check_image;
        input integer flat;
        input integer value;
        input integer peak;
        begin
            for (yy=380; yy<452; yy=yy+1) begin
                for (xx=60; xx<600; xx=xx+1) begin
                    x=xx; y=yy;
                    idx=(xx-64)/16;
                    interp=value;
                    if (!flat && idx>=0 && idx<32) interp=samples[idx];
                    offset=interp / 4;
                    if (offset>30) offset=30;
                    if (offset< -30) offset= -30;
                    sy=416-offset;
                    expected=24'h876543;
                    if (xx>=64 && xx<576 && yy>=384 && yy<448) begin
                        if (yy==416) expected=24'h406060;
                        if (yy>=sy-1 && yy<=sy+1) expected=24'h20ff90;
                    end
                    if (xx>=584 && xx<592 && yy>=448-(peak/4) && yy<448)
                        expected=24'hffb020;
                    #1;
                    if (rgb !== expected || active !== (expected!=24'h876543))
                        $fatal(1,"FAIL waveform x=%0d y=%0d got=%h expected=%h",xx,yy,rgb,expected);
                    checks=checks+1;
                end
            end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        for(n=0;n<32;n=n+1)
            samples[n]=(n<16) ? -120+n*16 : 120-(n-16)*16;
        // 未发布采样组之前只允许参考轴，不能读取未初始化 RAM。
        x=64; y=415; #1;
        if(rgb!==24'h876543) $fatal(1,"FAIL uninitialized waveform");
        for(n=0;n<100;n=n+1) pcm_word((n%12==0) ? samples[n/12] : 127);
        frame_boundary;
        if(dut.display_valid || dut.capture_count!=0 || dut.write_bank!=0)
            $fatal(1,"FAIL incomplete group must be discarded at frame boundary");
        for(n=0;n<384;n=n+1) pcm_word((n%12==0) ? samples[n/12] : 127);
        for(n=0;n<10;n=n+1) pcm_word(-128);
        if(dut.capture_count!=32 || dut.display_valid)
            $fatal(1,"FAIL capture must wait for VS");
        frame_boundary;
        if(!dut.display_valid || dut.display_bank!=0 || dut.write_bank!=1)
            $fatal(1,"FAIL ping-pong publish");
        if(dut.display_peak!=120) $fatal(1,"FAIL captured peak=%0d",dut.display_peak);
        check_image(0,0,120);
        for(n=0;n<100;n=n+1) pcm_word(-128);
        frame_boundary;
        if(dut.display_bank!=0 || dut.capture_count!=0)
            $fatal(1,"FAIL partial capture changed display");
        check_image(0,0,120);
        for(n=0;n<384;n=n+1) pcm_word(-128);
        frame_boundary;
        if(dut.display_bank!=1 || dut.write_bank!=0)
            $fatal(1,"FAIL second bank publish");
        if(dut.display_peak!=128) $fatal(1,"FAIL negative full-scale peak=%0d",dut.display_peak);
        check_image(1,-128,128);
        for(n=0;n<384;n=n+1) pcm_word(127);
        frame_boundary;
        if(dut.display_peak!=127) $fatal(1,"FAIL positive peak=%0d",dut.display_peak);
        check_image(1,127,127);
        x=64; y=386; enable=0; #1;
        if(rgb!==24'h876543 || active) $fatal(1,"FAIL disabled passthrough");
        enable=1; de=0; #1;
        if(rgb!==24'h876543 || active) $fatal(1,"FAIL blanking passthrough");
        $display("TB_AUDIO_WAVEFORM PASS checks=%0d",checks); $finish;
    end
    initial begin #500000; $fatal(1,"FAIL waveform timeout"); end
endmodule
