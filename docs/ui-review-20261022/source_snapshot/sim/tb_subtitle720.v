`timescale 1ns/1ps
module tb_subtitle720;
    reg clk=0, rst=1, vs=0;
    always #5 clk=~clk;
    reg [10:0] x=0;
    reg [9:0] y=0;
    reg [4:0] cfg=5'h08;
    reg clock_enable=0, text_enable=0;
    wire [23:0] rgb;
    osd_engine_720 dut(.I_clk(clk),.I_rst(rst),.I_vs_pulse(vs),.I_subtitle_cfg(cfg),
        .I_x(x),.I_y(y),.I_bg_rgb(24'h84B6E8),.I_uptime_bcd(24'h123456),
        .I_mode(2'd1),.I_clock_enable(clock_enable),.I_text_enable(text_enable),.O_rgb(rgb));
    reg [31:0] font [0:2047];
    reg [5:0] cells [0:95];
    integer i,j,px,py,preset,phase,speed,expected_phase,dump;
    integer source,column,glyph;
    reg [31:0] font_row;
    reg [23:0] expected;
    task frame;
        begin
            @(negedge clk); vs=1;
            @(negedge clk); vs=0;
        end
    endtask
    // Compare real glyph pixels and transparent background after the ROM edge.
    // Exercise both clock positions without deriving color from DUT signals.
    task check_fixed_cell;
        input integer left,top,glyph_id;
        input [23:0] ink;
        input enabled;
        integer cx,cy;
        reg [23:0] reference_rgb;
        reg [31:0] reference_row;
        begin
            for(cy=0;cy<32;cy=cy+1)
                for(cx=0;cx<32;cx=cx+1) begin
                    @(negedge clk); x=left+cx; y=top+cy;
                    reference_row=font[glyph_id*32+cy];
                    reference_rgb=(enabled && reference_row[31-cx]) ? ink : 24'h84B6E8;
                    @(posedge clk); #1;
                    if(rgb!==reference_rgb)
                        $fatal(1,"fixed OSD color xy=%0d,%0d got=%h expected=%h",x,y,rgb,reference_rgb);
                end
        end
    endtask
    task configure;
        input [4:0] value;
        begin
            @(negedge clk); x=0; y=0; cfg=value;
            repeat(3) @(negedge clk);
        end
    endtask
    // Reference uses screen-space bounds and literal preset character IDs,
    // independently of the RTL's source-coordinate and cell-address wiring.
    task check_pixel;
        input integer xx,yy,pp,offset;
        begin
            @(negedge clk); x=xx; y=yy;
            expected=24'h84B6E8;
            if(cfg[0] && xx>=32 && xx<1248 && yy>=672 && yy<712) begin
                expected=(xx<144) ? 24'h124E70 : 24'h425B74;
                glyph=0; column=0;
                if(yy>=676 && yy<708) begin
                    if(xx>=48 && xx<112) begin
                        glyph=(xx<80) ? 53 : 54;
                        column=(xx-48)%32;
                    end else if(xx>=160 && xx<1232) begin
                        source=(xx-160+offset)%1024;
                        glyph=cells[pp*32+source/32];
                        column=source%32;
                    end
                    font_row=font[glyph*32+yy-676];
                    if(font_row[31-column]) expected=24'hF5FBFF;
                end
                if(yy==672 || xx<36) expected=24'h38BDF8;
            end
            @(posedge clk); #1;
            if(rgb!==expected) $fatal(1,"subtitle pixel p=%0d phase=%0d xy=%0d,%0d got=%h expected=%h",pp,offset,xx,yy,rgb,expected);
        end
    endtask
    initial begin
        $readmemh("D:/FPGA/code/example/rtl/video/font_720.hex",font);
        for(i=0;i<96;i=i+1) cells[i]=0;
        cells[0]=33;cells[1]=34;cells[2]=12;cells[3]=35;cells[4]=4;cells[5]=2;
        cells[6]=10;cells[7]=11;cells[8]=12;cells[9]=13;cells[10]=14;
        cells[32]=36;cells[33]=37;cells[34]=38;cells[35]=39;cells[36]=40;cells[37]=21;
        cells[39]=33;cells[40]=34;cells[41]=41;cells[42]=42;cells[43]=12;cells[44]=35;
        cells[64]=43;cells[65]=44;cells[67]=45;cells[68]=46;cells[70]=47;cells[71]=48;
        cells[73]=49;cells[74]=50;cells[75]=51;cells[76]=52;
        repeat(4) @(negedge clk); rst=0;
        for(speed=0;speed<3;speed=speed+1) begin
            configure((speed<<3)|1);
            for(i=0;i<60;i=i+1) frame;
            expected_phase=(speed==0) ? 30 : ((speed==1) ? 60 : 120);
            if(dut.scroll_origin !== ((864+expected_phase)%1024)) $fatal(1,"scroll rate speed=%0d",speed);
            repeat(9) @(negedge clk);
            if(dut.scroll_origin !== ((864+expected_phase)%1024)) $fatal(1,"scroll moved without VS");
        end
        configure(5'h08);
        if(dut.scroll_origin!==864) $fatal(1,"disabled origin");
        check_pixel(160,680,0,0);
        for(preset=0;preset<3;preset=preset+1) begin
            configure(9|(preset<<1));
            if(dut.scroll_origin!==864) $fatal(1,"preset restart");
            if(preset==0) dump=$fopen("subtitle_welcome.ppm","w");
            else if(preset==1) dump=$fopen("subtitle_event.ppm","w");
            else dump=$fopen("subtitle_media.ppm","w");
            $fwrite(dump,"P3\n1280 48\n255\n");
            for(py=668;py<716;py=py+1)
                for(px=0;px<1280;px=px+1) begin
                    check_pixel(px,py,preset,0);
                    $fwrite(dump,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
                end
            $fclose(dump);
            for(i=0;i<1023;i=i+1) frame;
            if(dut.scroll_origin!==863) $fatal(1,"end of cycle");
            for(py=675;py<709;py=py+1)
                for(px=145;px<1249;px=px+1) check_pixel(px,py,preset,1023);
            frame;
            if(dut.scroll_origin!==864) $fatal(1,"exact cycle wrap");
        end
        // Uptime moves to y80 when the lower banner is visible, and returns
        // to y656 when disabled. Static title remains independently disabled.
        clock_enable=1; configure(5'h09);
        @(negedge clk); x=896; y=80; #1;
        if(!dut.clock_y || dut.subtitle_band) $fatal(1,"clock relocation");
        @(negedge clk); y=656; #1;
        if(dut.clock_y) $fatal(1,"old clock not cleared");
        configure(5'h08);
        @(negedge clk); x=896; y=656; #1;
        if(!dut.clock_y || dut.subtitle_band) $fatal(1,"clock restore");
        text_enable=1;
        check_fixed_cell(32,32,1,24'h38BDF8,1'b1);
        check_fixed_cell(1120,32,15,24'h38BDF8,1'b1);
        check_fixed_cell(896,656,20,24'hC8F75A,1'b1);
        configure(5'h09);
        check_fixed_cell(896,80,20,24'hC8F75A,1'b1);
        text_enable=0;
        check_fixed_cell(32,32,1,24'h38BDF8,1'b0);
        clock_enable=0;
        check_fixed_cell(896,80,20,24'hC8F75A,1'b0);
        $display("FIXED_OSD_COLOR PASS title/mode=sky clock=lime enabled/disabled relocation latency=1");
        $display("TB_SUBTITLE720 PASS presets=3 speeds=30/60/120 clipping=all wrap=1024 latency=1");
        $finish;
    end
    initial begin #6000000; $fatal(1,"subtitle timeout"); end
endmodule
