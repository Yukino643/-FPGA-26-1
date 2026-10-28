# 构建证据

- 分支：`feat/raw-video-320x180`
- 布局 seed：21
- 构建命令：`D:/miniconda3/python.exe -X utf8 td_prj/build_native.py --output build/720p/picture-resolution-fixed-order-seed21`
- 报告验收：`scripts/check_reports.py` 0 failures
- 缩放器验收：`scripts/check_resize_timing.py` PASS
- 功能回归：`scripts/regression_native.py --sim-only --reuse --jobs 4`，88/88
- 媒体流水线：`verify_media_runtime.py --pipeline 0/1/2/7`，四场景 PASS
- 发布 bit：`td_prj/av_media_Runs/phy_1/av_media.bit`

资源与时序数值以本目录的 `av_media_phy.area` 和 `av_media_pr.timing` 为准。旧加密 SDRAM 跨域 SWNS -6.565 ns 是历史基线项，未被伪装成全工程闭合。
