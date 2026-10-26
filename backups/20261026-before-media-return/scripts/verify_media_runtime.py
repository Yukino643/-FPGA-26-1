"""运行时媒体整合验证；提取当前top真实连线，Windows原生仿真。"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/media_runtime/test'
IV='C:/iverilog/bin/iverilog.exe'
VVP='C:/iverilog/bin/vvp.exe'
SOURCE=['rtl/sd/media_source.v','rtl/sd/media_fat_service.v','rtl/sd/raw_video_player.v',
        'rtl/sd/sd_card_bmp_g.v','rtl/sd/sd_card_bmp.v','rtl/sd/bmp_read_g.v',
        'rtl/sd/fat32_bmp_index.v','rtl/sd/fat32_file_sector_mapper.v']
PIPE=['sim/tb_media_pipeline.v','sim/media_card_model.v',*SOURCE,
      'rtl/ctrl/media_runtime_ctrl.v','rtl/ctrl/reset_sync.v','rtl/video/video_frame_commit.v',
      'rtl/video/transition_ctrl.v','rtl/sd/src_packer.v','rtl/sd/source_scaler_gate.v',
      'rtl/sd/frame_read_write.v','rtl/sd/frame_fifo_write.v','rtl/pll/afifo_16_32_256.v',
      'rtl/video/resize_frame_720.v','rtl/video/display_stream_720.v','rtl/video/disp_mixer_565.v',
      'rtl/mem/disp_read_engine.v','rtl/mem/afifo_simple.v','rtl/mem/mem_mpu.v',
      'rtl/video/video_timing_gen.v','sim/sdram_beh.v','rtl/sd/sd_arbiter.v',
      'rtl/audio/wav_read.v','rtl/audio/audio_player.v','rtl/audio/media_audio_router.v']

def section(text,first,last):
    start=text.index(first)
    return text[start:text.index(last,start)]

def instance(text,marker):
    start=text.index(marker)
    return text[start:text.index(');',start)+2]

def prepare():
    OUT.mkdir(parents=True,exist_ok=True)
    for name in ('header.hex','frame0.hex','frame1.hex'):
        shutil.copy2(ROOT/'build/raw_video/media/big-blue-fish'/name,OUT/name)
    top=(ROOT/'rtl/top/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
    blocks=[section(top,'reg [1:0] retained_front_sd;','// 媒体音轨元数据结束'),instance(top,'media_runtime_ctrl #('),
            section(top,'reg [2:0] commit_sync;','// vs_rise toggle'),
            section(top,'// mem_clk 域把 write_finish 单拍转成 toggle','// ===================== TF多图扫描'),
            section(top,'// 同一稳定ACK','media_source #('),
            instance(top,'media_source #('),instance(top,'src_packer u_src_packer('),
            instance(top,'source_scaler_gate u_source_scaler_gate ('),
            instance(top,'resize_frame_720 u_resize_frame('),
            section(top,'wire video_read_en_unused;','sdram U3('),
            section(top,'// 两种提交策略','// ---- mem_mpu:'),
            section(top,'wire        mpu_A_cv','// 首图提交前黑屏'),
            section(top,'reg [1:0] display_valid_sync_v;','// 仅源解析'),
            instance(top,'sd_arbiter #('),
            section(top,'reg wav_scan_start_r, wav_load_start_r;','audio_player #('),
            instance(top,'audio_player #(')]
    target=OUT/'reg_media_pipeline.vh'
    content='\n'.join(blocks)
    if not target.exists() or target.read_text(encoding='utf-8')!=content:
        temporary=OUT/f'reg_media_pipeline.{os.getpid()}.tmp'
        temporary.write_text(content,encoding='utf-8',newline='\n')
        temporary.replace(target)

def command(name,args,env=None,timeout=600):
    with (OUT/(name+'.log')).open('wb') as log:
        result=subprocess.run(args,cwd=OUT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
    text=(OUT/(name+'.log')).read_text(encoding='utf-8',errors='replace')
    if result.returncode:
        raise RuntimeError(name+': '+text[-5000:])
    return text

def unit(name,files,params=()):
    command(name+'_compile',[IV,'-g2005','-DSIMULATION','-s','tb_'+name,'-I',str(OUT),
        '-o',str(OUT/(name+'.vvp')),*params,*[str(ROOT/f) for f in files]])
    text=command(name,[VVP,str(OUT/(name+'.vvp'))])
    if 'PASS' not in text or 'FAIL' in text or 'ERROR' in text: raise RuntimeError(text[-4000:])
    print(text,flush=True)

def compiled_pipeline(case):
    vroot=ROOT/'build/raw_video/tools/verilator_py/verilator'
    cxx=Path('D:/minGW64/mingw64/bin/g++.exe')
    obj=OUT/f'compiled{case}'
    obj.mkdir(exist_ok=True)
    env=os.environ.copy();env['VERILATOR_ROOT']=vroot.as_posix()
    env['PATH']=str(cxx.parent)+os.pathsep+env['PATH']
    command(f'pipeline{case}_generate',[str(vroot/'bin/verilator_bin.exe'),'--cc','--main','--timing','--assert',
        '-DSIMULATION','-Wno-fatal','--top-module','tb_media_pipeline',f'-GCASE={case}',
        '--Mdir',str(obj),'-I'+str(OUT),*[str(ROOT/f) for f in PIPE]],env,180)
    print(f'pipeline{case} Verilator generated',flush=True)
    # Windows重定向stdout默认为全缓冲；长仿真也应实时保留阶段证据。
    main=obj/'Vtb_media_pipeline__main.cpp'
    source=main.read_text(encoding='utf-8')
    source,count=re.subn(r'(int main\([^\n]+\) \{)',
        r'\1\n    std::setvbuf(stdout, nullptr, _IONBF, 0);',source,count=1)
    if count!=1: raise RuntimeError('Verilator main入口不匹配，无法打开实时日志')
    source='#include <cstdio>\n'+source
    main.write_text(source,encoding='utf-8',newline='\n')
    inc=vroot/'include';exe=obj/'pipeline.exe'
    command(f'pipeline{case}_compile',[str(cxx),'-std=c++20','-O2','-pthread','-DVL_TIME_CONTEXT',
        '-I'+str(inc),'-I'+str(inc/'vltstd'),'-I'+str(obj),*[str(p) for p in sorted(obj.glob('*.cpp'))],
        *[str(inc/n) for n in ('verilated.cpp','verilated_timing.cpp','verilated_threads.cpp')],'-o',str(exe)],env,600)
    print(f'pipeline{case} C++ compiled',flush=True)
    text=command(f'pipeline{case}',[str(exe)],env,3600)
    if 'PASS media_pipeline' not in text or 'FAIL' in text or 'ERROR' in text: raise RuntimeError(text[-4000:])
    print(text,flush=True)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--pipeline',type=int)
    parser.add_argument('--unit-only',action='store_true')
    args=parser.parse_args();prepare();started=time.monotonic()
    # 绑定真实依赖，独立测试台的编辑不能使长时间整机验证作废。
    dependencies=set(PIPE)|{'rtl/top/top_tf_hdmi_audio.v','sim/tb_media_runtime_ctrl.v',
        'sim/tb_media_menu.v','sim/tb_media_renderer.v','rtl/ctrl/monitor_menu_ctrl.v',
        'rtl/video/monitor_menu_renderer.v','rtl/video/monitor_cjk_rom.v',
        'rtl/ctrl/font_rom_ascii.v','sim/fixtures/media_cjk_rows.hex'}
    inputs={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sorted(dependencies)}
    if args.pipeline is None:
        unit('media_runtime_ctrl',['sim/tb_media_runtime_ctrl.v','rtl/ctrl/media_runtime_ctrl.v','rtl/ctrl/reset_sync.v','rtl/video/video_frame_commit.v'])
        unit('media_menu',['sim/tb_media_menu.v','rtl/ctrl/monitor_menu_ctrl.v'])
        unit('media_renderer',['sim/tb_media_renderer.v','rtl/video/monitor_menu_renderer.v',
            'rtl/video/monitor_cjk_rom.v','rtl/ctrl/font_rom_ascii.v'])
    if not args.unit_only:
        for case in ([args.pipeline] if args.pipeline is not None else [0,1,2,7]): compiled_pipeline(case)
    for name,digest in inputs.items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest: raise RuntimeError('验证中输入改变：'+name)
    name='unit' if args.unit_only else f'pipeline{args.pipeline}' if args.pipeline is not None else 'all'
    (OUT/(name+'_results.json')).write_text(json.dumps({'pass':True,'seconds':time.monotonic()-started,
        'inputs_sha256':inputs},indent=2)+'\n',encoding='utf-8',newline='\n')

if __name__=='__main__': main()
