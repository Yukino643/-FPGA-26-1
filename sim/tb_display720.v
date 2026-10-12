`timescale 1ns/1ps
// 实际720p时序、125MHz存储、真实仲裁、刷新阻塞及完整帧逐像素检查。
module tb_display720 #(
    parameter ACTIVE_ROWS=720,
    parameter TEST_FRAMES=8
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
    mem_mpu #(.MAX_A_RUN(8),.MAX_B_RUN(8),.MAX_C_RUN(4)) mpu(
        .clk(mc),.rst(rst),.A_cmd_valid(av),.A_cmd_addr(aa),.A_cmd_len(an),.A_cmd_ready(ar),
        .A_rsp_valid(ard),.A_rsp_data(ad),.A_rsp_last(al),
        .B_cmd_valid(bv),.B_cmd_addr(ba),.B_cmd_len(bn),.B_cmd_ready(br),.B_rsp_valid(brd),.B_rsp_data(bd),.B_rsp_last(bl),
        .C_cmd_valid(1'b0),.C_cmd_addr(21'd0),.C_cmd_len(8'd1),.C_cmd_ready(),.C_rsp_valid(),.C_rsp_data(),.C_rsp_last(),
        .App_rd_en(ren),.App_rd_addr(raddr),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),.Sdr_init_done(1'b1),.Sdr_busy(refresh_busy),
        .source_write_busy(1'b0),.scaler_write_request(1'b0),.read_busy(),.write_ready(),
        .App_wr_en_u(1'b0),.App_wr_addr_u(21'd0),.App_wr_din_u(32'd0),.App_wr_dm_u(4'd0),
        .App_wr2_en_u(1'b0),.App_wr2_addr_u(21'd0),.App_wr2_din_u(32'd0),.App_wr2_dm_u(4'd0),.wr2_active(1'b0),
        .App_wr_en(),.App_wr_addr(),.App_wr_din(),.App_wr_dm());
    sdram_beh #(.LAT(12)) memory(.clk(mc),.rst(rst),.wr_en(1'b0),.wr_addr(21'd0),.wr_data(32'd0),.wr_dm(4'd0),
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
    reg [23:0] expected[0:1];
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
                    $display("TB_DISPLAY720 PASS frames=%d checked=%d static+blend+handover no_underflow",frame-1,checked);$finish;
                end
            end
            expected[1]=expected[0];ex[1]=ex[0];ey[1]=ey[0];valid={valid[0],de};
            ca=color(pattern(x,y,pagea!=0));cb=color(pattern(x,y,pageb!=0));
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
        for(j=0;j<ACTIVE_ROWS;j=j+1) for(i=0;i<640;i=i+1) begin
            memory.mem[j*640+i]={pattern(2*i+1,j,0),pattern(2*i,j,0)};
            memory.mem[21'h80000+j*640+i]={pattern(2*i+1,j,1),pattern(2*i,j,1)};
        end
        repeat(10) @(negedge vc);rst=0;
        wait(frame==1);wait(y==100 || ACTIVE_ROWS<100);
        @(negedge vc);commit=1;@(negedge vc);commit=0;
    end
    initial begin #200000000; $fatal(1,"FAIL 720p display timeout");end
endmodule
