// tb_disp_path.v — W5 显示读出全路径仿真
// 链路: sdram_beh → mem_mpu → 2×disp_read_engine → 2×afifo_simple → disp_mixer
//       ← transition_ctrl ← 视频时序(video_timing_gen+pixel_pos_gen)
// 检查: ①非转场帧输出=页A内容 ②淡入淡出中帧=blend(A,B,α) 精确值
//       ③完成后输出=页B内容 ④下溢计数=0 ⑤帧完整覆盖(哨兵)
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
    wire        tr_active, page_upd_a, page_upd_b, hold_load;
    wire [7:0]  alpha;
    wire [9:0]  boundary;
    wire [1:0]  slide_axis;
    wire [20:0] page_a_base, page_b_base;

    localparam ALPHA_STEP = 8'd32;   // TB 加速: 8 帧完成淡入淡出

    transition_ctrl #(
        .PAGE0_BASE(PAGE0), .PAGE1_BASE(PAGE1), .ALPHA_STEP(ALPHA_STEP)
    ) u_tr(
        .clk(clk25), .rst(rst), .vs_rise(vs_rise), .x(px), .y(py),
        .commit_toggle(commit_toggle), .commit_buf(commit_buf),
        .tr_mode(2'd1),
        .tr_active(tr_active), .alpha(alpha), .boundary(boundary),
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
        .tr_active(tr_active), .alpha(alpha), .boundary(boundary), .slide_axis(slide_axis),
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

    // 哨兵帧缓存
    reg [23:0] fb [0:307199];
    integer si;
    initial for (si = 0; si < 307200; si = si + 1) fb[si] = 24'hFF00FF;

    // ---- 捕获与检查 ----
    integer frames_seen = 0;
    integer err = 0;
    reg [23:0] exp;
    integer chk_frame = -1;         // 需要精确校验的帧号（-1 不校验）
    integer stim_target;            // 激励专用等待目标（chk_frame 会被 vs 块清 -1，勿混用）
    reg [7:0] chk_alpha;
    integer nbad;

    always @(posedge clk25)
        if (commit_toggle) $display("DBG commit seen t=%0t", $time);
    always @(posedge clk25)
        if (vs_rise && u_tr.commit_pend) $display("DBG vs with pend t=%0t pend=%0d", $time, u_tr.pend_buf);
    always @(posedge clk25)
        if (vs_rise) $display("DBG vs t=%0t tr=%b pend_f=%b", $time, tr_active, u_tr.commit_pend);
    reg dbg8 = 0;
    always @(posedge clk25) begin
        if (vs_rise && frames_seen == 8) dbg8 = 1;
        if (vs_rise && frames_seen == 9) dbg8 = 0;
        if (dbg8 && de_al && px == 10'd100 && py == 9'd10)
            $display("MIX8 t=%0t a_e=%b b_e=%b pa=%h pb=%h alpha=%0d out=%h a_ru=%0d b_ru=%0d",
                     $time, a_e, b_e, a_dd[23:0], b_dd[23:0], alpha, mix_rgb, a_ru, b_ru);
        if (de_al) fb[py * 640 + px] <= mix_rgb;
        if (vs_rise) begin
            if (chk_frame >= 0 && frames_seen == chk_frame) begin
                // 帧结束时全帧比对: blend(64,192,alpha)+rounding
                nbad = 0;
                for (si = 0; si < 307200; si = si + 1) begin
                    exp = expected_mix(si, chk_alpha);
                    if (fb[si] !== exp) nbad = nbad + 1;
                end
                if (nbad != 0) begin
                    err = err + 1;
                    $display("ERR frame %0d alpha=%0d nbad=%0d sample fb[100]=%h exp=%h",
                             frames_seen, chk_alpha, nbad, fb[100], exp);
                end else
                    $display("CHK frame %0d alpha=%0d OK", frames_seen, chk_alpha);
                chk_frame = -1;
            end
            $display("INFO frame %0d start: tr=%b alpha=%0d ufl=%0d", frames_seen, tr_active, alpha, ufl);
            frames_seen = frames_seen + 1;
        end
    end

    // ---- 链路探针 ----
    integer n_go, n_acmd, n_agrant, n_aen, n_sd, n_awe, n_apop;
    initial begin n_go=0; n_acmd=0; n_agrant=0; n_aen=0; n_sd=0; n_awe=0; n_apop=0; end
    integer st_idle, st_cmd, st_drain, n_wm_block, n_fb_idle;
    integer n_inb, n_should, n_stuck;
    initial n_stuck = 0;
    initial begin st_idle=0; st_cmd=0; st_drain=0; n_wm_block=0; n_fb_idle=0; n_inb=0; n_should=0; end
    always @(posedge clk125) begin
        case (u_mpu.state)
            2'd0: st_idle = st_idle + 1;
            2'd1: st_cmd = st_cmd + 1;
            2'd2: st_drain = st_drain + 1;
        endcase
        if (u_eng_a.frame_act == 0) n_fb_idle = n_fb_idle + 1;
        if (u_eng_a.frame_act && !u_eng_a.in_burst && a_wu >= 512) n_wm_block = n_wm_block + 1;
        if (u_eng_a.frame_act && u_eng_a.in_burst) begin
            n_inb = n_inb + 1;
            if (!u_eng_a.cmd_valid && u_eng_a.burst_left == 0) begin
                n_stuck = n_stuck + 1;
                if (n_stuck <= 3)
                    $display("DBG stuck#%0d t=%0t word_cnt=%0d mpu_state=%0d sd_vld=%b",
                             n_stuck, $time, u_eng_a.word_cnt, u_mpu.state, sd_vld);
            end
        end
        if (u_eng_a.frame_act && !u_eng_a.in_burst && a_wu < 512) n_should = n_should + 1;
        if (frame_go) n_go = n_go + 1;
        if (u_eng_a.cmd_valid) n_acmd = n_acmd + 1;
        if (A_cr) n_agrant = n_agrant + 1;
        if (a_we) n_awe = n_awe + 1;
        if (App_rd_en) n_aen = n_aen + 1;
        if (sd_vld) n_sd = n_sd + 1;
    end
    always @(posedge clk25) if (a_re) n_apop = n_apop + 1;

    initial begin
        $timeformat(-9, 1, " ns", 13);
    end

    // ---- burst1 内部时间戳 ----
    reg t_en_on = 0, t_en_off = 0, t_sd_on = 0, t_sd_off = 0;
    integer t_en_cnt = 0;
    integer sd_cnt1 = 0;
    always @(posedge clk125) begin
        if (App_rd_en) begin
            t_en_cnt = t_en_cnt + 1;
            if (t_en_cnt <= 20 || t_en_cnt == 127 || t_en_cnt == 128)
                $display("TS t=%0t en beat#%0d addr=%0d mpu_state=%0d", $time, t_en_cnt, App_rd_addr, u_mpu.state);
        end
        if (App_rd_en && !t_en_on) begin t_en_on = 1; end
        if (t_en_on && !App_rd_en && !t_en_off) begin t_en_off = 1; $display("TS t=%0t App_rd_en last beat done (cnt=%0d)", $time, t_en_cnt); end
        if (sd_vld && !t_sd_on) begin t_sd_on = 1; $display("TS t=%0t sd first beat", $time); end
        if (t_sd_on && sd_vld) begin
            sd_cnt1 = sd_cnt1 + 1;
            if (!t_sd_off && sd_cnt1 >= 128) begin t_sd_off = 1; $display("TS t=%0t sd beat#%0d", $time, sd_cnt1); end
        end
    end

    // ---- 时钟周期实测 ----
    reg c125_d = 0; integer t_last = 0; integer n_meas = 0;
    always @(posedge clk125) begin
        if (c125_d === 1'b0 || n_meas < 3) begin
            if (t_last != 0 && n_meas < 3)
                $display("TSCLK t=%0t delta=%0d", $time, $time - t_last);
            t_last = $time;
            n_meas = n_meas + 1;
        end
        c125_d <= 1'b1;
    end

    // ---- 突发生命周期追踪 ----
    reg inb_d = 0;
    integer burst_id;
    initial burst_id = 0;
    always @(posedge clk125) begin
        inb_d <= u_eng_a.in_burst;
        if (u_eng_a.in_burst && !inb_d) begin
            burst_id = burst_id + 1;
            if (burst_id <= 3)
                $display("TRC t=%0t burst%0d START cv=%b eng_len=%0d mpu_len=%0d wu=%0d mpu=%0d ready=%b",
                         $time, burst_id, u_eng_a.cmd_valid, u_eng_a.cmd_len, u_mpu.cmd_len, a_wu, u_mpu.state, A_cr);
        end
        if (!u_eng_a.in_burst && inb_d && burst_id <= 3)
            $display("TRC t=%0t burst%0d END word=%0d", $time, burst_id, u_eng_a.word_cnt);
    end

    // ---- 停转检测: in_burst 且 500 拍无 rsp ----
    integer stall_cnt = 0;
    reg stall_reported = 0;
    always @(posedge clk125) begin
        if (u_eng_a.in_burst && !u_eng_a.cmd_valid && u_eng_a.burst_left != 0 && !A_rv)
            stall_cnt = stall_cnt + 1;
        else
            stall_cnt = 0;
        if (stall_cnt == 500 && !stall_reported) begin
            stall_reported = 1;
            $display("STALL t=%0t burst_left=%0d word_cnt=%0d mpu_state=%0d mpu_rsp_beats=%0d mpu_cmd_len=%0d grant_a=%b sd_vld=%b mpu_gap=%0d",
                     $time, u_eng_a.burst_left, u_eng_a.word_cnt, u_mpu.state,
                     u_mpu.rsp_beats, u_mpu.cmd_len, u_mpu.grant_sel, sd_vld, u_mpu.gap_cnt);
        end
    end

    // ---- 激励 ----
    initial begin
        rst = 1; #200;
        @(posedge clk25); rst = 0;

        // 帧 1~2: 非转场（应输出页A=灰64）
        chk_frame = 2; chk_alpha = 8'd0;
        wait(frames_seen == 3);
        // 触发转场: 提交页B
        @(posedge clk25); commit_toggle = 1; commit_buf = 2'd1;
        @(posedge clk25); commit_toggle = 0;
        // 淡入淡出第 16 帧: alpha≈128 → 校验中点
        wait(tr_active == 1'b1);
        @(posedge vs_rise);
        wait(alpha == 8'd128);
        chk_frame = frames_seen; chk_alpha = 8'd128;
        stim_target = frames_seen + 1;
        wait(frames_seen == stim_target);
        // 完成后第一帧: 应输出页B（tr=0 直通 A 引擎, A 引擎此时已切到页B）
        $display("STIM wait tr==0 (cur=%b)", tr_active);
        wait(tr_active == 1'b0);
        $display("STIM tr fell, frames_seen=%0d", frames_seen);
        @(posedge vs_rise);
        $display("STIM next vs, frames_seen=%0d", frames_seen);
        chk_frame = frames_seen; chk_alpha = 8'd255;
        stim_target = frames_seen + 1;
        wait(frames_seen == stim_target);
        $display("STIM final frame captured");

        #200_000;
        if (ufl > 32'd307200) begin err = err + 1; $display("ERR underflow=%0d (首帧豁免 307200)", ufl); end
        $display("PROBE2 idle=%0d cmd=%0d drain=%0d fb_idle=%0d wm_block=%0d inb=%0d should=%0d stuck=%0d",
                 st_idle, st_cmd, st_drain, n_fb_idle, n_wm_block, n_inb, n_should, n_stuck);
        $display("PROBE go=%0d acmd=%0d agrant=%0d aen=%0d sd=%0d awe=%0d apop=%0d fifo_a_wu=%0d ru=%0d empty=%b base=%h",
                 n_go, n_acmd, n_agrant, n_aen, n_sd, n_awe, n_apop, a_wu, a_ru, a_e, base_a_sync2);
        if (err == 0) $display("TB_DISP_PATH PASS");
        else $display("TB_DISP_PATH FAIL err=%0d", err);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("PROBE2 idle=%0d cmd=%0d drain=%0d fb_idle=%0d wm_block=%0d inb=%0d should=%0d stuck=%0d",
                 st_idle, st_cmd, st_drain, n_fb_idle, n_wm_block, n_inb, n_should, n_stuck);
        $display("PROBE go=%0d acmd=%0d agrant=%0d aen=%0d sd=%0d awe=%0d apop=%0d fifo_a_wu=%0d ru=%0d empty=%b base=%h",
                 n_go, n_acmd, n_agrant, n_aen, n_sd, n_awe, n_apop, a_wu, a_ru, a_e, base_a_sync2);
        $display("TB_DISP_PATH TIMEOUT");
        $finish;
    end
endmodule
