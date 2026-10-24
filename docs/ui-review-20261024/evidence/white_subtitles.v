`timescale 1ns/1ps
module tb_review_white;
reg clk=0,rst=1; always #5 clk=~clk;
reg [10:0] x=0; reg [9:0] y=0; reg [4:0] cfg=9;
wire [23:0] rgb; integer preset,i,f;
osd_engine_720 dut(.I_clk(clk),.I_rst(rst),.I_vs_pulse(1'b0),.I_subtitle_cfg(cfg),
.I_x(x),.I_y(y),.I_bg_rgb(24'hffffff),.I_uptime_bcd(24'h123456),.I_mode(2'd1),
.I_clock_enable(1'b0),.I_text_enable(1'b0),.O_rgb(rgb));
initial begin
repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);
f=$fopen("D:/FPGA/code/example/build/ui-review-20261024/white_subtitles.rgb","wb");if(!f)$fatal(1,"FAIL open");
for(preset=0;preset<3;preset=preset+1)begin
@(negedge clk);cfg=9+2*preset;repeat(4)@(negedge clk);
// 仅取证夹具定格在正文完全可见位置，不代表产品新增暂停功能。
force dut.scroll_position=11'd1024;
for(i=664*1280;i<712*1280;i=i+1)begin
@(negedge clk);x=i%1280;y=i/1280;
@(posedge clk);#1;$fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);end
release dut.scroll_position;
end
$fclose(f);$display("REVIEW_WHITE_SUBTITLES PASS");$finish;end
endmodule
