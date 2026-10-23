`timescale 1ns/1ps
// 以1000拍代表1秒，独立测量真实管理器发布间隔；卡端/缩放耗时由环境模型提供。
module tb_autoplay_period #(parameter LEGACY_PRESETS=0);
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg [1:0] period_sel=0;
    reg next_event=0, auto_event=0;
    reg source_done=0, writer_toggle=0;
    wire publish;
    integer cycle=0, last_publish=-1, publish_count=0, failures=0;
    integer transition_left=0, read_left=0, resize_left=0;
    integer read_cost=200, resize_cost=250, transition_cost=200;
    integer samples=0, target_period=1000, previous=-1, delta, i, base, deadline;
    reg measure=0;
    integer minimum_period=LEGACY_PRESETS ? 1000 : 2000;
    wire transition_hold=(transition_left!=0);
    wire resize_hold=(resize_left!=0);

    sd_card_bmp_g #(.CLK_FREQ_HZ(1000),.PREFETCH_NEXT(1)) dut(
        .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
        .key_event_override(1'b1),.key_next_event(next_event),.key_auto_event(auto_event),
        .auto_period_sel(period_sel),.hold_load(transition_hold | resize_hold),
        .display_commit_pulse(publish),.write_finish_toggle(writer_toggle),
        .write_req_ack(1'b0),.sd_init_done(1'b1),.sd_sec_read_abort(1'b0),
        .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0));

    always @(posedge clk) begin
        cycle=cycle+1;
        if (!rst && publish) begin
            publish_count=publish_count+1;
            last_publish=cycle;
            if (measure) begin
                if (previous>=0) begin
                    delta=cycle-previous;
                    $display("PERIOD sel=%0d expected=%0d actual=%0d",period_sel,target_period,delta);
                    if (delta<target_period || delta>target_period+12) failures=failures+1;
                    samples=samples+1;
                end
                previous=cycle;
            end
            if (resize_hold || transition_hold)
                $fatal(1,"publication violated page ownership");
        end
    end

    // 后半拍更新环境，避免测试驱动与DUT采样竞争。提交锁住旧页；读完才缩放，缩放完才完成。
    always @(negedge clk) begin
        source_done=0;
        if (rst) begin
            transition_left=0;read_left=0;resize_left=0;writer_toggle=0;
        end else begin
            if (transition_left>0) transition_left=transition_left-1;
            if (read_left>0) begin
                read_left=read_left-1;
                if (read_left==0) resize_left=resize_cost;
            end else if (resize_left>0) begin
                resize_left=resize_left-1;
                if (resize_left==0) begin source_done=1;writer_toggle=~writer_toggle;end
            end
            if (dut.load_start_pulse) read_left=read_cost;
            if (last_publish==cycle) transition_left=transition_cost;
        end
    end

    task reset_case;
        input [1:0] sel;
        begin
            @(negedge clk);rst=1;auto_event=0;next_event=0;measure=0;previous=-1;samples=0;
            period_sel=sel;
            repeat(4) @(negedge clk);
            rst=0;
            dut.scan_kicked=1;dut.img_found_count=3;
            wait(dut.display_valid);
            repeat(2) @(negedge clk);
        end
    endtask
    task toggle_auto;
        begin @(negedge clk);auto_event=1;@(negedge clk);auto_event=0;end
    endtask
    task wait_publication;
        input integer old_count;
        input integer timeout_cycles;
        integer end_cycle;
        begin
            end_cycle=cycle+timeout_cycles;
            while(publish_count==old_count && cycle<end_cycle) @(negedge clk);
            if(publish_count==old_count) $fatal(1,"publication timeout sel=%0d count=%0d",period_sel,dut.auto_cnt);
        end
    endtask

    initial begin
        force dut.scan_done=1;force dut.scan_found_valid=0;force dut.bmp_ready=1;
        force dut.fs_scan_error=0;force dut.bmp_load_error=0;
        force dut.load_done=source_done;force dut.load_img_w=16'd1280;force dut.load_img_h=16'd720;
        for(i=0;i<4;i=i+1) begin
            read_cost=200;resize_cost=250;transition_cost=200;
            reset_case(i[1:0]);
            case(i) 0:target_period=minimum_period;1:target_period=LEGACY_PRESETS ? 2000 : 3000;2:target_period=5000;3:target_period=10000;endcase
            toggle_auto;measure=1;
            deadline=cycle+target_period*5+5000;
            while(samples<3 && cycle<deadline) @(negedge clk);
            if(samples!=3) $fatal(1,"insufficient cadence samples auto=%b count=%0d request=%b ready=%b busy=%b hold=%b commits=%0d",dut.auto_play_en,dut.auto_cnt,dut.auto_request_pending,dut.prefetch_ready,dut.load_busy,transition_hold | resize_hold,publish_count);
            measure=0;
        end
        // 额外模拟较长缩放：5秒档仍应5秒切图，不能叠加2.2秒缩放和0.55秒转场。
        read_cost=200;resize_cost=2200;transition_cost=550;
        reset_case(2);target_period=5000;toggle_auto;measure=1;
        deadline=cycle+40000;
        while(samples<3 && cycle<deadline) @(negedge clk);
        if(samples!=3) $fatal(1,"long resize cadence timeout");
        measure=0;
        if(failures) $fatal(1,"AUTO PERIOD REGRESSION: %0d intervals include hidden hold time",failures);

        // 10秒运行到3.5秒，改为最短档必须重新起算，不能错过比较后等32位回绕。
        read_cost=200;resize_cost=250;transition_cost=200;
        reset_case(3);toggle_auto;repeat(3500) @(negedge clk);
        period_sel=0;base=cycle;i=publish_count;
        wait_publication(i,minimum_period+100);
        if(last_publish-base<minimum_period || last_publish-base>minimum_period+12) $fatal(1,"period change did not restart timing");

        // 慢图超过两个周期，只保存一个待请求；计数饱和、不累计过期请求。
        read_cost=5200;resize_cost=300;transition_cost=200;
        reset_case(0);toggle_auto;
        repeat(minimum_period+100) @(negedge clk);
        if(!dut.auto_request_pending) $fatal(1,"missing cold deadline");
        base=dut.auto_cnt;
        repeat(100) @(negedge clk);
        if(dut.auto_cnt!=base) $fatal(1,"expired timer did not saturate");
        i=publish_count;wait_publication(i,4500);
        base=cycle;i=publish_count;
        repeat(minimum_period) @(negedge clk);
        if(publish_count!=i) $fatal(1,"late image manufactured catch-up publication");
        wait_publication(i,4000);
        if(last_publish-base<5700) $fatal(1,"slow path timing environment invalid");

        // 截止已过、页面还在缩放时关闭自动；就绪后不得泄漏自动提交。
        wait(dut.auto_request_pending);toggle_auto;i=publish_count;
        repeat(6000) @(negedge clk);
        if(dut.auto_play_en || dut.auto_request_pending || publish_count!=i) $fatal(1,"auto cancellation leaked request");

        // 就绪与关闭同拍；实际KEY关闭仍必须高于自动发布。
        wait(dut.prefetch_ready);
        @(negedge clk);dut.auto_play_en=1;dut.auto_request_pending=1;auto_event=1;
        @(negedge clk);auto_event=0;
        repeat(10) @(negedge clk);
        if(publish_count!=i) $fatal(1,"same-cycle disable published");

        // 手动切换重新起算；本周期不能随后跟着遗留自动请求连跳。
        read_cost=200;resize_cost=250;
        @(negedge clk);next_event=1;
        @(negedge clk);next_event=0;
        wait_publication(i,50);toggle_auto;i=publish_count;
        repeat(500) @(negedge clk);
        if(publish_count!=i) $fatal(1,"manual switch retained expired auto request");
        wait_publication(i,minimum_period);
        $display("TB_AUTOPLAY_PERIOD PASS four_presets hold resize late_saturation change disable manual");
        $finish;
    end
    initial begin #3000000;$fatal(1,"autoplay timing test timeout");end
endmodule
