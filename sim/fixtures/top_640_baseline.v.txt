
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 物理 KEY2：手动下一张
    input                       key2,           // 物理 KEY3：自动播放 开/关
    input                       key3,           // 物理 KEY4：短按转场，长按应急
    input  [3:0]                sw,             // 物理 SW1-SW4：参数调节/图层开关
    output                      buzzer,         // W9: 蜂鸣器（低有效）

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // HDMI_A TMDS（副通道监视台，W2 新增）
    output                      HDMI_A_CLK_P,
    output                      HDMI_A_D2_P,
    output                      HDMI_A_D1_P,
    output                      HDMI_A_D0_P,

    // HDMI_A DDC
    output                      HDMI_A_DDC_SCL,
    inout                       HDMI_A_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 21'd307200;   // 640*480，SDRAM 字地址
parameter BUF0_ADDR     = 21'd0;
parameter BUF1_ADDR     = 21'd524288;   // mem_map: bank1 起点 0x80000（转场双流读零 bank 冲突）

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req_ack;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        sys_pll_lock;
wire        video_pll_lock;
wire        audio_valid;
wire        audio_sample_data_valid;
wire        waveform_pcm_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

// W7: WAV 播放链路
wire        wav_ready;
wire        wav_scan_done, wav_scan_found;
wire [31:0] wav_scan_sector;
wire        wav_load_done, wav_load_active;
wire [31:0] wav_pcm_bytes;
wire        wav_pcm_valid;
wire [15:0] wav_pcm_left, wav_pcm_right;
wire        audio_sample_tick;
wire        wav_sd_sec_read;
wire [31:0] wav_sd_sec_read_addr;
wire [7:0]  wav_sd_sec_read_data;
wire        wav_sd_sec_read_data_valid;
wire        wav_sd_sec_read_end;
wire        wav_fifo_empty, wav_fifo_full;
wire        bmp_load_done;
wire [15:0] bmp_load_img_w, bmp_load_img_h;
wire        sd_init_done;
wire        bmp_sd_sec_read;
wire [31:0] bmp_sd_sec_read_addr;
wire [7:0]  bmp_sd_sec_read_data;
wire        bmp_sd_sec_read_data_valid, bmp_sd_sec_read_end;
wire        sd_phy_sec_read;
wire [31:0] sd_phy_sec_read_addr;
wire [7:0]  sd_phy_sec_read_data;
wire        sd_phy_sec_read_data_valid, sd_phy_sec_read_end;
wire        sd_controller_reset;
wire        bmp_sd_timeout, wav_sd_timeout;
wire [1:0]  sd_owner;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位请求：显式等待 sys/video PLL 锁定并稳定 1ms。
reg [17:0] por_cnt = 18'd0;        // 1ms @ 100MHz (sd_card_clk)
reg        por_done = 1'b0;
reg [1:0]  pll_lock_sync;
always @(posedge sd_card_clk or negedge rst_n) begin
    if (!rst_n) begin
        pll_lock_sync <= 2'b00;
        por_cnt  <= 18'd0;
        por_done <= 1'b0;
    end else begin
        pll_lock_sync <= {pll_lock_sync[0], sys_pll_lock && video_pll_lock};
        if (!pll_lock_sync[1]) begin
            por_cnt  <= 18'd0;
            por_done <= 1'b0;
        end else if (por_cnt < 18'd100_000) begin
            por_cnt <= por_cnt + 18'd1;
        end else begin
            por_done <= 1'b1;
        end
    end
end
wire reset_request = ~rst_n | ~sys_pll_lock | ~video_pll_lock | ~por_done;
wire rst_sd, rst_mem, rst_video;
reset_sync u_rst_sd    (.clk(sd_card_clk), .arst(reset_request), .rst(rst_sd));
reset_sync u_rst_mem   (.clk(ext_mem_clk), .arst(reset_request), .rst(rst_mem));
reset_sync u_rst_video (.clk(video_clk),   .arst(reset_request), .rst(rst_video));

// W10: 物理 KEY4 短按切换转场；同一按键长按由 emergency_ctrl 触发应急。
reg [1:0] tr_mode_reg = 2'd1;   // 默认双页交叉淡化，不改变逐行 SDRAM 读地址
reg       key3_meta, key3_sync, key3_prev;
reg [19:0] key3_cnt;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        key3_meta <= 1'b1;
        key3_sync <= 1'b1;
        key3_prev <= 1'b1;
        key3_cnt  <= 20'd0;
        tr_mode_reg <= 2'd1;
    end else begin
        key3_meta <= key3;
        key3_sync <= key3_meta;
        if (key3_sync != key3_prev) begin
            if (key3_cnt >= 20'd999_999) begin
                key3_prev <= key3_sync;
                key3_cnt  <= 20'd0;
                // 下降沿（按下）→ 切换转场模式
                if (key3_prev && !key3_sync)
                    tr_mode_reg <= tr_mode_reg + 2'd1;
            end else
                key3_cnt <= key3_cnt + 20'd1;
        end else
            key3_cnt <= 20'd0;
    end
end

// W5/W4 主通道像素坐标（供转场/OSD）
wire       main_de_al;
wire [9:0] main_x;
wire [8:0] main_y;
wire [31:0] main_fc;
wire       tr_hold_load;    // 转场期间暂缓装载
wire [23:0] vout_osd;       // OSD 输出
wire [23:0] vout_waveform;  // 老师第十二讲：PCM 时域波形图层输出
wire [23:0] vout_color;     // W8: 色彩调节后输出
wire [23:0] vout_final;     // W9: 应急渲染后输出（最终）

// 前向声明（避免隐式声明）
reg         emergency_mode;
wire        emergency_request_sd;
reg [1:0]   emergency_req_sync_v;
reg [1:0]   emergency_mode_sync_sd;
wire        emergency_mode_sd = emergency_mode_sync_sd[1];
wire [15:0] sync_dev_real;
wire        audio_valid_final;
wire [23:0] audio_left_final;
wire [23:0] audio_right_final;
wire        scaler_done_toggle;
// A2: 主通道 OSD 字库同步读引入 1 拍延迟，de/vs 打 1 拍对齐（vs 宽脉冲，±1 拍无影响）
// （监视台的 mon_de_d1/mon_vs_d1 在 mon_de 声明之后的监视台区段）
reg de_d1, vs_d1;
reg de_d2, de_d3, vs_d2, vs_d3;
reg [9:0] x_d1, x_d2, x_d3;
reg [8:0] y_d1, y_d2, y_d3;
// 波形模块的同步查表已经包含一拍，直接交给下一拍字库层。
wire [23:0] waveform_q = vout_waveform;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        de_d1 <= 0; de_d2 <= 0; de_d3 <= 0;
        vs_d1 <= 0; vs_d2 <= 0; vs_d3 <= 0;
        x_d1 <= 0; x_d2 <= 0; x_d3 <= 0;
        y_d1 <= 0; y_d2 <= 0; y_d3 <= 0;
    end else begin
        // 颜色调整、波形、字库各一拍；RGB、坐标和 DE 必须同拍推进。
        de_d1 <= main_de_al; de_d2 <= de_d1; de_d3 <= de_d2;
        vs_d1 <= vs; vs_d2 <= vs_d1; vs_d3 <= vs_d2;
        x_d1 <= main_x; x_d2 <= x_d1; x_d3 <= x_d2;
        y_d1 <= main_y; y_d2 <= y_d1; y_d3 <= y_d2;
    end
end

// 缩放完成 toggle → video 域 2FF（供转场控制器提交）。
// 源缓存写完只允许启动 scaler，不能提前提交显示页。
wire bmp_display_commit_toggle, bmp_display_commit_pulse;
reg [2:0] commit_sync;
reg [1:0] commit_buf_sync1, commit_buf_sync2;
reg [1:0] tr_mode_sync1_v, tr_mode_sync2_v;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        commit_sync <= 3'b000;
        commit_buf_sync1 <= 2'd0;
        commit_buf_sync2 <= 2'd0;
        tr_mode_sync1_v <= 2'd0;
        tr_mode_sync2_v <= 2'd0;
    end else begin
        commit_sync <= {commit_sync[1:0], bmp_display_commit_toggle};
        commit_buf_sync1 <= write_buf_idx;
        commit_buf_sync2 <= commit_buf_sync1;
        tr_mode_sync1_v <= tr_mode_reg;
        tr_mode_sync2_v <= tr_mode_sync1_v;
    end
end
wire commit_toggle_v = commit_sync[1] ^ commit_sync[2];
reg [1:0] commit_buf_v;
reg commit_pulse_v;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        commit_buf_v <= 2'd0;
        commit_pulse_v <= 1'b0;
    end else begin
        commit_pulse_v <= commit_toggle_v;
        if (commit_toggle_v) commit_buf_v <= commit_buf_sync2;
    end
end
// vs_rise toggle（帧同步给读引擎）
reg vs_toggle_r;
reg vs_toggle_d;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        vs_toggle_r <= 1'b0;
        vs_toggle_d <= 1'b0;
    end else begin
        vs_toggle_d <= vs;
        if (vs && !vs_toggle_d)
            vs_toggle_r <= ~vs_toggle_r;
    end
end

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .extlock    (sys_pll_lock),
    .reset      (~rst_n)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .extlock    (video_pll_lock),
    .reset      (~rst_n)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// W6: frame_write_finish → sd_card_clk 域脉冲（src_packer 排空 + scaler 触发）
reg [2:0] fw_tgl_sync;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) fw_tgl_sync <= 3'b000;
    else         fw_tgl_sync <= {fw_tgl_sync[1:0], frame_write_toggle_mem};
end
wire frame_write_finish_pulse = fw_tgl_sync[2] ^ fw_tgl_sync[1];

// W6: scaler 完成 toggle → sd_card_clk 域 → 作为 write_finish_toggle 给 sd_card_bmp_g。
// 输入是持久 toggle，sd_card_bmp_g 内部再做边沿检测，确保只提交一次。
reg [2:0] scaler_done_sync;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) scaler_done_sync <= 3'b000;
    else         scaler_done_sync <= {scaler_done_sync[1:0], scaler_done_toggle};
