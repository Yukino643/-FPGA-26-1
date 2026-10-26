"""仿真直接复用顶层提交/释放握手，防止测试副本遗漏真实 CDC 连接。"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "rtl/top/top_tf_hdmi_audio.v").read_text(encoding="utf-8")
blocks = []
for first, last in (
    ("reg [2:0] commit_sync;", "// vs_rise toggle"),
    ("reg [2:0] scaler_done_sync;", "// ===================== TF 多图扫描"),
    ("transition_ctrl #(", "// ---- mem_mpu:"),
):
    start = source.index(first)
    blocks.append(source[start:source.index(last, start)])
(root / "sim/reg_display_commit.vh").write_text("\n".join(blocks), encoding="utf-8")
print("Extracted actual top display commit handshake")

start = source.index("source_scaler_gate u_source_scaler_gate (")
end = source.index("\n);", start) + len("\n);")
(root / "sim/reg_source_scaler_gate.vh").write_text(source[start:end], encoding="utf-8")
