`timescale 1ns/1ps
module tb_sd_card_init;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg sd_sec_read = 1'b0;
    reg [31:0] sd_sec_read_addr = 32'd0;
    wire [7:0] sd_sec_read_data;
    wire sd_sec_read_data_valid, sd_sec_read_end;
    reg sd_sec_write = 1'b0;
    reg [31:0] sd_sec_write_addr = 32'd0;
    reg [7:0] sd_sec_write_data = 8'd0;
    wire sd_sec_write_data_req, sd_sec_write_end;
    wire sd_init_done, cmd_req;
    reg cmd_req_ack = 1'b0, cmd_req_error = 1'b0;
    wire [47:0] cmd;
    wire [7:0] cmd_r1;
    wire [15:0] cmd_data_len, spi_clk_div;
    reg cmd_data_valid = 1'b0;
    reg [7:0] cmd_data_byte = 8'd0;
    wire block_read_req, block_write_req;
    reg block_read_valid = 1'b0, block_read_req_ack = 1'b0;
    reg [7:0] block_read_data = 8'd0;
    wire [7:0] block_write_data;
    reg block_write_data_rd = 1'b0, block_write_req_ack = 1'b0;

    integer errors = 0;
    integer watchdog = 0;

    sd_card_sec_read_write #(
        .SPI_LOW_SPEED_DIV(8),
        .SPI_HIGH_SPEED_DIV(0)
    ) dut (
        .clk(clk), .rst(rst), .sd_init_done(sd_init_done),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data), .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end), .sd_sec_write(sd_sec_write),
        .sd_sec_write_addr(sd_sec_write_addr), .sd_sec_write_data(sd_sec_write_data),
        .sd_sec_write_data_req(sd_sec_write_data_req), .sd_sec_write_end(sd_sec_write_end),
        .spi_clk_div(spi_clk_div), .cmd_req(cmd_req), .cmd_req_ack(cmd_req_ack),
        .cmd_req_error(cmd_req_error), .cmd(cmd), .cmd_r1(cmd_r1),
        .cmd_data_len(cmd_data_len), .cmd_data_valid(cmd_data_valid),
        .cmd_data_byte(cmd_data_byte), .block_read_req(block_read_req),
        .block_read_valid(block_read_valid), .block_read_data(block_read_data),
        .block_read_req_ack(block_read_req_ack), .block_write_req(block_write_req),
        .block_write_data(block_write_data), .block_write_data_rd(block_write_data_rd),
        .block_write_req_ack(block_write_req_ack)
    );

    task expect_command;
        input [7:0] command_index;
        input [31:0] argument;
        input check_argument;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while (!cmd_req && wait_cycles < 100) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (wait_cycles == 100) begin
                $display("FAIL: timeout waiting CMD%0d", command_index);
                errors = errors + 1;
            end else begin
                #1;
                if (cmd[47:40] !== command_index) begin
                    $display("FAIL: expected CMD%0d, got CMD%0d", command_index, cmd[47:40]);
                    errors = errors + 1;
                end
                if (check_argument && cmd[39:8] !== argument) begin
                    $display("FAIL: CMD%0d arg expected %08x got %08x", command_index, argument, cmd[39:8]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task acknowledge_command;
        begin
            @(negedge clk);
            cmd_req_ack = 1'b1;
            cmd_req_error = 1'b0;
            @(negedge clk);
            cmd_req_ack = 1'b0;
        end
    endtask

    task send_ocr;
        input high_capacity;
        integer i;
        begin
            for (i = 0; i < 4; i = i + 1) begin
                @(negedge clk);
                cmd_data_valid = 1'b1;
                cmd_data_byte = (i == 0) ? (high_capacity ? 8'hC0 : 8'h80) : 8'h00;
                // CMD58 最后一个 OCR 字节与完成应答同拍，验证边界握手。
                cmd_req_ack = (i == 3);
                cmd_req_error = 1'b0;
            end
            @(negedge clk);
            cmd_data_valid = 1'b0;
            cmd_req_ack = 1'b0;
        end
    endtask

    task run_card_case;
        input high_capacity;
        reg [31:0] expected_read_arg;
        reg [31:0] expected_write_arg;
        begin
            rst = 1'b1;
            repeat (3) @(negedge clk);
            rst = 1'b0;

            expect_command(8'd0, 32'd0, 1'b0); acknowledge_command;
            if (sd_init_done) errors = errors + 1;
            expect_command(8'd8, 32'd0, 1'b0); acknowledge_command;
            expect_command(8'd55, 32'd0, 1'b0); acknowledge_command;
            expect_command(8'd41, 32'd0, 1'b0); acknowledge_command;
            expect_command(8'd58, 32'd0, 1'b0);
            if (sd_init_done) errors = errors + 1;
            send_ocr(high_capacity);

            if (high_capacity) begin
                if (!sd_init_done) begin
                    $display("FAIL: SDHC not ready after valid OCR");
                    errors = errors + 1;
                end
            end else begin
                if (sd_init_done) errors = errors + 1;
                expect_command(8'd16, 32'd512, 1'b1);
                acknowledge_command;
                if (!sd_init_done) begin
                    $display("FAIL: SDSC not ready after CMD16");
                    errors = errors + 1;
                end
            end

            expected_read_arg = high_capacity ? 32'h00001234 : 32'h00246800;
            expected_write_arg = high_capacity ? 32'h00000010 : 32'h00002000;
            @(negedge clk);
            sd_sec_read_addr = 32'h00001234;
            sd_sec_read = 1'b1;
            @(negedge clk);
            sd_sec_read = 1'b0;
            expect_command(8'd17, expected_read_arg, 1'b1);
            acknowledge_command;
            repeat (2) @(negedge clk);
            block_read_req_ack = 1'b1;
            @(negedge clk);
            block_read_req_ack = 1'b0;
            repeat (2) @(negedge clk);

            sd_sec_write_addr = 32'h00000010;
            sd_sec_write = 1'b1;
            @(negedge clk);
            sd_sec_write = 1'b0;
            expect_command(8'd24, expected_write_arg, 1'b1);
            acknowledge_command;
            repeat (2) @(negedge clk);
            block_write_req_ack = 1'b1;
            @(negedge clk);
            block_write_req_ack = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        run_card_case(1'b1);
        run_card_case(1'b0);
        if (errors == 0) $display("TB_SD_CARD_INIT PASS");
        else $display("TB_SD_CARD_INIT FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #1000000;
        $display("TB_SD_CARD_INIT TIMEOUT");
        $finish;
    end
endmodule
