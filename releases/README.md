# 正式烧录版本索引

## 当前稳定候选：20261027-flash-coldboot

- [冷启动修复 bit](20261027-flash-coldboot/av_media.bit)，SHA256 `08FB2D34D16536D2D74CB753FC438774188DADBAFDAC2D853CBC9421107426CA`。
- 基于 `20261026-media-return`，只含 SD 初始化上电等待与失败重试；不含图片源分辨率显示实验。
- SD 冷启动专项回归 10/10 通过，综合/P&R/bitgen 完成；尚待用户断电重启实测。LUT 16578、BRAM9K 57；报告仍有全局负余量，详见[构建证据](20261027-flash-coldboot/BUILD_EVIDENCE.md)。
- [烧录说明](20261027-flash-coldboot/README.md)、[源码范围](20261027-flash-coldboot/SOURCE_SCOPE.md)。分辨率 OSD 实验单独保存在 `../experiments/20261027-picture-resolution/`。
- 旧稳定版本及证据均保留，不覆盖。

## 最新待板验版本：20261026-media-return

- [返回图片提速 av_media.bit](20261026-media-return/av_media.bit)，SHA256 `739ed883a45ad803ff7c1c5739a6d40bd55b72e0465a6e48d641163753e10cb2`。
- 视频返回首张淡化32VS→8VS，减少约0.4秒动画；完整读卡/缩放等待仍保留。图片/WAV、有声视频、暂停/循环、双屏菜单、音量与应急均回归通过；TF素材无需更换。
- 89/89完整范围回归、四组媒体流水、完整综合/P&R/bitgen和定向时序通过；LUT16533、BRAM9K57。video/SD/ext_mem同域setup为+0.225/+0.168/+0.149ns，所有hold非负。旧SDRAM跨域全局setup−6.565ns单列，不代表全工程闭合。
- [操作](../docs/media-return-20261026/USAGE.md)、[验收](../docs/media-return-20261026/VALIDATION.md)、[机器证据](20261026-media-return/verification.json)。上一有声版 `20261025-media-audio` 原样保留；本轮未上板、未写TF或提交Git。

## 历史菜单防误操作版本：20261024-menu-navigation

- [菜单防误操作 av_media.bit](20261024-menu-navigation/av_media.bit)，SHA256 `37f46d5f00b550914cf84679fe0a7281fdcd40a1fd099dd9edb78c2de6c60f31`。
- 主控制页图片/时间/周期：同卡两次KEY4确认，移开卡片取消未确认预览；已确认设置不撤销。二级页/长按保持，空格字幕保留。
- 88/88完整范围回归及完整综合/P&R/bitgen通过；字幕18整圈全部断言保留，只关闭重复的大体积栅格导出，未变化用例严格按输入SHA复用。
- LUT14815、REG9727、BRAM9K57、BRAM32K4、DSP15、PLL3。video setup/hold +0.478/+0.022ns，SD +0.320/+0.024ns，ext_mem +0.200/+0.021ns，HDMI5x +0.949/+0.329ns。
- 旧加密SDRAM跨域setup −6.565ns单列，不代表全工程时序闭合。菜单/字体/音量与缩放路径定向检查通过，新bit尚待上板确认。
- [简明操作](../docs/KEY_GUIDE_20261017.md)、[物理报告](../docs/menu-navigation-20261024/PHYSICAL_RELEASE.md)、[机器验收](20261024-menu-navigation/verification.json)、[发布校验](20261024-menu-navigation/SHA256SUMS.txt)。

## 上一版、字幕已获用户板验确认：20261024-subtitle-spaces

- [空格字幕 av_media.bit](20261024-subtitle-spaces/av_media.bit)，SHA256 `a59c79ffec64cde2cd48f17cd5679214ce96efd5e4253bb3dc1e892332a5fa76`。
- 感叹号删除，逗号和顿号换回空格；作品名破折号保留。三句18/14/16格，ROM字节与字体地址不变。
- 88/88完整范围验收、18字幕完整周期、完整综合/P&R/bitgen、字幕/菜单/字体/缩放定向时序通过；未变化用例按输入SHA复用。
- LUT14848、REG9732、BRAM9K57、BRAM32K4、DSP15、PLL3；video setup/hold +0.589/+0.022ns。旧SDRAM跨域setup −6.565ns单列，不代表全工程闭合。
- [文案/截图/操作](../docs/subtitle-spaces-20261024/README.md)、[实际验收](20261024-subtitle-spaces/verification.json)、[发布校验](20261024-subtitle-spaces/SHA256SUMS.txt)。用户已确认字幕修复正常，见[用户反馈](../docs/subtitle-spaces-20261024/BOARD_CHECK.md)；原发布验收JSON保留生成时状态。

## 上一版带标点字幕：20261024-subtitle-copy

- [新滚动字幕 av_media.bit](20261024-subtitle-copy/av_media.bit)，SHA256 `7491c5a36cf98a39cd8a2977ec4b6cdacd181db62b7d6fe0e21f3b5b6b974c75`。
- 三条确认文案、60/64字模，欢迎语19格；同步延长离场计数，保留句尾离场留白。双HDMI与按键功能保持。
- 88/88完整范围功能/物理验收通过，独立综合/P&R/bitgen及字幕/字体/缩放定向时序通过。最终验收按输入SHA复用本轮已通过的仿真，不宣称再跑一遍全部仿真。
- LUT14950、REG9755、BRAM9K57、BRAM32K4、DSP15、PLL3；video setup/hold +0.433/+0.027ns。旧加密SDRAM跨域setup −6.565ns单列，不代表全工程时序闭合。
- [物理验收](../docs/subtitle-copy-20261024/PHYSICAL_RELEASE.md)、[发布清单](20261024-subtitle-copy/SHA256SUMS.txt)、[机器验收](20261024-subtitle-copy/verification.json)。尚待用户烧录验证；下方版本完整保留回退。

