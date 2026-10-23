"""音量版本验收：当前源码/bit、保护边界、真实接线、资源时序及完整回归。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import check_reports
import check_menu_p0

ROOT=Path(__file__).resolve().parents[1]
PHY=ROOT/'td_prj/av_media_Runs/phy_1'
OUT=ROOT/'build/720p/audio-volume'
ALLOWED={'rtl/top/top_tf_hdmi_audio.v','rtl/ctrl/monitor_menu_ctrl.v',
         'rtl/ctrl/monitor_config_regs.v','rtl/video/monitor_menu_renderer.v',
         'rtl/video/monitor_cjk_rom.v','rtl/video/resize_frame_720.v',
         'rtl/sd/fat32_bmp_index.v'}


def instance(text,marker):
    start=text.index(marker)
    return text[start:text.index('\n);',start)+3]


def check_connections():
    top=(ROOT/'rtl/top/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
    expected={
        'pcm_volume_control u_pcm_volume_control(':{
            'clk':'video_clk','rst':'rst_video','audio_config':'audio_active_video',
            'in_valid':'audio_valid','in_data_valid':'audio_sample_data_valid',
            'in_left':'audio_left_data','in_right':'audio_right_data',
            'emergency_mode':'emergency_mode','siren_valid':'siren_valid',
            'siren_left':'siren_left','siren_right':'siren_right',
            'out_valid':'audio_valid_final','out_data_valid':'waveform_pcm_valid',
            'out_left':'audio_left_final','out_right':'audio_right_final'},
        'monitor_config_regs u_monitor_config_regs(':{
            'audio_payload_sd':'audio_payload_sd','audio_shadow_sd':'audio_shadow_sd',
            'audio_active_video':'audio_active_video','audio_preview_video':'audio_preview_video'},
        'monitor_menu_renderer u_mon_menu_renderer(':{
            'audio_page':'mon_audio_page_sync[1]','audio_edit':'mon_audio_edit_sync[1]',
            'audio_shadow':'audio_preview_video','audio_active':'audio_active_video'},
        ') u_monitor_menu_ctrl(':{
            'audio_page':'monitor_audio_page_sd','audio_edit':'monitor_audio_edit_sd',
            'audio_shadow':'audio_shadow_sd','audio_payload':'audio_payload_sd'},
    }
    for marker,ports in expected.items():
        block=instance(top,marker)
        actual=dict(re.findall(r'\.(\w+)\s*\(\s*([^()]*)\s*\)',block))
        for port,signal in ports.items():
            if actual.get(port,'').strip()!=signal:
                raise RuntimeError(f'真实top接线错误: {marker} {port} -> {actual.get(port)}')
    if re.search(r'assign\s+audio_(?:left|right|valid)_final\s*=',top):
        raise RuntimeError('音量流水输出存在第二驱动')
    if '../rtl/audio/pcm_volume_control.v' not in (ROOT/'td_prj/av_media.al').read_text(encoding='utf-8-sig'):
        raise RuntimeError('TD没有收录新增音量模块')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--physical-only',action='store_true')
    args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    failures=[]
    if not check_reports.manifest_matches() or not check_reports.project_snapshots_match():
        raise RuntimeError('当前源码、TD工程及bit清单不一致')
    baseline=json.loads((ROOT/'releases/20261022-audio-startup/SOURCE_SHA256.json').read_text(encoding='utf-8'))
    protected={name:digest for name,digest in baseline.items()
               if name.startswith(('rtl/','constraints/')) and name not in ALLOWED}
    for name,digest in protected.items():
        if check_reports.sha256(ROOT/name)!=digest:
            failures.append(['unexpected_source_change',name])
    check_connections()
    timing=(PHY/'av_media_pr.timing').read_text(encoding='utf-8')
    area=(PHY/'av_media_phy.area').read_text(encoding='utf-8')
    domains={}
    for clock in ('video_clk','sd_card_clk','ext_mem_clk','hdmi_5x_clk'):
        match=re.search(r'Path Group\s*:\s*'+clock+r' -> '+clock+r'\s*\n(.*?)(?=Path Group|\Z)',timing,re.S)
        if not match:raise RuntimeError('缺少时钟域 '+clock)
        setup=re.search(r'Max\s*:\s*SWNS\s+([-\d.]+)ns',match[1])
        hold=re.search(r'Min\s*:\s*HWNS\s+([-\d.]+)ns',match[1])
        if not setup or not hold:raise RuntimeError('缺少setup/hold '+clock)
        setup,hold=float(setup[1]),float(hold[1]);domains[clock]={'setup_ns':setup,'hold_ns':hold}
        if setup<(.15 if clock=='video_clk' else 0) or hold<0:
            failures.append(['domain_timing',clock,setup,hold])
    resources={}
    for name,limit in (('lut',16660),('reg',19600),('bram9k',57),('bram32k',4),('dsp',17),('pll',3)):
        match=re.search(r'^\s*#'+name+r'\s+(\d+)',area,re.M)
        if not match:raise RuntimeError('缺少资源 '+name)
        value=int(match[1]);resources[name]=value
        if value>limit:failures.append(['resource',name,value,limit])
    legacy=float(re.search(r'SWNS:\s*([-\d.]+)ns',timing)[1])
    global_hold=float(re.search(r'HWNS:\s*([-\d.]+)ns',timing)[1])
    if legacy < -6.565 or global_hold<0:failures.append(['global_timing',legacy,global_hold])
    if not args.physical_only:
        reg=ROOT/'build/720p/regression'
        status=json.loads((reg/'run_status.json').read_text(encoding='utf-8'))
        tests=json.loads((reg/'results.json').read_text(encoding='utf-8'))
        required={'audio_volume','audio_menu','monitor_menu_renderer','monitor_pipeline',
                  'monitor_menu_ctrl','monitor_config_regs','screen_color','audio720',
                  'wav_index','wav_startup','wav_startup_legacy','wav_startup_bad','wav_startup_missing',
                  'CURRENT_SOURCE_REPORTS','CURRENT_RESIZE_TIMING'}
        if (not status['complete'] or status['filter'] is not None or status['sim_only'] or
            status['passed']!=status['finished'] or len(tests)!=status['finished'] or len(tests)<84 or
            not all(t['pass'] for t in tests) or not required.issubset({t['name'] for t in tests})):
            failures.append(['full_regression',status])
        directed=json.loads((ROOT/'build/720p/subtitle_timing/summary.json').read_text(encoding='utf-8'))
        if directed['failures'] or 'volume_from' not in directed['summary']:
            failures.append(['directed_timing'])
        if not failures:
            protected_path=OUT/'protected-inputs.json'
            protected_path.write_text(json.dumps(protected,indent=2)+'\n',encoding='utf-8',newline='\n')
            check_menu_p0.SCENES.update({'menu_audio':(True,0,0,0),
                                        'menu_audio_edit':(True,0,1,1),
                                        'menu_audio_mute':(True,1,0,0)})
            check_menu_p0.verify_and_capture(OUT/'images',protected_path)
            # 复用历史检查函数的几何断言；本轮证据只保留实际菜单RTL栅格。
            capture=OUT/'images'
            (capture/'hdmi_b_subtitle_on_UNCHANGED_REFERENCE.png').unlink(missing_ok=True)
            layout_path=capture/'verification.json'
            layout=json.loads(layout_path.read_text(encoding='utf-8'))
            layout['scope']='当前音频菜单13场景的RTL栅格、边框及实际缩放映射检查'
            layout['limitations']=[
                '本文件仅报告界面检查；物理资源及时序以父目录verification.json为准',
                '未生成本轮HDMI-B照片栅格，不包含板级听感或显示验证']
            layout_path.write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    summary={'passed':not failures,'physical_only':args.physical_only,'domains':domains,'resources':resources,
             'legacy_encrypted_SDRAM_global_setup_ns':legacy,'global_hold_ns':global_hold,
             'bit_sha256':hashlib.sha256((PHY/'av_media.bit').read_bytes()).hexdigest(),
             'hardware_tested':False,'failures':failures}
    (OUT/'verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(summary,ensure_ascii=False,indent=2))
    if failures:raise RuntimeError('音量版本未通过门限，禁止发布')
    print('AUDIO_VOLUME PASS')


if __name__=='__main__':main()
