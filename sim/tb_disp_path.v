// tb_disp_path.v — W5 显示读出全路径仿真
// 链路: sdram_beh → mem_mpu → 2×disp_read_engine → 2×afifo_simple → disp_mixer
//       ← transition_ctrl ← 视频时序(video_timing_gen+pixel_pos_gen)
// 检查: 页0→页1→页0→页1直切，每次换页第一帧全像素及地址顺序必须正确。
// 端点饱和及黑帧淡入淡出由 tb_transition_ctrl 单独覆盖。
`timescale 1ns/1ps
module tb_disp_path;

    localparam FRAME_WORDS = 307200;
    localparam PAGE0 = 21'h0_0000;
    localparam PAGE1 = 21'h8_0000;
    // 地址编码像素能检出重复、丢字和跨行错位，纯灰页无法覆盖这些缺陷。
    function [23:0] pattern_a;
        input integer index;
        begin pattern_a = {index[7:0], index[15:8], (index[23:16] ^ 8'h5a)}; end
    endfunction
    function [23:0] pattern_b;
        input integer index;
        begin pattern_b = {~index[7:0], (index[15:8] ^ 8'ha5), index[23:16]}; end
    endfunction
    function [23:0] expected_mix;
        input integer index;
        input [7:0] weight;
        reg [23:0] a, b;
        reg [7:0] r, g, bl;
        begin
            a = pattern_a(index); b = pattern_b(index);
            r = (a[23:16]*(255-weight)+b[23:16]*weight+127)>>8;
            g = (a[15:8]*(255-weight)+b[15:8]*weight+127)>>8;
            bl = (a[7:0]*(255-weight)+b[7:0]*weight+127)>>8;
            expected_mix = (weight==0) ? a : (weight==255) ? b : {r,g,bl};
        end
    endfunction

    reg clk25 = 0;      // video 25.175M
    reg clk125 = 0;     // mem 125M
    reg rst = 1;
    always #19.86 clk25 = ~clk25;
    always #4    clk125 = ~clk125;

    // ---- 视频时序 ----
    wire hs, vs, de_t;
    wire [9:0] tx; wire [8:0] ty;
    video_timing_gen #(.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
                       .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480))
    u_timing(.I_clk(clk25), .I_rst(rst), .O_hs(hs), .O_vs(vs), .O_de(de_t), .O_x(tx), .O_y(ty));

    wire de_al; wire [9:0] px; wire [8:0] py; wire [31:0] fc;
    pixel_pos_gen u_pos(.I_clk(clk25), .I_rst(rst), .I_vs(vs), .I_de(de_t),
                        .O_de(de_al), .O_x(px), .O_y(py), .O_frame_cnt(fc));

    reg vs_d = 0;
    always @(posedge clk25) vs_d <= vs;
    wire vs_rise = vs & ~vs_d;

    // ---- 转场控制 ----
    reg         commit_toggle = 0;
    reg  [1:0]  commit_buf = 2'd1;
    wire        tr_active, fade_black, page_upd_a, page_upd_b, hold_load;
    wire [7:0]  alpha;
    wire [9:0]  boundary;
    wire [1:0]  slide_axis;
    wire [20:0] page_a_base, page_b_base;

    localparam ALPHA_STEP = 8'd32;   // 快单元测试另行覆盖淡入淡出

    transition_ctrl #(
        .PAGE0_BASE(PAGE0), .PAGE1_BASE(PAGE1), .ALPHA_STEP(ALPHA_STEP)
    ) u_tr(
        .clk(clk25), .rst(rst), .vs_rise(vs_rise), .x(px), .y(py),
        .commit_toggle(commit_toggle), .commit_buf(commit_buf),
        .tr_mode(2'd0),
        .tr_active(tr_active), .fade_black(fade_black), .alpha(alpha), .boundary(boundary),
        .slide_axis(slide_axis),
        .page_a_base(page_a_base), .page_b_base(page_b_base),
        .page_upd_a(page_upd_a), .page_upd_b(page_upd_b),
        .hold_load(hold_load)
    );

    // ---- mem 域同步: video 域 toggle → 2FF → 边沿译码为帧起始脉冲 ----
    reg [2:0] go_sync = 0;
    wire frame_go = go_sync[1] ^ go_sync[2];
    always @(posedge clk125) go_sync <= {go_sync[1:0], go_toggle};
    reg go_toggle = 0;
    always @(posedge clk25) begin
        if (rst) go_toggle <= 0;
        else if (vs_rise) go_toggle <= ~go_toggle;
    end

    // 页基址在 mem 域的采样（准静态，2FF）
    reg [20:0] base_a_sync1, base_a_sync2, base_b_sync1, base_b_sync2;
    always @(posedge clk125) begin
        base_a_sync1 <= page_a_base; base_a_sync2 <= base_a_sync1;
        base_b_sync1 <= page_b_base; base_b_sync2 <= base_b_sync1;
    end

    // ---- mem_mpu + 行为 SDRAM ----
    wire        A_cv, A_cr, A_rv, A_rl, B_cv, B_cr, B_rv, B_rl;
    wire [20:0] A_ca, B_ca;
    wire [31:0] A_rd, B_rd;
    wire [7:0]  A_cl, B_cl;
    wire        App_rd_en; wire [20:0] App_rd_addr;
    wire wr_en_w = 1'b0;
    wire [20:0] wr_addr_w = 21'd0;
    wire [31:0] wr_data_w = 32'd0;

    mem_mpu #(.MAX_A_RUN(2)) u_mpu(
        .clk(clk125), .rst(rst),
        .A_cmd_valid(A_cv), .A_cmd_addr(A_ca), .A_cmd_len(A_cl), .A_cmd_ready(A_cr),
        .A_rsp_valid(A_rv), .A_rsp_data(A_rd), .A_rsp_last(A_rl),
        .B_cmd_valid(B_cv), .B_cmd_addr(B_ca), .B_cmd_len(B_cl), .B_cmd_ready(B_cr),
        .B_rsp_valid(B_rv), .B_rsp_data(B_rd), .B_rsp_last(B_rl),
        .C_cmd_valid(1'b0), .C_cmd_addr(21'd0), .C_cmd_len(8'd1),
        .C_cmd_ready(), .C_rsp_valid(), .C_rsp_data(), .C_rsp_last(),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(sd_vld), .Sdr_rd_dout(sd_dout),
        .Sdr_init_done(1'b1), .Sdr_busy(1'b0),
        .source_write_busy(1'b0), .scaler_write_request(1'b0), .read_busy(), .write_ready(),
        .App_wr_en_u(wr_en_w), .App_wr_addr_u(wr_addr_w), .App_wr_din_u(wr_data_w), .App_wr_dm_u(4'h0),
        .App_wr2_en_u(1'b0), .App_wr2_addr_u(21'd0), .App_wr2_din_u(32'd0), .App_wr2_dm_u(4'd0),
        .wr2_active(1'b0),
        .App_wr_en(), .App_wr_addr(), .App_wr_din(), .App_wr_dm()
    );

    wire sd_vld; wire [31:0] sd_dout;
    sdram_beh #(.LAT(8)) u_sd(
        .clk(clk125), .rst(rst),
        .wr_en(wr_en_w), .wr_addr(wr_addr_w), .wr_data(wr_data_w), .wr_dm(4'h0),
        .rd_en(App_rd_en), .rd_addr(App_rd_addr),
        .rd_vld(sd_vld), .rd_dout(sd_dout)
    );

    // ---- 两路 FIFO + 引擎 ----
    wire        a_we, b_we; wire [31:0] a_wd, b_wd;
    wire [9:0] a_wu, b_wu;   // A1: 深度512 → 10 位
    wire        a_re, b_re; wire [31:0] a_dd, b_dd;
    wire        a_e, b_e; wire [9:0] a_ru, b_ru;   // A1

    afifo_simple #(.DW(32), .AW(9)) u_fa(
        .wr_clk(clk125), .wr_rst(rst), .wr_en(a_we), .wr_data(a_wd), .wr_full(), .wr_usedw(a_wu),
        .rd_clk(clk25), .rd_rst(rst), .rd_en(a_re), .rd_data(a_dd), .rd_empty(a_e), .rd_usedw(a_ru)
    );
    afifo_simple #(.DW(32), .AW(9)) u_fb(
        .wr_clk(clk125), .wr_rst(rst), .wr_en(b_we), .wr_data(b_wd), .wr_full(), .wr_usedw(b_wu),
        .rd_clk(clk25), .rd_rst(rst), .rd_en(b_re), .rd_data(b_dd), .rd_empty(b_e), .rd_usedw(b_ru)
    );

    disp_read_engine #(.HIGH_WATER(256)) u_eng_a(
        .clk(clk125), .rst(rst),
        .vs_toggle(go_toggle), .page_base(base_a_sync2),
        .fifo_we(a_we), .fifo_wdata(a_wd), .fifo_wusedw(a_wu),
        .cmd_valid(A_cv), .cmd_addr(A_ca), .cmd_len(A_cl), .cmd_ready(A_cr),
        .rsp_valid(A_rv), .rsp_data(A_rd), .rsp_last(A_rl)
    );
    disp_read_engine #(.HIGH_WATER(256)) u_eng_b(
        .clk(clk125), .rst(rst),
        .vs_toggle(go_toggle), .page_base(base_b_sync2),
        .fifo_we(b_we), .fifo_wdata(b_wd), .fifo_wusedw(b_wu),
        .cmd_valid(B_cv), .cmd_addr(B_ca), .cmd_len(B_cl), .cmd_ready(B_cr),
        .rsp_valid(B_rv), .rsp_data(B_rd), .rsp_last(B_rl)
    );

    // ---- 混合器 ----
    wire [23:0] mix_rgb; wire [31:0] ufl;
    disp_mixer u_mix(
        .clk(clk25), .rst(rst), .de_al(de_al), .x(px), .y(py),
        .a_rd_en(a_re), .a_rd_data(a_dd), .a_empty(a_e),
        .b_rd_en(b_re), .b_rd_data(b_dd), .b_empty(b_e),
        .tr_active(tr_active), .fade_black(fade_black), .alpha(alpha), .boundary(boundary), .slide_axis(slide_axis),
        .rgb(mix_rgb), .underflow_cnt(ufl)
    );

    // 与 scaler SDRAM 写布局一致：RGB 在 [31:8]，最低字节为 0。
    integer i;
    initial begin
        for (i = 0; i < FRAME_WORDS; i = i + 1) begin
            u_sd.mem[PAGE0 + i] = {pattern_a(i),8'd0};
            u_sd.mem[PAGE1 + i] = {pattern_b(i),8'd0};
        end
    end

    // 按外部提交建立参考页，不能从 DUT 的当前页反推期望结果。
    integer frames_seen=0, checked_pixels=0, checked_frames=0, err=0;
    reg expected_page=0, next_page=0, request_pending=0;
    reg [23:0] expected;
    always @(posedge clk25) begin
        if(de_al && frames_seen>0) begin
            expected=expected_page ? pattern_b(py*640+px) : pattern_a(py*640+px);
            if(mix_rgb !== expected) begin
                if(err<8) $display("FAIL pixel frame=%0d x=%0d y=%0d got=%h expected=%h page=%0d",
                    frames_seen,px,py,mix_rgb,expected,expected_page);
                err=err+1;
            end
            checked_pixels=checked_pixels+1;
        end
        if(vs_rise) begin
            if(frames_seen>0) begin
                if(checked_pixels!=FRAME_WORDS) $fatal(1,"FAIL incomplete frame pixels=%0d",checked_pixels);
                checked_frames=checked_frames+1;
                $display("CHK frame %0d page=%0d pixels=%0d",frames_seen,expected_page,checked_pixels);
            end
            checked_pixels=0;
            if(request_pending) begin expected_page=next_page; request_pending=0; end
            frames_seen=frames_seen+1;
        end
    end
    task submit_page;
        input [1:0] target;
        reg [20:0] old_page;
        begin
            old_page=page_a_base;
            @(negedge clk25); commit_buf=target; commit_toggle=1;
            next_page=target[0]; request_pending=1;
            @(negedge clk25); commit_toggle=0;
            repeat(8) @(negedge clk25);
            if(page_a_base!==old_page || !hold_load) $fatal(1,"FAIL mid-frame cut");
        end
    endtask
    initial begin
        #200; @(negedge clk25); rst=0;
        wait(frames_seen==2);
        submit_page(1); wait(frames_seen==4);
        submit_page(0); wait(frames_seen==6);
        submit_page(1); wait(frames_seen==8);
        #1000;
        // 只豁免启动时尚无 VS 预取的第一帧，此后不允许增加下溢。
        if(ufl!=FRAME_WORDS) $fatal(1,"FAIL underflow=%0d expected=%0d",ufl,FRAME_WORDS);
        if(err!=0 || checked_frames!=7) $fatal(1,"FAIL frames=%0d pixel_errors=%0d",checked_frames,err);
        $display("TB_DISP_PATH PASS frames=%0d exact_pixels=%0d",checked_frames,checked_frames*FRAME_WORDS);
        $finish;
    end
    initial begin #150000000; $fatal(1,"FAIL display path timeout"); end
endmodule
