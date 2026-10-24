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
    wire [1:0] mon_audio_page_sync=0, mon_audio_edit_sync=0;
    wire [4:0] audio_preview_video=10,audio_active_video=10;
    wire [1:0] mon_screen_page_sync=0, mon_screen_edit_sync=0, mon_cfg_busy_sync=0;
    wire [9:0] screen_preview_video=10'h144, screen_active_video=10'h144;
    wire [1:0] mon_subtitle_page_sync=0, mon_subtitle_edit_sync=0;
    wire [4:0] subtitle_preview_video=5'h08, subtitle_active_video=5'h08;
    `include "reg_monitor_pipeline.vh"
    reg [2:0] de_ref=0, hs_ref=0, vs_ref=0;
    reg [10:0] x_ref0=0, x_ref1=0, x_ref2=0;
    reg [9:0] y_ref0=0, y_ref1=0, y_ref2=0;
    integer logical_x, logical_y, pixels=0, border_pixels=0, edge_pixels=0;
    reg [23:0] first_in_pair, previous_row[0:1279];
    integer column,row,idx,x0,y0,w,thickness,left_count=0,right_count=0,top_count=0,bottom_count=0;
    reg [23:0] expected_border;
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
                if(mon_rgb===24'd0 || ^mon_rgb===1'bx) $fatal(1,"full-width active pixel black/unknown");
                if(x_ref2==0 || x_ref2==1279) edge_pixels=edge_pixels+1;
                if(!x_ref2[0]) first_in_pair=mon_rgb;
                else if(mon_rgb!==first_in_pair) $fatal(1,"horizontal 2x pair mismatch");
                if(!y_ref2[0]) previous_row[x_ref2]=mon_rgb;
                else if(mon_rgb!==previous_row[x_ref2]) $fatal(1,"vertical 2x pair mismatch");
                begin
                    logical_x=x_ref2/2; logical_y=y_ref2/2;
                    // 独立640x360网格参考，全有效区像素2x2重复，边框4/8物理像素。
                    column=(logical_x<220) ? 0 : (logical_x<424) ? 1 : 2;
                    row=(logical_y<196) ? 0 : 1;
                    idx=row*3+column;
                    x0=(column==0) ? 24 : (column==1) ? 228 : 432;
                    y0=(row==0) ? 64 : 204;
                    w=184; thickness=(idx==0) ? 4 : 2;
                    expected_border=(idx==0) ? 24'h38BDF8 : 24'h3A6478;
                    if(logical_x>=x0 && logical_x<x0+w && logical_y>=y0 && logical_y<y0+124) begin
                        if(logical_x<x0+thickness || logical_x>=x0+w-thickness ||
                           logical_y<y0+thickness || logical_y>=y0+124-thickness) begin
                            if(mon_rgb!==expected_border)
                                $fatal(1,"border width/phase idx=%0d xy=%0d,%0d rgb=%h",idx,x_ref2,y_ref2,mon_rgb);
                            border_pixels=border_pixels+1;
                        end
                        // 卡片中线没有文字，恰好验证边框后立即恢复填充。
                        if(logical_y==y0+52 && logical_x>=x0+thickness && logical_x<x0+w-thickness &&
                           mon_rgb!==((idx==0) ? 24'h1B4658 : 24'h142F40))
                            $fatal(1,"border overdraw idx=%0d",idx);
                    end
                    if(y_ref2==232 && x_ref2>=48 && x_ref2<416) begin
                        if(mon_rgb==24'h38BDF8) begin
                            if(x_ref2<232) left_count=left_count+1; else right_count=right_count+1;
                        end
                    end
                    if(x_ref2==232 && y_ref2>=128 && y_ref2<376) begin
                        if(mon_rgb==24'h38BDF8) begin
                            if(y_ref2<252) top_count=top_count+1; else bottom_count=bottom_count+1;
                        end
                    end
                end
            end else if(mon_rgb!==0) $fatal(1,"blanking RGB alignment");
        end
    end
    initial begin
        repeat(5) @(negedge video_clk); rst_video=0;
        repeat(1650*750+3) @(negedge video_clk);
        if(pixels!=921600 || border_pixels==0 || edge_pixels!=1440)
            $fatal(1,"monitor coverage pixels=%0d borders=%0d edge_pixels=%0d",pixels,border_pixels,edge_pixels);
        if(left_count!=8 || right_count!=8 || top_count!=8 || bottom_count!=8)
            $fatal(1,"physical selected sides L/R/T/B=%0d/%0d/%0d/%0d",left_count,right_count,top_count,bottom_count);
        $display("TB_MONITOR_PIPELINE PASS pixels=%0d borders=%0d selected_edges=8px regular_edges=4px full_width_2x2 latency=3",pixels,border_pixels); $finish;
    end
    initial begin #13000000; $fatal(1,"monitor pipeline timeout"); end
endmodule
