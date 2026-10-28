`timescale 1ns/1ps
module tb_picture_resolution;
    reg clk=0,rst=1,vs=0,commit=0,buf_id=0,front=0,enable=1;
    reg [10:0] w=0,x=0;
    reg [9:0] h=0,y=0;
    wire [23:0] rgb;
    reg [23:0] bg=24'hFFFFFF;
    reg expected_visible=1;
    reg [31:0] font[0:2047];
    integer dims,idx,px,py,outfile,checks=0;
    reg [31:0] expected_chars,saved;
    reg [3:0] ch;
    integer glyph,row,col;
    reg [23:0] expected;
    reg [31:0] pixels;
    always #5 clk=~clk;
    osd_engine_720 dut(.I_clk(clk),.I_rst(rst),.I_vs_pulse(vs),.I_subtitle_cfg(5'h08),
        .I_x(x),.I_y(y),.I_bg_rgb(bg),.I_uptime_bcd(24'h123456),
        .I_clock_enable(1'b1),.I_text_enable(1'b1),.I_picture_commit(commit),
        .I_picture_buf(buf_id),.I_picture_width(w),.I_picture_height(h),
        .I_picture_front(front),.I_picture_enable(enable),.O_rgb(rgb));
    function [31:0] reference_label;
        input integer width,height;
        reg [127:0] text;
        reg [31:0] label;
        integer k;
        reg [7:0] c;
        begin
            // 使用仿真格式化十进制字符串，与RTL逐位减法/压紧路径独立。
            $sformat(text,"%0dX%0d",width,height);
            label=32'hFFFFFFFF;
            for(k=15;k>=0;k=k-1) begin
                c=text[k*8 +: 8];
                if(c!=0) label={label[27:0],(c=="X" ? 4'hA : c[3:0])};
            end
            reference_label=label;
        end
    endfunction
    task frame;
        begin @(negedge clk);vs=1;@(negedge clk);vs=0;end
    endtask
    task capture;
        input integer width,height;
        input target;
        begin
            @(negedge clk);w=width;h=height;buf_id=target;commit=1;
            @(negedge clk);commit=0;
            if(dut.resolution_enable!==0) $fatal(1,"FAIL partially converted label visible");
            repeat(64) @(negedge clk);
            if(dut.resolution_pending!==reference_label(width,height))
                $fatal(1,"FAIL conversion %0dX%0d got=%h expected=%h",width,height,dut.resolution_pending,reference_label(width,height));
        end
    endtask
    task sample;
        input integer xx,yy;
        begin
            @(negedge clk);x=xx;y=yy;
            expected=bg;
            if(expected_visible && enable && xx>=976 && xx<1264 && yy>=80 && yy<128)
                expected={2'b0,bg[23:18],2'b0,bg[15:10],2'b0,bg[7:2]};
            if(expected_visible && enable && xx>=992 && xx<1248 && yy>=88 && yy<120) begin
                idx=(xx-992)/32;ch=expected_chars[31-idx*4 -: 4];
                glyph=(ch==4'hF) ? 0 : (ch==4'hA) ? 60 : (ch==0) ? 22 : ch+23;
                row=yy-88;col=(xx-992)%32;pixels=font[glyph*32+row];
                if(pixels[31-col]) expected=24'hD8B4FE;
            end
            @(posedge clk);#1;
            if(rgb!==expected) $fatal(1,"FAIL pixel %0d,%0d actual=%h expected=%h",xx,yy,rgb,expected);
            checks=checks+1;
        end
    endtask
    initial begin
        $readmemh("D:/FPGA/code/example/rtl/video/font_720.hex",font);
        repeat(3) @(negedge clk);rst=0;
        for(dims=1;dims<=1280;dims=dims+1) begin
            capture(dims,1+(dims*317)%720,0);frame;
            if(dut.resolution_chars!==reference_label(dims,1+(dims*317)%720) || !dut.resolution_enable)
                $fatal(1,"FAIL page publish width=%0d",dims);
        end
        capture(1280,720,0);frame;front=0;expected_chars=reference_label(1280,720);
        saved=dut.resolution_chars;
        capture(640,480,1);
        expected_visible=0;
        sample(1000,90);
        if(dut.resolution_enable!==0) $fatal(1,"FAIL label published before VS");
        frame;
        if(dut.resolution_enable!==0) $fatal(1,"FAIL background page label shown on old picture");
        sample(1000,90);
        // 模拟转场门控：页已切换但转场尚未结束时仍不画标签。
        front=1;enable=0;sample(1000,90);
        enable=1;expected_visible=1;expected_chars=reference_label(640,480);
        sample(1000,90);
        for(dims=0;dims<4;dims=dims+1) begin
            case(dims)
                0:begin w=1280;h=720;end
                1:begin w=640;h=480;end
                2:begin w=800;h=480;end
                3:begin w=320;h=180;end
            endcase
            capture(w,h,0);frame;front=0;expected_chars=reference_label(w,h);
            case(dims)
                0:outfile=$fopen("resolution_1280x720.ppm","w");
                1:outfile=$fopen("resolution_640x480.ppm","w");
                2:outfile=$fopen("resolution_800x480.ppm","w");
                3:outfile=$fopen("resolution_320x180.ppm","w");
            endcase
            $fwrite(outfile,"P3\n320 64\n255\n");
            for(py=72;py<136;py=py+1) begin
                for(px=952;px<1272;px=px+1) begin
                    sample(px,py);$fwrite(outfile,"%0d %0d %0d ",rgb[23:16],rgb[15:8],rgb[7:0]);
                end
                $fwrite(outfile,"\n");
            end
            $fclose(outfile);
        end
        capture(640,480,1);frame;front=1;expected_chars=reference_label(640,480);
        bg=24'h102030;
        for(py=80;py<128;py=py+1)for(px=976;px<1264;px=px+1) sample(px,py);
        enable=0;
        for(py=80;py<128;py=py+1)for(px=976;px<1264;px=px+1) sample(px,py);
        rst=1;@(negedge clk);rst=0;enable=1;expected_visible=0;
        sample(1000,90);
        $display("PASS PICTURE_RESOLUTION dimensions=1280 target-page-isolation frame-commit transition-hidden bright/dark/disabled/reset pixels=%0d",checks);
        $finish;
    end
    initial begin #10000000;$fatal(1,"FAIL resolution test timeout");end
endmodule
