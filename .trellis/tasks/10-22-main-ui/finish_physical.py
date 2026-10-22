"""有限布局候选验证：只改官方seed，不放宽约束；首次严格通过即停止。"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'


def archive(build):
    dst = build / 'rejected-timing-reports'
    dst.mkdir()
    for p in PHY.iterdir():
        if p.is_file() and (p.suffix in ('.bit', '.timing', '.area') or 'manifest' in p.name):
            shutil.copy2(p, dst / p.name)
    shutil.copy2(ROOT / 'build/720p/main-ui-verification.json', dst / 'main-ui-verification.json')


def main():
    archive(ROOT / 'build/720p/td/20261022-main-ui-macrotiming13')
    flow = ROOT / 'td_prj/flow_fixhold.tcl'
    text = flow.read_text(encoding='utf-8')
    start = text.index('  # TD 6.2官方MacroTiming物理策略；')
    end = text.index('  place\n', start)
    text = text[:start] + text[end:]
    text = text.replace('  # TD 6.2官方TimingHigh策略中的布线后时序优化；不改变时钟和SDC。\n', '')
    text = text.replace('  set_param route post_route_opt high\n', '')
    # 受测RTL输入全程不变；失败候选归档后才启动下一次构建。
    rtl = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT / 'rtl').rglob('*') if p.is_file()}
    for seed in range(19, 25):
        build = ROOT / f'build/720p/td/20261022-main-ui-default{seed}'
        if build.exists():
            raise RuntimeError('拒绝覆盖候选: ' + str(build))
        current, count = re.subn(r'set_param place seed \d+', f'set_param place seed {seed}', text)
        if count != 1:
            raise RuntimeError('seed参数不唯一')
        flow.write_text(current, encoding='utf-8', newline='\n')
        print('PHYSICAL_CANDIDATE', seed, flush=True)
        proc = subprocess.run([sys.executable, '-B', str(ROOT / 'td_prj/build_native.py'),
                               '--output', str(build)], cwd=ROOT)
        if any(hashlib.sha256(p.read_bytes()).hexdigest() != expected for p, expected in rtl.items()):
            raise RuntimeError('候选间RTL发生改变，停止')
        if proc.returncode:
            print('PHYSICAL_REJECT_BUILD', seed, flush=True)
            continue
        gate = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/check_main_ui.py'),
                               '--physical-only'], cwd=ROOT, capture_output=True)
        (build / 'strict_gate.log').write_bytes(gate.stdout + gate.stderr)
        print(gate.stdout.decode('utf-8', errors='replace'), flush=True)
        if gate.returncode == 0:
            record = {'build':build.relative_to(ROOT).as_posix(), 'seed':seed,
                      'strict_physical_passed':True, 'full_release_pending':True}
            (ROOT / '.trellis/tasks/10-22-main-ui/accepted-physical.json').write_text(
                json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
            print('PHYSICAL_ACCEPT', str(build), flush=True)
            return
        archive(build)
    raise RuntimeError('有限候选仍未通过；保留报告，禁止签发bit')


if __name__ == '__main__':
    main()
