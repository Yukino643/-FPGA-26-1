"""音频启动发布门限：独立于旧主屏任务计数及其顶层保护范围。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import check_reports

ROOT = Path(__file__).resolve().parents[1]
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'
OUT = ROOT / 'build/720p/audio-startup'
CHANGED_RTL = {
    'rtl/top/top_tf_hdmi_audio.v', 'rtl/sd/sd_card_bmp_g.v',
    'rtl/sd/fat32_bmp_index.v', 'rtl/audio/wav_read.v',
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--physical-only', action='store_true')
    args = parser.parse_args()
    failures = []
    if not check_reports.manifest_matches():
        raise RuntimeError('源码、工程快照与bit清单不一致，拒绝使用旧报告')
    baseline = json.loads((ROOT/'releases/20261022-main-ui/SOURCE_SHA256.json').read_text(encoding='utf-8'))
    for name, digest in baseline.items():
        if name.startswith(('rtl/', 'constraints/')) and name not in CHANGED_RTL:
            if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest:
                failures.append(['protected_source_changed', name])
    # 仿真提取真实top，另核对manager/index的连线，避免输出浮空被行为模型掩盖。
    top = (ROOT/'rtl/top/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
    manager = (ROOT/'rtl/sd/sd_card_bmp_g.v').read_text(encoding='utf-8')
    for source, pattern in (
        (top, r'\.INDEX_WAV\(1\)'),
        (top, r'\.wav_index_found\s*\(wav_index_found\)'),
        (top, r'\.wav_index_sector\s*\(wav_index_sector\)'),
        (manager, r'\.INDEX_WAV\s*\(INDEX_WAV\)'),
        (manager, r'\.wav_found\s*\(wav_index_found\)'),
        (manager, r'\.wav_sector\s*\(wav_index_sector\)'),
    ):
        if not re.search(pattern, source):
            failures.append(['missing_actual_connection', pattern])
    timing = (PHY/'av_media_pr.timing').read_text(encoding='utf-8')
    area = (PHY/'av_media_phy.area').read_text(encoding='utf-8')
    domains = {}
    for clock in ('video_clk', 'sd_card_clk', 'ext_mem_clk', 'hdmi_5x_clk'):
        group = re.search(r'Path Group\s*:\s*'+clock+r' -> '+clock+r'\s*\n(.*?)(?=Path Group|\Z)', timing, re.S)
        if not group:
            raise RuntimeError('缺少域内路径 '+clock)
        setup = re.search(r'Max\s*:\s*SWNS\s+([-\d.]+)ns', group[1])
        hold = re.search(r'Min\s*:\s*HWNS\s+([-\d.]+)ns', group[1])
        if not setup or not hold:
            raise RuntimeError('缺少域内Max/Min '+clock)
        setup, hold = float(setup[1]), float(hold[1])
        domains[clock] = {'setup_ns': setup, 'hold_ns': hold}
        if setup < (.15 if clock == 'video_clk' else 0) or hold < 0:
            failures.append(['domain_timing', clock, setup, hold])
    resources = {}
    for name, limit in (('lut',16660), ('reg',19600), ('bram9k',57), ('bram32k',4), ('dsp',13), ('pll',3)):
        match = re.search(r'^\s*#'+name+r'\s+(\d+)', area, re.M)
        if not match:
            raise RuntimeError('缺少资源统计 '+name)
        count = int(match[1])
        resources[name] = count
        if count > limit:
            failures.append(['resource', name, count, limit])
    global_setup = re.search(r'SWNS:\s*([-\d.]+)ns', timing)
    global_hold = re.search(r'HWNS:\s*([-\d.]+)ns', timing)
    if not global_setup or not global_hold:
        raise RuntimeError('缺少全局时序')
    global_setup, global_hold = float(global_setup[1]), float(global_hold[1])
    if global_hold < 0 or global_setup < -6.565:
        failures.append(['legacy_global_timing', global_setup, global_hold])
    measurements = {}
    regression = ROOT/'build/720p/regression'
    if not args.physical_only:
        subtitle = json.loads((ROOT/'build/720p/subtitle_timing/summary.json').read_text(encoding='utf-8'))
        resize = json.loads((ROOT/'build/720p/resize_timing/summary.json').read_text(encoding='utf-8'))
        if subtitle['failures'] or any(float(item[-1]) < 0 for item in resize):
            failures.append(['directed_timing_failed'])
        status = json.loads((regression/'run_status.json').read_text(encoding='utf-8'))
        tests = json.loads((regression/'results.json').read_text(encoding='utf-8'))
        required = {'wav_index','wav_startup','wav_startup_legacy','wav_startup_bad','wav_startup_missing',
                    'CURRENT_SOURCE_REPORTS','CURRENT_RESIZE_TIMING'}
        if (not status['complete'] or status['filter'] is not None or status['sim_only'] or
                status['passed'] != status['finished'] or status['finished'] != len(tests) or
                len(tests) not in (82,83) or not all(t['pass'] for t in tests) or
                not required.issubset({t['name'] for t in tests})):
            failures.append(['full_regression',status])
        for case in ('wav_startup', 'wav_startup_legacy'):
            log = (regression/(case+'.log')).read_text(encoding='utf-8')
            match = re.search(r'first_pcm_cycles=(\d+) first_image_cycles=(\d+) reads_to_pcm=(\d+)',log)
            if not match:
                raise RuntimeError('缺少首PCM/首图测量 '+case)
            measurements[case] = dict(zip(('first_pcm_cycles','first_image_cycles','reads_to_pcm'),map(int,match.groups())))
        before, after = measurements['wav_startup_legacy'], measurements['wav_startup']
        if after['reads_to_pcm'] >= before['reads_to_pcm'] or after['first_pcm_cycles'] >= before['first_pcm_cycles']:
            failures.append(['startup_did_not_improve',measurements])
    summary = {'passed':not failures,'physical_only':args.physical_only,'domains':domains,'resources':resources,
               'legacy_encrypted_SDRAM_global_setup_ns':global_setup,'global_hold_ns':global_hold,
               'bit_sha256':hashlib.sha256((PHY/'av_media.bit').read_bytes()).hexdigest(),
               'simulation_measurements':measurements,'hardware_tested':False,'failures':failures}
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(summary,ensure_ascii=False,indent=2))
    if failures:
        raise RuntimeError('音频启动验收未通过，禁止发布')
    print('AUDIO_STARTUP PASS')


if __name__ == '__main__':
    main()
