`timescale 1ns/1ps
module tb_raw_video #(parameter CASE=0);
    reg clk=0,rst=1,hold_load=0,finish=0,ack=0;
    always #5 clk=~clk;
    wire req,valid,sd_done,abort,wr,px,restart,loaded,commit,dvalid;
    wire [7:0] data,error;
    wire [31:0] addr,cycles;
    wire [23:0] rgb;
    wire [1:0] writebuf;
    wire [15:0] frameidx;
    wire [3:0] state;
    wire [31:0] transactions;
    integer count=0,commits=0,release_count=0,scale_delay=0;
    reg [15:0] p;
    reg [23:0] expected;
    raw_video_player #(.CLK_FREQ_HZ(100000)) dut(.clk(clk),.rst(rst),.sd_init_done(!rst),.sd_abort(abort),
        .hold_load(hold_load),.write_finish_toggle(finish),.write_req_ack(ack),.state_code(state),.debug_status(),
        .display_valid(dvalid),.display_commit_toggle(),.display_commit_pulse(commit),.write_buf_idx(writebuf),.disp_buf_idx(),
        .source_restart(restart),.load_done(loaded),.write_req(wr),.pixel_valid(px),.pixel_rgb(rgb),
        .sd_req(req),.sd_addr(addr),.sd_data(data),.sd_valid(valid),.sd_done(sd_done),
        .error_code(error),.frame_index(frameidx),.read_cycles_last(cycles));
    raw_video_card_model #(.CASE(CASE)) card(.clk(clk),.rst(rst),.req(req),.addr(addr),
        .data(data),.valid(valid),.done(sd_done),.abort(abort),.transactions(transactions));
    always @(negedge clk) if(!rst) begin
        ack=wr;
        if(restart) count=0;
        if(px) begin
            p={card.pixels[frameidx*115200+2*count+1],card.pixels[frameidx*115200+2*count]};
            expected={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};
            if(count>=57600 || rgb!==expected) $fatal(1,"FAIL RGB565 frame=%d pixel=%d got=%h expected=%h",frameidx,count,rgb,expected);
            count=count+1;
        end
        if(loaded) begin
            if(count!=57600) $fatal(1,"FAIL source incomplete %d",count);
            scale_delay=100;
            $display("source frame=%0d read_cycles=%0d at 100MHz",frameidx,cycles);
        end
        if(scale_delay>0) begin scale_delay=scale_delay-1;if(scale_delay==0) finish=~finish;end
        if(commit) begin
            if(CASE!=0 || count!=57600 || writebuf!=(commits%2) || frameidx!=(commits%2)) $fatal(1,"FAIL partial/order commit");
            commits=commits+1;hold_load=1;release_count=40;
        end
        if(release_count>0) begin release_count=release_count-1;if(release_count==0) hold_load=0;end
        if(error!=0) begin
            if(CASE==0 || commits!=0 || loaded) $fatal(1,"FAIL unexpected error/partial publish %h",error);
            if((CASE==1 && error!=8'h42)||(CASE==2 && error!=8'h44)||(CASE==3 && error!=8'h52)||
               (CASE==4 && error!=8'h51)||(CASE==5 && error!=8'h40)||(CASE==6 && error!=8'h43))
                $fatal(1,"FAIL incorrect error %h case%d",error,CASE);
            repeat(20) @(negedge clk);
            if(commit || loaded || wr) $fatal(1,"FAIL failed player still publishing");
            $display("PASS raw_video rejected case=%0d error=%h without partial commit",CASE,error);$finish;
        end
        if(commits==3) begin
            $display("PASS raw_video exact RGB565, fragmented FAT32, 2 frames + wrap, page hold, SPI byte cadence transactions=%d",transactions);$finish;
        end
    end
    initial begin repeat(5) @(negedge clk);rst=0;end
    initial begin #180000000;$fatal(1,"FAIL raw video timeout state%d err%h count%d",state,error,count);end
endmodule
