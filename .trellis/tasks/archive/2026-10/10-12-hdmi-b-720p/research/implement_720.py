from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]
def edit(name, changes):
    p = ROOT / name
    text = p.read_bytes().decode('utf-8-sig').replace('\r\n', '\n')
    for old, new in changes:
        if new in text:
            continue
        if old not in text:
            raise RuntimeError(f'{name}: missing replacement {old[:70]}')
        text = text.replace(old, new)
    p.write_bytes(text.replace('\r\n', '\n').encode('utf-8'))

# 原640模块仍保留回归覆盖；其顶层连接明确保存为legacy fixture。
original = subprocess.check_output(['git', 'show', '4e35e9e:rtl/top/top_tf_hdmi_audio.v'], cwd=ROOT).decode('utf-8')
fixture = ROOT / 'sim/fixtures'
fixture.mkdir(exist_ok=True)
(fixture / 'top_640_baseline.v.txt').write_text(original, encoding='utf-8', newline='\n')

edit('rtl/mem/disp_read_engine.v', [
    ('parameter ENABLE_SCROLL = 0', 'parameter ENABLE_SCROLL = 0,\n    parameter FIFO_USED_BITS = 10,\n    parameter GATE_ENABLE = 0'),
    ('input  wire [9:0]               scroll_x,', 'input  wire [9:0]               scroll_x,\n    input  wire                     frame_enable,'),
    ('input  wire [9:0]               fifo_wusedw', 'input  wire [FIFO_USED_BITS-1:0] fifo_wusedw'),
    ('reg                 frame_act;', 'reg                 frame_act;\n    reg [1:0] enable_sync;'),
    ("vs_sync    <= 3'b000;", "vs_sync    <= 3'b000;\n            enable_sync <= 0;"),
    ('vs_sync <= {vs_sync[1:0], vs_toggle};', 'vs_sync <= {vs_sync[1:0], vs_toggle};\n            enable_sync <= {enable_sync[0], frame_enable};'),
    ("frame_act <= 1'b1;", "// 只在帧边界采纳使能；已有突发必须完整收尾。\n                frame_act <= !GATE_ENABLE || enable_sync[1];"),
])
edit('rtl/video/video_timing_gen.v', [
    ('parameter integer VACTIVE = 480', 'parameter integer VACTIVE = 480,\n    parameter integer X_BITS = 10,\n    parameter integer Y_BITS = 9'),
    ('[9:0]  O_x', '[X_BITS-1:0] O_x'), ('[8:0]  O_y', '[Y_BITS-1:0] O_y'),
    ('S_xc[9:0]', 'S_xc[X_BITS-1:0]'), ('S_yc[8:0]', 'S_yc[Y_BITS-1:0]'),
])
edit('rtl/video/pixel_pos_gen.v', [
    ('module pixel_pos_gen(', 'module pixel_pos_gen #(parameter X_BITS=10, parameter Y_BITS=9)('),
    ('[9:0]  O_x', '[X_BITS-1:0] O_x'), ('[8:0]  O_y', '[Y_BITS-1:0] O_y'),
    ('line_cnt[8:0]', 'line_cnt[Y_BITS-1:0]'),
])
edit('rtl/video/video_rgb_to_axis_640x480.v', [
    ('module video_rgb_to_axis_640x480(', 'module video_rgb_to_axis_640x480 #(parameter ACTIVE_WIDTH=640)('),
    ("S_x_cnt == 11'd638", 'S_x_cnt == ACTIVE_WIDTH-2'),
])
edit('rtl/video/transition_ctrl.v', [
    ("parameter [9:0] SLIDE_STEP = 10'd16", "parameter [9:0] SLIDE_STEP = 10'd16,\n    parameter X_BITS=10, Y_BITS=9"),
    ('[9:0] x,', '[X_BITS-1:0] x,'), ('[8:0] y,', '[Y_BITS-1:0] y,'),
])
edit('rtl/sd/bmp_read_g.v', [
    ('parameter SD_READ_TIMEOUT_MS = 500', 'parameter SD_READ_TIMEOUT_MS = 500,\n    parameter EXACT_WIDTH = 0,\n    parameter EXACT_HEIGHT = 0'),
    ("&& (pixel_offset >= 32'd54)", "&& (EXACT_WIDTH == 0 || width == EXACT_WIDTH)\n                           && (EXACT_HEIGHT == 0 || height == EXACT_HEIGHT)\n                           && (pixel_offset >= 32'd54)"),
])
edit('rtl/sd/sd_card_bmp_g.v', [
    ("parameter [3:0]   SCAN_TARGET_COUNT = 4'd8", "parameter [3:0]   SCAN_TARGET_COUNT = 4'd8,\n    parameter EXACT_WIDTH = 0, EXACT_HEIGHT = 0"),
    ('bmp_read_g #(\n', 'bmp_read_g #(\n        .EXACT_WIDTH(EXACT_WIDTH), .EXACT_HEIGHT(EXACT_HEIGHT),\n'),
])
edit('rtl/audio/audio_player.v', [
    ('parameter integer SAMPLE_RATE_HZ = 48_000', 'parameter integer SAMPLE_RATE_HZ = 48_000,\n    parameter integer NOMINAL_SAMPLES_PER_FRAME = 806'),
    ('localparam integer NOMINAL_SAMPLES_PER_FRAME = 806;', '// 720p60 配置为每帧800样本。'),
    ("samples_in_frame <= samples_in_frame + 16'd1;", "// VS同拍的sample属于新帧，禁止覆盖VS清零并累积旧帧。\n                samples_in_frame <= vs_pulse ? 16'd1 : samples_in_frame + 16'd1;"),
])
edit('rtl/video/promax_audio_waveform.v', [
    ('parameter integer DECIMATE = 12', 'parameter integer DECIMATE = 12,\n    parameter integer VIDEO_WIDTH=640, VIDEO_HEIGHT=480, X_BITS=10, Y_BITS=9'),
    ('[9:0] pixel_x', '[X_BITS-1:0] pixel_x'), ('[8:0] pixel_y', '[Y_BITS-1:0] pixel_y'),
    ('reg [8:0] previous_y', 'reg [Y_BITS-1:0] previous_y'),
    ('wire [8:0] current_y', 'wire [Y_BITS-1:0] current_y'),
    ('wire [8:0] top_y', 'wire [Y_BITS-1:0] top_y'),
    ('wire [8:0] bottom_y', 'wire [Y_BITS-1:0] bottom_y'),
    ('localparam CURVE_AW', 'localparam CURVE_DW = 2*Y_BITS;\n    localparam CURVE_AW'),
    ('[17:0]', '[CURVE_DW-1:0]'),
    ('.DATA_WIDTH_A(18), .DATA_WIDTH_B(18)', '.DATA_WIDTH_A(CURVE_DW), .DATA_WIDTH_B(CURVE_DW)'),
    (".dib(18'd0)", '.dib({CURVE_DW{1\'b0}})'),
    ('reg [8:0] y_q', 'reg [Y_BITS-1:0] y_q'),
    ('bounds_q[8:0]', 'bounds_q[Y_BITS-1:0]'), ('bounds_q[17:9]', 'bounds_q[CURVE_DW-1:Y_BITS]'),
    ('WAVE_X+WAVE_WIDTH > 640', 'WAVE_X+WAVE_WIDTH > VIDEO_WIDTH'),
    ('WAVE_Y+WAVE_HEIGHT > 480', 'WAVE_Y+WAVE_HEIGHT > VIDEO_HEIGHT'),
])
edit('rtl/video/emergency_render.v', [
    ('module emergency_render(', 'module emergency_render #(parameter X_BITS=10, Y_BITS=9)('),
    ('[9:0]  x,', '[X_BITS-1:0] x,'), ('[8:0]  y,', '[Y_BITS-1:0] y,'),
    ('reg [9:0] scroll_off;', "reg [9:0] scroll_off = 10'd0;"),
])
print('Parameterized legacy-compatible modules; baseline fixture saved')
