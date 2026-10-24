# 双 HDMI 监视与控制台进度记录

更新时间：2026-10-16

## 当前已完成

- HDMI-B 保持 1280x720 主节目输出。
- HDMI-A 监视内容使用 640x480 逻辑画布，对外采用标准 1280x720@60Hz 时序；当前已按 1.5 倍最近邻放大到居中的 960x720 区域，左右各 160 像素黑边，适合 7 寸屏观察。
- HDMI-A 菜单 UI 已重构：四张卡片均匀 2x2 排列，新增页眉/页脚操作提示、ON/OFF/READY/TEST 状态文字和 2 倍逻辑字模，修复旧布局中卡片拥挤、字库错位和文字难读问题。
- HDMI-A 监视页支持状态显示和节目控制菜单框架：IMAGE、WAVE、CLOCK、VISUAL。
- 新增菜单控制、长短按区分、预览/确认/取消和 200 ms 蜂鸣器测试逻辑。
- 新增 `monitor_config_regs.v`，采用 shadow/active 配置和 toggle CDC，在 HDMI-B 帧边界提交配置。
- HDMI-B 已接入图片、波形、时间 OSD、文字图层四个配置位。
- 原有回归仿真此前记录为 54/54 PASS。
- 双 HDMI 完整综合此前已经成功生成 bit。

## 上一次完整综合结果

来自 `td_prj/av_media_Runs/syn_1/av_media_gate.area`：

| 资源 | 使用量 |
|---|---:|
| LUT | 14691 / 19600，74.95% |
| Register | 10025 / 19600，51.15% |
| BRAM9K | 63 / 64，98.44% |
| DSP | 9 / 29，31.03% |
| PLL | 3 / 4，75.00% |

布局布线结果已经生成 `td_prj/av_media_Runs/phy_1/av_media.bit`，但时序报告仍有软件时序负裕量，不能把它当作最终板级通过：

- `SWNS = -6.565 ns`
- `STNS = -357.132 ns`
- 硬件时序 `HWNS = 0.024 ns`
- 详细路径中仍有约 `-0.713 ns` 的软件时序负裕量

暂停时 `phy_1/build_manifest.sha256` 曾被综合输出删除；后续构建已经重新生成清单，当前 bit 与清单一致。旧记录中的“清单缺失”仅描述暂停时状态。

## 参考老师完赛工程得到的资源结论

参考工程路径：

`D:\FPGA\micu_FPGA_lesson\选题一完赛参考工程代码\米醋电子工作室忧郁完赛参考工程`

参考工程的 HDMI-B 路径采用自有轻量 TMDS/音频模块；其 HDL 中包含：

- `risk_prototypes/hdmi_audio_route_b/rtl/hdmi_tmds_channel_encoder.v`
- `risk_prototypes/hdmi_audio_route_b/rtl/hdmi_tmds_eg4_phy.v`
- `risk_prototypes/hdmi_audio_route_b/rtl/hdmi_audio_symbol_core.v`
- `rtl/integration/media_hdmi_audio_bridge.v`

当前工程的综合层级显示，第二个完整 `hdmi_1_4b_transmitter_core_wrapper` 约占用 10 个 BRAM9K；其中主要来源为：

- EDID/IIC 路径约 2 个 BRAM9K；
- HDMI 视频 AXI 接收 FIFO 约 3 个 BRAM9K；
- 即使音频输入接常数 0，音频数据岛路径仍约 5 个 BRAM9K。

因此 HDMI-A 作为纯监视通道继续复用完整 HDMI 音频核，会把 BRAM 从原来的约 49 个推高到 63 个，余量只剩 1 个。

## 资源优化实现结果

已经新增两个 RTL 文件：

- `rtl/hdmi/hdmi_tmds_channel_encoder.v`
- `rtl/hdmi/hdmi_video_only_640x480.v`

并已在 `rtl/top/top_tf_hdmi_audio.v` 中把 HDMI-A 的完整 HDMI 发射核替换为纯视频 TMDS 编码路径：

