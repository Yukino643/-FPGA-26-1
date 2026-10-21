# Journal - Yukino643 (Part 1)

> AI development session journal
> Started: 2026-10-02

---

## 2026-10-02 - First image startup optimization

- Replaced raw sector-signature scanning with FAT32 root-directory BMP indexing and fragmented-file sector mapping.
- Delayed WAV scanning until `display_valid`; surfaced filesystem scan errors through the board diagnostic status.
- Pipelined BPB geometry validation after TD timing identified its arithmetic chain as the new critical path.
- Moved the status seven-segment scanner onto `sd_card_clk` (100 MHz) and adjusted its divider to retain 200 Hz per digit, removing a cross-domain hold violation.
- `bash scripts/regression.sh`: 35/35 passed. `bash scripts/regression.sh --full`: 36/36 passed.
- Final reports: SWNS -6.565 ns, HWNS +0.024 ns, LUT 81.11%, BRAM9K 75%. The existing setup path still has negative slack but passes the repository baseline tolerance.
- Board cold-start timing and a FAT32-to-HDMI end-to-end 3-second measurement remain pending.



## Session 1: 连续PCM曲线与无黑场双页转场

**Date**: 2026-10-03
**Task**: 连续PCM曲线与无黑场双页转场
**Branch**: `fix/bmp-header-spi-valid`

### Summary

连续插值曲线；默认16px双页横推；可选双页交叉淡化。当前源码全量构建通过，bit/manifest一致，分支与修改前恢复点已上传。

### Main Changes

- 沿用老师第十二讲采集契约和第十讲双页混合；页交接保持目标B一整帧。

### Git Commits

| Hash | Message |
|------|---------|
| `bcece2b` | (see git log) |

### Testing

- [OK] 基础40/40、完整41/41、独立报告fails=0；默认16px整链路101帧517120像素。

### Status

[OK] **Completed**

### Next Steps

- 下载2026-10-03 01:45:46生成的新bit，检查曲线、接缝、末帧、连续按键、音频及应急；setup仍负余量。


## Session 2: 圆润PCM波形与KEY2事务隔离

**Date**: 2026-10-03
**Task**: 圆润PCM波形与KEY2事务隔离
**Branch**: `fix/bmp-header-spi-valid`

### Summary

真实PCM的B样条与逐帧平滑；255积压请求、双成功提交及源写握手隔离；基础44/44，全量45/45，报告fails=0，bit和备份tag已推送。setup未全闭合，板测待用户下载。

### Main Changes

- 保留老师双bank完整组发布，消隐流水生成同步BRAM曲线
- 隔离失败源和旧完成，成功同拍锁显示pending；修复请求恢复、半字清理及短尾写入

### Git Commits

| Hash | Message |
|------|---------|
| `a75b408` | (see git log) |

### Testing

- [OK] basic44/full45/独立报告0失败；678次切换、20消抖按键模型、11成功0失败提交、3次全目标缩放

### Status

[OK] **Completed**

### Next Steps

- 板级检查波形圆润/时间平滑、KEY2逐次40次及转场中连按5次、两路HDMI和应急


## Session 3: HDMI-B 720p verified implementation

**Date**: 2026-10-13
**Task**: HDMI-B 720p verified implementation
**Branch**: `feat/hdmi-b-720p`

### Summary

HDMI-B 1280x720/60; RGB565 two pages, teacher frame ownership/blend/waveform; basic51/full52/report0; board pending

### Git Commits

| Hash | Message |
|------|---------|
| `fa1e485` | (see git log) |

### Testing

- [OK] 50 source checks; 6451200 pixels no underflow; 41 switches; audio2400 ticks; current-source TD

### Status

[OK] **Completed**

### Next Steps

- Board HDMI-B seven BMP/WAV, KEY2 repeat, cold-start and long stability


## Session 4: KEY2 next-frame prefetch and resource audit

**Date**: 2026-10-14
**Task**: KEY2 next-frame prefetch and resource audit
**Branch**: `feat/key2-next-prefetch`

### Summary

Recovered interrupted build, verified prefetch ownership and real memory-write checks, completed current-source TD and resources; GitHub upload pending network.

### Main Changes

- Prefetch next 720p image in idle page; teacher complete-page/frame-boundary rules retained.

### Git Commits

| Hash | Message |
|------|---------|
| `52cd68f` | (see git log) |

### Testing

