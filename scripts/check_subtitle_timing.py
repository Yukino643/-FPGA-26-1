"""检查监视菜单与新增字幕寄存器/字体 RAM 的实际布局后时序。"""
from pathlib import Path
import json
import re
import subprocess
import check_reports

ROOT = Path(__file__).resolve().parents[1]
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'
OUT = ROOT / 'build/720p/subtitle_timing'
TD = 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'


def main():
    if not check_reports.manifest_matches():
        raise RuntimeError('当前输入与构建清单不一致，拒绝读取旧数据库')
    OUT.mkdir(parents=True, exist_ok=True)
    targets = {'menu': 'u_monitor_menu_ctrl/*', 'config': 'u_monitor_config_regs/*',
               'renderer': 'u_mon_menu_renderer/*', 'color': 'u_color_adjust/*',
               'osd': 'u_osd/*', 'volume': 'u_pcm_volume_control/*'}
    commands = ['import_device eagle_s20.db -package EG4S20BG256',
                f'import_db {{{(PHY / "av_media_pr.db").as_posix()}}}',
                'update_timing -mode final']
    for name, pattern in targets.items():
        commands += [f'set regs [get_regs {{{pattern}}}]',
                     f'puts "REG_COUNT|{name}|[llength $regs]"',
                     'if {[llength $regs] == 0} {error "Empty timing target"}']
        for direction in ('from', 'to'):
            report = OUT / f'{name}_{direction}.timing'
            report.unlink(missing_ok=True)
            commands.append(f'report_timing_path -{direction} $regs -ep_num 5 -file {{{report.as_posix()}}}')
    # 与缩放器检查相同，物理 BRAM 使用 report_cells 检查所有入出引脚。
    commands += ['set font_cells [concat [get_cells -hier *u_osd/u_font*] [get_cells -hier *u_mon_menu_renderer/u_font_cjk*]]',
                 'if {[llength $font_cells] == 0} {error "Empty font RAM target"}',
                 'foreach cell $font_cells {foreach check {setup hold} {',
                 'puts "FONT_BEGIN|$check|$cell"',
                 'if {$check eq "hold"} {report_cells $cell -timing -hold -mode final} else {report_cells $cell -timing -mode final}',
                 'puts "FONT_END"', '}}', 'exit']
    tcl = OUT / 'check.tcl'
    tcl.write_text('\n'.join(commands) + '\n', encoding='utf-8', newline='\n')
    proc = subprocess.run([TD, tcl.as_posix()], input=b'exit\n', capture_output=True, cwd=OUT, timeout=180)
    raw = proc.stdout + proc.stderr
    (OUT / 'console.log').write_bytes(raw)
    try:
        console = raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        console = raw.decode('gb18030')
    (OUT / 'console_utf8.log').write_text(console.replace('\r\n', '\n'), encoding='utf-8', newline='\n')
    if proc.returncode or re.search(r"\b[A-Z]+-\d+ ERROR|invalid command|wrong # args|Empty .* target|couldn't read file", console):
        raise RuntimeError(f'TD 时序查询失败: {OUT / "console_utf8.log"}')
    summary = {}
    for name in targets:
        for direction in ('from', 'to'):
            report = (OUT / f'{name}_{direction}.timing').read_text(encoding='utf-8')
            real = report.split('Path Group     :     Set Clock Groups')[0]
            maxima = [float(v) for v in re.findall(r'Max\s*:\s*SWNS\s+([-0-9.]+)ns', real)]
            minima = [float(v) for v in re.findall(r'Min\s*:\s*HWNS\s+([-0-9.]+)ns', real)]
            if not maxima or len(maxima) != len(minima):
                raise RuntimeError(f'缺少完整 Max/Min 统计: {name} {direction}')
            summary[f'{name}_{direction}'] = {'max_ns': min(maxima), 'min_ns': min(minima)}
    font_summary = []
    for check, cell, report in re.findall(r'FONT_BEGIN\|(setup|hold)\|([^\r\n]+)\r?\n(.*?)FONT_END', console, re.S):
        if 'EG_PHY_BRAM' not in report:
            continue
        for direction, title in (('in', 'Input'), ('out', 'Output')):
            section = re.search(title + r' Pin\(s\):(.*?)(?=Output Pin\(s\):|$)', report, re.S)
            values = re.findall(r'^.*?:\s*\d+\s*\|[^|]+\|[^|]+\|\s*(-?\d+)\s*$', section.group(1) if section else '', re.M)
            if not values:
                raise RuntimeError(f'字体 RAM 缺少有效引脚余量: {cell} {check} {direction}')
            font_summary.append([cell, direction, check, min(map(int, values)) / 1000])
    if not any('u_osd/u_font' in row[0] for row in font_summary) or not any('u_mon_menu_renderer/u_font_cjk' in row[0] for row in font_summary):
        raise RuntimeError('必须同时覆盖 HDMI-A 中文字体与 HDMI-B OSD 字体 RAM')
    failures = [(name, item) for name, item in summary.items() if min(item.values()) < 0]
    failures += [row for row in font_summary if row[-1] < 0]
    result = {'summary': summary, 'font_pins': font_summary, 'failures': failures,
              'method': 'TD Max/Min SWNS/HWNS includes recovery/removal; asynchronous Set Clock Groups excluded; physical font RAM pins in ps'}
    (OUT / 'summary.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(result, indent=2))
    if not check_reports.manifest_matches() or failures:
        raise RuntimeError(f'字幕或菜单时序检查失败: {failures}')
    print('SUBTITLE_TIMING PASS current-source menu/config/renderer/color/OSD/volume and font RAM pins')


if __name__ == '__main__':
    main()
