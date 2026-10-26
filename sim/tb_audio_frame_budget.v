`timescale 1ns/1ps
module tb_audio_frame_budget;
    reg sdclk=0,clk=0,rst=1,pause=0,ready=0;
    always #3 sdclk=~sdclk;
    always #5 clk=~clk;
    integer cyc=0,vs_count=0,written=0,played=0,applies=0,last_vs=0,n,held;
    wire full,empty,frame_done,buffer_ready,will_apply,applied,data_valid;
    wire [23:0] left,right;
    wire vs=(cyc%8000)==0; // 800samples/VS，10个pixel周期/sample。
    wire wr=!full && !rst;
    always @(posedge sdclk)if(!rst && wr)written<=written+1;
    audio_player #(.VIDEO_CLK_HZ(480000),.CONTROL_ENABLE(1)) player(
        .clk_sd(sdclk),.clk_video(clk),.rst_sd(rst),.rst_video(rst),.fifo_rst_sd(rst),.fifo_rst_video(rst),
        .consume_enable(!pause),.frame_mode(1'b1),.frame_start(will_apply),
        .frame_done(frame_done),.buffer_ready(buffer_ready),.pcm_valid(wr),
        .pcm_left(written[15:0]),.pcm_right(~written[15:0]),.vs_pulse(vs),
        .sample_data_valid(data_valid),.audio_left(left),.audio_right(right),.fifo_full(full),.fifo_empty(empty));
    video_frame_commit #(.PAUSE_ENABLE(1),.AUDIO_ENABLE(1)) commit(
        .clk(clk),.rst(rst),.vs_rise(vs),.pause(pause),.audio_mode(1'b1),
        .audio_ready(buffer_ready),.audio_frame_done(frame_done),.ready_pulse(ready),.ready_buf(2'd0),
        .will_apply(will_apply),.applied_pulse(applied));
    always @(posedge clk)begin
        if(!rst)begin
            cyc<=cyc+1;
            if(vs)vs_count<=vs_count+1;
        end
    end
    always @(negedge clk) if(!rst)begin
        if(data_valid)begin
            if(left[23:8]!==played[15:0] || right[23:8]!==~played[15:0])
                $fatal(1,"FAIL audio budget order sample=%0d got=%h",played,left);
            played=played+1;
        end
        if(applied)begin
            applies=applies+1;
            if(played%4800!=0)$fatal(1,"FAIL frame boundary sample=%0d",played);
            if(applies>1 && applies<5 && vs_count-last_vs!=6)
                $fatal(1,"FAIL added a 60Hz delay interval=%0d",vs_count-last_vs);
            last_vs=vs_count;
        end
    end
    task submit;
        begin @(negedge clk);ready=1;@(negedge clk);ready=0;end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=0;
        for(n=1;n<=4;n=n+1)begin submit;wait(applies==n);end
        wait(played>=14800);@(negedge clk);pause=1;held=played;
        repeat(10000)@(negedge clk);
        if(played!=held)$fatal(1,"FAIL pause consumed audio");
        pause=0;submit;wait(applies==5);
        wait(player.frame_samples==4800);@(negedge clk);#1;
        held=played;repeat(16000)@(negedge clk);
        if(played!=held || played!=24000)$fatal(1,"FAIL slow-video budget overrun");
        $display("PASS audio_frame_budget 4800 exact samples, 6VS cadence, pause/resume, slow frame hold");$finish;
    end
    initial begin #10000000;$fatal(1,"FAIL audio budget timeout played=%0d applies=%0d",played,applies);end
endmodule
