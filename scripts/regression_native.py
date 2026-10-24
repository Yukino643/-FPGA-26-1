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
from concurrent.futures import ThreadPoolExecutor
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
    # 只提取可读的真实计数/刷新请求前缀；不解密IP，也不重写其计时逻辑。
    refresh=(ROOT/'rtl/mem/include/sdr_init_ref.enc.v').read_text(encoding='utf-8')
    prefix=refresh.split('`pragma protect begin_protected',1)[0]
    if 'assign Sdr_ref_req=ref_req | App_ref_req;' not in prefix:
        raise RuntimeError('SDRAM刷新前缀结构已变化，请重新核对测试边界')
    (OUTPUT/'reg_sdram_refresh.v').write_text(prefix+'\nendmodule\n',encoding='utf-8',newline='\n')
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
    (OUTPUT/'reg_wav_startup.vh').write_text(
        extract(top,'reg wav_scan_start_r, wav_load_start_r;','audio_player #('),
        encoding='utf-8',newline='\n')
    (OUTPUT/'reg_wav_arbiter.vh').write_text(extract_instance(top,'sd_arbiter #('),
        encoding='utf-8',newline='\n')
    (OUTPUT/'reg_wav_startup_legacy.vh').write_text(
        (ROOT/'sim/fixtures/wav_startup_legacy.v.txt').read_text(encoding='utf-8'),
        encoding='utf-8',newline='\n')
    # 核对当前顶层的真实邮箱/档位译码/颜色实例，避免测试桩掩盖错接 HDMI。
    screen_blocks=[extract(top,'// HDMI-B 专用参数','wire        cfg_commit_seen_video;'),
                   extract_instance(top,'monitor_config_regs u_monitor_config_regs('),
                   extract_instance(top,'color_adjust u_color_adjust(')]
    (OUTPUT/'reg_screen_color.vh').write_text('\n'.join(screen_blocks),encoding='utf-8',newline='\n')
    (OUTPUT/'reg_monitor_pipeline.vh').write_text(
        extract(top,'wire mon_hs, mon_vs, mon_de;','// HDMI-A is intentionally'),
        encoding='utf-8',newline='\n')
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
    blocks=[extract(top,'// mem_clk 域把 write_finish 单拍转成 toggle', '// 源帧完整后启动缩放'),
            extract_instance(top,'src_packer u_src_packer('),
            extract_instance(top,'source_scaler_gate u_source_scaler_gate ('),
            extract_instance(top,'resize_frame_720 u_resize_frame('),
            extract(top,'wire video_read_en_unused;','sdram U3(')]
    (OUTPUT/'reg_multisize_source.vh').write_text('\n'.join(blocks),encoding='utf-8',newline='\n')
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
    # 刷新测试确实include了这个.v宏头；其内容也必须纳入缓存。
    if name.startswith('sdram_refresh'):
        dependencies.append(ROOT/'rtl/mem/include/global_def.v')
    dependencies+=list(OUTPUT.glob('reg_*.vh'))+list((ROOT/'sim/fixtures').glob('*.hex'))
    dependencies+=list((ROOT/'sim').glob('*.hex'))+list(OUTPUT.glob('*.hex'))
    # 新增的WAV提取头只属于启动用例。保留完整旧签名作为缓存迁移候选，
    # 但仅当所有输入/旧生成头都没有引用reg_wav_时，才允许匹配去掉这些新头的签名。
    # 这不排除任何RTL/字库/约束依赖，避免未改菜单因新增无关头而重复渲染。
    previous_fingerprint=fingerprint.copy()
    wav_headers={file for file in dependencies if file.name.startswith('reg_wav_')}
    references_wav=any('reg_wav_' in file.read_text(encoding='utf-8')
                       for file in set(dependencies)-wav_headers
                       if file.suffix in ('.v','.vh'))
    for file in sorted(set(dependencies)):
        encoded_path=file.as_posix().encode('utf-8')
        data=file.read_bytes()
        fingerprint.update(encoded_path);fingerprint.update(data)
        if file not in wav_headers:
            previous_fingerprint.update(encoded_path);previous_fingerprint.update(data)
    signature=fingerprint.hexdigest()
    accepted_signatures={signature}
    if not references_wav:
        accepted_signatures.add(previous_fingerprint.hexdigest())
    stamp=OUTPUT/(name+'.pass.sha256')
    if reuse and stamp.is_file() and stamp.read_text(encoding='ascii') in accepted_signatures:
        print(f'[REG][PASS] {name} verified input hash unchanged',flush=True)
        return
    command([IV,'-g2005','-I',OUTPUT.as_posix(),'-I',(ROOT/'sim').as_posix(),'-o',out,*files],name+'_compile')
    text,elapsed=command([VVP,out],name)
    if 'PASS' not in text or re.search(r'\bFAIL\b|\bERROR\b',text):
        raise RuntimeError(f'{name}: {text[-2000:]}')
    stamp.write_text(signature,encoding='ascii',newline='\n')
    print(f'[REG][PASS] {name} ({elapsed:.1f}s)',flush=True)

