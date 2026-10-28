// 在 SPI 引脚层响应，覆盖初始化 FSM、命令层和 SPI 主机完整链路。
`timescale 1ns/1ps
module tb_sd_spi_chain;
    parameter integer HIGH_CAPACITY = 1;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    wire ncs, sck, mosi, init_done, valid, done;
    reg miso = 1;
    reg req = 0;
    reg [31:0] lba = 0;
    wire [7:0] data;
    integer errors = 0, cmd16_seen = 0, cmd58_seen = 0, bytes_seen = 0;
    integer command_count = 0;
    sd_card_top #(.SPI_LOW_SPEED_DIV(4), .SPI_HIGH_SPEED_DIV(0)) dut (
        .clk(clk), .rst(rst), .SD_nCS(ncs), .SD_DCLK(sck),
        .SD_MOSI(mosi), .SD_MISO(miso), .sd_init_done(init_done),
        .sd_sec_read(req), .sd_sec_read_addr(lba), .sd_sec_read_data(data),
        .sd_sec_read_data_valid(valid), .sd_sec_read_end(done),
        .sd_sec_write(1'b0), .sd_sec_write_addr(32'd0),
        .sd_sec_write_data(8'd0), .sd_sec_write_data_req(), .sd_sec_write_end()
    );

    // SD SPI 模型：下降沿给出 MISO，上升沿采样 MOSI；不 mock 内部 ACK。
    reg [7:0] rx = 0, tx = 8'hff;
    integer bit_idx = 0, command_pos = 0;
    reg [7:0] packet[0:5];
    reg [7:0] queue[0:2047];
    integer qread = 0, qwrite = 0, j;
    reg [31:0] argument, sector;
    reg [7:0] incoming;
    task enqueue;
        input [7:0] value;
        begin
            queue[qwrite] = value;
            qwrite = qwrite + 1;
        end
    endtask
    task respond;
        begin
            argument = {packet[1],packet[2],packet[3],packet[4]};
            command_count = command_count + 1;
            // 留出一字节响应延迟，验证命令层等待返回值的行为。
            enqueue(8'hff);
            case (packet[0] & 8'h3f)
                0: enqueue(8'h01);
                8: begin
                    enqueue(8'h01); enqueue(0); enqueue(0); enqueue(1); enqueue(8'haa);
                end
                55: enqueue(8'h01);
                41: enqueue(0);
                58: begin
                    cmd58_seen = cmd58_seen + 1;
                    enqueue(0);
                    enqueue(HIGH_CAPACITY ? 8'hc0 : 8'h80);
                    enqueue(8'hff); enqueue(8'h80); enqueue(0);
                end
                16: begin
                    cmd16_seen = cmd16_seen + 1;
                    if (HIGH_CAPACITY || argument != 512) begin
                        errors = errors + 1;
                        $display("ERROR CMD16 high_capacity=%0d arg=%0d", HIGH_CAPACITY, argument);
                    end
                    enqueue(0);
                end
                17: begin
                    if (argument != (HIGH_CAPACITY ? lba : (lba << 9))) begin
                        errors = errors + 1;
                        $display("ERROR CMD17 addressing arg=%0d lba=%0d", argument, lba);
                    end
                    sector = HIGH_CAPACITY ? argument : (argument >> 9);
                    enqueue(0); enqueue(8'hff); enqueue(8'hfe);
                    for (j=0; j<512; j=j+1) enqueue(j[7:0] ^ sector[7:0]);
                    enqueue(8'h12); enqueue(8'h34); // CRC 不得作为有效扇区数据输出
                end
                default: begin
                    errors = errors + 1;
                    $display("ERROR unexpected command %h", packet[0]);
                    enqueue(8'h04);
                end
            endcase
        end
    endtask
    always @(posedge ncs or posedge rst) begin
        bit_idx = 0;
        command_pos = 0;
        rx = 0;
        qread = 0;
        qwrite = 0;
        miso = 1;
    end
    always @(negedge sck) begin
        if (!ncs && !rst) begin
            if (bit_idx == 0) begin
                if (qread < qwrite) begin
                    tx = queue[qread];
                    qread = qread + 1;
                end else tx = 8'hff;
            end
            miso = tx[7-bit_idx];
        end else miso = 1;
    end
    always @(posedge sck) begin
        if (!ncs && !rst) begin
            incoming = {rx[6:0],mosi};
            rx = incoming;
            if (bit_idx == 7) begin
                bit_idx = 0;
                if (command_pos != 0 || incoming[7:6] == 2'b01) begin
                    packet[command_pos] = incoming;
                    if (command_pos == 5) begin
                        command_pos = 0;
                        respond;
                    end else command_pos = command_pos + 1;
                end
            end else bit_idx = bit_idx + 1;
        end
    end

    always @(posedge clk) begin
        if (!rst && valid) begin
            if (data !== (bytes_seen[7:0] ^ lba[7:0])) begin
                errors = errors + 1;
                $display("ERROR data #%0d got=%h lba=%0d", bytes_seen,data,lba);
            end
            bytes_seen = bytes_seen + 1;
        end
    end
    task read_sector;
        input [31:0] address;
        begin
            @(negedge clk); lba = address; bytes_seen = 0; req = 1;
            @(negedge clk); req = 0; // 与实际仲裁器一样，只向控制器发单拍请求
            wait(done);
            @(negedge clk);
            if (bytes_seen != 512) begin
                errors = errors + 1;
                $display("ERROR data length=%0d",bytes_seen);
            end
            repeat (6) @(negedge clk);
        end
    endtask
    initial begin
        repeat (5) @(negedge clk); rst = 0;
        wait(init_done);
        repeat (6) @(negedge clk);
        if (cmd58_seen != 1 || cmd16_seen != (HIGH_CAPACITY ? 0 : 1)) begin
            errors = errors + 1;
            $display("ERROR init command sequence CMD58=%0d CMD16=%0d",cmd58_seen,cmd16_seen);
        end
        read_sector(32'd2);
        read_sector(32'd1801);
        if (errors) $fatal(1,"FAIL SD SPI chain errors=%0d",errors);
        $display("PASS SD SPI chain high_capacity=%0d: init, addressing, two 512-byte sectors",HIGH_CAPACITY);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"FAIL SD SPI chain timeout init=%b cmd_count=%0d",init_done,command_count);
    end
endmodule
