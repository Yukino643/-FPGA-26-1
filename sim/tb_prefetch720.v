`timescale 1ns/1ps
// 当前顶层的事务门、CDC及页释放原文；只模拟卡端/写端环境事件。
module tb_prefetch720;
    reg video_clk=0,sd_card_clk=0,rst_video=1,rst_sd=1;
    always #6.734 video_clk=~video_clk;
    always #5 sd_card_clk=~sd_card_clk;
    reg vs_rise_v=0,keypulse=0,source_done=0,error=0,key=1,autopulse=0;
    reg sd_card_write_req=0,sd_card_write_req_ack=0,frame_write_finish_pulse=0;
    reg sd_init_done=1,extra_hold=0;
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
    wire loader_hold=extra_hold | display_submit_pending_sd | tr_hold_sync_sd[1];
    integer commits=0,prior,target,n,k,prior_img,cycles,expected_idx,search;
    always @(posedge video_clk) if(!rst_video && commit_pulse_v) commits=commits+1;
    sd_card_bmp_g #(.CLK_FREQ_HZ(1000),.EXACT_WIDTH(1280),.EXACT_HEIGHT(720),.PREFETCH_NEXT(1)) loader(
        .clk(sd_card_clk),.rst(rst_sd),.key_next(key),.key_auto(1'b1),.hold_load(loader_hold),
        .state_code(),.img_count(),.cur_img_w(),.cur_img_h(),.display_valid(),.source_restart(bmp_source_restart),
        .display_commit_toggle(bmp_display_commit_toggle),.display_commit_pulse(bmp_display_commit_pulse),
        .load_done(),.load_img_w(),.load_img_h(),.debug_status(),.write_finish_toggle(scaler_commit_toggle),
        .write_buf_idx(write_buf_idx),.disp_buf_idx(),.write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),
        .sd_init_done(sd_init_done),.sd_sec_read_abort(1'b0),.sd_sec_read(),.sd_sec_read_addr(),
        .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0));
    task press;
        begin @(negedge sd_card_clk);keypulse=1;@(negedge sd_card_clk);keypulse=0;end
    endtask
    task start_load;
        begin
            n=0;while(!loader.load_busy) begin @(negedge sd_card_clk);n=n+1;if(n>30)$fatal(1,"FAIL prefetch did not start");end
            target=write_buf_idx;prior=commits;prior_img=loader.img_idx;
            expected_idx=(prior_img+1)%7;
            for(search=0;search<7;search=search+1)
                if(loader.failed_mask[expected_idx]) expected_idx=(expected_idx+1)%7;
            if(loader.first_image_committed && (target==loader.disp_buf_idx || loader.load_idx!=expected_idx))
                $fatal(1,"FAIL prefetch page/image target k=%0d image=%0d load=%0d page=%0d display=%0d bad=%h",k,prior_img,loader.load_idx,target,loader.disp_buf_idx,loader.failed_mask);
            repeat(8) @(negedge sd_card_clk);
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
    task complete;
        input integer order;
        begin
            // 新ACK前旧写完成不得继承。
            written;handshake;
            if(order==0) begin parsed;repeat(8) @(negedge sd_card_clk);if(commits!=prior || loader.prefetch_ready)$fatal(1,"FAIL source bypassed writer");written;end
            else if(order==1) begin written;repeat(8) @(negedge sd_card_clk);if(commits!=prior || loader.prefetch_ready)$fatal(1,"FAIL writer bypassed source");parsed;end
            else begin
                @(negedge sd_card_clk);source_done=1;frame_write_finish_pulse=1;
                @(negedge sd_card_clk);source_done=0;frame_write_finish_pulse=0;
            end
            repeat(12) @(negedge sd_card_clk);
        end
    endtask
    task ready_idle;
        begin
            if(!loader.prefetch_ready || loader.load_busy || commits!=prior || loader.img_idx!=prior_img || loader_hold)
                $fatal(1,"FAIL prefetch autonomously published");
            repeat(30) @(negedge video_clk);
            if(commits!=prior || !loader.prefetch_ready || write_buf_idx!=target)
                $fatal(1,"FAIL ready page not retained");
        end
    endtask
    task finish_transition;
        begin
            repeat(20) @(negedge video_clk);
            if(commits!=prior+1 || !loader_hold || !tr_hold_load || loader.load_busy) $fatal(1,"FAIL commit/hold exact once");
            n=0;
            while(tr_hold_load) begin
                if(loader.load_busy || write_buf_idx!=target || tr_fade_black)$fatal(1,"FAIL write during transition/black frame");
                @(negedge video_clk);vs_rise_v=1;@(negedge video_clk);vs_rise_v=0;
                n=n+1;if(n>40)$fatal(1,"FAIL transition stalled");
            end
            repeat(10) @(negedge video_clk);
            if(loader_hold || page_a_base!=(target ? 21'h80000:21'd0))$fatal(1,"FAIL settled page");
            if(loader.cur_img_w!=1280 || loader.cur_img_h!=720)$fatal(1,"FAIL cached dimensions");
        end
    endtask
    // 元数据用互不相同的位图，防止索引/宽mux选错仍被全零测试数据掩盖。
    always @(posedge sd_card_clk) begin
        if(!rst_sd && loader.load_start_pulse) begin
            if(loader.load_cluster !== (32'h10203000 + loader.load_idx) ||
               loader.load_file_size !== (32'h00ab4000 + loader.load_idx * 32'h101))
                $fatal(1,"FAIL metadata mismatch idx=%0d cluster=%h size=%h",loader.load_idx,loader.load_cluster,loader.load_file_size);
        end
    end
    initial begin
        force loader.scan_done=1;force loader.scan_found_valid=0;force loader.bmp_ready=1;
        force loader.fs_scan_error=0;force loader.bmp_load_error=error;
        force loader.key_next_press=keypulse;force loader.key_auto_press=autopulse;
        force loader.load_done=source_done;force loader.load_img_w=16'd1280;force loader.load_img_h=16'd720;
        force loader.img_cluster0=32'h10203000;force loader.img_size0=32'h00ab4000;
        force loader.img_cluster1=32'h10203001;force loader.img_size1=32'h00ab4101;
        force loader.img_cluster2=32'h10203002;force loader.img_size2=32'h00ab4202;
        force loader.img_cluster3=32'h10203003;force loader.img_size3=32'h00ab4303;
        force loader.img_cluster4=32'h10203004;force loader.img_size4=32'h00ab4404;
        force loader.img_cluster5=32'h10203005;force loader.img_size5=32'h00ab4505;
        force loader.img_cluster6=32'h10203006;force loader.img_size6=32'h00ab4606;
        repeat(4) @(negedge video_clk);rst_video=0;rst_sd=0;
        loader.scan_kicked=1;loader.img_found_count=7;
        // 首图不必按键，但仍须双完成与新ACK。
        start_load;complete(2);finish_transition;
        for(k=0;k<41;k=k+1) begin
            start_load;complete(k%3);ready_idle;
            press;
            repeat(2) @(negedge sd_card_clk);
            if(loader.next_req_count!=0 || loader.prefetch_ready)$fatal(1,"FAIL hot request not consumed promptly");
            finish_transition;
        end
        // 冷按键先排队，读完之前不能提交半帧。
        start_load;press;repeat(20) @(negedge sd_card_clk);
        if(loader.next_req_count!=1 || commits!=prior)$fatal(1,"FAIL cold request");
        complete(0);finish_transition;
        // 后台坏候选有界重试，两次失败均不能自行切图。
        start_load;handshake;written;
        @(negedge sd_card_clk);error=1;source_done=1;@(negedge sd_card_clk);error=0;source_done=0;
        repeat(8) @(negedge sd_card_clk);
        if(commits!=prior || loader.prefetch_ready || !loader.load_retry_used)$fatal(1,"FAIL retry priority");
        @(negedge sd_card_clk);error=1;@(negedge sd_card_clk);error=0;
        repeat(10) @(negedge sd_card_clk);
        if(commits!=prior || loader.prefetch_ready || loader.next_req_count!=0 || loader.failed_mask==0)
            $fatal(1,"FAIL failed prefetch manufactured request");
        // 修复环境后继续，不以坏图状态缩短测试循环。
        start_load;complete(1);ready_idle;
        loader.failed_mask=0;
        // 实际消抖器：CLK_FREQ_HZ缩比，20ms对应20拍。长按仅一次。
        release loader.key_next_press;key=0;cycles=0;
        while(!loader_hold) begin @(negedge sd_card_clk);cycles=cycles+1;if(cycles>30)$fatal(1,"FAIL hot physical key late");end
        if(cycles<20)$fatal(1,"FAIL debounce bypassed");
        repeat(35) @(negedge sd_card_clk);
        if(loader.next_req_count!=0)$fatal(1,"FAIL held key repeated");
        key=1;repeat(35) @(negedge sd_card_clk);finish_transition;
        force loader.key_next_press=keypulse;
        // 转场/外部占页期间300次按键饱和；同拍消费与新增抵消。
        start_load;complete(2);ready_idle;extra_hold=1;
        for(k=0;k<300;k=k+1) press;
        if(loader.next_req_count!=255 || commits!=prior)$fatal(1,"FAIL saturation/hold");
        @(negedge sd_card_clk);keypulse=1;extra_hold=0;
        @(negedge sd_card_clk);keypulse=0;
        if(loader.next_req_count!=255)$fatal(1,"FAIL concurrent enqueue/consume");
        finish_transition;
        for(k=0;k<255;k=k+1) begin start_load;complete(k%3);finish_transition;end
        if(loader.next_req_count!=0)$fatal(1,"FAIL saturation queue drain");
        start_load;complete(2);ready_idle;press;finish_transition;
        // 自动计时在冷预取时继续，到期只记请求；关闭后不遗留自动切图。
        start_load;
        @(negedge sd_card_clk);autopulse=1;@(negedge sd_card_clk);autopulse=0;
        repeat(2010) @(negedge sd_card_clk);
        if(!loader.auto_request_pending || commits!=prior)$fatal(1,"FAIL cold auto deadline");
        @(negedge sd_card_clk);autopulse=1;@(negedge sd_card_clk);autopulse=0;
        if(loader.auto_request_pending || loader.auto_play_en)$fatal(1,"FAIL disable auto pending");
        complete(2);ready_idle;
        // ready与自动关闭同拍不能发布；随后重新开启，自动到期才发布。
        @(negedge sd_card_clk);loader.auto_play_en=1;loader.auto_request_pending=1;autopulse=1;
        @(negedge sd_card_clk);autopulse=0;
        repeat(10) @(negedge sd_card_clk);if(commits!=prior)$fatal(1,"FAIL auto disable race");
        autopulse=1;@(negedge sd_card_clk);autopulse=0;
        repeat(2010) @(negedge sd_card_clk);finish_transition;
        // SD失效撤销缓存和请求；完成toggle历史不变，不能伪造新提交。
        start_load;complete(2); // 转场刚结束计时未到，保有缓存。
        extra_hold=1;prior=commits;
        sd_init_done=0;repeat(10) @(negedge sd_card_clk);
        if(loader.prefetch_ready || loader.next_req_count || loader.display_valid || commits!=prior)
            $fatal(1,"FAIL deinit retained prefetch");
        sd_init_done=1;extra_hold=0;
        @(negedge sd_card_clk);loader.scan_kicked=1;loader.img_found_count=7;
        start_load;complete(0);finish_transition;
        // 其他六张均失败时，自动到期仍可重载唯一好图，不得留下永久待请求。
        rst_sd=1;rst_video=1;repeat(5) @(negedge video_clk);rst_sd=0;rst_video=0;
        loader.scan_kicked=1;loader.img_found_count=7;loader.first_image_committed=1;
        loader.display_valid=1;loader.img_idx=0;loader.failed_mask=8'h7e;
        loader.auto_play_en=1;loader.auto_cnt=1999;
        start_load;
        if(loader.load_idx!=0 || !loader.auto_request_pending)$fatal(1,"FAIL unique-good auto recovery");
        complete(2);finish_transition;
        // 新增的元数据准备拍也属于事务；SD失效必须撤销尚未发出的启动。
        rst_sd=1;rst_video=1;repeat(5) @(negedge video_clk);rst_sd=0;rst_video=0;
        loader.scan_kicked=1;loader.img_found_count=7;
        wait(loader.load_select_pending);
        @(negedge sd_card_clk);sd_init_done=0;
        @(posedge sd_card_clk);#1;
        if(loader.load_start_pulse || bmp_source_restart || loader.load_busy)
            $fatal(1,"FAIL deinit launched pending metadata transaction");
        $display("TB_PREFETCH720 PASS first_image hot41 cold_request debounce_cycles=%0d saturated255 errors auto_cancel reinit unique_good_auto CDC_page_hold metadata deinit_pending",cycles);$finish;
    end
    initial begin #5000000;$fatal(1,"FAIL prefetch720 timeout");end
endmodule
