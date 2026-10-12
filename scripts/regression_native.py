"""PowerShell原生回归入口；旧模块覆盖+当前720p链路，不启动bash/WSL。"""
from pathlib import Path
import argparse
import re
import subprocess
import shlex
import json
import shutil
import time
import hashlib
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
PY='D:/miniconda3/python.exe'
IV='C:/iverilog/bin/iverilog.exe'
VVP='C:/iverilog/bin/vvp.exe'
OUTPUT=ROOT/'build/720p/regression'

def extract(text,first,last):
    start=text.index(first)
    return text[start:text.index(last,start)]

def extract_instance(text,marker):
    start=text.index(marker)
    return text[start:text.index('\n);',start)+3]

def prepare():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    fixture=(ROOT/'sim/fixtures/top_640_baseline.v.txt').read_text(encoding='utf-8')
    blocks=[extract(fixture,'reg [2:0] commit_sync;','// vs_rise toggle'),
            extract(fixture,'reg [2:0] scaler_done_sync;','// ===================== TF 多图扫描'),
            extract(fixture,'transition_ctrl #(','// ---- mem_mpu:')]
    (OUTPUT/'reg_display_commit.vh').write_text('\n'.join(blocks),encoding='utf-8',newline='\n')
    (OUTPUT/'reg_source_scaler_gate.vh').write_text(extract_instance(fixture,'source_scaler_gate u_source_scaler_gate ('),encoding='utf-8',newline='\n')
    blocks=[extract(fixture,'reg de_d1, vs_d1;','// 缩放完成 toggle')]
    for marker in ('osd_engine u_osd(', 'promax_audio_waveform #(', 'color_adjust u_color_adjust(',
                   'emergency_render u_emergency_render(', 'video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480('):
        blocks.append(extract_instance(fixture,marker))
    (OUTPUT/'reg_video_pipeline.vh').write_text('\n'.join(blocks),encoding='utf-8',newline='\n')
    (OUTPUT/'reg_top_scaler_block.vh').write_text(extract(fixture,'wire scaler_start_tgl;','wire video_read_en_unused;'),encoding='utf-8',newline='\n')
    # 当前720p顶层的图层流水，真实连接与回归同步。
    top=(ROOT/'rtl/top/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
    blocks=[extract(top,'reg de_d1, vs_d1;','// 缩放完成 toggle')]
    for marker in ('osd_engine_720 u_osd(', 'promax_audio_waveform #(', 'color_adjust u_color_adjust(',
                   'emergency_render #(', 'video_rgb_to_axis_640x480 #('):
        blocks.append(extract_instance(top,marker))
    (OUTPUT/'reg_video_pipeline_720.vh').write_text('\n'.join(blocks),encoding='utf-8',newline='\n')
    blocks=[extract(top,'reg [2:0] commit_sync;','// vs_rise toggle'),
            extract(top,'// 显示提交握手','// ===================== TF多图扫描'),
            extract(top,'transition_ctrl #(','// ---- mem_mpu:')]
    (OUTPUT/'reg_display_commit_720.vh').write_text('\n'.join(blocks),encoding='utf-8',newline='\n')
    (OUTPUT/'reg_source_gate_720.vh').write_text(extract_instance(top,'source_scaler_gate u_source_scaler_gate ('),encoding='utf-8',newline='\n')
    for file in (ROOT/'sim').glob('*.hex'): shutil.copy2(file,OUTPUT/file.name)
    fixtures=OUTPUT/'fixtures'
    fixtures.mkdir(exist_ok=True)
    for file in (ROOT/'sim/fixtures').glob('*.hex'): shutil.copy2(file,fixtures/file.name)
    subprocess.run([PY,'-X','utf8',str(ROOT/'scripts/extract_pll_model.py'),'--output',str(OUTPUT/'eg_phy_pll_functional.v')],check=True)

def command(args,name,timeout=1800):
    log=OUTPUT/(name+'.log')
    started=time.monotonic()
    with log.open('wb') as dst:
        result=subprocess.run(args,cwd=OUTPUT,stdout=dst,stderr=subprocess.STDOUT,timeout=timeout)
    text=log.read_bytes().decode('utf-8',errors='replace')
    if result.returncode:
        raise RuntimeError(f'{name}: 返回{result.returncode}; {text[-2000:]}')
    return text,time.monotonic()-started

def sim(name,args,reuse=False):
    files=[]
    for arg in args:
        if arg.endswith(('.v','.vh')): files.append((ROOT/'sim'/arg).resolve().as_posix())
        elif arg=='../rtl/video': files.append((ROOT/'rtl/video').as_posix())
        else: files.append(arg)
    out=(OUTPUT/(name+'.vvp')).as_posix()
    fingerprint=hashlib.sha256(json.dumps(args).encode('utf-8'))
    dependencies=[Path(file) for file in files if file.endswith(('.v','.vh'))]
    dependencies+=list((ROOT/'rtl').rglob('*.vh'))+list((ROOT/'rtl').rglob('*.hex'))
    dependencies+=list(OUTPUT.glob('reg_*.vh'))+list((ROOT/'sim/fixtures').glob('*.hex'))
    dependencies+=list((ROOT/'sim').glob('*.hex'))+list(OUTPUT.glob('*.hex'))
    for file in sorted(set(dependencies)):
        fingerprint.update(file.as_posix().encode('utf-8'));fingerprint.update(file.read_bytes())
    signature=fingerprint.hexdigest()
    stamp=OUTPUT/(name+'.pass.sha256')
    if reuse and stamp.is_file() and stamp.read_text(encoding='ascii')==signature:
        print(f'[REG][PASS] {name} verified input hash unchanged',flush=True)
        return
    command([IV,'-g2005','-I',OUTPUT.as_posix(),'-I',(ROOT/'sim').as_posix(),'-o',out,*files],name+'_compile')
    text,elapsed=command([VVP,out],name)
    if 'PASS' not in text or re.search(r'\bFAIL\b|\bERROR\b',text):
        raise RuntimeError(f'{name}: {text[-2000:]}')
    stamp.write_text(signature,encoding='ascii',newline='\n')
    print(f'[REG][PASS] {name} ({elapsed:.1f}s)',flush=True)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--full',action='store_true')
    parser.add_argument('--sim-only',action='store_true')
    parser.add_argument('--filter')
    parser.add_argument('--reuse',action='store_true',help='只复用当前输入hash完全一致的通过结果')
    args=parser.parse_args()
    prepare()
    results=[]
    def run(name,action):
        if args.filter and re.search(args.filter,name) is None: return
        try: action(); results.append({'name':name,'pass':True})
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            print(f'[REG][FAIL] {name}: {exc}',flush=True)
            results.append({'name':name,'pass':False,'error':str(exc)})
    run('constraints',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/check_constraints.py')],'constraints'))
    run('font720_generated',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/gen_font_720.py'),'--check'],'font720_generated'))
    run('legacy_generated',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/verify_generated.py'),'--output',str(OUTPUT/'generated')],'legacy_generated'))
    # 原有每个模块/边界用例保留，旧顶层提取用例明确作为640基线fixture回归。
    shell=(ROOT/'scripts/regression.sh').read_text(encoding='utf-8')
    for line in shell.splitlines():
        if line.startswith('run_sim '):
            parts=shlex.split(line)[1:]; name=parts.pop(0)
            run('legacy_'+name,lambda name=name,parts=parts:sim(name,parts,args.reuse))
    extra={
        'clock720':['-s','tb_video_clock_720','tb_video_clock_720.v','../rtl/pll/ref27_pll.v','../rtl/pll/video_pll.v',
                    (OUTPUT/'eg_phy_pll_functional.v').as_posix()],
        'mixer565':['-s','tb_mixer565','tb_mixer565.v','../rtl/video/disp_mixer_565.v'],
        'pipeline720':['-DSIMULATION','-I','../rtl/video','tb_video_pipeline_720.v','../rtl/video/osd_engine_720.v',
                       '../rtl/video/osd_text_720.v','../rtl/video/font_rom_720.v','../rtl/video/promax_audio_waveform.v',
                       '../rtl/video/color_adjust.v','../rtl/video/emergency_render.v','../rtl/video/video_rgb_to_axis_640x480.v'],
        'display720':['-DSIMULATION','tb_display720.v','../rtl/video/display_stream_720.v','../rtl/video/disp_mixer_565.v',
                      '../rtl/mem/disp_read_engine.v','../rtl/mem/afifo_simple.v','../rtl/mem/mem_mpu.v',
                      '../rtl/video/video_timing_gen.v','../rtl/video/transition_ctrl.v','sdram_beh.v'],
        'waveform720':['-DSIMULATION','tb_audio_waveform_720.v','../rtl/video/promax_audio_waveform.v'],
        'writer720':['tb_writer720.v','../rtl/sd/frame_fifo_write.v'],
        'bmp_exact720':['tb_bmp_exact720.v','../rtl/sd/bmp_read_g.v'],
        'commit720':['-s','tb_commit720','tb_commit720.v','../rtl/video/transition_ctrl.v','../rtl/sd/source_scaler_gate.v',
                     '../rtl/sd/sd_card_bmp.v','../rtl/sd/sd_card_bmp_g.v','../rtl/sd/bmp_read_g.v','../rtl/sd/fat32_bmp_index.v','../rtl/sd/fat32_file_sector_mapper.v'],
        'audio720':['-DSIMULATION','tb_audio720.v','../rtl/audio/audio_player.v','../rtl/mem/afifo_simple.v'],
    }
    for name,parts in extra.items(): run(name,lambda name=name,parts=parts:sim(name,parts,args.reuse))
    for ppm in OUTPUT.glob('*.ppm'): Image.open(ppm).save(ppm.with_suffix('.png'))
    sim_pass=all(item['pass'] for item in results)
    if args.full and sim_pass:
        run('TD_BUILD',lambda:command([PY,'-X','utf8',str(ROOT/'td_prj/build_native.py'),'--output',str(ROOT/'build/720p/td')],'td_build',3600))
    if not args.sim_only:
        run('CURRENT_SOURCE_REPORTS',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/check_reports.py')],'current_source_reports'))
    (OUTPUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8',newline='\n')
    passed=sum(item['pass'] for item in results)
    print(f'[REG] passed={passed}/{len(results)} output={OUTPUT}',flush=True)
    if passed!=len(results): raise SystemExit(1)

if __name__=='__main__': main()
