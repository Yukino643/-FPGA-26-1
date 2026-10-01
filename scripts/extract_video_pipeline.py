"""提取真实顶层图层连接，避免仿真副本掩盖 RGB/DE 延迟错误。"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
text = (root / "rtl/top/top_tf_hdmi_audio.v").read_text(encoding="utf-8")
start = text.index("reg de_d1, vs_d1;")
end = text.index("// 缩放完成 toggle", start)
blocks = [text[start:end]]
for marker in (
    "osd_engine u_osd(", "spectrum_layer u_spectrum_layer(",
    "subtitle_scroll u_subtitle_scroll(", "color_adjust u_color_adjust(",
    "emergency_render u_emergency_render(",
    "video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(",
):
    start = text.index(marker)
    end = text.index("\n);", start) + len("\n);")
    blocks.append(text[start:end])
(root / "sim/reg_video_pipeline.vh").write_text("\n".join(blocks), encoding="utf-8")
print("Extracted actual top video pipeline")
