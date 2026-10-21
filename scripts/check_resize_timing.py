"""基于当前P&R数据库检查新增缩放器路径；不以全局SDRAM旧基线放行新路径。"""
from pathlib import Path
import json
import re
import subprocess
import check_reports

ROOT = Path(__file__).resolve().parents[1]
PHY = ROOT / 'td_prj/av_media_Runs/phy_1'
OUTPUT = ROOT / 'build/720p/resize_timing'
TD = Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')


def path_slacks(text):
    return [(float(slack), check) for slack, check in re.findall(
        r'Slack\s*:\s*([-0-9.]+)ns\s*\n.*?Check Type\s*:\s*(\w+)', text, re.S)]


def ram_slacks(console):
    """TD6.2的report_cells引脚余量单位为ps，-hold选择最小延迟检查。"""
    result = []
    for check, cell, report in re.findall(r'RAM_BEGIN\|(setup|hold)\|([^\r\n]+)\r?\n(.*?)RAM_END', console, re.S):
        if 'EG_PHY_BRAM32K' not in report:
            raise RuntimeError(f'RAM类型不符合预期: {cell}')
        for direction, title in [('in', 'Input'), ('out', 'Output')]:
            section = re.search(title + r' Pin\(s\):(.*?)(?=Output Pin\(s\):|$)', report, re.S)
            values = re.findall(r'^.*?:\s*\d+\s*\|[^|]+\|[^|]+\|\s*(-?\d+)\s*$',
                                section.group(1) if section else '', re.M)
            if not values:
                raise RuntimeError(f'RAM引脚缺少有效余量: {cell} {check} {direction}')
            result.append((f'{cell}/{direction}', check, min(map(int, values))/1000))
    if len(result) != 16:
        raise RuntimeError(f'应覆盖4块物理RAM的setup/hold入出引脚，实际只有{len(result)}组')
    return result


def main():
    if not check_reports.manifest_matches():
        raise RuntimeError('拒绝读取与当前源码/bit不匹配的构建数据库')
    if not (PHY / 'av_media_pr.db').is_file():
        raise RuntimeError('缺少本轮P&R数据库')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    targets = {
        'from_regs': ('-from', '[get_regs {u_resize_frame/*}]'),
        'to_regs': ('-to', '[get_regs {u_resize_frame/*}]'),
    }
    commands = ['import_device eagle_s20.db -package EG4S20BG256',
                f'import_db {{{(PHY / "av_media_pr.db").as_posix()}}}', 'update_timing -mode final']
    for name, (direction, objects) in targets.items():
        report = OUTPUT / f'{name}.timing'
        if report.exists():
            report.unlink()
        commands.append(f'report_timing_path {direction} {objects} -ep_num 10 -file {{{report.as_posix()}}}')
    # 本机TD无法将BRAM32K作为report_timing_path筛选端点；官方report_cells可报告全部引脚余量。
    commands += ['set ram_cells [concat [get_cells -hier *source_line*] [get_cells -hier *output_line*]]',
                 'if {[llength $ram_cells] != 4} {error "Expected four physical resize RAM cells"}',
                 'foreach cell $ram_cells {foreach check {setup hold} {',
                 'puts "RAM_BEGIN|$check|$cell"',
                 'if {$check eq "hold"} {report_cells $cell -timing -hold -mode final} else {report_cells $cell -timing -mode final}',
                 'puts "RAM_END"', '}}']
    commands.append('exit')
    tcl = OUTPUT / 'check.tcl'
    tcl.write_text('\n'.join(commands) + '\n', encoding='utf-8', newline='\n')
    log = OUTPUT / 'console.log'
    with log.open('wb') as stream:
        result = subprocess.run([TD.as_posix(), tcl.as_posix()], input=b'exit\n', cwd=OUTPUT,
                                stdout=stream, stderr=subprocess.STDOUT, timeout=180)
    # TD本机原生stdout的中文用户名采用GBK；保留原始证据，另存严格解码的UTF-8副本。
    raw_console = log.read_bytes()
    try:
        console = raw_console.decode('utf-8-sig')
    except UnicodeDecodeError:
        console = raw_console.decode('gb18030')
    (OUTPUT / 'console_utf8.log').write_text(console.replace('\r\n', '\n'), encoding='utf-8', newline='\n')
    if result.returncode or re.search(r"\b[A-Z]+-\d+ ERROR|invalid command|wrong # args|couldn't read file", console):
        raise RuntimeError(f'TD时序查询失败: {log}')
    failures = []
    summary = []
    for name in targets:
        report = OUTPUT / f'{name}.timing'
        if not report.is_file():
            raise RuntimeError(f'TD未生成定向报告: {report}')
        values = path_slacks(report.read_text(encoding='utf-8', errors='replace'))
        if not values:
            raise RuntimeError(f'未查到有效路径，不能声称通过: {report}')
        # TD 展示的前十条 Min 路径可能全部为复位 removal，不能据此
        # 声称没有 hold 数据。完整 Max/Min 摘要覆盖全部 setup/hold
        # 及 recovery/removal，且异步 Set Clock Groups 必须排除。
        text = report.read_text(encoding='utf-8').split('Path Group     :     Set Clock Groups')[0]
        maxima = [float(v) for v in re.findall(r'Max\s*:\s*SWNS\s+([-0-9.]+)ns', text)]
        minima = [float(v) for v in re.findall(r'Min\s*:\s*HWNS\s+([-0-9.]+)ns', text)]
        if not maxima or len(maxima) != len(minima):
            raise RuntimeError(f'缺少完整 Max/Min 统计: {report}')
        for check, worst in (('max_setup_recovery', min(maxima)), ('min_hold_removal', min(minima))):
            print(f'[RESIZE_TIMING] {name} {check}={worst:.3f}ns')
            summary.append((name, check, worst))
            if worst < 0:
                failures.append((name, check, worst))
    for name, check, worst in ram_slacks(console):
        print(f'[RESIZE_TIMING] {name} {check}={worst:.3f}ns')
        summary.append((name, check, worst))
        if worst < 0:
            failures.append((name, check, worst))
    (OUTPUT / 'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8', newline='\n')
    if not check_reports.manifest_matches():
        raise RuntimeError('只读时序查询期间构建输入发生变化')
    if failures:
        raise RuntimeError(f'新增缩放路径仍有负余量: {failures}')
    print('[RESIZE_TIMING] PASS current-source registers/RAM incoming/outgoing paths')


if __name__ == '__main__':
    main()
