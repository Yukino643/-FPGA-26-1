"""检查当前实验bit中视频读取器/簇链/换页调度器的入出时序；不放宽约束。"""
from pathlib import Path
import json
import re
import subprocess

import check_reports

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/raw_video/timing'
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'
TD = 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'

def main():
    if not check_reports.manifest_matches():
        raise RuntimeError('当前bit与源码不一致，拒绝查询旧数据库')
    OUT.mkdir(parents=True, exist_ok=True)
    commands = ['import_device eagle_s20.db -package EG4S20BG256',
                f'import_db {{{(PHY/"av_media_pr.db").as_posix()}}}', 'update_timing -mode final']
    targets = {'player': '*g_raw_video*', 'commit': '*g_video_commit*'}
    for name, pattern in targets.items():
        commands += [f'set regs [get_regs {{{pattern}}}]', f'puts "REG_COUNT|{name}|[llength $regs]"',
                     'if {[llength $regs] == 0} {error "Empty raw-video timing target"}']
        for direction in ('from', 'to'):
            report = OUT / f'{name}_{direction}.timing'
            report.unlink(missing_ok=True)
            commands.append(f'report_timing_path -{direction} $regs -ep_num 10 -file {{{report.as_posix()}}}')
    commands.append('exit')
    tcl = OUT/'check.tcl'
    tcl.write_text('\n'.join(commands)+'\n', encoding='utf-8', newline='\n')
    proc = subprocess.run([TD, tcl.as_posix()], input=b'exit\n', capture_output=True, cwd=OUT, timeout=180)
    raw = proc.stdout+proc.stderr
    (OUT/'console.log').write_bytes(raw)
    try:
        console = raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        console = raw.decode('gb18030')
    (OUT/'console_utf8.log').write_text(console.replace('\r\n','\n'), encoding='utf-8', newline='\n')
    if proc.returncode or re.search(r"\b[A-Z]+-\d+ ERROR|Empty raw-video|invalid command|wrong # args|couldn't read file", console):
        raise RuntimeError('视频定向时序查询失败，见 '+str(OUT/'console_utf8.log'))
    summary = {}
    for name in targets:
        for direction in ('from','to'):
            text = (OUT/f'{name}_{direction}.timing').read_text(encoding='utf-8').split('Path Group     :     Set Clock Groups')[0]
            setup = [float(v) for v in re.findall(r'Max\s*:\s*SWNS\s+([-0-9.]+)ns',text)]
            hold = [float(v) for v in re.findall(r'Min\s*:\s*HWNS\s+([-0-9.]+)ns',text)]
            if not setup or not hold:
                raise RuntimeError('视频定向报告缺少有效setup/hold：'+name+' '+direction)
            summary[f'{name}_{direction}']={'setup_ns':min(setup),'hold_ns':min(hold)}
    failures = {name:value for name,value in summary.items() if min(value.values())<0}
    (OUT/'summary.json').write_text(json.dumps({'summary':summary,'failures':failures,
        'bit_sha256':check_reports.sha256(PHY/'av_media.bit')},indent=2)+'\n',encoding='utf-8',newline='\n')
    if failures:
        raise RuntimeError('新增视频路径未闭合：'+str(failures))
    if not check_reports.manifest_matches():
        raise RuntimeError('查询期间输入发生变化')
    print('RAW_VIDEO_TIMING PASS player/FAT/mapper/6VS scheduler setup and hold')

if __name__=='__main__':
    main()