- 删除 HDMI-A AXI 视频适配器；
- 删除 HDMI-A EDID 启动脉冲和 DDC 读链；
- 删除 HDMI-A 完整 HDMI 1.4b 音频/数据岛发射核；
- 保留 HDMI-A 640x480 时序、监视渲染器和现有 HDMI PHY；
- HDMI-A DDC 暂置空闲电平。

已完成以下工作：

- 两个新 RTL 文件已经加入 `create_project.tcl`、`add_new_sources.tcl` 和 `av_media.al`；
- TD 综合成功 analyze/elaborate，无新增黑盒和 HDL ERROR；
- 综合资源下降到 LUT 13610、Register 8807、BRAM9K 53；
- 使用布局 seed 7 完成布局、布线、hold 修复和 bitgen；
- 当前 `av_media.bit` 已生成，`build_manifest.sha256` 已生成；
- `scripts/check_reports.py` 已通过 bit 与 SHA-256 清单、物理报告一致性、BRAM/LUT/HWNS 检查。

最终物理资源报告 `td_prj/av_media_Runs/phy_1/av_media_phy.area`：

| 资源 | 最终使用 |
|---|---:|
| LUT | 14065 / 19600，71.76% |
| Register | 8924 / 19600，45.53% |
| BRAM9K | 53 / 64，82.81% |
| DSP | 9 / 29，31.03% |
| PLL | 3 / 4，75.00% |

物理时序报告 `td_prj/av_media_Runs/phy_1/av_media_pr.timing`：

- `HWNS = +0.027 ns`，`HTNS = 0`，硬件 hold 无违例；
- `SWNS = -6.565 ns`，`STNS = -565.507 ns`；
- `video_clk` setup 仍未闭合，`check_reports.py` 因此保留 1 个失败项；
- `hdmi_5x_clk` setup/hold 已通过。

布局 seed 7 解决了 seed 6 在 `u_mon_compositor` hold-buffer 上的 `PHY-8023` 增量布线冲突。当前 bit 是 seed 7 重新生成的版本，不是暂停前残留 bit。

## 恢复工作时的下一步

1. 将 `td_prj/av_media_Runs/phy_1/av_media.bit` 下载到板上，确认 HDMI-A 能锁定标准 720p 输入，并显示居中的放大监视画面；
2. 同时确认 HDMI-B 图片、音频、波形、OSD 和 KEY2 播放行为没有回归；
3. 在 HDMI-A 菜单中测试预览、确认、取消及应急模式优先级；
4. 如果板级 HDMI-A 在部分显示器上无法锁定，再评估恢复 DDC/EDID 或回退完整 HDMI-A 发射核；
5. 后续单独处理 720p `video_clk` setup 负裕量，不能通过放宽检查门限冒充时序闭合。

## 风险记录

- 新 TMDS 路径采用老师资料中的视频编码思路，但没有复用加密 HDMI IP 的内部实现；综合和物理实现已通过，仍需板级验证 Anlogic EG4 PHY 输入时序。
- HDMI-A 无音频和 EDID 后，部分显示器可能仍能通过固定 640x480 DVI 时序锁定，也可能要求 DDC；不能仅凭 RTL 仿真确认兼容性。
- HDMI-A 已切换到与 HDMI-B 相同的 720p 时钟和同步参数，规避了原 74.25MHz 驱动 800x525 总时序导致的约 176.8Hz 非标准输入；当前仍未恢复 DDC/EDID，若个别显示器不锁定需单独评估。
- `git status` 中已有用户和前序任务修改，暂停时没有回滚任何文件。

## 2026-10-16 菜单重复显示与 KEY4 修复

本轮板级照片暴露了两个问题：节目控制页和外设页的底行卡片复用了顶行的编号，导致上下都显示 `IMAGE/WAVE` 或 `TF CARD/BEEP`；另外，上一笔配置提交的 ACK 尚未返回时，`KEY4` 短按会被忙状态静默丢弃。

已完成修复：

- `monitor_menu_renderer.v` 改为显式二维卡片编号：
  - 左上 `0`、右上 `1`；
  - 左下 `2`、右下 `3`；
  - 底行分别显示 `CLOCK/VISUAL` 或 `KEYS/LEDS`。
