`timescale 1ns/1ps

module tb_fat32_file_sector_mapper;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg file_start = 1'b0;
    reg [31:0] first_cluster = 32'd5;
    reg [31:0] file_size = 32'd2048;
    reg [7:0] sectors_per_cluster = 8'd2;
    reg [2:0] sectors_per_cluster_shift = 3'd1;
    reg [31:0] fat_start_lba = 32'd10;
    reg [31:0] data_start_lba = 32'd100;
    reg [31:0] max_cluster = 32'd20;
    reg client_req = 1'b0;
    reg [31:0] client_sector_index = 32'd0;
    wire busy, client_done, client_error;
    wire [7:0] client_data;
    wire client_data_valid;
    wire sector_req;
    wire [31:0] sector_lba;
    reg sector_valid = 1'b0;
    reg [8:0] sector_byte_index = 9'd0;
    reg [7:0] sector_byte = 8'd0;
    reg sector_done = 1'b0;
    reg [7:0] sector_error = 8'd0;

    reg card_active = 1'b0;
    reg stall_card = 1'b0;
    reg [31:0] active_lba = 32'd0;
    reg [8:0] card_byte_index = 9'd0;
    reg [7:0] fat_sector [0:511];
    reg [31:0] lba_log [0:63];
    integer physical_count = 0;
    integer client_data_count = 0;
    integer i, cycles, shift_test;
    reg [31:0] expected_lba;

    fat32_file_sector_mapper #(
        .MAX_CHAIN_STEPS(32), .TIMEOUT_CYCLES(2000)
    ) dut (
        .clk(clk), .rst(rst), .file_start(file_start), .first_cluster(first_cluster),
        .file_size(file_size), .sectors_per_cluster(sectors_per_cluster),
        .sectors_per_cluster_shift(sectors_per_cluster_shift),
        .fat_start_lba(fat_start_lba), .data_start_lba(data_start_lba),
        .max_cluster(max_cluster), .client_req(client_req),
        .client_sector_index(client_sector_index), .busy(busy),
        .client_done(client_done), .client_error(client_error),
        .client_data(client_data), .client_data_valid(client_data_valid),
        .sector_req(sector_req), .sector_lba(sector_lba), .sector_busy(card_active),
        .sector_valid(sector_valid), .sector_byte_index(sector_byte_index),
        .sector_byte(sector_byte), .sector_done(sector_done), .sector_error(sector_error)
    );

    // 每次物理扇区响应返回 512 字节；FAT 项按小端序模拟。
    always @(posedge clk) begin
        if (rst) begin
            card_active <= 1'b0;
            active_lba <= 32'd0;
            card_byte_index <= 9'd0;
            sector_valid <= 1'b0;
            sector_byte_index <= 9'd0;
            sector_byte <= 8'd0;
            sector_done <= 1'b0;
            physical_count <= 0;
            client_data_count <= 0;
        end else begin
            sector_valid <= 1'b0;
            sector_done <= 1'b0;
            if (client_data_valid)
                client_data_count <= client_data_count + 1;
            if (!card_active && sector_req) begin
                card_active <= 1'b1;
                active_lba <= sector_lba;
                card_byte_index <= 9'd0;
                lba_log[physical_count] <= sector_lba;
                physical_count <= physical_count + 1;
            end else if (card_active && !stall_card) begin
                sector_valid <= 1'b1;
                sector_byte_index <= card_byte_index;
                if (active_lba == 32'd10)
                    sector_byte <= fat_sector[card_byte_index];
                else
                    sector_byte <= active_lba[7:0] ^ card_byte_index[7:0];
                if (card_byte_index == 9'd511) begin
                    sector_done <= 1'b1;
                    card_active <= 1'b0;
                end else begin
                    card_byte_index <= card_byte_index + 9'd1;
                end
            end
        end
    end

    task pulse_file_start;
        begin
            @(negedge clk); file_start = 1'b1;
            @(negedge clk); file_start = 1'b0;
        end
    endtask

    task request_sector;
        input [31:0] logical_sector;
        input [31:0] expected_physical_lba;
        integer wait_cycles;
        begin
            @(negedge clk);
            client_sector_index = logical_sector;
            client_req = 1'b1;
            wait_cycles = 0;
            while (!client_done && wait_cycles < 10000) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
                // 接受后客户端总线可以变化，遍历必须只使用锁存请求。
                if (wait_cycles == 1) client_sector_index = ~logical_sector;
            end
            if (!client_done || client_error) begin
                $display("ERROR map sector %0d: done=%b error=%b", logical_sector, client_done, client_error);
                $finish;
            end
            if (lba_log[physical_count-1] != expected_physical_lba) begin
                $display("ERROR map sector %0d -> LBA %0d, expected %0d",
                         logical_sector, lba_log[physical_count-1], expected_physical_lba);
                $finish;
            end
            @(negedge clk); client_req = 1'b0;
            wait_cycles = 0;
            while (busy && wait_cycles < 20) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
        end
    endtask

    task request_error;
        input [31:0] logical_sector;
        integer wait_cycles;
        begin
            @(negedge clk);
            client_sector_index = logical_sector;
            client_req = 1'b1;
            wait_cycles = 0;
            while (!client_done && wait_cycles < 10000) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!client_done || !client_error) begin
                $display("ERROR expected mapper failure at sector %0d: done=%b error=%b",
                         logical_sector, client_done, client_error);
                $finish;
            end
            @(negedge clk); client_req = 1'b0;
        end
    endtask

    initial begin
        for (i = 0; i < 512; i = i + 1)
            fat_sector[i] = 8'd0;
        // FAT[5] = 9：文件的第二个簇不连续。
        fat_sector[20] = 8'd9;
        fat_sector[21] = 8'd0;
        fat_sector[22] = 8'd0;
        fat_sector[23] = 8'd0;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        pulse_file_start();

        // 头扇区被读两次；随后连续读完簇 5，再按 FAT 跳到簇 9。
        request_sector(32'd0, 32'd106);
        request_sector(32'd0, 32'd106);
        request_sector(32'd1, 32'd107);
        request_sector(32'd2, 32'd114);
        request_sector(32'd3, 32'd115);
        if (physical_count != 6 || client_data_count != 5 * 512 ||
            lba_log[0] != 106 || lba_log[1] != 106 || lba_log[2] != 107 ||
            lba_log[3] != 10 || lba_log[4] != 114 || lba_log[5] != 115) begin
            $display("ERROR fragmented chain transactions=%0d bytes=%0d",
                     physical_count, client_data_count);
            $finish;
        end

        // 同一文件向后请求再向前跨碎片簇，准备结果不能阻断回退/遍历。
        request_sector(32'd0, 32'd106);
        request_sector(32'd3, 32'd115);

        // 文件长度恰好落在声明范围内；读完最后一个扇区不要求簇链额外 EOC。
        @(negedge clk);
        file_size = 32'd1536;
        fat_sector[20] = 8'hf8; fat_sector[21] = 8'hff;
        fat_sector[22] = 8'hff; fat_sector[23] = 8'h0f;
        pulse_file_start();
        request_error(32'd2);

        // FAT 自环必须作为坏链退出，而不是重复读同一个簇。
        @(negedge clk);
        fat_sector[20] = 8'd5; fat_sector[21] = 8'd0;
        fat_sector[22] = 8'd0; fat_sector[23] = 8'd0;
        pulse_file_start();
        request_error(32'd2);

        // 首簇越界立即返回错误，不发起 SD 事务。
        @(negedge clk); first_cluster = 32'd1; file_size = 32'd512;
        pulse_file_start();
        request_error(32'd0);

        // The largest BMP byte size must round up without truncating its sector bound.
        @(negedge clk); first_cluster = 32'd5; file_size = 32'hffffffff;
        pulse_file_start();
        request_error(32'd8388608);

        // 拆拍LBA运算的独立乘法参考：全部合法簇大小、簇内首尾及32位进位。
        // 只在sector_req时采样最终地址；不得把流水中间值当成实际读请求。
        for (shift_test = 0; shift_test < 8; shift_test = shift_test + 1) begin
            @(negedge clk);
            first_cluster = 32'h001fffff;
            max_cluster = 32'h0ffffff6;
            sectors_per_cluster = 8'd1 << shift_test;
            sectors_per_cluster_shift = shift_test;
            file_size = sectors_per_cluster * 512;
            data_start_lba = 32'h70fffffe;
            pulse_file_start();
            expected_lba = data_start_lba + (first_cluster - 2) * sectors_per_cluster;
            request_sector(0, expected_lba);
            expected_lba = expected_lba + sectors_per_cluster - 1;
            request_sector(sectors_per_cluster - 1, expected_lba);
        end

        // 超时路径：外部不返回扇区数据，映射器必须有界报错。
        @(negedge clk); first_cluster = 32'd5; stall_card = 1'b1;
        pulse_file_start();
        @(negedge clk); client_sector_index = 0; client_req = 1'b1;
        cycles = 0;
        while (!client_done && cycles < 3000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (!client_done || !client_error) begin
            $display("ERROR mapper timeout was not bounded");
            $finish;
        end

        $display("PASS FAT32 mapper: fragmented clusters, repeated sector 0, file bound, invalid cluster, timeout");
        $finish;
    end
endmodule
