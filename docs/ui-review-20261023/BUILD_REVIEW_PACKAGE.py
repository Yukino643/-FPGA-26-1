"""当前 UI 只读取证；仅写本资料目录和独立 build 目录，不改变硬件输入。"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import subprocess
import sys
import shutil
import re

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WORK = ROOT / 'build/720p/ui-review-20261023'
IV = Path('C:/iverilog/bin/iverilog.exe')
VVP = Path('C:/iverilog/bin/vvp.exe')
SCENES = ['menu_program', 'menu_peripheral', 'menu_playback', 'menu_screen',
          'menu_screen_edit', 'menu_program_screen', 'menu_subtitle',
          'menu_subtitle_edit', 'menu_screen_pending', 'menu_wait',
          'menu_audio', 'menu_audio_edit', 'menu_audio_mute']


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value.replace('\r\n', '\n'), encoding='utf-8', newline='\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args, name, cwd=WORK):
    p = subprocess.run(list(map(str, args)), cwd=cwd, capture_output=True, timeout=300)
    write(HERE / 'evidence' / (name + '.log'),
          p.stdout.decode('utf-8', errors='strict') + p.stderr.decode('utf-8', errors='strict'))
    if p.returncode:
        raise RuntimeError(f'{name} failed: code={p.returncode}; see evidence/{name}.log')
    return p.stdout.decode('utf-8', errors='strict')


def menu_group(first, last):
    name = f'menu_{first}_{last}'
    exe = WORK / (name + '.vvp')
    run([IV, '-g2005', '-s', 'tb_monitor_menu_renderer',
         f'-Ptb_monitor_menu_renderer.FIRST_SCENE={first}',
         f'-Ptb_monitor_menu_renderer.LAST_SCENE={last}', '-o', exe,
         ROOT/'sim/tb_monitor_menu_renderer.v', ROOT/'rtl/video/monitor_menu_renderer.v',
         ROOT/'rtl/video/monitor_cjk_rom.v', ROOT/'rtl/ctrl/font_rom_ascii.v'], name+'_compile')
    result = run([VVP, exe], name)
    if 'TB_MONITOR_MENU_RENDERER PASS' not in result:
        raise RuntimeError(name + ' missing PASS')
    print(name + ' PASS', flush=True)


def photo_render():
    result = run([sys.executable, '-B', ROOT/'scripts/render_main_ui.py',
                  '--output', WORK/'main'], 'main_photo')
    if result.count('MAIN_UI_PHOTO PASS') != 3:
        raise RuntimeError('photo scene count mismatch')
    print('main photo-fed RTL PASS, 3 scenes', flush=True)


def main():
    for p in (WORK, HERE/'images', HERE/'images/logical', HERE/'evidence'):
        p.mkdir(parents=True, exist_ok=True)
    protected = [p for folder in ('rtl', 'constraints', 'scripts', 'sim')
                 for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in str(p)]
    protected += [ROOT/'td_prj/flow_fixhold.tcl', ROOT/'td_prj/av_media.al',
                  ROOT/'td_prj/av_media_Runs/phy_1/av_media.bit',
                  ROOT/'releases/20261023-autoplay-period/av_media.bit']
    before = {p.relative_to(ROOT).as_posix(): digest(p) for p in protected}
    with ThreadPoolExecutor(max_workers=5) as pool:
        jobs = [pool.submit(menu_group, a, b) for a,b in ((0,3),(4,6),(7,9),(10,12))]
        jobs.append(pool.submit(photo_render))
        for job in jobs:
            job.result()
    provenance = []
    for scene, name in enumerate(SCENES):
        im = Image.open(WORK/(name+'.ppm')).convert('RGB')
        if im.size != (640,480):
            raise RuntimeError('menu size mismatch: '+name)
        im.save(HERE/'images/logical'/(name+'_640.png'))
        a = np.asarray(im)
        out = np.zeros((720,1280,3),dtype=np.uint8)
        out[:,160:1120] = a[(np.arange(720)*2//3)[:,None], (np.arange(960)*2//3)[None,:]]
        file = 'images/'+name+'_720.png'
        Image.fromarray(out).save(HERE/file)
        provenance.append({'file':file, 'kind':'current menu RTL raster with top coordinate mapping',
                           'bench':'sim/tb_monitor_menu_renderer.v', 'scene':scene,
                           'mapping':'x=160..1120, y=0..720, nearest 1.5x; black sidebars',
                           'limits':'testbench fixture; not board capture; not a recorded key sequence'})
    for name in ('light','dark','subtitle_off'):
        file = 'images/hdmi_b_'+name+'_OSD_RTL.png'
        shutil.copy2(WORK/'main'/(name+'_OSD_RTL.png'), HERE/file)
        provenance.append({'file':file,'kind':'photo-fed current OSD RTL, pixel-reference checked',
                           'generator':'scripts/render_main_ui.py', 'waveform':False,
                           'title':True,'clock':True,'subtitle':name!='subtitle_off',
                           'uptime':'12:34:56', 'preset':0,'scroll_phase':0,
                           'limits':'not board capture; waveform disabled; no full SDRAM/HDMI physical validation'})
    shutil.copy2(WORK/'main/verification.json', HERE/'evidence/PHOTO_RTL_VERIFICATION.json')

    # 照片图不含波形；波形证据另取当前独立RTL测试及源码，不拼接伪造主屏。
    snapshot_files = [
        'rtl/video/monitor_menu_renderer.v','rtl/video/monitor_cjk_rom.v',
        'rtl/ctrl/font_rom_ascii.v','rtl/ctrl/font_ascii_bram.hex',
        'rtl/ctrl/monitor_menu_ctrl.v','rtl/ctrl/monitor_config_regs.v',
        'rtl/top/top_tf_hdmi_audio.v','rtl/video/osd_engine_720.v',
        'rtl/video/osd_text_720.v','rtl/video/subtitle_text_720.v',
        'rtl/video/font_rom_720.v','rtl/video/font_720.hex','rtl/video/font_720_map.vh',
        'rtl/video/promax_audio_waveform.v','rtl/video/color_adjust.v',
        'rtl/video/emergency_render.v','rtl/ctrl/emergency_ctrl.v',
        'rtl/audio/pcm_volume_control.v','rtl/sd/sd_card_bmp_g.v',
        'scripts/gen_font_720.py','scripts/gen_monitor_cjk.py','scripts/render_main_ui.py',
        'sim/tb_monitor_menu_renderer.v','sim/tb_monitor_menu_ctrl.v',
        'sim/tb_monitor_config_regs.v','sim/tb_monitor_pipeline.v',
        'sim/tb_subtitle720.v','sim/tb_video_pipeline_720.v','sim/tb_audio_menu.v']
    source_hashes = {}
    locations = {}
    for name in snapshot_files:
        src = ROOT/name
        dest = HERE/'source_snapshot'/name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src,dest)
        source_hashes[name]=digest(src)
        # 索引记录实际行号；不把读者锁定在可能过时的历史编号。
        if src.suffix in ('.v','.py'):
            content = src.read_bytes().decode('utf-8-sig',errors='strict')
            locations[name] = [{'line':i, 'text':line.strip()[:180]}
                               for i,line in enumerate(content.splitlines(),1)
                               if re.search(r'localparam.*(?:BG=|SCROLL_ORIGIN|TITLE_FG|SCREEN_DEFAULT)|'
                                            r'CHARSET =|AUDIO =|WINDOWS =|PRESETS =|CHARS =|'
                                            r'wire wide_cards|wire card_area|wire title_plate|wire clock_plate|'
                                            r'wire subtitle_band|wire subtitle_message_text|wire arrow_hit|'
                                            r'header_status<=|if \(next_long\)|if \(!cfg_dirty\)|'
                                            r'wire mon_de_view|wire \[10:0\] mon_x_logical|'
                                            r'WAVE_X\(128\)|assign rgb_out|module ',line)]
    write(HERE/'evidence/SOURCE_SHA256.json', json.dumps(source_hashes,ensure_ascii=False,indent=2)+'\n')
    write(HERE/'evidence/CODE_LOCATIONS.json',json.dumps(locations,ensure_ascii=False,indent=2)+'\n')
    release = ROOT/'releases/20261023-autoplay-period'
    for name in ('verification.json','SOURCE_SHA256.json','build_manifest.sha256'):
        shutil.copy2(release/name,HERE/'evidence'/('RELEASE_'+name))
    for name in ('MAIN_UI_20261022.md','MAIN_UI_20261022_BOARD_CHECK.md',
                 'AUDIO_VOLUME_20261022.md','AUDIO_VOLUME_20261023_BOARD_CHECK.md',
                 'AUTOPLAY_PERIOD_20261023.md','AUTOPLAY_PERIOD_20261023_BOARD_CHECK.md'):
        shutil.copy2(ROOT/'docs'/name,HERE/'evidence'/name)

    font = ImageFont.truetype('C:/Windows/Fonts/simhei.ttf',20)
    # 联系图只是RTL图的缩略导航，审美判断必须回到原尺寸。
    thumbs=[('A '+str(i+1)+' '+name,HERE/'images'/(name+'_720.png')) for i,name in enumerate(SCENES)]
    thumbs += [('B '+name,HERE/'images'/('hdmi_b_'+name+'_OSD_RTL.png')) for name in ('light','dark','subtitle_off')]
    sheet=Image.new('RGB',(1280,((len(thumbs)+1)//2)*400),'#07131D')
    draw=ImageDraw.Draw(sheet)
    for i,(label,path) in enumerate(thumbs):
        xx=(i%2)*640; yy=(i//2)*400
        draw.text((xx+12,yy+10),label,font=font,fill='#E9F4FA')
        sheet.paste(Image.open(path).resize((640,360),Image.Resampling.NEAREST),(xx,yy+40))
    sheet.save(HERE/'images/CONTACT_SHEET.png')
    write(HERE/'evidence/IMAGE_PROVENANCE.json',json.dumps(provenance,ensure_ascii=False,indent=2)+'\n')
    after={p.relative_to(ROOT).as_posix():digest(p) for p in protected}
    if before != after:
        raise RuntimeError('保护范围文件发生变化，拒绝交付')
    verification={'passed':True,'menu_rtl_scenes':13,'photo_osd_rtl_scenes':3,
                  'photo_pixel_checks':3*1280*720,'protected_file_count':len(before),
                  'protected_inputs_unchanged':True,'source_snapshot_files':len(source_hashes),
                  'bit_sha256':digest(release/'av_media.bit'),
                  'limits':'documentation and RTL raster run only; no new P&R, bitgen or board test'}
    write(HERE/'evidence/PACKAGE_VERIFICATION.json',json.dumps(verification,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(verification,ensure_ascii=False),flush=True)


if __name__=='__main__':
    main()
