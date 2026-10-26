"""签发无声视频实验包：保留稳定发布，核对仿真输入及真实P&R，拒绝旧bit混用。"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

import check_reports

ROOT = Path(__file__).resolve().parents[1]
PHY = ROOT/'td_prj/av_media_Runs/phy_1'
DEST = ROOT/'releases/20261025-raw-video'
REG = ROOT/'build/720p/regression'
VIDEO = ROOT/'build/raw_video'

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))

def verify():
    if not check_reports.manifest_matches() or not check_reports.project_snapshots_match():
        raise RuntimeError('输入/工程快照/bit版本不一致')
    status = read_json(REG/'run_status.json')
    results = read_json(REG/'results.json')
    if (not status['complete'] or status['filter'] is not None or status['sim_only']
            or status['finished']!=status['passed'] or len(results)<88 or not all(r['pass'] for r in results)):
        raise RuntimeError('原完整回归未全部通过')
    video_results = []
    for file in ('unit_results.json','pipeline_results.json'):
        report = read_json(VIDEO/'test'/file)
        for name,digest in report['inputs_sha256'].items():
            if check_reports.sha256(ROOT/name)!=digest:
                raise RuntimeError('视频仿真后输入变化：'+name)
        if not report['results'] or not all(r['pass'] for r in report['results']):
            raise RuntimeError('视频仿真未通过：'+file)
        video_results += report['results']
    if not {'raw0','raw1','raw2','raw3','raw4','raw5','raw6','frame_commit','pipeline'}.issubset({r['name'] for r in video_results}):
        raise RuntimeError('视频正常/错误/循环/换页测试缺项')
    for log,needle in [('pipeline_sim.log','PASS raw_video_pipeline'),('spi_budget_sim.log','PASS official SPI')]:
        text = (VIDEO/'test'/log).read_text(encoding='utf-8')
        if needle not in text or re.search(r'\bFAIL\b|\bFATAL\b|\bERROR\b',text):
            raise RuntimeError('视频日志未通过：'+log)
    if not any(row['name']=='spi_budget' for row in video_results):
        video_results.append({'name':'spi_budget','pass':True,'log':'spi_budget_sim.log'})
    for folder in ('resize_timing','subtitle_timing'):
        report=read_json(ROOT/'build/720p'/folder/'summary.json')
        if (folder=='resize_timing' and (not report or any(r[-1]<0 for r in report))) or (folder=='subtitle_timing' and report['failures']):
            raise RuntimeError('定向物理路径未通过：'+folder)
    directed = read_json(VIDEO/'timing/summary.json')
    bit_sha = check_reports.sha256(PHY/'av_media.bit')
    if directed['failures'] or directed['bit_sha256']!=bit_sha:
        raise RuntimeError('新视频路径时序未通过或bit不一致')
    timing = (PHY/'av_media_pr.timing').read_text(encoding='utf-8')
    domains={}
    for clock in ('video_clk','sd_card_clk','ext_mem_clk','hdmi_5x_clk'):
        group=re.search(r'Path Group\s*:\s*'+clock+r' -> '+clock+r'\s*\n(.*?)(?=Path Group|\Z)',timing,re.S)
        if not group:
            raise RuntimeError('缺少同域时序：'+clock)
        setup=re.search(r'Max\s*:\s*SWNS\s+([-\d.]+)ns',group[1])
        hold=re.search(r'Min\s*:\s*HWNS\s+([-\d.]+)ns',group[1])
        if not setup or not hold:
            raise RuntimeError('时序摘要缺项：'+clock)
        values={'setup_ns':float(setup[1]),'hold_ns':float(hold[1])}
        if values['setup_ns']<(0.15 if clock=='video_clk' else 0) or values['hold_ns']<0:
            raise RuntimeError('同域时序未过门：'+clock+str(values))
        domains[clock]=values
    area=(PHY/'av_media_phy.area').read_text(encoding='utf-8')
    resources={}
    for name,limit in [('lut',16660),('reg',19600),('bram9k',57),('bram32k',4),('dsp',15),('pll',3)]:
        match=re.search(r'^\s*#'+name+r'\s+(\d+)',area,re.M)
        if not match or int(match[1])>limit:
            raise RuntimeError('资源超限或缺失：'+name)
        resources[name]=int(match[1])
    global_setup=float(re.search(r'SWNS:\s*([-\d.]+)ns',timing)[1])
    global_hold=float(re.search(r'HWNS:\s*([-\d.]+)ns',timing)[1])
    if global_setup < -6.565 or global_hold<0:
        raise RuntimeError('旧全局基线恶化/hold违例')
    media=VIDEO/'media/big-blue-fish'
    metadata=read_json(media/'metadata.json')
    if check_reports.sha256(media/'VIDEO.R16')!=metadata['sha256'] or (media/'VIDEO.R16').stat().st_size!=metadata['bytes']:
        raise RuntimeError('视频素材损坏')
    return {'passed':True,'bit_sha256':bit_sha,'resources':resources,'domains':domains,
            'legacy_encrypted_SDRAM_global_setup_ns':global_setup,'global_hold_ns':global_hold,
            'regression':status,'video_tests':video_results,'media':metadata,'hardware_tested':False,
            'mode':'boot-loop 320x180 RGB565 10fps silent; HDMI-B 1280x720 nearest x4',
            'stable_commit':'1cacb41d34910553b52a49ccd69b275303539910'}

def main():
    result=verify()
    if DEST.exists():
        raise RuntimeError('禁止覆盖已有发布目录：'+str(DEST))
    DEST.mkdir(parents=True)
    for name in ('av_media.bit','av_media_phy.area','av_media_phy.ts','av_media_pr.timing','build_manifest.sha256','av_media.prj'):
        shutil.copy2(PHY/name,DEST/name)
    shutil.copytree(VIDEO/'media/big-blue-fish',DEST/'media')
    validation=DEST/'validation'
    shutil.copytree(ROOT/'build/720p/td/20261025-raw-video-seed16',validation/'td')
    shutil.copytree(ROOT/'build/720p/td/20261025-raw-video',validation/'seed14-failed')
    for name in ('resize_timing','subtitle_timing'):
        shutil.copytree(ROOT/'build/720p'/name,validation/name)
    shutil.copytree(VIDEO/'timing',validation/'raw_video_timing')
    for folder,target in [(VIDEO/'test',validation/'video_tests'),(REG,validation/'regression')]:
        target.mkdir()
        for path in folder.iterdir():
            if path.is_file() and (path.suffix in ('.log','.json','.vh') or path.name.endswith('.pass.sha256')):
                shutil.copy2(path,target/path.name)
    shutil.copy2(ROOT/'docs/raw-video-20261025/USAGE.md',DEST/'README.md')
    (DEST/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    paths={Path(p).relative_to(ROOT).as_posix():check_reports.sha256(p) for p in check_reports.source_files()}
    for folder in ('sim','scripts','docs/raw-video-20261025'):
        for path in (ROOT/folder).rglob('*'):
            if path.is_file() and path.suffix in ('.v','.vh','.hex','.py','.md'):
                paths[path.relative_to(ROOT).as_posix()]=check_reports.sha256(path)
    (DEST/'SOURCE_SHA256.json').write_text(json.dumps(paths,indent=2)+'\n',encoding='utf-8',newline='\n')
    with zipfile.ZipFile(DEST/'source-and-bit.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for name,digest in sorted(paths.items()):
            data=(ROOT/name).read_bytes()
            if hashlib.sha256(data).hexdigest()!=digest:
                raise RuntimeError('归档时输入变化：'+name)
            archive.writestr('source_snapshot/'+name,data)
    with zipfile.ZipFile(DEST/'source-and-bit.zip') as archive:
        if archive.testzip() is not None:
            raise RuntimeError('发布归档CRC失败')
        for name,digest in paths.items():
            if hashlib.sha256(archive.read('source_snapshot/'+name)).hexdigest()!=digest:
                raise RuntimeError('归档回读SHA失败：'+name)
    sums=[check_reports.sha256(p)+'  '+p.relative_to(DEST).as_posix() for p in sorted(DEST.rglob('*')) if p.is_file()]
    (DEST/'SHA256SUMS.txt').write_text('\n'.join(sums)+'\n',encoding='ascii',newline='\n')
    for line in sums:
        digest,name=line.split('  ',1)
        if check_reports.sha256(DEST/name)!=digest:
            raise RuntimeError('发布回读SHA失败：'+name)
    if verify()!=result:
        raise RuntimeError('发布期间输入变化')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    print('RAW_VIDEO_PACKAGE PASS '+str(DEST/'av_media.bit'))

if __name__=='__main__':
    main()
