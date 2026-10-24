"""全幅菜单发布门：核对仿真源码、实际布局结果及独立发布副本，不执行烧录或Git。"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

import check_reports

ROOT = Path(__file__).resolve().parents[1]
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'
EVIDENCE = ROOT / 'docs/menu-16x9-20261023'
DEST = ROOT / 'releases/20261024-menu-16x9'
BUILD = ROOT / 'build/720p/td/20261024-menu-16x9'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def verify():
    if not check_reports.manifest_matches() or not check_reports.project_snapshots_match():
        raise RuntimeError('当前源码、工程快照与bit不一致')
    # 仿真阶段清单中的硬件输入必须与这次真正布局的源码一致。
    audit = read_json(EVIDENCE / 'SOURCE_AUDIT.json')
    protected = {item['path']: item['sha256'] for item in audit['unchanged']}
    protected.update({item['path']: item['after_sha256'] for item in audit['changed']})
    for name, digest in protected.items():
        if name.startswith(('rtl/', 'constraints/', 'sim/', 'scripts/')):
            if check_reports.sha256(ROOT / name) != digest:
                raise RuntimeError('仿真后输入漂移: ' + name)
    status = read_json(ROOT / 'build/720p/regression/run_status.json')
    results = read_json(ROOT / 'build/720p/regression/results.json')
    required = {'monitor_pipeline', 'monitor_menu_renderer', 'subtitle720',
                'autoplay_period', 'autoplay_visible', 'autoplay_labels',
                'audio_menu', 'audio_volume', 'CURRENT_SOURCE_REPORTS', 'CURRENT_RESIZE_TIMING'}
    if (not status['complete'] or status['filter'] is not None or status['sim_only']
            or status['passed'] != status['finished'] or len(results) != status['finished']
            or len(results) < 88 or not all(item['pass'] for item in results)
            or not required.issubset({item['name'] for item in results})):
        raise RuntimeError('完整功能/当前源码物理回归未通过')
    timing = (PHY / 'av_media_pr.timing').read_text(encoding='utf-8')
    area = (PHY / 'av_media_phy.area').read_text(encoding='utf-8')
    domains = {}
    for clock in ('video_clk', 'sd_card_clk', 'ext_mem_clk', 'hdmi_5x_clk'):
        group = re.search(r'Path Group\s*:\s*' + clock + r' -> ' + clock
                          + r'\s*\n(.*?)(?=Path Group|\Z)', timing, re.S)
        if not group:
            raise RuntimeError('缺少域内时序报告: ' + clock)
        setup = re.search(r'Max\s*:\s*SWNS\s+([-\d.]+)ns', group[1])
        hold = re.search(r'Min\s*:\s*HWNS\s+([-\d.]+)ns', group[1])
        if not setup or not hold:
            raise RuntimeError('缺少setup/hold: ' + clock)
        values = {'setup_ns': float(setup[1]), 'hold_ns': float(hold[1])}
        if values['setup_ns'] < (0.15 if clock == 'video_clk' else 0) or values['hold_ns'] < 0:
            raise RuntimeError(f'域内时序不满足门限: {clock}: {values}')
        domains[clock] = values
    resources = {}
    for name, limit in [('lut', 16660), ('reg', 19600), ('bram9k', 57),
                        ('bram32k', 4), ('dsp', 15), ('pll', 3)]:
        match = re.search(r'^\s*#' + name + r'\s+(\d+)', area, re.M)
        if not match or int(match[1]) > limit:
            raise RuntimeError('实际资源不满足门限: ' + name)
        resources[name] = int(match[1])
    global_setup = float(re.search(r'SWNS:\s*([-\d.]+)ns', timing)[1])
    global_hold = float(re.search(r'HWNS:\s*([-\d.]+)ns', timing)[1])
    if global_setup < -6.565 or global_hold < 0:
        raise RuntimeError('全局基线恶化或hold违例')
    directed = read_json(ROOT / 'build/720p/subtitle_timing/summary.json')
    resize = read_json(ROOT / 'build/720p/resize_timing/summary.json')
    if directed['failures'] or not resize or any(row[-1] < 0 for row in resize):
        raise RuntimeError('菜单/OSD/音量/字体/缩放器定向物理检查失败')
    final = read_json(EVIDENCE / 'FINAL_VERIFICATION.json')
    if (final['menu_images'] < 13 or final['main_images'] < 16 or final['cycles'] != 18
            or final['consecutive_capture_frames'] != 64):
        raise RuntimeError('仿真图集或整圈字幕证据不完整')
    for name in ('syn_1_console.log', 'phy_1_console.log', 'build_inputs.sha256'):
        if not (BUILD / name).is_file():
            raise RuntimeError('缺少当前构建过程证据: ' + name)
    return {'passed': True, 'regression': status, 'resources': resources,
            'lut_baseline': 14839, 'lut_delta': resources['lut'] - 14839,
            'domains': domains, 'legacy_encrypted_SDRAM_global_setup_ns': global_setup,
            'global_hold_ns': global_hold, 'bit_sha256': check_reports.sha256(PHY / 'av_media.bit'),
            'logical_canvas': [640, 360], 'output_pixels': [1280, 720], 'integer_scale': 2,
            'hardware_tested': False, 'evidence': 'RTL raster and physical TD reports; not board capture'}


def main():
    result = verify()
    if DEST.exists():
        raise RuntimeError('禁止覆盖发布目录: ' + str(DEST))
    DEST.mkdir(parents=True)
    for name in ('av_media.bit', 'av_media_phy.area', 'av_media_phy.ts',
                 'av_media_pr.timing', 'build_manifest.sha256', 'av_media.prj'):
        shutil.copy2(PHY / name, DEST / name)
    (DEST / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)
                                           + '\n', encoding='utf-8', newline='\n')
    validation = DEST / 'validation'
    shutil.copytree(BUILD, validation / 'td')
    for directory in ('resize_timing', 'subtitle_timing'):
        shutil.copytree(ROOT / 'build/720p' / directory, validation / directory)
    for name in ('run_status.json', 'results.json', 'current_source_reports.log',
                 'current_resize_timing.log'):
        shutil.copy2(ROOT / 'build/720p/regression' / name, validation / name)
    for name in ('FINAL_VERIFICATION.json', 'SOURCE_AUDIT.json'):
        shutil.copy2(EVIDENCE / name, DEST / name)
    (DEST / 'README.md').write_text(
        '# 全幅16:9监视菜单发布\n\n烧录本目录av_media.bit，HDMI-A/B继续输出1280×720。'
        'HDMI-A为640×360逻辑画布整数2×全幅，无原160px居中黑边。\n\n'
        '包含六项UI调整、64格字幕及此前已板验的2/3/5/10秒轮播修复。按键语义保持。'
        '本轮仿真和TD物理验收已通过，尚未烧录验证，不把RTL截图当作7寸屏实拍。\n\n'
        '资源及时序见verification.json；旧加密SDRAM跨域setup −6.565ns单列，'
        '不代表全工程时序闭合。上板回退使用../20261023-autoplay-period/av_media.bit。\n',
        encoding='utf-8', newline='\n')
    with (DEST / 'README.md').open('a', encoding='utf-8', newline='\n') as report:
        report.write('\n[六项改动与图集](../../docs/menu-16x9-20261023/IMPLEMENTATION_REPORT.md)；'
                     '[本轮物理验收](../../docs/menu-16x9-20261023/PHYSICAL_RELEASE_20261024.md)。'
                     '本目录FINAL_VERIFICATION/SOURCE_AUDIT为先前纯RTL阶段原始证据，'
                     '其中未综合标记为历史记录，当前实测以verification.json为准。\n')
    paths = {Path(p).relative_to(ROOT).as_posix(): check_reports.sha256(p)
             for p in check_reports.source_files()}
    for directory in ('scripts', 'sim', '.trellis/tasks/10-23-menu-16x9-rtl'):
        for path in (ROOT / directory).rglob('*'):
            if path.is_file() and path.suffix in ('.py', '.v', '.vh', '.hex', '.json', '.md', '.sh', '.ps1'):
                paths[path.relative_to(ROOT).as_posix()] = check_reports.sha256(path)
    (DEST / 'SOURCE_SHA256.json').write_text(json.dumps(paths, ensure_ascii=False, indent=2)
                                            + '\n', encoding='utf-8', newline='\n')
    with zipfile.ZipFile(DEST / 'source-and-bit.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, digest in sorted(paths.items()):
            data = (ROOT / name).read_bytes()
            if hashlib.sha256(data).hexdigest() != digest:
                raise RuntimeError('归档期间输入漂移: ' + name)
            archive.writestr('source_snapshot/' + name, data)
        archive.write(DEST / 'av_media.bit', 'av_media.bit')
        archive.write(DEST / 'SOURCE_SHA256.json', 'SOURCE_SHA256.json')
    with zipfile.ZipFile(DEST / 'source-and-bit.zip') as archive:
        if archive.testzip() is not None:
            raise RuntimeError('归档CRC校验失败')
        for name, digest in paths.items():
            if hashlib.sha256(archive.read('source_snapshot/' + name)).hexdigest() != digest:
                raise RuntimeError('归档回读失败: ' + name)
        if hashlib.sha256(archive.read('av_media.bit')).hexdigest() != result['bit_sha256']:
            raise RuntimeError('归档bit回读失败')
    sums = [check_reports.sha256(path) + '  ' + path.relative_to(DEST).as_posix()
            for path in sorted(DEST.rglob('*')) if path.is_file()]
    (DEST / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n', encoding='ascii', newline='\n')
    for line in sums:
        digest, name = line.split('  ', 1)
        if check_reports.sha256(DEST / name) != digest:
            raise RuntimeError('发布副本回读失败: ' + name)
    if verify() != result:
        raise RuntimeError('发布期间验收输入漂移')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print('MENU_16X9_PACKAGE PASS ' + str(DEST / 'av_media.bit'))


if __name__ == '__main__':
    main()
