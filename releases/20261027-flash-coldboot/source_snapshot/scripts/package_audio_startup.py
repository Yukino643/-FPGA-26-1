"""归档已验收的音频启动版本；任何门限失败均不创建发布目录。"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
import check_reports

ROOT = Path(__file__).resolve().parents[1]
PHY = ROOT/'td_prj/av_media_Runs/phy_1'
DEST = ROOT/'releases/20261022-audio-startup'


def main():
    result = subprocess.run([sys.executable, '-B', str(ROOT/'scripts/check_audio_startup.py')],
                            cwd=ROOT, capture_output=True)
    if result.returncode:
        raise RuntimeError('发布门限失败：'+result.stdout.decode('utf-8',errors='replace')+
                           result.stderr.decode('utf-8',errors='replace'))
    if DEST.exists():
        raise RuntimeError('发布目录已存在，不覆盖：'+str(DEST))
    inputs = {Path(p).relative_to(ROOT).as_posix():check_reports.sha256(p)
              for p in check_reports.source_files()}
    for directory in ('sim', 'scripts'):
        for path in (ROOT/directory).rglob('*'):
            if path.is_file() and '__pycache__' not in path.parts:
                inputs[path.relative_to(ROOT).as_posix()] = check_reports.sha256(path)
    for path in (ROOT/'.trellis/tasks/10-22-audio-startup').rglob('*'):
        if path.is_file():
            inputs[path.relative_to(ROOT).as_posix()] = check_reports.sha256(path)
    extra = ['docs/AUDIO_STARTUP_20261022.md', '.trellis/spec/embedded/audio-startup.md',
             'releases/20261022-main-ui/SOURCE_SHA256.json']
    for name in extra:
        inputs[name] = check_reports.sha256(ROOT/name)
    DEST.mkdir(parents=True)
    for name in ('av_media.bit','av_media_phy.area','av_media_pr.timing','av_media_phy.ts','build_manifest.sha256','av_media.prj'):
        shutil.copy2(PHY/name,DEST/name)
    shutil.copy2(ROOT/'docs/AUDIO_STARTUP_20261022.md',DEST/'AUDIO_STARTUP_20261022.md')
    shutil.copy2(ROOT/'build/720p/audio-startup/verification.json',DEST/'verification.json')
    (DEST/'check_audio_startup.log').write_bytes(result.stdout)
    evidence=DEST/'validation'
    evidence.mkdir()
    for name in ('results.json','run_status.json','wav_index.log','wav_startup.log','wav_startup_legacy.log',
                 'wav_startup_bad.log','wav_startup_missing.log','current_source_reports.log','current_resize_timing.log'):
        shutil.copy2(ROOT/'build/720p/regression'/name,evidence/name)
    for name in ('resize_timing','subtitle_timing'):
        shutil.copytree(ROOT/'build/720p'/name,evidence/name)
    (DEST/'SOURCE_SHA256.json').write_text(json.dumps(inputs,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    with zipfile.ZipFile(DEST/'source-and-bit.zip','w',compression=zipfile.ZIP_DEFLATED) as archive:
        for name,digest in sorted(inputs.items()):
            data=(ROOT/name).read_bytes()
            if hashlib.sha256(data).hexdigest()!=digest:
                raise RuntimeError('归档期间输入变化：'+name)
            archive.writestr('source_snapshot/'+name,data)
        archive.write(DEST/'SOURCE_SHA256.json','SOURCE_SHA256.json')
        archive.write(DEST/'av_media.bit','av_media.bit')
        archive.write(DEST/'verification.json','verification.json')
    with zipfile.ZipFile(DEST/'source-and-bit.zip') as archive:
        if archive.testzip() is not None:
            raise RuntimeError('ZIP校验失败')
        for name,digest in inputs.items():
            if hashlib.sha256(archive.read('source_snapshot/'+name)).hexdigest()!=digest:
                raise RuntimeError('ZIP源文件校验失败：'+name)
    if not check_reports.manifest_matches():
        raise RuntimeError('归档期间构建清单变化')
    (DEST/'README.md').write_text(
        '# 20261022-audio-startup\n\n烧录文件：`av_media.bit`。完整说明见`AUDIO_STARTUP_20261022.md`。\n\n'
        'FAT32根目录直接定位WAV，不再等待首图或从LBA0逐扇区扫描。完整回归及严格域内时序通过；尚待上板测首声时间。\n\n'
        'WAV保持原有标准44字节头、48kHz/16bit/双声道、物理连续存放要求。本轮不改TF卡文件。\n\n'
        '旧加密SDRAM跨域setup负余量仍单列，不能声称全工程时序闭合。\n\n'
        '`source-and-bit.zip`含本轮RTL/工程输入、仿真、脚本与任务快照，非TD安装包；重建仍需本机工具链。\n',
        encoding='utf-8',newline='\n')
    sums=[]
    for path in sorted(DEST.rglob('*')):
        if path.is_file():
            sums.append(check_reports.sha256(path)+'  '+path.relative_to(DEST).as_posix())
    (DEST/'SHA256SUMS.txt').write_text('\n'.join(sums)+'\n',encoding='utf-8',newline='\n')
    for line in sums:
        digest,name=line.split('  ',1)
        if check_reports.sha256(DEST/name)!=digest:
            raise RuntimeError('发布回读校验失败：'+name)
    print('AUDIO_STARTUP_PACKAGE PASS '+str(DEST/'av_media.bit'))


if __name__=='__main__':
    main()
