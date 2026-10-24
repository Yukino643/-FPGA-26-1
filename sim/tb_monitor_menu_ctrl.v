`timescale 1ns/1ps
module tb_monitor_menu_ctrl;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg key_next=1, key_auto=1, key_emergency=1;
    reg emergency_active=0, ack_toggle=0;
    wire menu_active, menu_page, cfg_dirty, buzzer_test;
    wire [2:0] cursor;
    wire [1:0] period_shadow, period_active;
    wire [3:0] cfg_shadow, cfg_payload;
    wire screen_page, screen_edit, cfg_busy, audio_page;
    wire [9:0] screen_shadow, screen_payload;
    wire subtitle_page, subtitle_edit;
    wire [4:0] subtitle_shadow, subtitle_payload;
    integer n;
    reg old_toggle;
    wire cfg_toggle, next_pulse, auto_pulse;
    wire [2:0] key_state;
    wire [15:0] event_count;
    integer next_count=0, auto_count=0, beep_count=0;
    monitor_menu_ctrl #(.CLK_FREQ_HZ(1000), .DEBOUNCE_MS(2),
                        .LONG_PRESS_MS(10), .TEST_MS(40)) dut(
        .clk(clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),
        .key_emergency(key_emergency), .emergency_active(emergency_active),
        .cfg_commit_ack_toggle(ack_toggle), .menu_active(menu_active),
        .menu_page(menu_page), .cursor(cursor), .cfg_shadow(cfg_shadow),
        .cfg_payload(cfg_payload), .cfg_commit_toggle(cfg_toggle), .cfg_dirty(cfg_dirty),
        .period_shadow(period_shadow), .period_active(period_active),
        .audio_page(audio_page),
        .screen_page(screen_page), .screen_edit(screen_edit),
        .screen_shadow(screen_shadow), .screen_payload(screen_payload), .cfg_commit_busy(cfg_busy),
        .subtitle_page(subtitle_page), .subtitle_edit(subtitle_edit),
        .subtitle_shadow(subtitle_shadow), .subtitle_payload(subtitle_payload),
        .buzzer_test(buzzer_test), .key_state(key_state),
        .key_next_pulse(next_pulse), .key_auto_pulse(auto_pulse), .key_event_count(event_count));
    always @(negedge clk) begin
        if(next_pulse) next_count=next_count+1;
        if(auto_pulse) auto_count=auto_count+1;
        if(buzzer_test) beep_count=beep_count+1;
    end
    // 下降沿驱动，避免测试台与 DUT 的采样竞争。
    task press;
        input integer key_id, ticks;
        begin
            @(negedge clk);
            case(key_id) 2:key_next=0; 3:key_auto=0; 4:key_emergency=0; endcase
            repeat(ticks) @(negedge clk);
            case(key_id) 2:key_next=1; 3:key_auto=1; 4:key_emergency=1; endcase
            repeat(12) @(negedge clk);
        end
    endtask
    // 六条主卡离开路径均进入二级页：旧预览不能随导航或入口确认提交。
    task cancel_main_preview;
        input integer card, direction;
        reg saved_toggle;
        begin
            while(cursor != card) press(3,8);
            saved_toggle=cfg_toggle;
            press(4,8);
            if(!cfg_dirty || cfg_payload!==7 || period_active!==0)
                $fatal(1,"main card %0d preview isolation",card);
            if(card==4) begin
                if(period_shadow!==1) $fatal(1,"period preview missing");
            end else if(cfg_shadow!==(4'd7 ^ (4'd1 << card)))
                $fatal(1,"main card %0d preview missing",card);
            press(direction,8);
            if(cursor != ((direction==2) ? ((card+5)%6) : ((card+1)%6)) ||
               cfg_dirty || cfg_shadow!==7 || cfg_payload!==7 ||
               period_shadow!==0 || period_active!==0 || cfg_toggle!==saved_toggle)
                $fatal(1,"main card %0d direction %0d failed to cancel",card,direction);
            press(4,8);
            if(!(audio_page || screen_page || subtitle_page) || cfg_dirty ||
               cfg_payload!==7 || cfg_toggle!==saved_toggle)
                $fatal(1,"entry after navigation committed abandoned preview");
            press(2,30);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        if(!menu_active || menu_page || cfg_payload!==7) $fatal(1,"boot state");
        for(n=0;n<=4;n=n+2) begin
            cancel_main_preview(n,2);
            cancel_main_preview(n,3);
        end
        while(cursor!=0) press(3,8);
        press(4,8);
        if(!cfg_dirty || cfg_shadow!==6 || cfg_payload!==7) $fatal(1,"preview isolation");
        press(2,8);
        if(cursor!==5 || cfg_dirty || cfg_shadow!==7 || cfg_toggle)
            $fatal(1,"six-card previous wrap cancels preview");
        press(3,8);
        if(cursor!==0) $fatal(1,"next wrap");
        press(4,8);
        if(!cfg_dirty || cfg_shadow!==6 || cfg_payload!==7 || cfg_toggle)
            $fatal(1,"return to card must start fresh preview");
        press(4,8);
        if(!cfg_toggle || cfg_dirty || cfg_payload!==6) $fatal(1,"commit");
        // ACK 延迟时仍可预览，但不得改写在途正文或发第二笔提交。
        press(4,8);
        if(cfg_shadow!==7 || cfg_payload!==6 || !cfg_dirty) $fatal(1,"busy preview isolation");
        press(4,8);
        if(!cfg_toggle || cfg_payload!==6 || !cfg_dirty) $fatal(1,"busy second commit");
        press(3,8);
        if(cursor!==1 || cfg_dirty || cfg_shadow!==6 || cfg_payload!==6 || !cfg_busy || !cfg_toggle)
            $fatal(1,"busy navigation must preserve in-flight commit");
        press(2,8); press(4,8);
        if(!cfg_dirty || cfg_shadow!==7 || cfg_payload!==6)
            $fatal(1,"busy navigation must allow fresh preview");
        press(2,30);
        if(menu_active || cfg_dirty || cfg_shadow!==6 || cfg_payload!==6) $fatal(1,"exit pending");
        ack_toggle=cfg_toggle;
        press(2,8); press(3,8);
        if(next_count!=1 || auto_count!=1) $fatal(1,"playback short counts");
        press(3,30);
        if(!menu_active || menu_page || auto_count!=1 || cfg_shadow!==6) $fatal(1,"reenter suppression");
        press(2,8); press(2,8); press(4,8);
        if(period_shadow!==1 || period_active!==0 || !cfg_dirty) $fatal(1,"period preview");
        press(4,8);
        if(period_active!==1 || cfg_dirty) $fatal(1,"period commit");
        ack_toggle=cfg_toggle;
        press(4,8); press(2,30);
        if(menu_active || cfg_shadow!==6 || cfg_dirty || next_count!=1 || period_shadow!==period_active)
            $fatal(1,"cancel preview including period");
        press(3,30);
        // 从有未确认图层预览的主菜单进入屏幕页，不得误提交该预览。
        press(4,8); press(2,8); press(4,8);
        if(!screen_page || cursor!==0 || cfg_shadow!==6 || cfg_dirty || screen_shadow!==10'h144)
            $fatal(1,"screen entry cancels unrelated preview");
        press(4,8); press(3,8);
        if(!screen_edit || screen_shadow!==10'h145 || screen_payload!==10'h144) $fatal(1,"screen preview isolation");
        press(4,8);
        if(screen_edit || screen_payload!==10'h145 || !cfg_busy) $fatal(1,"screen commit");
        old_toggle=cfg_toggle;
        press(4,8); press(3,8); press(4,8);
        if(!screen_edit || cfg_toggle!==old_toggle || screen_payload!==10'h145 || screen_shadow!==10'h146)
            $fatal(1,"screen busy overwrote mailbox");
        press(2,30);
        if(!menu_active || !screen_page || screen_edit || screen_shadow!==10'h145) $fatal(1,"edit cancel navigation");
        ack_toggle=cfg_toggle;
        press(4,8);
        for(n=0;n<12;n=n+1) press(3,8);
        if(screen_shadow[3:0]!==8) $fatal(1,"brightness upper bound");
        for(n=0;n<12;n=n+1) press(2,8);
        if(screen_shadow[3:0]!==0) $fatal(1,"brightness lower bound");
        press(2,30);
        press(3,8); press(4,8);
        for(n=0;n<12;n=n+1) press(3,8);
        if(screen_shadow[7:4]!==8) $fatal(1,"contrast upper bound");
        for(n=0;n<12;n=n+1) press(2,8);
        if(screen_shadow[7:4]!==0) $fatal(1,"contrast lower bound");
        press(2,30); press(4,8); press(3,8); press(4,8);
        ack_toggle=cfg_toggle;
        if(screen_payload!==10'h155) $fatal(1,"contrast commit");
        press(3,8); press(4,8);
        for(n=0;n<4;n=n+1) press(3,8);
        if(screen_shadow[9:8]!==2) $fatal(1,"temperature upper bound");
        for(n=0;n<4;n=n+1) press(2,8);
        if(screen_shadow[9:8]!==0) $fatal(1,"temperature lower bound");
        press(3,8); press(3,8);
        old_toggle=cfg_toggle; press(4,30);
        if(!screen_edit || cfg_toggle!==old_toggle) $fatal(1,"screen emergency long emitted confirm");
        press(4,8); ack_toggle=cfg_toggle;
        if(screen_payload!==10'h255) $fatal(1,"temperature commit");
        press(3,8); press(4,8);
        if(!screen_edit || screen_shadow!==10'h144 || screen_payload!==10'h255) $fatal(1,"reset must preview");
        press(2,30);
        if(screen_shadow!==10'h255 || screen_edit) $fatal(1,"reset cancel");
        press(4,8); press(4,8); ack_toggle=cfg_toggle;
        if(screen_payload!==10'h144 || cfg_payload!==6 || screen_edit) $fatal(1,"reset only screen settings");
        press(2,30);
        if(screen_page || !menu_active || cursor!==5) $fatal(1,"screen returns to selected card");
        press(2,30);
        if(menu_active || next_count!=1 || auto_count!=1) $fatal(1,"hierarchical exit leaked key");
        press(3,30); press(3,30);
        if(!menu_page || auto_count!=1) $fatal(1,"page suppression");
        press(3,8);
        press(4,30);
        if(buzzer_test || beep_count!=0) $fatal(1,"KEY4 long emitted short");
        emergency_active=1;
        press(4,8);
        if(buzzer_test || beep_count!=0) $fatal(1,"emergency priority");
        emergency_active=0;
        press(4,8);
        if(!buzzer_test) $fatal(1,"beep start");
        repeat(45) @(negedge clk);
        if(buzzer_test || beep_count!=40) $fatal(1,"beep duration %0d",beep_count);
        if(next_count!=1 || auto_count!=1) $fatal(1,"menu leaked player events");
        // 字幕页保留六卡布局，取消/忙保护不能污染既有图片和色彩配置。
        press(3,30);
        repeat(3) press(3,8);
        press(4,8);
        if(!subtitle_page || cursor!==0 || subtitle_shadow!==5'h08) $fatal(1,"subtitle entry");
        press(4,8); press(3,8);
        if(!subtitle_edit || subtitle_shadow!==9 || subtitle_payload!==8) $fatal(1,"subtitle preview isolation");
        press(4,8);
        if(subtitle_edit || subtitle_payload!==9 || !cfg_busy) $fatal(1,"subtitle enable commit");
        old_toggle=cfg_toggle;
        press(3,8); press(4,8); press(3,8); press(4,8);
        if(!subtitle_edit || subtitle_payload!==9 || cfg_toggle!==old_toggle) $fatal(1,"subtitle busy overwrite");
        press(2,30); ack_toggle=cfg_toggle;
        if(subtitle_edit || subtitle_shadow!==9 || !subtitle_page) $fatal(1,"subtitle edit cancel");
        press(4,8); repeat(4) press(3,8);
        if(subtitle_shadow[2:1]!==2) $fatal(1,"preset upper bound");
        repeat(4) press(2,8);
        if(subtitle_shadow[2:1]!==0) $fatal(1,"preset lower bound");
        press(3,8); press(4,8); ack_toggle=cfg_toggle;
        if(subtitle_payload!==5'h0b) $fatal(1,"preset commit");
        press(3,8); press(4,8); repeat(4) press(3,8);
        if(subtitle_shadow[4:3]!==2) $fatal(1,"speed upper bound");
        repeat(4) press(2,8);
        if(subtitle_shadow[4:3]!==0) $fatal(1,"speed lower bound");
        repeat(2) press(3,8);
        old_toggle=cfg_toggle; press(4,30);
        if(!subtitle_edit || cfg_toggle!==old_toggle) $fatal(1,"subtitle long confirm suppression");
        press(4,8); ack_toggle=cfg_toggle;
        if(subtitle_payload!==5'h13) $fatal(1,"speed commit");
        press(3,8); press(4,8); press(3,8); press(4,8); ack_toggle=cfg_toggle;
        if(cfg_payload!==14 || screen_payload!==10'h144 || subtitle_payload!==5'h13) $fatal(1,"legacy layer atomicity");
        press(2,30);
        if(subtitle_page || !menu_active || cursor!==3) $fatal(1,"subtitle parent return");
        press(4,8); press(3,30);
        if(subtitle_page || menu_page || cursor!==0) $fatal(1,"subtitle KEY3 parent return");
        press(2,30);
        if(menu_active || next_count!=1 || auto_count!=1) $fatal(1,"subtitle exit event isolation");
        $display("TB_MONITOR_MENU_CTRL PASS"); $finish;
    end
    initial begin #200000; $fatal(1,"menu timeout"); end
endmodule