- [OK] Source 52/52, basic 53/53, filtered full build 53/53 plus independent full display 6451200 pixels; reports 0 failures.
- [OK] Poisoned target page and real write interface count/mask check passed; disabled memory write negative test rejected.

### Status

[OK] **Completed**

### Next Steps

- Board-test hot/cold KEY2, continuous key presses, WAV and long-run prefetch.
- Push feat/key2-next-prefetch when GitHub TCP 443 or existing local proxy becomes available.

## 2026-10-17 - 多尺寸图片与双屏交互修复（待硬件验收）

- 修复应急条纹逐行相位、KEY2长按退出菜单、KEY3重入及提交正文/预览隔离；移除旧参数页。
- BMP24宽1..1280、高1..720，SDRAM紧凑源区0x100000，源/目标完整门分离；最近邻等比适配720p，640/800为960×720左右补黑。
- 两个逻辑行缓存映射4块32K RAM；输出打包、几何乘法、读命令及HDMI-A坐标/TMDS分拍；源writer数据资格寄存但读写互斥保持当拍。
- 完整TD构建20261017-multisize-tmds-ready生成当前清单匹配bit；LUT13801(70.41%)、寄存器8895(45.38%)、BRAM9K51/64、BRAM32K4/16、DSP13/29、PLL3/4。
- 新视频setup/hold+0.273/+0.022ns、串行+0.625/+0.068ns；缩放入/出及RAM全部正。旧TF/FAT与SDRAM仍有负setup，全局−6.565ns，未宣称全闭合。
- 最终72/72通过；普通与缩放并发显示各7帧6451200像素无欠载；TMDS独立逆解码/控制/复位/偏差、分批FIFO/尾突发/互斥、奇数宽/极端比例/取消重启均覆盖。
- TD6.2不能把32K RAM作为report_timing_path端点，改用官方report_cells逐引脚setup/hold；解析器负值注入验证可识别失败。TD原生stdout中文用户名GBK，保留原始日志并严格解码为UTF-8副本。
- 交付build/720p/releases/20261017-multisize-720p，bit SHA256 6655129d7b734e5a66e16267dc0d0c85fcb3bc775cd967246927d52415555d99。
- 用户尚需新bit双屏、640/800/奇数宽/720混合素材、菜单退出、应急及长时实测；未烧录/写TF/Flash固化，任务保持in_progress。本轮未提交Git。

## 2026-10-17 - 切图驻留颗粒与SDRAM周期刷新

- 用户确认应急与按键通过，HDMI-B偶发新图颗粒并保持到下一张；HDMI-A正常。多尺寸任务保持待硬件验收，新增image-sparkle-refresh跟进。
- global_def.v宏缺少括号，真实展开刷新周期0；sdr_init_ref可读前缀init_cnt不前进、周期ref_req无触发。老师完赛工程明确有同类宏括号修正。
- 保持125MHz/720p，只修配置头，终值3905，相邻请求3906拍（31.248µs），包含计数归零拍预算。
- 新测试抽取当前IP可读前缀；旧配置失败日志保留，新配置覆盖超过64ms、2060次请求/模拟ACK、四档有限忙等待、复位和关闭自动刷新/显式请求。
- 综合网表14位init_cnt和ref_req真实存在；不把理想数组无限保持数据的仿真当作物理刷新证明。
- TD告警表阶段号7.1/9.1变化引起首次误拒绝；按检查项名称结束表格，仍严格核对唯一SDRAM网名/驱动/数量。真实日志正例及视频网名/扇出/缺表负例通过。
- check_reports新增存储域内部setup/hold门，实际正例及负setup注入拒绝验证通过。
- 最终完整TD构建20261017-sdram-refresh-delivery成功；74/74功能和报告检查通过。LUT13818(70.50%)、reg8908(45.45%)、BRAM9K51、BRAM32K4、DSP13、PLL3。
- video+0.152/+0.031ns，serial+0.843/+0.041ns，存储域内部+0.033/+0.027ns；缩放出/入setup+0.269/+0.335ns，RAM最小setup+0.899、hold+0.483ns。
- 旧TF/FAT和SDRAM跨时钟负setup仍存在，全局−6.565ns，不能宣称全闭合。未修改TF卡、未烧录、未提交Git，先前dirty全部保留。
- 交付build/720p/releases/20261017-sdram-refresh；bit SHA256 295dfda5f2667c4c8f1f17d1fc01792206e5b155d17c797c018fdaef99e63112。待50次切图、预取驻留2/10/60秒、静态10分钟及轮播30分钟板验；刷新缺陷已证实，但颗粒消失需用户确认。
## 2026-10-18 SD路径优化候选评估未闭合

