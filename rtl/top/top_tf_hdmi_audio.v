
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 物理 KEY2：手动下一张
    input                       key2,           // 物理 KEY3：自动播放 开/关
    input                       key3,           // 物理 KEY4：长按进入/退出应急
    input  [3:0]                sw,             // 物理 SW1-SW4：参数调节/图层开关
    output                      buzzer,         // W9: 蜂鸣器（低有效）
    output [3:0]                led,            // 板载绿色 LED，LED0..LED3

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

    // HDMI_A TMDS（640x480 监视与控制台）
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
parameter FRAME_PIXELS  = 21'd460800;   // 1280*720/2，RGB565双像素字
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

// 菜单控制器与 HDMI-A 状态信号必须在实例化前声明，避免 TD 生成隐式网。
wire [3:0]  cfg_shadow_sd;
wire [3:0]  cfg_payload_sd;
wire [9:0]  screen_shadow_sd, screen_payload_sd;
wire [4:0]  subtitle_shadow_sd, subtitle_payload_sd;
wire        monitor_subtitle_page_sd, monitor_subtitle_edit_sd;
wire        monitor_screen_page_sd, monitor_screen_edit_sd, monitor_cfg_busy_sd;
wire        cfg_commit_toggle_sd;
wire        monitor_menu_active_sd, monitor_menu_page_sd;
wire [2:0]  monitor_cursor_sd;
wire [1:0]  monitor_period_shadow_sd, monitor_period_active_sd;
wire        monitor_cfg_dirty_sd, monitor_buzzer_test_sd;
wire        monitor_key_next_pulse_sd, monitor_key_auto_pulse_sd;
wire [15:0] monitor_key_events_sd;
wire [2:0]  monitor_key_state_sd;
wire        cfg_commit_ack_toggle_sd;
reg  [2:0]  cfg_ack_sync_sd;
wire [9:0]  mon_tmds_ch0, mon_tmds_ch1, mon_tmds_ch2, mon_tmds_clk;
reg         emergency_mode;
wire        emergency_request_sd;
reg [1:0]   emergency_req_sync_v;
reg [1:0]   emergency_mode_sync_sd;
wire        emergency_mode_sd = emergency_mode_sync_sd[1];

// 板载 LED 状态：LED0 心跳，LED1 TF/首图有效，LED2 WAV 已找到，
// LED3 应急或 SD 超时告警。LED 引脚采用老师完赛工程确认的高电平点亮方式。
reg [25:0] led_heartbeat_cnt;
reg        led_heartbeat;
reg        led_audio_present;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        led_heartbeat_cnt <= 26'd0;
        led_heartbeat     <= 1'b0;
        led_audio_present <= 1'b0;
    end else begin
        if (led_heartbeat_cnt >= 26'd49_999_999) begin
            led_heartbeat_cnt <= 26'd0;
            led_heartbeat     <= ~led_heartbeat;
        end else begin
            led_heartbeat_cnt <= led_heartbeat_cnt + 1'b1;
        end
        if (!sd_init_done)
            led_audio_present <= 1'b0;
        else if (wav_scan_done && wav_scan_found)
            led_audio_present <= 1'b1;
    end
end
// 上电和 TF 初始化期间保持四灯全亮，沿用开发板的可见启动反馈；
// 初始化完成后切换为媒体系统状态编码，避免把“未初始化”误报成故障。
wire [3:0] led_state_sd = (!rst_n || !sd_init_done) ? 4'b1111 : {
    emergency_mode_sd | bmp_sd_timeout | wav_sd_timeout,
    led_audio_present,
    display_valid,
    led_heartbeat
};
assign led = led_state_sd;

monitor_menu_ctrl #(.CLK_FREQ_HZ(100_000_000), .DEBOUNCE_MS(20),
                    .LONG_PRESS_MS(1000), .TEST_MS(200)) u_monitor_menu_ctrl(
    .clk(sd_card_clk), .rst(rst_sd),
    .key_next(key1), .key_auto(key2), .key_emergency(key3),
    .emergency_active(emergency_mode_sd),
    .cfg_commit_ack_toggle(cfg_commit_ack_toggle_sd),
    .menu_active(monitor_menu_active_sd), .menu_page(monitor_menu_page_sd),
    .cursor(monitor_cursor_sd), .cfg_shadow(cfg_shadow_sd),
    .cfg_payload(cfg_payload_sd),
    .period_shadow(monitor_period_shadow_sd),
    .period_active(monitor_period_active_sd),
    .screen_page(monitor_screen_page_sd), .screen_edit(monitor_screen_edit_sd),
    .screen_shadow(screen_shadow_sd), .screen_payload(screen_payload_sd),
    .subtitle_page(monitor_subtitle_page_sd), .subtitle_edit(monitor_subtitle_edit_sd),
    .subtitle_shadow(subtitle_shadow_sd), .subtitle_payload(subtitle_payload_sd),
    .cfg_commit_busy(monitor_cfg_busy_sd),
    .cfg_commit_toggle(cfg_commit_toggle_sd), .cfg_dirty(monitor_cfg_dirty_sd),
    .buzzer_test(monitor_buzzer_test_sd),
    .key_state(monitor_key_state_sd),
    .key_next_pulse(monitor_key_next_pulse_sd),
    .key_auto_pulse(monitor_key_auto_pulse_sd),
    .key_event_count(monitor_key_events_sd)
);

