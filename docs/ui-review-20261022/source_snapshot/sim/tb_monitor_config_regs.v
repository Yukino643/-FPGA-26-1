`timescale 1ns/1ps
module tb_monitor_config_regs;
    reg video_clk=0, video_rst=1, vs_rise=0;
    always #5 video_clk=~video_clk;
    reg [3:0] shadow_sd=7, payload_sd=7;
    reg [9:0] screen_shadow_sd=10'h144, screen_payload_sd=10'h144;
    wire [9:0] screen_active, screen_preview;
    reg [4:0] subtitle_shadow_sd=5'h08, subtitle_payload_sd=5'h08;
    wire [4:0] subtitle_active, subtitle_preview;
    reg commit_toggle_sd=0;
    wire [3:0] active_video, preview_video;
    wire commit_seen, applied_toggle;
    monitor_config_regs dut(
        .video_clk(video_clk), .video_rst(video_rst), .vs_rise(vs_rise),
        .cfg_shadow_sd(shadow_sd), .cfg_payload_sd(payload_sd),
        .screen_shadow_sd(screen_shadow_sd), .screen_payload_sd(screen_payload_sd),
        .screen_active_video(screen_active), .screen_preview_video(screen_preview),
        .subtitle_shadow_sd(subtitle_shadow_sd), .subtitle_payload_sd(subtitle_payload_sd),
        .subtitle_active_video(subtitle_active), .subtitle_preview_video(subtitle_preview),
        .cfg_commit_toggle_sd(commit_toggle_sd),
        .cfg_active_video(active_video), .cfg_preview_video(preview_video),
        .cfg_commit_seen_video(commit_seen), .cfg_applied_toggle_video(applied_toggle));
    task pulse_vs;
        begin @(negedge video_clk); vs_rise=1; @(negedge video_clk); vs_rise=0; end
    endtask
    initial begin
        repeat(3) @(negedge video_clk); video_rst=0;
        if(screen_active!==10'h144) $fatal(1,"screen default");
        #2; shadow_sd=5; payload_sd=5; screen_payload_sd=10'h288; commit_toggle_sd=1;
        subtitle_payload_sd=5'h13;
        repeat(8) @(negedge video_clk);
        shadow_sd=1; screen_shadow_sd=10'h000;
        subtitle_shadow_sd=5'h01;
        repeat(6) @(negedge video_clk);
        if(active_video!==7 || preview_video!==1) $fatal(1,"preview before VS");
        if(screen_active!==10'h144 || screen_preview!==0) $fatal(1,"screen preview before VS");
        if(subtitle_active!==5'h08 || subtitle_preview!==5'h01) $fatal(1,"subtitle preview before VS");
        pulse_vs;
        if(active_video!==5 || !commit_seen || !applied_toggle) $fatal(1,"first VS commit");
        if(screen_active!==10'h288) $fatal(1,"atomic color payload");
        if(subtitle_active!==5'h13) $fatal(1,"atomic subtitle payload");
        pulse_vs;
        if(active_video!==5 || commit_seen) $fatal(1,"duplicate commit");
        #3; payload_sd=1; screen_payload_sd=10'h144; commit_toggle_sd=0;
        subtitle_payload_sd=5'h08;
        repeat(8) @(negedge video_clk);
        if(active_video!==5) $fatal(1,"second outside VS");
        pulse_vs;
        if(active_video!==1 || !commit_seen || applied_toggle) $fatal(1,"reverse toggle");
        if(screen_active!==10'h144) $fatal(1,"screen restore on reverse toggle");
        if(subtitle_active!==5'h08) $fatal(1,"subtitle reverse toggle");
        $display("TB_MONITOR_CONFIG_REGS PASS"); $finish;
    end
endmodule