- `monitor_menu_ctrl.v` 的 `KEY4` 预览与提交分开处理：第一次短按修改 `cfg_shadow`，第二次短按在 ACK 空闲后提交；上一笔 ACK 未返回时仍允许新的预览，不再无提示丢键。
- 菜单长按 `KEY3` 翻页时自动丢弃未提交预览，避免节目页和外设页之间带入旧配置。
- `top_tf_hdmi_audio.v` 将提交 ACK 改为显式连续赋值，避免重复网络声明造成工具差异。
- `flow_fixhold.tcl` 使用 seed 7；seed 8/9 在本轮网表上均出现局部 hold ECO 增量布线冲突，seed 7 已完成 bitgen。

本轮最终构建：

- bit：`td_prj/av_media_Runs/phy_1/av_media.bit`
- LUT：14337/19600（73.15%）
- Register：物理报告约 45%
- BRAM9K：53/64（82.81%）
- PLL：3/4（75%）
- 硬件 hold：`HWNS=+0.022ns`，无违例
- HDMI 5x setup：`+0.092ns`
- 既有 HDMI-B `video_clk` setup：约 `-5.693ns`，仍未闭合，不能宣称全工程时序通过
- `scripts/check_reports.py`：bit、manifest、物理报告、BRAM/LUT/HWNS 检查通过；仅保留既有 `video_clk setup` 失败项

## 2026-10-16 上电菜单、板载 LED 与选中圆点

- `monitor_menu_ctrl.v` 复位后直接置 `menu_active=1`、`menu_page=0`，HDMI-A 上电即显示 `PROGRAM CONTROL`；不再需要先长按 KEY3 进入旧参数页。
- KEY3 长按只负责在 `PROGRAM CONTROL` 与 `PERIPHERAL TEST` 两页之间切换；KEY2 长按只取消当前预览并留在菜单页。
- 外设页第四张卡片改为 `LEDS`，真实引脚来自老师完赛工程：`led[0]=A4`、`led[1]=A3`、`led[2]=C10`、`led[3]=B12`，均按高电平点亮。
- LED 语义：复位/TF 初始化期间四灯全亮；初始化完成后 LED0 为 FPGA 心跳，LED1 为当前图片有效，LED2 为检测到 WAV，LED3 为应急或 SD 超时告警。HDMI-A 同步显示四灯十六进制组合，例如 `LED F`。
- 选中卡片保留黄色边框，并在卡片右侧增加 8x8 位图圆点；采用坐标高位和常量位图实现，避免把多组范围比较器放进像素关键路径。

### 最新构建

- bit：`td_prj/av_media_Runs/phy_1/av_media.bit`（2026-10-16 20:15）
- LUT：14381/19600（73.37%）
- Register：8938/19600（45.60%）
- BRAM9K：53/64（82.81%）
- DSP：9/29（31.03%）
- PLL：3/4（75.00%）
- `hdmi_5x_clk` setup/hold：`+0.281 ns / +0.041 ns`
- 硬件 hold：`HWNS=+0.021 ns`、`HTNS=0`
- 既有 `video_clk` setup：`-6.590 ns`；相对基线 `-6.699 ns` 在允许容差内，但仍未完全闭合，不能宣称全工程时序通过。

验证结果（2026-10-17复核修正）：约束、`monitor`、`monitor_menu_ctrl`通过；`top_commit_order`本轮正常通过。历史上被误认为挂起的是耗时较长的`disp`，本轮独立运行366.9秒后通过，不能再把它记成提交门死锁。

## 2026-10-17 多尺寸、应急与播放按键（软件验证完成，待板验）

本节优先于上方历史构建记录；不能拿旧bit或旧资源数字代表当前版本。

