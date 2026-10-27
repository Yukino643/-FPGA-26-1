# 图片原始分辨率 OSD 实验归档

本目录保存“在 HDMI-B 每张图片右上角显示源分辨率”的实验，不属于 `20261027-flash-coldboot` 稳定候选，也没有替换稳定版 bit。

## 实验内容

- 右上角紫色 32px 分辨率文字，例如 `1280X720`。
- 复用现有 32px 字库，增加 `X` 字模；尺寸信息按图片提交事件跨时钟域同步，并在帧边界后显示。
- 转场、视频模式、图片关闭和前台页不匹配时隐藏尺寸信息。
- 相关源码位于本目录 `rtl/`、`scripts/`、`sim/`；`baseline-before-experiment/` 是实验前备份。

## bit 边界

- `validation/picture-resolution-current-worktree.bit`：当前工作区混合候选，SHA-256 为 `B00DA234B6D0345E75395A92300B4377403B01AE248449C339F97E9DD5F8AB69`。它同时包含冷启动、顶层和 OSD 改动，不能当作稳定版。
- `validation/attempt4-rejected.bit`：分辨率实验第 4 轮构建产物，物理门禁失败，不能烧录。
- `validation/` 中的结果、资源和时序报告只用于保留实验依据，不代表当前稳定版资源或时序。

稳定烧录入口仍是 `../releases/20261027-flash-coldboot/av_media.bit`。
