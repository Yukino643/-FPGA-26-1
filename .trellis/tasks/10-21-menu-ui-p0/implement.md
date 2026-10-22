# 当前交付状态

## 2026-10-22 当前源码构建与板验交付

用户已授权生成新烧录文件并要求参考老师工程。此授权覆盖早期“只交付RTL、不运行TD”的停止点，范围仍为8.1–8.5，不实施8.6/8.7。

- 修改前备份：`build/720p/backups/20261022-before-menu-build/source-and-previous-bit.zip`，源码与旧bit逐字节回读通过。
- 老师资料实际对照与各轮物理证据：`.trellis/tasks/10-21-menu-ui-p0/teacher-review-20261022.md`。借鉴窄位宽地址和同步字模/命中对齐；本工程将每卡8位字符并行选择，再选卡，解耦字库地址与绘制命中。不增加字库bank、像素延迟、帧缓存或PLL。
- 最终源码完整回归 **75/75 PASS**，`complete=true/filter=null`；未变化项按依赖哈希复用，菜单10整页像素及真实顶层三拍相位重新仿真。10场景、48卡四侧3/6像素、14受保护输入哈希另由独立脚本核验。
- 当前源码完整综合、P&R、hold修复、bitgen通过；基础、菜单/字体和缩放定向时序检查通过。最终构建日志：`build/720p/td/20261022-menu-ui-p0-final`。布局使用工程既有seed11，不修改SDC、频率或验收门限。

| 最终物理项 | 实测 |
|---|---|
| LUT | 15022/19600，76.64%，较旧14875增加147 |
| 寄存器 | 9371/19600，47.81% |
| BRAM9K / BRAM32K | 57/64，89.06% / 4/16 |
| DSP / PLL | 13/29 / 3/4 |
| video setup / hold | +0.184 / +0.024 ns，达到setup≥0.15ns |
| HDMI 5x setup / hold | +0.962 / +0.049 ns |
| ext_mem内部 setup / hold | +0.143 / +0.022 ns |
| 全局hold | +0.022 ns |

旧加密SDRAM跨域全局setup **−6.565ns**继续单列，不能宣称全工程setup闭合；本轮新增域内路径按非负门限验收。初始及中间失败bit已隔离，不能用于板验。

新发布目标：`build/720p/releases/20261022-menu-ui-p0/av_media.bit`，完整SHA256、资源、日志、源码快照与回归证据随发布包归档；以该目录README及SHA256SUMS为准。
当前尚未烧录或Flash固化；需用户验证七寸屏可读性、播放提示留白、EDIT随聚焦pending变化、确认/取消、双屏切图音频及应急。未提交或推送Git。

## 历史RTL阶段记录

# P0 菜单实施交接

已按方案8.1–8.5完成 `monitor_menu_renderer.v`，对应像素/相位测试与 `scripts/check_menu_p0.py`。
定向回归9/9（complete=true），10场景RGB、48卡四侧3/6像素边框、14保护输入哈希通过；字库检查通过。
原按键/配置控制器、顶层、HDMI-B代码和字库均相对本轮开始字节不变。

详细逐项改动、截图、验证边界、用户后续本机构建命令：
`docs/ui-review-20261021/p0-result/P0_MENU_CHANGELOG.md`。
方案文件和修改前源码保存在 `build/720p/backups/20261021-before-menu-p0/`。

用户要求停止等确认：当前review，不实施8.6/8.7、不综合/P&R/bitgen、不提交/推送。
资源BRAM9K≤57、视频setup≥0.15ns及LUT增量尚待实际构建；没有P0新bit或板验结论。

## 2026-10-22 用户复审修订

确认播放提示与y448卡片底边贴合，已改为单行x32/y456..472，8×16，文案K2 NEXT K3 AUTO HOLD K3 MENU，上下8px留白。确认页眉使用全局cfg_dirty，已改为同拍计算当前聚焦卡pending或二级edit，WAIT仍优先；四页新增状态切换RGB检查。亮度0档保留0。
修改前ZIP及原P0交付证据保存在build/720p/backups/20261022-before-menu-followup。继续不改8.6/8.7，不运行TD。
