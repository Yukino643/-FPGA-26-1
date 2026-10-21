`timescale 1ns/1ps
// 直接提取当前顶层的 HDMI-A 时序/缩放/渲染/输出寄存，检查真实连接相位。
module tb_monitor_pipeline;
    reg video_clk=0, rst_video=1;
    always #5 video_clk=~video_clk;
    wire [1:0] mon_menu_active_sync=2'b11, mon_menu_page_sync=0;
    wire [2:0] mon_cursor_sync1=0;
    wire [1:0] mon_dirty_sync=0, mon_buzzer_sync=0, mon_sd_init_sync=3;
    wire [1:0] mon_period_shadow_sync1=0, mon_period_active_sync1=0;
    wire [2:0] mon_key_state_sync1=0;
    wire [15:0] mon_key_events_sync1=0;
    wire [3:0] mon_img_count_sync1=7, mon_led_state_sync1=3;
    wire [3:0] cfg_preview_video=7, cfg_active_video=7;
    wire cfg_commit_seen_video=0;
    wire [1:0] mon_screen_page_sync=0, mon_screen_edit_sync=0, mon_cfg_busy_sync=0;
    wire [9:0] screen_preview_video=10'h144, screen_active_video=10'h144;
    wire [1:0] mon_subtitle_page_sync=0, mon_subtitle_edit_sync=0;
    wire [4:0] subtitle_preview_video=5'h08, subtitle_active_video=5'h08;
    `include "reg_monitor_pipeline.vh"
    reg [2:0] de_ref=0, hs_ref=0, vs_ref=0;
    reg [10:0] x_ref0=0, x_ref1=0, x_ref2=0;
    reg [9:0] y_ref0=0, y_ref1=0, y_ref2=0;
    integer logical_x, logical_y, pixels=0, border_pixels=0, blank_pixels=0;
    always @(posedge video_clk) begin
        if(rst_video) begin de_ref=0; hs_ref=0; vs_ref=0; end
        else begin
            de_ref={de_ref[1:0],mon_de}; hs_ref={hs_ref[1:0],mon_hs}; vs_ref={vs_ref[1:0],mon_vs};
            x_ref2=x_ref1;x_ref1=x_ref0; x_ref0=mon_x_full;
            y_ref2=y_ref1;y_ref1=y_ref0; y_ref0=mon_y_full;
            #1;
            if(mon_de_d3!==de_ref[2] || mon_hs_d3!==hs_ref[2] || mon_vs_d3!==vs_ref[2])
                $fatal(1,"HDMI-A sync latency");
            if(mon_de_d3) begin
                pixels=pixels+1;
                if(x_ref2<160 || x_ref2>=1120) begin
                    if(mon_rgb!==0) $fatal(1,"letterbox RGB alignment");
                    blank_pixels=blank_pixels+1;
                end else begin
                    logical_x=((x_ref2-160)*2)/3; logical_y=(y_ref2*2)/3;
                    // 独立按逻辑卡片边界核对，覆盖放大后的第一/最后像素。
                    if(logical_x>=24 && logical_x<208 && logical_y>=88 && logical_y<248 &&
                       (logical_x<27 || logical_x>=205 || logical_y<91 || logical_y>=245)) begin
                        if(mon_rgb!==24'hFFD166) $fatal(1,"selected border x=%0d y=%0d RGB=%h",x_ref2,y_ref2,mon_rgb);
                        border_pixels=border_pixels+1;
                    end
                end
            end else if(mon_rgb!==0) $fatal(1,"blanking RGB alignment");
        end
    end
    initial begin
        repeat(5) @(negedge video_clk); rst_video=0;
        repeat(1650*750+8) @(negedge video_clk);
        if(pixels<921600 || border_pixels==0 || blank_pixels<230400) $fatal(1,"monitor coverage");
        $display("TB_MONITOR_PIPELINE PASS pixels=%0d borders=%0d",pixels,border_pixels); $finish;
    end
    initial begin #13000000; $fatal(1,"monitor pipeline timeout"); end
endmodule
