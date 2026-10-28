`timescale 1ns/1ps
// 连续64个VS帧的实际OSD细条输出；Python另用独立位图参考逐像素比对。
module tb_subtitle_capture_segment;
    reg clk=0, rst=1, vs=0;
    always #5 clk=~clk;
    reg [10:0] x=0;
    reg [9:0] y=0;
    wire [23:0] rgb;
    integer f,n,xx,yy;
    osd_engine_720 dut(.I_clk(clk),.I_rst(rst),.I_vs_pulse(vs),
        .I_subtitle_cfg(5'd17),.I_x(x),.I_y(y),.I_bg_rgb(24'h84B6E8),
        .I_uptime_bcd(24'h123456),.I_mode(2'd1),.I_clock_enable(1'b1),
        .I_text_enable(1'b0),.O_rgb(rgb));
    task frame;
        begin @(negedge clk);vs=1;@(negedge clk);vs=0;end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);
        repeat(256)frame;
        f=$fopen("subtitle_segment.rgb","wb");
        if(!f)$fatal(1,"cannot open segment capture");
        for(n=0;n<64;n=n+1)begin
            if(n>0)frame;
            if(dut.scroll_position!==(512+2*n))$fatal(1,"segment VS position");
            for(yy=656;yy<720;yy=yy+1)
                for(xx=0;xx<1280;xx=xx+1)begin
                    @(negedge clk);x=xx;y=yy;
                    @(posedge clk);#1;
                    if(^rgb===1'bx)$fatal(1,"segment unknown RGB");
                    $fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                end
        end
        $fclose(f);$display("SUBTITLE_SEGMENT PASS frames=64 position=512..638 step=2");$finish;
    end
    initial begin #100000000;$fatal(1,"segment timeout");end
endmodule
