`timescale 1ns/1ps
// 真实采集、逐帧收敛、独立数学参考和实际光栅连通检查。
module tb_audio_waveform;
 wire a,b,c;
 tb_audio_waveform_case #(.RENDER(1)) t0(a);
 tb_audio_waveform_case #(.WAVE_X(0),.WAVE_Y(300),.WAVE_WIDTH(640),.WAVE_HEIGHT(128),.DECIMATE(3)) t1(b);
 tb_audio_waveform_case #(.WAVE_X(96),.WAVE_Y(250),.WAVE_WIDTH(32),.DECIMATE(1)) t2(c);
 initial begin wait(a&&b&&c);$display("TB_AUDIO_WAVEFORM PASS checks=%0d",t0.checks+t1.checks+t2.checks);$finish;end
 initial begin #100000000;$fatal(1,"FAIL waveform timeout");end
endmodule
module tb_audio_waveform_case #(
 parameter WAVE_X=64,WAVE_Y=376,WAVE_WIDTH=512,WAVE_HEIGHT=72,DECIMATE=4,RENDER=0
)(output reg done=0);
 localparam SPACING=WAVE_WIDTH/32,CENTER=WAVE_Y+WAVE_HEIGHT/2,LIMIT=WAVE_HEIGHT/2-2;
 localparam [23:0] BG=24'h876543;
 reg clk=0,rst=1,vs=0,de=0,enable=1,valid=0;
 reg [9:0] x=0;reg [8:0] y=0;reg signed [15:0] pcm=0;
 wire [23:0] rgb;wire active;
 integer samples[0:31],old_nodes[0:31],saved_bounds[0:WAVE_WIDTH-1];
 integer n,j,f,xx,yy,checks=0,cycles,top_y,bot_y,last_bot,last_top,first_y,last_y,visible,file;
 real ref0,ref1;integer rtop,rbot,target,error_old,error_new;
 always #5 clk=~clk;
 promax_audio_waveform #(.WAVE_X(WAVE_X),.WAVE_Y(WAVE_Y),.WAVE_WIDTH(WAVE_WIDTH),
 .WAVE_HEIGHT(WAVE_HEIGHT),.DECIMATE(DECIMATE)) dut(.clk(clk),.rst(rst),.vs_pulse(vs),.de(de),
 .enable(enable),.pixel_x(x),.pixel_y(y),.rgb_in(BG),.pcm_tap_valid(valid),.pcm_tap_left(pcm),.rgb_out(rgb),.waveform_active(active));
 task pixel;input integer px,py;
 begin @(negedge clk);x=px;y=py;@(posedge clk);#1;end endtask
 task frame;
 begin @(negedge clk);de=0;vs=1;@(negedge clk);vs=0;cycles=0;
 while(dut.build_state!=0)begin @(negedge clk);cycles=cycles+1;end
 if(cycles>WAVE_WIDTH+40)$fatal(1,"FAIL VS build deadline cycles=%0d",cycles);
 repeat(2)@(negedge clk);de=1;end endtask
 task pcm_word;input integer value;
 begin @(negedge clk);valid=1;pcm=value*256;@(negedge clk);valid=0;@(negedge clk);end endtask
 task capture;input integer first,count;integer i;
 begin for(i=0;i<count*DECIMATE;i=i+1)pcm_word(i%DECIMATE==0?samples[first+i/DECIMATE]:0);end endtask
 function real ideal_y;input integer column;integer i,i0,i2,i3;real t;
 begin i=column/SPACING;i0=i==0?0:i-1;i2=i==31?31:i+1;i3=i>=30?31:i+2;
 t=i==31?0.0:(column%SPACING)*1.0/SPACING;
 // 标准基函数校对定点 Horner 流水，容许两像素量化误差。
 ideal_y=CENTER-(((1-t)*(1-t)*(1-t)*$signed(dut.smooth_nodes[i0])+
 (3*t*t*t-6*t*t+4)*$signed(dut.smooth_nodes[i])+
 (-3*t*t*t+3*t*t+3*t+1)*$signed(dut.smooth_nodes[i2])+
 t*t*t*$signed(dut.smooth_nodes[i3]))/96.0);end endfunction
 task snapshot;begin for(j=0;j<WAVE_WIDTH;j=j+1)saved_bounds[j]=dut.curve_bounds[j];end endtask
 task check_curve;
 begin last_top=-1;last_bot=-1;
 for(xx=0;xx<WAVE_WIDTH;xx=xx+1)begin
 top_y=dut.curve_bounds[xx][8:0];bot_y=dut.curve_bounds[xx][17:9];
 ref0=ideal_y(xx);ref1=ideal_y(xx==WAVE_WIDTH-1?xx:xx+1);
 rtop=$rtoi(ref0<ref1?ref0:ref1)-1;rbot=$rtoi(ref0>ref1?ref0:ref1)+1;
 if(top_y<WAVE_Y || bot_y>=WAVE_Y+WAVE_HEIGHT || top_y>bot_y ||
 top_y-rtop>2 || rtop-top_y>2 || bot_y-rbot>2 || rbot-bot_y>2)
 $fatal(1,"FAIL curve numeric/range width=%0d x=%0d [%0d,%0d] ref=[%0d,%0d]",WAVE_WIDTH,xx,top_y,bot_y,rtop,rbot);
 first_y=-1;last_y=-1;visible=0;
 for(yy=WAVE_Y;yy<WAVE_Y+WAVE_HEIGHT;yy=yy+1)begin pixel(WAVE_X+xx,yy);
 if(rgb===24'h3bf0a5)begin if(first_y<0)first_y=yy;last_y=yy;visible=visible+1;end
 if(dut.curve_bounds[xx]!==saved_bounds[xx])$fatal(1,"FAIL curve mutated during display");end
 if(first_y!=top_y || last_y!=bot_y || visible!=bot_y-top_y+1)$fatal(1,"FAIL sync raster x=%0d",xx);
 if(xx>0 && (top_y>last_bot || bot_y<last_top))$fatal(1,"FAIL disconnected columns");
 last_top=top_y;last_bot=bot_y;checks=checks+1;end end endtask
 task converge;
 begin for(f=0;f<28;f=f+1)begin
 for(j=0;j<32;j=j+1)old_nodes[j]=$signed(dut.smooth_nodes[j]);frame;
 for(j=0;j<32;j=j+1)begin target=samples[j]*8;
 if(target>LIMIT*16)target=LIMIT*16;if(target< -LIMIT*16)target=-LIMIT*16;
 error_old=target-old_nodes[j];error_new=target-$signed(dut.smooth_nodes[j]);
 if((error_old>0 && (error_new<0 || error_new>error_old)) ||
 (error_old<0 && (error_new>0 || error_new<error_old)) ||
 ((error_old>=4 || error_old<=-4) && error_old==error_new))
 $fatal(1,"FAIL temporal smoothing frame=%0d node=%0d",f,j);end end
 for(j=0;j<32;j=j+1)begin target=samples[j]*8;
 if(target>LIMIT*16)target=LIMIT*16;if(target< -LIMIT*16)target=-LIMIT*16;
 error_new=target-$signed(dut.smooth_nodes[j]);
 if(error_new>3 || error_new< -3)$fatal(1,"FAIL temporal convergence");end end endtask
 task render;
 begin file=$fopen("waveform_continuous.ppm","w");if(!file)$fatal(1,"FAIL render open");
 $fwrite(file,"P3\n%0d %0d\n255\n",WAVE_WIDTH+48,WAVE_HEIGHT+16);
 for(yy=WAVE_Y-8;yy<WAVE_Y+WAVE_HEIGHT+8;yy=yy+1)
 for(xx=WAVE_X-16;xx<WAVE_X+WAVE_WIDTH+32;xx=xx+1)begin pixel(xx,yy);
 $fwrite(file,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);end
 $fclose(file);end endtask
 initial begin repeat(3)@(negedge clk);rst=0;de=1;
 pixel(WAVE_X,CENTER);if(rgb!==24'h2A4E58)$fatal(1,"FAIL unpublished RAM exposed");
 for(n=0;n<32;n=n+1)samples[n]=48;
 capture(0,25);frame;if(dut.display_valid || dut.capture_count!=25)$fatal(1,"FAIL incomplete publish");
 capture(25,7);pcm_word(-128);if(dut.capture_count!=32)$fatal(1,"FAIL full group overwritten");
 frame;if(!dut.display_valid || dut.display_bank!=0 || dut.write_bank!=1 || dut.display_peak!=48)$fatal(1,"FAIL group publish");
 if($signed(dut.smooth_nodes[0])!=96)$fatal(1,"FAIL first quarter step");
 frame;if($signed(dut.smooth_nodes[0])!=168)$fatal(1,"FAIL VS advance without group");
 converge;snapshot;check_curve;
 for(n=0;n<3*DECIMATE;n=n+1)pcm_word(-128);
 frame;if(dut.display_bank!=0 || dut.capture_count!=3)$fatal(1,"FAIL partial group changed bank");
 for(n=0;n<29*DECIMATE;n=n+1)pcm_word(-128);
 frame;if(dut.display_bank!=1 || dut.display_peak!=128)$fatal(1,"FAIL negative full-scale");
 for(n=0;n<32;n=n+1)samples[n]=-128;converge;snapshot;check_curve;
 for(n=0;n<32;n=n+1)samples[n]=127;capture(0,32);frame;converge;snapshot;check_curve;
 for(n=0;n<32;n=n+1)samples[n]=n%2?-128:127;capture(0,32);frame;converge;snapshot;check_curve;
 for(n=0;n<32;n=n+1)samples[n]=$rtoi(44.0*$sin(n*0.48)+18.0*$sin(n*1.12));
 capture(0,32);frame;converge;snapshot;check_curve;if(RENDER)render;
 // 峰值数据已发布，但波形外区域必须原样透传。
 for(yy=WAVE_Y;yy<WAVE_Y+WAVE_HEIGHT;yy=yy+1)begin
 pixel(WAVE_X+WAVE_WIDTH+8,yy);if(rgb!==BG || active)$fatal(1,"FAIL removed peak visible");end
 enable=0;pixel(WAVE_X,CENTER);if(rgb!==BG || active)$fatal(1,"FAIL disabled passthrough");
 enable=1;de=0;pixel(WAVE_X,CENTER);if(rgb!==BG || active)$fatal(1,"FAIL blanking passthrough");
 $display("TB_AUDIO_WAVEFORM width=%0d checks=%0d PASS",WAVE_WIDTH,checks);done=1;end
endmodule
