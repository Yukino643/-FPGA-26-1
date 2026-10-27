// tb_sd_arbiter.v — SD 单扇区仲裁协议验证
// 覆盖：轮转公平、请求保持到 done、释放等待、防重复发起、超时复位。
`timescale 1ns/1ps
module tb_sd_arbiter;
    reg clk = 1'b0, rst = 1'b1;
    always #5 clk = ~clk;
    reg a_req = 1'b0, b_req = 1'b0;
    reg [31:0] a_addr = 32'h1000, b_addr = 32'h2000;
    wire a_ack, b_ack, a_data_valid, b_data_valid, a_done, b_done;
    wire [7:0] a_data, b_data;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    reg [7:0] sd_sec_read_data = 8'd0;
    reg sd_sec_read_data_valid = 1'b0, sd_sec_read_end = 1'b0;
    wire a_timeout, b_timeout, controller_reset_req;
    wire [1:0] owner;
    reg respond = 1'b1;
    reg pending_end = 1'b0;
    integer read_starts = 0;
    integer errors = 0;

    sd_arbiter #(.TIMEOUT_CYCLES(8)) u_dut(
        .clk(clk), .rst(rst),
        .a_req(a_req), .a_addr(a_addr), .a_ack(a_ack), .a_data(a_data),
        .a_data_valid(a_data_valid), .a_done(a_done), .a_timeout(a_timeout),
        .b_req(b_req), .b_addr(b_addr), .b_ack(b_ack), .b_data(b_data),
        .b_data_valid(b_data_valid), .b_done(b_done), .b_timeout(b_timeout),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid), .sd_sec_read_end(sd_sec_read_end),
        .controller_reset_req(controller_reset_req), .owner(owner)
    );

    always @(posedge clk) begin
        if (rst) begin
            sd_sec_read_data_valid <= 1'b0;
            sd_sec_read_end <= 1'b0;
            pending_end <= 1'b0;
            read_starts <= 0;
        end else begin
            sd_sec_read_data_valid <= 1'b0;
            sd_sec_read_end <= 1'b0;
            if (sd_sec_read) begin
                read_starts <= read_starts + 1;
                if (respond)
                    pending_end <= 1'b1;
            end else if (pending_end) begin
                sd_sec_read_data <= (sd_sec_read_addr == a_addr) ? 8'hA1 : 8'hB2;
                sd_sec_read_data_valid <= 1'b1;
                sd_sec_read_end <= 1'b1;
                pending_end <= 1'b0;
            end
        end
    end

    initial begin
        #40;
        rst = 1'b0;
        a_req = 1'b1;
        b_req = 1'b1;
        wait (b_ack);
        if (owner !== 2'd2 || sd_sec_read_addr !== b_addr) errors = errors + 1;
        wait (b_done);
        repeat (3) @(posedge clk);
        if (read_starts !== 1) errors = errors + 1;
        b_req = 1'b0;

        wait (a_ack);
        if (owner !== 2'd1 || sd_sec_read_addr !== a_addr) errors = errors + 1;
        wait (a_done);
        a_req = 1'b0;
        if (read_starts !== 2) errors = errors + 1;

        repeat (2) @(posedge clk);
        respond = 1'b0;
        b_req = 1'b1;
        wait (b_timeout);
        if (!controller_reset_req || !b_done) errors = errors + 1;
        b_req = 1'b0;

        if (errors == 0) $display("TB_SD_ARBITER PASS");
        else $display("TB_SD_ARBITER FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("TB_SD_ARBITER TIMEOUT");
        $finish;
    end
endmodule
