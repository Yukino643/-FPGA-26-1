from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[4]
p=ROOT/'rtl/top/top_tf_hdmi_audio.v'
t=p.read_bytes().decode('utf-8-sig').replace('\r\n','\n')
def replace(old,new):
    global t
    if old not in t: raise RuntimeError(f'missing {old[:70]}')
    t=t.replace(old,new)
def section(first,last,content):
    global t
    a=t.index(first); b=t.index(last,a)
    t=t[:a]+content+'\n'+t[b:]

replace("parameter FRAME_PIXELS  = 21'd307200;", "parameter FRAME_PIXELS  = 21'd460800;")
replace('// 640*480，SDRAM 字地址', '// 1280*720/2，RGB565双像素字')
section('// W10: 物理 KEY4 短按', '// W5/W4 主通道', "// 720p首版固定交叉淡化；KEY4长按仍由emergency_ctrl处理。\nwire [1:0] tr_mode_reg=2'd1;")
replace('wire [9:0] main_x;', 'wire [10:0] main_x;')
replace('wire [8:0] main_y;', 'wire [9:0] main_y;')
replace('reg [9:0] x_d1, x_d2, x_d3;', 'reg [10:0] x_d1, x_d2, x_d3;')
replace('reg [8:0] y_d1, y_d2, y_d3;', 'reg [9:0] y_d1, y_d2, y_d3;')
replace('de_d1 <= main_de_al;', 'de_d1 <= mix_de;')
replace('vs_d1 <= vs;', 'vs_d1 <= mix_vs;')
replace('x_d1 <= main_x;', 'x_d1 <= mix_x;')
replace('y_d1 <= main_y;', 'y_d1 <= mix_y;')
replace('wire        scaler_done_toggle;', '// direct writer gate完成事件同属SD域。')
section('// W6: scaler 完成 toggle', '// 显示提交握手', '''// direct writer必须解析成功且写完成，并经过新请求ACK隔离门。
wire scaler_start_tgl;
wire scaler_commit_toggle=scaler_start_tgl;
''')
replace('.refclk     (clk),\n    .clk0_out   (video_clk)', '.refclk     (ref27_clk),\n    .clk0_out   (video_clk)')
replace('video_pll video_pll_m0(', '''// 50→27参考级联：第一PLL锁定后稳定100us，再释放像素PLL。
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
video_pll video_pll_m0(''')
start=t.index('video_pll video_pll_m0(');end=t.index('\n);',start)
t=t[:start]+t[start:end].replace('.reset      (~rst_n)', '.reset      (pixel_pll_reset)')+t[end:]
section('wire [3:0]  scaler_debug_state;', 'wire [3:0]  img_count;', "wire [7:0] scaler_debug_status=8'd0;")
replace(".SCAN_TARGET_COUNT (4'd8)", ".SCAN_TARGET_COUNT (4'd8),\n    .EXACT_WIDTH(1280), .EXACT_HEIGHT(720)")
section('video_timing_data video_timing_data_m0(', 'assign hs = hs_0;', '''video_timing_gen #(
    .HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
    .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.X_BITS(11),.Y_BITS(10)
) u_timing_720(.I_clk(video_clk),.I_rst(rst_video),.O_hs(hs_0),.O_vs(vs_0),.O_de(de_0),.O_x(),.O_y());
''')
replace('.SLIDE_STEP (10\'d16)', ".SLIDE_STEP (10'd16), .X_BITS(11), .Y_BITS(10)")
section('// W6: C 口', 'mem_mpu #(', '''// 720p直接写空闲显示页；C和第二写口关闭。
wire source_write_busy, memory_read_busy, memory_write_ready;
wire sdram_wr_en;
wire [20:0] sdram_wr_addr;
wire [31:0] sdram_wr_din;
wire [3:0] sdram_wr_dm;
''')
for old,new in [('mpu_C_cv',"1'b0"),('mpu_C_ca',"21'd0"),('mpu_C_cl',"8'd1"),
                ('mpu_C_cr',''),('mpu_C_rv',''),('mpu_C_rd',''),('mpu_C_rl',''),
                ('scaler_write_request',"1'b0"),('scaler_wr_en',"1'b0"),('scaler_wr_addr',"21'd0"),
                ('scaler_wr_din',"32'd0"),('scaler_busy',"1'b0")]:
    # 限于实例端口，禁止改动端口名。
    t=t.replace('('+old+')','('+new+')')
