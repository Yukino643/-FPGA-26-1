`timescale 1ns/1ps
module tb_mem_mpu_overlap;
    reg clk=0, rst=1; always #4 clk=~clk;
    reg init_done=0, sdr_busy=0;
    reg c_valid=0;
    reg [20:0] c_addr=0;
    reg [7:0] c_len=0;
    wire c_ready, c_rsp, c_last;
    wire [31:0] c_data;
    wire rd_en; wire [20:0] rd_addr;
    reg [2:0] valid_pipe=0;
    reg [20:0] addr_pipe[0:2];
    wire sdr_rd_en=valid_pipe[2];
    wire [31:0] sdr_rd_data={11'h35a,addr_pipe[2]};
    integer got=0, lasts=0, cycles=0;
    reg [20:0] expected=21'd1000;

    mem_mpu #(.MAX_A_RUN(2),.MAX_B_RUN(2),.MAX_C_RUN(2)) dut(
      .clk(clk),.rst(rst),
      .A_cmd_valid(1'b0),.A_cmd_addr(21'd0),.A_cmd_len(8'd1),.A_cmd_ready(),.A_rsp_valid(),.A_rsp_data(),.A_rsp_last(),
      .B_cmd_valid(1'b0),.B_cmd_addr(21'd0),.B_cmd_len(8'd1),.B_cmd_ready(),.B_rsp_valid(),.B_rsp_data(),.B_rsp_last(),
      .C_cmd_valid(c_valid),.C_cmd_addr(c_addr),.C_cmd_len(c_len),.C_cmd_ready(c_ready),.C_rsp_valid(c_rsp),.C_rsp_data(c_data),.C_rsp_last(c_last),
      .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(sdr_rd_en),.Sdr_rd_dout(sdr_rd_data),
      .Sdr_init_done(init_done),.Sdr_busy(sdr_busy),
      .App_wr_en_u(1'b0),.App_wr_addr_u(21'd0),.App_wr_din_u(32'd0),.App_wr_dm_u(4'd0),
      .App_wr2_en_u(1'b0),.App_wr2_addr_u(21'd0),.App_wr2_din_u(32'd0),.App_wr2_dm_u(4'd0),
      .wr2_active(1'b0),.App_wr_en(),.App_wr_addr(),.App_wr_din(),.App_wr_dm());

    integer i;
    always @(posedge clk) begin
      valid_pipe[2] <= valid_pipe[1];
      valid_pipe[1] <= valid_pipe[0];
      valid_pipe[0] <= rd_en;
      if(rd_en) addr_pipe[0] <= rd_addr;
      addr_pipe[1] <= addr_pipe[0];
      addr_pipe[2] <= addr_pipe[1];
      if(!rst) begin
        cycles <= cycles+1;
        if(c_rsp) begin
          if(c_data[20:0] !== expected) begin
            $display("FAIL response[%0d]=%0d expected=%0d",got,c_data[20:0],expected);
            $fatal(1);
          end
          got <= got+1;
          expected <= expected+1'b1;
          if(c_last) lasts <= lasts+1;
        end
      end
    end

    initial begin
      #40; rst=0; c_valid=1; c_addr=21'd1000; c_len=8'd8;
      repeat(6) begin @(posedge clk); if(c_ready) begin $display("FAIL accepted before initialization"); $fatal(1); end end
      init_done=1; sdr_busy=1;
      repeat(4) begin @(posedge clk); if(c_ready) begin $display("FAIL accepted while controller busy"); $fatal(1); end end
      sdr_busy=0;
      wait(c_ready); @(posedge clk); c_valid=0;
      wait(lasts==1); repeat(14) @(posedge clk);
      if(got!=8 || lasts!=1) begin $display("FAIL got=%0d last=%0d",got,lasts); $fatal(1); end
      $display("TB_MEM_MPU_OVERLAP PASS got=%0d cycles=%0d",got,cycles);
      $finish;
    end
    initial begin #20000; $display("FAIL timeout state=%0d got=%0d",dut.state,got); $fatal(1); end
endmodule