## 上一版全幅菜单：20261024-menu-16x9

- [全幅菜单 av_media.bit](20261024-menu-16x9/av_media.bit)，SHA256 `afe5562c7740a7d93a4e1c3884770b9572332b8cb2a349fc5e2ea125922b138c`。
- HDMI-A 640×360整数2×全幅1280×720；六项菜单/主屏/字幕改造，按键和页序保持。
- 88/88完整当前回归、独立TD综合/P&R/bitgen、字幕/菜单/字体及缩放器定向时序通过。
- LUT14837、REG9728、BRAM9K57、BRAM32K4、DSP15、PLL3；video setup/hold +0.290/+0.020ns。
- [物理验收报告](../docs/menu-16x9-20261023/PHYSICAL_RELEASE_20261024.md)、[发布清单](20261024-menu-16x9/SHA256SUMS.txt)、[实际门限](20261024-menu-16x9/verification.json)。
- 本轮未烧录，RTL图不代表7寸屏板拍。旧加密SDRAM跨域setup −6.565ns仍单列，不代表全工程闭合。

## 最新版本、周期已获用户板验确认：20261023-autoplay-period

- [轮播周期修复烧录文件](20261023-autoplay-period/av_media.bit)
- SHA256：`4fd5943df07d5ae416b46548f15a97df359969fd5a8691016509095048a4725d`
- [四档测时、操作与物理报告](../docs/AUTOPLAY_PERIOD_20261023.md)、[发布说明](20261023-autoplay-period/README.md)、[校验清单](20261023-autoplay-period/SHA256SUMS.txt)。
- 档位2/3/5/10秒；计时含缩放/转场/读卡，改档重新计时，慢卡饱和等待、无补切。四档逐像素菜单和每档3次真实顶层CDC后转场间隔仿真通过，播放中4次改档及冷缓存/取消/手动路径通过。
- 89/89完整回归、当前源码完整P&R/bitgen和严格发布门通过。LUT14839，BRAM9K57，DSP15，PLL3；video/SD/ext_mem setup分别+0.680/+0.138/+0.190ns，hold均非负。旧加密SDRAM跨域全局setup −6.565ns单列。
- 用户本轮烧录后反馈“周期都比较准确了”，登记为周期定性板验确认，见[独立记录](../docs/AUTOPLAY_PERIOD_20261023_BOARD_CHECK.md)；未提供逐次秒表误差或长稳统计。原发布归档保留生成时状态；上一版音量/多尺寸已板验版本完整保留在下方。

## 最新已板验版本：20261023-audio-volume

- [音量与音频二级页烧录文件](20261023-audio-volume/av_media.bit)
- SHA256：`8e3930111f9329802128d4e9b56c3eec628c9ef264899636245f87d1db93ad68`
- [详细操作、资源与时序](../docs/AUDIO_VOLUME_20261022.md)、[发布说明](20261023-audio-volume/README.md)。
- 主页原“波形”卡改为“音频”，二级页提供音量0..100%、独立静音、波形、恢复默认；保留WAV目录直达启动优化。85/85完整回归、完整TD综合/P&R/bitgen、定向路径和发布门限通过。LUT14817、BRAM9K57、DSP15、PLL3；video域内setup +0.280ns，SD +0.147ns，ext_mem +0.318ns。旧加密SDRAM跨域全局setup −6.565ns单列。
- 用户于2026-10-23确认不同分辨率适配、音频快速出声、音量控制正常；见[本轮板验记录](../docs/AUDIO_VOLUME_20261023_BOARD_CHECK.md)。未报告首声秒数、长稳或Flash固化结果；运行期音量设置不掉电保存。

上一轮独立音频启动候选保留于[20261022-audio-startup](20261022-audio-startup/README.md)，bit SHA256 `ec260a8984beee5a5b439deee676bd4fd7b45ddbc906b9ae976601165b6ca47e`；82/82完整回归及物理检查通过，实机首声时间仍待计时。已板验稳定回退基线如下。

## 历史稳定回退：20261022-main-ui

- [烧录文件](20261022-main-ui/av_media.bit)
- SHA256：`a87d1d0b280f66e6c12229b27f68e6bcd51586f8db23b489ae87097728723fbb`
- [实现、操作与77项完整回归/物理验收结果](../docs/MAIN_UI_20261022.md)
- [2026-10-22用户实机确认记录](../docs/MAIN_UI_20261022_BOARD_CHECK.md)
- [原始发布说明](20261022-main-ui/README.md)和[校验清单](20261022-main-ui/SHA256SUMS.txt)

用户反馈本轮修改检查完成，作为稳定基线。归档内README、资源JSON等描述的是发布生成时的状态，之后的用户确认由上方独立记录补充，不回写原始证据。不将概括反馈视为所有压力测试或Flash固化通过。

本目录的`20261022-main-ui`与`20261022-menu-ui-p0`分别从本地`build/720p/releases`复制，逐文件SHA256及各自SHA256SUMS均已验证。源码ZIP保留发布当时的快照；后续文档修订以当前Git源码树为准。

## 上一版菜单P0

[20261022-menu-ui-p0](20261022-menu-ui-p0/README.md)保留用于对照及回退，bit SHA256为`1bf3e751daa910d08c1220406b2a91dfb9f18defb78e7da823c502be2905aee7`。该旧版SD卡域内部setup存在−0.142ns，不能据旧摘要声称其所有域内时序通过；当前主屏版已将该项纳入非负门限并通过。

当前版旧加密SDRAM跨域全局setup仍为−6.565ns，不能宣称全工程时序闭合。更早的20261021发布目录保留历史证据，不代表当前状态。