- 修复应急条纹逐行推进导致倾斜：改为有效帧首坐标每帧推进一次。
- KEY2长按约1.2秒松开退出菜单并取消未提交预览，播放状态KEY2短按下一张、KEY3短按自动；KEY3长按回菜单。退出不自动打开已关闭的IMAGE，先在菜单按两次KEY4完成ON预览与提交。
- 主节目支持边界内不同源尺寸BMP24，输出仍720p。640×480/800×600等比放大到960×720，左右黑边；奇数宽正常处理。
- 源区0x100000与双显示页隔离；解析/源写双完成才缩放，完整目标页写完才发布；两块逻辑行RAM实际占4块BRAM32K。
- HDMI-A移除旧参数页，坐标/字库/RGB共三拍；TMDS变换与输出偏差拆两级，已通过独立逆解码与控制/复位测试。
- 源writer寄存FIFO数据资格与预先锁定突发长度；读占用/刷新仍当拍互斥，分批供数、尾突发与重启测试通过。
- 完整TD构建`20261017-multisize-tmds-ready`成功签发当前源/bit清单。此前geometry版本的video setup−0.200ns、新增缩放入向−0.648ns已消除。
- 最终`regression_native.py --reuse`：72/72通过，所有复用结果逐项核对当前输入hash；包含新TMDS、各尺寸/生命周期、真实源链、双屏流水、音频/预取和报告门。
- 普通`display720`与实际缩放并发`resize_display720`各检查7帧、6451200像素，静态/混合/交接无欠载；后者当前版本耗时747.2秒，正常耗时不能判为死锁。

使用说明：`docs/KEY_GUIDE_20261017.md`、`docs/MULTISIZE_IMAGES_20261017.md`。赛题缺项与参考依据：`docs/REQUIREMENTS_AUDIT_20261017.md`。

| 本轮物理资源 | 实际使用 |
|---|---|
| LUT | 13801/19600，70.41% |
| 寄存器 | 8895/19600，45.38% |
| BRAM9K | 51/64，79.69% |
| BRAM32K | 4/16，25.00% |
| DSP | 13/29，44.83% |
| PLL | 3/4，75.00% |

| 本轮时序检查 | 结果 |
|---|---|
| video_clk setup/hold | +0.273/+0.022ns |
| hdmi_5x_clk setup/hold | +0.625/+0.068ns |
| 缩放寄存器出/入最差setup | +0.157/+0.167ns |
| 缩放4块物理RAM全部引脚 | setup/hold均非负，setup最小+1.334ns，hold最小+0.395ns |
| 全局setup/hold | −6.565/+0.022ns；旧TF/FAT与SDRAM路径仍有负setup，不是全工程时序闭合 |

定向时序脚本读取当前P&R数据库。TD6.2不能把32K RAM用作`report_timing_path`筛选端点，改用官方`report_cells -timing`及`-hold`，核对4块RAM的全部入出引脚，禁止把空报告当通过。

交付目录：`build/720p/releases/20261017-multisize-720p/`。包含`av_media.bit`、当前构建清单、资源/时序报告、72项结果、缩放定向报告、三张测试素材、按键/审计说明、`source-and-bit.zip`及归档SHA-256；ZIP执行CRC与构建输入逐字节回读核对。

本轮bit SHA-256：`6655129d7b734e5a66e16267dc0d0c85fcb3bc775cd967246927d52415555d99`。

当前待完成：用户双屏/混合素材板验。未操作TF卡、未替用户烧录、未验证Flash冷启动。任务保持in_progress等待硬件验收；目前无须因这些功能增加第二块板子，但仍要尊重旧TF/SDRAM时序及真实带宽的限制。

## 2026-10-17 切图白色颗粒与SDRAM刷新修复（软件与缺陷复测完成）

本节是最新交付，优先于上方多尺寸版本记录。用户确认应急条纹及按键修复正常；新增反馈为HDMI-B偶发新图驻留颗粒，下一次切换恢复，HDMI-A未发现异常。

