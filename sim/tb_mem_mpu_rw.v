`timescale 1ns/1ps
// 使用真实官方装载 FSM 与仲裁器，覆盖显示读在途时启动源写的交接。
module tb_mem_mpu_rw;
    reg clk=0, rst=1;
    always #4 clk=~clk;
    reg request=0, a_valid=0;
    wire ack, finish, source_busy, read_busy, write_ready, a_ready;
    wire wr_en, rd_en;
    wire [20:0] wr_addr, rd_addr;
    reg [2:0] response_pipe=0;
    integer writes=0, reads=0, returns=0;
    frame_fifo_write #(.WRITE_V_FLIP(0),.BURST_SIZE(16)) u_writer(
        .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
        .App_rd_busy(read_busy),.O_wr_busy(source_busy),.App_wr_en(wr_en),.App_wr_addr(wr_addr),
        .write_req(request),.write_req_ack(ack),.write_finish(finish),
        .write_addr_0(21'd1000),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
        .write_addr_index(2'd0),.write_len(21'd64),.fifo_aclr(),.rdusedw(10'd64));
    mem_mpu u_mpu(
        .clk(clk),.rst(rst),
        .A_cmd_valid(a_valid),.A_cmd_addr(21'd0),.A_cmd_len(8'd16),.A_cmd_ready(a_ready),.A_rsp_valid(),.A_rsp_data(),.A_rsp_last(),
        .B_cmd_valid(1'b0),.B_cmd_addr(21'd0),.B_cmd_len(8'd1),.B_cmd_ready(),.B_rsp_valid(),.B_rsp_data(),.B_rsp_last(),
        .C_cmd_valid(1'b0),.C_cmd_addr(21'd0),.C_cmd_len(8'd1),.C_cmd_ready(),.C_rsp_valid(),.C_rsp_data(),.C_rsp_last(),
        .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(response_pipe[2]),.Sdr_rd_dout(32'd0),
        .Sdr_init_done(1'b1),.Sdr_busy(1'b0),.source_write_busy(source_busy),.scaler_write_request(1'b0),.read_busy(read_busy),.write_ready(write_ready),
        .App_wr_en_u(wr_en),.App_wr_addr_u(wr_addr),.App_wr_din_u(32'd0),.App_wr_dm_u(4'd0),
        .App_wr2_en_u(1'b0),.App_wr2_addr_u(21'd0),.App_wr2_din_u(32'd0),.App_wr2_dm_u(4'd0),.wr2_active(1'b0),
        .App_wr_en(),.App_wr_addr(),.App_wr_din(),.App_wr_dm());
    always @(posedge clk) begin
        response_pipe <= rst ? 3'd0 : {response_pipe[1:0],rd_en};
        if(!rst) begin
            if(a_ready) reads=reads+1;
            if(response_pipe[2]) returns=returns+1;
            if(wr_en) begin
                if(read_busy || rd_en || response_pipe!=0) begin $display("FAIL source write interrupted read"); $fatal(1); end
                if(wr_addr !== 1000+writes) begin $display("FAIL source write address %0d",wr_addr); $fatal(1); end
                writes=writes+1;
            end
            if(a_ready && source_busy) begin $display("FAIL accepted read during source write reservation"); $fatal(1); end
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst=0; a_valid=1;
        wait(read_busy); @(negedge clk); request=1;
        wait(ack); @(negedge clk); request=0;
        wait(finish); repeat(100) @(negedge clk);
        if(writes!=64 || reads<2 || returns<32) begin $display("FAIL coverage w=%0d r=%0d returns=%0d",writes,reads,returns); $fatal(1); end
        $display("TB_MEM_MPU_RW PASS writes=%0d read_bursts=%0d",writes,reads); $finish;
    end
    initial begin #20000; $display("FAIL source write arbitration timeout"); $fatal(1); end
endmodule
