// tb_disp_read_engine.v — 验证末字完成条件与长 VS 电平不会重复启动
`timescale 1ns/1ps
module tb_disp_read_engine;
    localparam FRAME_WORDS = 10;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg vs_toggle = 1'b0;
    reg [20:0] page_base = 21'h120;
    reg cmd_ready = 1'b0;
    reg rsp_valid = 1'b0;
    reg [31:0] rsp_data = 32'd0;
    reg rsp_last = 1'b0;
    wire fifo_we;
    wire [31:0] fifo_wdata;
    wire cmd_valid;
    wire [20:0] cmd_addr;
    wire [7:0] cmd_len;

    integer errors = 0;
    integer words = 0;
    integer starts = 0;
    integer beats_left = 0;

    always #4 clk = ~clk;

    disp_read_engine #(.FRAME_WORDS(FRAME_WORDS), .BURST(4), .HIGH_WATER(8)) u_dut (
        .clk(clk), .rst(rst), .vs_toggle(vs_toggle), .page_base(page_base),
        .fifo_we(fifo_we), .fifo_wdata(fifo_wdata), .fifo_wusedw(10'd0),
        .cmd_valid(cmd_valid), .cmd_addr(cmd_addr), .cmd_len(cmd_len),
        .cmd_ready(cmd_ready), .rsp_valid(rsp_valid), .rsp_data(rsp_data), .rsp_last(rsp_last)
    );

    always @(posedge clk) begin
        cmd_ready <= 1'b0;
        rsp_valid <= 1'b0;
        rsp_last <= 1'b0;
        if (cmd_valid && beats_left == 0) begin
            cmd_ready <= 1'b1;
            beats_left <= cmd_len;
        end else if (beats_left != 0) begin
            rsp_valid <= 1'b1;
            rsp_data <= 32'hCAFE0000 + words;
            rsp_last <= (beats_left == 1);
            beats_left <= beats_left - 1;
        end
        if (fifo_we)
            words <= words + 1;
        if (u_dut.go_pend && !u_dut.in_burst)
            starts <= starts + 1;
    end

    initial begin
        #40;
        @(negedge clk); rst = 1'b0;
        repeat (3) @(posedge clk);
        // toggle 只变化一次；之后保持高电平，接收端应只产生一个事件。
        @(negedge clk); vs_toggle = 1'b1;
        wait (words == FRAME_WORDS);
        wait (!u_dut.frame_act);
        repeat (10) @(posedge clk);

        if (u_dut.word_cnt !== FRAME_WORDS) begin
            $display("FAIL word_cnt=%0d expected=%0d", u_dut.word_cnt, FRAME_WORDS);
            errors = errors + 1;
        end
        if (words != FRAME_WORDS) begin
            $display("FAIL fifo words=%0d expected=%0d", words, FRAME_WORDS);
            errors = errors + 1;
        end
        if (starts != 1) begin
            $display("FAIL starts=%0d expected=1", starts);
            errors = errors + 1;
        end

        if (errors == 0) $display("TB_DISP_READ_ENGINE PASS");
        else $display("TB_DISP_READ_ENGINE FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("TB_DISP_READ_ENGINE TIMEOUT");
        $finish;
    end
endmodule