section('// ---- 双行预取引擎', '// 首图提交前黑屏', '''// ---- RGB565双页预取与两拍混合流水 ----
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
''')
section('// ===================== W6: 缩放引擎', '// ---- W6: 装载写路径', '''// 完整页发布隔离门沿用已验证的事务契约；不再启动scaler。
source_scaler_gate u_source_scaler_gate (
    .clk(sd_card_clk), .rst(rst_sd), .sd_init_done(sd_init_done),
    .source_restart(bmp_source_restart), .source_done(bmp_load_done),
    .write_req(sd_card_write_req), .write_req_ack(sd_card_write_req_ack),
    .frame_write_finish_pulse(frame_write_finish_pulse),
    .scaler_start_toggle(scaler_start_tgl), .scaler_start_pulse()
);
''')
replace('.WRITE_V_FLIP     (0)', '.WRITE_V_FLIP     (1)')
replace('.FRAME_WIDTH      (320)', '.FRAME_WIDTH      (640)')
replace('.FRAME_HEIGHT     (480)', '.FRAME_HEIGHT     (720)')
replace('.write_addr_0      (21\'hC_B000)', '.write_addr_0      (BUF0_ADDR)')
replace('.write_addr_1      (21\'hC_B000)', '.write_addr_1      (BUF1_ADDR)')
replace('.write_addr_2      (21\'hC_B000)', ".write_addr_2      (21'd0)")
replace('.write_addr_3      (21\'hC_B000)', ".write_addr_3      (21'd0)")
replace('.write_addr_index  (2\'d0)', '.write_addr_index  (write_buf_idx)')
replace('.write_len         (src_write_len)', '.write_len         (FRAME_PIXELS)')
section('// SRC_BUF 写入长度', 'frame_read_write #(', '// 两像素/字，640字×720行；写地址反转抵消BMP底向上行序。')
replace('audio_player u_audio_player(', 'audio_player #(.VIDEO_CLK_HZ(74_250_000),.NOMINAL_SAMPLES_PER_FRAME(800)) u_audio_player(')
replace('video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(', 'video_rgb_to_axis_640x480 #(.ACTIVE_WIDTH(1280)) u_video_rgb_to_axis_640x480(')
for name,old,new in [('HTOTAL',800,1650),('HSA',96,40),('HFP',16,110),('HBP',48,220),('HACTIVE',640,1280),
                     ('VTOTAL',525,750),('VSA',2,5),('VFP',10,5),('VBP',33,20),('VACTIVE',480,720),('VIDEO_VIC',1,4)]:
    t=re.sub(r'\.'+name+r'\s*\(\s*'+str(old)+r'\s*\)',f'.{name}({new})',t)
section('// 运行状态计数', '// W10: 接入真实同步偏差', '''// 运行计时采用准确像素时钟分频，不依赖首个VS或帧计数相位。
reg [26:0] second_div;
reg [31:0] uptime_sec;
wire sec_tick=(second_div==27'd74249999);
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin second_div<=0; uptime_sec<=0; end
    else if (sec_tick) begin second_div<=0; uptime_sec<=uptime_sec+1'b1; end
    else second_div<=second_div+1'b1;
end
''')
replace("wire      sec_tick = vs_edge && (sec_frames == 6'd0);", '// sec_tick由准确时钟分频提供。')
replace('pixel_pos_gen u_main_pos(', 'pixel_pos_gen #(.X_BITS(11),.Y_BITS(10)) u_main_pos(')
replace('osd_engine u_osd(', 'osd_engine_720 u_osd(')
replace('.WAVE_X      (64), .WAVE_Y(376), .WAVE_WIDTH(512), .WAVE_HEIGHT(72), .DECIMATE(120)',
        '.WAVE_X(128),.WAVE_Y(576),.WAVE_WIDTH(1024),.WAVE_HEIGHT(96),.DECIMATE(120),\n    .VIDEO_WIDTH(1280),.VIDEO_HEIGHT(720),.X_BITS(11),.Y_BITS(10)')
replace('.de_in      (main_de_al)', '.de_in      (mix_de)')
replace('emergency_render u_emergency_render(', 'emergency_render #(.X_BITS(11),.Y_BITS(10)) u_emergency_render(')
section('wire mon_hs, mon_vs, mon_de;', 'endmodule', '''// 首版720p仅HDMI-B；A端口处于确定的闲置状态。
assign HDMI_A_CLK_P=1'b0;
assign HDMI_A_D2_P=1'b0;
assign HDMI_A_D1_P=1'b0;
assign HDMI_A_D0_P=1'b0;
assign HDMI_A_DDC_SCL=1'b1;
assign HDMI_A_DDC_SDA=1'bz;
''')
# 修正旧链路注释，避免把direct writer误读成仍经过scaler。
t=t.replace('W6: scaler 完成后才 commit', 'direct writer两端完成后才commit')
t=t.replace('W6: 写入 SRC_BUF（固定地址，不交替）','RGB565直接写本次空闲显示页')
t=t.replace('源缓存按 BMP 文件顺序线性写入；scaler 按动态 row_words 负责垂直方向转换。','按640字/行翻转垂直地址；解析器已经拒绝非1280×720素材。')
p.write_bytes(t.encode('utf-8'))

al=ROOT/'td_prj/av_media.al'
a=al.read_bytes().decode('utf-8-sig')
for name in ('pll/ref27_pll.v','video/display_stream_720.v','video/disp_mixer_565.v',
             'video/osd_engine_720.v','video/osd_text_720.v','video/font_rom_720.v'):
    entry=f'''            <File Path="../rtl/{name}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                </FileInfo>
            </File>
'''
    if name not in a: a=a.replace('        </Verilog>',entry+'        </Verilog>')
al.write_bytes(a.replace('\r\n','\n').encode('utf-8'))
print('Connected 720p top; project sources updated')
