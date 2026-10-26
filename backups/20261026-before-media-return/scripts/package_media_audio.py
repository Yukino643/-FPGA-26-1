"""有声融合版签发：当前源码/bit、实际测试依赖、完整回归及物理门限全部过门。"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

import check_reports
from verify_media_runtime import PIPE

ROOT=Path(__file__).resolve().parents[1]
PHY=ROOT/'td_prj/av_media_Runs/phy_1'
DEST=ROOT/'releases/20261025-media-audio'
REG=ROOT/'build/720p/regression'
TEST=ROOT/'build/media_runtime/test'
MEDIA=ROOT/'build/media_audio/media/big-blue-fish'
TD=ROOT/'build/media_audio/td-stream-bounds-seed15'

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))

def sha(path):
    return check_reports.sha256(path)

def tested_inputs(path, required=None):
    report=read_json(path)
    if not report.get('pass',False) and not (report.get('results') and all(r['pass'] for r in report['results'])):
        raise RuntimeError('仿真未通过：'+str(path))
    recorded=report['inputs_sha256']
    names=set(recorded) if required is None else set(required)
    for name in sorted(names):
        if name not in recorded or sha(ROOT/name)!=recorded[name]:
            raise RuntimeError('测试实际依赖缺失或变化：'+name+' @ '+str(path))
    # 旧流水报告记录了整个rtl/sim目录。只允许无关文件变化，显式列入发布证据；
    # 不改写旧报告，也不因菜单文案变化重跑不实例化renderer的存储流水。
    unrelated=[name for name,digest in recorded.items() if name not in names and sha(ROOT/name)!=digest]
    return {'report':path.relative_to(ROOT).as_posix(),'required_inputs':len(names),
            'unrelated_changed_inputs':unrelated}

def verify():
    if not check_reports.manifest_matches() or not check_reports.project_snapshots_match():
        raise RuntimeError('当前源码/工程/bit不一致')
    status=read_json(REG/'run_status.json');results=read_json(REG/'results.json')
    if (not status['complete'] or status['filter'] is not None or status['sim_only']
            or not status['subtitle_cycle_raster_export'] or status['finished']!=status['passed']
            or len(results)!=status['finished'] or len(results)<88 or not all(r['pass'] for r in results)):
        raise RuntimeError('完整回归及字幕完整栅格尚未通过')
    # 显式核验本轮报告，不允许旧all_results掩盖新case7或新音频依赖。
    evidence=[tested_inputs(TEST/'unit_results.json'),tested_inputs(TEST/'audio_results.json'),
              tested_inputs(ROOT/'build/media_audio/waveform-tdm/results.json'),
              tested_inputs(ROOT/'build/media_audio/bmp-timing/results.json')]
    bmp=ROOT/'build/media_audio/bmp-timing'
    if read_json(bmp/'results.json')['gaps']!=[0,1,7]:
        raise RuntimeError('BMP逐拍等价验证缺少连续/间歇输入')
    for gap in (0,1,7):
        log=(bmp/f'equiv{gap}_simulation.log').read_text(encoding='utf-8')
        if not re.search(rf'TB_BMP_TIMING_EQUIV PASS cases=13 cycles=\d+ gap={gap} compares=300163',log) or re.search(r'\bFAIL\b|\bERROR\b|\bFATAL\b',log):
            raise RuntimeError('BMP逐拍等价日志失败：'+str(gap))
    waveform_log=(ROOT/'build/media_audio/waveform-tdm/simulation.log').read_text(encoding='utf-8')
    if 'TB_WAVEFORM_TDM PASS exact_columns=143520' not in waveform_log or re.search(r'\bFAIL\b|\bERROR\b|\bFATAL\b',waveform_log):
        raise RuntimeError('波形分时读取等价验证失败或缺项')
    required=set(PIPE)|{'rtl/top/top_tf_hdmi_audio.v'}
    for case in (0,1,2,7):
        evidence.append(tested_inputs(TEST/f'pipeline{case}_results.json',required))
        text=(TEST/f'pipeline{case}.log').read_text(encoding='utf-8')
        if 'PASS media_pipeline' not in text or re.search(r'\bFAIL\b|\bERROR\b|\bFATAL\b',text):
            raise RuntimeError('媒体流水日志失败：'+str(case))
    evidence.append(tested_inputs(ROOT/'build/media_runtime/bounds/results.json'))
    raw_deps={'sim/tb_raw_video.v','sim/raw_video_card_model.v','rtl/sd/raw_video_player.v',
              'rtl/sd/fat32_bmp_index.v','rtl/sd/fat32_file_sector_mapper.v',
              'sim/tb_video_frame_commit.v','rtl/video/video_frame_commit.v',
              'sim/tb_video_spi_budget.v','rtl/sd/sd_card_cmd.v','rtl/sd/spi_master.v'}
    raw=ROOT/'build/raw_video/test'
    evidence.append(tested_inputs(raw/'unit_results.json',raw_deps))
    raw_results=read_json(raw/'unit_results.json')['results']
    if not {'spi_budget','frame_commit',*[f'raw{n}' for n in range(7)]}.issubset({r['name'] for r in raw_results}):
        raise RuntimeError('原视频解析器/错误/SPI测试缺项')
    for folder in (raw,TEST):
        for name in ('header.hex','frame0.hex','frame1.hex'):
            if sha(folder/name)!=sha((ROOT/'build/raw_video/media/big-blue-fish')/name):
                raise RuntimeError('仿真素材与发布素材不一致：'+str(folder/name))
    # v1夹具保留兼容测试；发布素材v2的帧数据必须逐字节相同，头/原轨独立解析。
    for name in ('frame0.hex','frame1.hex'):
        if sha(TEST/name)!=sha(MEDIA/name):
            raise RuntimeError('v2发布帧与流水测试帧不一致：'+name)
    asset=read_json(ROOT/'build/media_audio/asset_verification.json')
    if not asset['pass'] or asset['file_sha256']!=sha(MEDIA/'VIDEO.R16'):
        raise RuntimeError('有声素材独立核验缺失或不一致')
    directed=read_json(ROOT/'build/media_runtime/timing/summary.json')
    bit_sha=sha(PHY/'av_media.bit')
    if directed['failures'] or directed['bit_sha256']!=bit_sha:
        raise RuntimeError('媒体定向时序未过门或版本不一致')
    timing_evidence={}
    for folder in ('resize_timing','subtitle_timing'):
        report=read_json(ROOT/'build/720p'/folder/'summary.json')
        binding=read_json(ROOT/'build/media_runtime'/f'{folder}_binding.json')
        if binding!={'bit_sha256':bit_sha,'summary_sha256':sha(ROOT/'build/720p'/folder/'summary.json')}:
            raise RuntimeError('定向时序与当前bit绑定不一致：'+folder)
        if (folder=='resize_timing' and (not report or any(r[-1]<0 for r in report))) or (folder=='subtitle_timing' and report['failures']):
            raise RuntimeError('定向时序未通过：'+folder)
        timing_evidence[folder]=binding
    timing=(PHY/'av_media_pr.timing').read_text(encoding='utf-8');domains={}
    for clock in ('video_clk','sd_card_clk','ext_mem_clk','hdmi_5x_clk'):
        group=re.search(r'Path Group\s*:\s*'+clock+r' -> '+clock+r'\s*\n(.*?)(?=Path Group|\Z)',timing,re.S)
        if not group:raise RuntimeError('缺少同域时序：'+clock)
        setup=re.search(r'Max\s*:\s*SWNS\s+([-\d.]+)ns',group[1]);hold=re.search(r'Min\s*:\s*HWNS\s+([-\d.]+)ns',group[1])
        if not setup or not hold:raise RuntimeError('缺少setup/hold：'+clock)
        values={'setup_ns':float(setup[1]),'hold_ns':float(hold[1])}
        if values['setup_ns']<(0.15 if clock=='video_clk' else 0) or values['hold_ns']<0:
            raise RuntimeError('同域时序未过门：'+clock+str(values))
        domains[clock]=values
    area=(PHY/'av_media_phy.area').read_text(encoding='utf-8');resources={}
    for name,limit in [('lut',16660),('reg',19600),('bram9k',57),('bram32k',4),('dsp',15),('pll',3)]:
        found=re.search(r'^\s*#'+name+r'\s+(\d+)',area,re.M)
        if not found or int(found[1])>limit:raise RuntimeError('资源超限或缺失：'+name)
        resources[name]=int(found[1])
    global_setup=float(re.search(r'SWNS:\s*([-\d.]+)ns',timing)[1])
    global_hold=float(re.search(r'HWNS:\s*([-\d.]+)ns',timing)[1])
    if global_setup < -6.565 or global_hold<0:raise RuntimeError('旧全局基线恶化/hold违例')
    metadata=read_json(MEDIA/'metadata.json')
    if sha(MEDIA/'VIDEO.R16')!=metadata['sha256'] or (MEDIA/'VIDEO.R16').stat().st_size!=metadata['bytes']:
        raise RuntimeError('视频素材损坏')
    if sha(TD/'av_media.bit')!=bit_sha:raise RuntimeError('最终构建档案与发布bit不符')
    return {'passed':True,'release':'20261025-media-audio','bit_sha256':bit_sha,
            'resources':resources,'lut_delta_from_picture_release':resources['lut']-14815,
            'domains':domains,'legacy_encrypted_SDRAM_global_setup_ns':global_setup,
            'global_hold_ns':global_hold,'regression':status,'test_inputs':evidence,
            'directed_timing':timing_evidence,'raw_tests':raw_results,'media':metadata,
            'hardware_tested':False,'boot_mode':'picture/WAV',
            'video':'320x180 RGB565 10fps; v1 silent / v2 original-track PCM; frame-budget pause/resume',
            'audio':'v2 48kHz signed16LE stereo; 4800 samples/video frame; WAV restarts on return; emergency preserved',
            'asset_verification':asset,
            'mode_switch':'retain complete front page; load opposite page; 32-frame picture fade',
            'stable_commit':'1cacb41d34910553b52a49ccd69b275303539910'}

def main():
    result=verify()
    if DEST.exists():raise RuntimeError('拒绝覆盖已有发布：'+str(DEST))
    DEST.mkdir(parents=True)
    for name in ('av_media.bit','av_media_phy.area','av_media_phy.ts','av_media_pr.timing','build_manifest.sha256','av_media.prj'):
        shutil.copy2(PHY/name,DEST/name)
    shutil.copytree(MEDIA,DEST/'media')
    validation=DEST/'validation';validation.mkdir()
    shutil.copytree(TD,validation/'td')
    for folder in ('resize_timing','subtitle_timing'):
        shutil.copytree(ROOT/'build/720p'/folder,validation/folder)
        shutil.copy2(ROOT/'build/media_runtime'/f'{folder}_binding.json',validation/f'{folder}_binding.json')
    shutil.copytree(ROOT/'build/media_runtime/timing',validation/'media_timing')
    shutil.copytree(ROOT/'build/media_runtime/bounds',validation/'bounds')
    shutil.copy2(ROOT/'build/media_audio/asset_verification.json',validation/'asset_verification.json')
    shutil.copytree(ROOT/'build/media_audio/waveform-tdm',validation/'waveform-tdm',
                    ignore=shutil.ignore_patterns('*.vvp'))
    bmp_target=validation/'bmp-timing';bmp_target.mkdir()
    for name in ('results.json','bmp_read_g_ref.v',*[f'equiv{g}_{step}.log' for g in (0,1,7) for step in ('compile','simulation')]):
        shutil.copy2(ROOT/'build/media_audio/bmp-timing'/name,bmp_target/name)
    for folder,label in [(TEST,'media_tests'),(ROOT/'build/raw_video/test','raw_tests'),(REG,'regression')]:
        target=validation/label;target.mkdir()
        for path in folder.iterdir():
            if path.is_file() and (path.suffix in ('.log','.json','.vh','.png') or path.name.endswith('.pass.sha256')):
                shutil.copy2(path,target/path.name)
    shutil.copytree(ROOT/'docs/media-audio-20261025',DEST/'docs')
    shutil.copy2(ROOT/'docs/media-audio-20261025/USAGE.md',DEST/'README.md')
    (DEST/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    paths={Path(p).relative_to(ROOT).as_posix():sha(p) for p in check_reports.source_files()}
    for folder in ('sim','scripts','docs/media-audio-20261025','.trellis/spec/embedded'):
        for path in (ROOT/folder).rglob('*'):
            if path.is_file() and path.suffix in ('.v','.vh','.hex','.py','.md'):
                paths[path.relative_to(ROOT).as_posix()]=sha(path)
    (DEST/'SOURCE_SHA256.json').write_text(json.dumps(paths,indent=2)+'\n',encoding='utf-8',newline='\n')
    with zipfile.ZipFile(DEST/'source-and-bit.zip','w',zipfile.ZIP_DEFLATED) as archive:
        archive.write(DEST/'av_media.bit','av_media.bit')
        for name,digest in sorted(paths.items()):
            data=(ROOT/name).read_bytes()
            if hashlib.sha256(data).hexdigest()!=digest:raise RuntimeError('归档中输入变化：'+name)
            archive.writestr('source_snapshot/'+name,data)
    with zipfile.ZipFile(DEST/'source-and-bit.zip') as archive:
        if archive.testzip() is not None:raise RuntimeError('归档CRC失败')
        if hashlib.sha256(archive.read('av_media.bit')).hexdigest()!=result['bit_sha256']:
            raise RuntimeError('归档bit回读SHA失败')
        for name,digest in paths.items():
            if hashlib.sha256(archive.read('source_snapshot/'+name)).hexdigest()!=digest:
                raise RuntimeError('归档回读SHA失败：'+name)
    sums=[sha(p)+'  '+p.relative_to(DEST).as_posix() for p in sorted(DEST.rglob('*')) if p.is_file()]
    (DEST/'SHA256SUMS.txt').write_text('\n'.join(sums)+'\n',encoding='ascii',newline='\n')
    for line in sums:
        digest,name=line.split('  ',1)
        if sha(DEST/name)!=digest:raise RuntimeError('发布回读SHA失败：'+name)
    if verify()!=result:raise RuntimeError('发布期间输入变化')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    print('MEDIA_AUDIO_PACKAGE PASS '+str(DEST/'av_media.bit'))

if __name__=='__main__':main()
