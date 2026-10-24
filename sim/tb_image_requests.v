`timescale 1ns/1ps
// 控制器真实 RTL，边界事件由环境注入；不以镜像状态机替代被测实现。
module tb_image_requests;
 reg clk=0,rst=1,key=1,hold_load=1,keypulse=0,source_done=0,finish=0,err=0;
 integer i,n,switched=0,old_img,old_page;
 always #5 clk=~clk;
 sd_card_bmp_g #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.key_next(key),.key_auto(1'b1),.hold_load(hold_load),
 .state_code(),.img_count(),.cur_img_w(),.cur_img_h(),.display_valid(),.load_done(),.load_img_w(),.load_img_h(),.debug_status(),
 .write_finish_toggle(1'b0),.write_buf_idx(),.disp_buf_idx(),.write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),
 .sd_init_done(1'b1),.sd_sec_read_abort(1'b0),.sd_sec_read(),.sd_sec_read_addr(),.sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0));
 task press;begin keypulse=1;@(negedge clk);keypulse=0;@(negedge clk);end endtask
 task start_load;
 begin
   n=0;while(!dut.load_busy)begin @(negedge clk);n=n+1;if(n>30)$fatal(1,"FAIL next request stalled count=%0d",dut.next_req_count);end
   if(dut.load_idx!==(dut.img_idx+1)%3 || dut.write_buf_idx==dut.disp_buf_idx)
     $fatal(1,"FAIL next image/page target current=%0d target=%0d",dut.img_idx,dut.load_idx);
   hold_load=1;old_img=dut.img_idx;old_page=dut.disp_buf_idx;
 end endtask
 task complete;
 input integer order;
 begin
   source_done=0;finish=0;
   if(order==0)begin source_done=1;@(negedge clk);source_done=0;repeat(2)@(negedge clk);
     if(!dut.load_busy)$fatal(1,"FAIL committed without writer");finish=1;end
   else if(order==1)begin finish=1;@(negedge clk);finish=0;repeat(2)@(negedge clk);
     if(!dut.load_busy)$fatal(1,"FAIL committed without source");source_done=1;end
   else begin source_done=1;finish=1;end
   @(negedge clk);source_done=0;finish=0;
   if(dut.load_busy || dut.img_idx!==(old_img+1)%3 || dut.disp_buf_idx===old_page ||
      dut.source_done_seen || dut.write_finish_seen)$fatal(1,"FAIL completion order=%0d",order);
   switched=switched+1;hold_load=0;
 end endtask
 initial begin
   force dut.scan_done=1'b1;force dut.scan_found_valid=1'b0;force dut.bmp_ready=1'b1;
   force dut.fs_scan_error=8'd0;force dut.bmp_load_error=err;
   force dut.key_next_press=keypulse;force dut.load_done=source_done;force dut.write_finish_pulse=finish;
   repeat(3)@(negedge clk);rst=0;
   dut.scan_kicked=1;dut.first_image_committed=1;dut.display_valid=1;
   dut.img_found_count=3;dut.img_idx=0;dut.load_busy=0;
   // 同拍消费与按下净计数为0，且等待转场期间不装载。
   press;if(dut.next_req_count!=1)$fatal(1,"FAIL queue insert");
   keypulse=1;hold_load=0;@(negedge clk);keypulse=0;
   if(dut.next_req_count!=1 || !dut.load_busy)$fatal(1,"FAIL concurrent enqueue/dequeue");
   hold_load=1;old_img=0;old_page=dut.disp_buf_idx;complete(2);start_load;complete(1);
   // 300个积压请求在255饱和，不回绕到0；处理后能继续收到新请求。
   hold_load=1;for(i=0;i<300;i=i+1)press;
   if(dut.next_req_count!=255 || dut.load_busy)$fatal(1,"FAIL saturation/hold");
   hold_load=0;
   for(i=0;i<255;i=i+1)begin start_load;complete(i%3);end
   if(dut.next_req_count!=0)$fatal(1,"FAIL queue drain");
   for(i=0;i<400;i=i+1)begin press;start_load;complete(i%3);end
   // 恢复真实消抖，物理长按只生成一次，释放后可以反复按。
   release dut.key_next_press;
   for(i=0;i<20;i=i+1)begin
     hold_load=1;key=0;repeat(35)@(negedge clk);
     if(dut.next_req_count!=1)$fatal(1,"FAIL physical key one request");
     repeat(35)@(negedge clk);if(dut.next_req_count!=1)$fatal(1,"FAIL held key repeats");
     key=1;repeat(35)@(negedge clk);hold_load=0;start_load;complete(i%3);
   end
   force dut.key_next_press=keypulse;
   // 当前图是唯一好图时不得跳向坏图0。
   hold_load=1;dut.failed_mask=8'h03;dut.img_idx=2;#1;
   if(dut.next_from_current!=2)$fatal(1,"FAIL single good fallback");
   // 全部图片被屏蔽后自动等待；新手动请求启动一次恢复。
   dut.failed_mask=8'h07;dut.next_req_count=0;repeat(5)@(negedge clk);
   if(dut.load_busy)$fatal(1,"FAIL all-bad automatic loop");
   press;if(dut.failed_mask!=0)$fatal(1,"FAIL manual all-bad recovery");
   hold_load=0;start_load;
   // 错误与完成同拍必须优先撤销，且重试不能继承旧完成事件。
   err=1;source_done=1;finish=1;@(negedge clk);err=0;source_done=0;finish=0;
   if(!dut.load_busy || !dut.load_retry_used || dut.source_done_seen || dut.write_finish_seen)
     $fatal(1,"FAIL error event priority");
   complete(0);
   $display("TB_IMAGE_REQUESTS PASS switches=%0d physical_keys=20 saturated=255 orders=3",switched);$finish;
 end
 initial begin #3000000;$fatal(1,"FAIL image requests timeout");end
endmodule
