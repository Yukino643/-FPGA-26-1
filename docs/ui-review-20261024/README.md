# 2026-10-24 最新UI审查包入口

这是全幅菜单版 `20261024-menu-16x9` 的审美审查资料，不是旧版20261023。

1. 先读 [CURRENT_UI_REVIEW.md](CURRENT_UI_REVIEW.md)：全部布局、色值、字库、交互、图层、循环、资源和已知边界。
2. 打开 [VISUAL_GALLERY.html](VISUAL_GALLERY.html)：13菜单、16明暗照片组合、三句字幕、波形、全周期/连续帧、字形图与缩小预览。
3. 使用 [REVIEW_PROMPT.txt](REVIEW_PROMPT.txt)，按 [REVIEW_RETURN_TEMPLATE.md](REVIEW_RETURN_TEMPLATE.md) 给出审美结论与精确规格。
4. 源码在 `source_snapshot/`；代码行号、图片来源、每句字格及SHA在 `evidence/`。
5. 报告写 `proposal/UI_AESTHETIC_REVIEW.md`，提案图片写 `proposal/images/`；不能覆盖现状图片或修改工程。

离线包：同级 `../UI_REVIEW_20261024.zip`，内含本目录全部文件；ZIP CRC与逐文件SHA已回读。
源码快照仅为审查摘录，不是可单独构建的全工程；包内没有bit，bit身份与TD实测在证据JSON。
本轮只生成资料和补充RTL图，不综合、不烧录、不提交/推送Git。新bit实体屏效果尚待用户确认。

简短启动提示：

> 读 `D:\FPGA\code\example\docs\ui-review-20261024\REVIEW_PROMPT.txt`，按其中顺序读取现状、画廊与源码，严格以美观为主审查。不要改工程，按返回模板给精确可实施规格。输出 `proposal\UI_AESTHETIC_REVIEW.md`。不要误用20261023旧包或把RTL图当成板拍。

复现资料包：使用PowerShell7，执行本目录 `BUILD_REVIEW_PACKAGE.py`；会运行只读RTL取证，不会修改产品输入。
