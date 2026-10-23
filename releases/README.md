# 正式烧录版本索引

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
