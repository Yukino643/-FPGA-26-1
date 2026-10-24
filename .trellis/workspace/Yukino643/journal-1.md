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

### 2026-10-21：标题配色与UI审美交接

已备份当前工作区（含既有TD工程差异）；修改标题/时间颜色、图层标签改标题及同步字模映射，5/5定向回归通过。用户要求先将全局UI交由外部智能体评审，交付docs/ui-review-20261021完整现状报告、22张图、离线HTML、两份提示词与可上传ZIP。字幕文字保留旧版，最终文案及视觉方案待返回；本轮尚未完整TD构建、生成新bit、提交或推送Git。

### 2026-10-21：UI方案P0菜单，RTL交付后停止

按用户指定8.1–8.5执行，源文件修改前ZIP回读保存；renderer及独立像素/顶层相位测试、新check_menu_p0.py完成。9/9定向回归、10场景RGB、48卡3/6像素四边检查、14保护输入哈希、36字形及主屏字库检查通过。已查看6种RTL菜单PNG并比对方案主菜单效果图。逐项清单与后续TD命令见docs/ui-review-20261021/p0-result/P0_MENU_CHANGELOG.md；任务10-21-menu-ui-p0置review。保持按键/邮箱/顶层/主屏/字库bank，未做8.6/8.7、不运行综合/P&R/bitgen、无新bit或新资源时序结论，等用户确认；不提交/推送。

### 2026-10-22：P0菜单复审修订

确认并修复播放提示贴边：单行8×16在x32/y456..472，卡片下方与屏底各8px；EDIT移除全局cfg_dirty，取同拍聚焦卡pending或二级edit，WAIT优先。0档保留0。新增四页状态RGB和上下留白检查，9/9定向回归（变化项重跑）及最终依赖复核、10场景、48卡边框、14保护输入哈希通过；已查看新播放页PNG。备份build/720p/backups/20261022-before-menu-followup，清单及证据docs/ui-review-20261021/p0-result。保持不做8.6/8.7、不运行TD、无新bit；任务review等待确认。

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

## 2026-10-22 当前工程与字幕未实施项的外部审查交接

用户要求继续写现有工程详细说明。新增docs/ui-review-20261022/CURRENT_PROJECT_REVIEW.md、同名离线HTML和REVIEW_PROMPT.txt，UI_REVIEW_20261022.zip含14图、27源码快照和发布证据。明确菜单P0已做，主屏8.6/文案8.7未做，通知与旧三句保留；比较用户暂选和外部方案不同的第二句，计算字集55/47/50单元。记录现有全局dirty提交与局部READY语义、时钟/波形16px交叠、循环窗口、LED2为WAV发现锁存等审查点。110构建输入/bit清单未变，所有引用、ZIP/哈希独立回读通过；未修改RTL/字库/约束/bit，未新跑仿真/TD/烧录，未Git提交。


## Session 6: HDMI-B主屏与视界字幕完成，77项与严格时序通过，待板验

**Date**: 2026-10-22
**Task**: HDMI-B主屏与视界字幕完成，77项与严格时序通过，待板验
**Branch**: `feat/key2-next-prefetch`

### Summary

标题局部底板、右下时间、视界B组字幕和波形UI；官方映射及高扇出优化后LUT14161，BRAM57，video+.274ns；旧SDRAM跨域负余量单列。

### Main Changes

- 修改前574文件与旧bit已备份；菜单/按键/邮箱/SDRAM功能和约束哈希保持。
- 新发布目标build/720p/releases/20261022-main-ui；bit SHA256 a87d1d0b280f66e6c12229b27f68e6bcd51586f8db23b489ae87097728723fbb。

### Git Commits

(No commits - planning session)

### Testing

- [OK] 完整77/77；8组合3背景18滚动整圈；照片RTL2764800像素；完整TD和菜单/字幕/字体/缩放定向检查通过。
- [OK] video+.274/.024ns，SD+.219/.022ns，ext内部+.313/.030ns；旧加密SDRAMglobal setup−6.565ns单列。

### Status

[OK] **Completed**

### Next Steps

- 用户双屏板验8开关组合、三句三速、明暗底图、切图音频及应急；未烧录、Flash或Git提交。


## Session 7: WAV目录直达启动优化完成，82项与完整P&R通过

**Date**: 2026-10-22
**Task**: WAV目录直达启动优化完成，82项与完整P&R通过
**Branch**: `feat/key2-next-prefetch`

### Summary

复用FAT32根目录直接定位WAV，取消首图等待和LBA0原始扫描；根目录寻址分拍，LUT14267/BRAM57，严格域内时序通过，已独立归档。

### Main Changes

- WAV启动模型首PCM前总扇区请求2162降至8；真实出声时间待上板计时。

### Git Commits

(No commits - planning session)

### Testing

- [OK] 82/82完整回归；完整综合/P&R/bitgen；音频发布门限、缩放及字幕定向时序、缓存负向控制、ZIP与逐文件SHA256回读。

### Status

[OK] **Completed**

### Next Steps

- 用户烧录releases/20261022-audio-startup/av_media.bit，保持同一根目录WAV，冷上电至少5次记录首图/首声，播放期间切图20次。


## Session 8: HDMI-B音量和音频菜单完成，85项与完整P&R通过

**Date**: 2026-10-23
**Task**: HDMI-B音量和音频菜单完成，85项与完整P&R通过
**Branch**: `feat/key2-next-prefetch`

### Summary

音量0..100%、独立静音、波形和恢复默认二级页；双声道平滑增益与警笛旁路；目录簇号提前比较后严格域内时序收敛。

### Main Changes

- 修改前备份保留；新bit SHA256 8e3930111f9329802128d4e9b56c3eec628c9ef264899636245f87d1db93ad68，发布releases/20261023-audio-volume。

