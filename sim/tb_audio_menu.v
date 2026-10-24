`timescale 1ns/1ps
// 两个异步时钟下测试真实按键分类、邮箱忙保护、VS提交、取消和页面返回。
module tb_audio_menu;
    reg clk=0,vclk=0,rst=1;
    always #5 clk=~clk;
    always #7 vclk=~vclk;
    reg k2=1,k3=1,k4=1,vs=0;
    wire active,page,audio_page,audio_edit,screen_page,subtitle_page,dirty,toggle;
    wire [2:0] cursor;
    wire [3:0] shadow,payload,cfg_active,cfg_preview;
    wire [4:0] ashadow,apayload,aactive,apreview;
    wire [9:0] sshadow,spayload;
    wire [4:0] tshadow,tpayload;
    wire ack;
    reg [2:0] ack_sync=0;
    wire busy;
    wire next_pulse,auto_pulse;
    integer next_count=0,auto_count=0,n;
    reg old_toggle;
    monitor_menu_ctrl #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(2),.LONG_PRESS_MS(10)) menu(
        .clk(clk),.rst(rst),.key_next(k2),.key_auto(k3),.key_emergency(k4),.emergency_active(1'b0),
        .cfg_commit_ack_toggle(ack_sync[2]),.menu_active(active),.menu_page(page),.cursor(cursor),
        .cfg_shadow(shadow),.cfg_payload(payload),.audio_page(audio_page),.audio_edit(audio_edit),
        .audio_shadow(ashadow),.audio_payload(apayload),.screen_page(screen_page),
        .screen_shadow(sshadow),.screen_payload(spayload),.subtitle_page(subtitle_page),
        .subtitle_shadow(tshadow),.subtitle_payload(tpayload),.cfg_commit_toggle(toggle),
        .cfg_dirty(dirty),.cfg_commit_busy(busy),.key_next_pulse(next_pulse),.key_auto_pulse(auto_pulse));
    monitor_config_regs cfg(.video_clk(vclk),.video_rst(rst),.vs_rise(vs),
        .cfg_shadow_sd(shadow),.cfg_payload_sd(payload),.audio_shadow_sd(ashadow),.audio_payload_sd(apayload),
        .screen_shadow_sd(sshadow),.screen_payload_sd(spayload),
        .subtitle_shadow_sd(tshadow),.subtitle_payload_sd(tpayload),.cfg_commit_toggle_sd(toggle),
        .cfg_active_video(cfg_active),.cfg_preview_video(cfg_preview),
        .audio_active_video(aactive),.audio_preview_video(apreview),.cfg_applied_toggle_video(ack));
    always @(posedge clk)if(rst)ack_sync<=0;else ack_sync<={ack_sync[1:0],ack};
    always @(negedge clk)begin
        if(next_pulse)next_count=next_count+1;
        if(auto_pulse)auto_count=auto_count+1;
    end
    task press;
        input integer id,ticks;
        begin
            @(negedge clk);case(id)2:k2=0;3:k3=0;4:k4=0;endcase
            repeat(ticks)@(negedge clk);
            case(id)2:k2=1;3:k3=1;4:k4=1;endcase
            repeat(12)@(negedge clk);
        end
    endtask
    task frame;
        begin
            repeat(8)@(negedge vclk);vs=1;@(negedge vclk);vs=0;
            repeat(8)@(negedge clk);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=0;
        // 真实异步邮箱：移开仅取消预览，在途提交必须仍等 VS 生效。
        press(4,8); press(3,8);
        if(cursor!==1 || dirty || shadow!==7 || payload!==7 || toggle || cfg_active!==7)
            $fatal(1,"unconfirmed image preview survived navigation");
        press(3,8); press(4,8);
        if(cursor!==2 || !dirty || shadow!==3 || payload!==7 || cfg_active!==7)
            $fatal(1,"new card must preview its own setting");
        press(2,8); press(2,8); press(4,8); press(4,8);
        if(!busy || payload!==6 || cfg_active!==7) $fatal(1,"image commit must await VS");
        old_toggle=toggle;
        press(4,8); press(3,8); press(3,8);
        if(cursor!==2 || dirty || shadow!==6 || payload!==6 || toggle!==old_toggle || !busy || cfg_active!==7)
            $fatal(1,"busy navigation changed mailbox or active setting");
        frame;
        if(cfg_active!==6 || busy) $fatal(1,"navigation canceled an already confirmed image setting");
        press(4,8);
        if(!dirty || shadow!==2 || payload!==6 || cfg_active!==6)
            $fatal(1,"time card reused abandoned image preview");
        press(2,8); press(2,8); press(4,8); press(4,8); frame;
        if(cfg_active!==7 || busy || dirty) $fatal(1,"restore image after navigation");
        press(3,8);press(4,8);
        if(!audio_page || cursor!=0 || ashadow!==10 || payload!==7)$fatal(1,"audio entry/default");
        press(4,8);press(2,8);
        if(!audio_edit || ashadow!==9 || apayload!==10 || aactive!==10)$fatal(1,"volume preview");
        press(4,8);
        if(audio_edit || apayload!==9 || !busy || aactive!==10)$fatal(1,"volume awaiting frame");
        old_toggle=toggle;press(4,8);press(2,8);press(4,8);
        if(!audio_edit || ashadow!==8 || apayload!==9 || toggle!==old_toggle)$fatal(1,"busy isolation");
        frame;
        if(aactive!==9 || busy)$fatal(1,"async VS/ACK");
        press(2,30);
        if(!audio_page || audio_edit || ashadow!==9)$fatal(1,"cancel stays page");
        press(4,8);repeat(15)press(2,8);
        if(ashadow[3:0]!==0)$fatal(1,"lower bound");
        repeat(15)press(3,8);
        if(ashadow[3:0]!==10)$fatal(1,"upper bound");
        press(2,30);press(3,8);press(4,8);press(3,8);press(4,8);
        if(apayload!==5'h19 || aactive!==9)$fatal(1,"mute retains volume");
        frame;if(aactive!==5'h19)$fatal(1,"mute commit");
        press(3,8);press(4,8);press(2,8);press(4,8);frame;
        if(cfg_active!==5 || aactive!==5'h19)$fatal(1,"wave independent");
        press(3,8);press(4,8);
        if(ashadow!==10 || shadow!==7 || apayload!==5'h19 || payload!==5)$fatal(1,"reset preview");
        press(2,30);
        if(ashadow!==5'h19 || shadow!==5 || audio_edit)$fatal(1,"reset cancel");
        press(4,8);press(4,8);frame;
        if(aactive!==10 || cfg_active!==7 || spayload!==10'h144 || tpayload!==8)$fatal(1,"reset scope");
        press(2,30);
        if(audio_page || cursor!==1 || !active)$fatal(1,"parent focus");
        press(4,8);press(2,8);if(cursor!==3)$fatal(1,"four card wrap");
        press(3,8);if(cursor!==0)$fatal(1,"four card forward wrap");
        press(4,8);old_toggle=toggle;press(4,30);
        if(!audio_edit || toggle!==old_toggle)$fatal(1,"long KEY4 confirmed");
        press(3,30);
        if(audio_page || audio_edit || page || cursor!==0 || dirty)$fatal(1,"long KEY3 parent/cancel");
        press(2,30);if(active)$fatal(1,"exit to player");
        press(2,8);press(3,8);
        if(next_count!=1 || auto_count!=1)$fatal(1,"player keys leaked");
        press(3,30);if(!active || auto_count!=1)$fatal(1,"reentry suppression");
        $display("TB_AUDIO_MENU PASS async mailbox preview commit cancel bounds mute wave reset page longpress");$finish;
    end
    initial begin #100000;$fatal(1,"audio menu timeout");end
endmodule