end
wire scaler_commit_toggle = scaler_done_sync[1];

// 显示提交握手：源与目标均成功完成才锁住下一次装载，视频完成转场才释放。
// 只同步持久电平和 toggle；不跨域传递单拍脉冲。
reg display_submit_pending_sd;
reg [1:0] tr_hold_sync_sd;
reg tr_hold_prev_v, display_release_toggle_v;
reg [2:0] display_release_sync_sd;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        tr_hold_prev_v <= 0;
        display_release_toggle_v <= 0;
    end else begin
        tr_hold_prev_v <= tr_hold_load;
        if (tr_hold_prev_v && !tr_hold_load)
            display_release_toggle_v <= ~display_release_toggle_v;
    end
end
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        display_submit_pending_sd <= 0;
        tr_hold_sync_sd <= 0;
        display_release_sync_sd <= 0;
    end else begin
        tr_hold_sync_sd <= {tr_hold_sync_sd[0], tr_hold_load};
        display_release_sync_sd <= {display_release_sync_sd[1:0], display_release_toggle_v};
        if (bmp_display_commit_pulse)
            display_submit_pending_sd <= 1;
        else if (display_release_sync_sd[2] ^ display_release_sync_sd[1])
            display_submit_pending_sd <= 0;
    end
end

// ===================== TF 多图扫描与缓存（双缓冲，W3 泛化版: 8 图 + 任意分辨率） =====================
wire [31:0] tf_bmp_debug;
wire [191:0] tf_video_snapshot;
wire [3:0]  scaler_debug_state;
reg  [3:0]  scaler_state_sd;
reg         scaler_busy_sd, scaler_cmd_valid_sd, scaler_cmd_ready_sd, scaler_done_sd;
wire [7:0]  scaler_debug_status = {scaler_state_sd, scaler_busy_sd,
                                    scaler_cmd_valid_sd, scaler_cmd_ready_sd,
                                    scaler_done_sd};
wire [3:0]  img_count;
wire [15:0] cur_img_w, cur_img_h;

// W6: src_packer 插在 bmp_read_g 输出与 frame_read_write 之间
// bmp_read_g 输出 24bit 像素流 → src_packer 打包 RGB565 → frame_read_write 写 SRC_BUF
wire        bmp_wr_en;
wire [23:0] bmp_wr_data;
wire        packed_wr_en;
wire [31:0] packed_wr_data;

