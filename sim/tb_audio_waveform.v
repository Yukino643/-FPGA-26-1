`timescale 1ns/1ps
// 同时覆盖默认、非二次幂步长和单像素步长，检查曲线连通及完整采样组发布。
module tb_audio_waveform;
    wire default_done, wide_done, narrow_done;
    tb_audio_waveform_case #(.RENDER(1)) default_case(.done(default_done));
    tb_audio_waveform_case #(
        .WAVE_X(0), .WAVE_Y(300), .WAVE_WIDTH(640), .WAVE_HEIGHT(128), .DECIMATE(3)
    ) wide_case(.done(wide_done));
    tb_audio_waveform_case #(
        .WAVE_X(96), .WAVE_Y(250), .WAVE_WIDTH(32), .WAVE_HEIGHT(72), .DECIMATE(1)
    ) narrow_case(.done(narrow_done));
    initial begin
        wait(default_done && wide_done && narrow_done);
        $display("TB_AUDIO_WAVEFORM PASS checks=%0d", default_case.checks+wide_case.checks+narrow_case.checks);
        $finish;
    end
    initial begin #2000000; $fatal(1,"FAIL waveform timeout"); end
endmodule

module tb_audio_waveform_case #(
    parameter integer WAVE_X=64,
    parameter integer WAVE_Y=376,
    parameter integer WAVE_WIDTH=512,
    parameter integer WAVE_HEIGHT=72,
    parameter integer DECIMATE=4,
    parameter integer RENDER=0
)(output reg done=0);
    localparam integer SPACING=WAVE_WIDTH/32;
    localparam integer CENTER=WAVE_Y+WAVE_HEIGHT/2;
    localparam integer LIMIT=WAVE_HEIGHT/2-2;
    localparam [23:0] BACKGROUND=24'h876543;
    reg clk=0, rst=1, vs=0, de=1, enable=1, valid=0;
    reg [9:0] x=0;
    reg [8:0] y=0;
    reg signed [15:0] pcm=0;
    wire [23:0] rgb;
    wire active;
    integer samples[0:31];
    integer n, xx, yy, start_x, checks=0;
    integer expected_top, expected_bottom, first_y, last_y, previous_bottom, previous_top;
    integer visible_count, render_file;
    reg [23:0] expected;
    always #5 clk=~clk;
    promax_audio_waveform #(
        .WAVE_X(WAVE_X), .WAVE_Y(WAVE_Y), .WAVE_WIDTH(WAVE_WIDTH),
        .WAVE_HEIGHT(WAVE_HEIGHT), .DECIMATE(DECIMATE)
    ) dut(.clk(clk), .rst(rst), .vs_pulse(vs), .de(de), .enable(enable),
        .pixel_x(x), .pixel_y(y), .rgb_in(BACKGROUND), .pcm_tap_valid(valid),
        .pcm_tap_left(pcm), .rgb_out(rgb), .waveform_active(active));

    function integer clipped_offset;
        input integer sample;
        integer value;
        begin
            value=sample/2;
            if(value>LIMIT) value=LIMIT;
            if(value< -LIMIT) value= -LIMIT;
            clipped_offset=value;
        end
    endfunction
    function integer curve_y;
        input integer column;
        integer sample_number, fraction, a, b;
        begin
            sample_number=column/SPACING;
            fraction=column%SPACING;
            a=clipped_offset(samples[sample_number]);
            b=(sample_number==31) ? a : clipped_offset(samples[sample_number+1]);
            curve_y=CENTER-a-(b-a)*fraction/SPACING;
        end
    endfunction
    // 用相邻列的解析端点构建独立整数参考；最右边保持第 32 个样本。
    task expected_column;
        input integer column;
        integer a, b;
        begin
            a=curve_y(column);
            b=(column==WAVE_WIDTH-1) ? a : curve_y(column+1);
            expected_top=((a<b) ? a : b)-1;
            expected_bottom=((a>b) ? a : b)+1;
        end
    endtask
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
            // 无有效样本的空拍不能推进抽取计数。
            @(negedge clk);
        end
    endtask
    task capture_range;
        input integer first;
        input integer count;
        integer word_number;
        begin
            for(word_number=0;word_number<count*DECIMATE;word_number=word_number+1)
                pcm_word((word_number%DECIMATE==0) ? samples[first+word_number/DECIMATE] : 0);
        end
    endtask
    task check_image;
        input integer published;
        input integer peak;
        begin
            start_x=(WAVE_X<4) ? 0 : WAVE_X-4;
            for(yy=WAVE_Y-4;yy<WAVE_Y+WAVE_HEIGHT+4;yy=yy+1) begin
                for(xx=start_x;xx<WAVE_X+WAVE_WIDTH+24;xx=xx+1) begin
                    x=xx; y=yy;
                    expected=BACKGROUND;
                    if(xx>=WAVE_X && xx<WAVE_X+WAVE_WIDTH && yy>=WAVE_Y && yy<WAVE_Y+WAVE_HEIGHT) begin
                        if(yy==CENTER) expected=24'h406060;
                        if(published) begin
                            expected_column(xx-WAVE_X);
                            if(yy>=expected_top && yy<=expected_bottom) expected=24'h20ff90;
                        end
                    end
                    if(xx>=WAVE_X+WAVE_WIDTH+8 && xx<WAVE_X+WAVE_WIDTH+16 &&
                       yy>=WAVE_Y+WAVE_HEIGHT-(peak/4) && yy<WAVE_Y+WAVE_HEIGHT)
                        expected=24'hffb020;
                    #1;
                    if(rgb !== expected || active !== (expected!=BACKGROUND))
                        $fatal(1,"FAIL waveform width=%0d x=%0d y=%0d got=%h expected=%h",WAVE_WIDTH,xx,yy,rgb,expected);
                    checks=checks+1;
                end
            end
        end
    endtask
    task check_continuity;
        begin
            previous_top=-1; previous_bottom=-1;
            for(xx=WAVE_X;xx<WAVE_X+WAVE_WIDTH;xx=xx+1) begin
                first_y=-1; last_y=-1; visible_count=0;
                for(yy=WAVE_Y;yy<WAVE_Y+WAVE_HEIGHT;yy=yy+1) begin
                    x=xx; y=yy; #1;
                    if(rgb===24'h20ff90) begin
                        if(first_y<0) first_y=yy;
                        last_y=yy;
                        visible_count=visible_count+1;
                    end
                end
                if(first_y<0 || last_y-first_y+1!=visible_count)
                    $fatal(1,"FAIL curve has an empty column or internal hole width=%0d x=%0d",WAVE_WIDTH,xx);
                if(xx>WAVE_X && (first_y>previous_bottom || last_y<previous_top))
                    $fatal(1,"FAIL curve columns disconnected width=%0d x=%0d",WAVE_WIDTH,xx);
                // 最后一个采样区间必须保持末点且为三像素宽，不读取第 33 个样本。
                if(xx>=WAVE_X+31*SPACING &&
                   (visible_count!=3 || first_y!=CENTER-clipped_offset(samples[31])-1))
                    $fatal(1,"FAIL final sample width=%0d x=%0d",WAVE_WIDTH,xx);
                previous_top=first_y; previous_bottom=last_y;
                checks=checks+1;
            end
        end
    endtask
    task render_image;
        begin
            render_file=$fopen("waveform_continuous.ppm","w");
            if(!render_file) $fatal(1,"FAIL waveform render output cannot be opened");
            $fwrite(render_file,"P3\n%0d %0d\n255\n",WAVE_WIDTH+48,WAVE_HEIGHT+16);
            for(yy=WAVE_Y-8;yy<WAVE_Y+WAVE_HEIGHT+8;yy=yy+1) begin
                for(xx=WAVE_X-16;xx<WAVE_X+WAVE_WIDTH+32;xx=xx+1) begin
                    x=xx; y=yy; #1;
                    $fwrite(render_file,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
                end
            end
            $fclose(render_file);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        for(n=0;n<32;n=n+1)
            samples[n]=(n<16) ? -120+n*16 : 120-(n-16)*16;
        // RAM 无须复位填零；显示有效位发布前必须遮住全部未初始化样本。
        check_image(0,0);
        capture_range(0,25);
        frame_boundary;
        if(dut.display_valid || dut.capture_count!=25 || dut.write_bank!=0)
            $fatal(1,"FAIL incomplete group must survive VS width=%0d",WAVE_WIDTH);
        capture_range(25,7);
        if(dut.capture_count!=32 || dut.display_valid)
            $fatal(1,"FAIL capture must wait for VS width=%0d",WAVE_WIDTH);
        pcm_word(127);
        if(dut.capture_count!=32) $fatal(1,"FAIL full capture overwrote group");
        frame_boundary;
        if(!dut.display_valid || dut.display_bank!=0 || dut.write_bank!=1 || dut.display_peak!=120)
            $fatal(1,"FAIL first bank publish width=%0d",WAVE_WIDTH);
        check_image(1,120);
        check_continuity;
        // 写侧部分采样和 VS 不得影响旧曲线；对不同 bank 的数据单独验证。
        for(n=0;n<3*DECIMATE;n=n+1) pcm_word(-128);
        frame_boundary;
        if(dut.display_bank!=0 || dut.capture_count!=3)
            $fatal(1,"FAIL partial capture changed display width=%0d",WAVE_WIDTH);
        check_image(1,120);
        for(n=0;n<29*DECIMATE;n=n+1) pcm_word(-128);
        frame_boundary;
        if(dut.display_bank!=1 || dut.write_bank!=0 || dut.display_peak!=128)
            $fatal(1,"FAIL negative full-scale publish width=%0d",WAVE_WIDTH);
        for(n=0;n<32;n=n+1) samples[n]=-128;
        check_image(1,128);
        check_continuity;
        for(n=0;n<32;n=n+1) samples[n]=127;
        capture_range(0,32);
        frame_boundary;
        if(dut.display_peak!=127) $fatal(1,"FAIL positive full-scale peak");
        check_image(1,127);
        check_continuity;
        // 最大正负交替会让相邻列跳跃超过三像素，必须仍逐列连通且负坡方向正确。
        for(n=0;n<32;n=n+1) samples[n]=(n%2) ? -128 : 127;
        capture_range(0,32);
        frame_boundary;
        check_image(1,128);
        check_continuity;
        // 非单调曲线验证每个分段及末点，避免只测纯色或统一斜率。
        for(n=0;n<32;n=n+1)
            samples[n]=$rtoi(44.0*$sin(n*0.48)+18.0*$sin(n*1.12));
        capture_range(0,32);
        frame_boundary;
        check_image(1,dut.display_peak);
        check_continuity;
        if(RENDER) render_image;
        x=WAVE_X; y=CENTER; enable=0; #1;
        if(rgb!==BACKGROUND || active) $fatal(1,"FAIL disabled passthrough");
        enable=1; de=0; #1;
        if(rgb!==BACKGROUND || active) $fatal(1,"FAIL blanking passthrough");
        $display("TB_AUDIO_WAVEFORM case width=%0d spacing=%0d checks=%0d PASS",WAVE_WIDTH,SPACING,checks);
        done=1;
    end
endmodule