- 确认SDRAM配置头的宏缺少括号：刷新表达式展开为连续整数除法，结果0。实际IP可读计数前缀的init_cnt停在0，周期ref_req不触发，顶层显式刷新请求又固定为0。
- 老师完赛工程已对同类宏加括号；本工程保留125MHz。额外考虑比较后归零一拍，终值3905，相邻周期请求3906拍（31.248µs）。不修改加密IP或PLL。
- 当前预取页写完后等待按键，需要刷新维持数据；整帧发布门只能保证写入完整，不能保证后续数据保持。缺少刷新与用户现象相符，但硬件根因闭环仍以新bit复测为准。
- 修复前真实IP前缀测试失败：period_ns=8、slot_cycles=0、requests=0。修复后超过64ms产生/模拟应答2060次，间隔准确，复位与关闭自动/显式请求通过。
- 综合数据库查到14位init_cnt与ref_req寄存器，证明确实进入硬件网表。理想SDRAM数组没有数据保留时间，原像素测试因此无法覆盖该缺陷；没有宣称已仿真加密命令生成器或物理SDRAM。
- 构建告警解析器原来写死Clock Net Status Check阶段7.1，本轮TD为9.1。已按同一检查项名称确定表格边界，唯一SDRAM网名/驱动/扇出/标记白名单保留；真实两种日志通过，视频网名、扇出和缺表负例拒绝。
- 新增ext_mem_clk域内部setup/hold门，负setup注入被拒绝；不以旧硬核跨时钟基线掩盖普通存储逻辑违例。

最终构建：`build/720p/td/20261017-sdram-refresh-delivery`，完整综合、布局布线、bitgen和当前源清单成功。最终`regression_native.py --reuse`为74/74通过；未受影响项按实际依赖hash复用，新增刷新测试及报告门均纳入。

| 本轮物理资源 | 使用 |
|---|---|
| LUT | 13818/19600，70.50% |
| 寄存器 | 8908/19600，45.45% |
| BRAM9K | 51/64，79.69% |
| BRAM32K | 4/16，25.00% |
| DSP / PLL | 13/29；3/4 |

| 本轮时序 | setup / hold |
|---|---|
| video_clk | +0.152 / +0.031ns |
| hdmi_5x_clk | +0.843 / +0.041ns |
| ext_mem_clk域内部 | +0.033 / +0.027ns |
| 缩放寄存器及4块物理RAM入出 | 均非负，见resize_timing/summary.json |
| 全局 | −6.565 / +0.024ns；旧TF/FAT及SDRAM跨时钟路径仍有负setup，未全闭合 |

交付：`build/720p/releases/20261017-sdram-refresh/av_media.bit`；同目录保留源码ZIP、SHA256、完整报告、74项结果、修复前失败日志、实际刷新/网表证据和说明。

bit SHA256：`295dfda5f2667c4c8f1f17d1fc01792206e5b155d17c797c018fdaef99e63112`。

2026-10-18 用户反馈已验证，切图颗粒修复成功。故障修复任务由此关闭。对话没有记录切换次数、静态驻留时间和自动轮播时长，因此更广泛的长时间可靠性结论仍未形成；不要把本次确认扩大解释为所有长稳场景均通过。bit SHA256与资源时序信息保持不变。没有替用户烧录或修改TF卡。本轮未提交Git，保留此前全部工作区改动。

## 2026-10-19 最终验收准备

- 已保存当前源码和已验证 bit 快照：`build/720p/releases/20261019-pre-final-acceptance/`。
- 快照中的已验证 bit SHA256 为 `295dfda5f2667c4c8f1f17d1fc01792206e5b155d17c797c018fdaef99e63112`；快照操作未生成新 bit、未修改 RTL。
- 新增 `docs/FINAL_ACCEPTANCE_CHECKLIST_20261019.md`，将72/72仿真证据与必须板级确认的冷启动、双屏、按键、50次切图、10分钟驻留、30分钟轮播、Flash断电启动分开记录。
- 保存快照后复核 `scripts/regression_native.py --sim-only --reuse`，结果仍为72/72通过。
- 下一步为烧录已验证 bit 并完成现场清单；在现场证据完成前，不宣称长时间稳定性和Flash断电启动已通过。

## 2026-10-19 自动轮播、中文菜单与节目页重构

