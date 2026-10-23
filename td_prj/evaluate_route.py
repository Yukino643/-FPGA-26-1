"""隔离综合/布线评估；不生成 bit，不修改发布 run 或放宽时序约束。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

import build_native

ROOT = build_native.ROOT
RUNS = ROOT / 'td_prj/optimization_Runs'
OUTPUT = ROOT / 'build/720p/optimization-evaluation'


def snapshot():
    paths = [Path(p) for p in build_native.reports.source_files()]
    paths += [Path(__file__)]
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


def main():
    global RUNS, OUTPUT
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', default='optimization-final')
    parser.add_argument('--seed', type=int, default=11)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9-]*', args.name):
        raise ValueError('评估名称必须是小写字母、数字或短横线')
    if not 0 <= args.seed <= 2147483647:
        raise ValueError('布局seed越界')
    RUNS = ROOT / 'td_prj' / (args.name + '_Runs')
    OUTPUT = ROOT / 'build/720p' / args.name
    # 名称复用必须在任何写入前拒绝，防止破坏历史评估的输入/流程证据。
    if RUNS.exists() or OUTPUT.exists():
        raise RuntimeError(f'评估目录已存在，请使用新名称: {args.name}')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    flow = OUTPUT / 'flow.tcl'
    flow_text = (ROOT / 'td_prj/flow_fixhold.tcl').read_text(encoding='utf-8-sig')
    flow_text, n = re.subn(r'(?m)^(\s*set_param place seed) \d+$',
                          lambda m: m[1] + ' ' + str(args.seed), flow_text)
    if n != 1:
        raise RuntimeError('布局seed设置不唯一')
    flow.write_text(flow_text, encoding='utf-8', newline='\n')
    flow_hash = hashlib.sha256(flow.read_bytes()).hexdigest()
    (OUTPUT / 'flow_config.json').write_text(json.dumps({'seed':args.seed, 'sha256':flow_hash}, indent=2)+'\n', encoding='utf-8', newline='\n')
    if not build_native.reports.project_snapshots_match():
        raise RuntimeError('当前工程快照不一致，拒绝构建')
    inputs = snapshot()
    (OUTPUT / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n', encoding='utf-8', newline='\n')
    for kind in ('syn_1', 'phy_1'):
        source = ROOT / 'td_prj/av_media_Runs' / kind
        run = RUNS / kind
        run.mkdir(parents=True, exist_ok=True)
        project = (source / 'av_media.prj').read_text(encoding='utf-8-sig')
        # 工程根目录也置于隔离区，防止 TD 回写原 .al。
        project = re.sub(r'(<Project\b[^>]*\bPath=")[^"]+',
                         lambda m: m.group(1) + RUNS.as_posix(), project, count=1)
        (run / 'av_media.prj').write_text(project, encoding='utf-8', newline='\n')
        cfg = (source / 'settings.cfg').read_text(encoding='utf-8-sig')
        if kind == 'phy_1':
            cfg, n = re.subn(r'(?m)^set end_step \S+$', 'set end_step opt_route', cfg)
            if n != 1:
                raise RuntimeError('物理流程结束步骤不明确')
        (run / 'settings.cfg').write_text(cfg, encoding='utf-8', newline='\n')
        # flow 的步骤名是 opt_route（route 只是工具命令）。
        required = 'av_media_gate.db' if kind == 'syn_1' else 'av_media_pr.db'
        if (run / required).exists():
            raise RuntimeError(f'评估输出已存在，请使用新的隔离目录: {run / required}')
        print(f'[EVAL] {kind} begin', flush=True)
        started = time.monotonic()
        build_native.run_td(run, OUTPUT, flow)
        if not (run / required).is_file():
            raise RuntimeError(f'本轮没有生成 {required}')
        if snapshot() != inputs:
            raise RuntimeError('构建期间源码或发布产物变化，拒绝使用报告')
        if hashlib.sha256(flow.read_bytes()).hexdigest() != flow_hash:
            raise RuntimeError('构建期间隔离流程发生变化')
        print(f'[EVAL] {kind} done {time.monotonic()-started:.1f}s', flush=True)
    if (RUNS / 'phy_1/av_media.bit').exists():
        raise RuntimeError('仅布线评估不应生成 bit')
    (OUTPUT / 'completed.json').write_text(
        json.dumps({'inputs_match': True, 'bitgen': False, 'seed':args.seed, 'runs': RUNS.as_posix()}, indent=2) + '\n',
        encoding='utf-8', newline='\n')
    print('[EVAL] PASS synthesis and route completed, release BIT unchanged', flush=True)


if __name__ == '__main__':
    main()