def monitor_rasters(parts,reuse):
    # 场景输出文件互不重叠；四个原生仿真进程检查同一RTL，不裁掉任何像素。
    groups=((0,3),(4,6),(7,9),(10,12))
    names=[f'monitor_menu_renderer_{n}' for n in range(len(groups))]
    with ThreadPoolExecutor(max_workers=4) as pool:
        jobs=[pool.submit(sim,name,[
            f'-Ptb_monitor_menu_renderer.FIRST_SCENE={first}',
            f'-Ptb_monitor_menu_renderer.LAST_SCENE={last}']+parts,reuse)
            for name,(first,last) in zip(names,groups)]
        for job in jobs:job.result()
    (OUTPUT/'monitor_menu_renderer.log').write_text(
        '\n'.join((OUTPUT/(name+'.log')).read_text(encoding='utf-8') for name in names),
        encoding='utf-8',newline='\n')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--full',action='store_true')
    parser.add_argument('--sim-only',action='store_true')
    parser.add_argument('--filter')
    parser.add_argument('--reuse',action='store_true',help='只复用当前输入hash完全一致的通过结果')
    parser.add_argument('--subtitle-state-only',action='store_true',
                        help='保留字幕全部逐VS/像素断言，仅关闭整圈大体积栅格导出')
    parser.add_argument('--jobs',type=int,default=1,choices=(1,2,3,4),help='额外独立仿真并行数；各用例独立输出')
    args=parser.parse_args()
    prepare()
    results=[]
    def save_results(complete=False):
        # 每个用例结束即落盘；中断后不能继续留下上一轮的两项结果冒充本轮进度。
        (OUTPUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
        (OUTPUT/'run_status.json').write_text(json.dumps({
            'complete':complete,'filter':args.filter,'sim_only':args.sim_only,
            'subtitle_cycle_raster_export':not args.subtitle_state_only,
            'finished':len(results),'passed':sum(item['pass'] for item in results)
        },ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    save_results()
    def run(name,action):
        if args.filter and re.search(args.filter,name) is None: return
        try: action(); results.append({'name':name,'pass':True})
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            print(f'[REG][FAIL] {name}: {exc}',flush=True)
            results.append({'name':name,'pass':False,'error':str(exc)})
        save_results()
    run('constraints',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/check_constraints.py')],'constraints'))
    run('font720_generated',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/gen_font_720.py'),'--check'],'font720_generated'))
    run('monitor_font_generated',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/gen_monitor_cjk.py'),'--check'],'monitor_font_generated'))
    run('legacy_generated',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/verify_generated.py'),'--output',str(OUTPUT/'generated')],'legacy_generated'))
    # 原有每个模块/边界用例保留，旧顶层提取用例明确作为640基线fixture回归。
    shell=(ROOT/'scripts/regression.sh').read_text(encoding='utf-8')
    for line in shell.splitlines():
        if line.startswith('run_sim '):
            parts=shlex.split(line)[1:]; name=parts.pop(0)
            run('legacy_'+name,lambda name=name,parts=parts:sim(name,parts,args.reuse))
    extra={
        'audio_volume':['-s','tb_audio_volume','tb_audio_volume.v','../rtl/audio/pcm_volume_control.v'],
        'audio_menu':['-s','tb_audio_menu','tb_audio_menu.v','../rtl/ctrl/monitor_menu_ctrl.v','../rtl/ctrl/monitor_config_regs.v'],
        'wav_index':['-s','tb_wav_index','tb_wav_index.v','../rtl/sd/fat32_bmp_index.v'],
        'wav_startup':['-DSIMULATION','-s','tb_wav_startup','tb_wav_startup.v',
                       '../rtl/sd/fat32_bmp_index.v','../rtl/sd/sd_arbiter.v','../rtl/audio/wav_read.v'],
        'wav_startup_legacy':['-DSIMULATION','-s','tb_wav_startup','-Ptb_wav_startup.LEGACY=1','tb_wav_startup.v',
                       '../rtl/sd/fat32_bmp_index.v','../rtl/sd/sd_arbiter.v','../rtl/audio/wav_read.v'],
        'wav_startup_bad':['-DSIMULATION','-s','tb_wav_startup','-Ptb_wav_startup.BAD_HEADER=1','tb_wav_startup.v',
                       '../rtl/sd/fat32_bmp_index.v','../rtl/sd/sd_arbiter.v','../rtl/audio/wav_read.v'],
        'wav_startup_missing':['-DSIMULATION','-s','tb_wav_startup','-Ptb_wav_startup.NO_WAV=1','tb_wav_startup.v',
                       '../rtl/sd/fat32_bmp_index.v','../rtl/sd/sd_arbiter.v','../rtl/audio/wav_read.v'],
        'sdram_refresh':['-I',(ROOT/'rtl/mem/include').as_posix(),'-s','tb_sdram_refresh',
                         'tb_sdram_refresh.v',(OUTPUT/'reg_sdram_refresh.v').as_posix()],
        'sdram_refresh_disabled':['-I',(ROOT/'rtl/mem/include').as_posix(),'-s','tb_sdram_refresh',
                         '-Ptb_sdram_refresh.AUTO_REFRESH=0','tb_sdram_refresh.v',
                         (OUTPUT/'reg_sdram_refresh.v').as_posix()],
        'monitor_tmds':['-s','tb_hdmi_video_only_640x480','tb_hdmi_video_only_640x480.v',
                        '../rtl/hdmi/hdmi_video_only_640x480.v','../rtl/hdmi/hdmi_tmds_channel_encoder.v'],
        'resize640':['-DSIMULATION','-s','tb_resize_frame_720','tb_resize_frame_720.v','../rtl/video/resize_frame_720.v'],
        'resize800':['-DSIMULATION','-s','tb_resize_frame_720','-Ptb_resize_frame_720.W=800','-Ptb_resize_frame_720.H=600',
                     'tb_resize_frame_720.v','../rtl/video/resize_frame_720.v'],
        'resize720':['-DSIMULATION','-s','tb_resize_frame_720','-Ptb_resize_frame_720.W=1280','-Ptb_resize_frame_720.H=720',
                     'tb_resize_frame_720.v','../rtl/video/resize_frame_720.v'],
        'resize_odd':['-DSIMULATION','-s','tb_resize_frame_720','-Ptb_resize_frame_720.W=3','-Ptb_resize_frame_720.H=2',
                     'tb_resize_frame_720.v','../rtl/video/resize_frame_720.v'],
        'resize_tiny':['-DSIMULATION','-s','tb_resize_frame_720','-Ptb_resize_frame_720.W=1','-Ptb_resize_frame_720.H=1',
                     'tb_resize_frame_720.v','../rtl/video/resize_frame_720.v'],
        'resize_tall':['-DSIMULATION','-s','tb_resize_frame_720','-Ptb_resize_frame_720.W=1','-Ptb_resize_frame_720.H=720',
                     'tb_resize_frame_720.v','../rtl/video/resize_frame_720.v'],
        'resize_wide':['-DSIMULATION','-s','tb_resize_frame_720','-Ptb_resize_frame_720.W=1280','-Ptb_resize_frame_720.H=1',
                     'tb_resize_frame_720.v','../rtl/video/resize_frame_720.v'],
        'resize_lifecycle':['-DSIMULATION','-s','tb_resize_frame_720','-Ptb_resize_frame_720.FLOW=1',
                     'tb_resize_frame_720.v','../rtl/video/resize_frame_720.v'],
        'source_multisize640':['-DSIMULATION','-s','tb_top_multisize','tb_top_multisize.v',
                     '../rtl/sd/frame_read_write.v','../rtl/sd/frame_fifo_write.v','../rtl/sd/src_packer.v',
                     '../rtl/sd/source_scaler_gate.v','../rtl/video/resize_frame_720.v','../rtl/pll/afifo_16_32_256.v'],
        'source_multisize_odd':['-DSIMULATION','-s','tb_top_multisize','-Ptb_top_multisize.W=3','-Ptb_top_multisize.H=2',
                     'tb_top_multisize.v','../rtl/sd/frame_read_write.v','../rtl/sd/frame_fifo_write.v','../rtl/sd/src_packer.v',
                     '../rtl/sd/source_scaler_gate.v','../rtl/video/resize_frame_720.v','../rtl/pll/afifo_16_32_256.v'],
        'monitor_pipeline':['-s','tb_monitor_pipeline','tb_monitor_pipeline.v','../rtl/video/monitor_menu_renderer.v','../rtl/video/monitor_cjk_rom.v',
                            '../rtl/ctrl/font_rom_ascii.v','../rtl/video/video_timing_gen.v'],
        'emergency_raster':['-s','tb_emergency_render','tb_emergency_render.v','../rtl/video/emergency_render.v'],
        'monitor_menu_renderer':['-s','tb_monitor_menu_renderer','tb_monitor_menu_renderer.v',
                                 '../rtl/video/monitor_menu_renderer.v','../rtl/video/monitor_cjk_rom.v','../rtl/ctrl/font_rom_ascii.v'],
        'monitor_menu_ctrl':['-s','tb_monitor_menu_ctrl','tb_monitor_menu_ctrl.v','../rtl/ctrl/monitor_menu_ctrl.v'],
        'monitor_config_regs':['-s','tb_monitor_config_regs','tb_monitor_config_regs.v','../rtl/ctrl/monitor_config_regs.v'],
        'screen_color':['-s','tb_screen_color','tb_screen_color.v','../rtl/ctrl/monitor_config_regs.v',
                        '../rtl/video/color_adjust.v'],
        'clock720':['-s','tb_video_clock_720','tb_video_clock_720.v','../rtl/pll/ref27_pll.v','../rtl/pll/video_pll.v',
                    (OUTPUT/'eg_phy_pll_functional.v').as_posix()],
        'mixer565':['-s','tb_mixer565','tb_mixer565.v','../rtl/video/disp_mixer_565.v'],
        'pipeline720':['-DSIMULATION','-I','../rtl/video','tb_video_pipeline_720.v','../rtl/video/osd_engine_720.v',
                       '../rtl/video/osd_text_720.v','../rtl/video/subtitle_text_720.v','../rtl/video/font_rom_720.v','../rtl/video/promax_audio_waveform.v',
                       '../rtl/video/color_adjust.v','../rtl/video/emergency_render.v','../rtl/video/video_rgb_to_axis_640x480.v'],
        'subtitle_pipeline720':['-DSIMULATION','-I','../rtl/video','-Ptb_video_pipeline_720.SUBTITLES=1',
                       'tb_video_pipeline_720.v','../rtl/video/osd_engine_720.v',
                       '../rtl/video/osd_text_720.v','../rtl/video/subtitle_text_720.v','../rtl/video/font_rom_720.v',
                       '../rtl/video/promax_audio_waveform.v','../rtl/video/color_adjust.v',
                       '../rtl/video/emergency_render.v','../rtl/video/video_rgb_to_axis_640x480.v'],
        'subtitle720':['-s','tb_subtitle720','-I','../rtl/video','tb_subtitle720.v',
                       '../rtl/video/osd_engine_720.v','../rtl/video/osd_text_720.v',
                       '../rtl/video/subtitle_text_720.v','../rtl/video/font_rom_720.v'],
        'resize_display720':['-DSIMULATION','-Ptb_display720.RESIZE_WRITES=1',
                      'tb_display720.v','../rtl/video/resize_frame_720.v','../rtl/video/display_stream_720.v','../rtl/video/disp_mixer_565.v',
                      '../rtl/mem/disp_read_engine.v','../rtl/mem/afifo_simple.v','../rtl/mem/mem_mpu.v',
                      '../rtl/video/video_timing_gen.v','../rtl/video/transition_ctrl.v','../rtl/sd/frame_fifo_write.v','sdram_beh.v'],
        'display720':['-DSIMULATION','tb_display720.v','../rtl/video/resize_frame_720.v','../rtl/video/display_stream_720.v','../rtl/video/disp_mixer_565.v',
                      '../rtl/mem/disp_read_engine.v','../rtl/mem/afifo_simple.v','../rtl/mem/mem_mpu.v',
                      '../rtl/video/video_timing_gen.v','../rtl/video/transition_ctrl.v','../rtl/sd/frame_fifo_write.v','sdram_beh.v'],
        'prefetch_display720':['-DSIMULATION','-Ptb_display720.ACTIVE_ROWS=8','-Ptb_display720.TEST_FRAMES=12',
                      '-Ptb_display720.PREFETCH_WRITES=1','tb_display720.v','../rtl/video/resize_frame_720.v','../rtl/video/display_stream_720.v','../rtl/video/disp_mixer_565.v',
                      '../rtl/mem/disp_read_engine.v','../rtl/mem/afifo_simple.v','../rtl/mem/mem_mpu.v',
                      '../rtl/video/video_timing_gen.v','../rtl/video/transition_ctrl.v','../rtl/sd/frame_fifo_write.v','sdram_beh.v'],
        'waveform720':['-DSIMULATION','tb_audio_waveform_720.v','../rtl/video/promax_audio_waveform.v'],
        'writer720':['tb_writer720.v','../rtl/sd/frame_fifo_write.v'],
        'bmp_exact720':['tb_bmp_exact720.v','../rtl/sd/bmp_read_g.v'],
        'bmp_multisize':['-Ptb_bmp_exact720.MULTISIZE=1','tb_bmp_exact720.v','../rtl/sd/bmp_read_g.v'],
        'commit720':['-s','tb_commit720','tb_commit720.v','../rtl/video/transition_ctrl.v','../rtl/sd/source_scaler_gate.v',
                     '../rtl/sd/sd_card_bmp.v','../rtl/sd/sd_card_bmp_g.v','../rtl/sd/bmp_read_g.v','../rtl/sd/fat32_bmp_index.v','../rtl/sd/fat32_file_sector_mapper.v'],
        'autoplay_labels':['-s','tb_autoplay_labels','tb_autoplay_labels.v',
                          '../rtl/video/monitor_menu_renderer.v','../rtl/video/monitor_cjk_rom.v','../rtl/ctrl/font_rom_ascii.v'],
        'autoplay_period':['-s','tb_autoplay_period','tb_autoplay_period.v',
                       '../rtl/sd/sd_card_bmp.v','../rtl/sd/sd_card_bmp_g.v','../rtl/sd/bmp_read_g.v','../rtl/sd/fat32_bmp_index.v','../rtl/sd/fat32_file_sector_mapper.v'],
        'autoplay_visible':['-s','tb_autoplay_visible','tb_autoplay_visible.v',
                       '../rtl/video/transition_ctrl.v','../rtl/sd/source_scaler_gate.v',
                       '../rtl/sd/sd_card_bmp.v','../rtl/sd/sd_card_bmp_g.v','../rtl/sd/bmp_read_g.v','../rtl/sd/fat32_bmp_index.v','../rtl/sd/fat32_file_sector_mapper.v'],
        'prefetch720':['-s','tb_prefetch720','tb_prefetch720.v','../rtl/video/transition_ctrl.v','../rtl/sd/source_scaler_gate.v',
                       '../rtl/sd/sd_card_bmp.v','../rtl/sd/sd_card_bmp_g.v','../rtl/sd/bmp_read_g.v','../rtl/sd/fat32_bmp_index.v','../rtl/sd/fat32_file_sector_mapper.v'],
        'audio720':['-DSIMULATION','tb_audio720.v','../rtl/audio/audio_player.v','../rtl/mem/afifo_simple.v'],
    }
    if args.subtitle_state_only:
        extra['subtitle720'].insert(0,'-Ptb_subtitle720.CAPTURE_CYCLE_PIXELS=0')
    raster=extra.pop('monitor_menu_renderer')
    def extra_action(name,parts):
        try:
            sim(name,parts,args.reuse)
            return {'name':name,'pass':True}
        except (RuntimeError,subprocess.TimeoutExpired) as exc:
            print(f'[REG][FAIL] {name}: {exc}',flush=True)
            return {'name':name,'pass':False,'error':str(exc)}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        jobs=[pool.submit(extra_action,name,parts) for name,parts in extra.items()
              if not args.filter or re.search(args.filter,name)]
        for job in jobs:
            results.append(job.result());save_results()
    run('monitor_menu_renderer',lambda:monitor_rasters(raster,args.reuse))
    # 分组并行回归时，其他进程可能正在写栅格；仅在本轮完整通过渲染后转换。
    renderer_pass=any(item['name']=='monitor_menu_renderer' and item['pass'] for item in results)
    if renderer_pass and all(item['pass'] for item in results):
        for ppm in OUTPUT.glob('menu_*.ppm'): Image.open(ppm).save(ppm.with_suffix('.png'))
    sim_pass=all(item['pass'] for item in results)
    if args.full and sim_pass:
        run('TD_BUILD',lambda:command([PY,'-X','utf8',str(ROOT/'td_prj/build_native.py'),'--output',str(ROOT/'build/720p/td')],'td_build',3600))
    if not args.sim_only:
        run('CURRENT_SOURCE_REPORTS',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/check_reports.py')],'current_source_reports'))
        run('CURRENT_RESIZE_TIMING',lambda:command([PY,'-X','utf8',str(ROOT/'scripts/check_resize_timing.py')],'current_resize_timing',180))
    save_results(complete=True)
    passed=sum(item['pass'] for item in results)
    print(f'[REG] passed={passed}/{len(results)} output={OUTPUT}',flush=True)
    if passed!=len(results): raise SystemExit(1)

if __name__=='__main__': main()
