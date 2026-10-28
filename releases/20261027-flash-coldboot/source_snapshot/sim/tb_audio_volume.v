`timescale 1ns/1ps
// 独立整数参考：覆盖正负满幅、所有档位、静音恢复、有效资格、警笛旁路。
module tb_audio_volume;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg [4:0] volume_cfg=10;
    reg valid=0, data_valid=0, emergency=0, siren_valid=0;
    reg [23:0] left=0,right=0,siren_left=0,siren_right=0;
    wire out_valid,out_data_valid;
    wire [23:0] out_left,out_right;
    pcm_volume_control dut(.clk(clk),.rst(rst),.audio_config(volume_cfg),
        .in_valid(valid),.in_data_valid(data_valid),.in_left(left),.in_right(right),
        .emergency_mode(emergency),.siren_valid(siren_valid),.siren_left(siren_left),.siren_right(siren_right),
        .out_valid(out_valid),.out_data_valid(out_data_valid),.out_left(out_left),.out_right(out_right));
    integer gain=256, divider=0, target, expected_l,expected_r, checks=0;
    integer pending_l=0,pending_r=0;
    reg pending_valid=0,pending_data=0;
    integer lev,n,sl,sr;
    // 前一个上升沿记录的预期，在本拍输出端核对；不读取DUT增益寄存器。
    always @(posedge clk) begin
        if(rst) begin gain=256;divider=0;pending_valid=0;pending_data=0; end
        else begin
            expected_l=pending_l;expected_r=pending_r;
            #1;
            if(out_valid!==pending_valid || out_data_valid!==pending_data)
                $fatal(1,"valid/source qualification mismatch");
            if(pending_valid) begin
                if($signed(out_left)!==expected_l || $signed(out_right)!==expected_r)
                    $fatal(1,"stereo mismatch got=%0d/%0d expected=%0d/%0d",$signed(out_left),$signed(out_right),expected_l,expected_r);
                checks=checks+1;
            end
            pending_valid=emergency ? siren_valid : valid;
            pending_data=emergency ? siren_valid : (valid && data_valid);
            if(emergency) begin pending_l=$signed(siren_left);pending_r=$signed(siren_right);end
            else begin pending_l=$signed(left[23:8])*gain;pending_r=$signed(right[23:8])*gain;end
            target=volume_cfg[3:0]<=10 ? (volume_cfg[3:0]*256+5)/10 : 0;
            if(volume_cfg[4])target=0;
            if(valid) begin
                if(gain==target)divider=0;
                else begin
                    divider=divider+1;
                    if(divider==4)begin divider=0;gain=gain+((gain<target)?1:-1);end
                end
            end
        end
    end
    task sample;
        input integer l,r,real_data;
        begin
            @(negedge clk);valid=1;data_valid=real_data;left=l*256;right=r*256;
            siren_valid=emergency;siren_left=24'h934567;siren_right=24'h765432;
            @(negedge clk);valid=0;data_valid=0;siren_valid=0;
            repeat(2)@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;
        sample(-32768,32767,1);sample(-1,1,1);sample(0,0,0);
        for(lev=0;lev<=10;lev=lev+1)begin
            volume_cfg=lev;
            repeat(1030)sample(-32768,32767,1);
            for(n=0;n<40;n=n+1)begin
                sl=($random & 65535)-32768;sr=($random & 65535)-32768;
                sample(sl,sr,1);
            end
        end
        volume_cfg=5'h15;repeat(1030)sample(12345,-23456,1);
        if(gain!=0)$fatal(1,"mute did not settle");
        emergency=1;
        repeat(20)sample(32767,-32768,1);
        emergency=0;repeat(10)sample(32767,-32768,1);
        volume_cfg=5;repeat(1030)sample(12345,-23456,1);
        if(gain!=128)$fatal(1,"unmute did not restore 50 percent");
        volume_cfg=15;repeat(1030)sample(32767,-32768,1);
        if(gain!=0)$fatal(1,"invalid setting not muted");
        // 连续采样也不能串声道或丢valid；正常48kHz间隔更宽裕。
        @(negedge clk);volume_cfg=10;valid=1;data_valid=1;left=24'h800000;right=24'h7FFF00;
        repeat(1035)@(negedge clk);
        valid=0;data_valid=0;repeat(5)@(negedge clk);
        rst=1;repeat(3)@(negedge clk);rst=0;sample(-32768,32767,1);
        repeat(4)@(negedge clk);
        if(checks<15000)$fatal(1,"coverage %0d",checks);
        $display("TB_AUDIO_VOLUME PASS checked_samples=%0d all_levels stereo signs mute ramp siren validity reset",checks);$finish;
    end
    initial begin #2000000;$fatal(1,"volume timeout");end
endmodule
