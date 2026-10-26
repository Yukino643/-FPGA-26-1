// tb_bmp_read_g.v — bmp_read_g 单元仿真：虚拟 TF 卡 + 小尺寸 BMP（含 padding 用例）
//  卡内容: sector0-1  junk | sector2  img1 (3x2, 行尾 pad3) | sector4 junk | sector6 img2 (5x2, pad1)
`timescale 1ns/1ps
module tb_bmp_read_g;
    // 参数同时覆盖连续供数和真实 SPI 中有效字节之间的空拍。
    parameter integer BYTE_GAP = 0;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;      // 100MHz

    // ---- DUT ----
    reg         scan_start = 0, load_start = 0;
    reg  [31:0] load_sector = 0;
    wire        scan_done, scan_fv, ready, write_req, load_done, load_error;
    wire [3:0]  error_code;
    wire [31:0] scan_fs;
    wire [3:0]  scan_ft;
    wire [15:0] scan_fw, scan_fh, load_w, load_h;
    wire [3:0]  state_code;
    wire        wr_en;
    wire [23:0] wr_data;
    reg         wr_ack = 0;

    wire        sd_rd;
    wire [31:0] sd_addr;
    reg         sd_dv = 0, sd_end = 0, sd_error = 0;
    reg  [7:0]  sd_data = 0;
    reg         force_sd_error = 0;

    bmp_read_g #(.MAX_IMAGES(8), .MAX_DIM(2047)) dut (
        .clk(clk), .rst(rst),
        .ready(ready),
        .scan_start(scan_start), .scan_start_sector(32'd0), .scan_max_sector(32'd15),
        .scan_target_count(4'd8),
        .scan_done(scan_done), .scan_found_valid(scan_fv),
        .scan_found_sector(scan_fs), .scan_found_total(scan_ft),
        .scan_found_w(scan_fw), .scan_found_h(scan_fh),
        .load_start(load_start), .load_sector(load_sector),
        .load_done(load_done), .load_error(load_error), .error_code(error_code),
        .load_active(), .load_img_w(load_w), .load_img_h(load_h),
        .sd_init_done(1'b1), .state_code(state_code),
        .write_req(write_req), .write_req_ack(wr_ack),
        .sd_sec_read(sd_rd), .sd_sec_read_addr(sd_addr),
        .sd_sec_read_data(sd_data), .sd_sec_read_data_valid(sd_dv), .sd_sec_read_end(sd_end),
        .sd_sec_read_error(sd_error),
        .bmp_data_wr_en(wr_en), .bmp_data(wr_data)
    );

    // ---- 虚拟卡: 字节内存 ----
    reg [7:0] card [0:16*512-1];
    integer i;

    task put_bmp(input integer sec, input integer w, input integer h);
        integer fl, off, rb, k, base, pb, r, c;
        begin
            off = 54;
            rb  = (w*3 + 3) & ~3;
            fl  = off + rb * h;
            base = sec * 512;
            for (i = 0; i < 512; i = i + 1) card[base + i] = 8'h00;
            card[base+0] = "B"; card[base+1] = "M";
            card[base+2]  = fl[7:0];  card[base+3]  = fl[15:8];
            card[base+4]  = fl[23:16]; card[base+5] = fl[31:24];
            card[base+10] = off[7:0]; card[base+11] = off[15:8];
            card[base+12] = off[23:16]; card[base+13] = off[31:24];
            card[base+14] = 8'd40;   // BITMAPINFOHEADER
            card[base+26] = 8'd1;    // planes = 1
            card[base+18] = w[7:0];  card[base+19] = w[15:8];
            card[base+20] = w[23:16]; card[base+21] = w[31:24];
            card[base+22] = h[7:0];  card[base+23] = h[15:8];
            card[base+24] = h[23:16]; card[base+25] = h[31:24];
            card[base+28] = 8'd24;   // 24bpp（LE 高字节 0）
            card[base+30] = 8'd0;    // 无压缩
            // 像素（自底向上行序），字节值 = 全局流序号 k+1，便于核对
            k = 0;
            for (r = 0; r < h; r = r + 1)          // r=0 即 BMP 流中的第一行(最底行)
                for (c = 0; c < w; c = c + 1) begin
                    pb = base + off + r * rb + c * 3;
                    card[pb+0] = 8'h80 + k[6:0];   // B
                    card[pb+1] = 8'h40 + k[6:0];   // G
                    card[pb+2] = 8'h01 + k[6:0];   // R
                    k = k + 1;
                end
        end
    endtask

    // 扇区读取行为模型: 4 拍延迟后逐字节给出 512 字节；
    // 末字节后 data_valid 撤销，end 单独一拍（对齐真实 sd_card_top 时序）
    reg [31:0] sec_ptr;
    integer    sec_cnt;
    integer    lat;
    reg        end_sent;
    integer gap_left = 0;
    always @(posedge clk) begin
        if (sd_rd && lat == -1) begin
            sec_ptr  <= sd_addr * 512;
            sec_cnt  <= 0;
            end_sent <= 0;
            lat      <= 4;
            gap_left <= 0;
            sd_error <= 0;
        end else if (lat > 0) begin
            lat <= lat - 1;
        end else if (lat == 0) begin
            if (gap_left > 0) begin
                sd_dv <= 1'b0;
                gap_left <= gap_left - 1;
            end else if (sec_cnt < 512) begin
                sd_dv   <= 1'b1;
                sd_data <= card[sec_ptr + sec_cnt];
                sec_cnt <= sec_cnt + 1;
                gap_left <= BYTE_GAP;
            end else if (!end_sent) begin
                sd_dv    <= 1'b0;
                sd_end   <= 1'b1;
                sd_error <= force_sd_error;
                end_sent <= 1'b1;
            end else begin
                sd_end <= 1'b0;
                sd_error <= 1'b0;
                lat    <= -1;
            end
        end else begin
            sd_dv  <= 1'b0;
            sd_end <= 1'b0;
        end
    end
    initial lat = -1;

    // ---- 检查器 ----
    integer errors = 0, px_got = 0;
    reg [23:0] exp_px;
    integer exp_k;   // 当前流序号
    reg loading = 0;

    always @(posedge clk) begin
        if (!rst && wr_en) begin
            exp_px = {8'h01 + exp_k[6:0], 8'h40 + exp_k[6:0], 8'h80 + exp_k[6:0]}; // {R,G,B}
            if (wr_data !== exp_px) begin
                errors = errors + 1;
                $display("ERR t=%0t px#%0d got=%h exp=%h", $time, px_got, wr_data, exp_px);
            end
            px_got = px_got + 1;
            exp_k  = exp_k + 1;
        end
    end

    // scan_found 检查
    integer found_seen = 0;
    reg [31:0] exp_sec [0:1];
    reg [15:0] exp_w [0:1];
    reg [15:0] exp_h [0:1];
    always @(posedge clk) begin
        if (!rst && scan_fv) begin
            if (scan_fs !== exp_sec[found_seen] || scan_fw !== exp_w[found_seen] || scan_fh !== exp_h[found_seen]) begin
                errors = errors + 1;
                $display("ERR scan#%0d sec=%h w=%0d h=%0d", found_seen, scan_fs, scan_fw, scan_fh);
            end
            found_seen = found_seen + 1;
        end
    end

    task load_img(input [31:0] sec, input integer npx);
        begin
            @(posedge clk);
            exp_k    = 0;
            px_base  = px_got;
            load_sector = sec; load_start = 1;
            @(posedge clk); load_start = 0;
            while (write_req !== 1'b1) @(posedge clk);
            wr_ack = 1;
            @(posedge clk); wr_ack = 0;
            while (load_done !== 1'b1) @(posedge clk);
            if (px_got - px_base !== npx) begin
                errors = errors + 1;
                $display("ERR pixel count %0d exp %0d", px_got - px_base, npx);
            end
        end
    endtask

    task load_bad_header(input [31:0] sec);
        begin
            load_sector = sec;
            @(posedge clk); load_start = 1;
            @(posedge clk); load_start = 0;
            while (load_error !== 1'b1) @(posedge clk);
            if (error_code !== 4'd1 || load_done === 1'b1) begin
                errors = errors + 1;
                $display("ERR bad header code=%0d done=%b", error_code, load_done);
            end
        end
    endtask

    task load_sd_failure(input [31:0] sec);
        begin
            load_sector = sec;
            force_sd_error = 1'b1;
            @(posedge clk); load_start = 1'b1;
            @(posedge clk); load_start = 1'b0;
            while (load_error !== 1'b1) @(posedge clk);
            force_sd_error = 1'b0;
            if (error_code !== 4'd4 || load_done === 1'b1) begin
                errors = errors + 1;
                $display("ERR SD failure code=%0d done=%b", error_code, load_done);
            end
        end
    endtask
    integer px_base = 0;

    // 调试: 每个 end 脉冲打印头部采样结果
    always @(posedge clk)
        if (!rst && dut.sd_sec_read_end)
            $display("DBG sec=%0d h0=%c h1=%c len=%0d off=%0d w=%0d h=%0d bc=%0d cmp=%0d",
                     dut.sd_sec_read_addr, dut.header_0, dut.header_1,
                     dut.file_len, dut.pixel_offset, dut.width, dut.height,
                     dut.bit_count, dut.compression);

    initial begin
        for (i = 0; i < 16*512; i = i + 1) card[i] = 8'hAA;   // junk
        put_bmp(2, 3, 2);     // 行宽 9B -> pad 3
        put_bmp(6, 5, 2);     // 行宽 15B -> pad 1
        exp_sec[0] = 32'd2; exp_w[0] = 16'd3; exp_h[0] = 16'd2;
        exp_sec[1] = 32'd6; exp_w[1] = 16'd5; exp_h[1] = 16'd2;

        rst = 1; #100;
        @(posedge clk); rst = 0;

        // 扫描
        @(posedge clk); scan_start = 1;
        @(posedge clk); scan_start = 0;
        while (scan_done !== 1'b1) @(posedge clk);
        if (found_seen !== 2) begin errors = errors + 1; $display("ERR found=%0d", found_seen); end

        // 装载 img1: 6 像素
        load_img(32'd2, 6);
        // 装载 img2: 10 像素
        load_img(32'd6, 10);

        // 物理扇区虽正常结束，但控制器报告错误时必须拒绝该扇区。
        load_sd_failure(32'd2);

        // 坏头不得进入写入态，也不得伪装成正常完成。
        card[2*512 + 28] = 8'd16;  // bit_count = 16，触发 ERR_HEADER
        load_bad_header(32'd2);

        #1000;
        $display("==== px_got=%0d found=%0d errors=%0d ====", px_got, found_seen, errors);
        if (errors == 0) $display("TB_BMP_READ_G PASS");
        else $display("TB_BMP_READ_G FAIL");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "FAIL BMP read timed out (BYTE_GAP=%0d)", BYTE_GAP);
    end
endmodule
