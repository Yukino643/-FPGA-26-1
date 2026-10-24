`timescale 1ns/1ps
// 引用真实顶层的 CDC 原文，异步时钟验证提交页号与装载释放握手。
module tb_display_commit;
    reg video_clk=0, sd_card_clk=0, rst_video=1, rst_sd=1;
    reg scaler_done_toggle=0, vs_rise_v=0;
    reg bmp_display_commit_toggle=0, bmp_display_commit_pulse=0;
    reg [1:0] write_buf_idx=0, tr_mode_reg=1;
    wire [9:0] main_x=0;
    wire [8:0] main_y=0;
    wire tr_hold_load, tr_active, tr_fade_black;
    wire [7:0] tr_alpha;
    wire [9:0] tr_boundary;
    wire [1:0] tr_slide_axis;
    wire [20:0] page_a_base, page_b_base;
    wire loader_hold=display_submit_pending_sd | tr_hold_sync_sd[1];
    integer k, frames, pulse_count=0;
    always @(posedge sd_card_clk)
        if (bmp_display_commit_pulse) bmp_display_commit_toggle <= ~bmp_display_commit_toggle;
    always #20 video_clk=~video_clk;
    always #5 sd_card_clk=~sd_card_clk;
    `include "reg_display_commit.vh"
    always @(posedge video_clk)
        if(!rst_video && commit_pulse_v) begin
            if(commit_buf_v !== write_buf_idx) $fatal(1,"FAIL stale commit payload");
            pulse_count=pulse_count+1;
        end
    task frame_boundary;
        begin
            @(negedge video_clk); vs_rise_v=1;
            @(negedge video_clk); vs_rise_v=0;
        end
    endtask
    initial begin
        repeat(4) @(negedge video_clk); rst_video=0; rst_sd=0;
        for(k=0;k<8;k=k+1) begin
            @(negedge sd_card_clk); write_buf_idx=k%2; tr_mode_reg=k%4;
            // 页号从装载开始到视频确认一直稳定。
            repeat(8) @(negedge video_clk);
            @(negedge sd_card_clk); bmp_display_commit_pulse=1;
            @(negedge sd_card_clk); bmp_display_commit_pulse=0;
            repeat(5) @(negedge sd_card_clk);
            if(!loader_hold) $fatal(1,"FAIL successful commit not held in SD domain");
            repeat(5) @(negedge video_clk);
            if(!tr_hold_load || !loader_hold) $fatal(1,"FAIL missing video hold");
            frame_boundary;
            frames=0;
            while(tr_hold_load) begin
                if(!loader_hold) $fatal(1,"FAIL loader released during transition");
                frame_boundary; frames=frames+1;
                if(frames>70) $fatal(1,"FAIL display release deadlock");
            end
            if(page_a_base !== ((k%2)==1 ? 21'h80000 : 21'd0))
                $fatal(1,"FAIL display page association commit=%0d page=%h",k,page_a_base);
            repeat(5) @(negedge video_clk);
            if(loader_hold || display_submit_pending_sd) $fatal(1,"FAIL SD release not acknowledged");
            if(pulse_count!=k+1) $fatal(1,"FAIL duplicate/lost commit event");
        end
        $display("TB_DISPLAY_COMMIT PASS commits=%0d",pulse_count); $finish;
    end
    initial begin #100000; $fatal(1,"FAIL commit timeout"); end
endmodule