// 720p首版固定交叉淡化；KEY4长按仍由emergency_ctrl处理。
wire [1:0] tr_mode_reg=2'd1;
// W5/W4 主通道像素坐标（供转场/OSD）
wire       main_de_al;
wire [10:0] main_x;
wire [9:0] main_y;
wire [31:0] main_fc;
wire       tr_hold_load;    // 转场期间暂缓装载
wire [23:0] vout_osd;       // OSD 输出
wire [23:0] vout_waveform;  // 老师第十二讲：PCM 时域波形图层输出
wire [23:0] vout_color;     // W8: 色彩调节后输出
wire [23:0] vout_final;     // W9: 应急渲染后输出（最终）
wire [3:0]  cfg_active_video;
wire [3:0]  cfg_preview_video;
wire [9:0]  screen_active_video, screen_preview_video;
wire [4:0]  subtitle_active_video, subtitle_preview_video;
// HDMI-B 专用参数；不作用于 HDMI-A 菜单。
wire [7:0] screen_contrast_video = 8'd64 + {screen_active_video[7:4], 4'b0000};
wire signed [7:0] screen_brightness_video = {screen_active_video[3:0], 4'b0000} - 8'd64;
wire signed [7:0] screen_temp_video = (screen_active_video[9:8] == 0) ? -8'sd20 :
                                    (screen_active_video[9:8] == 2) ? 8'sd20 : 8'sd0;
wire        cfg_commit_seen_video;
wire        cfg_applied_toggle_video;
wire        menu_buzzer_test = monitor_buzzer_test_sd;
wire        cfg_image_enable = cfg_active_video[0];
wire        cfg_wave_enable  = cfg_active_video[1];
wire        cfg_clock_enable = cfg_active_video[2];
wire        cfg_text_enable  = cfg_active_video[3];
assign cfg_commit_ack_toggle_sd = cfg_ack_sync_sd[2];

// 其余跨模块状态信号
wire [15:0] sync_dev_real;
wire        audio_valid_final;
wire [23:0] audio_left_final;
wire [23:0] audio_right_final;
// direct writer gate完成事件同属SD域。
// A2: 主通道 OSD 字库同步读引入 1 拍延迟，de/vs 打 1 拍对齐（vs 宽脉冲，±1 拍无影响）
// （监视台的 mon_de_d1/mon_vs_d1 在 mon_de 声明之后的监视台区段）
reg de_d1, vs_d1;
reg de_d2, de_d3, vs_d2, vs_d3;
reg [10:0] x_d1, x_d2, x_d3;
reg [9:0] y_d1, y_d2, y_d3;
// 波形模块的同步查表已经包含一拍，直接交给下一拍字库层。
wire [23:0] waveform_q = vout_waveform;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        de_d1 <= 0; de_d2 <= 0; de_d3 <= 0;
        vs_d1 <= 0; vs_d2 <= 0; vs_d3 <= 0;
        x_d1 <= 0; x_d2 <= 0; x_d3 <= 0;
        y_d1 <= 0; y_d2 <= 0; y_d3 <= 0;
    end else begin
        // 两拍混合器之后：颜色、波形、字库各一拍；RGB/坐标/DE同拍推进。
        de_d1 <= mix_de; de_d2 <= de_d1; de_d3 <= de_d2;
        vs_d1 <= mix_vs; vs_d2 <= vs_d1; vs_d3 <= vs_d2;
        x_d1 <= mix_x; x_d2 <= x_d1; x_d3 <= x_d2;
        y_d1 <= mix_y; y_d2 <= y_d1; y_d3 <= y_d2;
    end
end

// 缩放完成 toggle接口已替换为管理器完整页提交；video域同步事件与稳定页号。
// 只有解析和writer均成功的事务可发布，不能绕过隔离门。
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

// TF/SDRAM时钟沿用基线，视频改为准确74.25MHz级联PLL。
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .extlock    (sys_pll_lock),
    .reset      (~rst_n)
);

