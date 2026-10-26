`timescale 1ns/1ps
// 原轨解析、碎片簇链、循环顺序、背压和在途收尾，不依赖视频像素参考。
module tb_media_audio;
    reg clk=0,rst=1,start=0,halt=0;
    always #5 clk=~clk;
    wire ready,quiet,req,valid,done,error,idle,physical_req;
    wire [31:0] sector,addr;
    wire [7:0] data,physical_data,load_error;
    wire physical_valid,physical_done,physical_error;
    wire pcm_valid;
    wire [15:0] left,right;
    integer cycles=0,samples=0;
    wire pcm_ready=(cycles%13)<5;
    wav_read #(.RAW_ENABLE(1)) reader(.clk(clk),.rst(rst),.raw_mode(1'b1),.halt(halt),
        .raw_sector_error(error),.raw_start_sector(32'd451),.raw_sample_count(32'd9600),
        .quiescent(quiet),.load_error(load_error),.ready(ready),.scan_start(1'b0),.scan_start_sector(32'd0),
        .load_start(start),.load_sector(32'd0),.sd_sec_read(req),.sd_sec_read_addr(sector),
        .sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(done),
        .pcm_valid(pcm_valid),.pcm_left(left),.pcm_right(right),.pcm_ready(pcm_ready));
    media_audio_router router(.clk(clk),.rst(rst),.video_mode(1'b1),.metadata_ready(!rst),
        .first_cluster(32'd4),.file_size(32'd269312),.fat_lba(32'd1),.data_lba(32'd5),
        .max_cluster(32'd64),.spc(8'd64),.spc_shift(3'd6),
        .reader_req(req),.reader_sector(sector),.reader_data(data),.reader_valid(valid),
        .reader_done(done),.reader_error(error),.idle(idle),.physical_req(physical_req),.physical_addr(addr),
        .physical_data(physical_data),.physical_valid(physical_valid),.physical_done(physical_done),
        .physical_error(1'b0));
    media_card_model #(.CASE(7),.BYTE_CYCLES(1)) card(.clk(clk),.rst(rst),.req(physical_req),.addr(addr),
        .data(physical_data),.valid(physical_valid),.done(physical_done));
    reg [15:0] expected;
    always @(posedge clk) if(!rst)begin
        cycles=cycles+1;
        if(load_error)$fatal(1,"FAIL original audio load error %h",load_error);
        if(pcm_valid)begin
            expected=samples%9600;
            if(left!==expected || right!==~expected)$fatal(1,"FAIL raw PCM sample=%0d got=%h/%h",samples,left,right);
            samples=samples+1;
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst=0;
        repeat(5)@(negedge clk);start=1;@(negedge clk);start=0;
        wait(samples>=20000);
        wait(physical_req && card.idx>50);
        @(negedge clk);halt=1;
        if(quiet)$fatal(1,"FAIL in-flight audio claimed idle");
        wait(quiet && idle);
        repeat(10)@(negedge clk);
        if(physical_req || req || pcm_valid)$fatal(1,"FAIL audio request after halt");
        $display("PASS media_audio fragmented FAT tail + 2 loops + backpressure + in-flight halt samples=%0d",samples);
        $finish;
    end
    initial begin #50000000;$fatal(1,"FAIL media audio timeout");end
endmodule
