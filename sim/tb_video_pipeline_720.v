`timescale 1ns/1ps
// 直接实例化顶层原文，验证行首、行尾、消隐及连续地址编码像素。
module tb_video_pipeline_720;
    parameter integer SUBTITLES=0;
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
    // 新增 HDMI-B 图层开关：旧流水线回归保持默认全开启。
    wire cfg_image_enable=1'b1, cfg_wave_enable=1'b1;
    wire cfg_clock_enable=1'b1, cfg_text_enable=1'b1;
    wire [7:0] screen_contrast_video=8'd128;
    wire signed [7:0] screen_brightness_video=0, screen_temp_video=0;
    wire [4:0] subtitle_active_video=SUBTITLES ? 5'h09 : 5'h08;
    `include "reg_video_pipeline_720.vh"

    reg [3:0] valid_pipe=0, last_pipe=0;
    reg [23:0] data_pipe[0:3];
    reg [31:0] font[0:2047];
    integer title_cells[0:13],mode_cells[0:3];
    integer i, x, row, got=0, lines=0;
    integer glyph,cell_col,glyph_row,glyph_x;
    reg [31:0] ink_bits;
    reg glyph_hit;
    reg [23:0] ink;
    always @(posedge video_clk) begin
        if (rst_video) begin valid_pipe=0; last_pipe=0; end
        else begin
            // 色彩、波形、OSD、AXIS 共四拍；在沿后检查寄存输出。
            for(i=3;i>0;i=i-1) data_pipe[i]=data_pipe[i-1];
            data_pipe[0]=vout_data;
            // 波形无已发布采样时仍画中轴，几何必须跟真实顶层88高一致。
            if(mix_y==620 && mix_x>=128 && mix_x<1152) data_pipe[0]=24'h2A4E58;
            if((mix_y>=16 && mix_y<64 &&
                ((mix_x>=16 && mix_x<496) || (mix_x>=1104 && mix_x<1264))) ||
               (mix_y>=664 && mix_y<712 && mix_x<1264 &&
                ((SUBTITLES && mix_x>=16) || mix_x>=880)))
                data_pipe[0]={2'b0,vout_data[23:18],2'b0,vout_data[15:10],2'b0,vout_data[7:2]};
            if(SUBTITLES && mix_y>=664 && mix_y<712 && mix_x>=16 && mix_x<112)
                data_pipe[0]=24'h0E3A4C;
            glyph=0;glyph_row=0;glyph_x=0;glyph_hit=0;ink=24'hF2FAFF;
            if(mix_y>=24 && mix_y<56) begin
                glyph_row=mix_y-24;glyph_x=mix_x%32;
                if(mix_x>=32 && mix_x<480)begin glyph=title_cells[(mix_x-32)/32];glyph_hit=1;end
                else if(mix_x>=1120 && mix_x<1248)begin
                    glyph=mode_cells[(mix_x-1120)/32];glyph_hit=1;ink=24'h8FD5FA;
                end
            end
            if(mix_y>=672 && mix_y<704) begin
                glyph_row=mix_y-672;
                if(mix_x>=896 && mix_x<1248)begin
                    glyph_hit=1;glyph_x=(mix_x-896)%32;cell_col=(mix_x-896)/32;ink=24'hC9DBE5;
                    case(cell_col)
                        0:glyph=20;1:glyph=21;2:glyph=0;5,8:glyph=23;default:glyph=22;
                    endcase
                end else if(SUBTITLES && mix_x>=32 && mix_x<96)begin
                    glyph_hit=1;glyph_x=(mix_x-32)%32;glyph=mix_x<64?48:49;
                end else if(SUBTITLES && mix_x>=128 && mix_x<864)begin
                    glyph_hit=1;glyph_x=(mix_x+1184)%32;glyph=0;
                end
            end
            ink_bits=font[glyph*32+glyph_row];
            if(glyph_hit && ink_bits[31-glyph_x])data_pipe[0]=ink;
            if(SUBTITLES && mix_y>=664 && mix_y<666 && mix_x>=16 && mix_x<1264)data_pipe[0]=24'h38BDF8;
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
        $readmemh("D:/FPGA/code/example/rtl/video/font_720.hex",font);
        for(i=0;i<14;i=i+1)title_cells[i]=i+1;
        mode_cells[0]=15;mode_cells[1]=16;mode_cells[2]=5;mode_cells[3]=17;
        repeat(5) @(negedge video_clk); rst_video=0;
        repeat(10) @(negedge video_clk);
        for(row=0;row<10;row=row+1) begin
            for(x=0;x<1280;x=x+1) begin
                @(negedge video_clk); mix_de=1; mix_x=x;
                case(row)
                    0:mix_y=100;1:mix_y=710;2:mix_y=24;3:mix_y=40;
                    4:mix_y=55;5:mix_y=620;6:mix_y=664;7:mix_y=672;
                    8:mix_y=687;9:mix_y=703;
                endcase
                vout_data={x[7:0],x[9:2],8'h5a^x[7:0]};
            end
            @(negedge video_clk); mix_de=0; vout_data=24'hffffff;
            repeat(160) @(negedge video_clk);
        end
        if(got!=12800 || lines!=10) begin $display("FAIL coverage pixels=%0d lines=%0d",got,lines); $fatal(1); end
        $display("TB_VIDEO_PIPELINE_720 PASS pixels=%0d lines=%0d",got,lines); $finish;
    end
    initial begin #400000; $display("FAIL video pipeline timeout"); $fatal(1); end
endmodule
