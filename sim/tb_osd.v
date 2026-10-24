// 透明黑字整帧验证：三处文字存在，所有非文字窗口像素原样保留。
`timescale 1ns/1ps
module tb_osd;

    reg clk = 0, rst = 1;
    always #20 clk = ~clk;     // 25.175MHz 等效

    wire hs, vs, de;
    wire [9:0] x;
    wire [8:0] y;

    video_timing_gen #(
        .HTOTAL(800), .HSA(96), .HFP(16), .HBP(48), .HACTIVE(640),
        .VTOTAL(525), .VSA(2),  .VFP(10), .VBP(33), .VACTIVE(480)
    ) u_timing (.I_clk(clk), .I_rst(rst), .O_hs(hs), .O_vs(vs), .O_de(de), .O_x(x), .O_y(y));

    wire [9:0] px; wire [8:0] py; wire [31:0] fc; wire de_al;
    pixel_pos_gen u_pos (.I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de),
                         .O_de(de_al), .O_x(px), .O_y(py), .O_frame_cnt(fc));

    // 合成背景: 对角渐变 + 棋盘格，便于观察混合效果
    wire [23:0] bg = {px[7:0], py[7:0], 8'h60} ^ (px[3] ^ py[3] ? 24'h181818 : 24'h0);
    function [23:0] background;
        input integer c, r;
        begin background={c[7:0],r[7:0],8'h60} ^ (((c>>3)^(r>>3))&1 ? 24'h181818 : 24'h0); end
    endfunction

    wire [23:0] osd_rgb;
    osd_engine u_osd (
        .I_clk(clk),
        .I_x(px), .I_y(py),
        .I_bg_rgb(bg),
        .I_uptime_bcd(24'h094133),   // 09:41:33
        .I_mode(2'd1),               // 广告模式
        .O_rgb(osd_rgb)
    );

    // A2: OSD 流水线输出延迟 1 拍，采集坐标同步打 1 拍
    reg        de_cap;
    reg [9:0]  px_cap;
    reg [8:0]  py_cap;
    always @(posedge clk) begin
        de_cap <= de_al;
        px_cap <= px;
        py_cap <= py;
    end

    reg [23:0] fb [0:640*480-1];
    reg vs_d2 = 0;
    integer fd, r, c, frames_done = 0;
    integer si, nbad, title_pixels, mode_pixels, clock_pixels;
    reg [23:0] bg_expected;

    always @(posedge clk) begin
        if (de_cap) fb[py_cap * 640 + px_cap] <= osd_rgb;
        vs_d2 <= vs;
        if (vs && !vs_d2) $display("DBG frame end: last de px = (%0d,%0d)", px, py);
        if (vs && frames_done == 0) begin
            frames_done <= 1;
            fd = $fopen("osd_frame.ppm", "w");
            $fwrite(fd, "P3\n640 480\n255\n");
            for (r = 0; r < 480; r = r + 1)
                for (c = 0; c < 640; c = c + 1)
                    $fwrite(fd, "%0d %0d %0d\n", fb[r*640+c][23:16], fb[r*640+c][15:8], fb[r*640+c][7:0]);
            $fclose(fd);
            nbad = 0;
            title_pixels=0; mode_pixels=0; clock_pixels=0;
            for (r=0; r<480; r=r+1) begin
                for (c=0; c<640; c=c+1) begin
                    bg_expected=background(c,r);
                    if(fb[r*640+c]!==bg_expected) begin
                        if(fb[r*640+c]!==24'd0) nbad=nbad+1;
                        else if(r>=4 && r<20 && c>=16 && c<240) title_pixels=title_pixels+1;
                        else if(r>=4 && r<20 && c>=560 && c<624) mode_pixels=mode_pixels+1;
                        else if(r>=456 && r<472 && c>=448 && c<624) clock_pixels=clock_pixels+1;
                        else nbad=nbad+1;
                    end
                end
            end
            if(title_pixels==0 || mode_pixels==0 || clock_pixels==0) nbad=nbad+1;
            if (nbad == 0) $display("TB_OSD PASS");
            else $display("TB_OSD FAIL nbad=%0d", nbad);
            $finish;
        end
    end

    initial begin
        for (si = 0; si < 640*480; si = si + 1) fb[si] = 24'hFF00FF;   // 哨兵
        rst = 1; #100;
        @(posedge clk); rst = 0;
        #20_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