- 恢复并完成隔离候选 `optimization-bounds12/14` 的综合与opt_route，二者都未运行bitgen；既存发布bit保持不变。
- 最新源码依赖哈希回归重跑72/72通过。
- bounds12域内SD/ext_mem setup分别−0.255/−0.087ns，拒绝。
- bounds14 SD/ext_mem/video/HDMI串行域内setup分别+0.001/+0.093/+0.158/+0.950ns；缩放器from setup/hold +0.620/+1.276ns，to setup +0.750ns；TD `report_timing_path -to`的hold列表没有数值余量，故目标寄存器全覆盖门不通过。RAM最小setup/hold +1.189/+0.461ns。
- bounds14资源LUT13974、寄存器9063、BRAM9K51、BRAM32K4、DSP13、PLL3；比2026-10-17 bit多156 LUT和155寄存器，不算资源优化。
- 未签发bit、未烧录、未碰TF卡、未提交Git。下一步先解决TD定向hold报告的证据缺口；任务仍in_progress。

## 2026-10-18 SD路径优化评估收尾

- 复核bounds14隔离评估的全部输入哈希与当前工程一致；定向验收结果`failures=[]`。
- 逐引脚报告覆盖缩放寄存器237个单元/2034个引脚，最小hold +0.038ns；SD setup +0.001ns。旧记录中“目标hold缺数值、未完整验收”已由该证据更新。
- bounds14比2026-10-17已验证交付版增加156 LUT、155个寄存器，没有资源收益；SD余量过薄，不替换稳定交付bit。
- SPC预计算候选SD setup −0.539ns，已撤回实验RTL；非法SPC拒绝和后续合法重扫用例保留。撤回后完整回归为72/72。
- 用户明确优先稳定完成赛题，不追求极限优化。本轮评估结束，不继续边际RTL/P&R试验；未生成候选bit、未烧录、原发布bit保持不变。

## 2026-10-19 最终验收准备

- 按用户要求先保存现有版本，创建`build/720p/releases/20261019-pre-final-acceptance/`快照，包含当前源码归档、已验证bit、SHA256清单和Git状态。
- 快照保留的已验证bit为2026-10-17 SDRAM刷新交付版，SHA256为`295dfda5f2667c4c8f1f17d1fc01792206e5b155d17c797c018fdaef99e63112`。
- 新增`docs/FINAL_ACCEPTANCE_CHECKLIST_20261019.md`，区分仿真证据和板级证据，覆盖双屏、按键、外设、混合尺寸、长稳和Flash断电启动。
- 保存后复核回归为72/72通过。下一步转为板级验收，不再开启新的边际RTL时序优化。

## 2026-10-19 - 中文菜单接入收尾

- 按老师完赛工程的固定字模思路新增 `monitor_cjk_rom.v`，采用同步 16x16 ROM；菜单固定标题使用内部字模，避免综合时依赖外部 `$readmemh` 路径。
- `monitor_menu_renderer.v` 已接入节目页“图片/波形/时间/图层/周期”和外设页“外设/蜂鸣器/按键/板载灯”的中文标题，控制器、配置提交和 HDMI-B 图层逻辑未改。
- 将新模块加入三处工程源清单，并修正 `av_media.al` 的重复 CompileOrder。最新只综合日志无 `PRJ-5611`、无黑盒、无 HDL ERROR。
- 当前源码综合资源为 LUT 13860、寄存器 8965、BRAM9K 52/64；CJK ROM 占 1 个 BRAM9K。该轮未 P&R/bitgen，不能覆盖已验证 20261017 bit。

## 2026-10-19 - 中文菜单完整 P&R 与 bitgen

