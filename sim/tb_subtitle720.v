`timescale 1ns/1ps
// 独立屏幕空间参考：字索引/区域/色彩不从DUT命中或地址信号推导。
module tb_subtitle720;
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
    integer cells [0:127];
    integer title_cells [0:13];
    integer mode_cells [0:3];
    integer digit_cells [0:9];
    integer i,j,px,py,preset,speed,combo,background_case,phase,steps,increment;
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
                  (clock_enable && xx>=848 && xx<1248 && yy>=664 && yy<712) ||
                  (cfg[0] && xx>=32 && xx<1248 && yy>=664 && yy<712);
            if(plate) expected={2'b0,bg[23:18],2'b0,bg[15:10],2'b0,bg[7:2]};
            if(cfg[0] && xx>=32 && xx<128 && yy>=664 && yy<712) expected=24'h0E3A4C;
            if(text_enable && yy>=24 && yy<56) begin
                if(xx>=32 && xx<480) begin
                    hit=1; glyph=title_cells[(xx-32)/32]; col=(xx-32)%32; row=yy-24;
                end else if(xx>=1120 && xx<1248) begin
                    hit=1; glyph=mode_cells[(xx-1120)/32]; col=(xx-1120)%32; row=yy-24; ink=24'h8FD5FA;
                    if(mode==2 && xx<1184) glyph=(xx<1152) ? 18 : 19;
                end
            end
            if(clock_enable && xx>=864 && xx<1216 && yy>=672 && yy<704) begin
                hit=1; cell_col=(xx-864)/32; col=(xx-864)%32; row=yy-672; ink=24'hC8F75A;
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
                if(xx>=48 && xx<112) begin
                    hit=1; glyph=(xx<80) ? 48 : 49; col=(xx-48)%32; row=yy-672;
                end else if(xx>=144 && xx<(clock_enable ? 832 : 1168)) begin
                    source=(xx-144+offset)%1024;
                    hit=1; glyph=cells[cfg[2:1]*32+source/32]; col=source%32; row=yy-672;
                end
            end
            bits=font[glyph*32+row];
            if(hit && bits[31-col]) expected=ink;
            if(cfg[0] && xx>=32 && xx<1248 && yy>=664 && yy<666) expected=24'h38BDF8;
            @(posedge clk); #1;
            checks=checks+1;
            if(rgb!==expected) $fatal(1,"OSD xy=%0d,%0d cfg=%h TC=%b%b phase=%0d bg=%h got=%h expected=%h glyph=%0d row=%0d col=%0d",xx,yy,cfg,text_enable,clock_enable,offset,bg,rgb,expected,glyph,row,col);
        end
    endtask
    task check_edges;
        input integer offset;
        begin
            check_pixel(143,687,offset); check_pixel(144,687,offset);
            check_pixel(175,687,offset); check_pixel(831,687,offset);
            check_pixel(832,687,offset); check_pixel(847,687,offset);
            check_pixel(848,687,offset); check_pixel(863,687,offset);
            check_pixel(864,687,offset); check_pixel(1167,687,offset);
            check_pixel(1168,687,offset); check_pixel(1215,687,offset);
            check_pixel(1216,687,offset); check_pixel(1247,687,offset);
            check_pixel(1248,687,offset);
        end
    endtask
    initial begin
        $readmemh("D:/FPGA/code/example/rtl/video/font_720.hex",font);
        for(i=0;i<128;i=i+1) cells[i]=0;
        for(i=0;i<14;i=i+1) begin title_cells[i]=i+1; cells[i]=i+1; end
        mode_cells[0]=15;mode_cells[1]=16;mode_cells[2]=5;mode_cells[3]=17;
        digit_cells[0]=22;
        for(i=1;i<10;i=i+1) digit_cells[i]=23+i;
        // B组独立固定索引：双屏协作 一屏操作 一屏呈现。
        cells[32]=4;cells[33]=2;cells[34]=33;cells[35]=34;
        cells[37]=35;cells[38]=2;cells[39]=36;cells[40]=34;
        cells[42]=35;cells[43]=2;cells[44]=37;cells[45]=38;
        // 图片 音乐 字幕 精彩同屏。
        cells[64]=39;cells[65]=40;cells[67]=41;cells[68]=42;
        cells[70]=43;cells[71]=44;cells[73]=45;cells[74]=46;cells[75]=47;cells[76]=2;
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
        // 各内容、各速度、两窗口均滚完整周期；每一相位检查裁剪端点。
        bg=24'h84B6E8; text_enable=0;
        for(preset=0;preset<3;preset=preset+1)
            for(speed=0;speed<3;speed=speed+1)
                for(j=0;j<2;j=j+1) begin
                    clock_enable=j;
                    configure(8); configure((speed<<3)|(preset<<1)|1);
                    steps=(speed==0) ? 2048 : speed==1 ? 1024 : 512;
                    phase=0;
                    for(i=0;i<steps;i=i+1) begin
                        frame;
                        increment=(speed==0) ? ((i%2)==1) : speed==1 ? 1 : 2;
                        phase=(phase+increment)%1024;
                        if(dut.scroll_origin!==((880+phase)%1024)) $fatal(1,"scroll speed/VS mismatch");
                        check_edges(phase);
                    end
                    if(phase!=0 || dut.scroll_origin!==880) $fatal(1,"full cycle wrap");
                    repeat(8) @(negedge clk);
                    if(dut.scroll_origin!==880) $fatal(1,"scroll moved without VS");
                    // 历史文件名保留以兼容预览工具；内容实际为获批B组。
                    if(j==0 && speed==1) begin
                        if(preset==0) dump=$fopen("subtitle_welcome.ppm","w");
                        else if(preset==1) dump=$fopen("subtitle_event.ppm","w");
                        else dump=$fopen("subtitle_media.ppm","w");
                        if(!dump) $fatal(1,"subtitle preview open failed");
                        $fwrite(dump,"P3\n1280 64\n255\n");
                        for(py=656;py<720;py=py+1)
                            for(px=0;px<1280;px=px+1) begin
                                check_pixel(px,py,0);
                                $fwrite(dump,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
                            end
                        $fclose(dump);
                    end
                end
        // 标题、时间变化不重启字幕；内容或速度变化必须重启。
        configure(9); frame; frame; phase=2;
        clock_enable=1; text_enable=1;
        repeat(4) @(negedge clk);
        if(dut.scroll_origin!==882) $fatal(1,"unrelated switch reset scroll");
        check_edges(2);
        configure(11);
        if(dut.scroll_origin!==880 || dut.slow_phase!==0) $fatal(1,"content restart");
        configure(19);
        if(dut.scroll_origin!==880 || dut.slow_phase!==0) $fatal(1,"speed restart");
        // 时间进位、模式切换：检查实际所有字形像素，不只测矩形命中。
        configure(8);
        for(part=0;part<4;part=part+1) begin
            case(part)
                0:uptime=24'h005959; 1:uptime=24'h010000;
                2:uptime=24'h235959; 3:uptime=24'h000000;
            endcase
            mode=part%2 ? 2 : 1;
            for(py=672;py<704;py=py+1)
                for(px=864;px<1216;px=px+1) check_pixel(px,py,0);
            for(py=24;py<56;py=py+1)
                for(px=1120;px<1248;px=px+1) check_pixel(px,py,0);
        end
        // 非法预设只出空白；速度3保留FAST别名。
        configure(31); frame;
        if(dut.scroll_origin!==882) $fatal(1,"invalid speed fallback");
        for(py=672;py<704;py=py+1)
            for(px=144;px<832;px=px+1) check_pixel(px,py,2);
        configure(8);
        if(dut.scroll_origin!==880) $fatal(1,"disabled origin");
        $display("TB_SUBTITLE720 PASS combinations=8 backgrounds=3 presets=3 speeds=3 widths=2 full-cycles=18 checks=%0d VS=%0d latency=1",checks,frame_count);
        $finish;
    end
    initial begin #100000000; $fatal(1,"subtitle timeout"); end
endmodule
