`timescale 1ns/1ps
// 独立屏幕空间参考：字索引/区域/色彩不从DUT命中或地址信号推导。
module tb_subtitle720;
    // 文案定向回归可关闭大体积整圈栅格导出，逐VS状态/边界检查始终执行。
    parameter integer CAPTURE_CYCLE_PIXELS=1;
    reg clk=0, rst=1, vs=0;
    always #5 clk=~clk;
    reg [10:0] x=0;
    reg [9:0] y=0;
    reg [4:0] cfg=5'h08;
    reg clock_enable=0, text_enable=0;
    reg [23:0] bg=24'h84B6E8, uptime=24'h123456;
    reg [1:0] mode=1;
    wire [23:0] rgb;
    osd_engine_720 dut(.I_clk(clk),.I_rst(rst),.I_vs_pulse(vs),.I_subtitle_cfg(cfg),
        .I_x(x),.I_y(y),.I_bg_rgb(bg),.I_uptime_bcd(uptime),
        .I_mode(mode),.I_clock_enable(clock_enable),.I_text_enable(text_enable),.O_rgb(rgb));
    reg [31:0] font [0:2047];
    integer cells [0:255];
    integer title_cells [0:13];
    integer mode_cells [0:3];
    integer digit_cells [0:9];
    integer i,j,px,py,preset,speed,combo,background_case,phase,steps,increment;
    integer trace,cycle_dump,capture_index,cycle_frames,old_phase,blank_steps,cycle_no=0;
    integer sentence_width;
    integer dump,frame_count=0,checks=0,source,col,glyph,row,cell_col,part;
    reg hit,plate;
    reg [23:0] expected,ink;
    reg [31:0] bits;
    task frame;
        begin
            @(negedge clk); vs=1;
            @(negedge clk); vs=0;
            frame_count=frame_count+1;
        end
    endtask
    task configure;
        input [4:0] value;
        begin
            @(negedge clk); x=0; y=0; cfg=value;
            repeat(3) @(negedge clk);
        end
    endtask
    task check_pixel;
        input integer xx,yy,offset;
        begin
            @(negedge clk); x=xx; y=yy;
            expected=bg; hit=0; glyph=0; row=0; col=0; ink=24'hF2FAFF;
            plate=(text_enable && yy>=16 && yy<64 &&
                   ((xx>=16 && xx<496) || (xx>=1104 && xx<1264))) ||
                  (clock_enable && xx>=880 && xx<1264 && yy>=664 && yy<712) ||
                  (cfg[0] && xx>=16 && xx<1264 && yy>=664 && yy<712);
            if(plate) expected={2'b0,bg[23:18],2'b0,bg[15:10],2'b0,bg[7:2]};
            if(cfg[0] && xx>=16 && xx<112 && yy>=664 && yy<712) expected=24'h0E3A4C;
            if(text_enable && yy>=24 && yy<56) begin
                if(xx>=32 && xx<480) begin
                    hit=1; glyph=title_cells[(xx-32)/32]; col=(xx-32)%32; row=yy-24;
                end else if(xx>=1120 && xx<1248) begin
                    hit=1; glyph=mode_cells[(xx-1120)/32]; col=(xx-1120)%32; row=yy-24; ink=24'h8FD5FA;
                    if(mode==2 && xx<1184) glyph=(xx<1152) ? 18 : 19;
                end
            end
            if(clock_enable && xx>=896 && xx<1248 && yy>=672 && yy<704) begin
                hit=1; cell_col=(xx-896)/32; col=(xx-896)%32; row=yy-672; ink=24'hC9DBE5;
                case(cell_col)
                    0:glyph=20; 1:glyph=21; 2:glyph=0;
                    3:glyph=digit_cells[uptime[23:20]];
                    4:glyph=digit_cells[uptime[19:16]];
                    5,8:glyph=23;
                    6:glyph=digit_cells[uptime[15:12]];
                    7:glyph=digit_cells[uptime[11:8]];
                    9:glyph=digit_cells[uptime[7:4]];
                    10:glyph=digit_cells[uptime[3:0]];
                endcase
            end
            if(cfg[0] && yy>=672 && yy<704) begin
                if(xx>=32 && xx<96) begin
                    hit=1; glyph=(xx<64) ? 58 : 59; col=(xx-32)%32; row=yy-672;
                end else if(xx>=128 && xx<(clock_enable ? 864 : 1152)) begin
                    source=(xx+(clock_enable ? 1184 : 896)+offset)%2048;
                    hit=1; glyph=cells[cfg[2:1]*64+source/32]; col=source%32; row=yy-672;
                end
            end
            bits=font[glyph*32+row];
            if(hit && bits[31-col]) expected=ink;
            if(cfg[0] && xx>=16 && xx<1264 && yy>=664 && yy<666) expected=24'h38BDF8;
            @(posedge clk); #1;
            checks=checks+1;
            if(rgb!==expected) $fatal(1,"OSD xy=%0d,%0d cfg=%h TC=%b%b phase=%0d bg=%h got=%h expected=%h glyph=%0d row=%0d col=%0d",xx,yy,cfg,text_enable,clock_enable,offset,bg,rgb,expected,glyph,row,col);
        end
    endtask
    task check_edges;
        input integer offset;
        begin
            check_pixel(15,687,offset); check_pixel(16,687,offset);
            check_pixel(31,687,offset); check_pixel(32,687,offset);
            check_pixel(95,687,offset); check_pixel(96,687,offset);
            check_pixel(111,687,offset); check_pixel(112,687,offset);
            check_pixel(127,687,offset); check_pixel(128,687,offset);
            check_pixel(863,687,offset); check_pixel(864,687,offset);
            check_pixel(879,687,offset); check_pixel(880,687,offset);
            check_pixel(895,687,offset); check_pixel(896,687,offset);
            check_pixel(1151,687,offset); check_pixel(1152,687,offset);
            check_pixel(1247,687,offset); check_pixel(1248,687,offset);
            check_pixel(1263,687,offset); check_pixel(1264,687,offset);
        end
    endtask
    initial begin
        $readmemh("D:/FPGA/code/example/rtl/video/font_720.hex",font);
        for(i=0;i<256;i=i+1) cells[i]=0;
        for(i=0;i<14;i=i+1) title_cells[i]=i+1;
        mode_cells[0]=15;mode_cells[1]=16;mode_cells[2]=5;mode_cells[3]=17;
        digit_cells[0]=22;
        for(i=1;i<10;i=i+1) digit_cells[i]=23+i;
        // 用户确认文案的独立固定索引；不读取DUT文本表作为期望值。
        // 欢迎使用炬屏—双模HDMI多媒体系统（无句末标点）
        cells[0]=33;cells[1]=34;cells[2]=35;cells[3]=36;
        for(i=0;i<14;i=i+1) cells[i+4]=i+1;
        // 双屏协作 一屏操作 一屏呈现；空格保持初始化的索引0。
        cells[64]=4;cells[65]=2;cells[66]=38;cells[67]=39;
        cells[69]=41;cells[70]=2;cells[71]=42;cells[72]=39;
        cells[74]=41;cells[75]=2;cells[76]=43;cells[77]=44;
        // 图片 字幕 音乐 波形 随心设置
        cells[128]=45;cells[129]=46;cells[131]=48;
        cells[132]=49;cells[134]=50;cells[135]=51;
        cells[137]=52;cells[138]=53;
        cells[140]=54;cells[141]=55;cells[142]=56;cells[143]=57;
        repeat(4) @(negedge clk); rst=0;
        // 三种背景逐像素覆盖8种组合的完整文字带和周围留白。
        for(background_case=0;background_case<3;background_case=background_case+1) begin
            bg=background_case==0 ? 24'hFFFFFF : background_case==1 ? 24'h000000 : 24'h84B6E8;
            for(combo=0;combo<8;combo=combo+1) begin
                text_enable=(combo>>2)&1; clock_enable=(combo>>1)&1;
                configure(8|(combo&1));
                for(py=15;py<65;py=py+1)
                    for(px=0;px<1280;px=px+1) check_pixel(px,py,0);
                for(py=656;py<716;py=py+1)
                    for(px=0;px<1280;px=px+1) check_pixel(px,py,0);
            end
        end
        // 三句×三速×两窗口完整VS轨迹；每32px及末尾抓实际RTL全高细条。
        // 帧间全状态检查不跳帧，截图采样另在trace中明确标记。
        trace=$fopen("subtitle_cycles.csv","w");
        if(!trace)$fatal(1,"trace open");
        $fwrite(trace,"cycle,preset,speed,clock,frame,position,origin,capture\n");
        bg=24'h84B6E8; text_enable=0;
        for(preset=0;preset<3;preset=preset+1)
            for(speed=0;speed<3;speed=speed+1)
                for(j=0;j<2;j=j+1) begin
                    clock_enable=j;
                    configure(8); configure((speed<<3)|(preset<<1)|1);
                    phase=0;old_phase=0;capture_index=0;blank_steps=0;
                    sentence_width=(preset==0 ? 18 : preset==1 ? 14 : 16)*32;
                    cycle_frames=(j ? 1408 : 1696)*(speed==0 ? 2 : 1)/(speed==2 ? 2 : 1)+1;
                    cycle_dump=$fopen($sformatf("subtitle_cycle_%0d_%0d_%0d.rgb",preset,speed,j),"wb");
                    if(!cycle_dump)$fatal(1,"cycle capture open");
                    for(i=0;i<=cycle_frames;i=i+1) begin
                        if(i>0) begin
                            frame;
                            if(phase>=(j ? 1408 : 1696))phase=0;
                            else phase=phase+((speed==0) ? ((i%2)==0) : speed==1 ? 1 : 2);
                        end
                        if(dut.scroll_position!==phase || dut.scroll_origin!==(((j ? 1184 : 896)+phase)%2048))
                            $fatal(1,"position/VS mismatch cycle=%0d frame=%0d",cycle_no,i);
                        // 按每条真实长度验证离场空白，不把最长句尾误当成空白。
                        if(phase>=(j ? 736 : 1024)+sentence_width)blank_steps=blank_steps+1;
                        if(phase>0 && phase<(j ? 1408 : 1696) &&
                           ((128+(j ? 1184 : 896)+phase)%2048)<sentence_width &&
                           (((j ? 863 : 1151)+(j ? 1184 : 896)+phase)%2048)<sentence_width)
                            $fatal(1,"sentence split across window endpoints");
                        capture_index=(i==0 || phase!=old_phase && phase%32==0 || i==cycle_frames);
                        $fwrite(trace,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",cycle_no,preset,speed,j,i,phase,dut.scroll_origin,capture_index);
                        check_edges(phase);
                        if(capture_index && CAPTURE_CYCLE_PIXELS)begin
                            for(py=656;py<720;py=py+1)
                                for(px=0;px<1280;px=px+1)begin
                                    check_pixel(px,py,phase);
                                    $fwrite(cycle_dump,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                                end
                        end
                        old_phase=phase;
                    end
                    $fclose(cycle_dump);
                    if(phase!=0 || blank_steps<(speed==2 ? 32 : 64))$fatal(1,"wrap/gap coverage");
                    repeat(8)@(negedge clk);
                    if(dut.scroll_position!==0)$fatal(1,"moved without VS");
                    cycle_no=cycle_no+1;
                    $display("SUBTITLE_CYCLE PASS preset=%0d speed=%0d clock=%0d frames=%0d",preset,speed,j,cycle_frames);
                end
        $fclose(trace);
        // 时间变化重启，标题不重启；内容/速度/关闭都重启。
        clock_enable=0;configure(9);frame;frame;
        if(dut.scroll_position!==2)$fatal(1,"normal speed");
        text_enable=1;repeat(4)@(negedge clk);
        if(dut.scroll_position!==2)$fatal(1,"title reset scroll");
        clock_enable=1;repeat(4)@(negedge clk);
        if(dut.scroll_position!==0 || dut.scroll_origin!==1184)$fatal(1,"clock restart");
        check_edges(0);
        frame;configure(11);
        if(dut.scroll_position!==0 || dut.slow_phase!==0)$fatal(1,"content restart");
        frame;configure(19);
        if(dut.scroll_position!==0 || dut.slow_phase!==0)$fatal(1,"speed restart");
        // 时间进位、模式切换：检查实际所有字形像素，不只测矩形命中。
        configure(8);
        for(part=0;part<4;part=part+1) begin
            case(part)
                0:uptime=24'h005959; 1:uptime=24'h010000;
                2:uptime=24'h235959; 3:uptime=24'h000000;
            endcase
            mode=part%2 ? 2 : 1;
            for(py=672;py<704;py=py+1)
                for(px=896;px<1248;px=px+1) check_pixel(px,py,0);
            for(py=24;py<56;py=py+1)
                for(px=1120;px<1248;px=px+1) check_pixel(px,py,0);
        end
        // 非法预设只出空白；速度3保留FAST别名。
        configure(31); frame;
        if(dut.scroll_position!==2) $fatal(1,"invalid speed fallback");
        for(py=672;py<704;py=py+1)
            for(px=128;px<864;px=px+1) check_pixel(px,py,2);
        configure(8);
        if(dut.scroll_position!==0) $fatal(1,"disabled origin");
        $display("TB_SUBTITLE720 PASS combinations=8 backgrounds=3 presets=3 speeds=3 widths=2 full-cycles=18 checks=%0d VS=%0d latency=1 cycle-raster=%0d",checks,frame_count,CAPTURE_CYCLE_PIXELS);
        $finish;
    end
    initial begin #2000000000; $fatal(1,"subtitle timeout"); end
endmodule
