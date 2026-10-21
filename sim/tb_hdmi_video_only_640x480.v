`timescale 1ns/1ps
module tb_hdmi_video_only_640x480;
    reg clk=0, rst_n=0, hsync=0, vsync=0, de=0;
    reg [23:0] rgb=0;
    wire [9:0] ch0_symbol, ch1_symbol, ch2_symbol, clk_symbol;
    reg prev_de=0;
    reg [1:0] prev_control=0;
    reg [23:0] prev_rgb=0;
    integer disparity[0:2];
    integer i, channel, checks=0, random_seed=32'h124573;
    hdmi_video_only_640x480 dut(.*);
    always #5 clk=~clk;
    function [9:0] control_symbol(input [1:0] c);
        case(c)
            0: control_symbol=10'b1101010100;
            1: control_symbol=10'b0010101011;
            2: control_symbol=10'b0101010100;
            3: control_symbol=10'b1010101011;
        endcase
    endfunction
    // 独立逆变换验证像素；实际符号的1/0计数验证线路偏差。
    task check_channel(input integer ch, input [9:0] encoded, input [7:0] expected);
        reg [7:0] qm, decoded;
        integer k, ones, measured;
        begin
            if (!prev_de) begin
                if(encoded !== control_symbol(ch==0 ? prev_control : 2'b00))
                    $fatal(1,"control mismatch channel=%0d control=%b symbol=%b",ch,prev_control,encoded);
                disparity[ch]=0;
            end else begin
                qm=encoded[9] ? ~encoded[7:0] : encoded[7:0];
                decoded[0]=qm[0];
                for(k=1;k<8;k=k+1)
                    decoded[k]=encoded[8] ? (qm[k]^qm[k-1]) : ~(qm[k]^qm[k-1]);
                if(decoded !== expected)
                    $fatal(1,"pixel mismatch channel=%0d expected=%h decoded=%h",ch,expected,decoded);
                ones=0;
                for(k=0;k<10;k=k+1) ones=ones+encoded[k];
                disparity[ch]=disparity[ch]+2*ones-10;
                if(disparity[ch] < -8 || disparity[ch] > 8)
                    $fatal(1,"unbounded disparity channel=%0d value=%0d",ch,disparity[ch]);
            end
            case(ch)
                0: measured=$signed(dut.u_ch0.disparity);
                1: measured=$signed(dut.u_ch1.disparity);
                2: measured=$signed(dut.u_ch2.disparity);
            endcase
            if(measured !== disparity[ch]) $fatal(1,"disparity accounting mismatch channel=%0d",ch);
        end
    endtask
    task step(input reg en, input [1:0] ctrl, input [23:0] pixel);
        begin
            @(negedge clk); de=en; {vsync,hsync}=ctrl; rgb=pixel;
            @(posedge clk); #1;
            check_channel(0,ch0_symbol,prev_rgb[7:0]);
            check_channel(1,ch1_symbol,prev_rgb[15:8]);
            check_channel(2,ch2_symbol,prev_rgb[23:16]);
            if(clk_symbol !== 10'b0000011111) $fatal(1,"clock symbol mismatch");
            prev_de=en; prev_control=ctrl; prev_rgb=pixel;
            checks=checks+1;
        end
    endtask
    initial begin
        for(channel=0;channel<3;channel=channel+1) disparity[channel]=0;
        repeat(3) @(negedge clk);
        rst_n=1;
        for(i=0;i<4;i=i+1) step(0,i,0);
        for(i=0;i<256;i=i+1) step(1,0,{~i[7:0],(i[7:0]^8'h55),i[7:0]});
        for(i=0;i<4096;i=i+1) step((i%37)!=0,i%4,$random(random_seed));
        step(0,0,0); step(0,0,0);
        step(1,0,24'hffffff);
        @(negedge clk); rst_n=0; de=0; hsync=0; vsync=0; #1;
        if(ch0_symbol !== control_symbol(0) || dut.u_ch0.disparity !== 0)
            $fatal(1,"asynchronous reset mismatch");
        prev_de=0; prev_control=0;
        for(channel=0;channel<3;channel=channel+1) disparity[channel]=0;
        @(negedge clk); rst_n=1;
        step(1,0,24'h123456); step(0,0,0); step(0,0,0);
        $display("PASS tb_hdmi_video_only_640x480 pixels/control/reset/disparity checks=%0d",checks);
        $finish;
    end
endmodule
