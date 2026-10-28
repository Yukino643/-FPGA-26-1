`timescale 1ns/1ps
// 当前顶层原文gate+CDC+transition，重复按键完成并交换页，错误零提交。
module tb_commit720;
    reg retained_front_v,retain_display_v;
    wire media_rst_sd=rst_sd, media_rst_video=rst_video;
    wire media_mode_v=0,media_pause_v=0,media_switch_v=0;
    wire media_blank_v=0,video_audio_mode=0,audio_buffer_ready=0,audio_frame_done=0;
    wire video_will_apply;
    reg video_clk=0,sd_card_clk=0,rst_video=1,rst_sd=1;
    always #6.734 video_clk=~video_clk;
    always #5 sd_card_clk=~sd_card_clk;
    reg vs_rise_v=0,keypulse=0,source_done=0,error=0;
    reg sd_card_write_req=0,sd_card_write_req_ack=0,frame_write_finish_pulse=0;
    wire sd_init_done=1;
    wire bmp_source_restart;
    wire bmp_load_done=source_done;
    wire scaler_start_tgl;
    wire scaler_commit_toggle=scaler_start_tgl;
    wire [1:0] write_buf_idx;
    wire [1:0] tr_mode_reg=1;
    wire bmp_display_commit_toggle,bmp_display_commit_pulse;
    wire [10:0] main_x=0;
    wire [9:0] main_y=0;
    wire tr_hold_load,tr_active,tr_fade_black;
    wire [7:0] tr_alpha;
    wire [9:0] tr_boundary;
    wire [1:0] tr_slide_axis;
    wire [20:0] page_a_base,page_b_base;
    `include "reg_source_gate_720.vh"
    `include "reg_display_commit_720.vh"
    wire loader_hold=display_submit_pending_sd | tr_hold_sync_sd[1];
    integer commits=0,prior,target,n,k;
    always @(posedge video_clk) if(!rst_video && commit_pulse_v) commits=commits+1;
    sd_card_bmp_g #(.EXACT_WIDTH(1280),.EXACT_HEIGHT(720)) loader(
        .clk(sd_card_clk),.rst(rst_sd),.key_next(1'b1),.key_auto(1'b1),.hold_load(loader_hold),
        .state_code(),.img_count(),.cur_img_w(),.cur_img_h(),.display_valid(),.source_restart(bmp_source_restart),
        .display_commit_toggle(bmp_display_commit_toggle),.display_commit_pulse(bmp_display_commit_pulse),
        .load_done(),.load_img_w(),.load_img_h(),.debug_status(),.write_finish_toggle(scaler_commit_toggle),
        .write_buf_idx(write_buf_idx),.disp_buf_idx(),.write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),
        .sd_init_done(1'b1),.sd_sec_read_abort(1'b0),.sd_sec_read(),.sd_sec_read_addr(),
        .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0));
    task start_load;
        begin
            @(negedge sd_card_clk);keypulse=1;@(negedge sd_card_clk);keypulse=0;
            n=0;while(!loader.load_busy) begin @(negedge sd_card_clk);n=n+1;if(n>30)$fatal(1,"FAIL key requests stopped");end
            target=write_buf_idx;prior=commits;repeat(8) @(negedge sd_card_clk);
        end
    endtask
    task handshake;
        begin
            @(negedge sd_card_clk);sd_card_write_req=1;
            repeat(5) @(negedge sd_card_clk);sd_card_write_req_ack=1;
            repeat(5) @(negedge sd_card_clk);sd_card_write_req=0;
            repeat(5) @(negedge sd_card_clk);sd_card_write_req_ack=0;
        end
    endtask
    task parsed;
        begin @(negedge sd_card_clk);source_done=1;@(negedge sd_card_clk);source_done=0;end
    endtask
    task written;
        begin @(negedge sd_card_clk);frame_write_finish_pulse=1;@(negedge sd_card_clk);frame_write_finish_pulse=0;end
    endtask
    task finish_transition;
        begin
            repeat(20) @(negedge video_clk);
            if(commits!=prior+1 || !loader_hold || !tr_hold_load || loader.load_busy) $fatal(1,"FAIL commit/hold exact once");
            n=0;
            while(tr_hold_load) begin
                @(negedge video_clk);vs_rise_v=1;@(negedge video_clk);vs_rise_v=0;
                n=n+1;if(n>40 || !loader_hold)$fatal(1,"FAIL early release/transition stalled");
            end
            repeat(10) @(negedge video_clk);
            if(loader_hold || page_a_base!=(target ? 21'h80000:21'd0))$fatal(1,"FAIL settled page");
        end
    endtask
    initial begin
        force loader.scan_done=1;force loader.scan_found_valid=0;force loader.bmp_ready=1;
        force loader.fs_scan_error=0;force loader.bmp_load_error=error;
        force loader.key_next_press=keypulse;force loader.load_done=source_done;
        repeat(4) @(negedge video_clk);rst_video=0;rst_sd=0;
        loader.scan_kicked=1;loader.first_image_committed=1;loader.display_valid=1;loader.img_found_count=7;loader.img_idx=0;
        for(k=0;k<40;k=k+1) begin
            start_load;
            // 未经新ACK的迟到完成必须忽略。
            written;handshake;
            if(k%3==0) begin parsed;repeat(8) @(negedge sd_card_clk);if(commits!=prior)$fatal(1,"FAIL parser bypassed writer");written;end
            else if(k%3==1) begin written;repeat(8) @(negedge sd_card_clk);if(commits!=prior)$fatal(1,"FAIL writer bypassed parser");parsed;end
            else begin
                @(negedge sd_card_clk);source_done=1;frame_write_finish_pulse=1;
                @(negedge sd_card_clk);source_done=0;frame_write_finish_pulse=0;
            end
            finish_transition;
        end
        start_load;handshake;written;
        @(negedge sd_card_clk);error=1;@(negedge sd_card_clk);error=0;
        repeat(20) @(negedge video_clk);
        if(commits!=prior || loader_hold)$fatal(1,"FAIL failed frame submitted");
        written;handshake;parsed;repeat(12) @(negedge sd_card_clk);
        if(commits!=prior)$fatal(1,"FAIL retry inherited stale writer");
        written;finish_transition;
        if(commits!=41)$fatal(1,"FAIL duplicate commit");
        $display("TB_COMMIT720 PASS 41 switches three completion orders failed_frame_blocked stale_writer_blocked");$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL current720 commit timeout");end
endmodule
