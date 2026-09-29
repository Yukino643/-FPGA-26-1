"""检查顶层端口约束的完整性和 LOCATION 冲突。

只解析当前工程的 Verilog 顶层端口和 pin.adc 中未注释的有效约束，
在 TD bitgen 之前捕获漏约束、重复管脚和陈旧端口。
"""
from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOP = ROOT / "rtl" / "top" / "top_tf_hdmi_audio.v"
ADC = ROOT / "constraints" / "pin.adc"


def expand_signal(signal: str) -> set[str]:
    """展开单 bit 或 Verilog 总线声明。"""
    signal = signal.strip()
    match = re.fullmatch(r"([A-Za-z_]\w*)\[(\d+)\s*:\s*(\d+)\]", signal)
    if not match:
        return {signal}
    name, msb, lsb = match.group(1), int(match.group(2)), int(match.group(3))
    return {f"{name}[{index}]" for index in range(min(msb, lsb), max(msb, lsb) + 1)}


def top_ports() -> set[str]:
    text = TOP.read_text(encoding="utf-8")
    header = text.split(");", 1)[0]
    ports: set[str] = set()
    declaration = re.compile(
        r"\b(?:input|output|inout)\s+"
        r"(?:(?:wire|reg)\s+)?"
        r"(?:(\[\d+\s*:\s*\d+\])\s+)?"
        r"([A-Za-z_]\w*)"
    )
    for match in declaration.finditer(header):
        bus_range, name = match.groups()
        ports |= expand_signal(f"{name}{bus_range or ''}")
    return ports


def constrained_ports() -> tuple[set[str], dict[str, list[str]]]:
    assignments: set[str] = set()
    locations: dict[str, list[str]] = {}
    for line in ADC.read_text(encoding="utf-8").splitlines():
        if not line.lstrip().startswith("set_pin_assignment"):
            continue
        match = re.search(
            r"\{\s*([^}]+?)\s*\}.*?LOCATION\s*=\s*([A-Za-z0-9_]+)", line
        )
        if not match:
            raise ValueError(f"无法解析有效约束行: {line}")
        signal, location = match.groups()
        for bit in expand_signal(signal):
            assignments.add(bit)
            locations.setdefault(location, []).append(bit)
    return assignments, locations


def main() -> int:
    ports = top_ports()
    assignments, locations = constrained_ports()
    missing = sorted(ports - assignments)
    extra = sorted(assignments - ports)
    conflicts = {loc: names for loc, names in locations.items() if len(names) > 1}
    if missing or conflicts:
        if missing:
            print("[CONSTRAINT][FAIL] 未约束顶层端口:", ", ".join(missing))
        if conflicts:
            print("[CONSTRAINT][FAIL] LOCATION 冲突:", conflicts)
        return 1
    if extra:
        print("[CONSTRAINT][WARN] 约束中不存在的端口:", ", ".join(extra))
    print(f"[CONSTRAINT][PASS] 顶层端口 {len(ports)} 个，约束完整且无 LOCATION 冲突")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
