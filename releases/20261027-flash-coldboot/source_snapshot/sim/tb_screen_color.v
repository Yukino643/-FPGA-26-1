`timescale 1ns/1ps
// 使用顶层真实连接，穷举合法色彩档位，并对所有通道值检查饱和/符号。
module tb_screen_color;
    reg video_clk=0, rst_video=1, vs_rise_v=0, mix_de=1;
    always #5 video_clk=~video_clk;
    reg [3:0] cfg_shadow_sd=7, cfg_payload_sd=7;
    reg [9:0] screen_shadow_sd=10'h144, screen_payload_sd=10'h144;
    wire [4:0] subtitle_shadow_sd=5'h08, subtitle_payload_sd=5'h08;
    wire [4:0] subtitle_active_video, subtitle_preview_video;
    wire [4:0] audio_shadow_sd=10, audio_payload_sd=10;
    wire [4:0] audio_active_video,audio_preview_video;
    reg cfg_commit_toggle_sd=0;
    wire [3:0] cfg_active_video, cfg_preview_video;
    wire [9:0] screen_active_video, screen_preview_video;
    wire cfg_commit_seen_video, cfg_applied_toggle_video;
    wire cfg_image_enable=cfg_active_video[0];
    reg [23:0] vout_data=0;
    wire [23:0] vout_color;
    `include "reg_screen_color.vh"
    integer br, co, te, px, count=0;
    reg [23:0] expected;
    function [7:0] reference;
        input integer channel, gain, offset;
        integer product, result;
        begin
            product=(channel-128)*gain;
            // 独立用除法实现向负无穷舍入，与硬件算术移位比较。
            result=(product>=0 ? product/128 : -((-product+127)/128))+128+offset;
            reference=(result<0) ? 0 : ((result>255) ? 255 : result);
        end
    endfunction
    initial begin
        repeat(5) @(negedge video_clk); rst_video=0;
        for(te=0;te<3;te=te+1)
            for(co=0;co<=8;co=co+1)
                for(br=0;br<=8;br=br+1) begin
                    @(negedge video_clk);
                    screen_payload_sd={te[1:0],co[3:0],br[3:0]};
                    screen_shadow_sd=screen_payload_sd;
                    cfg_commit_toggle_sd=~cfg_commit_toggle_sd;
                    repeat(6) @(negedge video_clk);
                    // 改预览不能抢跑或污染已经登记的正文。
                    screen_shadow_sd=10'h144;
                    repeat(4) @(negedge video_clk);
                    vs_rise_v=1;
                    @(negedge video_clk); vs_rise_v=0;
                    if(screen_active_video!==screen_payload_sd || cfg_applied_toggle_video!==cfg_commit_toggle_sd)
                        $fatal(1,"top mailbox parameter wiring");
                    for(px=0;px<256;px=px+1) begin
                        @(negedge video_clk); vout_data={px[7:0],(8'd255-px[7:0]),(px[7:0]^8'h5A)};
                        expected={reference(px,64+co*16,br*16-64+(te-1)*20),
                                  reference(255-px,64+co*16,br*16-64),
                                  reference(px^8'h5A,64+co*16,br*16-64-(te-1)*20)};
                        @(posedge video_clk); #1;
                        if(vout_color!==expected)
                            $fatal(1,"HDMI-B color br=%0d co=%0d te=%0d px=%0d got=%h expected=%h",br,co,te,px,vout_color,expected);
                        count=count+1;
                    end
                end
        $display("TB_SCREEN_COLOR PASS pixels=%0d",count); $finish;
    end
    // 即使预览继续变化，active 也只能在 HDMI-B 的 VS 发生时改变。
    reg [9:0] prior_active=10'h144;
    reg prior_vs=0;
    always @(posedge video_clk) begin
        prior_vs=vs_rise_v;
        #1;
        if(!rst_video && !prior_vs && screen_active_video!==prior_active)
            $fatal(1,"parameter changed inside a frame");
        prior_active=screen_active_video;
    end
    initial begin #2000000; $fatal(1,"color timeout"); end
endmodule