wire bmp_source_restart;
// 同一稳定ACK同时供解析器接收握手；raw ACK仍送gate内部相同两级同步。
reg [1:0] source_write_ack_sync_sd;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) source_write_ack_sync_sd <= 0;
    else source_write_ack_sync_sd <= {source_write_ack_sync_sd[0], sd_card_write_req_ack};
end
sd_card_bmp_g #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_TARGET_COUNT (4'd8)
) sd_card_bmp_g_m0(
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .key_next          (key1),
    .key_auto          (key2),
    .hold_load         (display_submit_pending_sd | tr_hold_sync_sd[1]),
    .state_code        (state_code),
    .debug_status      (tf_bmp_debug),
    .img_count         (img_count),
    .cur_img_w         (cur_img_w),
    .cur_img_h         (cur_img_h),
    .display_valid     (display_valid),
    .display_commit_toggle(bmp_display_commit_toggle),
    .display_commit_pulse (bmp_display_commit_pulse),
    .source_restart    (bmp_source_restart),
    .load_done         (bmp_load_done),
    .load_img_w        (bmp_load_img_w),
    .load_img_h        (bmp_load_img_h),

    .write_finish_toggle(scaler_commit_toggle),  // W6: scaler 完成后才 commit
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (source_write_ack_sync_sd[1]),
    .write_en          (bmp_wr_en),           // W6: 改接 src_packer
    .write_data        (bmp_wr_data),         // W6: 24bit RGB
    .sd_init_done      (sd_init_done),
    .sd_sec_read_abort (bmp_sd_timeout),
    .sd_sec_read       (bmp_sd_sec_read),
    .sd_sec_read_addr  (bmp_sd_sec_read_addr),
    .sd_sec_read_data  (bmp_sd_sec_read_data),
    .sd_sec_read_data_valid(bmp_sd_sec_read_data_valid),
    .sd_sec_read_end   (bmp_sd_sec_read_end)
);

// BMP 与 WAV 以扇区为粒度轮转共享唯一 SD 控制器。
sd_arbiter #(.TIMEOUT_CYCLES(10_000_000)) u_sd_arbiter(
    .clk(sd_card_clk), .rst(rst_sd),
    .a_req(bmp_sd_sec_read), .a_addr(bmp_sd_sec_read_addr), .a_ack(),
    .a_data(bmp_sd_sec_read_data), .a_data_valid(bmp_sd_sec_read_data_valid),
    .a_done(bmp_sd_sec_read_end), .a_timeout(bmp_sd_timeout),
    .b_req(wav_sd_sec_read), .b_addr(wav_sd_sec_read_addr), .b_ack(),
    .b_data(wav_sd_sec_read_data), .b_data_valid(wav_sd_sec_read_data_valid),
    .b_done(wav_sd_sec_read_end), .b_timeout(wav_sd_timeout),
    .sd_sec_read(sd_phy_sec_read), .sd_sec_read_addr(sd_phy_sec_read_addr),
    .sd_sec_read_data(sd_phy_sec_read_data),
    .sd_sec_read_data_valid(sd_phy_sec_read_data_valid),
    .sd_sec_read_end(sd_phy_sec_read_end),
    .controller_reset_req(sd_controller_reset), .owner(sd_owner)
);

