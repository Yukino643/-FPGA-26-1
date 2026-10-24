"""轮播修复发布门：源码边界、完整回归、各档独立测时、真实布局资源及时序。"""
from pathlib import Path
import hashlib
import json
import re
import check_reports

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/720p/autoplay-period'
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'


def main():
    if not check_reports.manifest_matches() or not check_reports.project_snapshots_match():
        raise RuntimeError('当前源码/工程/bit清单不一致')
    baseline = json.loads((ROOT / 'releases/20261023-audio-volume/SOURCE_SHA256.json').read_text(encoding='utf-8'))
    allowed = {'rtl/sd/sd_card_bmp_g.v', 'rtl/video/monitor_menu_renderer.v',
               'rtl/sd/fat32_file_sector_mapper.v'}
    for name, expected in baseline.items():
        if name.startswith(('rtl/', 'constraints/')) and name not in allowed:
            if check_reports.sha256(ROOT / name) != expected:
                raise RuntimeError('超范围硬件输入变化: ' + name)
    status = json.loads((ROOT / 'build/720p/regression/run_status.json').read_text(encoding='utf-8'))
    results = json.loads((ROOT / 'build/720p/regression/results.json').read_text(encoding='utf-8'))
    names = {item['name'] for item in results if item['pass']}
    required = {'autoplay_period', 'autoplay_visible', 'autoplay_labels', 'prefetch720', 'commit720',
                'monitor_menu_renderer', 'monitor_pipeline', 'audio_volume', 'audio_menu',
                'CURRENT_SOURCE_REPORTS', 'CURRENT_RESIZE_TIMING'}
    if (not status['complete'] or status['filter'] is not None or status['sim_only']
            or status['finished'] != status['passed'] or len(results) != status['finished']
            or len(results) < 88 or not all(item['pass'] for item in results)
            or not required.issubset(names)):
        raise RuntimeError('缺少完整88项回归或必要用例')
    timing = (PHY / 'av_media_pr.timing').read_text(encoding='utf-8')
    area = (PHY / 'av_media_phy.area').read_text(encoding='utf-8')
    domains = {}
    for clock in ('video_clk', 'sd_card_clk', 'ext_mem_clk', 'hdmi_5x_clk'):
        group = re.search(r'Path Group\s*:\s*' + clock + r' -> ' + clock + r'\s*\n(.*?)(?=Path Group|\Z)', timing, re.S)
        if not group:
            raise RuntimeError('缺少时钟域报告: ' + clock)
        setup = re.search(r'Max\s*:\s*SWNS\s+([-\d.]+)ns', group[1])
        hold = re.search(r'Min\s*:\s*HWNS\s+([-\d.]+)ns', group[1])
        if not setup or not hold:
            raise RuntimeError('缺少setup/hold: ' + clock)
        values = {'setup_ns': float(setup[1]), 'hold_ns': float(hold[1])}
        if values['setup_ns'] < (0.15 if clock == 'video_clk' else 0) or values['hold_ns'] < 0:
            raise RuntimeError(f'域内时序未通过: {clock} {values}')
        domains[clock] = values
    resources = {}
    for name, limit in [('lut', 16660), ('reg', 19600), ('bram9k', 57), ('bram32k', 4), ('dsp', 15), ('pll', 3)]:
        match = re.search(r'^\s*#' + name + r'\s+(\d+)', area, re.M)
        if not match or int(match[1]) > limit:
            raise RuntimeError('资源不满足门限: ' + name)
        resources[name] = int(match[1])
    global_setup = float(re.search(r'SWNS:\s*([-\d.]+)ns', timing)[1])
    global_hold = float(re.search(r'HWNS:\s*([-\d.]+)ns', timing)[1])
    if global_setup < -6.565 or global_hold < 0:
        raise RuntimeError('全局时序恶化或hold为负')
    directed = json.loads((ROOT / 'build/720p/subtitle_timing/summary.json').read_text(encoding='utf-8'))
    if directed['failures']:
        raise RuntimeError('菜单/字幕/音量/字体定向物理检查失败')
    measurements = {}
    log = (ROOT / 'build/720p/regression/autoplay_visible.log').read_text(encoding='utf-8')
    for sel, seconds in enumerate((2, 3, 5, 10)):
        values = [int(value) for value in re.findall(rf'VISIBLE preset={sel} target_cycles={seconds * 1000} actual_cycles=(\d+)', log)]
        if len(values) != 3 or any(abs(value - seconds * 1000) > 20 for value in values):
            raise RuntimeError(f'缺少/不正确的可见周期测量: {seconds}s')
        measurements[str(seconds)] = {'scaled_cycles': values, 'scaled_clock_hz': 1000}
    if len(re.findall(r'VISIBLE_CHANGE preset=\d', log)) != 4 or 'TB_AUTOPLAY_VISIBLE PASS' not in log:
        raise RuntimeError('缺少四档运行期修改验证')
    labels = (ROOT / 'build/720p/regression/autoplay_labels.log').read_text(encoding='utf-8')
    if 'TB_AUTOPLAY_LABELS PASS' not in labels or len(re.findall(r'PERIOD_LABEL preset=\d', labels)) != 4:
        raise RuntimeError('缺少四档周期菜单的逐像素核对')
    before = (OUT / 'before.log').read_text(encoding='utf-8')
    if 'AUTO PERIOD REGRESSION' not in before or 'expected=5000 actual=7953' not in before:
        raise RuntimeError('缺少旧RTL负向复现')
    summary = {'passed': True, 'regression': status, 'presets_seconds': [2, 3, 5, 10],
               'measurements': measurements, 'resources': resources, 'domains': domains,
               'legacy_encrypted_SDRAM_global_setup_ns': global_setup, 'global_hold_ns': global_hold,
               'bit_sha256': check_reports.sha256(PHY / 'av_media.bit'),
               'hardware_tested': False, 'measurement_scope': 'scaled RTL simulation; actual top CDC and transition; synthetic card/resize delays'}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'verification.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print('AUTOPLAY_PERIOD PASS')


if __name__ == '__main__':
    main()
