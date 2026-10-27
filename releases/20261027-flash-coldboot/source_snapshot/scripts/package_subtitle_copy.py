"""签发新字幕bit；严格检查当前输入、完整回归与真实物理报告，不执行烧录或Git。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import zipfile

import check_reports

ROOT = Path(__file__).resolve().parents[1]
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'
REG = ROOT / 'build/720p/regression'
BUILD = ROOT / 'build/720p/td/20261024-subtitle-copy'
DEST = ROOT / 'releases/20261024-subtitle-copy'
DOC = ROOT / 'docs/subtitle-copy-20261024'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def verify():
    if not check_reports.manifest_matches() or not check_reports.project_snapshots_match():
        raise RuntimeError('源码、工程快照与bit清单不一致')
    status = read_json(REG / 'run_status.json')
    results = read_json(REG / 'results.json')
    required = {'subtitle720', 'pipeline720', 'subtitle_pipeline720', 'monitor_pipeline',
                'monitor_menu_renderer', 'autoplay_period', 'autoplay_visible', 'audio_menu',
                'audio_volume', 'CURRENT_SOURCE_REPORTS', 'CURRENT_RESIZE_TIMING'}
    if (not status['complete'] or status['filter'] is not None or status['sim_only']
            or status['finished'] != status['passed'] or len(results) != status['finished']
            or len(results) < 88 or not all(r['pass'] for r in results)
            or not required.issubset({r['name'] for r in results})):
        raise RuntimeError('完整功能/物理回归未完成或未全部通过')
    subtitle = (REG / 'subtitle720.log').read_text(encoding='utf-8')
    if subtitle.count('SUBTITLE_CYCLE PASS') != 18 or 'TB_SUBTITLE720 PASS' not in subtitle:
        raise RuntimeError('字幕缺少18完整周期验证')
    evidence = read_json(DOC / 'verification.json')
    if not evidence['passed'] or evidence['independent_strip_pixel_checks'] != 184320:
        raise RuntimeError('新句完整字形缺少独立像素证据')
    for name, digest in evidence['source_sha256'].items():
        if check_reports.sha256(ROOT / name) != digest:
            raise RuntimeError('定向验证后源码漂移：' + name)
    timing = (PHY / 'av_media_pr.timing').read_text(encoding='utf-8')
    area = (PHY / 'av_media_phy.area').read_text(encoding='utf-8')
    domains = {}
    for clock in ('video_clk', 'sd_card_clk', 'ext_mem_clk', 'hdmi_5x_clk'):
        group = re.search(r'Path Group\s*:\s*' + clock + r' -> ' + clock
                          + r'\s*\n(.*?)(?=Path Group|\Z)', timing, re.S)
        if not group:
            raise RuntimeError('缺少域内报告：' + clock)
        setup = re.search(r'Max\s*:\s*SWNS\s+([-\d.]+)ns', group[1])
        hold = re.search(r'Min\s*:\s*HWNS\s+([-\d.]+)ns', group[1])
        if not setup or not hold:
            raise RuntimeError('缺少域内setup/hold：' + clock)
        values = {'setup_ns': float(setup[1]), 'hold_ns': float(hold[1])}
        if values['setup_ns'] < (0.15 if clock == 'video_clk' else 0) or values['hold_ns'] < 0:
            raise RuntimeError(f'域内时序不满足门限：{clock} {values}')
        domains[clock] = values
    resources = {}
    for name, limit in [('lut', 16660), ('reg', 19600), ('bram9k', 57),
                        ('bram32k', 4), ('dsp', 15), ('pll', 3)]:
        found = re.search(r'^\s*#' + name + r'\s+(\d+)', area, re.M)
        if not found or int(found[1]) > limit:
            raise RuntimeError('资源超限或报告缺项：' + name)
        resources[name] = int(found[1])
    global_setup = float(re.search(r'SWNS:\s*([-\d.]+)ns', timing)[1])
    global_hold = float(re.search(r'HWNS:\s*([-\d.]+)ns', timing)[1])
    if global_setup < -6.565 or global_hold < 0:
        raise RuntimeError('全局基线恶化或hold违例')
    directed = read_json(ROOT / 'build/720p/subtitle_timing/summary.json')
    resize = read_json(ROOT / 'build/720p/resize_timing/summary.json')
    if directed['failures'] or not resize or any(row[-1] < 0 for row in resize):
        raise RuntimeError('菜单/OSD/字体/音量/缩放定向物理检查未通过')
    for name in ('syn_1_console.log', 'phy_1_console.log', 'build_inputs.sha256'):
        if not (BUILD / name).is_file():
            raise RuntimeError('缺少当前构建记录：' + name)
    return {'passed': True, 'release': DEST.name, 'regression': status,
            'presets': evidence['presets'], 'cells': evidence['cells'], 'glyphs': evidence['glyphs'],
            'font_rom': [2048, 32], 'resources': resources, 'domains': domains,
            'legacy_encrypted_SDRAM_global_setup_ns': global_setup,
            'global_hold_ns': global_hold, 'bit_sha256': check_reports.sha256(PHY / 'av_media.bit'),
            'hardware_tested': False, 'cycle_raster_export': status['subtitle_cycle_raster_export']}


def main():
    global BUILD, DEST, DOC
    parser = argparse.ArgumentParser()
    parser.add_argument('--variant', choices=('subtitle-copy', 'subtitle-spaces'), default='subtitle-copy')
    args = parser.parse_args()
    BUILD = ROOT / 'build/720p/td' / ('20261024-' + args.variant)
    DEST = ROOT / 'releases' / ('20261024-' + args.variant)
    DOC = ROOT / 'docs' / (args.variant + '-20261024')
    result = verify()
    if DEST.exists():
        raise RuntimeError('禁止覆盖已存在的发布目录：' + str(DEST))
    DEST.mkdir(parents=True)
    for name in ('av_media.bit', 'av_media_phy.area', 'av_media_phy.ts',
                 'av_media_pr.timing', 'build_manifest.sha256', 'av_media.prj'):
        shutil.copy2(PHY / name, DEST / name)
    (DEST / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)
                                            + '\n', encoding='utf-8', newline='\n')
    validation = DEST / 'validation'
    shutil.copytree(BUILD, validation / 'td')
    for name in ('resize_timing', 'subtitle_timing'):
        shutil.copytree(ROOT / 'build/720p' / name, validation / name)
    logs = validation / 'regression'
    logs.mkdir()
    for path in REG.iterdir():
        if path.is_file() and (path.suffix == '.log' or path.name.endswith('.pass.sha256')
                               or path.name in ('run_status.json', 'results.json')):
            shutil.copy2(path, logs / path.name)
    shutil.copytree(DOC / 'evidence', validation / 'directed')
    shutil.copy2(DOC / 'verification.json', validation / 'directed/verification.json')
    (DEST / 'README.md').write_text(
        '# 新滚动字幕烧录版（2026-10-24）\n\n烧录本目录 `av_media.bit`；'
        'HDMI-A/B仍输出1280×720，监视菜单640×360整数2倍全幅。\n\n'
        + '\n'.join(f'{i+1}. {line}' for i, line in enumerate(result['presets']))
        + '\n\n字模地址槽60/64，最长欢迎语完整离场后留空再重启。'
        '完整仿真与TD物理检查已通过；实际资源、域内时序、bit SHA256见verification.json。'
        '旧加密SDRAM跨域setup仍单列，不能称全工程时序闭合；尚待用户烧录确认。\n\n'
        '[操作与图形验证](../../docs/subtitle-copy-20261024/README.md)。'
        '回退文件：../20261024-menu-16x9/av_media.bit。\n', encoding='utf-8', newline='\n')
    paths = {Path(p).relative_to(ROOT).as_posix(): check_reports.sha256(p)
             for p in check_reports.source_files()}
    for folder in ('scripts', 'sim'):
        for path in (ROOT / folder).rglob('*'):
            if path.is_file() and path.suffix in ('.py', '.v', '.vh', '.hex', '.sh', '.ps1'):
                paths[path.relative_to(ROOT).as_posix()] = check_reports.sha256(path)
    (DEST / 'SOURCE_SHA256.json').write_text(json.dumps(paths, ensure_ascii=False, indent=2)
                                             + '\n', encoding='utf-8', newline='\n')
    with zipfile.ZipFile(DEST / 'source-and-bit.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, digest in sorted(paths.items()):
            data = (ROOT / name).read_bytes()
            if hashlib.sha256(data).hexdigest() != digest:
                raise RuntimeError('归档时输入漂移：' + name)
            archive.writestr('source_snapshot/' + name, data)
    with zipfile.ZipFile(DEST / 'source-and-bit.zip') as archive:
        if archive.testzip() is not None:
            raise RuntimeError('源码bit归档CRC失败')
        for name, digest in paths.items():
            if hashlib.sha256(archive.read('source_snapshot/' + name)).hexdigest() != digest:
                raise RuntimeError('归档SHA回读失败：' + name)
    sums = [check_reports.sha256(p) + '  ' + p.relative_to(DEST).as_posix()
            for p in sorted(DEST.rglob('*')) if p.is_file()]
    (DEST / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n', encoding='ascii', newline='\n')
    for line in sums:
        digest, name = line.split('  ', 1)
        if check_reports.sha256(DEST / name) != digest:
            raise RuntimeError('发布文件回读失败：' + name)
    if verify() != result:
        raise RuntimeError('发布期间输入漂移')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print('SUBTITLE_COPY_PACKAGE PASS ' + str(DEST / 'av_media.bit'))


if __name__ == '__main__':
    main()
