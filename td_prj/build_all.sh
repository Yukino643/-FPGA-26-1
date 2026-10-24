#!/usr/bin/env bash
# 一键命令行编译 av_media 工程（等价于 TD GUI 里 syn_1 + phy_1 全流程）
# 用法: bash td_prj/build_all.sh          # 全流程
#       bash td_prj/build_all.sh syn     # 只综合
set -e
if [ -d /mnt/d ]; then
  TD="/mnt/d/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe"
  # TD 是 Windows 程序，Tcl 脚本参数必须使用盘符路径而非 WSL 挂载路径。
  FLOW="D:/FPGA/code/example/td_prj/flow_fixhold.tcl"
  ROOT="/mnt/d/FPGA/code/example/td_prj"
  PROJ_ROOT="/mnt/d/FPGA/code/example"
else
  TD="/d/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe"
  FLOW="/d/FPGA/code/example/td_prj/flow_fixhold.tcl"
  ROOT="/d/FPGA/code/example/td_prj"
  PROJ_ROOT="/d/FPGA/code/example"
fi
RUNS="$ROOT/av_media_Runs"
if [ -z "${PYTHON_BIN:-}" ]; then
  if [ -d /mnt/d ] && [ -x /mnt/d/miniconda3/python.exe ]; then
    PYTHON_BIN=/mnt/d/miniconda3/python.exe
  elif [ -x /d/miniconda3/python.exe ]; then
    PYTHON_BIN=/d/miniconda3/python.exe
  else
    PYTHON_BIN=python3
  fi
fi

if [ ! -x "$PYTHON_BIN" ] && ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  PYTHON_BIN="python3"
fi

CANONICAL_AL="$ROOT/av_media.al"
CANONICAL_AL_BACKUP="$ROOT/.av_media.al.build-backup"
cp "$CANONICAL_AL" "$CANONICAL_AL_BACKUP"

# 刷新 run 目录的工程快照（.al 路径 ../ → ../../../，相对 run 目录）
"$PYTHON_BIN" -X utf8 - << 'PYEOF'
al = open(r'D:\FPGA\code\example\td_prj\av_media.al', encoding='utf-8').read()
prj = al.replace('Path="../', 'Path="../../../')
for d in [r'D:\FPGA\code\example\td_prj\av_media_Runs\syn_1', r'D:\FPGA\code\example\td_prj\av_media_Runs\phy_1']:
    open(d + r'\av_media.prj', 'w', encoding='utf-8', newline='\n').write(prj)
import hashlib
import os
import sys
sys.path.insert(0, r'D:\FPGA\code\example\scripts')
from check_reports import source_files, project_snapshots_match
if not project_snapshots_match():
    raise RuntimeError("构建入口与工程快照不一致")
root = r'D:\FPGA\code\example'
inputs = [p for p in source_files() if not p.endswith('av_media.bit')]
with open(os.path.join(root, 'td_prj', 'av_media_Runs', 'phy_1', '.build_inputs.sha256'), 'w', encoding='ascii', newline='\n') as dst:
    for path in inputs:
        with open(path, 'rb') as src:
            digest = hashlib.sha256(src.read()).hexdigest()
        dst.write(f"{digest}  {os.path.relpath(path, root).replace(chr(92), '/')}\n")
PYEOF

if [ "${1:-all}" = "all" ] || [ "${1:-all}" = "syn" ]; then
  echo "==== [1/2] synthesis (syn_1: elaborate -> opt_rtl -> opt_gate) ===="
  rm -f "$RUNS/syn_1"/.*.error.f
  rm -f "$RUNS/syn_1/av_media_gate.db"
  (cd "$RUNS/syn_1" && printf 'exit\n' | "$TD" "$FLOW" > syn_console.log 2>&1)
  # ---- 产物新鲜度门: 防止综合失败后下游用旧库出假 bit ----
  if [ ! -f "$RUNS/syn_1/av_media_gate.db" ]; then
    echo "SYN FAILED: 未生成 av_media_gate.db（综合出错）"; exit 1
  fi
  if ls "$RUNS/syn_1"/.*.error.f > /dev/null 2>&1; then
    echo "SYN FAILED: 存在步骤错误标记:"; ls "$RUNS/syn_1"/.*.error.f; exit 1
  fi
  grep -E "HDL-[0-9]+ ERROR|USR-[0-9]+ ERROR|CRITICAL" "$RUNS/syn_1/syn_console.log" && {
    echo "SYN FAILED: 综合日志含 ERROR"; exit 1
  }
