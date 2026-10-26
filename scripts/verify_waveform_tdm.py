"""分时节点读取与原组合读取逐位等价；结果绑定实际输入 SHA。"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/media_audio/waveform-tdm'
FILES = ['sim/tb_waveform_tdm.v', 'rtl/video/promax_audio_waveform.v']


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    inputs = {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in FILES}
    commands = [
        ['C:/iverilog/bin/iverilog.exe', '-g2005', '-DSIMULATION', '-s', 'tb_waveform_tdm',
         '-o', str(OUT/'waveform_tdm.vvp'), *[str(ROOT/name) for name in FILES]],
        ['C:/iverilog/bin/vvp.exe', str(OUT/'waveform_tdm.vvp')],
    ]
    for label, command in zip(('compile', 'simulation'), commands):
        result = subprocess.run(command, cwd=OUT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=120)
        (OUT/f'{label}.log').write_bytes(result.stdout)
        output = result.stdout.decode('utf-8', errors='strict')
        if result.returncode or any(word in output for word in ('FAIL', 'FATAL', 'ERROR')):
            raise RuntimeError(f'{label} failed:\n{output}')
    if 'TB_WAVEFORM_TDM PASS' not in output:
        raise RuntimeError('Missing waveform equivalence PASS')
    for name, expected in inputs.items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != expected:
            raise RuntimeError('Input changed during test: '+name)
    (OUT/'results.json').write_text(json.dumps({'pass': True, 'inputs_sha256': inputs},
        indent=2)+'\n', encoding='utf-8', newline='\n')
    print(output, end='')


if __name__ == '__main__':
    main()
