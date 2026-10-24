# 设计

当前工作树为唯一 UI 现状，最新20261023-autoplay-period发布提供历史物理验证边界。现有tb_monitor_menu_renderer生成13菜单状态，按顶层等比映射导出720p PNG，并保留逻辑栅格。现有render_main_ui.py将照片输入OSD RTL，生成三张图；波形关闭，不是板拍或完整存储/HDMI物理验证。

资料包含CURRENT_UI_REVIEW.md、REVIEW_PROMPT.txt、REVIEW_RETURN_TEMPLATE.md、images、source_snapshot、evidence。逐图记录测试状态、工具和限制。源码快照仅供阅读，不是可独立构建全工程。生成前后保护既有RTL、约束、脚本、测试、TD及发布文件哈希；临时输出进入build/720p/ui-review-20261023。
