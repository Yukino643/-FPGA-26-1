"""严格门限通过后归档主屏版本；不烧录、不提交，拒绝覆盖已有发布。"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[3]
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', required=True)
    args = parser.parse_args()
    build = (ROOT / args.build).resolve()
    if not build.is_relative_to(ROOT / 'build/720p/td'):
        raise ValueError('构建日志必须位于本工程TD记录目录')
    release = ROOT / 'build/720p/releases/20261022-main-ui'
    if release.exists():
        raise RuntimeError('发布目录已存在，拒绝覆盖')
    # 门限在复制之前重新执行；任何失败都不创建发布目录。
    logs = {}
    for script in ('check_reports.py', 'check_main_ui.py'):
        result = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts' / script)],
                                cwd=ROOT, capture_output=True, check=True)
        logs[script.replace('.py', '.log')] = result.stdout + result.stderr
    checks = json.loads((ROOT / 'build/720p/main-ui-verification.json').read_text(encoding='utf-8'))
    if not checks['passed'] or checks['physical_only']:
        raise RuntimeError('发布门限不完整')
    # 两种manifest格式由原构建器维护，逐行核对输入子集，不能靠文件名判断。
    inputs = (build / 'build_inputs.sha256').read_text(encoding='ascii').splitlines()
    manifest = (PHY / 'build_manifest.sha256').read_text(encoding='ascii').splitlines()
    if not set(inputs).issubset(manifest):
        raise RuntimeError('所选构建日志与当前bit输入清单不一致')
    stage = ROOT / 'build/720p/main-ui-release-staging'
    if stage.exists():
        raise RuntimeError('归档暂存目录已存在，请先核查旧内容')
    stage.mkdir()

    def copy(source, target):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    for name in ('av_media.bit', 'av_media_phy.area', 'av_media_phy.ts',
                 'av_media_pr.timing', 'build_manifest.sha256', 'av_media.prj'):
        copy(PHY / name, stage / name)
    for file in build.iterdir():
        if file.is_file():
            copy(file, stage / 'build-log' / file.name)
    for name, data in logs.items():
        (stage / name).write_bytes(data)
    for name in ('subtitle_timing', 'resize_timing'):
        shutil.copytree(ROOT / 'build/720p' / name, stage / name)
    regression = ROOT / 'build/720p/regression'
    for file in regression.iterdir():
        if file.is_file() and file.suffix in ('.log', '.json', '.png'):
            copy(file, stage / 'regression' / file.name)
    for folder in ('main-ui-previews', 'main-ui-negative'):
        for file in (ROOT / 'build/720p' / folder).iterdir():
            if file.is_file() and file.suffix in ('.png', '.json', '.log'):
                copy(file, stage / folder / file.name)
    copy(ROOT / 'docs/MAIN_UI_20261022.md', stage / 'MAIN_UI_20261022.md')
    copy(ROOT / 'build/720p/main-ui-verification.json', stage / 'resource_summary.json')

    baseline = json.loads((ROOT / 'build/720p/backups/20261022-before-main-ui/SHA256.json').read_text(encoding='utf-8'))
    sources = {ROOT / name for name in baseline if (ROOT / name).is_file()}
    sources.update((ROOT / '.trellis/tasks/10-22-main-ui').rglob('*'))
    sources.update(ROOT / name for name in ('docs/MAIN_UI_20261022.md',
                                          'scripts/check_main_ui.py', 'scripts/render_main_ui.py'))
    sources = sorted(p for p in sources if p.is_file() and '__pycache__' not in p.parts)
    source_hashes = {p.relative_to(ROOT).as_posix(): digest(p) for p in sources}
    (stage / 'SOURCE_SHA256.json').write_text(json.dumps(source_hashes, ensure_ascii=False, indent=2) + '\n',
                                            encoding='utf-8', newline='\n')
    with zipfile.ZipFile(stage / 'source-and-bit.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for p in sources:
            archive.write(p, p.relative_to(ROOT).as_posix())
        archive.write(PHY / 'av_media.bit', 'av_media.bit')
    with zipfile.ZipFile(stage / 'source-and-bit.zip') as archive:
        if archive.testzip() is not None:
            raise RuntimeError('源码ZIP CRC校验失败')
        for name, expected in source_hashes.items():
            if hashlib.sha256(archive.read(name)).hexdigest() != expected:
                raise RuntimeError('源码ZIP回读不一致: ' + name)
        if hashlib.sha256(archive.read('av_media.bit')).hexdigest() != checks['bit_sha256']:
            raise RuntimeError('ZIP中的bit不一致')
    if digest(stage / 'av_media.bit') != checks['bit_sha256']:
        raise RuntimeError('归档bit复制校验失败')
    d = checks['domains']
    readme = f'''# 炬屏 HDMI-B主屏与视界字幕（2026-10-22）

烧录文件：av_media.bit
SHA256：{checks['bit_sha256']}

本轮：标题/模式局部底板，时间固定右下；48px字幕条、96px“视界”标签及B组三句；单次RGB>>2压暗；1024/688px循环窗口；薄荷绿波形高88，移除孤立峰值条。HDMI-A菜单、按键、邮箱与SDRAM功能保持修改前内容。

默认图片/波形/时间开启，固定标题与字幕关闭。进入“字幕”二级页，KEY4编辑，KEY2减/关、KEY3增/开，KEY4确认；标题独立开启。菜单的取消/返回、播放切图、应急仍用原有按键规则。详细8组合与板测步骤见MAIN_UI_20261022.md。

完整回归77/77（75项功能/生成检查＋2项当前物理检查，complete=true/filter=null/sim_only=false，哈希相同项复用）。完整TD综合/P&R/hold/bitgen，基础、菜单/字幕/字库与缩放定向时序检查通过。资源见resource_summary.json。
视频setup/hold：{d['video_clk']['setup_ns']:+.3f}/{d['video_clk']['hold_ns']:+.3f}ns；视频setup门限+0.150ns。
SD卡域：{d['sd_card_clk']['setup_ns']:+.3f}/{d['sd_card_clk']['hold_ns']:+.3f}ns；存储内部：{d['ext_mem_clk']['setup_ns']:+.3f}/{d['ext_mem_clk']['hold_ns']:+.3f}ns。

旧加密SDRAM跨域全局setup仍为{checks['legacy_encrypted_SDRAM_global_setup_ns']:.3f}ns，单独保留，不代表全工程时序闭合。复查发现旧菜单发布SD卡域内部setup=-0.142ns，本轮已纳入并通过非负检查。
预览中main-ui-previews为照片输入OSD RTL、波形关闭；regression内为RTL栅格，均非板拍。未烧录、未Flash固化；物理验证与实际双屏效果仍需板测。
原发布与修改前574文件备份保留。不提交或推送Git。失败布局候选不属于本发布。
'''
    (stage / 'README.md').write_text(readme, encoding='utf-8', newline='\n')
    files = sorted(p for p in stage.rglob('*') if p.is_file())
    (stage / 'SHA256SUMS.txt').write_text(''.join(
        f'{digest(p)}  {p.relative_to(stage).as_posix()}\n' for p in files), encoding='utf-8', newline='\n')
    for line in (stage / 'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
        expected, name = line.split('  ', 1)
        if digest(stage / name) != expected:
            raise RuntimeError('发布SHA256回读失败: ' + name)
    stage.rename(release)
    print('RELEASE PASS', release, checks['bit_sha256'], flush=True)


if __name__ == '__main__':
    main()
