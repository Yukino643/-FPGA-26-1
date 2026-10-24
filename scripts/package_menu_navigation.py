"""签发菜单移开取消版本；复用既有物理门，并核对本轮交互回归证据。"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

import check_reports
import package_subtitle_copy as common

ROOT = Path(__file__).resolve().parents[1]
NAME = '20261024-menu-navigation'
DEST = ROOT / 'releases' / NAME
DOC = ROOT / 'docs/menu-navigation-20261024'
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'
BUILD = ROOT / 'build/720p/td' / NAME
REG = ROOT / 'build/720p/regression'


def verify():
    # 字幕未改，继承其独立像素证据；物理报告、完整回归必须属于当前构建。
    common.BUILD = BUILD
    common.DEST = DEST
    common.DOC = ROOT / 'docs/subtitle-spaces-20261024'
    result = common.verify()
    results = common.read_json(REG / 'results.json')
    names = {row['name'] for row in results if row['pass']}
    required = {'monitor_menu_ctrl', 'audio_menu', 'monitor_config_regs', 'screen_color'}
    if not required.issubset(names):
        raise RuntimeError('缺少菜单导航/异步握手回归')
    directed = common.read_json(DOC / 'verification.json')
    if not directed['passed'] or not directed['negative_control_failed_as_expected']:
        raise RuntimeError('缺少移开取消回归与旧RTL负向证据')
    for name, digest in directed['source_sha256'].items():
        if check_reports.sha256(ROOT / name) != digest:
            raise RuntimeError('菜单定向验证后输入变化：' + name)
    for name in required:
        text = (REG / (name + '.log')).read_text(encoding='utf-8')
        if 'PASS' not in text or re.search(r'\bFAIL\b|\bERROR\b|\bFATAL\b', text):
            raise RuntimeError('菜单回归日志未通过：' + name)
    for name, message in [('monitor_menu_ctrl', 'failed to cancel'),
                          ('audio_menu', 'preview survived navigation')]:
        if message not in (DOC / 'logs' / ('before-' + name + '.log')).read_text(encoding='utf-8'):
            raise RuntimeError('旧RTL负向用例没有命中预期断言：' + name)
    result.update({'change': 'main-card navigation cancels unconfirmed preview; confirmed mailbox preserved',
                   'menu_regression': sorted(required), 'lut_previous_release': 14848,
                   'lut_delta': result['resources']['lut'] - 14848,
                   'logical_canvas': [640, 360], 'output_pixels': [1280, 720]})
    return result


def main():
    result = verify()
    if DEST.exists():
        raise RuntimeError('禁止覆盖既有发布目录：' + str(DEST))
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
                              or path.name in ('results.json', 'run_status.json')):
            shutil.copy2(path, logs / path.name)
    shutil.copytree(DOC / 'logs', validation / 'menu-navigation')
    shutil.copy2(DOC / 'verification.json', validation / 'menu-navigation/verification.json')
    (DEST / 'README.md').write_text(
        '# 菜单跨卡防误操作烧录版（2026-10-24）\n\n'
        '烧录本目录 `av_media.bit`。主控制页图片/时间/周期卡：同卡两次 KEY4 确认，'
        'KEY2/KEY3 移开即取消未确认预览；已经确认的设置不撤销。二级编辑与长按规则不变。\n\n'
        '保留全幅中文菜单、音量控制、多尺寸图片、2/3/5/10秒轮播与空格字幕。'
        '完整范围回归与当前源码综合/P&R/bitgen、菜单/字库/缩放器定向时序通过；'
        '实际资源、域内时序、SHA256见 verification.json。旧加密SDRAM跨域负余量单列，'
        '不能称全工程时序闭合。新bit尚待上板验证。\n\n'
        '[简明操作说明](../../docs/KEY_GUIDE_20261017.md)；'
        '[验证记录](../../docs/menu-navigation-20261024/README.md)。'
        '回退：../20261024-subtitle-spaces/av_media.bit。\n', encoding='utf-8', newline='\n')
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
                raise RuntimeError('归档时输入变化：' + name)
            archive.writestr('source_snapshot/' + name, data)
    with zipfile.ZipFile(DEST / 'source-and-bit.zip') as archive:
        if archive.testzip() is not None:
            raise RuntimeError('发布归档CRC检查失败')
        for name, digest in paths.items():
            if hashlib.sha256(archive.read('source_snapshot/' + name)).hexdigest() != digest:
                raise RuntimeError('归档回读SHA失败：' + name)
    sums = [check_reports.sha256(p) + '  ' + p.relative_to(DEST).as_posix()
            for p in sorted(DEST.rglob('*')) if p.is_file()]
    (DEST / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n', encoding='ascii', newline='\n')
    for line in sums:
        digest, name = line.split('  ', 1)
        if check_reports.sha256(DEST / name) != digest:
            raise RuntimeError('发布文件回读失败：' + name)
    if verify() != result:
        raise RuntimeError('发布期间输入变化')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print('MENU_NAVIGATION_PACKAGE PASS ' + str(DEST / 'av_media.bit'))


if __name__ == '__main__':
    main()
