"""主屏UI追加门限；不以基础报告PASS替代video>=0.15ns或完整回归。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import check_reports

ROOT=Path(__file__).resolve().parents[1]
PHY=ROOT/'td_prj/av_media_Runs/phy_1'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--physical-only',action='store_true')
    args=parser.parse_args()
    if not check_reports.manifest_matches():
        raise RuntimeError('当前源码/bit/工程快照清单不匹配')
    timing=(PHY/'av_media_pr.timing').read_text(encoding='utf-8')
    area=(PHY/'av_media_phy.area').read_text(encoding='utf-8')
    failures=[]
    domains={}
    for clock in ('sd_card_clk','video_clk','ext_mem_clk','hdmi_5x_clk'):
        m=re.search(r'Path Group\s*:\s*'+re.escape(clock)+r' -> '+re.escape(clock)+r'\s*\n(.*?)(?=Path Group|\Z)',timing,re.S)
        if not m: raise RuntimeError('缺少域内路径 '+clock)
        setup=re.search(r'Max\s*:\s*SWNS\s+([-\d.]+)ns',m.group(1))
        hold=re.search(r'Min\s*:\s*HWNS\s+([-\d.]+)ns',m.group(1))
        if not setup or not hold: raise RuntimeError('缺少域内Max/Min '+clock)
        setup,hold=float(setup.group(1)),float(hold.group(1))
        domains[clock]={'setup_ns':setup,'hold_ns':hold}
        threshold=.15 if clock=='video_clk' else 0
        if setup<threshold or hold<0: failures.append([clock,setup,hold,threshold])
    resources={}
    for key,limit in (('lut',16660),('reg',19600),('bram9k',57),('bram32k',4),('dsp',13),('pll',3)):
        m=re.search(r'^#'+key+r'\s+(\d+)|^\s+#'+key+r'\s+(\d+)',area,re.M)
        if not m: raise RuntimeError('缺少资源行 '+key)
        count=int(m.group(1) or m.group(2))
        resources[key]=count
        if count>limit: failures.append([key,count,limit])
    global_setup=re.search(r'SWNS:\s*([-\d.]+)ns',timing)
    global_hold=re.search(r'HWNS:\s*([-\d.]+)ns',timing)
    if not global_setup or not global_hold: raise RuntimeError('缺少全局余量')
    if float(global_hold.group(1))<0: failures.append(['global_hold',global_hold.group(1)])
    if float(global_setup.group(1))< -6.565: failures.append(['legacy_SDRAM_regression',global_setup.group(1)])
    protected=json.loads((ROOT/'build/720p/main-ui-previews/source_boundaries.json').read_text(encoding='utf-8'))
    for name,digest in protected['protected_files'].items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:
            failures.append(['protected_file_changed',name])
    if len((ROOT/'rtl/video/font_720.hex').read_text(encoding='ascii').splitlines())!=2048:
        failures.append(['font_depth_changed'])
    if not args.physical_only:
        regression=ROOT/'build/720p/regression'
        status=json.loads((regression/'run_status.json').read_text(encoding='utf-8'))
        tests=json.loads((regression/'results.json').read_text(encoding='utf-8'))
        if (not status['complete'] or status['filter'] is not None or status['sim_only'] or
            status['passed']!=77 or status['finished']!=77 or len(tests)!=77 or not all(t['pass'] for t in tests) or
            not {'CURRENT_SOURCE_REPORTS','CURRENT_RESIZE_TIMING'}.issubset({t['name'] for t in tests})):
            failures.append(['full_regression_incomplete',status])
        sub=json.loads((ROOT/'build/720p/subtitle_timing/summary.json').read_text(encoding='utf-8'))
        resize=json.loads((ROOT/'build/720p/resize_timing/summary.json').read_text(encoding='utf-8'))
        if sub['failures'] or any(float(item[-1])<0 for item in resize):
            failures.append(['directed_timing_failed'])
    summary={'passed':not failures,'physical_only':args.physical_only,'domains':domains,'resources':resources,
             'legacy_encrypted_SDRAM_global_setup_ns':float(global_setup.group(1)),
             'global_hold_ns':float(global_hold.group(1)),
             'bit_sha256':hashlib.sha256((PHY/'av_media.bit').read_bytes()).hexdigest(),
             'failures':failures,'hardware_tested':False}
    out=ROOT/'build/720p/main-ui-verification.json'
    out.write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(summary,ensure_ascii=False,indent=2))
    if failures: raise RuntimeError('主屏UI验收失败，禁止发布中间bit')
    print('MAIN_UI PASS' + (' physical-only' if args.physical_only else ' full-release-gates'))


if __name__=='__main__':
    main()