- 基于当前中文菜单源码完成 TD 综合、布局、布线、hold 修复和 bitgen，流程成功生成新 bit。
- 新 bit 归档在 `build/720p/releases/20261019-cjk-menu-bitgen/av_media.bit`，SHA-256 为 `5D84CBC1B0BE3716D2BA7990F5DC6FA98E6CF2372689EA80CE7D125E0749DF6A`；输入清单和 bit 清单一致。
- 物理资源：LUT 14264/19600、BRAM9K 52/64、BRAM32K 4/16、DSP 13/29、PLL 3/4；HWNS +0.027ns、HTNS 0，HDMI 5x setup/hold +0.872/+0.049ns。
- `video_clk` setup -0.234ns、`ext_mem_clk` 内部 setup -0.237ns，故 `check_reports.py` 的时序门保留 2 个失败项；不能把本轮结果描述为全工程时序闭合。
- 旧 `20261017-sdram-refresh` bit 未覆盖，新 bit 尚未烧录；下一步是双屏、中文菜单、切图和断电启动板级验收。

## 2026-10-21 - 修复中文标题与英文叠加

- 用户新 bit 双屏反馈中文菜单与原英文标题叠加，中文过小，两页底部按键英文提示影响观感。
- 根因：CJK 标题仅覆盖旧 ASCII 标题上方子区域，未命中 CJK 的区域继续进入 ASCII 标题分支；此前测试只核对索引，未核对完整标题 RGB。
- 删除 ASCII 卡片标题常量及分支；CJK 16x16 字模按 2x2 展开成 32x32，两字/三字宽度按页面与标题实际长度选择。
- 菜单激活时关闭两行底部提示，播放模式保留提示；状态值和按键功能不变，字库同步读及整条视频延迟保持不变。
- 新增独立“图”字逐像素 2x2 参考、原英文残留区域及菜单底部全像素检查；定向4/4通过，完整输入哈希回归72/72通过，两页PNG已人工检查。
- 修复前源码备份与新仿真图保存在 build/720p/ui-fix-20261021/；当前正在完整TD构建，最终状态另记。

## 2026-10-21 中文菜单重叠、字号与底部清理（已生成验证 bit）

- 删除卡片旧 ASCII 标题路径，修复中文仅覆盖英文部分区域而产生交叠的问题。
- 中文字模从 16x16 放大为逻辑画布 32x32，最终720p放大区约48x48；节目页双字64像素宽，外设页双字/三字分别64/96宽。
- 两个菜单页关闭底部两行白色操作提示；播放模式提示、页眉、ON/OFF等状态值和按键行为保留。
- 本机参考老师 `topic1_student_reference/project_code/rtl/display/brand_watermark_24.v` 与 `subtitle_scroll_24.v`：固定BRAM字模、明确文字边界、同步读字模及RGB/DE/HS/VS同拍延迟。放大通过坐标右移复用原ROM，不增加大字库。
- 新增独立字形逐像素2x2参考、旧英文残留区域和菜单底部全像素检查；定向4/4通过，完整哈希回归72/72通过。故意恢复底部文字的反例被测试拒绝。两页PNG人工查看无叠字和底部提示。
- 完整TD综合/P&R/hold修复/bitgen完成，基础check_reports为0失败。物理资源LUT14112/19600（72.00%），寄存器9082/19600（46.34%），BRAM9K52/64，BRAM32K4/16，DSP13/29，PLL3/4。
- 视频setup/hold +0.159/+0.030ns，HDMI串行 +0.936/+0.166ns，ext_mem内部 +0.177/+0.021ns，全局hold +0.021ns；全局旧setup -6.565ns。
- 额外check_resize_timing定向报告失败：from_regs捕获SD域load_img_w到src_packer的setup -0.567ns，不能以基础报告0失败宣称完整时序通过。四块缩放RAM引脚setup/hold均非负；完整报告保留。
- 验证bit：`build/720p/releases/20261021-cjk-ui-clean/av_media.bit`，SHA256 `5b1ab1bd3039d58d21a2972de714f2e105b7078f56655940beb53847d4d16bbe`。
- 当前只交付JTAG板验版本，未烧录，未验证新画面在实物屏幕的最终效果，未做Flash固化；不宣称全工程setup闭合。原20261017及20261019发布目录保留。

## 2026-10-21 六卡屏幕设置与32×32中文（已归档，待板验）