// 50→27参考级联：第一PLL锁定后稳定100us，再释放像素PLL。
wire ref27_clk, ref27_lock;
reg [1:0] ref_lock_sync=0;
reg [12:0] ref_stable_count=0;
wire pixel_pll_reset=~rst_n | ~ref27_lock | (ref_stable_count != 13'd5000);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin ref_lock_sync<=0; ref_stable_count<=0; end
    else begin
        ref_lock_sync<={ref_lock_sync[0],ref27_lock};
        if (!ref_lock_sync[1]) ref_stable_count<=0;
        else if (ref_stable_count != 5000) ref_stable_count<=ref_stable_count+1'b1;
    end
end
ref27_pll u_ref27(.refclk(clk),.reset(~rst_n),.clk0_out(ref27_clk),.extlock(ref27_lock));
video_pll video_pll_m0(
    .refclk     (ref27_clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .extlock    (video_pll_lock),
    .reset      (pixel_pll_reset)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// writer完成toggle转SD域单拍，送完整页事务隔离门。
reg [2:0] fw_tgl_sync;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) fw_tgl_sync <= 3'b000;
    else         fw_tgl_sync <= {fw_tgl_sync[1:0], frame_write_toggle_mem};
end
wire frame_write_finish_pulse = fw_tgl_sync[2] ^ fw_tgl_sync[1];

// 源帧完整后启动缩放；管理器只接受目标显示页写完后的事件。
wire scaler_start_tgl;
wire scaler_commit_toggle;
wire resize_busy_mem, resize_error_mem;
reg [1:0] resize_busy_sync_sd;
reg [2:0] resize_error_sync_sd;
reg [1:0] resize_card_ready_mem;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if(rst_sd) begin resize_busy_sync_sd<=0; resize_error_sync_sd<=0; end
    else begin
        resize_busy_sync_sd<={resize_busy_sync_sd[0],resize_busy_mem};
        resize_error_sync_sd<={resize_error_sync_sd[1:0],resize_error_mem};
    end
end
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if(rst_mem) resize_card_ready_mem<=0;
    else resize_card_ready_mem<={resize_card_ready_mem[0],sd_init_done};
end

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

// ===================== TF多图扫描与缓存（最多8张，最大1280×720 BMP24） =====================
wire [31:0] tf_bmp_debug;
wire [191:0] tf_video_snapshot;
wire [7:0] scaler_debug_status=8'd0;
wire [3:0]  img_count;
wire [15:0] cur_img_w, cur_img_h;

// BMP24 → RGB565双像素打包 → 紧凑源图暂存 → 行缓存缩放 → 空闲显示页
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
    .SCAN_TARGET_COUNT (4'd8),
    .MAX_WIDTH(1280), .MAX_HEIGHT(720), .PREFETCH_NEXT(1)
) sd_card_bmp_g_m0(
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .key_next          (key1),
    .key_auto          (key2),
    .key_event_override(1'b1),
    .key_next_event    (monitor_key_next_pulse_sd),
    .key_auto_event    (monitor_key_auto_pulse_sd),
    .auto_period_sel   (monitor_period_active_sd),
    .hold_load         (display_submit_pending_sd | tr_hold_sync_sd[1] | resize_busy_sync_sd[1]),
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

    .write_finish_toggle(scaler_commit_toggle),  // direct writer两端完成后才commit
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (source_write_ack_sync_sd[1]),
    .write_en          (bmp_wr_en),           // W6: 改接 src_packer
    .write_data        (bmp_wr_data),         // W6: 24bit RGB
    .sd_init_done      (sd_init_done),
    .sd_sec_read_abort (bmp_sd_timeout | (resize_error_sync_sd[1] & ~resize_error_sync_sd[2])),
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
video_timing_gen #(
    .HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
    .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.X_BITS(11),.Y_BITS(10)
) u_timing_720(.I_clk(video_clk),.I_rst(rst_video),.O_hs(hs_0),.O_vs(vs_0),.O_de(de_0),.O_x(),.O_y());

assign hs = hs_0;
assign vs = vs_0;
assign de = de_0;

reg vs_d_v;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) vs_d_v <= 1'b0;
    else         vs_d_v <= vs;
end
wire vs_rise_v = vs & ~vs_d_v;

monitor_config_regs u_monitor_config_regs(
    .video_clk              (video_clk),
    .video_rst              (rst_video),
    .vs_rise                (vs_rise_v),
    .cfg_shadow_sd          (cfg_shadow_sd),
    .cfg_payload_sd         (cfg_payload_sd),
    .screen_shadow_sd       (screen_shadow_sd),
    .screen_payload_sd      (screen_payload_sd),
    .subtitle_shadow_sd     (subtitle_shadow_sd),
    .subtitle_payload_sd    (subtitle_payload_sd),
    .cfg_commit_toggle_sd   (cfg_commit_toggle_sd),
    .cfg_active_video       (cfg_active_video),
    .cfg_preview_video      (cfg_preview_video),
    .screen_active_video    (screen_active_video),
    .screen_preview_video   (screen_preview_video),
    .subtitle_active_video  (subtitle_active_video),
    .subtitle_preview_video (subtitle_preview_video),
    .cfg_commit_seen_video  (cfg_commit_seen_video),
    .cfg_applied_toggle_video(cfg_applied_toggle_video)
);

always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd)
        cfg_ack_sync_sd <= 3'b000;
    else
        cfg_ack_sync_sd <= {cfg_ack_sync_sd[1:0], cfg_applied_toggle_video};
end

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
    .SLIDE_STEP (10'd16), .X_BITS(11), .Y_BITS(10)
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
// 源写入与缩放写入互斥，C口在源帧完成后读取暂存区。
wire source_write_busy, memory_read_busy, memory_write_ready;
wire resize_cmd_valid, resize_cmd_ready, resize_rsp_valid, resize_rsp_last;
wire [20:0] resize_cmd_addr, resize_wr_addr;
wire [7:0] resize_cmd_len;
wire [31:0] resize_rsp_data, resize_wr_data;
wire resize_write_request, resize_wr_en;
wire sdram_wr_en;
wire [20:0] sdram_wr_addr;
wire [31:0] sdram_wr_din;
wire [3:0] sdram_wr_dm;

mem_mpu #(.MAX_A_RUN(8), .MAX_B_RUN(8), .MAX_C_RUN(4)) u_mem_mpu(
    .clk            (ext_mem_clk),
    .rst            (rst_mem),
    .A_cmd_valid    (mpu_A_cv), .A_cmd_addr(mpu_A_ca), .A_cmd_len(mpu_A_cl),
    .A_cmd_ready    (mpu_A_cr), .A_rsp_valid(mpu_A_rv), .A_rsp_data(mpu_A_rd), .A_rsp_last(mpu_A_rl),
    .B_cmd_valid    (mpu_B_cv), .B_cmd_addr(mpu_B_ca), .B_cmd_len(mpu_B_cl),
    .B_cmd_ready    (mpu_B_cr), .B_rsp_valid(mpu_B_rv), .B_rsp_data(mpu_B_rd), .B_rsp_last(mpu_B_rl),
    .C_cmd_valid    (resize_cmd_valid), .C_cmd_addr(resize_cmd_addr), .C_cmd_len(resize_cmd_len),
    .C_cmd_ready    (resize_cmd_ready), .C_rsp_valid(resize_rsp_valid), .C_rsp_data(resize_rsp_data), .C_rsp_last(resize_rsp_last),
    .App_rd_en      (App_rd_en),
    .App_rd_addr    (App_rd_addr),
    .Sdr_rd_en      (Sdr_rd_en),
    .Sdr_rd_dout    (Sdr_rd_dout),
    .Sdr_init_done  (Sdr_init_done),
    .Sdr_busy       (Sdr_busy),
    .source_write_busy(source_write_busy),
    .scaler_write_request(resize_write_request),
    .read_busy      (memory_read_busy),
    .write_ready    (memory_write_ready),
    .App_wr_en_u    (App_wr_en),
    .App_wr_addr_u  (App_wr_addr),
    .App_wr_din_u   (App_wr_din),
    .App_wr_dm_u    (App_wr_dm),
    .App_wr2_en_u   (resize_wr_en),
    .App_wr2_addr_u (resize_wr_addr),
    .App_wr2_din_u  (resize_wr_data),
    .App_wr2_dm_u   (4'h0),
    .wr2_active     (resize_busy_mem),
    .App_wr_en      (sdram_wr_en),
    .App_wr_addr    (sdram_wr_addr),
    .App_wr_din     (sdram_wr_din),
    .App_wr_dm      (sdram_wr_dm)
);

// ---- RGB565双页预取与两拍混合流水 ----
wire [23:0] mix_rgb;
wire mix_de,mix_vs;
wire [10:0] mix_x;
wire [9:0] mix_y;
wire [31:0] disp_underflow;
display_stream_720 u_display_stream(
    .mem_clk(ext_mem_clk),.mem_rst(rst_mem),.video_clk(video_clk),.video_rst(rst_video),
    .vs_toggle(vs_toggle_r),.de_in(main_de_al),.vs_in(vs),.x(main_x),.y(main_y),
    .tr_active(tr_active),.alpha(tr_alpha),.page_a_base(page_a_base),.page_b_base(page_b_base),
    .a_cmd_valid(mpu_A_cv),.a_cmd_addr(mpu_A_ca),.a_cmd_len(mpu_A_cl),.a_cmd_ready(mpu_A_cr),
    .a_rsp_valid(mpu_A_rv),.a_rsp_data(mpu_A_rd),.a_rsp_last(mpu_A_rl),
    .b_cmd_valid(mpu_B_cv),.b_cmd_addr(mpu_B_ca),.b_cmd_len(mpu_B_cl),.b_cmd_ready(mpu_B_cr),
    .b_rsp_valid(mpu_B_rv),.b_rsp_data(mpu_B_rd),.b_rsp_last(mpu_B_rl),
    .rgb_out(mix_rgb),.de_out(mix_de),.vs_out(mix_vs),.x_out(mix_x),.y_out(mix_y),
    .underflow_cnt(disp_underflow)
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

// 仅源解析和源writer均完成后启动缩放，失败事务不会进入目标页。
source_scaler_gate u_source_scaler_gate (
    .clk(sd_card_clk), .rst(rst_sd), .sd_init_done(sd_init_done),
    .source_restart(bmp_source_restart), .source_done(bmp_load_done),
    .write_req(sd_card_write_req), .write_req_ack(sd_card_write_req_ack),
    .frame_write_finish_pulse(frame_write_finish_pulse),
    .scaler_start_toggle(scaler_start_tgl), .scaler_start_pulse()
);

// ---- 多尺寸缩放桥：输入参数在源帧装载期间即稳定，保持至目标页完成 ----
resize_frame_720 u_resize_frame(
    .clk(ext_mem_clk), .rst(rst_mem), .cancel(~resize_card_ready_mem[1]),
    .start_toggle(scaler_start_tgl), .cfg_w(bmp_load_img_w[10:0]), .cfg_h(bmp_load_img_h[10:0]),
    .cfg_src_base(21'h100000), .cfg_dst_base(write_buf_idx[0] ? BUF1_ADDR : BUF0_ADDR),
    .cmd_valid(resize_cmd_valid), .cmd_addr(resize_cmd_addr), .cmd_len(resize_cmd_len),
    .cmd_ready(resize_cmd_ready), .rsp_valid(resize_rsp_valid), .rsp_last(resize_rsp_last), .rsp_data(resize_rsp_data),
    .write_request(resize_write_request), .write_ready(memory_write_ready),
    .wr_en(resize_wr_en), .wr_addr(resize_wr_addr), .wr_data(resize_wr_data),
    .busy(resize_busy_mem), .done_toggle(scaler_commit_toggle), .error(resize_error_mem)
);

// ---- RGB565紧凑源图写入；垂直方向在缩放读源行时转换 ----
wire video_read_en_unused;
wire [31:0] video_read_data_unused;
// 解析器已检查宽<=1280、高<=720；收窄乘法输入，避免为未支持的16bit尺寸保留DSP。
wire [9:0] source_row_words = ({1'b0,bmp_load_img_w[10:0]}+12'd1)>>1;
wire [20:0] source_frame_words = source_row_words*bmp_load_img_h[9:0];

// 先写完整紧凑源图，不能用固定460800字等待640素材的后续像素。
frame_read_write #(
    .WRITE_V_FLIP     (0),
    .EXTERNAL_READ    (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (720)
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
    // 显示双页以外的源图暂存区，最大源图末地址0x1707ff < 0x200000。
    .write_addr_0      (21'h100000),
    .write_addr_1      (21'h100000),
    .write_addr_2      (21'd0),
    .write_addr_3      (21'd0),
    .write_addr_index  (2'd0),
    .write_len         (source_frame_words),
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

audio_player #(.VIDEO_CLK_HZ(74_250_000),.NOMINAL_SAMPLES_PER_FRAME(800)) u_audio_player(
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
video_rgb_to_axis_640x480 #(.ACTIVE_WIDTH(1280)) u_video_rgb_to_axis_640x480(
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
    .HTOTAL(1650),
    .HSA(40),
    .HFP(110),
    .HBP(220),
    .HACTIVE(1280),
    .VTOTAL(750),
    .VSA(5),
    .VFP(5),
    .VBP(20),
    .VACTIVE(720),
    .VIDEO_VIC(4),
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
// 运行计时采用准确像素时钟分频，不依赖首个VS或帧计数相位。
reg [26:0] second_div;
reg [31:0] uptime_sec;
wire sec_tick=(second_div==27'd74249999);
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin second_div<=0; uptime_sec<=0; end
    else if (sec_tick) begin second_div<=0; uptime_sec<=uptime_sec+1'b1; end
    else second_div<=second_div+1'b1;
end

// W10: 接入真实同步偏差与模式（已在顶部前向声明）
wire [1:0]  mode_v1 = emergency_mode ? 2'd2 : 2'd1;  // 0:启动 1:广告 2:应急

// OSD 实时时钟（BCD）：HH/MM/SS 级联进位
reg [7:0] clk_ss, clk_mm, clk_hh;   // 各两位 BCD
// sec_tick由准确时钟分频提供。
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
pixel_pos_gen #(.X_BITS(11),.Y_BITS(10)) u_main_pos(
    .I_clk       (video_clk),
    .I_rst       (rst_video),
    .I_vs        (vs),
    .I_de        (de),
    .O_de        (main_de_al),
    .O_x         (main_x),
    .O_y         (main_y),
    .O_frame_cnt (main_fc)
);

osd_engine_720 u_osd(
    .I_clk        (video_clk),
    .I_rst        (rst_video),
    .I_vs_pulse   (vs_rise_v),
    .I_subtitle_cfg(subtitle_active_video),
    .I_x          (x_d2),
    .I_y          (y_d2),
    .I_bg_rgb     (waveform_q),
    .I_uptime_bcd ({clk_hh, clk_mm, clk_ss}),
    .I_mode       (mode_v1),
    .I_clock_enable(cfg_clock_enable),
    .I_text_enable (cfg_text_enable),
    .O_rgb        (vout_osd)
);

// ===================== 老师第十二讲：PCM 时域波形 =====================
// 每 120 个 PCM 样本抽取一个，32 点覆盖约 80 ms 音频；采集可跨帧继续，
// 只在 VS 边界发布完整采样组，并逐帧平滑、消隐期预计算曲线。
promax_audio_waveform #(
    .WAVE_X(128),.WAVE_Y(576),.WAVE_WIDTH(1024),.WAVE_HEIGHT(96),.DECIMATE(120),
    .VIDEO_WIDTH(1280),.VIDEO_HEIGHT(720),.X_BITS(11),.Y_BITS(10),.PIPELINED_GEOMETRY(1)
) u_promax_audio_waveform(
    .clk           (video_clk),
    .rst           (rst_video),
    .vs_pulse      (vs_rise_v),
    .de            (de_d1),
    .pixel_x       (x_d1),
    .pixel_y       (y_d1),
    .rgb_in        (vout_color),
    .enable        (cfg_wave_enable !== 1'b0),
    .pcm_tap_valid (waveform_pcm_valid),
    .pcm_tap_left  (audio_left_final[23:8]),
    .rgb_out       (vout_waveform),
    .waveform_active()
);

// HDMI-B 图片色彩调节：菜单确认后帧边界生效，SW2-4 不再覆盖菜单。
color_adjust u_color_adjust(
    .clk        (video_clk),
    .rst        (rst_video),
    .de_in      (mix_de),
    .rgb_in     ((cfg_image_enable !== 1'b0) ? vout_data : 24'h07131D),
    .contrast   (screen_contrast_video),
    .brightness (screen_brightness_video),
    .color_temp (screen_temp_video),
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

assign buzzer = ~(buzzer_drv | (monitor_buzzer_test_sd & ~emergency_mode_sd));  // 低有效，应急优先

// emergency_render: 应急模式下替换视频输出
emergency_render #(.X_BITS(11),.Y_BITS(10)) u_emergency_render(
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

// ===================== HDMI-A 640x480 监视与控制台 =====================
// 控制域状态均以稳定电平跨入视频域；配置正文由 monitor_config_regs
// 在视频帧边界提交，避免多位组合总线在像素路径中产生撕裂。
reg [1:0]  mon_menu_active_sync, mon_menu_page_sync;
reg [1:0]  mon_screen_page_sync, mon_screen_edit_sync, mon_cfg_busy_sync;
reg [1:0]  mon_subtitle_page_sync, mon_subtitle_edit_sync;
reg [2:0]  mon_cursor_sync0, mon_cursor_sync1;
reg [1:0]  mon_period_shadow_sync0, mon_period_shadow_sync1;
reg [1:0]  mon_period_active_sync0, mon_period_active_sync1;
reg [1:0]  mon_dirty_sync, mon_buzzer_sync, mon_sd_init_sync;
reg [2:0]  mon_key_state_sync0, mon_key_state_sync1;
reg [15:0] mon_key_events_sync0, mon_key_events_sync1;
reg [3:0]  mon_img_count_sync0, mon_img_count_sync1;
reg [3:0]  mon_led_state_sync0, mon_led_state_sync1;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        mon_menu_active_sync <= 2'b00;
        mon_menu_page_sync   <= 2'b00;
        mon_screen_page_sync <= 2'b00;
        mon_screen_edit_sync <= 2'b00;
        mon_subtitle_page_sync <= 2'b00;
        mon_subtitle_edit_sync <= 2'b00;
        mon_cfg_busy_sync <= 2'b00;
        mon_cursor_sync0     <= 3'b000;
        mon_cursor_sync1     <= 3'b000;
        mon_period_shadow_sync0 <= 2'd0;
        mon_period_shadow_sync1 <= 2'd0;
        mon_period_active_sync0 <= 2'd0;
        mon_period_active_sync1 <= 2'd0;
        mon_dirty_sync       <= 2'b00;
        mon_buzzer_sync      <= 2'b00;
        mon_sd_init_sync     <= 2'b00;
        mon_key_state_sync0  <= 3'b000;
        mon_key_state_sync1  <= 3'b000;
        mon_key_events_sync0<= 16'd0;
        mon_key_events_sync1<= 16'd0;
        mon_img_count_sync0 <= 4'd0;
        mon_img_count_sync1 <= 4'd0;
        mon_led_state_sync0 <= 4'd0;
        mon_led_state_sync1 <= 4'd0;
    end else begin
        mon_menu_active_sync <= {mon_menu_active_sync[0], monitor_menu_active_sd};
        mon_menu_page_sync   <= {mon_menu_page_sync[0], monitor_menu_page_sd};
        mon_screen_page_sync <= {mon_screen_page_sync[0], monitor_screen_page_sd};
        mon_screen_edit_sync <= {mon_screen_edit_sync[0], monitor_screen_edit_sd};
        mon_subtitle_page_sync <= {mon_subtitle_page_sync[0], monitor_subtitle_page_sd};
        mon_subtitle_edit_sync <= {mon_subtitle_edit_sync[0], monitor_subtitle_edit_sd};
        mon_cfg_busy_sync <= {mon_cfg_busy_sync[0], monitor_cfg_busy_sd};
        mon_cursor_sync0     <= monitor_cursor_sd;
        mon_cursor_sync1     <= mon_cursor_sync0;
        mon_period_shadow_sync0 <= monitor_period_shadow_sd;
        mon_period_shadow_sync1 <= mon_period_shadow_sync0;
        mon_period_active_sync0 <= monitor_period_active_sd;
        mon_period_active_sync1 <= mon_period_active_sync0;
        mon_dirty_sync       <= {mon_dirty_sync[0], monitor_cfg_dirty_sd};
        mon_buzzer_sync      <= {mon_buzzer_sync[0], monitor_buzzer_test_sd};
        mon_sd_init_sync     <= {mon_sd_init_sync[0], sd_init_done};
        mon_key_state_sync0  <= monitor_key_state_sd;
        mon_key_state_sync1  <= mon_key_state_sync0;
        mon_key_events_sync0<= monitor_key_events_sd;
        mon_key_events_sync1<= mon_key_events_sync0;
        mon_img_count_sync0 <= img_count;
        mon_img_count_sync1 <= mon_img_count_sync0;
        mon_led_state_sync0 <= led_state_sd;
        mon_led_state_sync1 <= mon_led_state_sync0;
    end
end

wire mon_hs, mon_vs, mon_de;
wire [10:0] mon_x_full;
wire [9:0] mon_y_full;
reg [9:0] mon_x;
reg [8:0] mon_y;
reg mon_de_view_q;
// HDMI-A 对外使用标准 1280x720@60Hz 时序，监视画布按 4:3 比例放大到
// 960x720 并水平居中。原 640x480 渲染器只接收缩放后的逻辑坐标，左右
// 各 160 像素为黑边，避免 7 寸屏上的文字过小或画面变形。
wire mon_de_view = mon_de && (mon_x_full >= 11'd160) &&
                   (mon_x_full < 11'd1120);
wire [10:0] mon_x_rel = (mon_x_full >= 11'd160) ?
                        (mon_x_full - 11'd160) : 11'd0;
wire [11:0] mon_x_num = {1'b0, mon_x_rel} << 1;
wire [10:0] mon_x_logical = (mon_x_num / 12'd3);
wire [10:0] mon_y_num = {1'b0, mon_y_full} << 1;
wire [10:0] mon_y_logical = (mon_y_num / 11'd3);
wire [23:0] mon_menu_rgb;
reg [23:0] mon_rgb;
wire mon_menu_active_v = mon_menu_active_sync[1];
wire mon_menu_page_v   = mon_menu_page_sync[1];
wire [2:0] mon_cursor_v = mon_cursor_sync1;
wire [1:0] mon_period_shadow_v = mon_period_shadow_sync1;
wire [1:0] mon_period_active_v = mon_period_active_sync1;
wire mon_cfg_dirty_v = mon_dirty_sync[1];
wire mon_buzzer_test_v = mon_buzzer_sync[1];
wire mon_sd_init_v = mon_sd_init_sync[1];
wire [2:0] mon_key_state_v = mon_key_state_sync1;
wire [15:0] mon_key_events_v = mon_key_events_sync1;
wire [3:0] mon_img_count_v = mon_img_count_sync1;
wire [3:0] mon_led_state_v = mon_led_state_sync1;
reg mon_hs_d1, mon_de_d1, mon_vs_d1;
reg mon_hs_d2, mon_de_d2, mon_vs_d2;
reg mon_hs_d3, mon_de_d3, mon_vs_d3;

video_timing_gen #(
    .HTOTAL(1650), .HSA(40), .HFP(110), .HBP(220), .HACTIVE(1280),
    .VTOTAL(750), .VSA(5), .VFP(5), .VBP(20), .VACTIVE(720),
    .X_BITS(11), .Y_BITS(10)
) u_mon_timing_gen(
    .I_clk(video_clk), .I_rst(rst_video),
    .O_hs(mon_hs), .O_vs(mon_vs), .O_de(mon_de),
    .O_x(mon_x_full), .O_y(mon_y_full)
);

// 坐标缩放与字符选择分拍，避免除3/卡片译码/字库地址串成一条视频组合长路径。
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) begin mon_x<=0; mon_y<=0; mon_de_view_q<=0; end
    else begin
        mon_x<=mon_x_logical[9:0]; mon_y<=mon_y_logical[8:0]; mon_de_view_q<=mon_de_view;
    end
end

monitor_menu_renderer u_mon_menu_renderer(
    .clk(video_clk), .de(mon_de_view_q), .x(mon_x), .y(mon_y),
    .menu_active(mon_menu_active_v),
    .page(mon_menu_page_v), .cursor(mon_cursor_v),
    .screen_page(mon_screen_page_sync[1]), .screen_edit(mon_screen_edit_sync[1]),
    .screen_shadow(screen_preview_video), .screen_active(screen_active_video),
    .subtitle_page(mon_subtitle_page_sync[1]), .subtitle_edit(mon_subtitle_edit_sync[1]),
    .subtitle_shadow(subtitle_preview_video), .subtitle_active(subtitle_active_video),
    .cfg_busy(mon_cfg_busy_sync[1]),
    .cfg_shadow(cfg_preview_video), .cfg_active(cfg_active_video),
    .period_shadow(mon_period_shadow_v), .period_active(mon_period_active_v),
    .cfg_dirty(mon_cfg_dirty_v), .commit_seen(cfg_commit_seen_video),
    .buzzer_test(mon_buzzer_test_v), .key_state(mon_key_state_v),
    .key_events(mon_key_events_v), .sd_init_done(mon_sd_init_v),
    .img_count(mon_img_count_v), .led_state(mon_led_state_v),
    .rgb(mon_menu_rgb)
);

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        mon_hs_d1 <= 1'b0;
        mon_de_d1 <= 1'b0;
        mon_vs_d1 <= 1'b0;
        mon_hs_d2 <= 1'b0;
        mon_de_d2 <= 1'b0;
        mon_vs_d2 <= 1'b0;
        mon_hs_d3 <= 1'b0;
        mon_de_d3 <= 1'b0;
        mon_vs_d3 <= 1'b0;
        mon_rgb <= 24'd0;
    end else begin
        mon_hs_d1 <= mon_hs;
        mon_de_d1 <= mon_de;
        mon_vs_d1 <= mon_vs;
        mon_hs_d2 <= mon_hs_d1;
        mon_de_d2 <= mon_de_d1;
        mon_vs_d2 <= mon_vs_d1;
        mon_hs_d3 <= mon_hs_d2;
        mon_de_d3 <= mon_de_d2;
        mon_vs_d3 <= mon_vs_d2;
        // 隔离菜单组合绘图和 TMDS 统计/直流平衡链，同步信号同样延迟一拍。
        mon_rgb <= mon_menu_rgb;
    end
end
// 播放按键模式继续显示卡片和操作提示，不再恢复旧参数页。

// HDMI-A is intentionally DVI-compatible video-only.  Its DDC pins remain
// idle because the monitor page has fixed timing and carries no audio.
assign HDMI_A_DDC_SCL = 1'b1;
assign HDMI_A_DDC_SDA = 1'bz;

hdmi_video_only_640x480 u_hdmi_video_mon(
    .clk(video_clk), .rst_n(~rst_video),
    .hsync(mon_hs_d3), .vsync(mon_vs_d3), .de(mon_de_d3), .rgb(mon_rgb),
    .ch0_symbol(mon_tmds_ch0), .ch1_symbol(mon_tmds_ch1),
    .ch2_symbol(mon_tmds_ch2), .clk_symbol(mon_tmds_clk)
);
hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy_mon(
    .I_pixel_clk(video_clk), .I_serial_clk(hdmi_5x_clk), .I_rst(rst_video),
    .I_tmds_channel_0(mon_tmds_ch0), .I_tmds_channel_1(mon_tmds_ch1),
    .I_tmds_channel_2(mon_tmds_ch2), .I_tmds_channel_clk(mon_tmds_clk),
    .O_tmds_ch0_p(HDMI_A_D0_P), .O_tmds_ch1_p(HDMI_A_D1_P),
    .O_tmds_ch2_p(HDMI_A_D2_P), .O_tmds_clk_p(HDMI_A_CLK_P)
);

endmodule