- 节目控制页改为 3+2 卡片布局，新增 PERIOD 设置；周期档位为 1/2/5/10 秒，默认 1 秒。第一次 KEY4 修改 shadow 预览，第二次 KEY4 在帧边界提交；长按 KEY2 取消预览。
- HDMI-A 菜单渲染器、控制器和流水线已同步为 3 位光标；外设页仍保持 2x2，避免重复卡片和文字挤压。选中卡片保留黄色边框并显示右侧黄色圆点。
- 中文字符已加入字库生成输入，`legacy_generated` 生成物检查通过；本轮字幕仍采用 FPGA 内部预置文本，未引入 TF 文本解析。
- `regression_native.py --sim-only --reuse`：72/72 通过；`monitor_menu_ctrl`、`monitor_menu_renderer`、`monitor_pipeline` 定向测试通过。
- TD 综合通过，资源为 LUT 13794/19600（70.38%）、寄存器 8964/19600（45.73%）、BRAM9K 51/64（79.69%）、BRAM32K 4/16（25.00%）、DSP 13/29（44.83%）、PLL 3/4（75.00%）。
- 本轮未执行布局布线和 bitgen，未覆盖已验证的 `20261017-sdram-refresh` bit；图片与音频逐图绑定继续暂缓。

## 2026-10-18 SD/存储控制路径优化评估

- 参考老师完赛工程的寄存读口与状态分拍原则，当前源码补充分阶段请求映射和BMP文件长度边界检查；最新完整功能回归 `regression_native.py --sim-only --reuse` 为72/72，输入依赖哈希匹配。
- 隔离布局 `optimization-bounds12`：SD域−0.255ns、ext_mem域−0.087ns，严格检查拒绝。
- 隔离布局 `optimization-bounds14`：SD域+0.001ns、ext_mem域+0.093ns、video域+0.158ns、HDMI串行域+0.950ns；缩放器入向setup/hold+0.620/+1.276ns，出向setup+0.750ns；逐引脚hold覆盖237个寄存器/2034个引脚，最小+0.038ns。四块缩放RAM最小setup/hold+1.189/+0.461ns，最终检查器`failures=[]`且输入哈希匹配。
- bounds14使用LUT13974、寄存器9063、BRAM9K51、BRAM32K4、DSP13、PLL3；相对2026-10-17交付版增加156 LUT与155寄存器，无资源下降。
- bounds14的SD setup仅+0.001ns，较2026-10-17已验证交付版增加156 LUT和155个寄存器；余量过薄且没有资源收益，按稳定完成赛题的目标不采用该候选。
- SPC合法性预计算候选的SD setup为−0.539ns，已撤回其实验RTL，只保留0/3/255非法SPC拒绝与合法重扫测试。
- 本轮完整回归72/72通过，优化评估到此结束；不再开展边际RTL/P&R试验，不生成候选bit、不覆盖已验证bit。原发布bit未改，未烧录，未做本轮板级验证。

## 2026-10-19 中文菜单接入与工程收尾

- 参考老师完赛工程的固定字模做法，新增 `rtl/video/monitor_cjk_rom.v`，使用同步 16x16 字模 ROM，菜单标题不依赖外部 `$readmemh` 路径。
- HDMI-A 节目页标题接入“图片、波形、时间、图层、周期”，外设页接入“外设、蜂鸣器、按键、板载灯”；状态值和操作提示继续使用 ASCII，控制器和配置协议不变。
- `monitor_cjk_rom.v` 已加入 `add_new_sources.tcl`、`create_project.tcl`、`av_media.al` 及原生回归依赖；`av_media.al` 的新模块编译序号已整理为唯一值，最新日志无 `PRJ-5611`。
- 当前源码定向菜单测试和此前 72/72 回归保持通过；本轮重新执行 TD 只综合，无黑盒和 HDL ERROR。

### 当前源码综合（仅综合，不是新 bit）

| 资源 | 使用量 |
|---|---:|
| LUT | 13860 / 19600（70.71%） |
| Register | 8965 / 19600（45.74%） |
| BRAM9K | 52 / 64（81.25%） |
| DSP | 13 / 29（44.83%） |
| PLL | 3 / 4（75.00%） |

综合目录：`build/720p/synthesis-20261019-cjk-rom-final2/`。CJK ROM 额外占用 1 个 BRAM9K，仍未引入第二套帧缓存。

本轮没有执行布局布线和 bitgen，已验证烧录基线仍是 `build/720p/releases/20261017-sdram-refresh/av_media.bit`，其 SHA-256 不变。中文菜单要上板，必须基于当前源码重新完成完整 P&R/bitgen，并重新做双屏板级验收；不能把本轮综合结果当作可烧录文件。