CONTROL两行三列、HDMI-B亮度/对比度/色温/默认二级页、黄色圆点内缩16逻辑像素完成。
中文由16×16放大升级为原生32×32，标题尺寸和视频流水线不变；按老师实际用字ROM和位宽裁剪案例，只保存31字，并消除字库地址表达式的32位进位链。
73/73回归通过（依赖哈希未变化项复用，菜单/双屏相位重跑）；颜色243档组合/62208样本、VS变异负例与六页PNG检查通过。TD当前源码完整综合/P&R/bitgen、清单/资源/新增域内时序、菜单与缩放定向检查通过。
最终资源LUT 14407/19600，reg 9207/19600，BRAM9K 55/64，BRAM32K 4/16，DSP 13/29，PLL 3/4。
[RPT][PASS] video_clk setup=0.123ns hold=0.053ns
[RPT][PASS] hdmi_5x_clk setup=0.970ns hold=0.041ns
[RPT][PASS] ext_mem_clk内部 setup=0.174ns hold=0.027ns
[RPT][PASS] SWNS=-6.565ns (基线 -6.699ns, 容差 0.5)
[RPT][PASS] HWNS=0.022ns (hold 无违例)
旧SDRAM全局setup -6.565ns仍单列，不声称全工程setup闭合。中间predecode的-0.421ns视频失败版未发布，其报告保存在隔离构建目录rejected-reports；最终有界寻址版本视频+0.123ns。
发布：build/720p/releases/20261021-screen-menu-cjk32/av_media.bit；SHA256 d2ab030fa8d33f729f186bc3c4b59bcd548f5adf397ee8f2ec8308ff4a63d5c7。
原cjk-ui-clean bit哈希不变；尚未烧录、未板验、未Flash固化。按键教学见docs/HDMIB_SCREEN_MENU_20261021.md。工作区历史修改保留，未自动Git提交。

## 2026-10-21 预设滚动字幕（本机验收完成，待双屏板验）

用户已确认上一版六卡、原生32中文、HDMI-B屏幕参数板验正常。修改前416文件源码快照、原bit和发布包已保存到build/720p/backups/20261021-before-subtitle，SHA256及压缩包回读通过；原板验bit哈希保持d2ab030fa8d33f729f186bc3c4b59bcd548f5adf397ee8f2ec8308ff4a63d5c7。
本轮CONTROL仍六卡，原图层改为字幕入口，二级页保留字幕/内容/速度/原图层四卡。HDMI-B底部深色半透明条、通知标记、原生32像素白字，三条预设和30/60/120像素每秒；开启时运行时间移右上，波形不重叠。字幕默认关闭，复位恢复默认。确认VS提交，busy正文保护、取消和长按应急保留。
完整回归75/75（complete=true/filter=null，未变项按依赖哈希复用），8页菜单和3条字幕真实RTL预览已人工查看；独立字索引/逐像素/裁剪/回绕/速度/时间避让/顶层相位通过，去除VS门控负例被正确拒绝。中文地址改为绝对字格边界、ROM持续读而输出按命中屏蔽，41984个标题像素与旧算法等价；OSD时间/标题/模式并行译码，共用唯一字体ROM，不增加视频延迟。
当前源码完整TD综合/P&R/hold修复/bitgen完成，check_reports零失败；菜单/邮箱/渲染器/颜色/OSD寄存器及字体/缩放物理RAM入出定向时序通过。
| lut | 14875/19600 | 75.89% |
| reg | 9315/19600 | 47.53% |
| bram | 57/64 | 89.06% |
| bram32k | 4/16 | 25.00% |
| dsp | 13/29 | 44.83% |
| pll | 3/4 | 75.00% |

[RPT][PASS] video_clk setup=0.262ns hold=0.036ns
[RPT][PASS] hdmi_5x_clk setup=0.370ns hold=0.041ns
[RPT][PASS] ext_mem_clk内部 setup=0.017ns hold=0.035ns
[RPT][PASS] SWNS=-6.565ns (基线 -6.699ns, 容差 0.5)
[RPT][PASS] HWNS=0.022ns (hold 无违例)

旧SDRAM全局setup -6.565ns继续单列，不声称全工程setup闭合。初版ASCII路径-0.732ns、textpath中文-0.003ns/缩放-0.037ns、seed13中文-1.270ns、glyphaddr OSD-0.499ns/显示FIFO-0.353ns均已隔离保留报告，未发布。最终parallel-osd采用原布局seed12并以RTL并行译码通过，不放宽约束或门限。
发布：build/720p/releases/20261021-preset-subtitle/av_media.bit；SHA256 d23b57a95832bc495678556cb34280770719a576be76b46499aae94a826fe6f4。
本轮尚未烧录、未双屏实物验证或Flash固化；重点检查字幕观感、菜单确认/取消、切图、音频与应急。按键详解docs/PRESET_SUBTITLE_20261021.md。保留工作区历史dirty/untracked，未自动Git提交。
