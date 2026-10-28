`timescale 1ns/1ps
module tb_audio720;
    reg vc=0,sc=0,rst=1,vs=0;
    always #6.734 vc=~vc;
    always #5 sc=~sc;
    wire tick,valid,data_valid;
    wire [31:0] sample_count,frames;
    wire signed [15:0] sync_dev;
    wire [23:0] l,r;
    audio_player #(.VIDEO_CLK_HZ(74250000),.NOMINAL_SAMPLES_PER_FRAME(800)) dut(
        .clk_sd(sc),.clk_video(vc),.rst_sd(rst),.rst_video(rst),.pcm_valid(1'b0),.pcm_left(16'd0),.pcm_right(16'd0),
        .vs_pulse(vs),.audio_valid(valid),.sample_data_valid(data_valid),.audio_left(l),.audio_right(r),
        .sync_dev(sync_dev),.sample_cnt(sample_count),.frame_cnt(frames),.sample_tick(tick),.fifo_empty(),.fifo_full());
    integer cycle=0,ticks=0,previous=0,spacing;
    always @(posedge vc) if(!rst) begin
        cycle=cycle+1;
        if(tick) begin
            spacing=cycle-previous;
            if(spacing!=1546 && spacing!=1547) $fatal(1,"FAIL audio720 cadence %d",spacing);
            previous=cycle;ticks=ticks+1;
        end
        #1;
        if(data_valid || l!=0 || r!=0) $fatal(1,"FAIL empty FIFO synthesized PCM");
        if(vs && dut.samples_in_frame!=1) $fatal(1,"FAIL VS/tick same-cycle new frame count");
        if(vs && frames>1 && sync_dev!=0) $fatal(1,"FAIL 720p frame sample rate %d",sync_dev);
    end
    integer frame;
    initial begin
        repeat(4) @(negedge vc);rst=0;
        for(frame=0;frame<3;frame=frame+1) begin
            repeat(1237499) @(negedge vc);
            vs=1;@(negedge vc);vs=0;
        end
        if(ticks!=2400 || sample_count!=2400 || frames!=3) $fatal(1,"FAIL 48k/60 exact count %d",ticks);
        $display("TB_AUDIO720 PASS 3 frames 2400 ticks intervals1546/1547 VS collision handled");$finish;
    end
endmodule
