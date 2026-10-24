# 全幅16:9监视菜单发布

烧录本目录av_media.bit，HDMI-A/B继续输出1280×720。HDMI-A为640×360逻辑画布整数2×全幅，无原160px居中黑边。

包含六项UI调整、64格字幕及此前已板验的2/3/5/10秒轮播修复。按键语义保持。本轮仿真和TD物理验收已通过，尚未烧录验证，不把RTL截图当作7寸屏实拍。

资源及时序见verification.json；旧加密SDRAM跨域setup −6.565ns单列，不代表全工程时序闭合。上板回退使用../20261023-autoplay-period/av_media.bit。

[六项改动与图集](../../docs/menu-16x9-20261023/IMPLEMENTATION_REPORT.md)；[本轮物理验收](../../docs/menu-16x9-20261023/PHYSICAL_RELEASE_20261024.md)。本目录FINAL_VERIFICATION/SOURCE_AUDIT为先前纯RTL阶段原始证据，其中未综合标记为历史记录，当前实测以verification.json为准。
