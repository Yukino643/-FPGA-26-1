// tb_bmp_read_g_timeout.v — BMP 读取器超时恢复测试
// 使用较小的仿真参数把 500 ms 保护窗口压缩到 2 ms，验证 SD 卡不响应时
// 状态机能够返回 ERR_TIMEOUT，而不是永久保持在 ST_LOAD_HDR。
`timescale 1ns/1ps
module tb_bmp_read_g_timeout;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sd_init_done = 1'b1;
    always #500 clk = ~clk;  // 1 MHz

    reg         load_start = 1'b0;
    reg  [31:0] load_sector = 32'd0;
    wire        ready;
    wire        load_done;
    wire        load_error;
    wire [3:0]  error_code;
    wire        load_active;
    wire        write_req;
    reg         write_req_ack = 1'b0;
    wire        sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    wire [3:0]  state_code;
    wire        bmp_data_wr_en;
    wire [23:0] bmp_data;

    bmp_read_g #(
        .MAX_IMAGES         (8),
        .MAX_DIM            (2047),
        .CLK_FREQ_HZ        (1_000_000),
        .SD_READ_TIMEOUT_MS (2)
    ) dut (
        .clk                    (clk),
        .rst                    (rst),
        .ready                  (ready),
        .scan_start             (1'b0),
        .scan_start_sector      (32'd0),
        .scan_max_sector        (32'd0),
        .scan_target_count      (4'd0),
        .scan_done              (),
        .scan_found_valid       (),
        .scan_found_sector      (),
        .scan_found_total       (),
        .scan_found_w           (),
        .scan_found_h           (),
        .load_start             (load_start),
        .load_sector            (load_sector),
        .load_done              (load_done),
        .load_error             (load_error),
        .error_code             (error_code),
        .load_active            (load_active),
        .load_img_w             (),
        .load_img_h             (),
        .sd_init_done           (sd_init_done),
        .state_code             (state_code),
        .write_req              (write_req),
        .write_req_ack          (write_req_ack),
        // 故意不返回任何 data_valid/end，模拟 SD 卡或仲裁器无响应。
        .sd_sec_read            (sd_sec_read),
        .sd_sec_read_addr      (sd_sec_read_addr),
        .sd_sec_read_data       (8'd0),
        .sd_sec_read_data_valid (1'b0),
        .sd_sec_read_end        (1'b0),
        .sd_sec_read_error      (1'b0),
        .bmp_data_wr_en         (bmp_data_wr_en),
        .bmp_data               (bmp_data)
    );

    integer cycles;
    integer errors;
    // 对照原有超时定义，约束预测到期标志不能提前或迟一拍。
    always @(negedge clk) begin
        if (!rst && dut.timeout_hit !== (dut.read_state && dut.timeout_cnt >= 32'd2000))
            $fatal(1, "FAIL timeout cycle equivalence count=%0d hit=%b", dut.timeout_cnt, dut.timeout_hit);
    end
    initial begin
        errors = 0;
        #3000;
        rst = 1'b0;
        @(negedge clk);
        load_start = 1'b1;
        @(negedge clk);
        load_start = 1'b0;

        cycles = 0;
        while (!load_error && cycles < 4000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!load_error) begin
            errors = errors + 1;
            $display("ERR timeout did not fire within 4000 cycles");
        end else if (error_code !== 4'd2) begin
            errors = errors + 1;
            $display("ERR timeout code=%0d expected=2", error_code);
        end

        @(posedge clk);
        if (!ready || load_active || sd_sec_read) begin
            errors = errors + 1;
            $display("ERR timeout recovery state ready=%b active=%b sd_read=%b",
                     ready, load_active, sd_sec_read);
        end

        // 到期前SD失效必须取消，重新初始化后的请求仍有完整的超时窗口。
        @(negedge clk); load_start = 1'b1;
        @(negedge clk); load_start = 1'b0;
        wait(dut.timeout_cnt == 1999);
        @(negedge clk); sd_init_done = 1'b0;
        repeat(3) @(negedge clk);
        if (!ready || load_error || dut.timeout_cnt != 0)
            $fatal(1, "FAIL timeout cancellation");
        sd_init_done = 1'b1; load_start = 1'b1;
        @(negedge clk); load_start = 1'b0;
        cycles = 0;
        while (!load_error && cycles < 4000) begin
            @(negedge clk); cycles = cycles + 1;
        end
        if (!load_error || error_code != 2 || cycles < 2000)
            $fatal(1, "FAIL timeout restart cycles=%0d error=%h", cycles, error_code);
        if (errors == 0)
            $display("TB_BMP_READ_G_TIMEOUT PASS");
        else
            $display("TB_BMP_READ_G_TIMEOUT FAIL errors=%0d", errors);
        $finish;
    end
endmodule