sd_card_top u_sd_card_top(
    .clk(sd_card_clk),
    .rst(rst_sd | sd_controller_reset),
    .SD_nCS(sd_ncs), .SD_DCLK(sd_dclk), .SD_MOSI(sd_mosi), .SD_MISO(sd_miso),
    .sd_init_done(sd_init_done),
    .sd_sec_read(sd_phy_sec_read), .sd_sec_read_addr(sd_phy_sec_read_addr),
    .sd_sec_read_data(sd_phy_sec_read_data),
    .sd_sec_read_data_valid(sd_phy_sec_read_data_valid), .sd_sec_read_end(sd_phy_sec_read_end),
    .sd_sec_write(1'b0), .sd_sec_write_addr(32'd0), .sd_sec_write_data(8'd0),
    .sd_sec_write_data_req(), .sd_sec_write_end()
);

// TF 诊断旁路：所有输入均已在 SD 时钟域；握手快照后才交给视频渲染。
tf_diag_capture u_tf_diag (
    .sd_clk(sd_card_clk), .sd_rst(rst_sd), .video_clk(video_clk), .video_rst(rst_video),
    .sd_init_done(sd_init_done), .bmp_status(tf_bmp_debug),
    .sd_req(sd_phy_sec_read), .sd_addr(sd_phy_sec_read_addr),
    .sd_data(sd_phy_sec_read_data), .sd_data_valid(sd_phy_sec_read_data_valid),
    .sd_end(sd_phy_sec_read_end), .controller_reset(sd_controller_reset),
    .bmp_timeout(bmp_sd_timeout), .wav_timeout(wav_sd_timeout),
    .pixel_valid(bmp_wr_en), .write_req(sd_card_write_req),
    .frame_write_finish_pulse(frame_write_finish_pulse),
    .scaler_commit_toggle(scaler_commit_toggle), .scaler_debug_status(scaler_debug_status),
    .video_snapshot(tf_video_snapshot)
);

// W6: src_packer — 24bit BMP 像素流 → RGB565 打包（2 像素/字）
// load_done 必须来自 BMP 源解析完成，不能等待 SDRAM write_finish 形成循环依赖。
src_packer u_src_packer(
    .clk       (sd_card_clk),
    .rst       (rst_sd),
    .frame_restart (bmp_source_restart),
    .px_valid  (bmp_wr_en),
    .px_rgb    (bmp_wr_data),
    .row_width (bmp_load_img_w),
    .load_done (bmp_load_done),
    .out_valid (packed_wr_en),
    .out_data  (packed_wr_data)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_scan #(.CLK_FREQ(100_000_000)) seg_scan_m0(
    .clk               (sd_card_clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== W5 显示读出路径重构 =====================
// 官方整帧 FIFO 流读出 → mem_mpu 多主仲裁 + 双行预取引擎 + 双异步 FIFO + 转场混合器
// 装载写路径保持官方 frame_read_write（其读端口闲置: read_req 恒 0）
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_req          (),              // W5: 读时序由 disp_read_engine 自管
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

assign hs = hs_0;
assign vs = vs_0;
assign de = de_0;

reg vs_d_v;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) vs_d_v <= 1'b0;
    else         vs_d_v <= vs;
end
wire vs_rise_v = vs & ~vs_d_v;

// KEY4 请求跨到 video 域，只在帧起始提交；提交结果再同步回控制域。
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        emergency_req_sync_v <= 2'b00;
        emergency_mode       <= 1'b0;
    end else begin
        emergency_req_sync_v <= {emergency_req_sync_v[0], emergency_request_sd};
        if (vs_rise_v)
            emergency_mode <= emergency_req_sync_v[1];
    end
end

always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd)
        emergency_mode_sync_sd <= 2'b00;
    else
        emergency_mode_sync_sd <= {emergency_mode_sync_sd[0], emergency_mode};
end

// ---- 转场控制（video 域） ----
wire        tr_active;           // tr_hold_load 已在 L128 声明
wire        tr_fade_black;
wire [7:0]  tr_alpha;
wire [9:0]  tr_boundary;
wire [1:0]  tr_slide_axis;
wire [20:0] page_a_base, page_b_base;
wire [9:0]  display_scroll_x = (tr_active && tr_slide_axis == 2'd1)
                              ? tr_boundary : 10'd0;

transition_ctrl #(
    .PAGE0_BASE (21'h0_0000),
    .PAGE1_BASE (21'h8_0000),
    .ALPHA_STEP (8'd8),
    .SLIDE_STEP (10'd16)
) u_transition(
    .clk           (video_clk),
    .rst           (rst_video),
    .vs_rise       (vs_rise_v),
    .x             (main_x),
    .y             (main_y),
    .commit_toggle (commit_pulse_v),
    .commit_buf    (commit_buf_v),
    .tr_mode       (tr_mode_sync2_v), // KEY4配置在提交时锁存，转场途中不可变
    .tr_active     (tr_active),
    .fade_black    (tr_fade_black),
    .alpha         (tr_alpha),
    .boundary      (tr_boundary),
    .slide_axis    (tr_slide_axis),
    .page_a_base   (page_a_base),
    .page_b_base   (page_b_base),
    .page_upd_a    (),
    .page_upd_b    (),
    .hold_load     (tr_hold_load)
);

// ---- mem_mpu: 读口三请求方 + 写口二选一 ----
wire        mpu_A_cv, mpu_A_cr, mpu_A_rv, mpu_A_rl;
wire [20:0] mpu_A_ca;
wire [31:0] mpu_A_rd;
wire [7:0]  mpu_A_cl;
wire        mpu_B_cv, mpu_B_cr, mpu_B_rv, mpu_B_rl;
wire [20:0] mpu_B_ca;
wire [31:0] mpu_B_rd;
wire [7:0]  mpu_B_cl;
// W6: C 口（缩放引擎读 SRC_BUF）
wire        mpu_C_cv, mpu_C_cr, mpu_C_rv, mpu_C_rl;
wire [20:0] mpu_C_ca;
wire [31:0] mpu_C_rd;
wire [7:0]  mpu_C_cl;
// W6: 写口 2（缩放引擎写 DISP_BUF）
wire        scaler_wr_en;
wire [20:0] scaler_wr_addr;
wire [31:0] scaler_wr_din;
wire        scaler_busy;
wire        source_write_busy, memory_read_busy, memory_write_ready;
wire        scaler_write_request;
wire        sdram_wr_en;
wire [20:0] sdram_wr_addr;
wire [31:0] sdram_wr_din;
wire [3:0]  sdram_wr_dm;

mem_mpu #(.MAX_A_RUN(8), .MAX_B_RUN(8), .MAX_C_RUN(4)) u_mem_mpu(
    .clk            (ext_mem_clk),
    .rst            (rst_mem),
    .A_cmd_valid    (mpu_A_cv), .A_cmd_addr(mpu_A_ca), .A_cmd_len(mpu_A_cl),
    .A_cmd_ready    (mpu_A_cr), .A_rsp_valid(mpu_A_rv), .A_rsp_data(mpu_A_rd), .A_rsp_last(mpu_A_rl),
    .B_cmd_valid    (mpu_B_cv), .B_cmd_addr(mpu_B_ca), .B_cmd_len(mpu_B_cl),
    .B_cmd_ready    (mpu_B_cr), .B_rsp_valid(mpu_B_rv), .B_rsp_data(mpu_B_rd), .B_rsp_last(mpu_B_rl),
    .C_cmd_valid    (mpu_C_cv), .C_cmd_addr(mpu_C_ca), .C_cmd_len(mpu_C_cl),
    .C_cmd_ready    (mpu_C_cr), .C_rsp_valid(mpu_C_rv), .C_rsp_data(mpu_C_rd), .C_rsp_last(mpu_C_rl),
    .App_rd_en      (App_rd_en),
    .App_rd_addr    (App_rd_addr),
    .Sdr_rd_en      (Sdr_rd_en),
    .Sdr_rd_dout    (Sdr_rd_dout),
    .Sdr_init_done  (Sdr_init_done),
    .Sdr_busy       (Sdr_busy),
    .source_write_busy(source_write_busy),
    .scaler_write_request(scaler_write_request),
    .read_busy      (memory_read_busy),
    .write_ready    (memory_write_ready),
    .App_wr_en_u    (App_wr_en),
    .App_wr_addr_u  (App_wr_addr),
    .App_wr_din_u   (App_wr_din),
    .App_wr_dm_u    (App_wr_dm),
    .App_wr2_en_u   (scaler_wr_en),
    .App_wr2_addr_u (scaler_wr_addr),
    .App_wr2_din_u  (scaler_wr_din),
    .App_wr2_dm_u   (4'h0),
    .wr2_active     (scaler_busy),
    .App_wr_en      (sdram_wr_en),
    .App_wr_addr    (sdram_wr_addr),
    .App_wr_din     (sdram_wr_din),
    .App_wr_dm      (sdram_wr_dm)
);

// ---- 双行预取引擎 + 双异步 FIFO ----
wire        fa_we, fb_we;
wire [31:0] fa_wd, fb_wd;
wire [9:0]  fa_wu, fb_wu;    // A1: 深度 512 → usedw 10 位
wire        fa_re, fb_re;
wire [31:0] fa_dd, fb_dd;
wire        fa_e, fb_e;
wire [9:0]  fa_ru, fb_ru;    // A1

reg [20:0] page_a_sync1_mem, page_a_sync2_mem, page_b_sync1_mem, page_b_sync2_mem;
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem) begin
        page_a_sync1_mem <= 0; page_a_sync2_mem <= 0;
        page_b_sync1_mem <= 21'h8_0000; page_b_sync2_mem <= 21'h8_0000;
    end else begin
        page_a_sync1_mem <= page_a_base; page_a_sync2_mem <= page_a_sync1_mem;
        page_b_sync1_mem <= page_b_base; page_b_sync2_mem <= page_b_sync1_mem;
    end
end

disp_read_engine #(.ENABLE_SCROLL(1)) u_eng_a(
    .clk         (ext_mem_clk),
    .rst         (rst_mem),
    .vs_toggle   (vs_toggle_r),
    .page_base   (page_a_sync2_mem),
    .scroll_x    (display_scroll_x),
    .fifo_we     (fa_we),
    .fifo_wdata  (fa_wd),
    .fifo_wusedw (fa_wu),
    .cmd_valid   (mpu_A_cv),
    .cmd_addr    (mpu_A_ca),
    .cmd_len     (mpu_A_cl),
    .cmd_ready   (mpu_A_cr),
    .rsp_valid   (mpu_A_rv),
    .rsp_data    (mpu_A_rd),
    .rsp_last    (mpu_A_rl)
);
disp_read_engine #(.ENABLE_SCROLL(1)) u_eng_b(
    .clk         (ext_mem_clk),
    .rst         (rst_mem),
    .vs_toggle   (vs_toggle_r),
    .page_base   (page_b_sync2_mem),
    .scroll_x    (display_scroll_x),
    .fifo_we     (fb_we),
    .fifo_wdata  (fb_wd),
    .fifo_wusedw (fb_wu),
    .cmd_valid   (mpu_B_cv),
    .cmd_addr    (mpu_B_ca),
    .cmd_len     (mpu_B_cl),
    .cmd_ready   (mpu_B_cr),
    .rsp_valid   (mpu_B_rv),
    .rsp_data    (mpu_B_rd),
    .rsp_last    (mpu_B_rl)
);

// A1 回退方案B: afifo_simple AW=9（深度512）+ 同步读 + (* ram_style="block" *)
// 官方 wfifo_32_32_512 在 TD 6.2.168116 下存储推断失败（26K LUT/30K FF），已验证弃用
afifo_simple #(.DW(32), .AW(9)) u_fifo_a(
    .wr_clk(ext_mem_clk), .wr_rst(rst_mem), .wr_en(fa_we), .wr_data(fa_wd),
    .wr_full(), .wr_usedw(fa_wu),
    .rd_clk(video_clk), .rd_rst(rst_video), .rd_en(fa_re), .rd_data(fa_dd),
    .rd_empty(fa_e), .rd_usedw(fa_ru)
);
afifo_simple #(.DW(32), .AW(9)) u_fifo_b(
    .wr_clk(ext_mem_clk), .wr_rst(rst_mem), .wr_en(fb_we), .wr_data(fb_wd),
    .wr_full(), .wr_usedw(fb_wu),
    .rd_clk(video_clk), .rd_rst(rst_video), .rd_en(fb_re), .rd_data(fb_dd),
    .rd_empty(fb_e), .rd_usedw(fb_ru)
);

