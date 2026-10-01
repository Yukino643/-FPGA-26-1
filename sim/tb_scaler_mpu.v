`timescale 1ns/1ps
// scaler 接入真实 mem_mpu 和 SDRAM 行为模型，验证硬件读返回协议。
module tb_scaler_mpu;
    reg clk=0, rst=1; always #4 clk=~clk;
    reg start_toggle=0;
    reg [10:0] cfg_w=640, cfg_h=480;
    wire c_v,c_r,c_rv,c_rl; wire [20:0] c_a; wire [7:0] c_l; wire [31:0] c_d;
    wire rd_en; wire [20:0] rd_addr; wire sd_v; wire [31:0] sd_d;
    wire wr_en; wire [20:0] wr_addr; wire [31:0] wr_din; wire [3:0] wr_dm;
    wire done_toggle, busy;
    mem_mpu #(.MAX_A_RUN(8),.MAX_B_RUN(8),.MAX_C_RUN(4)) u_mpu(
      .clk(clk),.rst(rst),
      .A_cmd_valid(1'b0),.A_cmd_addr(21'd0),.A_cmd_len(8'd0),.A_cmd_ready(),.A_rsp_valid(),.A_rsp_data(),.A_rsp_last(),
      .B_cmd_valid(1'b0),.B_cmd_addr(21'h8_0000),.B_cmd_len(8'd0),.B_cmd_ready(),.B_rsp_valid(),.B_rsp_data(),.B_rsp_last(),
      .C_cmd_valid(c_v),.C_cmd_addr(c_a),.C_cmd_len(c_l),.C_cmd_ready(c_r),.C_rsp_valid(c_rv),.C_rsp_data(c_d),.C_rsp_last(c_rl),
      .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(sd_v),.Sdr_rd_dout(sd_d),
      .Sdr_init_done(1'b1),.Sdr_busy(1'b0),
      .App_wr_en_u(1'b0),.App_wr_addr_u(21'd0),.App_wr_din_u(32'd0),.App_wr_dm_u(4'd0),
      .App_wr2_en_u(wr_en),.App_wr2_addr_u(wr_addr),.App_wr2_din_u(wr_din),.App_wr2_dm_u(wr_dm),.wr2_active(busy),
      .App_wr_en(),.App_wr_addr(),.App_wr_din(),.App_wr_dm());
    sdram_beh #(.LAT(8)) u_sdram(.clk(clk),.rst(rst),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_din),.wr_dm(wr_dm),.rd_en(rd_en),.rd_addr(rd_addr),.rd_vld(sd_v),.rd_dout(sd_d));
    scaler #(.OUT_W(64),.OUT_H(48)) u_scaler(
      .clk(clk),.rst(rst),.start_toggle(start_toggle),.cfg_w(cfg_w),.cfg_h(cfg_h),
      .cfg_src_base(21'hC_B000),.cfg_dst_base(21'h0),.cmd_valid(c_v),.cmd_addr(c_a),.cmd_len(c_l),.cmd_ready(c_r),
      .rsp_valid(c_rv),.rsp_data(c_d),.rsp_last(c_rl),.wr_en(wr_en),.wr_addr(wr_addr),.wr_din(wr_din),.wr_dm(wr_dm),.busy(busy),.done_toggle(done_toggle),.debug_state());
    integer cycles=0, reads=0, writes=0; reg prev_done=0;
    always @(posedge clk) begin
      if (!rst) begin
        cycles=cycles+1; if(c_v&&c_r) reads=reads+1; if(wr_en) writes=writes+1;
        if (wr_en && wr_dm !== 4'b0000) begin $display("FAIL scaler SDRAM byte mask=%b",wr_dm); $fatal(1); end
        if(done_toggle!=prev_done) $display("DONE cycles=%0d reads=%0d writes=%0d",cycles,reads,writes);
        prev_done=done_toggle;
        if(cycles%1000000==0) $display("PROGRESS cycles=%0d state=%0d busy=%b c_v=%b c_r=%b rv=%b reads=%0d writes=%0d",cycles,u_scaler.state,busy,c_v,c_r,c_rv,reads,writes);
      end
    end
    initial begin
      #100; rst=0; #100; start_toggle=1; wait(done_toggle); $display("TB_SCALER_MPU PASS"); $finish;
    end
    initial begin #2_000_000_000; $display("TB_SCALER_MPU TIMEOUT state=%0d busy=%b reads=%0d writes=%0d",u_scaler.state,busy,reads,writes); $finish; end
endmodule
