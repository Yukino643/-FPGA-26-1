`timescale 1ns/1ps
// 实际720p时序、125MHz存储、真实仲裁、刷新阻塞及完整帧逐像素检查。
module tb_display720 #(
    parameter ACTIVE_ROWS=720,
    parameter TEST_FRAMES=8,
    parameter PREFETCH_WRITES=0,
    parameter RESIZE_WRITES=0
);
    reg vc=0,mc=0,rst=1;
    always #6.734 vc=~vc;
    always #4 mc=~mc;
    wire vs,de,hs;
    wire [10:0] x;
    wire [9:0] y;
    video_timing_gen #(.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
        .VTOTAL(ACTIVE_ROWS+30),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(ACTIVE_ROWS),.X_BITS(11),.Y_BITS(10)) timing(
        .I_clk(vc),.I_rst(rst),.O_hs(hs),.O_vs(vs),.O_de(de),.O_x(x),.O_y(y));
    reg vd=0,vt=0;
    wire edge_vs=vs && !vd;
    always @(posedge vc) begin
        if(rst) begin vd<=0;vt<=0;end
        else begin vd<=vs;if(edge_vs) vt<=~vt;end
    end
    reg commit=0;
    reg [1:0] commit_buf=1;
    wire active,hold_load;
    wire [7:0] alpha;
    wire [20:0] pagea,pageb;
    transition_ctrl #(.ALPHA_STEP(64),.X_BITS(11),.Y_BITS(10)) tr(
        .clk(vc),.rst(rst),.vs_rise(edge_vs),.x(x),.y(y),.commit_toggle(commit),.commit_buf(commit_buf),.tr_mode(2'd1),
        .tr_active(active),.alpha(alpha),.boundary(),.slide_axis(),.page_a_base(pagea),.page_b_base(pageb),
        .page_upd_a(),.page_upd_b(),.hold_load(hold_load),.fade_black());
    wire av,bv,ar,br,al,bl,ard,brd;
    wire [20:0] aa,ba;
    wire [7:0] an,bn;
    wire [31:0] ad,bd;
    wire [23:0] rgb;
    wire ode,ovs;
    wire [10:0] ox;
    wire [9:0] oy;
    wire [31:0] underflow;
    display_stream_720 #(.FRAME_WORDS(640*ACTIVE_ROWS)) stream(
        .mem_clk(mc),.mem_rst(rst),.video_clk(vc),.video_rst(rst),.vs_toggle(vt),.de_in(de),.vs_in(vs),.x(x),.y(y),
        .tr_active(active),.alpha(alpha),.page_a_base(pagea),.page_b_base(pageb),
        .a_cmd_valid(av),.a_cmd_addr(aa),.a_cmd_len(an),.a_cmd_ready(ar),.a_rsp_valid(ard),.a_rsp_data(ad),.a_rsp_last(al),
        .b_cmd_valid(bv),.b_cmd_addr(ba),.b_cmd_len(bn),.b_cmd_ready(br),.b_rsp_valid(brd),.b_rsp_data(bd),.b_rsp_last(bl),
        .rgb_out(rgb),.de_out(ode),.vs_out(ovs),.x_out(ox),.y_out(oy),.underflow_cnt(underflow));
    wire ren,rv;
    wire [20:0] raddr;
    wire [31:0] rd;
    integer refresh_div=0;
    // 125MHz下7.8us周期；强制32拍阻塞比常见tRFC更保守。
    always @(posedge mc) if(rst) refresh_div<=0;else refresh_div<=refresh_div==974?0:refresh_div+1;
    wire refresh_busy=refresh_div<32;
    wire read_busy,writer_busy,writer_wr,writer_ack,writer_finish,fifo_clear;
    wire [20:0] writer_addr,mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire [3:0] mem_wr_dm;
    wire mem_wr;
    wire rcv,rcr,rrv,rrl,rwrite,rwr,rbusy,rdone,rerror,write_ready;
    wire [20:0] rca,rwa;
    wire [7:0] rcl;
    wire [31:0] rrd,rwd;
    reg resize_start=0;
    resize_frame_720 resize(
        .clk(mc),.rst(rst),.cancel(1'b0),.start_toggle(resize_start),
        .cfg_w(11'd640),.cfg_h(11'd480),.cfg_src_base(21'h100000),.cfg_dst_base(21'h80000),
        .cmd_valid(rcv),.cmd_addr(rca),.cmd_len(rcl),.cmd_ready(rcr),.rsp_valid(rrv),.rsp_last(rrl),.rsp_data(rrd),
        .write_request(rwrite),.write_ready(write_ready),.wr_en(rwr),.wr_addr(rwa),.wr_data(rwd),
        .busy(rbusy),.done_toggle(rdone),.error(rerror));
    reg writer_req=0;
    reg [9:0] fifo_used=0;
    integer producer_div=0,written_words=0,mem_written_words=0;
    // 每64个存储拍产生一字，约1.95Mword/s，高于当前25MHz SPI可提供速率。
    wire producer_tick=PREFETCH_WRITES && !fifo_clear && producer_div==63 && fifo_used<512;
    always @(posedge mc) begin
        if(rst || fifo_clear) begin fifo_used<=0;producer_div<=0;end
        else begin
            producer_div<=producer_div==63 ? 0:producer_div+1;
            case({producer_tick,writer_wr})
                2'b10: fifo_used<=fifo_used+1;
                2'b01: fifo_used<=fifo_used-1;
                default: fifo_used<=fifo_used;
            endcase
        end
        if(!rst && writer_wr) begin
            if(!PREFETCH_WRITES || fifo_used==0 || read_busy || ren || active ||
               writer_addr!==21'h80000+written_words)$fatal(1,"FAIL background writer reservation/page");
            written_words=written_words+1;
        end
        if(!rst && mem_wr) begin
            if((!PREFETCH_WRITES && !RESIZE_WRITES) || mem_wr_addr!==21'h80000+mem_written_words || mem_wr_dm!==4'd0)
                $fatal(1,"FAIL background memory write address/mask");
            if(RESIZE_WRITES && (active || mem_wr_data!=={resized_pattern(2*(mem_written_words%640)+1,mem_written_words/640),
                                                         resized_pattern(2*(mem_written_words%640),mem_written_words/640)}))
                $fatal(1,"FAIL resized write content/ownership word=%0d",mem_written_words);
            mem_written_words=mem_written_words+1;
        end
    end
    frame_fifo_write #(.WRITE_V_FLIP(0),.FRAME_WIDTH(640),.FRAME_HEIGHT(ACTIVE_ROWS)) writer(
        .rst(rst),.mem_clk(mc),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(refresh_busy),
        .App_rd_busy(read_busy),.O_wr_busy(writer_busy),.App_wr_en(writer_wr),.App_wr_addr(writer_addr),
        .write_req(writer_req),.write_req_ack(writer_ack),.write_finish(writer_finish),
        .write_addr_0(21'h80000),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
        .write_addr_index(2'd0),.write_len(21'd640*ACTIVE_ROWS),.fifo_aclr(fifo_clear),.rdusedw(fifo_used));
    wire [31:0] writer_data={pattern(2*((writer_addr-21'h80000)%640)+1,(writer_addr-21'h80000)/640,1),
                            pattern(2*((writer_addr-21'h80000)%640),(writer_addr-21'h80000)/640,1)};
    mem_mpu #(.MAX_A_RUN(8),.MAX_B_RUN(8),.MAX_C_RUN(4)) mpu(
        .clk(mc),.rst(rst),.A_cmd_valid(av),.A_cmd_addr(aa),.A_cmd_len(an),.A_cmd_ready(ar),
        .A_rsp_valid(ard),.A_rsp_data(ad),.A_rsp_last(al),
        .B_cmd_valid(bv),.B_cmd_addr(ba),.B_cmd_len(bn),.B_cmd_ready(br),.B_rsp_valid(brd),.B_rsp_data(bd),.B_rsp_last(bl),
        .C_cmd_valid(rcv),.C_cmd_addr(rca),.C_cmd_len(rcl),.C_cmd_ready(rcr),.C_rsp_valid(rrv),.C_rsp_data(rrd),.C_rsp_last(rrl),
        .App_rd_en(ren),.App_rd_addr(raddr),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),.Sdr_init_done(1'b1),.Sdr_busy(refresh_busy),
        .source_write_busy(writer_busy),.scaler_write_request(rwrite),.read_busy(read_busy),.write_ready(write_ready),
        .App_wr_en_u(writer_wr),.App_wr_addr_u(writer_addr),.App_wr_din_u(writer_data),.App_wr_dm_u(4'd0),
        .App_wr2_en_u(rwr),.App_wr2_addr_u(rwa),.App_wr2_din_u(rwd),.App_wr2_dm_u(4'd0),.wr2_active(rbusy),
        .App_wr_en(mem_wr),.App_wr_addr(mem_wr_addr),.App_wr_din(mem_wr_data),.App_wr_dm(mem_wr_dm));
    sdram_beh #(.LAT(12)) memory(.clk(mc),.rst(rst),.wr_en(mem_wr),.wr_addr(mem_wr_addr),.wr_data(mem_wr_data),.wr_dm(mem_wr_dm),
        .rd_en(ren),.rd_addr(raddr),.rd_vld(rv),.rd_dout(rd));
    function [15:0] pattern;
        input integer px,py,page;
        reg [4:0] r,b;
        reg [5:0] g;
        begin
            r=(px/8 + page*13)%32;g=(py+px/32+page*29)%64;b=(px+py*3+page*7)%32;
            pattern={r,g,b};
        end
    endfunction
    function [23:0] color;
        input [15:0] p;
        begin color={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end
    endfunction
    function [15:0] resized_pattern;
        input integer px,py;
        begin
            resized_pattern=(px<160 || px>=1120) ? 16'd0 : pattern(((px-160)*2)/3,(py*2)/3,1);
        end
    endfunction
    reg [23:0] expected[0:1];
    // 独立数学参考只预计算一次，逐帧比较仍读取独立数组，不能从DUT存储回读期望值。
    reg [23:0] reference0[0:1280*ACTIVE_ROWS-1],reference1[0:1280*ACTIVE_ROWS-1];
    reg [1:0] valid=0;
    reg [10:0] ex[0:1];
    reg [9:0] ey[0:1];
    reg [23:0] ca,cb;
    integer cr,cg,cc,frame=0,checked=0,i,j,frame_pixels=0;
    reg [31:0] uf_start=0;
    always @(posedge vc) begin
        if(!rst) begin
            if(edge_vs) begin
                if(frame>0 && frame_pixels!=1280*ACTIVE_ROWS) $fatal(1,"FAIL incomplete 720p frame %d %d",frame,frame_pixels);
                frame_pixels=0;
                frame=frame+1;
                if(frame==1) uf_start=underflow;
                if(frame==TEST_FRAMES) begin
                    if(underflow!=uf_start) $fatal(1,"FAIL 720p underflow %d",underflow-uf_start);
                    if(PREFETCH_WRITES && (written_words!=640*ACTIVE_ROWS || mem_written_words!=640*ACTIVE_ROWS))
                        $fatal(1,"FAIL background write coverage");
                    if(RESIZE_WRITES && (rerror || !rdone || mem_written_words!=460800))
                        $fatal(1,"FAIL resize concurrent coverage");
                    $display("TB_DISPLAY720 PASS frames=%d checked=%d static+blend+handover no_underflow",frame-1,checked);$finish;
                end
            end
            expected[1]=expected[0];ex[1]=ex[0];ey[1]=ey[0];valid={valid[0],de};
            ca=de ? (pagea!=0 ? reference1[y*1280+x]:reference0[y*1280+x]):24'd0;
            cb=de ? (pageb!=0 ? reference1[y*1280+x]:reference0[y*1280+x]):24'd0;
            cr=(ca[23:16]*(256-alpha)+cb[23:16]*alpha+128)/256;
            cg=(ca[15:8]*(256-alpha)+cb[15:8]*alpha+128)/256;
            cc=(ca[7:0]*(256-alpha)+cb[7:0]*alpha+128)/256;
            expected[0]=!active || alpha==0 ? ca:alpha==255 ? cb:{cr[7:0],cg[7:0],cc[7:0]};ex[0]=x;ey[0]=y;
            #1;
            if(frame>0 && ode) begin
                if(rgb!==expected[1] || ox!==ex[1] || oy!==ey[1])
                    $fatal(1,"FAIL 720p frame%d xy%d,%d rgb%h exp%h alpha%d uf%d",frame,ox,oy,rgb,expected[1],alpha,underflow);
                checked=checked+1;frame_pixels=frame_pixels+1;
            end
        end
    end
    initial begin
        for(j=0;j<ACTIVE_ROWS;j=j+1) for(i=0;i<1280;i=i+1) begin
            reference0[j*1280+i]=color(pattern(i,j,0));
            reference1[j*1280+i]=color(RESIZE_WRITES ? resized_pattern(i,j):pattern(i,j,1));
        end
        for(j=0;j<ACTIVE_ROWS;j=j+1) for(i=0;i<640;i=i+1) begin
            memory.mem[j*640+i]={pattern(2*i+1,j,0),pattern(2*i,j,0)};
            // 预取必须通过实际写入生成正确内容，禁止预填期望图案掩盖丢写。
            memory.mem[21'h80000+j*640+i]=(PREFETCH_WRITES || RESIZE_WRITES) ? 32'hdeadbeef :
                                                        {pattern(2*i+1,j,1),pattern(2*i,j,1)};
        end
        if(RESIZE_WRITES)
            for(j=0;j<480;j=j+1) for(i=0;i<320;i=i+1)
                memory.mem[21'h100000+(479-j)*320+i]={pattern(2*i+1,j,1),pattern(2*i,j,1)};
        repeat(10) @(negedge vc);rst=0;
        wait(frame==1);wait(y==100 || ACTIVE_ROWS<100);
        if(PREFETCH_WRITES) begin
            @(negedge mc);writer_req=1;wait(writer_ack);@(negedge mc);writer_req=0;
            wait(writer_finish);repeat(10) @(negedge mc);
        end
        if(RESIZE_WRITES) begin
            @(negedge mc);resize_start=1;
            wait(rdone);repeat(10) @(negedge mc);
        end
        @(negedge vc);commit=1;@(negedge vc);commit=0;
    end
    initial begin #200000000; $fatal(1,"FAIL 720p display timeout");end
endmodule
