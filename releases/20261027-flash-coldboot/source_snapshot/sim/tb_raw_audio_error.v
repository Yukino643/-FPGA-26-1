`timescale 1ns/1ps
// 独立扇区模型验证末拍错误脉冲与短读；错误不得输出残缺PCM。
module tb_raw_audio_error;
    reg clk=0,rst=1,start=0,valid=0,done=0,error=0;
    always #5 clk=~clk;
    wire req,quiet,pcm_valid;
    wire [7:0] load_error;
    integer trial,n;
    wav_read #(.RAW_ENABLE(1)) dut(
        .clk(clk),.rst(rst),.raw_mode(1'b1),.halt(1'b0),.raw_sector_error(error),
        .raw_start_sector(32'd451),.raw_sample_count(32'd9600),.quiescent(quiet),
        .load_error(load_error),.scan_start(1'b0),.scan_start_sector(32'd0),
        .load_start(start),.load_sector(32'd0),.sd_sec_read(req),
        .sd_sec_read_data(8'h55),.sd_sec_read_data_valid(valid),.sd_sec_read_end(done),
        .pcm_valid(pcm_valid),.pcm_ready(1'b1));
    always @(posedge clk) if(!rst && pcm_valid)$fatal(1,"FAIL corrupt sector emitted PCM");
    initial begin
        for(trial=0;trial<2;trial=trial+1)begin
            rst=1;repeat(4)@(negedge clk);rst=0;
            repeat(3)@(negedge clk);start=1;@(negedge clk);start=0;
            wait(req);@(negedge clk);
            for(n=0;n<(trial==0 ? 512:511);n=n+1)begin
                valid=1;@(negedge clk);
            end
            valid=0;done=1;error=(trial==0);
            @(negedge clk);done=0;error=0;
            wait(load_error!=0);
            if(load_error!=8'h61)$fatal(1,"FAIL sector error code %h",load_error);
            wait(quiet);repeat(10)@(negedge clk);
            if(req)$fatal(1,"FAIL corrupt sector retried silently");
        end
        $display("PASS raw_audio_error last-cycle error latch and short sector rejection");$finish;
    end
    initial begin #100000;$fatal(1,"FAIL error test timeout");end
endmodule
