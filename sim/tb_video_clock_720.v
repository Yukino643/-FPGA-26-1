`timescale 1ns/100fs
module tb_video_clock_720;
    reg clk=0, reset=1;
    always #10 clk=~clk;
    wire ref27, lock27, pixel, serial, lock_video;
    ref27_pll u_ref(.refclk(clk), .reset(reset), .clk0_out(ref27), .extlock(lock27));
    video_pll u_video(.refclk(ref27), .reset(reset || !lock27), .clk0_out(pixel),
                     .clk1_out(serial), .extlock(lock_video));
    // 这里只替代无延迟时钟缓冲；PLL 频率及锁定采用安路官方功能模型。
    realtime first_pixel, last_pixel, first_serial, last_serial;
    integer i;
    initial begin
        #200 reset=0;
        wait(lock_video);
        repeat(100) @(posedge pixel);
        @(posedge pixel); first_pixel=$realtime;
        for(i=0;i<1000;i=i+1) @(posedge pixel);
        last_pixel=$realtime;
        @(posedge serial); first_serial=$realtime;
        for(i=0;i<5000;i=i+1) @(posedge serial);
        last_serial=$realtime;
        if ((last_pixel-first_pixel)<13467.5 || (last_pixel-first_pixel)>13468.5)
            $fatal(1,"FAIL pixel clock period total %f",last_pixel-first_pixel);
        if ((last_serial-first_serial)<13467.5 || (last_serial-first_serial)>13468.5)
            $fatal(1,"FAIL serial clock period total %f",last_serial-first_serial);
        $display("TB_VIDEO_CLOCK_720 PASS pixel=74.25MHz serial=371.25MHz");
        $finish;
    end
    initial begin #1000000; $fatal(1,"FAIL PLL lock timeout"); end
endmodule
module EG_LOGIC_BUFG(input wire i, output wire o);
    assign o=i;
endmodule
