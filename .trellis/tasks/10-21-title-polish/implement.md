# 当前进度

- 修改前备份：build/720p/backups/20261021-before-title-polish，源码ZIP回读一致，包含既有td_prj/av_media.al改动。
- OSD天蓝标题及模式、黄绿时间，新增单bit颜色命中寄存，与现有字库一拍同步。
- 菜单标题用标=6、题=31；字/内/容/速=32..35及1024x32+128x32容量不变。
- 扩展现有像素回归：标题/模式/上下两个时间位置/独立开关及背景透传。
- 5/5定向回归通过：monitor_pipeline、monitor_menu_renderer、pipeline720、subtitle_pipeline720、subtitle720。已检查主菜单和字幕页真实RTL截图，标题新字形正常。
- 用户改为先让其他AI构思字幕并评审全局审美；已提供候选但正文/通知标签暂不生成，当前bit仍是上一发布版。
- 最终文案确定后再统一完整构建与发布，避免用旧bit声明新源码可烧录。

## 外部审美评审交接

- 报告：docs/ui-review-20261021/REPORT.md；离线内嵌图片版REPORT.html。
- 提示词：REVIEW_PROMPT.txt（全局审美及返回工程提示词）、SUBTITLE_PROMPT.txt（单独字幕构思）。
- 交接包：docs/UI_REVIEW_20261021.zip，包含22张图片、来源与验证状态、SHA256清单；ZIP CRC、逐项哈希及Markdown图片引用校验通过。
- 菜单720p图按当前RTL的floor(2*coordinate/3)映射生成，保留左右黑边。主屏照片图明确标注为真实字库/仿真波形的软件合成参考，不冒充新bit或板验。
- 等外部评审方案与最终文案返回后再继续视觉实施和完整TD构建；不自动套用设计建议。
