"""返回首图的VS计时与默认行为逐拍等价；旧参考固定为稳定版归档。"""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/media_return/transition'
BASE=ROOT/'backups/20261026-before-media-return/rtl/video/transition_ctrl.v'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest=json.loads((ROOT/'backups/20261026-before-media-return/manifest.json').read_text(encoding='utf-8'))
    if digest(BASE)!=manifest['files']['rtl/video/transition_ctrl.v']:
        raise RuntimeError('旧转场参考已改变')
    OUT.mkdir(parents=True,exist_ok=True)
    reference=OUT/'transition_ctrl_legacy.v'
    old=BASE.read_bytes()
    if old.count(b'module transition_ctrl #(')!=1:
        raise RuntimeError('旧转场模块入口不唯一')
    reference.write_bytes(old.replace(b'module transition_ctrl #(',b'module transition_ctrl_legacy #('))
    names=['scripts/verify_media_return.py','sim/tb_media_return_transition.v',
           'rtl/video/transition_ctrl.v',BASE.relative_to(ROOT).as_posix()]
    inputs={n:digest(ROOT/n) for n in names}
    commands=[['C:/iverilog/bin/iverilog.exe','-g2005','-s','tb_media_return_transition',
               '-o',str(OUT/'test.vvp'),str(ROOT/names[1]),str(ROOT/names[2]),str(reference)],
              ['C:/iverilog/bin/vvp.exe',str(OUT/'test.vvp')]]
    for label,cmd in zip(['compile','simulation'],commands):
        r=subprocess.run(cmd,cwd=OUT,capture_output=True,timeout=60)
        output=(r.stdout+r.stderr).decode('utf-8',errors='strict')
        (OUT/(label+'.log')).write_text(output,encoding='utf-8',newline='\n')
        if r.returncode or re.search(r'\bFAIL\b|\bFATAL\b|\bERROR\b',output):
            raise RuntimeError(label+': '+output)
    if 'TB_MEDIA_RETURN_TRANSITION PASS slow=32 fast=8 saved_vs=24 checks=5' not in output:
        raise RuntimeError('缺少完整转场验证标记')
    for n,h in inputs.items():
        if digest(ROOT/n)!=h:raise RuntimeError('验证中输入改变：'+n)
    (OUT/'results.json').write_text(json.dumps({'pass':True,'inputs_sha256':inputs,
        'slow_blend_vs':32,'return_blend_vs':8,'saved_vs':24,'saved_seconds_at_60hz':0.4},indent=2)+'\n',
        encoding='utf-8',newline='\n')
    print(output,end='')


if __name__=='__main__':main()
