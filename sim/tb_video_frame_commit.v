`timescale 1ns/1ps
module tb_video_frame_commit;
    reg clk=0,rst=1,vs=0,ready=0;
    reg [1:0] bufidx=0;
    wire [20:0] page;
    wire hold_load,displayed,applied;
    integer k;
    video_frame_commit dut(.clk(clk),.rst(rst),.vs_rise(vs),.ready_pulse(ready),
        .ready_buf(bufidx),.page_base(page),.hold_load(hold_load),.displayed(displayed),.applied_pulse(applied));
    always #5 clk=~clk;
    task tick_vs;
        begin @(negedge clk);vs=1;@(negedge clk);vs=0;end
    endtask
    task submit;
        input [1:0] value;
        begin @(negedge clk);bufidx=value;ready=1;@(negedge clk);ready=0;
            if(!hold_load) $fatal(1,"FAIL mailbox not held");end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=0;
        submit(1);repeat(10) @(negedge clk);
        if(page!=0 || displayed) $fatal(1,"FAIL mid-frame first commit");
        tick_vs();if(page!=21'h80000 || !displayed || hold_load || !applied) $fatal(1,"FAIL first commit");
        submit(0);
        for(k=1;k<6;k=k+1) begin tick_vs();if(page!=21'h80000 || !hold_load) $fatal(1,"FAIL early frame %d",k);end
        tick_vs();if(page!=0 || hold_load) $fatal(1,"FAIL six VS cadence");
        repeat(12) tick_vs(); // 慢帧保持，不积压补帧。
        submit(1);tick_vs();if(page!=21'h80000) $fatal(1,"FAIL late frame");
        submit(0);repeat(5) tick_vs();if(page!=21'h80000) $fatal(1,"FAIL catch-up");
        tick_vs();if(page!=0) $fatal(1,"FAIL cadence after late frame");
        @(negedge clk);rst=1;@(negedge clk);
        if(displayed || hold_load || page!=0) $fatal(1,"FAIL reset");
        $display("PASS video_frame_commit first/6VS/late/no catch-up/reset");$finish;
    end
endmodule
