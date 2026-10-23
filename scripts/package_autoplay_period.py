"""当前轮播周期版本独立发布；禁止覆盖，校验源文件/bit/ZIP，不执行烧录或Git推送。"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
import check_reports

ROOT = Path(__file__).resolve().parents[1]
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'
DEST = ROOT / 'releases/20261023-autoplay-period'


def main():
    result = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/check_autoplay_period.py')],
                            cwd=ROOT, capture_output=True)
    if result.returncode:
        raise RuntimeError('验收失败：' + (result.stdout + result.stderr).decode('utf-8', errors='replace'))
    if DEST.exists():
        raise RuntimeError('禁止覆盖发布目录 ' + str(DEST))
    inputs = {Path(p).relative_to(ROOT).as_posix(): check_reports.sha256(p) for p in check_reports.source_files()}
    for directory in ('sim', 'scripts', '.trellis/tasks/10-23-autoplay-period'):
        for path in (ROOT / directory).rglob('*'):
            if path.is_file() and '__pycache__' not in path.parts:
                inputs[path.relative_to(ROOT).as_posix()] = check_reports.sha256(path)
    for name in ('docs/AUTOPLAY_PERIOD_20261023.md', '.trellis/spec/embedded/hdmi-b-720p.md'):
        inputs[name] = check_reports.sha256(ROOT / name)
    DEST.mkdir(parents=True)
    for name in ('av_media.bit', 'av_media_phy.area', 'av_media_pr.timing', 'av_media_phy.ts',
                 'build_manifest.sha256', 'av_media.prj'):
        shutil.copy2(PHY / name, DEST / name)
    shutil.copy2(ROOT / 'docs/AUTOPLAY_PERIOD_20261023.md', DEST / 'AUTOPLAY_PERIOD_20261023.md')
    shutil.copy2(ROOT / 'build/720p/autoplay-period/verification.json', DEST / 'verification.json')
    (DEST / 'check_autoplay_period.log').write_bytes(result.stdout)
    validation = DEST / 'validation'
    validation.mkdir()
    for name in ('results.json', 'run_status.json', 'autoplay_period.log', 'autoplay_visible.log',
                 'autoplay_labels.log', 'fat32_mapper.log', 'prefetch720.log', 'commit720.log',
                 'monitor_menu_renderer.log', 'current_source_reports.log', 'current_resize_timing.log',
                 'td_build.log'):
        shutil.copy2(ROOT / 'build/720p/regression' / name, validation / name)
    shutil.copy2(ROOT / 'build/720p/autoplay-period/before.log', validation / 'before-negative-control.log')
    shutil.copy2(ROOT / 'build/720p/autoplay-period/before_sd_card_bmp_g.v', validation / 'before_sd_card_bmp_g.v')
    for directory in ('subtitle_timing', 'resize_timing'):
        shutil.copytree(ROOT / 'build/720p' / directory, validation / directory)
    # 只复制当前菜单RTL栅格，不把照片合成图或旧图片当作本轮板验。
    images = DEST / 'images'
    images.mkdir()
    for path in (ROOT / 'build/720p/regression').glob('menu_*.png'):
        shutil.copy2(path, images / path.name)
    (images / 'README.md').write_text('本目录为当前菜单RTL仿真栅格，不是屏幕照片或上板验证。\n',
                                    encoding='utf-8', newline='\n')
    (DEST / 'SOURCE_SHA256.json').write_text(json.dumps(inputs, ensure_ascii=False, indent=2) + '\n',
                                           encoding='utf-8', newline='\n')
    with zipfile.ZipFile(DEST / 'source-and-bit.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, digest in sorted(inputs.items()):
            data = (ROOT / name).read_bytes()
            if hashlib.sha256(data).hexdigest() != digest:
                raise RuntimeError('归档输入变化 ' + name)
            archive.writestr('source_snapshot/' + name, data)
        for name in ('SOURCE_SHA256.json', 'av_media.bit', 'verification.json'):
            archive.write(DEST / name, name)
    with zipfile.ZipFile(DEST / 'source-and-bit.zip') as archive:
        if archive.testzip() is not None:
            raise RuntimeError('ZIP校验失败')
        for name, digest in inputs.items():
            if hashlib.sha256(archive.read('source_snapshot/' + name)).hexdigest() != digest:
                raise RuntimeError('ZIP源文件校验失败 ' + name)
        if hashlib.sha256(archive.read('av_media.bit')).hexdigest() != check_reports.sha256(PHY / 'av_media.bit'):
            raise RuntimeError('ZIP烧录文件不一致')
    if not check_reports.manifest_matches() or not check_reports.project_snapshots_match():
        raise RuntimeError('归档期间构建清单变化')
    (DEST / 'README.md').write_text(
        '# 自动轮播周期修复\n\n烧录av_media.bit；周期2/3/5/10秒，去掉1秒档。\n\n'
        '缩放、预取、转场计入周期；改档重新计时，慢卡只保留一次请求且不补切。\n\n'
        '已完成四档缩比RTL测时、菜单像素核对、完整回归、TD综合/P&R/bitgen与严格发布门限。'
        '实际TF卡和显示器的秒表结果仍待用户上板确认；不要把仿真秒数当实机测量。\n\n'
        '操作、测时方法及资源时序见AUTOPLAY_PERIOD_20261023.md。旧加密SDRAM跨域setup -6.565ns单列，'
        '不代表全工程时序闭合。20261023-audio-volume已板验回退完整保留。\n',
        encoding='utf-8', newline='\n')
    sums = [check_reports.sha256(p) + '  ' + p.relative_to(DEST).as_posix()
            for p in sorted(DEST.rglob('*')) if p.is_file()]
    (DEST / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n', encoding='utf-8', newline='\n')
    for line in sums:
        digest, name = line.split('  ', 1)
        if check_reports.sha256(DEST / name) != digest:
            raise RuntimeError('发布回读失败 ' + name)
    print('AUTOPLAY_PERIOD_PACKAGE PASS ' + str(DEST / 'av_media.bit'))


if __name__ == '__main__':
    main()
