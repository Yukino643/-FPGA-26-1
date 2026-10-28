"""原生Windows TD构建；输入hash、新鲜产物及工程快照三重校验。"""
from pathlib import Path
import argparse
import importlib.util
import re
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
TD=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
spec=importlib.util.spec_from_file_location('reports',ROOT/'scripts/check_reports.py')
reports=importlib.util.module_from_spec(spec)
spec.loader.exec_module(reports)

def manifest(include_bit=True):
    paths=reports.source_files()
    return ''.join(f'{reports.sha256(path)}  {Path(path).relative_to(ROOT).as_posix()}\n'
                   for path in paths if include_bit or not path.endswith('av_media.bit'))

def delete_outputs(run,names):
    # 路径逐项限制在已确认的run目录；不进行递归删除。
    for path in list(run.glob('.*.error.f'))+[run/name for name in names]:
        if path.parent.resolve()!=run.resolve(): raise RuntimeError('构建清理路径越界')
        if path.is_file(): path.unlink()

def run_td(run,output,flow=None):
    log=output/f'{run.name}_console.log'
    with log.open('wb') as dst:
        started=time.monotonic()
        proc=subprocess.Popen([TD.as_posix(),(flow or ROOT/'td_prj/flow_fixhold.tcl').as_posix()],cwd=run,
                              stdin=subprocess.PIPE,stdout=dst,stderr=subprocess.STDOUT)
        proc.stdin.write(b'exit\n'); proc.stdin.close()
        while proc.poll() is None:
            try: proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                tail=log.read_bytes()[-900:].decode('utf-8',errors='replace')
                print(f'[BUILD] {run.name} {time.monotonic()-started:.0f}s {tail[-300:]}',flush=True)
        rc=proc.returncode
    data=log.read_bytes().decode('utf-8',errors='replace')
    # 已知SDRAM ECO重定位、shifted clock local-wire警告逐项留档；其他关键警告拒绝。
    warnings=re.findall(r'^.*CRITICAL-WARNING:.*$',data,re.M)
    unexpected=[]
    for line in warnings:
        if re.search(r'PHY-7002 CRITICAL-WARNING: Instance U3/sdram location \(\d+, \d+\) is not honored\.',line):
            continue
        if 'PHY-5079 CRITICAL-WARNING: Marked 1 clock net(s)' in line:
            # 限定实际局部时钟表的一条旧SDRAM输出；不能凭全日志出现网名放行。
            # TD的DRC阶段号随实际优化流程变化（已见7.1/9.1）；
            # 用同一检查项名称结束表格，下面仍严格核对唯一网名/驱动/扇出。
            tables=re.findall(r'CTS Local Wire Summary(.*?)End Stage \d+\.\d+ \| Clock Net Status Check;',data,re.S)
            rows=[row for table in tables for row in table.splitlines()
                  if '|' in row and 'ClockName' not in row]
            if len(rows)==1:
                fields=[field.strip() for field in rows[0].split(':',1)[-1].split('|')]
                if fields==['sys_pll_m0/pll_inst.clkc[2]','AL_PHY_PLL','0/1','1','U3/u2_ram/SDRAM_CLK','true']:
                    continue
        unexpected.append(line)
    if warnings:
        (output/f'{run.name}_critical_warnings.txt').write_text('\n'.join(warnings)+'\n',encoding='utf-8',newline='\n')
    if rc or list(run.glob('.*.error.f')) or re.search(r'\b[A-Z]+-\d+ ERROR',data) or unexpected:
        raise RuntimeError(f'TD {run.name}失败，返回{rc}；完整日志 {log}')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',required=True)
    parser.add_argument('--syn-only',action='store_true')
    args=parser.parse_args()
    output=Path(args.output).resolve(); output.mkdir(parents=True,exist_ok=True)
    if not TD.is_file(): raise RuntimeError(f'TD不存在: {TD}')
    entry=ROOT/'td_prj/av_media.al'
    entry_bytes=entry.read_bytes()
    (output/'av_media.al.input').write_bytes(entry_bytes)
    syn=ROOT/'td_prj/av_media_Runs/syn_1'; phy=ROOT/'td_prj/av_media_Runs/phy_1'
    prj=entry_bytes.decode('utf-8-sig').replace('Path="../','Path="../../../')
    for run in (syn,phy): (run/'av_media.prj').write_text(prj,encoding='utf-8',newline='\n')
    if not reports.project_snapshots_match(): raise RuntimeError('构建快照不一致')
    inputs=manifest(False)
    (output/'build_inputs.sha256').write_text(inputs,encoding='ascii',newline='\n')
    try:
        delete_outputs(syn, ['av_media_gate.db'])
        print('[BUILD] synthesis',flush=True); run_td(syn,output)
        if not (syn/'av_media_gate.db').is_file(): raise RuntimeError('本轮综合没有生成gate.db')
        if args.syn_only: return
        delete_outputs(phy,['av_media_pr.db','av_media.bit','.bitgen.end.f','build_manifest.sha256'])
        print('[BUILD] place + route + bitgen',flush=True); run_td(phy,output)
        for name in ('av_media_pr.db','av_media.bit','.bitgen.end.f'):
            if not (phy/name).is_file(): raise RuntimeError(f'本轮缺少 {name}')
    finally:
        # TD有时回写工程入口，成功或失败都恢复本轮精确输入字节。
        if entry.read_bytes()!=entry_bytes: entry.write_bytes(entry_bytes)
    if not reports.project_snapshots_match() or manifest(False)!=inputs:
        raise RuntimeError('构建期间输入变动；拒绝签发bit清单')
    (phy/'build_manifest.sha256').write_text(manifest(),encoding='ascii',newline='\n')
    print(f'[BUILD] PASS current-source BIT {phy/"av_media.bit"}',flush=True)

if __name__=='__main__': main()
