`timescale 1ns/1ps
// 提取真实top的打包、动态帧长、官方FIFO writer、完成门和缩放连接。
// 存储读口使用有返回空拍的模型；真实读写仲裁另由resize_display720覆盖。
module tb_top_multisize;
    parameter W=640,H=480;
    reg sd_card_clk=0,ext_mem_clk=0,rst_sd=1,rst_mem=1;
    always #5 sd_card_clk=~sd_card_clk;
    always #4 ext_mem_clk=~ext_mem_clk;
    wire video_clk=sd_card_clk;
    wire Sdr_init_done=1'b1,Sdr_init_ref_vld=1'b0,Sdr_busy=1'b0,sd_init_done=1'b1;
    wire memory_read_busy=1'b0,memory_write_ready=1'b1;
    wire [1:0] resize_card_ready_mem=2'b11,write_buf_idx=2'd1,disp_buf_idx=2'd0;
    localparam [20:0] BUF0_ADDR=0,BUF1_ADDR=21'h80000,FRAME_PIXELS=460800;
    reg bmp_source_restart=0,bmp_load_done=0,bmp_wr_en=0,sd_card_write_req=0;
    reg [23:0] bmp_wr_data=0;
    wire [15:0] bmp_load_img_w=W,bmp_load_img_h=H;
    wire sd_card_write_req_ack,frame_write_finish,source_write_busy,App_wr_en;
    wire [20:0] App_wr_addr;
    wire [31:0] App_wr_din,packed_wr_data;
    wire [3:0] App_wr_dm;
    wire packed_wr_en,video_read_req_ack;
    reg frame_write_toggle_mem;
    wire scaler_start_tgl,scaler_commit_toggle,resize_busy_mem,resize_error_mem;
    wire resize_cmd_valid,resize_cmd_ready,resize_rsp_valid,resize_rsp_last,resize_write_request,resize_wr_en;
    wire [20:0] resize_cmd_addr,resize_wr_addr;
    wire [7:0] resize_cmd_len;
    wire [31:0] resize_rsp_data,resize_wr_data;
    `include "reg_multisize_source.vh"

    reg [31:0] source_mem[0:460799];
    integer source_words=0,dest_words=0,cycle=0,left_rsp=0,i,j,fitw,fith,left,top;
    reg [20:0] read_addr;
    reg source_complete=0;
    assign resize_cmd_ready=left_rsp==0 && cycle%7!=0;
    assign resize_rsp_valid=left_rsp!=0 && cycle%3!=0;
    assign resize_rsp_last=resize_rsp_valid && left_rsp==1;
    assign resize_rsp_data=source_mem[read_addr-21'h100000];
    function [15:0] pattern;
        input integer x,y;
        begin pattern={x[4:0]^5'h15,y[5:0]^6'h2a,x[4:0]^y[4:0]^5'h0f}; end
    endfunction
    function [23:0] rgb888;
        input [15:0] p;
        begin rgb888={p[15:11],3'b0,p[10:5],2'b0,p[4:0],3'b0};end
    endfunction
    function [15:0] expected_pixel;
        input integer x,y;
        begin
            if(x<left || x>=left+fitw || y<top || y>=top+fith) expected_pixel=0;
            else expected_pixel=pattern((x-left)*W/fitw,(y-top)*H/fith);
        end
    endfunction
    reg [31:0] expected_word;
    integer sx,sy,rowwords;
    always @(posedge ext_mem_clk) if(!rst_mem) begin
        cycle=cycle+1;
        if(App_wr_en) begin
            sx=2*(source_words%rowwords); sy=H-1-source_words/rowwords;
            expected_word={sx+1<W ? pattern(sx+1,sy):16'd0,pattern(sx,sy)};
            if(App_wr_addr!==21'h100000+source_words || App_wr_dm!==0 || App_wr_din!==expected_word || resize_busy_mem)
                $fatal(1,"source top write failed %0dx%0d word=%0d addr=%h data=%h exp=%h",W,H,source_words,App_wr_addr,App_wr_din,expected_word);
            source_mem[source_words]=App_wr_din; source_words=source_words+1;
        end
        if(frame_write_finish && source_words!=rowwords*H) $fatal(1,"dynamic source length wrong");
        if(resize_busy_mem && (!source_complete || source_words!=rowwords*H)) $fatal(1,"incomplete source started scaler");
        if(resize_cmd_valid && resize_cmd_ready) begin
            if(resize_cmd_addr<21'h100000 || resize_cmd_addr+resize_cmd_len>21'h100000+rowwords*H)
                $fatal(1,"source top read out of bounds");
            read_addr<=resize_cmd_addr; left_rsp<=resize_cmd_len;
        end else if(resize_rsp_valid) begin read_addr<=read_addr+1'b1;left_rsp<=left_rsp-1;end
        if(resize_wr_en) begin
            sx=2*(dest_words%640);sy=dest_words/640;
            expected_word={expected_pixel(sx+1,sy),expected_pixel(sx,sy)};
            if(resize_wr_addr!==BUF1_ADDR+dest_words || resize_wr_data!==expected_word || scaler_commit_toggle)
                $fatal(1,"source top destination/publication failed word=%0d",dest_words);
            dest_words=dest_words+1;
        end
        if(scaler_commit_toggle && dest_words!=460800) $fatal(1,"partial page published");
    end
    initial begin
        rowwords=(W+1)/2;
        if(W*720>=H*1280) begin fitw=1280;fith=H*1280/W;end
        else begin fitw=W*720/H;fith=720;end
        if(fitw<1)fitw=1;if(fith<1)fith=1;
        left=(1280-fitw)/2;top=(720-fith)/2;
        repeat(5) @(negedge sd_card_clk);rst_sd=0;rst_mem=0;
        repeat(10) @(negedge sd_card_clk);
        bmp_source_restart=1;@(negedge sd_card_clk);bmp_source_restart=0;
        repeat(6) @(negedge sd_card_clk);sd_card_write_req=1;
        wait(sd_card_write_req_ack);@(negedge sd_card_clk);sd_card_write_req=0;
        wait(!sd_card_write_req_ack);repeat(8) @(negedge sd_card_clk);
        for(j=H-1;j>=0;j=j-1) for(i=0;i<W;i=i+1) begin
            bmp_wr_en=1;bmp_wr_data=rgb888(pattern(i,j));@(negedge sd_card_clk);
            bmp_wr_en=0;repeat(3) @(negedge sd_card_clk);
        end
        source_complete=1;bmp_load_done=1;@(negedge sd_card_clk);bmp_load_done=0;
        wait(scaler_commit_toggle);repeat(6) @(negedge ext_mem_clk);
        if(resize_busy_mem || resize_error_mem || dest_words!=460800 || source_words!=rowwords*H)
            $fatal(1,"source top completion");
        $display("TB_TOP_MULTISIZE PASS %0dx%0d source=%0d destination=%0d official_FIFO actual_top_connections",W,H,source_words,dest_words);$finish;
    end
    initial begin #60000000;$fatal(1,"top multisize timeout");end
endmodule
