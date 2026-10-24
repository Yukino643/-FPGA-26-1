# 当前双HDMI UI外部审查资料包

## Goal

整理当前双 HDMI UI 信息及其他 AI 的阅读、审查和返回提示词，服务三分钟作品介绍视频。

## Requirements

- 新建 docs/ui-review-20261023/，以当前源码说明坐标、配色、字体、页面、状态、按键、默认值和资源限制。
- 生成当前菜单 RTL 栅格、照片输入 OSD RTL 图、只读源码快照、提示词、返回模板、哈希清单和离线 ZIP。
- 不修改产品 RTL、字库、约束、TD 数据库和发布 bit，不烧录、不改 TF、不提交或推送 Git。
- 不增加长期运行验证和新的产品功能，不为资料包重跑完整 P&R。

## Acceptance Criteria

- [x] 覆盖节目、音频、屏幕、字幕、外设、播放按键页和编辑/待确认/等待状态。
- [x] 主屏为当前视界字幕、局部底板、固定右下时间；图像来源及不含波形的范围明确。
- [x] 核对 720p 输出/640x480画布/左右黑边、菜单36 ROM字加4逻辑字、主屏50单元。
- [x] 源码及最新发布哈希可复核；文档UTF-8无BOM/LF、图片尺寸、路径链接及ZIP CRC检查通过。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
