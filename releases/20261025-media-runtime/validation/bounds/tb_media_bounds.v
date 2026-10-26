
`timescale 1ns/1ps
module timeout_check #(parameter T=17)(output reg finished=0);
reg clk=0,rst=1,start=0,done=0;
always #5 clk=~clk;
wire busy,scan_done;wire [7:0] error;
fat32_bmp_index #(.TIMEOUT_CYCLES(T)) dut(.clk(clk),.rst(rst),.scan_start(start),
 .target_count(4'd1),.busy(busy),.scan_done(scan_done),.error_code(error),
 .sector_busy(1'b0),.sector_valid(1'b0),.sector_byte_index(9'd0),
 .sector_byte(8'd0),.sector_done(done),.sector_error(8'd0));
integer n,trial;
initial begin
 for(trial=0;trial<2;trial=trial+1)begin
  rst=1;repeat(3)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
  while(dut.state!=2)@(negedge clk);
  for(n=1;n<=T;n=n+1)begin
   if(trial==1 && n==T)done=1;
   @(posedge clk);#1;
   if(n<T && (dut.state!=2 || scan_done))$fatal(1,"early timeout T=%0d n=%0d",T,n);
   if(n==T && trial==0 && (!scan_done || error!=8'h30))
    $fatal(1,"timeout boundary T=%0d state=%0d error=%h",T,dut.state,error);
   if(n==T && trial==1 && (dut.state!=11 || error!=0))
    $fatal(1,"sector_done priority T=%0d",T);
   @(negedge clk);
  end
  done=0;
 end
 finished=1;
end
endmodule
module tb_media_bounds;
wire a,b,c;
timeout_check #(.T(1)) t1(a);
timeout_check #(.T(2)) t2(b);
timeout_check #(.T(17)) t17(c);
reg clk=0,rst=1;
always #5 clk=~clk;
raw_video_player #(.EXTERNAL_FS(1)) player(.clk(clk),.rst(rst),.sd_init_done(1'b1),
 .sd_abort(1'b0),.hold_load(1'b1),.write_finish_toggle(1'b0),.write_req_ack(1'b0),
 .fs_busy_i(1'b0),.fs_done_i(1'b0),.fs_found_i(1'b0),.fs_error_i(8'd0),
 .fs_total_i(4'd0),.fs_cluster_i(32'd0),.fs_size_i(32'd0),.fs_sector_o(),
 .fs_data_i(8'd0),.fs_valid_i(1'b0),.fs_client_done_i(1'b0),.fs_client_error_i(1'b0),
 .sd_data(8'd0),.sd_valid(1'b0),.sd_done(1'b0));
integer n;reg [63:0] expected;
initial begin
 repeat(4)@(negedge clk);rst=0;
 player.header[0]=32'h36315652;player.header[1]={16'd320,16'd1};
 player.header[2]={16'd10,16'd180};player.header[4]=115200;
 player.header[5]=512;player.header[6]=1;
 for(n=1;n<=65535;n=n+1)begin
  @(negedge clk);player.header[3]=n;player.state=5;
  repeat(2)@(posedge clk);#1;
  expected=64'd512+64'd115200*n;
  if(player.state!=6 || player.expected_size!==expected[32:0])
   $fatal(1,"RV16 size n=%0d got=%0d expected=%0d",n,player.expected_size,expected);
  // 超过4GiB的文件不得因32位截断而被接纳。
  if(expected[32])begin
   @(negedge clk);player.file_size=expected[31:0];
   @(posedge clk);#1;if(player.error_code!=8'h43)$fatal(1,"size overflow accepted");
  end
 end
 wait(a&&b&&c);
 $display("PASS media_bounds timeout 1/2/17 exact edge and done priority; sizes 1..65535, overflow rejected");
 $finish;
end
initial begin #10000000;$fatal(1,"bounds timeout");end
endmodule
