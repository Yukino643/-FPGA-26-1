`timescale 1ns/1ps
// 真实管理器 + 提取的真实顶层CDC/转场；失败零提交，双成功恰好一次提交。
module tb_top_commit_order;
 reg video_clk=0,sd_card_clk=0,rst_video=1,rst_sd=1;
 reg scaler_done_toggle=0,vs_rise_v=0,keypulse=0,source_done=0,error=0;
 reg sd_init_done=1,sd_card_write_req=0,sd_card_write_req_ack=0,frame_write_finish_pulse=0;
 wire bmp_source_restart,scaler_start_tgl;
 wire bmp_load_done=source_done;
 integer scaler_starts=0;reg prev_start=0;
 `include "reg_source_scaler_gate.vh"
 always @(posedge sd_card_clk) if(!rst_sd)begin
   if(scaler_start_tgl!=prev_start)scaler_starts=scaler_starts+1;
   prev_start=scaler_start_tgl;
 end
 wire [1:0] write_buf_idx;reg [1:0]tr_mode_reg=2;
 wire bmp_display_commit_toggle,bmp_display_commit_pulse;
 wire [9:0]main_x=0;wire [8:0]main_y=0;
 wire tr_hold_load,tr_active,tr_fade_black;
 wire [7:0]tr_alpha;wire [9:0]tr_boundary;wire [1:0]tr_slide_axis;
 wire [20:0]page_a_base,page_b_base;
 wire loader_hold=display_submit_pending_sd|tr_hold_sync_sd[1];
 integer commits=0,k,n,prior,target_page;
 always #20 video_clk=~video_clk;always #5 sd_card_clk=~sd_card_clk;
 `include "reg_display_commit.vh"
 always @(posedge video_clk)if(!rst_video&&commit_pulse_v)commits=commits+1;
 sd_card_bmp_g u_loader(.clk(sd_card_clk),.rst(rst_sd),.key_next(1'b1),.key_auto(1'b1),.hold_load(loader_hold),
 .state_code(),.img_count(),.cur_img_w(),.cur_img_h(),.display_valid(),.source_restart(bmp_source_restart),
 .display_commit_toggle(bmp_display_commit_toggle),.display_commit_pulse(bmp_display_commit_pulse),
 .load_done(),.load_img_w(),.load_img_h(),.debug_status(),.write_finish_toggle(scaler_commit_toggle),
 .write_buf_idx(write_buf_idx),.disp_buf_idx(),.write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),
 .sd_init_done(1'b1),.sd_sec_read_abort(1'b0),.sd_sec_read(),.sd_sec_read_addr(),
 .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0));
 task press;begin @(negedge sd_card_clk);keypulse=1;@(negedge sd_card_clk);keypulse=0;end endtask
 task start;
 begin press;n=0;while(!u_loader.load_busy)begin @(negedge sd_card_clk);n=n+1;if(n>20)$fatal(1,"FAIL loader start");end
 target_page=write_buf_idx;prior=commits;repeat(8)@(negedge video_clk);
 end endtask
 task ack_new_source;
 begin
   @(negedge sd_card_clk);sd_card_write_req=1;
   repeat(5)@(negedge sd_card_clk);sd_card_write_req_ack=1;
   repeat(5)@(negedge sd_card_clk);sd_card_write_req=0;
   repeat(5)@(negedge sd_card_clk);sd_card_write_req_ack=0;
 end endtask
 task source_written;
 begin @(negedge sd_card_clk);frame_write_finish_pulse=1;
   @(negedge sd_card_clk);frame_write_finish_pulse=0;end endtask
 task source_complete;
 begin @(negedge sd_card_clk);source_done=1;@(negedge sd_card_clk);source_done=0;end endtask
 task writer_complete;
 begin @(negedge sd_card_clk);scaler_done_toggle=~scaler_done_toggle;repeat(12)@(negedge video_clk);end endtask
 task finish_display;
 begin
 repeat(12)@(negedge video_clk);
 if(commits!=prior+1 || u_loader.load_busy || !loader_hold || !tr_hold_load)
 $fatal(1,"FAIL success commit/hold commits=%0d expected=%0d",commits,prior+1);
 n=0;while(tr_hold_load)begin
 @(negedge video_clk);vs_rise_v=1;@(negedge video_clk);vs_rise_v=0;n=n+1;
 if(!loader_hold || n>70)$fatal(1,"FAIL hold/release");end
 repeat(8)@(negedge video_clk);
 if(loader_hold || page_a_base!==(target_page?21'h80000:21'd0))$fatal(1,"FAIL released target page");
 end endtask
 initial begin
 force u_loader.scan_done=1'b1;force u_loader.scan_found_valid=1'b0;force u_loader.bmp_ready=1'b1;
 force u_loader.fs_scan_error=8'd0;force u_loader.bmp_load_error=error;
 force u_loader.key_next_press=keypulse;force u_loader.load_done=source_done;
 repeat(3)@(negedge video_clk);rst_video=0;rst_sd=0;
 u_loader.scan_kicked=1;u_loader.first_image_committed=1;u_loader.display_valid=1;
 u_loader.img_found_count=3;u_loader.img_idx=0;
 // 源写先完成，但解析尚未成功，不能启动scaler/提交视频。
 start;ack_new_source;source_written;
 repeat(12)@(negedge video_clk);
 if(commits!=prior || scaler_starts!=0 || loader_hold || !u_loader.load_busy)
 $fatal(1,"FAIL source writer bypassed parser success");
 source_complete;repeat(6)@(negedge sd_card_clk);
 if(scaler_starts!=1)$fatal(1,"FAIL both source completions did not start scaler");
 writer_complete;finish_display;
 // 错误发生在源写已齐、解析未成功阶段：禁止遗留旧scaler任务。
 start;ack_new_source;source_written;
 @(negedge sd_card_clk);error=1;@(negedge sd_card_clk);error=0;
 repeat(12)@(negedge video_clk);
 if(commits!=prior || loader_hold || !u_loader.load_retry_used || scaler_starts!=1)
 $fatal(1,"FAIL failed attempt started scaler");
 // 重试头部期间旧writer迟到，不继承；新源done独自不能启动缩放。
 source_written;ack_new_source;source_complete;repeat(12)@(negedge video_clk);
 if(scaler_starts!=1 || commits!=prior)$fatal(1,"FAIL stale writer event inherited");
 source_written;repeat(6)@(negedge sd_card_clk);writer_complete;finish_display;
 // 解析成功、源写完成与错误同拍，错误必须取消本次启动。
 start;ack_new_source;
 @(negedge sd_card_clk);source_done=1;frame_write_finish_pulse=1;error=1;
 @(negedge sd_card_clk);source_done=0;frame_write_finish_pulse=0;error=0;
 repeat(12)@(negedge video_clk);
 if(commits!=prior || scaler_starts!=2 || loader_hold)$fatal(1,"FAIL simultaneous error source completion");
 ack_new_source;source_written;source_complete;repeat(6)@(negedge sd_card_clk);writer_complete;finish_display;
 // 后续按键及所有转场模式继续；同域pending与manager结束同拍锁装载。
 for(k=0;k<8;k=k+1)begin
   tr_mode_reg=k%4;start;ack_new_source;source_complete;source_written;
   repeat(6)@(negedge sd_card_clk);writer_complete;finish_display;
 end
 if(scaler_starts!=11)$fatal(1,"FAIL duplicate/missing scaler start");
 $display("TB_TOP_COMMIT_ORDER PASS success_commits=%0d failed_commits=0 retries=2 stale_writer=blocked scaler_starts=11",commits);$finish;
 end
 initial begin #300000;$fatal(1,"FAIL top commit timeout");end
endmodule
