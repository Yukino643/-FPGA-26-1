// tb_afifo_boundary.v — 异步 FIFO 空读/满写/顺序边界测试
`timescale 1ns/1ps
module tb_afifo_boundary;
    localparam AW = 3;
    localparam DEPTH = 1 << AW;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg wr_rst = 1'b1;
    reg rd_rst = 1'b1;
    reg wr_en = 1'b0;
    reg rd_en = 1'b0;
    reg [31:0] wr_data = 32'd0;
    wire wr_full;
    wire [AW:0] wr_usedw;
    wire [31:0] rd_data;
    wire rd_empty;
    wire [AW:0] rd_usedw;

    integer i;
    integer errors = 0;
    reg [AW:0] ptr_hold;

    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    afifo_simple #(.DW(32), .AW(AW)) u_dut (
        .wr_clk(wr_clk), .wr_rst(wr_rst), .wr_en(wr_en), .wr_data(wr_data),
        .wr_full(wr_full), .wr_usedw(wr_usedw),
        .rd_clk(rd_clk), .rd_rst(rd_rst), .rd_en(rd_en), .rd_data(rd_data),
        .rd_empty(rd_empty), .rd_usedw(rd_usedw)
    );

    initial begin
        #50;
        @(negedge wr_clk); wr_rst = 1'b0;
        @(negedge rd_clk); rd_rst = 1'b0;

        // 空读不得推进读指针。
        wait (rd_empty);
        ptr_hold = u_dut.rbin;
        rd_en = 1'b1;
        repeat (3) @(posedge rd_clk);
        rd_en = 1'b0;
        #1;
        if (u_dut.rbin !== ptr_hold) begin
            $display("FAIL empty read moved rbin: %0d -> %0d", ptr_hold, u_dut.rbin);
            errors = errors + 1;
        end

        // 写满整个 FIFO。
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge wr_clk);
            wr_en = 1'b1;
            wr_data = 32'h1000 + i;
        end
        @(negedge wr_clk); wr_en = 1'b0;
        wait (wr_full);

        // 满写不得推进写指针。
        ptr_hold = u_dut.wbin;
        wr_en = 1'b1;
        wr_data = 32'hDEADBEEF;
        repeat (3) @(posedge wr_clk);
        wr_en = 1'b0;
        #1;
        if (u_dut.wbin !== ptr_hold) begin
            $display("FAIL full write moved wbin: %0d -> %0d", ptr_hold, u_dut.wbin);
            errors = errors + 1;
        end

        // 顺序读出全部有效数据，溢出尝试不得污染内容。
        wait (!rd_empty);
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge rd_clk); rd_en = 1'b1;
            // FWFT 消费发生在上升沿；NBA 后输出已是下一队头。
            @(posedge rd_clk);
            if (rd_data !== (32'h1000 + i)) begin
                $display("FAIL data[%0d]: got=%h expected=%h", i, rd_data, 32'h1000 + i);
                errors = errors + 1;
            end
        end
        @(negedge rd_clk); rd_en = 1'b0;
        wait (rd_empty);
        ptr_hold = u_dut.rbin;
        repeat (2) begin
            @(negedge rd_clk); rd_en = 1'b1;
            @(posedge rd_clk);
        end
        rd_en = 1'b0;
        #1;
        if (u_dut.rbin !== ptr_hold) begin
            $display("FAIL final empty read moved rbin");
            errors = errors + 1;
        end

        if (errors == 0) $display("TB_AFIFO_BOUNDARY PASS");
        else $display("TB_AFIFO_BOUNDARY FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("TB_AFIFO_BOUNDARY TIMEOUT");
        $finish;
    end
endmodule
