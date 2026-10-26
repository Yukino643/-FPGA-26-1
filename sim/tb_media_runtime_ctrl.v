`timescale 1ns/1ps
module tb_media_runtime_ctrl;
    reg sd_clk=0,mem_clk=0,video_clk=0;
    always #5 sd_clk=~sd_clk;
    always #4 mem_clk=~mem_clk;
    always #7 video_clk=~video_clk;
    reg rst=1,request=0,pause=0,source_idle=0,pipeline_idle=0,storage_idle=0,vs=0;
    wire active,busy,hold_source,rs,rm,rv,drain,blank,mode,paused,switching;
    reg frame_ready=0;
    wire frame_pending,frame_applied;
    integer tick=0,changes=0,resets=0;
    reg previous_reset=0,previous_mode=0;
    media_runtime_ctrl dut(.sd_clk(sd_clk),.mem_clk(mem_clk),.video_clk(video_clk),
        .rst_sd(rst),.rst_mem(rst),.rst_video(rst),.requested_video(request),.requested_pause(pause),
        .source_idle(source_idle),.pipeline_idle(pipeline_idle),.storage_idle(storage_idle),.vs_rise(vs),
        .active_video(active),.busy(busy),.hold_source(hold_source),.media_rst_sd(rs),.media_rst_mem(rm),
        .media_rst_video(rv),.drain_mem(drain),.blank_video(blank),.video_mode(mode),.pause_video(paused),
        .switching_video(switching));
    // 模拟音频生产已停止且4800样本预算未满；只有切换收尾可绕过预算。
    video_frame_commit #(.PAUSE_ENABLE(1),.AUDIO_ENABLE(1)) commit(
        .clk(video_clk),.rst(rv|!mode),.vs_rise(vs),.pause(paused),
        .audio_mode(!switching),.audio_ready(1'b1),.audio_frame_done(1'b0),
        .ready_pulse(frame_ready),.ready_buf(2'd1),.hold_load(frame_pending),.applied_pulse(frame_applied));
    always @(negedge video_clk) begin tick=tick+1;vs=(tick%20==0);end
    always @(posedge mem_clk) if(!rst) begin
        if(rm && !previous_reset) begin
            if(!drain || !storage_idle || !blank) $fatal(1,"media reset before drain/blank");
            resets=resets+1;
        end
        previous_reset=rm;
    end else previous_reset=1;
    always @(posedge video_clk) begin
        #1;
        if(!rst && mode!=previous_mode) begin
            if(!blank) $fatal(1,"mode changed outside blank");
            changes=changes+1;
        end
        previous_mode=mode;
    end
    task wait_run;
        integer n;
        begin n=0;while(busy) begin @(negedge sd_clk);n=n+1;if(n>500)$fatal(1,"switch handshake deadlock state=%0d",dut.state);end end
    endtask
    task switch_to;
        input value;
        begin
            @(negedge sd_clk);source_idle=0;pipeline_idle=0;storage_idle=0;request=value;
            #1;if(!hold_source)$fatal(1,"new frame not held immediately");
            repeat(12) @(negedge sd_clk);
            if(!busy || blank || rs) $fatal(1,"did not wait for source");
            source_idle=1;
            repeat(12) @(negedge sd_clk);
            if(blank || rs)$fatal(1,"did not wait for pipeline");
            pipeline_idle=1;
            wait(drain);
            repeat(15) @(negedge sd_clk);
            if(rs || active!=!value)$fatal(1,"did not wait for memory");
            storage_idle=1;
            wait_run;
            if(active!=value || mode!=value || blank || drain || rs || rm || rv)
                $fatal(1,"switch final state");
        end
    endtask
    initial begin
        repeat(8) @(negedge sd_clk);rst=0;
        repeat(10) @(negedge sd_clk);
        switch_to(1);
        @(negedge video_clk);frame_ready=1;@(negedge video_clk);frame_ready=0;
        wait(frame_applied);
        pause=1;repeat(60) @(negedge video_clk);
        if(!paused)$fatal(1,"pause not applied");
        // 模拟暂停时完整页尚未提交：必须自动解除暂停，让原管线收尾。
        @(negedge video_clk);frame_ready=1;@(negedge video_clk);frame_ready=0;
        wait(frame_pending);
        source_idle=1;pipeline_idle=0;storage_idle=1;request=0;
        wait(!paused);wait(frame_applied);pipeline_idle=1;wait_run;
        if(mode || active)$fatal(1,"paused return failed");
        pause=0;switch_to(1);switch_to(0);switch_to(1);switch_to(0);
        if(resets!=6 || changes!=6)$fatal(1,"handshake counts %0d %0d",resets,changes);
        $display("PASS media_runtime_ctrl async clocks, drain, 6 switches, paused pending recovery");$finish;
    end
    initial begin #200000;$fatal(1,"runtime controller timeout");end
endmodule
