`timescale 1ns/1ps
module tb_media_menu;
    reg clk=0,rst=1,k2=1,k3=1,k4=1,busy=0;
    always #5 clk=~clk;
    wire menu,page,media,edit,shadow,mode,pause,next_event,auto_event;
    wire [2:0] cursor;
    integer next_count=0,auto_count=0;
    monitor_menu_ctrl #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(2),.LONG_PRESS_MS(10),.ENABLE_MEDIA(1)) dut(
        .clk(clk),.rst(rst),.key_next(k2),.key_auto(k3),.key_emergency(k4),.emergency_active(1'b0),
        .cfg_commit_ack_toggle(1'b0),.media_busy(busy),.media_page(media),.media_edit(edit),
        .media_shadow(shadow),.requested_video(mode),.requested_pause(pause),.menu_active(menu),
        .menu_page(page),.cursor(cursor),.key_next_pulse(next_event),.key_auto_pulse(auto_event));
    always @(negedge clk) begin if(next_event)next_count=next_count+1;if(auto_event)auto_count=auto_count+1;end
    task press;
        input integer key_id,ticks;
        begin
            @(negedge clk);case(key_id)2:k2=0;3:k3=0;4:k4=0;endcase
            repeat(ticks) @(negedge clk);
            case(key_id)2:k2=1;3:k3=1;4:k4=1;endcase
            repeat(12) @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=0;repeat(10) @(negedge clk);
        if(!menu || page || media || mode)$fatal(1,"boot compatibility");
        press(3,30);if(page || !media || auto_count)$fatal(1,"direct media page");
        press(2,8);if(cursor!=3)$fatal(1,"media previous wrap");
        press(3,8);if(cursor!=0)$fatal(1,"media next wrap");
        press(3,30);if(page || media)$fatal(1,"direct program page");
        press(3,30);if(page || !media || cursor)$fatal(1,"media page");
        press(4,8);press(3,8);
        if(!edit || !shadow || mode)$fatal(1,"mode preview isolation");
        press(2,30);if(edit || shadow || mode || !media)$fatal(1,"mode cancel");
        press(4,8);press(3,8);press(4,8);
        if(edit || !mode || pause)$fatal(1,"mode confirm");
        busy=1;press(3,8);press(4,8);if(pause)$fatal(1,"busy pause blocked");
        busy=0;press(4,8);if(!pause)$fatal(1,"pause card");
        press(4,30);if(!pause || !mode)$fatal(1,"emergency long leaked short");
        press(4,8);if(pause)$fatal(1,"resume card");
        press(2,30);if(menu)$fatal(1,"exit menu");
        press(2,8);press(3,8);if(next_count || auto_count || !pause)$fatal(1,"video player keys");
        press(3,30);if(!menu || page || media || !pause)$fatal(1,"reenter short suppression");
        press(3,30);
        press(4,8);press(2,8);press(4,8);
        if(mode || pause)$fatal(1,"return picture clears pause");
        press(3,30);if(media || page)$fatal(1,"two page cycle");
        press(2,30);press(2,8);press(3,8);
        if(next_count!=1 || auto_count!=1)$fatal(1,"picture keys restored");
        $display("PASS media_menu real debounce/short/long, preview, cancel, busy, mode, pause, original keys");$finish;
    end
endmodule