// ---- 双流混合器（下溢计数供监视台 W10） ----
wire [23:0] mix_rgb;
wire [31:0] disp_underflow;
reg [31:0] underflow_prev, underflow_frame;
reg [9:0] fifo_min_work, fifo_min_frame;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        underflow_prev <= 0; underflow_frame <= 0;
        fifo_min_work <= 10'd512; fifo_min_frame <= 0;
    end else if (vs_rise_v) begin
        // 帧边界锁存诊断，屏幕显示稳定值，不读取其他时钟域的水位总线。
        underflow_frame <= disp_underflow - underflow_prev;
        underflow_prev <= disp_underflow;
        fifo_min_frame <= fifo_min_work;
        fifo_min_work <= 10'd512;
    end else if (main_de_al && fa_ru < fifo_min_work) begin
        fifo_min_work <= fa_ru;
    end
end

disp_mixer u_disp_mixer(
    .clk        (video_clk),
    .rst        (rst_video),
    .de_al      (main_de_al),
    .x          (main_x),
    .y          (main_y),
    .a_rd_en    (fa_re),
    .a_rd_data  (fa_dd),
    .a_empty    (fa_e),
    .b_rd_en    (fb_re),
    .b_rd_data  (fb_dd),
    .b_empty    (fb_e),
    .tr_active  (tr_active),
    .fade_black (tr_fade_black),
    .alpha      (tr_alpha),
    .boundary   (tr_boundary),
    .slide_axis (tr_slide_axis),
    .rgb        (mix_rgb),
    .underflow_cnt (disp_underflow)
);

// 首图提交前黑屏；提交后显示转场混合器输出
reg [1:0] display_valid_sync_v;
reg display_visible_v;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin display_valid_sync_v <= 0; display_visible_v <= 0; end
    else begin
        display_valid_sync_v <= {display_valid_sync_v[0], display_valid};
        if (vs_rise_v) display_visible_v <= display_valid_sync_v[1];
    end
end
assign vout_data = display_visible_v ? mix_rgb : 24'd0;

