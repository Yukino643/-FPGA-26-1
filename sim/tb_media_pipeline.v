`timescale 1ns/1ps
// 当前top原文：两解析器/共享FAT/writer/scaler/仲裁/完整720p读取/三域切换。
module tb_media_pipeline;
    parameter CASE=0;
    localparam RAW_VIDEO_MODE=0;
    reg sd_card_clk=0,ext_mem_clk=0,video_clk=0,rst_sd=1;
    always #5 sd_card_clk=~sd_card_clk;
    always #4 ext_mem_clk=~ext_mem_clk;
    always #6.734 video_clk=~video_clk;
    wire rst_mem=rst_sd,rst_video=rst_sd;
    wire sd_init_done=!rst_sd,Sdr_init_done=!rst_sd,Sdr_init_ref_vld=0;
    integer refresh_div=0;
    always @(posedge ext_mem_clk) if(rst_mem)refresh_div<=0;else refresh_div<=refresh_div==974?0:refresh_div+1;
    wire Sdr_busy=refresh_div<32;
    localparam [20:0] BUF0_ADDR=0,BUF1_ADDR=21'h80000,FRAME_PIXELS=460800;
    reg media_requested_sd=0,media_pause_requested_sd=0;
    wire media_rst_sd,media_rst_mem,media_rst_video,media_active_sd,media_busy_sd,media_hold_sd;
    wire media_drain_mem,media_blank_v,media_mode_v,media_pause_v,media_switch_v,media_source_idle,media_storage_idle;
    wire [7:0] media_error_sd;
    wire [15:0] media_frame_sd;
    wire [1:0] write_buf_idx,disp_buf_idx,tr_mode_reg=1;
    wire tr_hold_load,tr_active,tr_fade_black;
    wire [7:0] tr_alpha;
    wire [9:0] tr_boundary;
    wire [1:0] tr_slide_axis;
    wire [20:0] page_a_base,page_b_base;
    wire bmp_display_commit_toggle,bmp_display_commit_pulse,bmp_source_restart,bmp_load_done,bmp_wr_en;
    wire sd_card_write_req,display_valid;
    wire [23:0] bmp_wr_data,vout_data;
    wire [15:0] bmp_load_img_w,bmp_load_img_h,cur_img_w,cur_img_h;
    wire [3:0] img_count,state_code;
    wire [31:0] tf_bmp_debug;
    wire wav_index_found;
    wire [31:0] wav_index_sector;
    reg monitor_key_next_pulse_sd=0;
    wire monitor_key_auto_pulse_sd=0;
    wire [1:0] monitor_period_active_sd=0;
    wire sd_card_write_req_ack,frame_write_finish,App_wr_en;
    wire [20:0] App_wr_addr;
    wire [31:0] App_wr_din,packed_wr_data;
    wire [3:0] App_wr_dm;
    wire packed_wr_en,video_read_req_ack;
    reg frame_write_toggle_mem;
    wire bmp_sd_timeout,bmp_sd_sec_read,bmp_sd_sec_read_end,bmp_sd_sec_read_data_valid;
    wire [31:0] bmp_sd_sec_read_addr;
    wire [7:0] bmp_sd_sec_read_data;
    wire [31:0] transactions;
    wire wav_ready,wav_scan_done,wav_scan_found,wav_load_done,wav_load_active;
    wire [31:0] wav_scan_sector,wav_pcm_bytes,wav_sd_sec_read_addr;
    wire wav_sd_sec_read,wav_sd_sec_read_data_valid,wav_sd_sec_read_end,wav_sd_timeout;
    wire [7:0] wav_sd_sec_read_data;
    wire wav_pcm_valid,wav_fifo_full,wav_fifo_empty;
    wire [15:0] wav_pcm_left,wav_pcm_right;
    wire sd_phy_sec_read,sd_phy_sec_read_data_valid,sd_phy_sec_read_end,card_abort,sd_controller_reset;
    wire [31:0] sd_phy_sec_read_addr;
    wire [7:0] sd_phy_sec_read_data;
    wire [1:0] sd_owner;
    wire audio_valid,audio_sample_data_valid,audio_sample_tick;
    wire [23:0] audio_left_data,audio_right_data;
    wire signed [15:0] sync_dev_real;
    integer pcm_samples=0,audio_samples=0,wav_transactions=0,video_audio_start=0;
    reg audio_started=0;
    integer raw_written=0,raw_played=0,raw_frames=0,last_apply=0,switch_partial_commits=0;
    reg [15:0] audio_expected;
    always @(posedge sd_card_clk) if(media_rst_sd) raw_written=0;
    always @(posedge video_clk) if(media_rst_video) begin raw_played=0;audio_started=0;end
    wire App_rd_en,Sdr_rd_en;
    wire [20:0] App_rd_addr;
    wire [31:0] Sdr_rd_dout;
    wire vs,hs,main_de_al;
    wire [10:0] main_x;
    wire [9:0] main_y;
    reg vd=0,vs_toggle_r=0;
    wire vs_rise_v=vs && !vd;
    always @(posedge video_clk) if(rst_video)begin vd<=0;vs_toggle_r<=0;end
        else begin vd<=vs;if(vs_rise_v)vs_toggle_r<=~vs_toggle_r;end
    `include "reg_media_pipeline.vh"
    video_timing_gen #(.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
        .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.X_BITS(11),.Y_BITS(10)) timing(
        .I_clk(video_clk),.I_rst(rst_video),.O_hs(hs),.O_vs(vs),.O_de(main_de_al),.O_x(main_x),.O_y(main_y));
    media_card_model #(.CASE(CASE),.HOLD_REQ(0)) card(.clk(sd_card_clk),.rst(rst_sd),.req(sd_phy_sec_read),.addr(sd_phy_sec_read_addr),
        .data(sd_phy_sec_read_data),.valid(sd_phy_sec_read_data_valid),.done(sd_phy_sec_read_end),
        .abort(card_abort),.transactions(transactions));
    always @(posedge sd_card_clk) if(!rst_sd) begin
        if(card_abort || sd_controller_reset || wav_sd_timeout || bmp_sd_timeout)
            $fatal(1,"FAIL unexpected shared SD timeout/reset");
        if(sd_phy_sec_read && sd_owner==2)wav_transactions=wav_transactions+1;
        if(wav_pcm_valid) begin
            audio_expected=raw_written%9600;
            if(wav_fifo_full || (media_active_sd ?
                (CASE!=7 || wav_pcm_left!==audio_expected || wav_pcm_right!==~audio_expected) :
                (wav_pcm_left!==16'h1234 || wav_pcm_right!==16'h5678)))
                $fatal(1,"FAIL shared SD WAV PCM/full");
            pcm_samples=pcm_samples+1;
            if(media_active_sd)raw_written=raw_written+1;
        end
    end
    always @(negedge video_clk) if(!rst_video && audio_valid) begin
        if(audio_sample_data_valid) begin
            if(media_mode_v) begin
                if(CASE!=7 || audio_left_data[23:8]!==raw_played%9600 ||
                    audio_right_data[23:8]!==16'hffff-(raw_played%9600))
                    $fatal(1,"FAIL raw audio order index=%0d got=%h/%h",raw_played,audio_left_data,audio_right_data);
                if(media_pause_v)$fatal(1,"FAIL audio advanced while paused");
                raw_played=raw_played+1;
            end else if(audio_left_data!==24'h123400 || audio_right_data!==24'h567800)
                $fatal(1,"FAIL shared SD audio FIFO output");
            audio_started=1;audio_samples=audio_samples+1;
        end else if(audio_started && !media_busy_sd && !media_rst_video &&
                    (!media_mode_v || (video_audio_mode && !media_pause_v &&
                       u_audio_player.frame_running && u_audio_player.frame_samples<4800)))
            $fatal(1,"FAIL shared SD audio underflow after startup");
    end
    sdram_beh #(.LAT(12)) memory(.clk(ext_mem_clk),.rst(rst_mem),.wr_en(sdram_wr_en),.wr_addr(sdram_wr_addr),
        .wr_data(sdram_wr_din),.wr_dm(sdram_wr_dm),.rd_en(App_rd_en),.rd_addr(App_rd_addr),.rd_vld(Sdr_rd_en),.rd_dout(Sdr_rd_dout));
    function [15:0] source_pixel;
        input integer mode,f,px,py;
        integer offset;
        begin
            if(!mode)source_pixel=card.bmp_pixel(px,py);
            else begin offset=f*115200+((179-py)*320+px)*2;source_pixel={card.pixels[offset+1],card.pixels[offset]};end
        end
    endfunction
    function [23:0] color;
        input [15:0] p;
        begin color={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end
    endfunction
    // 独立逐像素参考；记录实际写入页的帧号，不用正在预取的frame_index代替显示帧号。
    integer page_frame[0:1];integer page_mode[0:1];
    integer source_words=0,dest_words=0,commits=0,applies=0,frame=0,checked_picture=0,checked_video=0;
    integer resets=0,sx,sy,i,j,source_frame=0,source_mode=0;
    reg source_complete=0,previous_reset=1;
    reg [31:0] expected_word;
    reg [23:0] expected[0:1];
    reg [1:0] check_pipe=0,mode_pipe=0;
    reg previous_vs=0;
    reg [20:0] previous_page=0;
    reg [31:0] previous_underflow=0;
    always @(posedge sd_card_clk) if(!rst_sd && !media_rst_sd) begin
        if(bmp_source_restart) begin source_words=0;dest_words=0;source_complete=0;source_mode=media_active_sd;source_frame=media_frame_sd;end
        if(bmp_load_done)source_complete=1;
        if(resize_error_mem)$fatal(1,"FAIL scaler error");
        if(bmp_display_commit_pulse) begin
            if(source_words!=28800 || dest_words!=460800)$fatal(1,"FAIL partial commit %0d/%0d",source_words,dest_words);
            commits=commits+1;
            $display("ready mode=%0d frame=%0d page=%0d time=%0t",media_active_sd,media_frame_sd,write_buf_idx,$time);
        end
    end
    always @(posedge ext_mem_clk) if(!rst_mem) begin
        if(media_rst_mem && !previous_reset) begin
            if(!media_drain_mem || !media_storage_idle || !media_blank_v || Sdr_rd_en)
                $fatal(1,"FAIL pipeline reset before all outstanding traffic drained");
            resets=resets+1;
        end
        previous_reset=media_rst_mem;
        if(!media_rst_mem) begin
            if(App_wr_en) begin
                sx=2*(source_words%160);sy=179-source_words/160;
                expected_word={source_pixel(source_mode,source_frame,sx+1,sy),source_pixel(source_mode,source_frame,sx,sy)};
                if(App_wr_addr!==21'h100000+source_words || App_wr_din!==expected_word || resize_busy_mem)
                    $fatal(1,"FAIL source data mode=%0d word=%0d got=%h exp=%h",source_mode,source_words,App_wr_din,expected_word);
                source_words=source_words+1;
            end
            if(resize_wr_en) begin
                sx=2*(dest_words%640);sy=dest_words/640;
                expected_word={source_pixel(source_mode,source_frame,(sx+1)/4,sy/4),source_pixel(source_mode,source_frame,sx/4,sy/4)};
                if(!source_complete || source_words!=28800 || resize_wr_data!==expected_word ||
                   resize_wr_addr!==(write_buf_idx[0]?BUF1_ADDR:BUF0_ADDR)+dest_words)
                    $fatal(1,"FAIL destination word=%0d addr=%h",dest_words,resize_wr_addr);
                if(display_visible_v && (retain_display_v || (media_mode_v && u_frame_commit.displayed)) && resize_wr_addr[19]==page_a_base[19])
                    $fatal(1,"FAIL overwrote displayed video page");
                dest_words=dest_words+1;
                if(dest_words==460800)begin page_frame[write_buf_idx[0]]=source_frame;page_mode[write_buf_idx[0]]=source_mode;end
            end
        end
    end else previous_reset=1;
    always @(posedge video_clk) begin
        if(rst_video) begin check_pipe=0;previous_page=0;previous_vs=0;previous_underflow=0;end
        else begin
            if(page_a_base!=previous_page && !previous_vs)$fatal(1,"FAIL page changed outside VS");
            previous_page=page_a_base;previous_vs=vs_rise_v;
            if(u_frame_commit.applied_pulse)begin
                applies=applies+1;
                if(CASE==7 && !media_switch_v && raw_played%4800!=0)
                    $fatal(1,"FAIL audio/video frame budget samples=%0d",raw_played);
                if(CASE==7 && media_switch_v && raw_played%4800!=0)
                    switch_partial_commits=switch_partial_commits+1;
                if(CASE==7)raw_frames=raw_frames+1;
                $display("applied %0d at VS %0d audio=%0d interval=%0d",applies,frame,raw_played,frame-last_apply);
                last_apply=frame;
            end
            if(vs_rise_v)frame=frame+1;
            expected[1]=expected[0];mode_pipe={mode_pipe[0],media_mode_v};
            check_pipe={check_pipe[0],main_de_al && display_visible_v && (!tr_active || retain_display_v)};
            expected[0]=color(source_pixel(page_mode[page_a_base[19]],page_frame[page_a_base[19]],main_x/4,main_y/4));
            if(display_visible_v && disp_underflow!=previous_underflow)
                $fatal(1,"FAIL visible underflow mode=%0d count=%0d",media_mode_v,disp_underflow);
            previous_underflow=disp_underflow;
            #1;
            if(mix_de && check_pipe[1]) begin
                if(mix_rgb!==expected[1])$fatal(1,"FAIL display pixel mode=%0d xy=%0d,%0d rgb=%h expected=%h",media_mode_v,mix_x,mix_y,mix_rgb,expected[1]);
                if(vout_data!==mix_rgb)$fatal(1,"FAIL retained output was blanked");
                if(mode_pipe[1])checked_video=checked_video+1;else checked_picture=checked_picture+1;
            end
        end
    end
    task wait_frames;
        input integer count;
        integer n;
        begin for(n=0;n<count;n=n+1)begin @(negedge video_clk);while(!vs_rise_v)@(negedge video_clk);@(negedge video_clk);end end
    endtask
    task wait_switch;
        input value;
        integer n;
        begin
            @(negedge sd_card_clk);media_requested_sd=value;
            n=0;while(!media_busy_sd)begin @(negedge sd_card_clk);n=n+1;if(n>50)$fatal(1,"FAIL no mode request");end
            n=0;while(media_busy_sd)begin @(negedge sd_card_clk);n=n+1;if(n>15000000)$fatal(1,"FAIL switch stuck state=%0d src=%0d pending=%0d resize=%0d",u_media_runtime.state,media_source_idle,display_submit_pending_sd,resize_busy_mem);end
            if(media_active_sd!=value || media_mode_v!=value)$fatal(1,"FAIL final mode");
        end
    endtask
    integer held_applies,target;
    reg held_page;
    initial begin
        #1;page_frame[0]=0;page_frame[1]=0;page_mode[0]=0;page_mode[1]=0;
        for(i=0;i<460800;i=i+1) begin memory.mem[i]=32'hbad0bad0;memory.mem[BUF1_ADDR+i]=32'hbad1bad1;end
        repeat(10)@(negedge sd_card_clk);rst_sd=0;
        wait(display_visible_v && !tr_active);wait_frames(2);
        if(checked_picture<921600 || !wav_index_found)$fatal(1,"FAIL initial picture/WAV candidate");
        wait_switch(1);
        video_audio_start=audio_samples;
        if(CASE==1 || CASE==2) begin
            wait(media_error_sd!=0);wait_frames(1);
            if(display_valid || u_frame_commit.displayed)$fatal(1,"FAIL error video published");
            wait_switch(0);wait(!retain_display_v && display_valid && !tr_active);wait_frames(2);
            if(!wav_index_found || checked_picture<2*921600 || audio_samples<=video_audio_start)
                $fatal(1,"FAIL failed-video return picture/WAV");
            $display("PASS media_pipeline error recovery CASE=%0d resets=%0d pixels=%0d",CASE,resets,checked_picture);$finish;
        end
        wait(applies>=3);wait_frames(1);
        if(checked_video<2*921600)$fatal(1,"FAIL video loop coverage");
        @(negedge sd_card_clk);media_pause_requested_sd=1;
        wait(media_pause_v);wait_frames(1);held_applies=applies;held_page=page_a_base[19];
        wait_frames(8);
        if(applies!=held_applies || page_a_base[19]!=held_page)$fatal(1,"FAIL pause page moved");
        @(negedge sd_card_clk);media_pause_requested_sd=0;
        target=applies+2;wait(applies>=target);
        @(negedge sd_card_clk);media_pause_requested_sd=1;
        wait(media_pause_v);wait(u_frame_commit.pending);
        // 带完整待提交页的暂停状态直接返回图片，不能死锁。
        wait_switch(0);media_pause_requested_sd=0;
        wait(!retain_display_v && display_valid && !tr_active);wait_frames(2);
        wait_switch(1);target=applies+3;wait(applies>=target);wait_frames(1);
        if(resets!=3 || !wav_index_found || audio_samples-video_audio_start<1000 || wav_transactions<100)
            $fatal(1,"FAIL switch/WAV competition count");
        if(CASE==7 && (raw_frames<8 || raw_played<9600))$fatal(1,"FAIL original track coverage");
        if(CASE==7 && switch_partial_commits!=1)$fatal(1,"FAIL partial-audio switching boundary not covered");
        $display("MEASURE shared SD WAV reads=%0d PCM=%0d audio=%0d zero post-start underflow",wav_transactions,pcm_samples,audio_samples);
        $display("PASS media_pipeline full 720p picture/video loop/pause/resume/paused return/reenter, pixels=%0d/%0d resets=%0d",checked_picture,checked_video,resets);$finish;
    end
    // 初图与返回图均保留完整32帧淡化，再覆盖两轮视频及暂停，旧1.6秒不足。
    initial begin #4000000000;$fatal(1,"FAIL integrated timeout mode=%0d state=%0d video=%0d err=%h",media_mode_v,u_media_runtime.state,u_media_source.video.state,media_error_sd);end
endmodule
