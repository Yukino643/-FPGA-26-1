"""验收后归档音量版本；禁止覆盖上一版发布，ZIP与逐文件哈希均回读。"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
import check_reports

ROOT=Path(__file__).resolve().parents[1]
PHY=ROOT/'td_prj/av_media_Runs/phy_1'
DEST=ROOT/'releases/20261023-audio-volume'


def main():
    result=subprocess.run([sys.executable,'-B',str(ROOT/'scripts/check_audio_volume.py')],cwd=ROOT,capture_output=True)
    if result.returncode:
        raise RuntimeError('验收失败：'+(result.stdout+result.stderr).decode('utf-8',errors='replace'))
    if DEST.exists():raise RuntimeError('禁止覆盖发布目录 '+str(DEST))
    inputs={Path(p).relative_to(ROOT).as_posix():check_reports.sha256(p) for p in check_reports.source_files()}
    for directory in ('sim','scripts','.trellis/tasks/10-22-audio-volume'):
        for path in (ROOT/directory).rglob('*'):
            if path.is_file() and '__pycache__' not in path.parts:
                inputs[path.relative_to(ROOT).as_posix()]=check_reports.sha256(path)
    for name in ('docs/AUDIO_VOLUME_20261022.md','.trellis/spec/embedded/audio-volume.md'):
        inputs[name]=check_reports.sha256(ROOT/name)
    DEST.mkdir(parents=True)
    for name in ('av_media.bit','av_media_phy.area','av_media_pr.timing','av_media_phy.ts','build_manifest.sha256','av_media.prj'):
        shutil.copy2(PHY/name,DEST/name)
    shutil.copy2(ROOT/'docs/AUDIO_VOLUME_20261022.md',DEST/'AUDIO_VOLUME_20261022.md')
    shutil.copy2(ROOT/'build/720p/audio-volume/verification.json',DEST/'verification.json')
    (DEST/'check_audio_volume.log').write_bytes(result.stdout)
    validation=DEST/'validation';validation.mkdir()
    for name in ('results.json','run_status.json','audio_menu.log','audio_volume.log','monitor_menu_renderer.log',
                 'monitor_pipeline.log','current_source_reports.log','current_resize_timing.log'):
        shutil.copy2(ROOT/'build/720p/regression'/name,validation/name)
    for directory in ('subtitle_timing','resize_timing'):
        shutil.copytree(ROOT/'build/720p'/directory,validation/directory)
    shutil.copytree(ROOT/'build/720p/audio-volume/images',DEST/'images')
    # 旧P0检查器附带的软件合成参考不作为本轮证据发布。
    reference=DEST/'images/hdmi_b_subtitle_on_UNCHANGED_REFERENCE.png'
    reference.unlink(missing_ok=True)
    (DEST/'SOURCE_SHA256.json').write_text(json.dumps(inputs,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    with zipfile.ZipFile(DEST/'source-and-bit.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for name,digest in sorted(inputs.items()):
            data=(ROOT/name).read_bytes()
            if hashlib.sha256(data).hexdigest()!=digest:raise RuntimeError('归档输入变化 '+name)
            archive.writestr('source_snapshot/'+name,data)
        for name in ('SOURCE_SHA256.json','av_media.bit','verification.json'):
            archive.write(DEST/name,name)
    with zipfile.ZipFile(DEST/'source-and-bit.zip') as archive:
        if archive.testzip() is not None:raise RuntimeError('ZIP校验失败')
        for name,digest in inputs.items():
            if hashlib.sha256(archive.read('source_snapshot/'+name)).hexdigest()!=digest:
                raise RuntimeError('ZIP源文件校验失败 '+name)
    if not check_reports.manifest_matches():raise RuntimeError('归档期间构建清单变化')
    (DEST/'README.md').write_text(
        '# HDMI-B音量与音频菜单\n\n烧录av_media.bit；操作教学见AUDIO_VOLUME_20261022.md。\n\n'
        '主页面上排中间音频 -> 音量/静音/波形/恢复默认。0..100%节目幅度、确认生效、平滑增益，应急警笛旁路。\n\n'
        '显示器自身必须取消静音。此发布经过仿真与完整P&R，尚待板级听感与画面验证。\n\n'
        '旧加密SDRAM跨域setup负余量单列，不代表全工程时序闭合。原音频启动版仍保留，未修改TF卡。\n',
        encoding='utf-8',newline='\n')
    sums=[check_reports.sha256(p)+'  '+p.relative_to(DEST).as_posix() for p in sorted(DEST.rglob('*')) if p.is_file()]
    (DEST/'SHA256SUMS.txt').write_text('\n'.join(sums)+'\n',encoding='utf-8',newline='\n')
    for line in sums:
        digest,name=line.split('  ',1)
        if check_reports.sha256(DEST/name)!=digest:raise RuntimeError('发布回读失败 '+name)
    print('AUDIO_VOLUME_PACKAGE PASS '+str(DEST/'av_media.bit'))


if __name__=='__main__':main()
