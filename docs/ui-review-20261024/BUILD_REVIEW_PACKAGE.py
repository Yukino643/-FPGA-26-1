"""生成只读UI审查包；产品输入受哈希保护，截图来源逐项标注，不执行综合/烧录/Git。"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import html
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WORK = ROOT / 'build/ui-review-20261024'
PRIOR = ROOT / 'docs/menu-16x9-20261023'
RELEASE = ROOT / 'releases/20261024-menu-16x9'
IV = Path('C:/iverilog/bin/iverilog.exe')
VVP = Path('C:/iverilog/bin/vvp.exe')
PROVENANCE = []


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8', newline='\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(args, label):
    result = subprocess.run([str(a) for a in args], cwd=WORK, capture_output=True, timeout=180)
    raw = result.stdout + result.stderr
    write(HERE / 'evidence/logs' / (label + '.log'), raw.decode('utf-8', errors='strict'))
    if result.returncode or re.search(rb'\bFAIL\b|\bERROR\b', raw):
        raise RuntimeError(f'{label} failed: {raw[-1500:]!r}')
    return raw.decode('utf-8')


def record(path, kind, **details):
    with Image.open(path) as image:
        image.load()
        dimensions = list(image.size)
    PROVENANCE.append({'file': path.relative_to(HERE).as_posix(), 'kind': kind,
                       'dimensions': dimensions, 'sha256': digest(path), **details})


def copy_evidence():
    for folder in ('menu', 'scroll'):
        shutil.copytree(PRIOR / 'images' / folder, HERE / 'images' / folder, dirs_exist_ok=True)
    for path in (PRIOR / 'images/main').glob('*_OSD_RTL.png'):
        target = HERE / 'images/main' / path.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    main_data = json.loads((PRIOR / 'images/main/verification.json').read_text(encoding='utf-8'))
    for path in sorted((HERE / 'images/menu').glob('*.png')):
        record(path, 'actual menu RTL, integer 2x mapping', source=path.name,
               logical_canvas=[640, 360], limits='fixture state; not board capture or key sequence')
        with Image.open(path) as image:
            logical = image.resize((640, 360), Image.Resampling.NEAREST)
            if not np.array_equal(np.asarray(logical.resize((1280, 720), Image.Resampling.NEAREST)), np.asarray(image)):
                raise RuntimeError('菜单不是逐像素整数2x: ' + path.name)
            target = HERE / 'images/logical' / path.name.replace('_720', '_640x360')
            target.parent.mkdir(parents=True, exist_ok=True)
            logical.save(target)
            record(target, 'exact 2x decimation of current RTL PNG; not a separate simulation')
    for item in main_data:
        path = HERE / 'images/main' / (item['scene'] + '_OSD_RTL.png')
        record(path, 'photo-fed actual OSD RTL with independent pixel reference',
               **{key: value for key, value in item.items() if key != 'evidence'},
               limits='waveform off; no full TF/SDRAM/TMDS simulation; not board capture')
    for path in sorted((HERE / 'images/scroll').rglob('*')):
        if path.suffix.lower() in ('.png', '.gif', '.apng'):
            record(path, 'actual RTL strip ' + ('consecutive segment' if 'segment' in path.parts else 'cycle keyframes'),
                   source_region=[0, 656, 1280, 720],
                   limits='not board capture; GIF timing quantized; use every-VS CSV for speed')
    for name in ('REGRESSION_STATUS.json', 'REGRESSION_RESULTS.json', 'SOURCE_AUDIT.json', 'FINAL_VERIFICATION.json'):
        shutil.copy2(PRIOR / name, HERE / 'evidence' / ('rtl_stage_' + name))
    for name in ('verification.json', 'build_manifest.sha256', 'av_media_phy.area', 'av_media_phy.ts', 'av_media_pr.timing'):
        shutil.copy2(RELEASE / name, HERE / 'evidence' / name)
    for name in ('run_status.json', 'results.json', 'current_source_reports.log', 'current_resize_timing.log'):
        shutil.copy2(RELEASE / 'validation' / name, HERE / 'evidence' / name)
    for folder in ('subtitle_timing', 'resize_timing'):
        shutil.copy2(RELEASE / 'validation' / folder / 'summary.json', HERE / 'evidence' / (folder + '.json'))
    write(HERE / 'evidence/PHYSICAL_RELEASE_20261024.txt',
          '来源：docs/menu-16x9-20261023/PHYSICAL_RELEASE_20261024.md\n'
          '以下为原始发布说明摘录；相对路径以来源目录为基准，不是本审查包内链接。\n\n'
          + (PRIOR / 'PHYSICAL_RELEASE_20261024.md').read_text(encoding='utf-8-sig'))
    shutil.copy2(PRIOR / 'images/main/verification.json', HERE / 'evidence/main_images_verification.json')
    # 以纯文本保存原说明，避免把原目录相对链接渲染成离线包内的错误入口。


def white_subtitles():
    bench = WORK / 'white_subtitles.v'
    raw = WORK / 'white_subtitles.rgb'
    write(bench, f'''`timescale 1ns/1ps
module tb_review_white;
reg clk=0,rst=1; always #5 clk=~clk;
reg [10:0] x=0; reg [9:0] y=0; reg [4:0] cfg=9;
wire [23:0] rgb; integer preset,i,f;
osd_engine_720 dut(.I_clk(clk),.I_rst(rst),.I_vs_pulse(1'b0),.I_subtitle_cfg(cfg),
.I_x(x),.I_y(y),.I_bg_rgb(24'hffffff),.I_uptime_bcd(24'h123456),.I_mode(2'd1),
.I_clock_enable(1'b0),.I_text_enable(1'b0),.O_rgb(rgb));
initial begin
repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);
f=$fopen("{raw.as_posix()}","wb");if(!f)$fatal(1,"FAIL open");
for(preset=0;preset<3;preset=preset+1)begin
@(negedge clk);cfg=9+2*preset;repeat(4)@(negedge clk);
// 仅取证夹具定格在正文完全可见位置，不代表产品新增暂停功能。
force dut.scroll_position=11'd1024;
for(i=664*1280;i<712*1280;i=i+1)begin
@(negedge clk);x=i%1280;y=i/1280;
@(posedge clk);#1;$fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);end
release dut.scroll_position;
end
$fclose(f);$display("REVIEW_WHITE_SUBTITLES PASS");$finish;end
endmodule
''')
    output = WORK / 'white_subtitles.vvp'
    run([IV, '-g2005', '-I', ROOT / 'rtl/video', '-o', output, bench,
         *[ROOT / 'rtl/video' / name for name in ('osd_engine_720.v', 'osd_text_720.v', 'subtitle_text_720.v', 'font_rom_720.v')]], 'white_compile')
    if 'REVIEW_WHITE_SUBTITLES PASS' not in run([VVP, output], 'white_subtitles'):
        raise RuntimeError('Missing white subtitle PASS')
    pixels = np.frombuffer(raw.read_bytes(), np.uint8).reshape((3, 48, 1280, 3))
    reference = load_module('current_reference', ROOT / 'scripts/render_main_ui.py')
    bg = np.full((720, 1280, 3), 255, np.uint8)
    for preset in range(3):
        expected = reference.reference(bg, True, False, False, phase=1024, preset=preset)[664:712]
        if not np.array_equal(pixels[preset], expected):
            raise RuntimeError('白底字幕独立像素不匹配: ' + str(preset))
        path = HERE / 'images/subtitle' / f'preset{preset+1}_white_RTL.png'
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(pixels[preset]).save(path)
        record(path, 'new actual current OSD RTL white strip; independently pixel-checked',
               preset=preset, position=1024, clock=False, source_region=[0, 664, 1280, 712],
               pixel_checks=1280*48, limits='testbench force of internal p only for static capture; not board capture')
    shutil.copy2(bench, HERE / 'evidence/white_subtitles.v')


def waveform():
    output = WORK / 'waveform.vvp'
    run([IV, '-g2005', '-DSIMULATION', '-s', 'tb_audio_waveform_720', '-o', output,
         ROOT / 'sim/tb_audio_waveform_720.v', ROOT / 'rtl/video/promax_audio_waveform.v'], 'waveform_compile')
    if 'TB_AUDIO_WAVEFORM_720 PASS' not in run([VVP, output], 'waveform'):
        raise RuntimeError('波形没有PASS')
    with Image.open(WORK / 'waveform_720.ppm') as image:
        if image.size != (1072, 104):
            raise RuntimeError('波形裁剪尺寸错误')
        path = HERE / 'images/waveform_current_RTL.png'
        image.save(path)
    record(path, 'new actual current waveform RTL independent fixture', source_region=[112,568,1184,672],
           limits='synthetic PCM; #876543 constant background; DECIMATE4 fixture vs top120; not photo composite or board capture')


def font_atlases():
    bench = WORK / 'font_atlas.v'
    rows = WORK / 'font_rows.txt'
    write(bench, f'''`timescale 1ns/1ps
module tb_review_fonts;
reg clk=0;always #5 clk=~clk;
reg [5:0] g=0;reg [4:0] r=0;wire[31:0] bits;
reg [7:0] a=0;reg[3:0] ar=0;wire[7:0] ab;
integer i,j,f;
monitor_cjk_rom cjk(.I_clk(clk),.I_index(g),.I_row(r),.O_bits(bits));
font_rom_ascii ascii(.I_clk(clk),.I_char(a),.I_row(ar),.O_bits(ab));
initial begin f=$fopen("{rows.as_posix()}","w");if(!f)$fatal(1,"FAIL open");
for(i=0;i<40;i=i+1)for(j=0;j<32;j=j+1)begin
@(negedge clk);g=i;r=j;@(posedge clk);#1;$fwrite(f,"C %0d %0d %08x\\n",i,j,bits);end
for(i=32;i<=126;i=i+1)for(j=0;j<16;j=j+1)begin
@(negedge clk);a=i;ar=j;@(posedge clk);#1;$fwrite(f,"A %0d %0d %02x\\n",i,j,ab);end
$fclose(f);$display("REVIEW_FONTS PASS");$finish;end
endmodule
''')
    output = WORK / 'font_atlas.vvp'
    run([IV, '-g2005', '-o', output, bench, ROOT / 'rtl/video/monitor_cjk_rom.v',
         ROOT / 'rtl/ctrl/font_rom_ascii.v'], 'font_compile')
    if 'REVIEW_FONTS PASS' not in run([VVP, output], 'font_readback'):
        raise RuntimeError('字体没有PASS')
    cjk, ascii_rows = {}, {}
    for line in rows.read_text(encoding='ascii').splitlines():
        kind, index, row, value = line.split()
        target = cjk if kind == 'C' else ascii_rows
        target.setdefault(int(index), {})[int(row)] = int(value, 16)
    if len(cjk) != 40 or len(ascii_rows) != 95:
        raise RuntimeError('字形回读数量错误')
    generator = load_module('ascii_generator', ROOT / 'scripts/gen_font.py')
    if any([ascii_rows[code][row] for row in range(16)] != expected for code, expected in generator.rasterize().items()):
        raise RuntimeError('ASCII实际ROM与独立字体生成不一致')
    menu = load_module('cjk_generator', ROOT / 'scripts/gen_monitor_cjk.py')
    chars = menu.CHARSET + menu.EXTRA + menu.AUDIO
    source_font = ImageFont.truetype('C:/Windows/Fonts/simhei.ttf', 30)
    for index, ch in enumerate(chars):
        reference = Image.new('L', (32, 32))
        draw = ImageDraw.Draw(reference)
        left, top, right, bottom = draw.textbbox((0, 0), ch, font=source_font)
        draw.text(((32-right+left)//2-left, (32-bottom+top)//2-top), ch, fill=255, font=source_font)
        expected = [sum((reference.getpixel((x,y)) > 100) << (31-x) for x in range(32)) for y in range(32)]
        if [cjk[index][r] for r in range(32)] != expected:
            raise RuntimeError('中文ROM/逻辑字与字体参考不同: ' + ch)
    folder = HERE / 'images/typography'
    folder.mkdir(parents=True, exist_ok=True)
    for name, data, width, height, scale, columns in (
            ('menu_cjk40_ROM_2x.png', cjk,32,32,2,8), ('ascii95_ROM_4x.png',ascii_rows,8,16,4,16)):
        cell_w, cell_h = width*scale+16, height*scale+24
        atlas = Image.new('RGB', (columns*cell_w, ((len(data)+columns-1)//columns)*cell_h), '#07131D')
        draw = ImageDraw.Draw(atlas)
        for n,(index, values) in enumerate(sorted(data.items())):
            glyph = Image.new('RGB', (width,height), '#142F40')
            for y in range(height):
                for x in range(width):
                    if values[y] & (1 << (width-1-x)):
                        glyph.putpixel((x,y), (233,244,250))
            xx, yy = n%columns*cell_w, n//columns*cell_h
            atlas.paste(glyph.resize((width*scale,height*scale),Image.Resampling.NEAREST),(xx+8,yy+4))
            draw.text((xx+8,yy+height*scale+7), str(index) if width==32 else f'{index:02X} {chr(index)}', fill='#8FA9B8')
        path = folder/name
        atlas.save(path)
        record(path, 'new actual synchronous ROM readback atlas; annotations external to UI',
               limits='all40 CJK compared to font threshold reference; ASCII95 also compared; not board capture')
    shutil.copy2(rows, HERE/'evidence/font_rows.txt')
    shutil.copy2(bench, HERE/'evidence/font_atlas.v')
    write(HERE/'evidence/menu_cjk_index.json',json.dumps(dict(enumerate(chars)),ensure_ascii=False,indent=2)+'\n')


def snapshot():
    names = [
        'rtl/top/top_tf_hdmi_audio.v', 'rtl/video/monitor_menu_renderer.v',
        'rtl/ctrl/monitor_menu_ctrl.v','rtl/ctrl/monitor_config_regs.v','rtl/ctrl/emergency_ctrl.v',
        'rtl/ctrl/font_rom_ascii.v','rtl/ctrl/font_ascii_bram.hex','rtl/video/monitor_cjk_rom.v',
        'rtl/video/osd_engine_720.v','rtl/video/osd_text_720.v','rtl/video/subtitle_text_720.v',
        'rtl/video/font_rom_720.v','rtl/video/font_720.hex','rtl/video/font_720_map.vh',
        'rtl/video/promax_audio_waveform.v','rtl/video/color_adjust.v','rtl/video/emergency_render.v',
        'rtl/video/video_timing_gen.v','rtl/audio/pcm_volume_control.v',
        'scripts/gen_monitor_cjk.py','scripts/gen_font.py','scripts/gen_font_720.py',
        'scripts/render_main_ui.py','scripts/export_menu_16x9_evidence.py','scripts/capture_subtitle_segment.py',
        'scripts/package_menu_16x9.py','scripts/check_subtitle_timing.py',
        'sim/tb_monitor_menu_renderer.v','sim/tb_monitor_pipeline.v','sim/tb_subtitle720.v',
        'sim/tb_video_pipeline_720.v','sim/tb_audio_waveform_720.v','sim/tb_subtitle_capture_segment.v',
        'sim/tb_audio_menu.v','sim/tb_monitor_menu_ctrl.v','sim/tb_monitor_config_regs.v']
    hashes, locations = {}, {}
    patterns = {
        'rtl/video/monitor_menu_renderer.v': ['localparam.*BG=', 'STR_PROG', 'function.*card_pending', 'function.*card_value_label',
                                             'reg.*header_status', 'wire wide_cards', 'wire header_hit', 'volume_bar_d<=', 'wire.*thin_border', 'assign rgb='],
        'rtl/top/top_tf_hdmi_audio.v': ['led_state_sd =', 'screen_contrast_video =', 'u_osd\\(', 'WAVE_X\\(128', 'mon_de_view =', 'u_mon_timing_gen', 'u_mon_menu_renderer'],
        'rtl/ctrl/monitor_menu_ctrl.v': ['LONG_PRESS_MS =', 'wire next_short', 'menu_active <= 1', 'else if \\(next_long', 'else if \\(auto_long', 'if \\(!cfg_dirty\\)'],
        'rtl/video/osd_engine_720.v': ['TITLE_FG=', 'wire title_plate', 'reg.*scroll_position', 'scroll_base=', 'wire subtitle_band', 'wire.*subtitle_message_text', 'wire.*glyph =', 'assign O_rgb'],
        'scripts/gen_font_720.py': ['WINDOWS =', 'PRESETS =', 'CHARS =', 'subtitle ='],
        'scripts/gen_font.py': ['FONT_PATH ='],
        'scripts/gen_monitor_cjk.py': ['CHARSET =','EXTRA =','AUDIO ='],
    }
    for name in names:
        source = ROOT/name
        target = HERE/'source_snapshot'/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source,target)
        hashes[name]=digest(source)
        if digest(target)!=hashes[name]:
            raise RuntimeError('快照回读不符: '+name)
        if name in patterns:
            lines = source.read_text(encoding='utf-8-sig').splitlines()
            locations[name] = [{'line':i,'text':line.strip()} for i,line in enumerate(lines,1)
                               if any(re.search(pattern,line) for pattern in patterns[name])]
    write(HERE/'evidence/SOURCE_SHA256.json',json.dumps(hashes,ensure_ascii=False,indent=2)+'\n')
    write(HERE/'evidence/CODE_LOCATIONS.json',json.dumps(locations,ensure_ascii=False,indent=2)+'\n')
    fonts=load_module('font720_metrics',ROOT/'scripts/gen_font_720.py')
    write(HERE/'evidence/TEXT_METRICS.json',json.dumps({
        'badge':fonts.BADGE,'glyph_count':len(fonts.CHARS),'glyphs':list(fonts.CHARS),
        'presets':[{'text':line,'visible_spaces':line.replace(' ','␠'),'cells':len(line),
                    'cell_width':32,'width_px':len(line)*32,
                    'codepoints':[f'U+{ord(ch):04X}' for ch in line]} for line in fonts.PRESETS],
        'menu_ascii':'consolab.ttf; 8x16 bits; 2x logical for normal labels, then 2x physical',
        'menu_cjk':'simhei.ttf; 32x32 bits; 2x physical; 36 ROM+4 logic',
    },ensure_ascii=False,indent=2)+'\n')
    return hashes


def previews_gallery():
    selected = [HERE/'images/menu'/f'{name}_720.png' for name in ('menu_program','menu_audio','menu_screen')]
    selected += [HERE/'images/main'/f'{name}_T1C1S1_OSD_RTL.png' for name in ('BEACH720','NIGHT720')]
    for source in selected:
        target=HERE/'images/previews_800x450'/(source.stem+'_preview.png')
        target.parent.mkdir(parents=True,exist_ok=True)
        with Image.open(source) as image:
            image.resize((800,450),Image.Resampling.LANCZOS).save(target)
        record(target,'software resample preview of current RTL PNG', source=source.relative_to(HERE).as_posix(),
               limits='not actual panel resolution, PPI, physical size or board photo')
    # 以直接链接保留原像素查看；不用CSS拟造新的UI冒充RTL。
    sections = [('菜单720p','images/menu/*.png'),('菜单640×360逻辑抽取','images/logical/*.png'),
                ('明暗照片：8种组合各一组','images/main/*.png'),('三句白底字幕','images/subtitle/*.png'),
                ('完整字幕圈关键帧GIF','images/scroll/*_keyframes.gif'),
                ('64连续帧预览','images/scroll/segment/*.apng'),('字形图','images/typography/*.png'),
                ('仅缩小预览，非屏幕照片','images/previews_800x450/*.png')]
    parts=['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>20261024 全幅UI审查</title>',
           '<style>body{margin:24px;background:#eef2f5;color:#15232c;font:16px system-ui} img{max-width:100%;height:auto;background:#fff}figure{margin:32px 0}figcaption{margin:8px 0;overflow-wrap:anywhere}a{color:#075985}h2{margin-top:48px}</style>',
           '<h1>20261024 全幅菜单版：当前RTL视觉证据</h1><p>13菜单/16主屏/3白底字幕。不是板拍。点击原图按原像素看字形；GIF为关键帧保持，速度以VS轨迹为准。</p>',
           '<p><a href="CURRENT_UI_REVIEW.md">完整现状底稿</a> · <a href="REVIEW_PROMPT.txt">审查提示词</a> · <a href="REVIEW_RETURN_TEMPLATE.md">返回模板</a></p>']
    lookup={item['file']:item for item in PROVENANCE}
    for title,pattern in sections:
        parts.append('<h2>'+html.escape(title)+'</h2>')
        for path in sorted(HERE.glob(pattern)):
            rel=path.relative_to(HERE).as_posix()
            parts.append(f'<figure><a href="{html.escape(rel)}"><img loading="lazy" src="{html.escape(rel)}" alt="{html.escape(path.stem)}"></a><figcaption>{html.escape(rel)} — {html.escape(lookup[rel]["kind"])}</figcaption></figure>')
    parts.append('<h2>独立波形（合成PCM，非照片联合效果）</h2><img src="images/waveform_current_RTL.png"><p>全部关键帧PNG、每VS轨迹和连续64张PNG在images/scroll/。</p></html>')
    write(HERE/'VISUAL_GALLERY.html','\n'.join(parts)+'\n')


def document_inventory():
    rows=[]
    for path in sorted([ROOT/'AGENTS.md',ROOT/'README.md',ROOT/'PROGRESS_HDMI_MONITOR.md',*(ROOT/'docs').glob('*.md')]):
        raw=path.read_bytes()
        if raw.startswith((b'\xff\xfe',b'\xfe\xff')):
            text=raw.decode('utf-16')
        else:
            text=raw.decode('utf-8-sig',errors='strict')
        rows.append({'file':path.relative_to(ROOT).as_posix(),'lines':len(text.splitlines()),'bytes':len(raw),
                     'decision':'现有发布入口已指向本版；本轮只新增审查入口' if path.name=='README.md' else
                     '历史/其他专题，保留原始记录；本轮现状以CURRENT_UI_REVIEW.md为准',
                     'sha256':hashlib.sha256(raw).hexdigest()})
    write(HERE/'evidence/DOCUMENT_AUDIT.json',json.dumps(rows,ensure_ascii=False,indent=2)+'\n')


def main():
    HERE.joinpath('evidence').mkdir(exist_ok=True)
    WORK.mkdir(parents=True,exist_ok=True)
    # 保护实际产品输入与相关脚本/验证源，不对无关build临时文件递归计算。
    reports=load_module('reports_for_review',ROOT/'scripts/check_reports.py')
    paths=set(Path(path) for path in reports.source_files())
    for folder in ('scripts','sim'):
        paths.update(path for path in (ROOT/folder).rglob('*') if path.is_file() and path.suffix in ('.py','.v','.vh','.hex','.sh','.ps1'))
    protected={path.relative_to(ROOT).as_posix():digest(path) for path in paths}
    if not reports.manifest_matches():
        raise RuntimeError('当前源码与发布bit清单不一致，停止生成现状包')
    copy_evidence()
    with ThreadPoolExecutor(max_workers=3) as pool:
        jobs=[pool.submit(action) for action in (white_subtitles,waveform,font_atlases)]
        for job in jobs:
            job.result()
    hashes=snapshot()
    previews_gallery()
    document_inventory()
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode('ascii').strip()
    write(HERE/'evidence/BASELINE.json',json.dumps({
        'date':'2026-10-24','source_commit':'741d715','journal_commit':'4a23c05','head_at_packaging':head,
        'release':'20261024-menu-16x9','bit_sha256':digest(RELEASE/'av_media.bit'),
        'evidence':'current RTL/TD results; no new board test; packaging does not change product or Git',
    },ensure_ascii=False,indent=2)+'\n')
    for name,expected in protected.items():
        if digest(ROOT/name)!=expected:
            raise RuntimeError('产品输入在资料生成中变化: '+name)
    if not reports.manifest_matches():
        raise RuntimeError('生成资料后manifest失配')
    # 并发capture不共享清单文件，清单在主线程最终写出。
    PROVENANCE.sort(key=lambda item:item['file'])
    write(HERE/'evidence/IMAGE_PROVENANCE.json',json.dumps(PROVENANCE,ensure_ascii=False,indent=2)+'\n')
    image_files=[path for path in HERE.rglob('*') if path.suffix.lower() in ('.png','.gif','.apng')]
    for path in image_files:
        with Image.open(path) as im:
            for frame in range(getattr(im,'n_frames',1)):
                im.seek(frame);im.load()
    verification={'passed':True,'product_files_protected':len(protected),'product_drift':False,
                  'source_snapshot_files':len(hashes),'source_snapshot_all_match':True,
                  'menu_images':13,'main_photos_all8_combinations':16,'new_white_subtitle_strips':3,
                  'white_subtitle_independent_pixel_checks':3*1280*48,'font_glyphs_read_back_and_compared':135,
                  'full_scroll_cycles':18,'continuous_frames':64,'image_files_all_decoded':len(image_files),
                  'new_waveform_fixture_pass':True,'physical_build_rerun':False,'hardware_tested':False,
                  'git_committed_by_this_packaging':False,'source_snapshot_is_full_project':False}
    write(HERE/'evidence/PACKAGE_VERIFICATION.json',json.dumps(verification,ensure_ascii=False,indent=2)+'\n')
    # 审查者的输出目录先建空，不预写评审结论。
    (HERE/'proposal/images').mkdir(parents=True,exist_ok=True)
    sums=[digest(path)+'  '+path.relative_to(HERE).as_posix() for path in sorted(HERE.rglob('*'))
          if path.is_file() and path.name!='SHA256SUMS.txt']
    write(HERE/'SHA256SUMS.txt','\n'.join(sums)+'\n')
    archive=ROOT/'docs/UI_REVIEW_20261024.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for path in sorted(HERE.rglob('*')):
            if path.is_file():
                z.write(path,path.relative_to(HERE).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise RuntimeError('审查ZIP CRC失败')
        for line in sums:
            expected,name=line.split('  ',1)
            if hashlib.sha256(z.read(name)).hexdigest()!=expected:
                raise RuntimeError('审查ZIP SHA回读失败: '+name)
    write(archive.with_suffix('.zip.sha256'),digest(archive)+'  '+archive.name+'\n')
    print(json.dumps(verification,ensure_ascii=False,indent=2))
    print('UI_REVIEW_PACKAGE PASS '+str(archive))


if __name__=='__main__':
    main()
