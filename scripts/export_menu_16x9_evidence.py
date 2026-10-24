"""导出已通过验证的菜单/整圈字幕证据；拒绝将中断产物当作完成结果。"""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import shutil
import numpy as np
from PIL import Image, ImageDraw
from render_main_ui import reference, PRESETS

ROOT = Path(__file__).resolve().parents[1]
REG = ROOT/'build/720p/regression'


def contact_sheet(paths, target, columns=2):
    thumb_w, thumb_h, label_h = 640, 360, 24
    sheet = Image.new('RGB', (columns*thumb_w,
                            ((len(paths)+columns-1)//columns)*(thumb_h+label_h)), '#07131D')
    draw = ImageDraw.Draw(sheet)
    for n, path in enumerate(paths):
        left, top = (n % columns)*thumb_w, (n//columns)*(thumb_h+label_h)
        with Image.open(path) as original:
            sheet.paste(original.resize((thumb_w, thumb_h), Image.Resampling.NEAREST), (left, top))
        draw.text((left+8, top+thumb_h+4), path.stem, fill='#C9DBE5')
    sheet.save(target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    status = json.loads((REG/'run_status.json').read_text(encoding='utf-8'))
    results = json.loads((REG/'results.json').read_text(encoding='utf-8'))
    if not (status['complete'] and status['sim_only'] and status['filter'] is None
            and status['finished'] == status['passed'] and all(r['pass'] for r in results)):
        raise RuntimeError('完整纯仿真尚未全部通过，拒绝导出完成证据')
    subtitle_log = (REG/'subtitle720.log').read_text(encoding='utf-8')
    if 'TB_SUBTITLE720 PASS' not in subtitle_log or subtitle_log.count('SUBTITLE_CYCLE PASS') != 18:
        raise RuntimeError('字幕18完整周期缺少PASS，禁止使用部分RGB流')
    output.mkdir(parents=True, exist_ok=True)
    menus = output/'images/menu'
    menus.mkdir(parents=True, exist_ok=True)
    menu_paths = []
    for ppm in sorted(REG.glob('menu_*.ppm')):
        with Image.open(ppm) as im:
            if im.size != (640, 360):
                raise RuntimeError(f'菜单旧画布:{ppm}')
            path = menus/(ppm.stem+'_720.png')
            im.resize((1280, 720), Image.Resampling.NEAREST).save(path)
            menu_paths.append(path)
    if len(menu_paths) != 13:
        raise RuntimeError(f'菜单场景数不是13:{len(menu_paths)}')
    contact_sheet(menu_paths, output/'images/menu_contact_sheet.png')
    main_paths = sorted((output/'images/main').glob('*_OSD_RTL.png'))
    if len(main_paths) != 16:
        raise RuntimeError('明暗照片各8组合未完成')
    contact_sheet(main_paths, output/'images/main_contact_sheet.png')
    rows = list(csv.DictReader((REG/'subtitle_cycles.csv').open(encoding='ascii', newline='')))
    scroll = output/'images/scroll'
    scroll.mkdir(parents=True, exist_ok=True)
    manifest = []
    cache = {}
    bg = np.empty((720, 1280, 3), np.uint8)
    bg[:] = (132, 182, 232)
    for cycle in range(18):
        trace = [{k:int(v) for k,v in r.items()} for r in rows if int(r['cycle']) == cycle]
        if not trace:
            raise RuntimeError(f'轨迹缺失:{cycle}')
        preset, speed, clock = (trace[0][k] for k in ('preset','speed','clock'))
        limit = 1408 if clock else 1696
        duration_frames = limit*(2 if speed == 0 else 1)//(2 if speed == 2 else 1)+1
        if len(trace) != duration_frames+1:
            raise RuntimeError(f'完整VS数错误:{cycle}')
        position = 0
        for i, row in enumerate(trace):
            if i:
                position = (0 if position >= limit else position +
                            (int(i % 2 == 0) if speed == 0 else 1 if speed == 1 else 2))
            if row['frame'] != i or row['position'] != position or row['origin'] != (
                    (1184 if clock else 896)+position) % 2048:
                raise RuntimeError(f'独立逐帧轨迹核对失败:{cycle}/{i}')
            # 字幕包围盒在屏幕中的几何位置；离场最后64px必须全空白。
            left = (2048-((1184 if clock else 896)+position)) % 2048
            visible = [xx for xx in range(128, 864 if clock else 1152)
                       if (xx-left) % 2048 < len(PRESETS[preset])*32]
            if visible and visible[-1]-visible[0]+1 != len(visible):
                raise RuntimeError(f'两端分段:{cycle}/{i}')
            if position >= limit-64 and visible:
                raise RuntimeError(f'末尾64px留白不足:{cycle}/{i}')
        selected = [row for row in trace if row['capture']]
        raw_path = REG/f'subtitle_cycle_{preset}_{speed}_{clock}.rgb'
        raw = raw_path.read_bytes()
        if len(raw) != len(selected)*1280*64*3:
            raise RuntimeError(f'整圈关键帧RGB字节数错误:{cycle}')
        frames = np.frombuffer(raw, np.uint8).reshape(len(selected), 64, 1280, 3)
        name = f'preset{preset+1}_speed{speed}_clock{clock}'
        folder = scroll/name
        folder.mkdir(exist_ok=True)
        images, timings = [], []
        for i, (pixels, row) in enumerate(zip(frames, selected)):
            key = (preset, clock, row['position'])
            if key not in cache:
                cache[key] = reference(bg, True, False, clock, row['position'], preset)[656:720]
            if not np.array_equal(pixels, cache[key]):
                raise RuntimeError(f'整圈关键帧独立逐像素核对失败:{cycle}/{i}')
            im = Image.fromarray(pixels)
            im.save(folder/f'vs_{row["frame"]:04d}_p{row["position"]:04d}.png')
            images.append(im)
            next_frame = selected[i+1]['frame'] if i+1 < len(selected) else row['frame']+1
            timings.append(max(10, round((next_frame-row['frame'])*1000/60)))
        images[0].save(scroll/(name+'_keyframes.gif'), save_all=True,
                       append_images=images[1:], duration=timings, loop=0, optimize=False)
        manifest.append({'cycle':cycle, 'preset':preset, 'speed':speed, 'clock':bool(clock),
                         'checked_vs_frames':len(trace), 'keyframe_captures':len(images),
                         'last_position':trace[-1]['position'], 'blank_distance_px':64,
                         'capture_spacing':'32px plus cycle start/end; not every VS frame',
                         'raw_sha256':hashlib.sha256(raw).hexdigest()})
    shutil.copyfile(REG/'subtitle_cycles.csv', scroll/'all_vs_trace.csv')
    shutil.copyfile(REG/'results.json', output/'REGRESSION_RESULTS.json')
    shutil.copyfile(REG/'run_status.json', output/'REGRESSION_STATUS.json')
    for name in ('subtitle720','monitor_pipeline','monitor_menu_renderer','monitor_menu_ctrl',
                 'monitor_config_regs','audio_menu','font720_generated','monitor_font_generated','legacy_generated'):
        src = REG/(name+'.log')
        if not src.is_file():
            raise RuntimeError('验证日志缺失:'+str(src))
        (output/'logs').mkdir(exist_ok=True)
        shutil.copyfile(src, output/'logs'/src.name)
    (scroll/'verification.json').write_text(json.dumps({
        'cycles':manifest, 'vs_trace_rows':len(rows),
        'evidence':'actual RTL strip keyframes and every-VS trace; GIF uses keyframe holds; not board capture',
        'consecutive_segment':'segment/verification.json records 64 consecutive actual RTL frames'
    }, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(f'EVIDENCE_EXPORT PASS menu=13 main=16 cycles=18 trace_rows={len(rows)}')


if __name__ == '__main__':
    main()
