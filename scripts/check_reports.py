#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_reports.py — 编译产物门限检查
读取 td_prj/av_media_Runs/phy_1/ 的时序与资源报告，对照 scripts/baseline.rpt 门限。
输出 [RPT][PASS]/[RPT][FAIL] 行；有 FAIL 时退出码 1。
"""
import hashlib
import os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PHY  = os.path.join(ROOT, "td_prj", "av_media_Runs", "phy_1")
MANIFEST = os.path.join(PHY, "build_manifest.sha256")

def source_files():
    """返回参与构建的新鲜度校验的工程输入；不扫描 TD 生成物。"""
    paths = []
    for base in (os.path.join(ROOT, "rtl"), os.path.join(ROOT, "constraints")):
        for dirpath, _, names in os.walk(base):
            for name in names:
                path = os.path.join(dirpath, name)
                if name.lower().endswith((".v", ".vh", ".vhd", ".enc.v", ".sdc", ".adc", ".ipc")):
                    paths.append(path)
    paths.extend([
        os.path.join(ROOT, "td_prj", "av_media.al"),
        os.path.join(PHY, "av_media.prj"),
    ])
    return sorted(path for path in paths if os.path.isfile(path))

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

def manifest_matches():
    if not os.path.isfile(MANIFEST):
        print("[RPT][FAIL] 缺少 build_manifest.sha256，不能确认 bit 与源码同版本")
        return False
    expected = {}
    try:
        with open(MANIFEST, encoding="ascii") as f:
            for line in f:
                digest, rel = line.rstrip("\n").split("  ", 1)
                expected[rel] = digest
    except (OSError, ValueError) as exc:
        print(f"[RPT][FAIL] 构建清单损坏: {exc}")
        return False
    actual = {os.path.relpath(path, ROOT).replace("\\", "/"): sha256(path)
              for path in source_files()}
    if expected != actual:
        missing = sorted(set(expected) - set(actual))
        changed = sorted(k for k in set(expected) & set(actual) if expected[k] != actual[k])
        added = sorted(set(actual) - set(expected))
        print("[RPT][FAIL] 构建清单与当前输入不一致")
        if missing: print("  清单中已不存在:", ", ".join(missing[:8]))
        if changed: print("  已修改:", ", ".join(changed[:8]))
        if added: print("  构建后新增:", ", ".join(added[:8]))
        return False
    return True

def load_cfg():
    cfg = {}
    with open(os.path.join(ROOT, "scripts", "baseline.rpt"), encoding="utf-8") as f:
        for line in f:
            line = line.split("#")[0].strip()
            if "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = float(v)
    return cfg

def main():
    cfg = load_cfg()
    fails = 0

    ts_path = os.path.join(PHY, "av_media_phy.ts")
    area_path = os.path.join(PHY, "av_media_phy.area")
    bit_path = os.path.join(PHY, "av_media.bit")
    project_snapshot = os.path.join(PHY, "av_media.prj")

    if not os.path.isfile(bit_path):
        print("[RPT][FAIL] av_media.bit 不存在（尚未编译？用 --full 触发）")
        return 1
    error_markers = [name for name in os.listdir(PHY) if name.endswith(".error.f")]
    if error_markers:
        print("[RPT][FAIL] TD 物理设计存在错误标记:", ", ".join(sorted(error_markers)))
        return 1
    bitgen_end = os.path.join(PHY, ".bitgen.end.f")
    if not os.path.isfile(bitgen_end):
        print("[RPT][FAIL] 缺少 .bitgen.end.f，bitgen 未被当前流程确认完成")
        return 1
    if not manifest_matches():
        return 1
    print("[RPT][PASS] av_media.bit 与 SHA-256 构建清单一致")

    # ---- 时序 ----
    try:
        ts = open(ts_path, encoding="utf-8", errors="replace").read()
    except FileNotFoundError:
        print("[RPT][FAIL] 找不到 %s" % ts_path)
        return 1
    m = re.search(r"SWNS:\s*([-0-9.]+)ns,\s*STNS:\s*([-0-9.]+)ns", ts)
    h = re.search(r"HWNS:\s*([-0-9.]+)ns", ts)
    if not (m and h):
        print("[RPT][FAIL] 时序报告格式解析失败")
        return 1
    swns, hwns = float(m.group(1)), float(h.group(1))
    base, tol = cfg["SWNS_BASE"], cfg["SWNS_TOL"]
    if swns >= base - tol:
        print(f"[RPT][PASS] SWNS={swns:.3f}ns (基线 {base}ns, 容差 {tol})")
    else:
        print(f"[RPT][FAIL] SWNS={swns:.3f}ns 恶化超过基线 {base}ns 容差 {tol}")
        fails += 1
    if hwns >= cfg["HWNS_MIN"]:
        print(f"[RPT][PASS] HWNS={hwns:.3f}ns (hold 无违例)")
    else:
        print(f"[RPT][FAIL] HWNS={hwns:.3f}ns hold 违例")
        fails += 1

    # ---- 资源 ----
    area = open(area_path, encoding="utf-8", errors="replace").read()
    lm = re.search(r"#lut\s+(\d+)\s+out of\s+(\d+)\s+([0-9.]+)%", area)
    bm = re.search(r"#bram9k\s+(\d+)", area)
    if lm:
        used, total, pct = int(lm.group(1)), int(lm.group(2)), float(lm.group(3))
        if pct <= cfg["LUT_MAX_PCT"]:
            print(f"[RPT][PASS] LUT {used}/{total} = {pct}% (上限 {cfg['LUT_MAX_PCT']:.0f}%)")
        else:
            print(f"[RPT][FAIL] LUT {pct}% 超上限 {cfg['LUT_MAX_PCT']:.0f}%")
            fails += 1
    else:
        print("[RPT][FAIL] 资源报告 LUT 行解析失败")
        fails += 1
    if bm:
        n = int(bm.group(1))
        pct = n / 64 * 100
        if pct <= cfg["BRAM9K_MAX_PCT"]:
            print(f"[RPT][PASS] BRAM9K {n}/64 = {pct:.1f}% (上限 {cfg['BRAM9K_MAX_PCT']:.0f}%)")
        else:
            print(f"[RPT][FAIL] BRAM9K {pct:.1f}% 超上限")
            fails += 1

    print("[RPT] fails =", fails)
    return 1 if fails else 0

if __name__ == "__main__":
    sys.exit(main())
