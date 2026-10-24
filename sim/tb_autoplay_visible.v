`timescale 1ns/1ps
// 真实顶层的CDC、整页完成门和转场实例；缩比时钟下测量可见转场起点间隔。
module tb_autoplay_visible;
    reg video_clk=0,sd_card_clk=0,rst_video=1,rst_sd=1;
    always #6.734 video_clk=~video_clk;
    always #5 sd_card_clk=~sd_card_clk;
    reg vs_rise_v=0,source_done=0,auto_event=0;
    reg sd_card_write_req=0,sd_card_write_req_ack=0,frame_write_finish_pulse=0;
    reg sd_init_done=1;
    reg [1:0] resize_busy_sync_sd=0,period_sel=0;
    wire bmp_source_restart,scaler_start_tgl;
    wire bmp_load_done=source_done;
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
    wire loader_hold=display_submit_pending_sd | tr_hold_sync_sd[1] | resize_busy_sync_sd[1];
    integer cycle=0,frame_phase=0,read_left=0,resize_left=0;
    integer starts=0,intervals=0,previous_start=-1,last_start=-1;
    integer target_period=2000,delta,selection,limit,old_starts,changed_at;
    reg previous_active=0,measure=0;

    // 74.25MHz/60Hz在1000 SD拍/秒的缩比下为每12.375个视频周期一帧。
    always @(negedge video_clk) begin
        if(rst_video) begin frame_phase=0;vs_rise_v=0;end
        else begin
            frame_phase=frame_phase+8;
            if(frame_phase>=99) begin frame_phase=frame_phase-99;vs_rise_v=1;end
            else vs_rise_v=0;
        end
    end
    always @(posedge sd_card_clk) cycle=cycle+1;
    always @(posedge video_clk) begin
        #1;
        if(rst_video) previous_active=0;
        else begin
            if(tr_active && !previous_active) begin
                starts=starts+1;last_start=cycle;
                if(measure && previous_start>=0) begin
                    delta=cycle-previous_start;
                    $display("VISIBLE preset=%0d target_cycles=%0d actual_cycles=%0d model_seconds=%0.6f",period_sel,target_period,delta,delta/1000.0);
                    if(delta<target_period-20 || delta>target_period+20)
                        $fatal(1,"visible transition cadence outside one-frame tolerance");
                    intervals=intervals+1;
                end
                previous_start=cycle;
            end
            previous_active=tr_active;
        end
    end

    sd_card_bmp_g #(.CLK_FREQ_HZ(1000),.PREFETCH_NEXT(1)) loader(
        .clk(sd_card_clk),.rst(rst_sd),.key_next(1'b1),.key_auto(1'b1),
        .key_event_override(1'b1),.key_next_event(1'b0),.key_auto_event(auto_event),
        .auto_period_sel(period_sel),.hold_load(loader_hold),
        .source_restart(bmp_source_restart),.display_commit_toggle(bmp_display_commit_toggle),
        .display_commit_pulse(bmp_display_commit_pulse),.write_finish_toggle(scaler_commit_toggle),
        .write_buf_idx(write_buf_idx),.write_req_ack(1'b0),.sd_init_done(sd_init_done),
        .sd_sec_read_abort(1'b0),.sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0));

    // 保留真实req/ACK和源/目标完成事件，仅把读卡及缩放环境耗时缩比为200/250拍。
    always @(negedge sd_card_clk) begin
        source_done=0;frame_write_finish_pulse=0;
        if(rst_sd) begin
            read_left=0;resize_left=0;resize_busy_sync_sd=0;
            sd_card_write_req=0;sd_card_write_req_ack=0;
        end else begin
            if(read_left>0) begin
                read_left=read_left-1;
                if(read_left==195)sd_card_write_req=1;
                if(read_left==190)sd_card_write_req_ack=1;
                if(read_left==185)sd_card_write_req=0;
                if(read_left==180)sd_card_write_req_ack=0;
                if(read_left==0)begin source_done=1;resize_left=250;resize_busy_sync_sd=3;end
            end else if(resize_left>0) begin
                resize_left=resize_left-1;
                if(resize_left==0)begin resize_busy_sync_sd=0;frame_write_finish_pulse=1;end
            end
            if(loader.load_start_pulse)read_left=200;
        end
    end
    task toggle_auto;
        begin @(negedge sd_card_clk);auto_event=1;@(negedge sd_card_clk);auto_event=0;end
    endtask
    task wait_start;
        input integer old;
        input integer timeout_cycles;
        integer end_cycle;
        begin
            end_cycle=cycle+timeout_cycles;
            while(starts==old && cycle<end_cycle)@(negedge sd_card_clk);
            if(starts==old)$fatal(1,"visible transition timeout");
        end
    endtask
    initial begin
        force loader.scan_done=1;force loader.scan_found_valid=0;force loader.bmp_ready=1;
        force loader.fs_scan_error=0;force loader.bmp_load_error=0;
        force loader.load_done=source_done;force loader.load_img_w=16'd1280;force loader.load_img_h=16'd720;
        for(selection=0;selection<4;selection=selection+1)begin
            @(negedge sd_card_clk);rst_sd=1;rst_video=1;measure=0;auto_event=0;
            repeat(5)@(negedge video_clk);
            @(negedge sd_card_clk);period_sel=selection;rst_sd=0;rst_video=0;
            loader.scan_kicked=1;loader.img_found_count=3;
            previous_start=-1;intervals=0;
            case(selection)0:target_period=2000;1:target_period=3000;2:target_period=5000;3:target_period=10000;endcase
            wait(loader.display_valid);wait(!loader_hold);toggle_auto;measure=1;
            limit=cycle+target_period*5+2000;
            while(intervals<3 && cycle<limit)@(negedge sd_card_clk);
            if(intervals!=3)$fatal(1,"missing visible period samples");
            measure=0;
        end
        // 自动保持开启，依次切换2/3/5/10秒。确认后的首个转场也必须按新周期到达。
        for(selection=0;selection<4;selection=selection+1)begin
            wait(!loader_hold);
            @(negedge sd_card_clk);period_sel=selection;changed_at=cycle;old_starts=starts;
            case(selection)0:target_period=2000;1:target_period=3000;2:target_period=5000;3:target_period=10000;endcase
            wait_start(old_starts,target_period+50);
            delta=last_start-changed_at;
            $display("VISIBLE_CHANGE preset=%0d target_cycles=%0d actual_cycles=%0d",selection,target_period,delta);
            if(delta<target_period || delta>target_period+22)$fatal(1,"visible config change timing");
        end
        $display("TB_AUTOPLAY_VISIBLE PASS four_presets 12_intervals 4_live_changes real_top_CDC_transition");
        $finish;
    end
    initial begin #3000000;$fatal(1,"visible period timeout");end
endmodule