// ===================== W6: 缩放引擎 =====================
// 从 SRC_BUF 读 RGB565 源图，双线性插值缩放到 640×480，写入目标 DISP_BUF
// 触发: 本次新写请求应答后，BMP成功与SRC_BUF写完均到达，再翻转start_toggle。
wire scaler_start_tgl;
source_scaler_gate u_source_scaler_gate (
    .clk(sd_card_clk), .rst(rst_sd), .sd_init_done(sd_init_done),
    .source_restart(bmp_source_restart), .source_done(bmp_load_done),
    .write_req(sd_card_write_req), .write_req_ack(sd_card_write_req_ack),
    .frame_write_finish_pulse(frame_write_finish_pulse),
    .scaler_start_toggle(scaler_start_tgl), .scaler_start_pulse()
);
// 缩放器内部已经完成持久 toggle 的跨时钟域同步和边沿检测。
// 配置在同一个启动事件被锁存，必须使用本次装载的尺寸和写页。
// 装载管理器在缩放完成前保持 busy，宽高和写页在启动同步期间保持稳定。
// pending_buf_idx 与 write_buf_idx 在装载启动时同步更新，完成提交时也使用同一页。
wire [20:0] scaler_dst_base = (write_buf_idx == 2'd0) ? 21'h0_0000 : 21'h8_0000;

scaler #(
    .OUT_W(640),
    .OUT_H(480)
) u_scaler (
    .clk            (ext_mem_clk),
    .rst            (rst_mem),
    .start_toggle   (scaler_start_tgl),
    .cfg_w          (bmp_load_img_w[10:0]),
    .cfg_h          (bmp_load_img_h[10:0]),
    .cfg_src_base   (21'hC_B000),        // MEM_BUF_SRC_BASE
    .cfg_dst_base   (scaler_dst_base),   // 首图与后续图均写入本次待提交页
    // mem_mpu 请求方 C
    .cmd_valid      (mpu_C_cv),
    .cmd_addr       (mpu_C_ca),
    .cmd_len        (mpu_C_cl),
    .cmd_ready      (mpu_C_cr),
    .rsp_valid      (mpu_C_rv),
    .rsp_data       (mpu_C_rd),
    .rsp_last       (mpu_C_rl),
    .write_request  (scaler_write_request),
    .write_ready    (memory_write_ready),
    // mem_mpu 写方 2
    .wr_en          (scaler_wr_en),
    .wr_addr        (scaler_wr_addr),
    .wr_din         (scaler_wr_din),
    .wr_dm          (),
    .busy           (scaler_busy),
    .done_toggle    (scaler_done_toggle),
    .debug_state    (scaler_debug_state)
);

// TF-D3：将 scaler 状态和 C 口握手同步到 SD 诊断域。
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        scaler_state_sd <= 4'd0;
        scaler_busy_sd <= 1'b0;
        scaler_cmd_valid_sd <= 1'b0;
        scaler_cmd_ready_sd <= 1'b0;
        scaler_done_sd <= 1'b0;
    end else begin
        scaler_state_sd <= scaler_debug_state;
        scaler_busy_sd <= scaler_busy;
        scaler_cmd_valid_sd <= mpu_C_cv;
        scaler_cmd_ready_sd <= mpu_C_cr;
        scaler_done_sd <= scaler_done_toggle;
    end
end

// ---- W6: 装载写路径 → SRC_BUF（RGB565 打包，scaler 读取源） ----
wire video_read_en_unused;
wire [31:0] video_read_data_unused;

// SRC_BUF 写入长度：ceil(W/2)*H 个 32bit 字；奇数宽必须逐行补齐，不能整帧取整。
// frame_fifo_write 会在接受本次 write_req 时锁存该长度。
wire [31:0] src_row_words  = ({16'd0, bmp_load_img_w} + 32'd1) >> 1;
wire [31:0] src_word_count = src_row_words * {16'd0, bmp_load_img_h};
wire [20:0] src_write_len  = src_word_count[20:0];

frame_read_write #(
    // 源缓存按 BMP 文件顺序线性写入；scaler 按动态 row_words 负责垂直方向转换。
    .WRITE_V_FLIP     (0),
    .EXTERNAL_READ    (1),
    .FRAME_WIDTH      (320),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (),
    .App_rd_addr       (),
    .Sdr_rd_en         (1'b0),
    .Sdr_rd_dout       (32'd0),

    .read_clk          (video_clk),
    .read_req          (1'b0),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en_unused),
    .read_data         (video_read_data_unused),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .external_rd_busy   (memory_read_busy),
    .source_write_busy  (source_write_busy),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    // W6: 写入 SRC_BUF（固定地址，不交替）
    .write_addr_0      (21'hC_B000),      // MEM_BUF_SRC_BASE
    .write_addr_1      (21'hC_B000),
    .write_addr_2      (21'hC_B000),
    .write_addr_3      (21'hC_B000),
    .write_addr_index  (2'd0),            // 固定用 addr_0
    .write_len         (src_write_len),
    .write_en          (packed_wr_en),    // W6: 来自 src_packer
    .write_data        (packed_wr_data)   // W6: RGB565 打包
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (sdram_wr_en),
    .App_wr_addr       (sdram_wr_addr),
    .App_wr_dm         (sdram_wr_dm),
    .App_wr_din        (sdram_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== WAV 播放链路 =====================
// 首图提交后再扫描 WAV，避免启动阶段与图片索引/装载争用 SD 带宽。
reg wav_scan_start_r, wav_load_start_r;
reg wav_scan_kicked, wav_load_running;
wire wav_rst = rst_sd | ~sd_init_done;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        wav_scan_start_r <= 1'b0;
        wav_load_start_r <= 1'b0;
        wav_scan_kicked  <= 1'b0;
        wav_load_running <= 1'b0;
    end else begin
        wav_scan_start_r <= 1'b0;
        wav_load_start_r <= 1'b0;
        if (!sd_init_done) begin
            wav_scan_kicked  <= 1'b0;
            wav_load_running <= 1'b0;
        end else begin
            if (!wav_scan_kicked && wav_ready && display_valid) begin
                wav_scan_start_r <= 1'b1;
                wav_scan_kicked  <= 1'b1;
            end
            if (wav_scan_done && wav_scan_found && wav_ready && !wav_load_running) begin
                wav_load_start_r <= 1'b1;
                wav_load_running <= 1'b1;
            end
            if (wav_load_done)
                wav_load_running <= 1'b0;
        end
    end
end

wav_read u_wav_read(
    .clk                   (sd_card_clk),
    .rst                   (wav_rst),
    .ready                 (wav_ready),
    .scan_start            (wav_scan_start_r),
    .scan_start_sector     (32'd0),
    .scan_done             (wav_scan_done),
    .scan_found_valid      (wav_scan_found),
    .scan_found_sector     (wav_scan_sector),
    .load_start            (wav_load_start_r),
    .load_sector           (wav_scan_sector),
    .load_done             (wav_load_done),
    .load_active           (wav_load_active),
    .load_pcm_bytes        (wav_pcm_bytes),
    .sd_sec_read           (wav_sd_sec_read),
    .sd_sec_read_addr      (wav_sd_sec_read_addr),
    .sd_sec_read_data      (wav_sd_sec_read_data),
    .sd_sec_read_data_valid(wav_sd_sec_read_data_valid),
    .sd_sec_read_end       (wav_sd_sec_read_end),
    .pcm_valid             (wav_pcm_valid),
    .pcm_left              (wav_pcm_left),
    .pcm_right             (wav_pcm_right),
    .pcm_ready             (!wav_fifo_full)
);

audio_player u_audio_player(
    .clk_sd       (sd_card_clk),
    .clk_video    (video_clk),
    .rst_sd       (rst_sd),
    .rst_video    (rst_video),
    .pcm_valid    (wav_pcm_valid),
    .pcm_left     (wav_pcm_left),
    .pcm_right    (wav_pcm_right),
    .vs_pulse     (vs_rise_v),
    .audio_valid  (audio_valid),
    .sample_data_valid (audio_sample_data_valid),
    .audio_left   (audio_left_data),
    .audio_right  (audio_right_data),
    .sync_dev     (sync_dev_real),   // W10: 接监视台
    .sample_cnt   (),
    .frame_cnt    (),
    .sample_tick  (audio_sample_tick),
    .fifo_empty   (wav_fifo_empty),
    .fifo_full    (wav_fifo_full)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_audio_valid (audio_valid_final),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (vs_d3),
    .I_de          (de_d3),
    .I_rgb         (vout_final),      // W8: 色彩调节后输出
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid_final),   // W9: 应急模式切警笛
    .I_audio_left_data  (audio_left_final),
    .I_audio_right_data (audio_right_final),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_video),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

// ===================== W2: 副通道监视台（HDMI_A） =====================
// 运行状态计数（video_clk 域，主通道帧边界计数）
reg  [31:0] frame_cnt;
reg  [5:0]  sec_frames;
reg  [31:0] uptime_sec;
reg         vs_d;
wire        vs_edge = vs & ~vs_d;

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        frame_cnt  <= 32'd0;
        sec_frames <= 6'd0;
        uptime_sec <= 32'd0;
        vs_d       <= 1'b0;
    end else begin
        vs_d <= vs;
        if (vs_edge) begin
            frame_cnt <= frame_cnt + 32'd1;
            if (sec_frames == 6'd59) begin
                sec_frames <= 6'd0;
                uptime_sec <= uptime_sec + 32'd1;
            end else begin
                sec_frames <= sec_frames + 6'd1;
            end
        end
    end
end

// W10: 接入真实同步偏差与模式（已在顶部前向声明）
wire [1:0]  mode_v1 = emergency_mode ? 2'd2 : 2'd1;  // 0:启动 1:广告 2:应急

// OSD 实时时钟（BCD）：HH/MM/SS 级联进位
reg [7:0] clk_ss, clk_mm, clk_hh;   // 各两位 BCD
wire      sec_tick = vs_edge && (sec_frames == 6'd0);
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        clk_ss <= 8'd0; clk_mm <= 8'd0; clk_hh <= 8'd0;
    end else if (sec_tick) begin
        if (clk_ss[3:0] == 4'd9) begin
            clk_ss[3:0] <= 4'd0;
            if (clk_ss[7:4] == 4'd5) begin
                clk_ss[7:4] <= 4'd0;
                if (clk_mm[3:0] == 4'd9) begin
                    clk_mm[3:0] <= 4'd0;
                    if (clk_mm[7:4] == 4'd5) begin
                        clk_mm[7:4] <= 4'd0;
                        if (clk_hh[3:0] == 4'd9) begin
                            clk_hh[3:0] <= 4'd0;
                            clk_hh[7:4] <= (clk_hh[7:4] == 4'd2) ? 4'd0 : clk_hh[7:4] + 4'd1;
                        end else clk_hh[3:0] <= clk_hh[3:0] + 4'd1;
                    end else clk_mm[7:4] <= clk_mm[7:4] + 4'd1;
                end else clk_mm[3:0] <= clk_mm[3:0] + 4'd1;
            end else clk_ss[7:4] <= clk_ss[7:4] + 4'd1;
        end else clk_ss[3:0] <= clk_ss[3:0] + 4'd1;
    end
end

// ---- W4: 主通道 OSD 合成 ----
pixel_pos_gen u_main_pos(
    .I_clk       (video_clk),
    .I_rst       (rst_video),
    .I_vs        (vs),
    .I_de        (de),
    .O_de        (main_de_al),
    .O_x         (main_x),
    .O_y         (main_y),
    .O_frame_cnt (main_fc)
);

osd_engine u_osd(
    .I_clk        (video_clk),
    .I_x          (x_d2),
    .I_y          (y_d2),
    .I_bg_rgb     (waveform_q),
    .I_uptime_bcd ({clk_hh, clk_mm, clk_ss}),
    .I_mode       (mode_v1),
    .O_rgb        (vout_osd)
);

// ===================== 老师第十二讲：PCM 时域波形 =====================
// 每 120 个 PCM 样本抽取一个，32 点覆盖约 80 ms 音频；采集可跨帧继续，
// 只在 VS 边界发布完整采样组，并逐帧平滑、消隐期预计算曲线。
promax_audio_waveform #(
    .WAVE_X      (64), .WAVE_Y(376), .WAVE_WIDTH(512), .WAVE_HEIGHT(72), .DECIMATE(120)
) u_promax_audio_waveform(
    .clk           (video_clk),
    .rst           (rst_video),
    .vs_pulse      (vs_rise_v),
    .de            (de_d1),
    .pixel_x       (x_d1),
    .pixel_y       (y_d1),
    .rgb_in        (vout_color),
    .enable        (1'b1),
    .pcm_tap_valid (waveform_pcm_valid),
    .pcm_tap_left  (audio_left_final[23:8]),
    .rgb_out       (vout_waveform),
    .waveform_active()
);

// color_adjust: 亮度/对比度/色温（SW2-4 调节）
color_adjust u_color_adjust(
    .clk        (video_clk),
    .rst        (rst_video),
    .de_in      (main_de_al),
    .rgb_in     (vout_data),
    .contrast   (sw[1] ? 8'd192 : 8'd128),   // SW2: 对比度增强
    .brightness (sw[2] ? 8'sd30 : 8'sd0),    // SW3: 亮度提升
    .color_temp (sw[3] ? 8'sd20 : 8'sd0),    // SW4: 色温偏暖
    .de_out     (),
    .rgb_out    (vout_color)
);

// ===================== W9: 应急模式 =====================
wire buzzer_drv;

emergency_ctrl #(
    .CLK_FREQ_HZ   (100_000_000),
    .LONG_PRESS_MS (2000)
) u_emergency_ctrl(
    .clk            (sd_card_clk),
    .rst            (rst_sd),
    .key4           (key3),
    .mode_active    (emergency_mode_sd),
    .emergency_request(emergency_request_sd),
    .buzzer_on      (buzzer_drv)
);

assign buzzer = ~buzzer_drv;  // 低有效

// emergency_render: 应急模式下替换视频输出
emergency_render u_emergency_render(
    .clk            (video_clk),
    .de_in          (de_d3),
    .x              (x_d3),
    .y              (y_d3),
    .emergency_mode (emergency_mode),
    .normal_rgb     (vout_osd),
    .rgb_out        (vout_final)
);

// siren_gen: 应急模式下替换音频输出
wire        siren_valid;
wire [23:0] siren_left, siren_right;

siren_gen u_siren_gen(
    .clk         (video_clk),
    .rst         (rst_video),
    .enable      (emergency_mode),
    .sample_tick (audio_sample_tick),
    .audio_valid (siren_valid),
    .audio_left  (siren_left),
    .audio_right (siren_right)
);

// 音频源选择：应急模式 → 警笛，正常模式 → WAV（已在顶部前向声明）
assign audio_valid_final = emergency_mode ? siren_valid : audio_valid;
assign audio_left_final  = emergency_mode ? siren_left  : audio_left_data;
assign audio_right_final = emergency_mode ? siren_right : audio_right_data;
// HDMI 包节拍包含 FIFO 空时的静音；波形采集只接受真实 PCM 样本事件。
assign waveform_pcm_valid = emergency_mode ? siren_valid : audio_sample_data_valid;

wire mon_hs, mon_vs, mon_de;
wire [9:0]  mon_x;
wire [8:0]  mon_y;
wire [23:0] mon_rgb;
wire        mon_axis_user;
wire        mon_axis_valid;
wire        mon_axis_last;
wire [23:0] mon_axis_data;
// A2: 监视台字库同步读 1 拍延迟对齐
reg mon_de_d1, mon_vs_d1;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        mon_de_d1 <= 1'b0;
        mon_vs_d1 <= 1'b0;
    end else begin
        mon_de_d1 <= mon_de;
        mon_vs_d1 <= mon_vs;
    end
end
wire [9:0] mon_tmds_ch0, mon_tmds_ch1, mon_tmds_ch2, mon_tmds_clk;
wire       mon_edid_trig, mon_edid_valid;
wire [7:0] mon_edid_data;

video_timing_gen #(
    .HTOTAL(800), .HSA(96), .HFP(16), .HBP(48), .HACTIVE(640),
    .VTOTAL(525), .VSA(2),  .VFP(10), .VBP(33), .VACTIVE(480)
) u_mon_timing_gen(
    .I_clk (video_clk),
    .I_rst (rst_video),
    .O_hs  (mon_hs),
    .O_vs  (mon_vs),
    .O_de  (mon_de),
    .O_x   (mon_x),
    .O_y   (mon_y)
);

monitor_compositor u_mon_compositor(
    .I_clk        (video_clk),
    .I_de         (mon_de),
    .I_x          (mon_x),
    .I_y          (mon_y),
    .I_uptime_sec (uptime_sec),
    .I_frame_cnt  (frame_cnt),
    .I_sync_dev   (sync_dev_real),
    .I_mode       (mode_v1),
    .I_tf_diag    (tf_video_snapshot),
    .I_disp_underflow(underflow_frame),
    .I_fifo_a_used (fifo_min_frame),
    .O_rgb        (mon_rgb)
);

video_rgb_to_axis_640x480 u_mon_rgb_to_axis(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (mon_vs_d1),
    .I_de          (mon_de_d1),
    .I_rgb         (mon_rgb),
    .O_video_user  (mon_axis_user),
    .O_video_valid (mon_axis_valid),
    .O_video_last  (mon_axis_last),
    .O_video_data  (mon_axis_data)
);

startup_pulse #(
    .CNT_MAX(20'd200000)
) u_mon_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (mon_edid_trig)
);

hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_core_mon(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (mon_edid_trig),
    .O_edid_read_valid  (mon_edid_valid),
    .O_edid_read_data   (mon_edid_data),

    .I_axis_s_user      (mon_axis_user),
    .I_axis_s_valid     (mon_axis_valid),
    .I_axis_s_last      (mon_axis_last),
    .I_axis_s_data      (mon_axis_data),
    .O_axis_s_ready     (),

    .I_audio_valid      (1'b0),
    .I_audio_left_data  (24'd0),
    .I_audio_right_data (24'd0),
    .I_acr_valid        (1'b0),
    .I_acr_cts          (20'd0),
    .I_acr_n            (20'd0),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_A_DDC_SCL),
    .IO_ddc_sda         (HDMI_A_DDC_SDA),

    .O_ch0_tmds_data    (mon_tmds_ch0),
    .O_ch1_tmds_data    (mon_tmds_ch1),
    .O_ch2_tmds_data    (mon_tmds_ch2),
    .O_clk_tmds_data    (mon_tmds_clk)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi_phy_mon(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_video),
    .I_tmds_channel_0   (mon_tmds_ch0),
    .I_tmds_channel_1   (mon_tmds_ch1),
    .I_tmds_channel_2   (mon_tmds_ch2),
    .I_tmds_channel_clk (mon_tmds_clk),
    .O_tmds_ch0_p       (HDMI_A_D0_P),
    .O_tmds_ch1_p       (HDMI_A_D1_P),
    .O_tmds_ch2_p       (HDMI_A_D2_P),
    .O_tmds_clk_p       (HDMI_A_CLK_P)
);

endmodule
