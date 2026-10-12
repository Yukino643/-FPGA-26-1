`timescale 1ns/1ps
// 直接实例化顶层原文，验证行首、行尾、消隐及连续地址编码像素。
module tb_video_pipeline_720;
    reg video_clk=0, rst_video=1;
    always #6.734 video_clk=~video_clk;
    reg mix_de=0, mix_vs=0;
    reg [10:0] mix_x=0;
    reg [9:0] mix_y=100;
    reg [23:0] vout_data=0;
    wire [23:0] vout_osd, vout_waveform, vout_color, vout_final;
    wire axis_s_user, axis_s_valid, axis_s_last;
    wire [23:0] axis_s_data;
    wire [7:0] clk_hh=0, clk_mm=0, clk_ss=0;
    wire [1:0] mode_v1=1;
    wire audio_valid_final=0;
    wire [23:0] audio_left_final=0;
    wire waveform_pcm_valid=0;
    wire vs_rise_v=0, emergency_mode=0;
    wire [3:0] sw=0;
    `include "reg_video_pipeline_720.vh"

    reg [3:0] valid_pipe=0, last_pipe=0;
    reg [23:0] data_pipe[0:3];
    integer i, x, row, got=0, lines=0;
    always @(posedge video_clk) begin
        if (rst_video) begin valid_pipe=0; last_pipe=0; end
        else begin
            // 色彩、波形、OSD、AXIS 共四拍；在沿后检查寄存输出。
            for(i=3;i>0;i=i-1) data_pipe[i]=data_pipe[i-1];
            data_pipe[0]=vout_data;
            valid_pipe={valid_pipe[2:0],mix_de};
            last_pipe={last_pipe[2:0],mix_de && mix_x==1279};
            #1;
            if(axis_s_valid !== valid_pipe[3] || axis_s_last !== last_pipe[3]) begin
                $display("FAIL pipeline DE/TLAST valid=%b expected=%b last=%b expected=%b",axis_s_valid,valid_pipe[3],axis_s_last,last_pipe[3]); $fatal(1);
            end
            if(axis_s_valid) begin
                if(axis_s_data !== data_pipe[3]) begin
                    $display("FAIL pipeline RGB[%0d]=%h expected=%h",got,axis_s_data,data_pipe[3]); $fatal(1);
                end
                got=got+1;
                if(axis_s_last) lines=lines+1;
            end
        end
    end
    initial begin
        repeat(5) @(negedge video_clk); rst_video=0;
        repeat(10) @(negedge video_clk);
        for(row=0;row<2;row=row+1) begin
            for(x=0;x<1280;x=x+1) begin
                @(negedge video_clk); mix_de=1; mix_x=x; mix_y=row==0 ? 100:710;
                vout_data={x[7:0],x[9:2],8'h5a^x[7:0]};
            end
            @(negedge video_clk); mix_de=0; vout_data=24'hffffff;
            repeat(160) @(negedge video_clk);
        end
        if(got!=2560 || lines!=2) begin $display("FAIL coverage pixels=%0d lines=%0d",got,lines); $fatal(1); end
        $display("TB_VIDEO_PIPELINE_720 PASS pixels=%0d lines=%0d",got,lines); $finish;
    end
    initial begin #200000; $display("FAIL video pipeline timeout"); $fatal(1); end
endmodule
