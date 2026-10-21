`timescale 1ns/1ps

module tb_fat32_bmp_index;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg scan_start = 1'b0;
    reg [3:0] target_count = 4'd2;
    wire busy, scan_done;
    wire [7:0] error_code;
    wire [31:0] partition_lba, fat_start_lba, data_start_lba, max_cluster;
    wire [7:0] sectors_per_cluster;
    wire [2:0] sectors_per_cluster_shift;
    wire [3:0] found_total;
    wire found_valid;
    wire [31:0] found_cluster, found_size;
    wire sector_req;
    wire [31:0] sector_lba;
    reg sector_valid = 1'b0;
    reg [8:0] sector_byte_index = 9'd0;
    reg [7:0] sector_byte = 8'd0;
    reg sector_done = 1'b0;
    reg [7:0] sector_error = 8'd0;

    reg card_active = 1'b0;
    reg [31:0] active_lba = 32'd0;
    reg [8:0] card_byte_index = 9'd0;
    reg [7:0] disk [0:16383];
    reg [31:0] seen_cluster0 = 32'd0, seen_cluster1 = 32'd0;
    reg [31:0] seen_size0 = 32'd0, seen_size1 = 32'd0;
    integer seen_count = 0;
    integer i, cycles, partition_slot, entry, spc_test;

    fat32_bmp_index #(
        .MAX_IMAGES(8), .MAX_ROOT_CLUSTERS(16), .TIMEOUT_CYCLES(20000)
    ) dut (
        .clk(clk), .rst(rst), .scan_start(scan_start), .target_count(target_count),
        .busy(busy), .scan_done(scan_done), .error_code(error_code),
        .partition_lba(partition_lba), .sectors_per_cluster(sectors_per_cluster),
        .sectors_per_cluster_shift(sectors_per_cluster_shift),
        .fat_start_lba(fat_start_lba), .data_start_lba(data_start_lba),
        .max_cluster(max_cluster), .found_total(found_total),
        .found_valid(found_valid), .found_cluster(found_cluster), .found_size(found_size),
        .sector_req(sector_req), .sector_lba(sector_lba), .sector_busy(card_active),
        .sector_valid(sector_valid), .sector_byte_index(sector_byte_index),
        .sector_byte(sector_byte), .sector_done(sector_done), .sector_error(sector_error)
    );

    // 模拟扇区读接口：每个请求严格返回 512 个带索引的字节。
    always @(posedge clk) begin
        if (rst) begin
            card_active <= 1'b0;
            active_lba <= 32'd0;
            card_byte_index <= 9'd0;
            sector_valid <= 1'b0;
            sector_byte_index <= 9'd0;
            sector_byte <= 8'd0;
            sector_done <= 1'b0;
        end else begin
            sector_valid <= 1'b0;
            sector_done <= 1'b0;
            if (!card_active && sector_req) begin
                card_active <= 1'b1;
                active_lba <= sector_lba;
                card_byte_index <= 9'd0;
            end else if (card_active) begin
                sector_valid <= 1'b1;
                sector_byte_index <= card_byte_index;
                sector_byte <= disk[active_lba * 512 + card_byte_index];
                if (card_byte_index == 9'd511) begin
                    sector_done <= 1'b1;
                    card_active <= 1'b0;
                end else begin
                    card_byte_index <= card_byte_index + 9'd1;
                end
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            seen_count <= 0;
            seen_cluster0 <= 0;
            seen_cluster1 <= 0;
            seen_size0 <= 0;
            seen_size1 <= 0;
        end else if (found_valid) begin
            if (seen_count == 0) begin
                seen_cluster0 <= found_cluster;
                seen_size0 <= found_size;
            end else if (seen_count == 1) begin
                seen_cluster1 <= found_cluster;
                seen_size1 <= found_size;
            end
            seen_count <= seen_count + 1;
        end
    end

    task put_byte;
        input integer lba;
        input integer offset;
        input [7:0] value;
        begin
            disk[lba * 512 + offset] = value;
        end
    endtask

    task put_bpb;
        input integer lba;
        begin
            put_byte(lba, 0, 8'heb);
            put_byte(lba, 11, 8'h00); put_byte(lba, 12, 8'h02);
            put_byte(lba, 13, 8'd2);
            put_byte(lba, 14, 8'd1); put_byte(lba, 15, 8'd0);
            put_byte(lba, 16, 8'd1);
            put_byte(lba, 17, 8'd0); put_byte(lba, 18, 8'd0);
            put_byte(lba, 19, 8'd0); put_byte(lba, 20, 8'd0);
            put_byte(lba, 22, 8'd0); put_byte(lba, 23, 8'd0);
            put_byte(lba, 32, 8'd100); put_byte(lba, 33, 8'd0);
            put_byte(lba, 34, 8'd0); put_byte(lba, 35, 8'd0);
            put_byte(lba, 36, 8'd1); put_byte(lba, 37, 8'd0);
            put_byte(lba, 38, 8'd0); put_byte(lba, 39, 8'd0);
            put_byte(lba, 44, 8'd2); put_byte(lba, 45, 8'd0);
            put_byte(lba, 46, 8'd0); put_byte(lba, 47, 8'd0);
            put_byte(lba, 510, 8'h55); put_byte(lba, 511, 8'haa);
        end
    endtask

    task put_entry;
        input integer lba;
        input integer slot;
        input [7:0] first_name_byte;
        input [7:0] attr;
        input [7:0] ext0, ext1, ext2;
        input [31:0] cluster;
        input [31:0] size;
        integer base;
        integer j;
        begin
            base = slot * 32;
            for (j = 0; j < 11; j = j + 1)
                put_byte(lba, base + j, 8'h20);
            put_byte(lba, base + 0, first_name_byte);
            put_byte(lba, base + 8, ext0);
            put_byte(lba, base + 9, ext1);
            put_byte(lba, base + 10, ext2);
            put_byte(lba, base + 11, attr);
            put_byte(lba, base + 20, cluster[16 +: 8]);
            put_byte(lba, base + 21, cluster[24 +: 8]);
            put_byte(lba, base + 26, cluster[0 +: 8]);
            put_byte(lba, base + 27, cluster[8 +: 8]);
            put_byte(lba, base + 28, size[0 +: 8]);
            put_byte(lba, base + 29, size[8 +: 8]);
            put_byte(lba, base + 30, size[16 +: 8]);
            put_byte(lba, base + 31, size[24 +: 8]);
        end
    endtask

    task fill_dummy_directory_sector;
        input integer lba;
        integer slot;
        begin
            for (slot = 0; slot < 16; slot = slot + 1)
                put_entry(lba, slot, 8'h58, 8'h20, "T", "X", "T", 32'd0, 32'd0);
        end
    endtask

    task pulse_scan;
        begin
            @(negedge clk); scan_start = 1'b1;
            @(negedge clk); scan_start = 1'b0;
            cycles = 0;
            while (!scan_done && cycles < 10000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!scan_done) begin
                $display("ERROR FAT32 index timed out, busy=%b error=%h", busy, error_code);
                $finish;
            end
        end
    endtask

    initial begin
        for (i = 0; i < 16384; i = i + 1)
            disk[i] = 8'd0;

        // MBR: 第一个 FAT32 分区位于 LBA 1。
        put_byte(0, 450, 8'h0c);
        put_byte(0, 454, 8'd1); put_byte(0, 455, 0);
        put_byte(0, 456, 0); put_byte(0, 457, 0);
        put_byte(0, 510, 8'h55); put_byte(0, 511, 8'haa);
        put_bpb(1);

        // 根目录簇 2 -> 碎片簇 4；前两簇含非 BMP、删除项、目录和 LFN。
        put_byte(2, 8, 8'd4);
        fill_dummy_directory_sector(3);
        fill_dummy_directory_sector(4);
        put_entry(3, 0, 8'h52, 8'h20, "T", "X", "T", 32'd0, 32'd10);
        put_entry(3, 1, 8'he5, 8'h20, "B", "M", "P", 32'd5, 32'd100);
        put_entry(3, 2, 8'h44, 8'h10, "B", "M", "P", 32'd5, 32'd100);
        put_entry(3, 3, 8'h41, 8'h0f, "B", "M", "P", 32'd5, 32'd100);
        put_entry(7, 0, 8'h53, 8'h20, "B", "M", "P", 32'd5, 32'd921654);
        put_entry(7, 1, 8'h41, 8'h20, "b", "m", "p", 32'd9, 32'd543);

        repeat (4) @(negedge clk);
        rst = 1'b0;
        pulse_scan();
        if (error_code != 0 || found_total != 2 || seen_count != 2 ||
            partition_lba != 1 || sectors_per_cluster != 2 || fat_start_lba != 2 ||
            data_start_lba != 3 || max_cluster != 50 ||
            seen_cluster0 != 5 || seen_size0 != 921654 ||
            seen_cluster1 != 9 || seen_size1 != 543) begin
            $display("ERROR MBR/root-chain scan: err=%h count=%0d seen=%0d part=%0d data=%0d max=%0d c0=%0d s0=%0d c1=%0d s1=%0d",
                     error_code, found_total, seen_count, partition_lba, data_start_lba,
                     max_cluster, seen_cluster0, seen_size0, seen_cluster1, seen_size1);
            $finish;
        end

        // SPC legality is captured with BPB byte 13 and must reject malformed values.
        for (spc_test = 0; spc_test < 3; spc_test = spc_test + 1) begin
            case (spc_test)
                0: put_byte(1, 13, 8'd0);
                1: put_byte(1, 13, 8'd3);
                default: put_byte(1, 13, 8'd255);
            endcase
            pulse_scan();
            if (error_code != 8'h21 || found_total != 0)
                $fatal(1, "FAIL invalid sectors-per-cluster value=%0d error=%h", disk[1*512+13], error_code);
        end
        put_byte(1, 13, 8'd2);
        pulse_scan();
        if (error_code != 0 || found_total != 2)
            $fatal(1, "FAIL valid SPC rescan after invalid values error=%h count=%0d", error_code, found_total);

        // 连续扫描且不复位，验证四个MBR槽位的选择与新扫描清零不会串扰。
        for (partition_slot = 1; partition_slot < 4; partition_slot = partition_slot + 1) begin
            for (entry = 0; entry < 4; entry = entry + 1) begin
                put_byte(0, 450 + 16*entry, entry == partition_slot ? 8'h0b : 8'h07);
                put_byte(0, 454 + 16*entry, entry == partition_slot ? 8'd1 : 8'd31);
            end
            @(negedge clk); seen_count = 0;
            pulse_scan();
            if (error_code != 0 || partition_lba != 1 || found_total != 2 || seen_count != 2 ||
                seen_cluster0 != 5 || seen_size0 != 921654 || seen_cluster1 != 9 || seen_size1 != 543)
                $fatal(1, "FAIL MBR slot/rescan slot=%0d part=%0d error=%h", partition_slot, partition_lba, error_code);
        end

        // 超级软盘格式：BPB 直接位于 LBA 0，根目录仍需跟随 FAT 簇链。
        @(negedge clk); rst = 1'b1;
        for (i = 0; i < 512; i = i + 1)
            put_byte(0, i, 8'd0);
        put_bpb(0);
        put_byte(1, 8, 8'd4);
        fill_dummy_directory_sector(2);
        fill_dummy_directory_sector(3);
        put_entry(6, 0, 8'h57, 8'h20, "B", "M", "P", 32'd11, 32'd1000);
        put_entry(6, 1, 8'h4d, 8'h20, "B", "M", "P", 32'd14, 32'd2000);
        repeat (3) @(negedge clk);
        rst = 1'b0;
        pulse_scan();
        if (error_code != 0 || found_total != 2 || seen_count != 2 ||
            partition_lba != 0 || data_start_lba != 2 ||
            seen_cluster0 != 11 || seen_size0 != 1000 ||
            seen_cluster1 != 14 || seen_size1 != 2000) begin
            $display("ERROR superfloppy scan: err=%h count=%0d part=%0d data=%0d c0=%0d s0=%0d c1=%0d s1=%0d",
                     error_code, found_total, partition_lba, data_start_lba,
                     seen_cluster0, seen_size0, seen_cluster1, seen_size1);
            $finish;
        end

        // 空根目录不能假设无限存在，目录簇链结束后要报告“无 BMP”。
        @(negedge clk); rst = 1'b1;
        fill_dummy_directory_sector(6);
        fill_dummy_directory_sector(7);
        put_byte(1, 16, 8'hf8); put_byte(1, 17, 8'hff);
        put_byte(1, 18, 8'hff); put_byte(1, 19, 8'h0f);
        repeat (3) @(negedge clk);
        rst = 1'b0;
        pulse_scan();
        if (error_code != 8'h22 || found_total != 0 || seen_count != 0) begin
            $display("ERROR empty root scan: err=%h count=%0d", error_code, found_total);
            $finish;
        end

        $display("PASS FAT32 index: four MBR slots, rescan without reset, superfloppy, BMP filtering, fragmented root chain, empty card");
        $finish;
    end
endmodule