## 2026-10-19 中文菜单完整 P&R 与 bitgen

- 已基于当前源码执行完整 TD 流程：综合、布局、布线、hold 修复和 bitgen 均完成。
- 新 bit 归档于 `build/720p/releases/20261019-cjk-menu-bitgen/av_media.bit`，SHA-256：`5D84CBC1B0BE3716D2BA7990F5DC6FA98E6CF2372689EA80CE7D125E0749DF6A`。
- bit、`build_manifest.sha256`、输入清单、综合/物理日志和资源/时序报告已一并归档；bit 与源码清单校验一致。

### 新 bit 物理结果

| 资源/时序 | 结果 |
|---|---:|
| LUT | 14264 / 19600（72.78%） |
| BRAM9K | 52 / 64（81.25%） |
| BRAM32K | 4 / 16（25.00%） |
| DSP | 13 / 29（44.83%） |
| PLL | 3 / 4（75.00%） |
| HWNS / HTNS | +0.027 ns / 0 ns，hold 无违例 |
| HDMI 5x setup / hold | +0.872 ns / +0.049 ns |
| video_clk setup | -0.234 ns |
| ext_mem_clk 内部 setup | -0.237 ns |

`scripts/check_reports.py` 的 bit、清单、资源和硬件 hold 检查通过；由于 `video_clk` 和 `ext_mem_clk` 仍有 setup 负余量，报告保留 2 个时序失败项，不能宣称全工程时序完全闭合。该结果与工程此前的“旧存储/视频路径存在 setup 负余量”边界一致，需板上重点观察双屏、切图和长时间运行。

本轮 P&R 使用 `flow_fixhold.tcl` 的 seed 11，旧的 `20261017-sdram-refresh` 发布 bit 未被覆盖。新 bit 尚未替用户烧录，仍需完成双屏和断电启动验收。


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
## 2026-10-21 HDMI-B屏幕二级页 / 六卡菜单（实施中，勿烧录临时产物）

- 已实现CONTROL两行三列，新增屏幕卡片；HDMI-A仅作菜单，亮度/对比度/色温参数接HDMI-B图片色彩流水线，波形/OSD/应急覆盖保持自身颜色。
- KEY4选择/确认；编辑时KEY2减、KEY3增；KEY2长按逐级取消编辑、返回主菜单、退出菜单恢复切图。共享toggle/ACK提交，帧边界应用，预览和在途正文分离。原SW2-4不再覆盖菜单色彩设置。
- 根据用户追加建议，所有页面黄色圆点向左内缩16逻辑像素（当前720p放大区约24输出像素）；点大小不变。最终PNG已人工查看。
- 定向控制、邮箱、真实顶层色彩243组合/62208样本、像素UI、双屏相位测试通过。恢复默认提示仅在编辑该项时变RESET；已补固定坐标切换光标测试，避免嵌套函数敏感列表遗漏。原19字字模304行保持不变。
- 最新完整回归正在执行，64/73通过，resize_display720耗时681.5秒且通过；下一项为真实720p连续显示，尚不能把当前results.json当完整通过。
- 最终源码构建进行中：build/720p/td/20261021-screen-menu-delivery/。此前screen-menu和screen-menu-final均为中间版本，不应发给用户烧录。
- 终版完成后需重新check_reports.py/check_resize_timing.py和build/720p/screen-menu-work/check_menu_timing.py，再跑全量--reuse核对最终源码。
- 归档脚本已保存：build/720p/screen-menu-work/publish_screen.py，须在73/73完整回归后执行，并以最终物理报告更新其资源/时序数值。预期发布目录build/720p/releases/20261021-hdmib-screen-menu/。
- 本轮输入备份：build/720p/screen-menu-work/before-screen-menu.zip；旧中文修复版20261021-cjk-ui-clean bit SHA256仍为5b1ab1bd3039d58d21a2972de714f2e105b7078f56655940beb53847d4d16bbe，保持不变。未烧录、未做本轮板验。
- 按键说明已保存docs/HDMIB_SCREEN_MENU_20261021.md；任务prd/design/implement在.trellis/tasks/10-21-hdmib-screen-menu/。保留历史dirty/untracked，不自动Git提交。

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
