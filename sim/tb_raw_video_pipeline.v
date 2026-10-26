`timescale 1ns/1ps
// 真实top实例/CDC提取：R16→源FIFO writer→scaler→SDRAM仲裁→完整720p栅格。
module tb_raw_video_pipeline;
    reg sd_card_clk=0,ext_mem_clk=0,video_clk=0,rst_sd=1;
    always #5 sd_card_clk=~sd_card_clk;
    always #4 ext_mem_clk=~ext_mem_clk;
    always #6.734 video_clk=~video_clk;
    wire rst_mem=rst_sd,rst_video=rst_sd;
    wire sd_init_done=!rst_sd,Sdr_init_done=!rst_sd,Sdr_init_ref_vld=0;
    integer refresh_div=0;
    always @(posedge ext_mem_clk) if(rst_mem) refresh_div<=0;else refresh_div<=refresh_div==974 ? 0:refresh_div+1;
    wire Sdr_busy=refresh_div<32;
    localparam [20:0] BUF0_ADDR=0,BUF1_ADDR=21'h80000,FRAME_PIXELS=460800;
    wire [1:0] write_buf_idx,disp_buf_idx;
    wire [1:0] tr_mode_reg=0;
    wire tr_hold_load,bmp_display_commit_toggle,bmp_display_commit_pulse;
    wire bmp_source_restart,bmp_load_done,bmp_wr_en,sd_card_write_req,display_valid;
    wire [23:0] bmp_wr_data;
    wire [15:0] bmp_load_img_w=320,bmp_load_img_h=180;
    wire sd_card_write_req_ack,frame_write_finish,source_write_busy,App_wr_en;
    wire [20:0] App_wr_addr;
    wire [31:0] App_wr_din,packed_wr_data;
    wire [3:0] App_wr_dm;
    wire packed_wr_en,video_read_req_ack;
    reg frame_write_toggle_mem;
    wire [7:0] raw_error;
    wire [15:0] raw_frame;
    wire [3:0] state_code;
    wire [31:0] tf_bmp_debug;
    wire bmp_sd_timeout, bmp_sd_sec_read,bmp_sd_sec_read_end,bmp_sd_sec_read_data_valid;
    wire [31:0] bmp_sd_sec_read_addr;
    wire [7:0] bmp_sd_sec_read_data;
    wire [31:0] transactions;
    wire resize_cmd_valid,resize_cmd_ready,resize_rsp_valid,resize_rsp_last,resize_write_request,resize_wr_en;
    wire [20:0] resize_cmd_addr,resize_wr_addr;
    wire [7:0] resize_cmd_len;
    wire [31:0] resize_rsp_data,resize_wr_data;
    wire memory_read_busy,memory_write_ready;
    wire vs,de,hs;
    wire [10:0] x;
    wire [9:0] y;
    reg vd=0,vt=0;
    wire vs_rise_v=vs && !vd;
    always @(posedge video_clk) if(rst_video) begin vd<=0;vt<=0;end
        else begin vd<=vs;if(vs_rise_v) vt<=~vt;end
    wire [20:0] page_a_base;
    wire displayed,applied;
    `include "reg_raw_video_pipeline.vh"
    video_timing_gen #(.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
        .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.X_BITS(11),.Y_BITS(10)) timing(
        .I_clk(video_clk),.I_rst(rst_video),.O_hs(hs),.O_vs(vs),.O_de(de),.O_x(x),.O_y(y));
    raw_video_card_model card(.clk(sd_card_clk),.rst(rst_sd),.req(bmp_sd_sec_read),.addr(bmp_sd_sec_read_addr),
        .data(bmp_sd_sec_read_data),.valid(bmp_sd_sec_read_data_valid),.done(bmp_sd_sec_read_end),
        .abort(bmp_sd_timeout),.transactions(transactions));
    wire av,bv,ar,br,al,bl,ard,brd;
    wire [20:0] aa,ba;
    wire [7:0] an,bn;
    wire [31:0] ad,bd;
    wire [23:0] rgb;
    wire ode,ovs;
    wire [10:0] ox;
    wire [9:0] oy;
    wire [31:0] underflow;
    display_stream_720 stream(
        .mem_clk(ext_mem_clk),.mem_rst(rst_mem),.video_clk(video_clk),.video_rst(rst_video),
        .vs_toggle(vt),.de_in(de),.vs_in(vs),.x(x),.y(y),.tr_active(1'b0),.alpha(8'hff),
        .page_a_base(page_a_base),.page_b_base(page_a_base),
        .a_cmd_valid(av),.a_cmd_addr(aa),.a_cmd_len(an),.a_cmd_ready(ar),.a_rsp_valid(ard),.a_rsp_data(ad),.a_rsp_last(al),
        .b_cmd_valid(bv),.b_cmd_addr(ba),.b_cmd_len(bn),.b_cmd_ready(br),.b_rsp_valid(brd),.b_rsp_data(bd),.b_rsp_last(bl),
        .rgb_out(rgb),.de_out(ode),.vs_out(ovs),.x_out(ox),.y_out(oy),.underflow_cnt(underflow));
    wire ren,rv,mem_wr;
    wire [20:0] raddr,mem_wr_addr;
    wire [31:0] rd,mem_wr_data;
    wire [3:0] mem_wr_dm;
    mem_mpu #(.MAX_A_RUN(8),.MAX_B_RUN(8),.MAX_C_RUN(4)) mpu(
        .clk(ext_mem_clk),.rst(rst_mem),.A_cmd_valid(av),.A_cmd_addr(aa),.A_cmd_len(an),.A_cmd_ready(ar),
        .A_rsp_valid(ard),.A_rsp_data(ad),.A_rsp_last(al),
        .B_cmd_valid(bv),.B_cmd_addr(ba),.B_cmd_len(bn),.B_cmd_ready(br),.B_rsp_valid(brd),.B_rsp_data(bd),.B_rsp_last(bl),
        .C_cmd_valid(resize_cmd_valid),.C_cmd_addr(resize_cmd_addr),.C_cmd_len(resize_cmd_len),.C_cmd_ready(resize_cmd_ready),
        .C_rsp_valid(resize_rsp_valid),.C_rsp_data(resize_rsp_data),.C_rsp_last(resize_rsp_last),
        .App_rd_en(ren),.App_rd_addr(raddr),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),.Sdr_init_done(Sdr_init_done),.Sdr_busy(Sdr_busy),
        .source_write_busy(source_write_busy),.scaler_write_request(resize_write_request),
        .read_busy(memory_read_busy),.write_ready(memory_write_ready),
        .App_wr_en_u(App_wr_en),.App_wr_addr_u(App_wr_addr),.App_wr_din_u(App_wr_din),.App_wr_dm_u(App_wr_dm),
        .App_wr2_en_u(resize_wr_en),.App_wr2_addr_u(resize_wr_addr),.App_wr2_din_u(resize_wr_data),.App_wr2_dm_u(4'd0),.wr2_active(resize_busy_mem),
        .App_wr_en(mem_wr),.App_wr_addr(mem_wr_addr),.App_wr_din(mem_wr_data),.App_wr_dm(mem_wr_dm));
    sdram_beh #(.LAT(12)) memory(.clk(ext_mem_clk),.rst(rst_mem),.wr_en(mem_wr),.wr_addr(mem_wr_addr),.wr_data(mem_wr_data),.wr_dm(mem_wr_dm),
        .rd_en(ren),.rd_addr(raddr),.rd_vld(rv),.rd_dout(rd));

    function [15:0] source_pixel;
        input integer f,px,py;
        integer offset;
        begin offset=f*115200+((179-py)*320+px)*2;source_pixel={card.pixels[offset+1],card.pixels[offset]};end
    endfunction
    function [23:0] color;
        input [15:0] p;
        begin color={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end
    endfunction
    reg [23:0] reference0[0:921599],reference1[0:921599];
    integer source_words=0,dest_words=0,commits=0,applies=0,frame=0,last_apply=0,frame_pixels=0,checked=0;
    integer i,j,sx,sy;
    reg source_complete=0;
    reg [31:0] expected_word;
    reg [1:0] valid_pipe=0;
    reg [23:0] expected[0:1];
    reg current_page=0;
    reg [20:0] previous_page=0;
    reg [31:0] underflow_at_start=0;
    always @(posedge sd_card_clk) if(!rst_sd) begin
        if(bmp_source_restart) begin source_words=0;dest_words=0;source_complete=0;end
        if(bmp_load_done) source_complete=1;
        if(raw_error || resize_error_mem) $fatal(1,"FAIL integrated player error=%h state=%d",raw_error,state_code);
        if(bmp_display_commit_pulse) begin
            if(source_words!=28800 || dest_words!=460800) $fatal(1,"FAIL integrated partial commit %d/%d",source_words,dest_words);
            commits=commits+1;
            $display("integrated ready frame=%d page=%d time_ns=%0t",raw_frame,write_buf_idx,$time);
        end
    end
    always @(posedge ext_mem_clk) if(!rst_mem) begin
        if(App_wr_en) begin
            sx=2*(source_words%160);sy=179-source_words/160;
            expected_word={source_pixel(raw_frame,sx+1,sy),source_pixel(raw_frame,sx,sy)};
            if(App_wr_addr!==21'h100000+source_words || App_wr_din!==expected_word || resize_busy_mem)
                $fatal(1,"FAIL integrated source word=%d",source_words);
            source_words=source_words+1;
        end
        if(resize_wr_en) begin
            sx=2*(dest_words%640);sy=dest_words/640;
            expected_word={source_pixel(raw_frame,(sx+1)/4,sy/4),source_pixel(raw_frame,sx/4,sy/4)};
            if(!source_complete || source_words!=28800 ||
               (displayed && resize_wr_addr[19]==page_a_base[19]) ||
               resize_wr_addr!==(write_buf_idx[0]?BUF1_ADDR:BUF0_ADDR)+dest_words || resize_wr_data!==expected_word)
                $fatal(1,"FAIL integrated destination word=%d addr=%h",dest_words,resize_wr_addr);
            dest_words=dest_words+1;
        end
    end
    always @(posedge video_clk) if(!rst_video) begin
        // VS采纳后的下一拍applied才可见；同时核对页基址只在VS改变。
        if(page_a_base!=previous_page && !applied) $fatal(1,"FAIL page changed outside VS");
        previous_page=page_a_base;
        if(applied) begin
            if(applies>0 && frame-last_apply!=6) $fatal(1,"FAIL measured frame cadence=%d",frame-last_apply);
            applies=applies+1;last_apply=frame;
            if(applies==1) underflow_at_start=underflow;
            if(page_a_base[19]!=(applies-1)%2) $fatal(1,"FAIL displayed page ordering");
            $display("integrated applied=%d VS=%d time_ns=%0t",applies,frame,$time);
        end
        if(vs_rise_v) begin
            if(frame>0 && frame_pixels!=921600) $fatal(1,"FAIL incomplete full raster");
            frame_pixels=0;frame=frame+1;
            if(applies>=3) begin
                if(underflow!=underflow_at_start || checked<3*921600)
                    $fatal(1,"FAIL integrated underflow/coverage %d %d",underflow-underflow_at_start,checked);
                $display("PASS raw_video_pipeline 3 pages including loop, full 720p x4 pixels=%d 6VS cadence no underflow, SPI36, refresh and actual top CDC",checked);$finish;
            end
        end
        expected[1]=expected[0];valid_pipe={valid_pipe[0],de && displayed};
        expected[0]=page_a_base[19] ? reference1[y*1280+x]:reference0[y*1280+x];
        #1;
        if(ode) begin
            frame_pixels=frame_pixels+1;
            if(valid_pipe[1]) begin
                if(rgb!==expected[1]) $fatal(1,"FAIL video pixel xy=%d,%d got%h expected%h page%h uf%d",ox,oy,rgb,expected[1],page_a_base,underflow);
                checked=checked+1;
            end
        end
    end
    initial begin
        // 初始数据用毒值，不能以预填期望图掩盖源/目标丢写。
        #1;
        for(j=0;j<720;j=j+1) for(i=0;i<1280;i=i+1) begin
            reference0[j*1280+i]=color(source_pixel(0,i/4,j/4));
            reference1[j*1280+i]=color(source_pixel(1,i/4,j/4));
        end
        for(i=0;i<460800;i=i+1) begin memory.mem[i]=32'hbad0bad0;memory.mem[BUF1_ADDR+i]=32'hbad1bad1;end
        repeat(10) @(negedge sd_card_clk);rst_sd=0;
    end
    initial begin #380000000;$fatal(1,"FAIL integrated timeout rawstate=%d err=%h sources=%d dest=%d",state_code,raw_error,source_words,dest_words);end
endmodule
