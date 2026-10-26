# 2026-10-25首阶段交付

- 稳定源码/bit备份已核对，分支feat/raw-video-320x180独立开发。
- 发布 `releases/20261025-raw-video/av_media.bit`；SHA256 `d8019b2e6f7b1ce6ffdf7ef461e3a5a984c16bd086d7fa39e22f643f33d2931f`。
- TF素材 `releases/20261025-raw-video/media/VIDEO.R16`，97帧9.7秒，11,174,912B，素材SHA见metadata.json。
- 原完整回归88/88，视频10项通过；完整720p原生编译仿真检查11,980,800像素，0→1→0循环，6VS采纳，播放后新增欠载0。
- 同一完整测试台Icarus触及1800秒墙钟上限后改用Verilator编译仿真；未缩栅格/减断言。第三方包版本与运行器版本分别记录。
- 完整综合/P&R/bitgen seed16通过；seed14局部hold增量布线冲突失败证据已保留。未改时钟/SDC。
- LUT12153、REG8064、BRAM9K49、BRAM32K4、DSP10、PLL3；video setup+0.173ns、SD+0.196、ext_mem+0.130、HDMI5x同域+1.110ns；旧全局setup−6.565ns单列。
- 发布包有源/bit归档、输入SHA、物理日志、仿真日志、资料取舍和简明操作说明；发布文件均已SHA回读。
- 没有写TF卡、烧录、Git提交或推送。用户上板后确认方向/颜色/满幅、循环和实际9.7秒片长，再决定下一步。
- 后续才考虑音轨同步、播放/暂停和菜单返回图片模式；当前实验开机无声循环，不宣传MP4硬解码。

详细记录：`docs/raw-video-20261025/VERIFICATION.md`、`REFERENCE_REVIEW.md`、`USAGE.md`。
