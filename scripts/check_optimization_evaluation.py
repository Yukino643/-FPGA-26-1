"""校验隔离布线输入、域内时序和缩放RAM；旧SDRAM跨域负余量单独报告。"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess

from check_resize_timing import path_slacks, ram_slacks

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('evaluate_route', ROOT / 'td_prj/evaluate_route.py')
import sys
sys.path.insert(0, str(ROOT / 'td_prj'))
evaluation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evaluation)


def summary(run):
    text = (run / 'av_media_pr.timing').read_text(encoding='utf-8-sig')
    area = (run / 'av_media_phy.area').read_text(encoding='utf-8-sig')
    groups = {}
    for clock in ('sd_card_clk', 'video_clk', 'ext_mem_clk', 'hdmi_5x_clk'):
        match = re.search(r'Path Group\s*:\s*' + clock + ' -> ' + clock + r'\s*\n(.*?)(?=Path Group|\Z)', text, re.S)
        if not match:
            raise RuntimeError(f'缺少域内时序组 {clock}')
        body = match.group(1)
        setup = re.search(r'Max\s*:\s*SWNS\s+([-0-9.]+)ns', body)
        hold = re.search(r'Min\s*:\s*HWNS\s+([-0-9.]+)ns', body)
        if not setup or not hold:
            raise RuntimeError(f'缺少setup/hold {clock}')
        groups[clock] = dict(setup=float(setup[1]), hold=float(hold[1]))
        for key, title in (('begin', 'Begin Point'), ('end', 'End Point'), ('logic', 'Logic Level')):
            value = re.search(title + r'\s*:\s*([^\r\n]+)', body)
            groups[clock][key] = value[1] if value else None
    resources = {}
    for resource in ('lut', 'reg', 'bram9k', 'bram32k', 'dsp', 'pll'):
        found = re.search(r'^\s*#' + resource + r'\s+(\d+)', area, re.M)
        if not found:
            raise RuntimeError(f'缺少资源 {resource}')
        resources[resource] = int(found[1])
    global_setup = re.search(r'SWNS:\s*([-0-9.]+)ns', text)
    global_hold = re.search(r'HWNS:\s*([-0-9.]+)ns', text)
    if not global_setup or not global_hold:
        raise RuntimeError('缺少全局setup/hold')
    clock_totals = {}
    for clock in ('video_clk', 'hdmi_5x_clk'):
        header = re.search(r'(clk\d+):\s+[0-9.]+\s+\d+\s+' + clock + r'\s*$', text, re.M)
        row = re.search(r'^\s*' + header[1] + r'\s+local\s+(.+)$', text, re.M) if header else None
        if not row or len(row[1].split()) < 10:
            raise RuntimeError(f'缺少含跨域路径的时钟摘要 {clock}')
        values = row[1].split()
        clock_totals[clock] = dict(setup=float(values[6]), hold=float(values[8]))
    return dict(groups=groups, resources=resources, clock_totals=clock_totals,
                global_setup=float(global_setup[1]), global_hold=float(global_hold[1]))


def resize_register_hold_slacks(console):
    count_match = re.search(r'RESIZE_REG_CELLS=(\d+)', console)
    if not count_match:
        raise RuntimeError('TD没有报告缩放器寄存器单元数量')
    expected = int(count_match[1])
    blocks = re.findall(r'REG_BEGIN\|([^\r\n]+)\r?\n(.*?)REG_END', console, re.S)
    names = [cell for cell, _ in blocks]
    if expected == 0 or len(blocks) != expected or len(set(names)) != expected:
        raise RuntimeError(f'缩放器寄存器覆盖不完整: expected={expected}, blocks={len(blocks)}, unique={len(set(names))}')
    values = []
    for cell, report in blocks:
        if not cell.startswith('u_resize_frame/'):
            raise RuntimeError(f'寄存器超出缩放器层级: {cell}')
        if 'Input Pin(s):' not in report or 'Output Pin(s):' not in report:
            raise RuntimeError(f'寄存器引脚报告缺少输入或输出: {cell}')
        pins = re.findall(r'^RUN-1001\s+:\s+\d+\s+\|\s*[^|]+\|[^|]+\|\s*(-?\d+|inf)\s*$',
                          report, re.M)
        finite = [int(value) for value in pins if value != 'inf']
        if not finite:
            raise RuntimeError(f'寄存器引脚没有有限hold余量: {cell}')
        values.extend(finite)
    if not values:
        raise RuntimeError('缩放器寄存器hold报告没有数值')
    return expected, len(values), min(values) / 1000


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', default='optimization-final')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9-]*', args.name):
        raise ValueError('非法评估名称')
    output = ROOT / 'build/720p' / args.name
    phy = ROOT / 'td_prj' / (args.name + '_Runs') / 'phy_1'
    expected = json.loads((output / 'inputs.json').read_text(encoding='utf-8'))
    if evaluation.snapshot() != expected:
        raise RuntimeError('评估输入与当前源码或发布bit不一致')
    if not (output / 'completed.json').is_file():
        raise RuntimeError('布线评估未完成')
    config = json.loads((output / 'flow_config.json').read_text(encoding='utf-8'))
    if hashlib.sha256((output / 'flow.tcl').read_bytes()).hexdigest() != config['sha256']:
        raise RuntimeError('隔离流程与构建记录不匹配')
    baseline = summary(ROOT / 'td_prj/av_media_Runs/phy_1')
    current = summary(phy)
    checks = output / 'targeted_timing'
    checks.mkdir(exist_ok=True)
    commands = ['import_device eagle_s20.db -package EG4S20BG256',
                f'import_db {{{(phy / "av_media_pr.db").as_posix()}}}', 'update_timing -mode final']
    for name, direction in (('resize_from', '-from'), ('resize_to', '-to')):
        commands.append(f'report_timing_path {direction} [get_regs {{u_resize_frame/*}}] -ep_num 10 -file {{{(checks / (name + ".timing")).as_posix()}}}')
    commands += ['set cells [concat [get_cells -hier *source_line*] [get_cells -hier *output_line*]]',
                 'if {[llength $cells] != 4} {error "Expected four physical resize RAM cells"}',
                 'foreach cell $cells {foreach check {setup hold} {', 'puts "RAM_BEGIN|$check|$cell"',
                 'if {$check eq "hold"} {report_cells $cell -timing -hold -mode final} else {report_cells $cell -timing -mode final}',
                 'puts "RAM_END"', '}}',
                 'set resize_regs [get_cells -hier {u_resize_frame/*_reg*}]',
                 'puts "RESIZE_REG_CELLS=[llength $resize_regs]"',
                 'if {[llength $resize_regs] == 0} {error "No resize register cells found"}',
                 'foreach cell $resize_regs {puts "REG_BEGIN|$cell"; report_cells $cell -timing -hold -mode final; puts "REG_END"}',
                 'exit']
    tcl = checks / 'query.tcl'
    tcl.write_text('\n'.join(commands) + '\n', encoding='utf-8', newline='\n')
    with (checks / 'console.log').open('wb') as dst:
        rc = subprocess.run([evaluation.build_native.TD.as_posix(), tcl.as_posix()], input=b'exit\n',
                            cwd=checks, stdout=dst, stderr=subprocess.STDOUT, timeout=180).returncode
    raw = (checks / 'console.log').read_bytes()
    try:
        console = raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        console = raw.decode('gb18030')
    (checks / 'console_utf8.log').write_text(console.replace('\r\n', '\n'), encoding='utf-8', newline='\n')
    if rc or re.search(r'\b[A-Z]+-\d+ ERROR|invalid command|wrong # args|couldn.t read file', console):
        raise RuntimeError('定向时序查询失败，请查看console.log')
    targeted = []
    for name in ('resize_from', 'resize_to'):
        values = path_slacks((checks / (name + '.timing')).read_text(encoding='utf-8-sig'))
        kinds = {kind for _, kind in values}
        if 'setup' not in kinds or (name == 'resize_from' and 'hold' not in kinds):
            raise RuntimeError(f'{name}缺少必要的setup/hold路径')
        targeted += [(name, kind, min(slack for slack, check in values if check == kind))
                     for kind in ('setup', 'hold') if kind in kinds]
    targeted += ram_slacks(console)
    resize_count, resize_pin_count, resize_hold = resize_register_hold_slacks(console)
    targeted.append(('resize_register_cells', 'hold', resize_hold))
    failures = [(clock, kind, value) for clock, group in current['groups'].items()
                for kind, value in group.items() if kind in ('setup', 'hold') and value < 0]
    failures += [(clock + '/all_paths', kind, value) for clock, group in current['clock_totals'].items()
                 for kind, value in group.items() if value < 0]
    failures += [(name, kind, value) for name, kind, value in targeted if value < 0]
    limits = evaluation.build_native.reports.load_cfg()
    if current['global_setup'] < limits['SWNS_BASE'] - limits['SWNS_TOL']:
        failures.append(('global', 'legacy_setup_budget', current['global_setup']))
    if current['global_hold'] < limits['HWNS_MIN']:
        failures.append(('global', 'hold', current['global_hold']))
    for resource, total, limit in (('lut', 19600, 'LUT_MAX_PCT'), ('bram9k', 64, 'BRAM9K_MAX_PCT')):
        percent = current['resources'][resource] / total * 100
        if percent > limits[limit]:
            failures.append((resource, 'percent', percent))
    if evaluation.snapshot() != expected:
        raise RuntimeError('查询期间输入变化')
    result = dict(baseline=baseline, current=current, targeted=targeted,
                  resize_register_hold_coverage=dict(cells=resize_count, numeric_pins=resize_pin_count),
                  seed=config['seed'],
                  failures=failures, inputs_match=True, release_bit_unchanged=True)
    (output / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(result, indent=2), flush=True)
    if failures:
        raise RuntimeError(f'域内/新增路径存在负余量: {failures}')
    print('[EVAL_TIMING] PASS domain/resize register/RAM checks; global legacy SDRAM timing separately reported')


if __name__ == '__main__':
    main()
