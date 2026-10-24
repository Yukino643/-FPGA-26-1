"""从真实顶层提取缩放启动与例化，防止测试副本偏离工程连接。"""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--top", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
top = args.top or root / "rtl/top/top_tf_hdmi_audio.v"
text = top.read_text(encoding="utf-8")
start = text.index("wire scaler_start_tgl;")
end = text.index("wire video_read_en_unused;", start)
block = text[start:end]
if block.count("u_scaler (") != 1:
    raise RuntimeError("顶层缩放例化边界发生变化，请检查提取范围")
(root / "sim/reg_top_scaler_block.vh").write_text(block, encoding="utf-8")
print(f"Extracted scaler connections from {top}")
