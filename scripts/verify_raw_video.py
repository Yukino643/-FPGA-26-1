"""原生Windows视频实验验证，提取当前顶层实例并保留各用例日志与输入SHA。"""
from pathlib import Path
import argparse
import concurrent.futures
import hashlib
import json
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/raw_video/test'
IV = 'C:/iverilog/bin/iverilog.exe'
VVP = 'C:/iverilog/bin/vvp.exe'

def section(text, first, last):
    start = text.index(first)
    return text[start:text.index(last, start)]

def instance(text, marker):
    start = text.index(marker)
    return text[start:text.index(');', start)+2]

def prepare(unit_only=False):
    OUT.mkdir(parents=True, exist_ok=True)
    media = ROOT / 'build/raw_video/media/big-blue-fish'
    for name in ('header.hex', 'frame0.hex', 'frame1.hex'):
        shutil.copy2(media / name, OUT / name)
    if unit_only:
        return
    raise RuntimeError('当前top已整合运行时双模式；完整通路请运行 scripts/verify_media_runtime.py，独立解析器测试使用 --unit-only')

def run(name, test, files, params=()):
    started = time.monotonic()
    args = [IV, '-g2005', '-DSIMULATION', '-s', test, '-I', str(OUT), '-o', str(OUT / (name+'.vvp')),
            *params, *[str(ROOT / f) for f in files]]
    for suffix, command in (('compile', args), ('sim', [VVP, str(OUT/(name+'.vvp'))])):
        with (OUT/(name+'_'+suffix+'.log')).open('wb') as log:
            subprocess.run(command, cwd=OUT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1800)
    output = (OUT/(name+'_sim.log')).read_text(encoding='utf-8')
    if 'PASS' not in output or 'FAIL' in output or 'ERROR' in output:
        raise RuntimeError(name+': '+output[-2000:])
    print(f'PASS {name} {time.monotonic()-started:.1f}s', flush=True)
    return {'name': name, 'seconds': round(time.monotonic()-started, 1), 'pass': True}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pipeline-only', action='store_true')
    parser.add_argument('--unit-only', action='store_true')
    args = parser.parse_args()
    prepare(unit_only=args.unit_only)
    common = ['rtl/sd/raw_video_player.v', 'rtl/sd/fat32_bmp_index.v', 'rtl/sd/fat32_file_sector_mapper.v',
              'sim/raw_video_card_model.v']
    results = []
    if not args.pipeline_only:
        results.append(run('spi_budget', 'tb_video_spi_budget', ['sim/tb_video_spi_budget.v', 'rtl/sd/sd_card_cmd.v', 'rtl/sd/spi_master.v']))
        results.append(run('frame_commit', 'tb_video_frame_commit', ['sim/tb_video_frame_commit.v', 'rtl/video/video_frame_commit.v']))
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            jobs = [pool.submit(run, f'raw{case}', 'tb_raw_video', ['sim/tb_raw_video.v', *common],
                                [f'-Ptb_raw_video.CASE={case}']) for case in range(7)]
            for job in jobs:
                results.append(job.result())
    if not args.unit_only:
        results.append(run('pipeline', 'tb_raw_video_pipeline', ['sim/tb_raw_video_pipeline.v', *common,
            'rtl/video/video_frame_commit.v', 'rtl/sd/src_packer.v', 'rtl/sd/source_scaler_gate.v',
            'rtl/sd/frame_read_write.v', 'rtl/sd/frame_fifo_write.v', 'rtl/pll/afifo_16_32_256.v',
            'rtl/video/resize_frame_720.v', 'rtl/video/display_stream_720.v', 'rtl/video/disp_mixer_565.v',
            'rtl/mem/disp_read_engine.v', 'rtl/mem/afifo_simple.v', 'rtl/mem/mem_mpu.v',
            'rtl/video/video_timing_gen.v', 'sim/sdram_beh.v']))
    inputs = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in ('rtl', 'sim') for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ('.v','.hex','.vh')}
    (OUT/('pipeline_results.json' if args.pipeline_only else 'unit_results.json' if args.unit_only else 'results.json')).write_text(
        json.dumps({'results': results, 'inputs_sha256': inputs}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')

if __name__ == '__main__':
    main()
