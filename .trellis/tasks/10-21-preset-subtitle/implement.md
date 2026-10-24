# 实现与验收清单

- [x] 修改前备份当前源码、板验 bit 和发布包，逐字节回读 SHA256。
- [x] 实现字幕二级页、预览/确认/取消与正文忙保护。
- [x] 扩展现有 VS 邮箱，不改变原有图层、屏幕参数和应急优先级。
- [x] 复用现有 OSD 字库，绘制底部字幕条和三档帧同步滚动。
- [x] 新增独立文字/像素参考、循环与速度、顶层流水线回归。
- [x] 当前源码完成综合、完整 P&R 与 bitgen；拒绝新增域内负余量。
- [x] 检查菜单、字幕字库及缩放 RAM 入出时序。
- [x] 全量回归 75/75，complete=true、filter=null，复用须依赖哈希一致。
- [x] 查看真实 RTL 菜单及字幕预览，更新规范、进度、操作说明。
- [x] 归档新源码与 bit，核对旧板验 bit 不变；标注新功能待板验。

验证命令：scripts/regression_native.py --sim-only --reuse、scripts/check_reports.py、scripts/check_resize_timing.py、scripts/check_subtitle_timing.py。

首轮菜单文字路径 -0.732ns 的构建已隔离，不得发布；仅以最终当前源码的报告为准。
