"""BMP 时序优化逐拍等价验证；参考必须是修改前的固定归档。"""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/media_audio/bmp-timing'
REFERENCE = OUT / 'bmp_read_g_ref.v'
REFERENCE_SHA = '7fe33b4ee7e5a6aa132ccedf67ad928b7237347c8a02892d7fb4f7bc7a41e6de'
BASELINE = ROOT / 'build/media_audio/td-bpb-row/physical-final/bmp_read_g.v.before'
BASELINE_SHA = '3decadb2e75346fd7c44717a1840a3b0a6f514a5cb4c1c1e1e958ce49b6a8941'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if not REFERENCE.exists():
        if digest(BASELINE) != BASELINE_SHA:
            raise RuntimeError('修改前 BMP 归档 SHA 不符，拒绝生成参考模型')
        data = BASELINE.read_bytes()
        if data.count(b'module bmp_read_g #') != 1:
            raise RuntimeError('参考模块入口不唯一')
        REFERENCE.write_bytes(data.replace(b'module bmp_read_g #', b'module bmp_read_g_ref #'))
    if digest(REFERENCE) != REFERENCE_SHA:
        raise RuntimeError('BMP 参考模型不是已归档的旧实现')
    files = ['scripts/verify_bmp_timing.py', 'sim/tb_bmp_timing_equiv.v',
             'rtl/sd/bmp_read_g.v', REFERENCE.relative_to(ROOT).as_posix()]
    inputs = {name: digest(ROOT/name) for name in files}
    for gap in (0, 1, 7):
        exe = OUT / f'equiv{gap}.vvp'
        commands = [
            ['C:/iverilog/bin/iverilog.exe', '-g2005', '-s', 'tb_bmp_timing_equiv',
             f'-Ptb_bmp_timing_equiv.BYTE_GAP={gap}', '-o', str(exe),
             str(ROOT/'sim/tb_bmp_timing_equiv.v'), str(ROOT/'rtl/sd/bmp_read_g.v'), str(REFERENCE)],
            ['C:/iverilog/bin/vvp.exe', str(exe)],
        ]
        for label, command in zip(('compile', 'simulation'), commands):
            result = subprocess.run(command, cwd=OUT, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=120)
            (OUT/f'equiv{gap}_{label}.log').write_bytes(result.stdout)
            output = result.stdout.decode('utf-8', errors='strict')
            if result.returncode or re.search(r'\b(?:FAIL|FATAL|ERROR)\b', output):
                raise RuntimeError(f'BMP gap={gap} {label}:\n{output}')
        if not re.search(rf'TB_BMP_TIMING_EQUIV PASS cases=13 cycles=\d+ gap={gap} compares=300163', output):
            raise RuntimeError(f'BMP gap={gap} 缺少完整验证标记')
        print(output, end='', flush=True)
    for name, expected in inputs.items():
        if digest(ROOT/name) != expected:
            raise RuntimeError('验证中输入改变：'+name)
    (OUT/'results.json').write_text(json.dumps({'pass': True, 'inputs_sha256': inputs,
        'gaps': [0, 1, 7], 'reference_sha256': REFERENCE_SHA}, indent=2)+'\n',
        encoding='utf-8', newline='\n')


if __name__ == '__main__':
    main()
