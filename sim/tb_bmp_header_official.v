// 用官方 BMP 的真实首扇区检查头字段隔离，覆盖扫描和装载路径。
`timescale 1ns/1ps
module tb_bmp_header_official;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    reg scan_start = 0, load_start = 0;
    reg [31:0] load_sector = 0;
    wire ready, scan_done, scan_found, write_req, load_error;
    wire [31:0] found_sector, sd_addr;
    wire [3:0] found_total, error_code;
    wire [15:0] found_w, found_h, load_w, load_h;
    wire sd_req;
    reg [7:0] sd_data = 0;
    reg sd_valid = 0, sd_end = 0;
    reg [7:0] strawberry[0:511], apple[0:511], watermelon[0:511];
    integer errors = 0, found = 0, i, image;

    bmp_read_g dut (
        .clk(clk), .rst(rst), .ready(ready),
        .scan_start(scan_start), .scan_start_sector(32'd0),
        .scan_max_sector(32'd5402), .scan_target_count(4'd3),
        .scan_done(scan_done), .scan_found_valid(scan_found),
        .scan_found_sector(found_sector), .scan_found_total(found_total),
        .scan_found_w(found_w), .scan_found_h(found_h),
        .load_start(load_start), .load_sector(load_sector),
        .load_done(), .load_error(load_error), .error_code(error_code),
        .load_active(), .load_img_w(load_w), .load_img_h(load_h),
        .sd_init_done(1'b1), .state_code(),
        .write_req(write_req), .write_req_ack(1'b0),
        .sd_sec_read(sd_req), .sd_sec_read_addr(sd_addr),
        .sd_sec_read_data(sd_data), .sd_sec_read_data_valid(sd_valid),
        .sd_sec_read_end(sd_end), .sd_sec_read_error(1'b0),
        .bmp_data_wr_en(), .bmp_data()
    );

    // 以真实首扇区供数；1801 是 921654 字节向上取整后的扇区数。
    function [7:0] card_byte;
        input [31:0] sector;
        input integer offset;
        begin
            case (sector)
                0: card_byte = strawberry[offset];
                1801: card_byte = apple[offset];
                3602: card_byte = watermelon[offset];
                default: card_byte = 8'h00;
            endcase
        end
    endfunction
    integer pos = -1;
    reg [31:0] sector_latched;
    always @(posedge clk) begin
        sd_valid <= 0;
        sd_end <= 0;
        if (rst) pos <= -1;
        else if (pos == -1) begin
            if (sd_req) begin
                sector_latched <= sd_addr;
                pos <= 0;
            end
        end else if (pos < 512) begin
            sd_valid <= 1;
            sd_data <= card_byte(sector_latched, pos);
            pos <= pos + 1;
        end else if (pos == 512) begin
            sd_end <= 1;
            pos <= 513;
        end else if (!sd_req) pos <= -1;
    end

    always @(posedge clk) begin
        if (!rst && scan_found) begin
            if (found_sector !== found * 1801 || found_w !== 640 || found_h !== 480) begin
                $display("ERROR official scan #%0d sector=%0d size=%0dx%0d", found, found_sector, found_w, found_h);
                errors = errors + 1;
            end
            found = found + 1;
        end
        // 每个头扇区结束时，压缩字段必须仍然等于原始头部里的零。
        if (!rst && sd_end && dut.compression !== 32'd0) begin
            $display("ERROR compression overwritten sector=%0d got=%h", sector_latched, dut.compression);
            errors = errors + 1;
        end
    end

    initial begin
        $readmemh("fixtures/official_strawberry_sector0.hex", strawberry);
        $readmemh("fixtures/official_apple_sector0.hex", apple);
        $readmemh("fixtures/official_watermelon_sector0.hex", watermelon);
        repeat (5) @(negedge clk);
        rst = 0;
        @(negedge clk); scan_start = 1;
        @(negedge clk); scan_start = 0;
        wait(scan_done);
        repeat (3) @(negedge clk);
        if (found != 3 || found_total != 3) begin
            $display("ERROR official images rejected: found=%0d total=%0d", found, found_total);
            errors = errors + 1;
        end
        // 写入握手保持低，验证装载头被接受并进入等待，不读取后续像素扇区。
        for (image = 0; image < 3; image = image + 1) begin
            rst = 1;
            repeat (3) @(negedge clk);
            rst = 0;
            repeat (2) @(negedge clk);
            load_sector = image * 1801;
            load_start = 1;
            @(negedge clk); load_start = 0;
            wait(write_req || load_error);
            @(negedge clk);
            if (!write_req || load_w !== 640 || load_h !== 480 || load_error) begin
                $display("ERROR official load #%0d rejected code=%0d", image, error_code);
                errors = errors + 1;
            end
        end
        if (errors != 0) $fatal(1, "FAIL official BMP header errors=%0d", errors);
        $display("PASS official BMP headers: scan 3/3, load 3/3, compression preserved");
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "FAIL official BMP header test timed out");
    end
endmodule
