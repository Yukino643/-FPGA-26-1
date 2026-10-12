// 老师第八讲的页所有权与预取原则：完整帧消费，突发不可中途撤销。
// 静态仅A读取；转场首帧alpha=0预取B，收尾帧alpha=255后才停止B。
module display_stream_720 #(
    parameter FRAME_WORDS=460800
)(
    input wire mem_clk, mem_rst, video_clk, video_rst,
    input wire vs_toggle, de_in, vs_in, tr_active,
    input wire [10:0] x,
    input wire [9:0] y,
    input wire [7:0] alpha,
    input wire [20:0] page_a_base, page_b_base,
    output wire a_cmd_valid, b_cmd_valid,
    output wire [20:0] a_cmd_addr, b_cmd_addr,
    output wire [7:0] a_cmd_len, b_cmd_len,
    input wire a_cmd_ready, b_cmd_ready,
    input wire a_rsp_valid, b_rsp_valid, a_rsp_last, b_rsp_last,
    input wire [31:0] a_rsp_data, b_rsp_data,
    output wire [23:0] rgb_out,
    output wire de_out, vs_out,
    output wire [10:0] x_out,
    output wire [9:0] y_out,
    output wire [31:0] underflow_cnt
);
    reg [20:0] a_base_meta, a_base_sync, b_base_meta, b_base_sync;
    always @(posedge mem_clk or posedge mem_rst) begin
        if (mem_rst) begin a_base_meta<=0; a_base_sync<=0; b_base_meta<=21'h80000; b_base_sync<=21'h80000; end
        else begin
            a_base_meta<=page_a_base; a_base_sync<=a_base_meta;
            b_base_meta<=page_b_base; b_base_sync<=b_base_meta;
        end
    end
    wire a_we,b_we,a_pop,b_pop,a_empty,b_empty,a_full,b_full;
    wire [31:0] a_wdata,b_wdata,a_data,b_data;
    wire [11:0] a_used,b_used;
    disp_read_engine #(.FRAME_WORDS(FRAME_WORDS), .HIGH_WATER(1792), .FIFO_USED_BITS(12)) u_a(
        .clk(mem_clk),.rst(mem_rst),.vs_toggle(vs_toggle),.page_base(a_base_sync),
        .scroll_x(10'd0),.frame_enable(1'b1),.fifo_we(a_we),.fifo_wdata(a_wdata),.fifo_wusedw(a_used),
        .cmd_valid(a_cmd_valid),.cmd_addr(a_cmd_addr),.cmd_len(a_cmd_len),.cmd_ready(a_cmd_ready),
        .rsp_valid(a_rsp_valid),.rsp_data(a_rsp_data),.rsp_last(a_rsp_last)
    );
    disp_read_engine #(.FRAME_WORDS(FRAME_WORDS), .HIGH_WATER(1792), .FIFO_USED_BITS(12), .GATE_ENABLE(1)) u_b(
        .clk(mem_clk),.rst(mem_rst),.vs_toggle(vs_toggle),.page_base(b_base_sync),
        .scroll_x(10'd0),.frame_enable(tr_active),.fifo_we(b_we),.fifo_wdata(b_wdata),.fifo_wusedw(b_used),
        .cmd_valid(b_cmd_valid),.cmd_addr(b_cmd_addr),.cmd_len(b_cmd_len),.cmd_ready(b_cmd_ready),
        .rsp_valid(b_rsp_valid),.rsp_data(b_rsp_data),.rsp_last(b_rsp_last)
    );
    afifo_simple #(.DW(32),.AW(11)) u_fifo_a(
        .wr_clk(mem_clk),.wr_rst(mem_rst),.wr_en(a_we),.wr_data(a_wdata),.wr_full(a_full),.wr_usedw(a_used),
        .rd_clk(video_clk),.rd_rst(video_rst),.rd_en(a_pop),.rd_data(a_data),.rd_empty(a_empty),.rd_usedw()
    );
    afifo_simple #(.DW(32),.AW(11)) u_fifo_b(
        .wr_clk(mem_clk),.wr_rst(mem_rst),.wr_en(b_we),.wr_data(b_wdata),.wr_full(b_full),.wr_usedw(b_used),
        .rd_clk(video_clk),.rd_rst(video_rst),.rd_en(b_pop),.rd_data(b_data),.rd_empty(b_empty),.rd_usedw()
    );
    disp_mixer_565 u_mixer(
        .clk(video_clk),.rst(video_rst),.de_in(de_in),.vs_in(vs_in),.x(x),.y(y),
        .a_data(a_data),.b_data(b_data),.a_empty(a_empty),.b_empty(b_empty),.tr_active(tr_active),.alpha(alpha),
        .a_pop(a_pop),.b_pop(b_pop),.de_out(de_out),.vs_out(vs_out),.x_out(x_out),.y_out(y_out),
        .rgb_out(rgb_out),.underflow_cnt(underflow_cnt)
    );
    // synthesis translate_off
    always @(posedge mem_clk) if (!mem_rst && ((a_we && a_full)||(b_we && b_full)))
        $fatal(1,"720p display FIFO overflow");
    // synthesis translate_on
endmodule