### Git Commits

(No commits - planning session)

### Testing

- [OK] 85/85完整回归，15929音量样本与13菜单场景；完整TD和字体/音量/缩放定向时序通过。LUT14817，BRAM9K57，DSP15，PLL3；video+.280/SD+.147/ext+.318ns；旧SDRAM跨域−6.565ns单列。

### Status

[OK] **Completed**

### Next Steps

- 用户显示器取消静音后烧录，检查音量、静音恢复、波形和警笛旁路；未操作TF卡、未Flash、未Git提交或推送。


## Session 9: 轮播周期2/3/5/10秒修复，89项与完整P&R通过

**Date**: 2026-10-23
**Task**: 轮播周期2/3/5/10秒修复，89项与完整P&R通过
**Branch**: `feat/key2-next-prefetch`

### Summary

忙时清零改为真实经过时间；改档重启、过期饱和不补切；FAT32 LBA拆拍，seed14完整构建通过。独立发布20261023-autoplay-period，四档菜单/提交/真实顶层转场测时通过，仍待真实TF卡板验。未提交Git。

### Git Commits

(No commits - planning session)

### Testing

- [OK] 89/89完整回归；video/SD/ext_mem setup +0.680/+0.138/+0.190ns，旧SDRAM跨域-6.565ns单列；源码/bit/ZIP哈希回读通过。

### Status

[OK] **Completed**

### Next Steps

- 用户下载新bit，用同一转场标志逐档连续5次秒表计时，音频开启并混排720/640/960图片。


## Session 10: 周期用户板验确认与赛题重新审计

**Date**: 2026-10-23
**Task**: 周期用户板验确认与赛题重新审计
**Branch**: `feat/key2-next-prefetch`

### Summary

重新提取并目视核对官方PDF14/15页，检查老师6/8/10页与当前顶层；官方五扩展均已有对应实现，更新旧审计口径，新增20261023审计和周期板验独立记录。只改文档，不改RTL/bit。

### Git Commits

(No commits - planning session)

### Testing

- [OK] 核对89/89发布证据、源码连接、用户板验范围；UTF8/LF及原发布SHA256SUMS回读通过。

### Status

[OK] **Completed**

### Next Steps

- 优先Flash脱机断电启动、双屏长稳、最终材料；小范围代码完善可选菜单跨卡预览确认防误操作。


## Session 11: 当前UI严格审美外部审查资料包

**Date**: 2026-10-23
**Task**: 当前UI严格审美外部审查资料包
**Branch**: `feat/key2-next-prefetch`

### Summary

按用户三分钟视频目标和严格美观优先要求整理；28张新RTL取证图、30份源码快照、完整几何配色字体状态/按键说明、审查提示词与返回模板、9.53MB ZIP。仅资料整理，未修改产品或提交Git。

### Main Changes

- docs/ui-review-20261023与离线ZIP，覆盖全部菜单、8种主屏组合、三句字幕和独立波形；明确夹具/照片输入/板验边界。

### Git Commits

(No commits - planning session)

### Testing

- [OK] 主屏/字幕10321920像素独立参考、13菜单状态逐像素/字索引及波形参考通过；215产品文件保护；30快照匹配发布版；链接/编码/图片/清单/ZIP CRC复核通过。

### Status

[OK] **Completed**

### Next Steps

- 等待外部AI以美观为主要返回proposal/UI_AESTHETIC_REVIEW.md；未授权自动实施其建议。


## Session 12: C方向640x360全幅菜单RTL及仿真完成

**Date**: 2026-10-24
**Task**: C方向640x360全幅菜单RTL及仿真完成
**Branch**: `feat/key2-next-prefetch`

### Summary

六项UI RTL/生成器修改完成。完整纯仿真86/86；18完整字幕周期、13菜单与16主屏图、64连续帧；保护范围215文件回读。未综合/P&R/烧录/Git，资源时序未测。

### Main Changes

- 640x360整数2x、右对齐/无星号、状态纯字、统一16px主屏内框、64格有限字幕循环、统一粗体ASCII。

### Git Commits

(No commits - planning session)

### Testing

- [OK] 完整--sim-only回归86/86；字幕71200590次像素核对、18圈；连续64帧5242880像素；照片16组14745600像素。

### Status

[OK] **Completed**

### Next Steps

- 当前仅交付源码和仿真；用户另行授权实际TD构建后验收BRAM9K≤57及video setup≥0.15ns，并记录LUT增量。


## Session 13: 全幅菜单完整物理构建与Git发布

**Date**: 2026-10-24
**Task**: 全幅菜单完整物理构建与Git发布
**Branch**: `feat/key2-next-prefetch`

### Summary

用户追加授权后完成当前源码综合/P&R/bitgen和88/88回归；LUT14837（-2）、BRAM9K57，video setup/hold +0.290/+0.020ns，菜单/OSD/字体/缩放器定向时序通过。独立发布20261024-menu-16x9，bit SHA256 afe5562c7740a7d93a4e1c3884770b9572332b8cb2a349fc5e2ea125922b138c，提交源码/证据/bit。

### Main Changes

- 640x360整数2x全幅；13菜单RTL图和16主屏组合、18字幕周期证据纳入提交。旧周期已板验版本保留。

### Git Commits

| Hash | Message |
|------|---------|
| `741d715` | (see git log) |

### Testing

- [OK] 完整86功能/生成检查按输入SHA复用并通过，2项当前源码物理检查新跑通过；111个Git暂存构建输入与实际manifest字节一致，新旧发布包SHA逐文件回读通过。

### Status

[OK] **Completed**

### Next Steps

- 用户烧录新bit检查7寸屏与双HDMI；本轮未烧录、未推送。旧SDRAM跨域-6.565ns单列，不宣称全局闭合。
