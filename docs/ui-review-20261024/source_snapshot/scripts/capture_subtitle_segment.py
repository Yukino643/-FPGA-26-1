"""抓取连续64帧实际RTL细条，与独立照片OSD参考比较；不调用综合工具。"""
from pathlib import Path
import argparse
import json
import subprocess
import numpy as np
from PIL import Image
from render_main_ui import reference

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    work = ROOT/'build/menu-16x9/segment'
    work.mkdir(parents=True, exist_ok=True)
    sources = [ROOT/'sim/tb_subtitle_capture_segment.v']
    sources += [ROOT/'rtl/video'/n for n in (
        'osd_engine_720.v', 'osd_text_720.v', 'subtitle_text_720.v', 'font_rom_720.v')]
    exe = work/'segment.vvp'
    compile_result = subprocess.run([
        'C:/iverilog/bin/iverilog.exe', '-g2005', '-I', str(ROOT/'rtl/video'),
        '-o', str(exe), *map(str, sources)], cwd=work, capture_output=True, check=True)
    (work/'compile.log').write_bytes(compile_result.stdout+compile_result.stderr)
    with (work/'run.log').open('wb') as log:
        subprocess.run(['C:/iverilog/bin/vvp.exe', str(exe)], cwd=work,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)
    raw = (work/'subtitle_segment.rgb').read_bytes()
    if len(raw) != 64*1280*64*3:
        raise RuntimeError(f'64帧细条字节数错误:{len(raw)}')
    actual = np.frombuffer(raw, np.uint8).reshape(64, 64, 1280, 3)
    bg = np.empty((720, 1280, 3), np.uint8)
    bg[:] = (132, 182, 232)
    images = []
    for frame, pixels in enumerate(actual):
        expected = reference(bg, True, False, True, 512+2*frame)[656:720]
        if not np.array_equal(pixels, expected):
            raise RuntimeError(f'连续帧独立参考失败 frame={frame}')
        im = Image.fromarray(pixels)
        im.save(output/f'frame_{frame:03d}.png')
        images.append(im)
    images[0].save(output/'segment_rtl.apng', format='PNG', save_all=True,
                   append_images=images[1:], duration=[17, 17, 16]*21+[17], loop=0)
    # GIF仅支持10ms单位；用20/10/20ms近似60Hz，不把预览计时当硬件证据。
    images[0].save(output/'segment_rtl.gif', save_all=True, append_images=images[1:],
                   duration=[20, 10, 20]*21+[20], loop=0, optimize=False)
    (output/'verification.json').write_text(json.dumps({
        'frames':64, 'pixel_checks':64*1280*64, 'position':[512,638],
        'speed':'FAST=2px/VS', 'clock':True,
        'evidence':'64 consecutive actual RTL strip captures; 60Hz nominal; not board capture',
        'preview_timing':'APNG 1ms units; GIF 10ms units; timing assertions use VS trace',
        'independent_reference':'render_main_ui.reference; every pixel compared'
    }, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')
    print('SUBTITLE_SEGMENT_INDEPENDENT PASS frames=64 pixels=5242880')


if __name__ == '__main__':
    main()