fi

if [ "${1:-all}" = "syn" ]; then
  echo "SYN OK: $RUNS/syn_1/av_media_gate.db"
  exit 0
fi

echo "==== [2/2] place&route+bitgen (phy_1: opt_place -> opt_route -> bitgen) ===="
rm -f "$RUNS/phy_1"/.*.error.f
rm -f "$RUNS/phy_1/av_media_pr.db" "$RUNS/phy_1/av_media.bit" "$RUNS/phy_1/.bitgen.end.f"
(cd "$RUNS/phy_1" && printf 'exit\n' | "$TD" "$FLOW" > phy_console.log 2>&1)
if [ ! -f "$RUNS/phy_1/av_media_pr.db" ]; then
  echo "PHY FAILED: 未生成 av_media_pr.db"; exit 1
fi
if ls "$RUNS/phy_1"/.*.error.f > /dev/null 2>&1; then
  echo "PHY FAILED: 存在步骤错误标记:"; ls "$RUNS/phy_1"/.*.error.f; exit 1
fi

BIT="$RUNS/phy_1/av_media.bit"
[ -f "$BIT" ] && echo "BIT OK: $BIT" || { echo "BIT FAILED"; grep ERROR "$RUNS/phy_1/phy_console.log" | tail -5; exit 1; }
if [ ! -f "$RUNS/phy_1/.bitgen.end.f" ]; then
  echo "BIT FAILED: 缺少 .bitgen.end.f"; exit 1
fi
# TD 有时会回写入口工程；恢复 canonical 入口，保证 GUI 与 run 快照同源。
if ! cmp -s "$CANONICAL_AL" "$CANONICAL_AL_BACKUP"; then
  cp "$CANONICAL_AL_BACKUP" "$CANONICAL_AL"
fi
rm -f "$CANONICAL_AL_BACKUP"

# 用输入文件 SHA-256 固化 bit 的源码/约束版本，避免 Windows 与 WSL 的
# 文件时间基准差异导致旧 bit 被误判为新产物，或新 bit 被误判为旧产物。
"$PYTHON_BIN" -X utf8 - << 'PYEOF'
import hashlib
import os

root = r"D:\FPGA\code\example"
out = os.path.join(root, "td_prj", "av_media_Runs", "phy_1", "build_manifest.sha256")
import sys
sys.path.insert(0, os.path.join(root, 'scripts'))
from check_reports import source_files, project_snapshots_match
if not project_snapshots_match():
    raise RuntimeError("TD 运行后工程入口与快照不一致；拒绝签发 bit 清单")
paths = source_files()
actual_lines = []
for path in (p for p in paths if not p.endswith('av_media.bit')):
    with open(path, 'rb') as src:
        digest = hashlib.sha256(src.read()).hexdigest()
    actual_lines.append(f"{digest}  {os.path.relpath(path, root).replace(chr(92), '/')}\n")
with open(os.path.join(root, 'td_prj', 'av_media_Runs', 'phy_1', '.build_inputs.sha256'), encoding='ascii') as src:
    if "".join(actual_lines) != src.read():
        raise RuntimeError("构建期间输入发生变更；请修复工程版本后重新构建")
with open(out, "w", encoding="ascii", newline="\n") as dst:
    for path in sorted(p for p in paths if os.path.isfile(p)):
        digest = hashlib.sha256()
        with open(path, "rb") as src:
            for block in iter(lambda: src.read(1024 * 1024), b""):
                digest.update(block)
        rel = os.path.relpath(path, root).replace("\\", "/")
        dst.write(f"{digest.hexdigest()}  {rel}\n")
PYEOF
echo "MANIFEST OK: $RUNS/phy_1/build_manifest.sha256"
echo "---- 最终时序 ----"
head -3 "$RUNS/phy_1/av_media_phy.ts"
