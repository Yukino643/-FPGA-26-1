# 菜单 P0 改动清单与交接

依据：[UI_DESIGN_PROPOSAL.md](../proposal/UI_DESIGN_PROPOSAL.md) §8 前置上下文及 8.1–8.5。
当前已完成菜单RTL、最终75项回归及完整TD构建，准备交付板验；8.6/8.7 HDMI-B改造未实施。下文早期RTL交付记录保留为历史，当前结论以本节为准。

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


## 2026-10-22 复审修订

| 用户指出的问题 | 核对与修复 |
|---|---|
| 播放页提示贴卡片底边及屏幕底部 | 确认存在。两行合成一行，x[32,288)、y[456,472)，8×16字号不变；上下各8逻辑像素留白，映射后各12输出像素；不改卡片网格 |
| 页眉EDIT使用全局cfg_dirty | 确认存在。改成当前聚焦卡pending或二级edit，busy仍优先显示WAIT；页眉与卡片pending均从同一拍输入计算，避免直接读取旧state_pending造成光标切换错拍 |
| 亮度0档单字观感 | 保留原方案的`0`，不引入零档正号；其他档位格式不变 |

新增四页状态转换RGB检查：保留全局dirty、移到无变化卡、移回待确认卡、切二级页、二级页聚焦待确认/已生效卡、显式编辑及WAIT优先。
播放页整帧独立参考更新为单行字模；导图脚本额外检查上下8px留白和横向文字窗口。
本次修改前另备份 `build/720p/backups/20261022-before-menu-followup/before-menu-followup.zip`，ZIP与字节回读通过。
修订后9项定向回归通过（变化的菜单渲染与顶层相位重新仿真，其余按有效依赖哈希复用）；
最终源码依赖复核一致，10场景及48卡独立检查通过。已查看修订后播放页720p预览，上下安全边明确。

## 逐项改动

| 方案 | 本轮实现 | 文件 |
|---|---|---|
| 8.1 色板 | 全套规定色值；青色焦点、薄荷 ON、珊瑚 OFF、琥珀编辑/待确认；删除旧圆点和底部色带 | `rtl/video/monitor_menu_renderer.v` |
| 8.2 状态 | 逐卡比较 shadow/active，selected/editing/pending/action、值文本及色类别提前寄存；只让实际待确认的非聚焦卡显示琥珀细框；值后留一格再显示 `*`；仅有 KEY4 动作的聚焦卡显示 `>` | 同上 |
| 8.3 页眉 | 64 高深色页眉、2 高分隔线、灰色页名；四个菜单页统一 READY/EDIT/WAIT 状态块，WAIT 用琥珀实心底和深色字；播放页无状态块 | 同上 |
| 8.4 网格 | 主菜单 184×160，x=24/228/432，y=96/288；四卡页 272×160，x=32/336；同步调整命中区；标题 y=16，值 y=104；内缘边框常规 2、聚焦 4 逻辑像素 | 同上 |
| 8.4 底部（10月22日复审修订） | 菜单底部纯 BG；播放页改为单行 8×16，x=32、y=456..472，上下各留 8 逻辑像素，文案 `K2 NEXT K3 AUTO HOLD K3 MENU` | 同上 |
| 8.5 文案 | ON/OFF，1S/2S/5S/10S，HDMI-B；内容 1/3–3/3，SLOW/NORM/FAST；亮度不补零，对比度不加前导零，COOL/NORM/WARM，RESET/CONFIRM；外设 READY/WAIT、IDLE/TEST、CNTxx、LEDx；非法档位 ERR 珊瑚色 | 同上 |
| 像素验证 | 独立坐标/色值/ASCII ROM 参考，逐像素检查值、星号、箭头、边框、页眉与底部；中文字索引检查及“图”字独立位图参考；固定坐标只切状态，检查预计算状态更新 | `sim/tb_monitor_menu_renderer.v` |
| 输出验证 | 真实顶层时序/缩放代码提取；检查 RGB/DE/HS/VS 三拍相位及左右黑边；物理边框四面 3/6 像素检查 | `sim/tb_monitor_pipeline.v` |
| 检查与导图 | 拒绝未完成/失败回归；检查保护输入 SHA256、ROM 容量、旧圆点残留；逐卡检查全部逻辑边框和物理四侧宽度；将实际 RTL 栅格映射为 720p PNG | `scripts/check_menu_p0.py` |

## 保持的交互与边界

- 640×480 逻辑画布按原先 1.5 倍映射为 960×720，置于 1280×720 中间，左右各 160 黑边；不增加像素流水级。
- 控制器、提交邮箱及顶层文件保持本轮开始时的字节。KEY2/KEY3 导航或减增、KEY4 编辑/确认、KEY2 长按返回、KEY3 长按切页、KEY4 长按应急均沿用原实现。
- 页眉 EDIT 跟随当前聚焦卡的 pending，或二级页现有 edit 标志；cfg_busy 时 WAIT 优先。10月22日复审移除了全局 cfg_dirty 对页眉的影响，同拍计算聚焦卡 pending，避免上一拍状态配新光标。本轮没有增加 WAIT 保持、提交闪光、busy 冻结或新的操作行为。
- 恢复默认是动作，不是第四个参数。编辑该卡显示 CONFIRM，参数差异在亮度/对比度/色温卡上分别标记。
- 外设页只给蜂鸣器卡显示动作箭头，其余三卡只读。CNTxx 沿用既有事件计数高字节显示口径，不改变计数功能。
- 无新增禁用输入或禁用规则，屏幕页提供待确认场景，不虚构“置灰”功能。DIS 色值按方案保留，目前没有对应硬件禁用状态。
- 菜单中文仍 36 字形，基础 ROM 1024×32、扩展 ROM 128×32；ASCII ROM、主屏字体及生成脚本未改。本轮没有新增字库 bank 或帧缓存。
- HDMI-B 文件相对本轮开始不变，包括此前尚未提交的标题/运行时间配色。不能将 Git HEAD 差异误认为本轮修改。

## 验证与证据边界

实际结果以本目录 `regression_status.json`、`regression_results.json`、`verification.json` 及日志为准。

本轮定向回归 **9/9 PASS**（complete=true），10 个菜单场景 RGB 检查通过。
独立脚本完成 48 个卡片实例的全部逻辑边框检查，以及物理左/右/上/下 3/6 像素宽度检查。
真实顶层检查921605个像素样本，输出延迟仍为3拍；屏幕参数回归检查62208个样本。
14 个保护输入 SHA256 全部与修改前相同。菜单/主屏字库 `--check` 和差异空白检查均通过。
已人工查看主菜单、字幕编辑、屏幕待确认、外设、WAIT及播放页RTL预览，并与方案主菜单效果图比对；
测试主菜单字幕为ON，方案示意图为OFF，仅输入状态不同，布局及配色一致。

| §8.8 条目 | 本轮处理 |
|---|---|
| 1 菜单字库 | 运行 `gen_monitor_cjk.py --check`，不生成新字库 |
| 2 主屏字库 | 仅运行 `gen_font_720.py --check`，校验现存 2048 行；不执行属于 8.7 的重新生成 |
| 3 定向回归 | 运行菜单渲染/控制/配置、真实菜单流水、屏幕参数、HDMI-B 两种字幕流水、字幕与应急共 9 项 |
| 4 边框 | 顶层 720p 仿真加独立脚本，核对常规 3 / 聚焦 6 输出像素，四侧等宽 |
| 5 资源和物理时序 | 早期RTL阶段未构建；10月22日完整TD已通过，BRAM9K57、LUT+147、视频setup+0.184ns |
| 6 HDMI-B 新布局组合 | 8.6/8.7 不在本轮范围；只回归现有主屏路径、核对禁止修改文件的 SHA256 |
| 7 新 bit | 10月22日已生成当前源码新bit；发布目录20261022-menu-ui-p0，旧发布bit不用于验证P0 |
| 8 图像与清单 | 本文件及 10 张实际 RTL 菜单图；另附明确命名为 UNCHANGED_REFERENCE 的旧主屏参考 |

所有菜单 PNG 均由本轮 RTL 仿真的 640×480 PPM 按真实最近邻映射生成，**不是板拍**。
`hdmi_b_subtitle_on_UNCHANGED_REFERENCE.png` 仅复制评审报告原有的软件合成参考，**不是本轮 HDMI-B 仿真或实物验收**。

| 预览 | 文件 |
|---|---|
| 主菜单 | [menu_program_720.png](menu_program_720.png) |
| 字幕编辑（聚焦/非聚焦待确认） | [menu_subtitle_edit_720.png](menu_subtitle_edit_720.png) |
| 屏幕待确认 | [menu_screen_pending_720.png](menu_screen_pending_720.png) |
| 外设 | [menu_peripheral_720.png](menu_peripheral_720.png) |
| WAIT | [menu_wait_720.png](menu_wait_720.png) |
| 播放提示 | [menu_playback_720.png](menu_playback_720.png) |
| 未改变的主屏参考 | [hdmi_b_subtitle_on_UNCHANGED_REFERENCE.png](hdmi_b_subtitle_on_UNCHANGED_REFERENCE.png) |

## 用户确认后，在本机执行的命令

以下是早期RTL交接时提供的复现命令；10月22日已实际执行完整回归与TD构建，最终日志目录为 `build/720p/td/20261022-menu-ui-p0-final`。在 `pwsh -NoLogo -NoProfile` 中运行；任一步非零退出即停止。
完整回归会对未变依赖复用其有效结果，变化的依赖自动重跑；TD 构建较长，会定期输出进度。

```powershell
if ($PSVersionTable.PSVersion.Major -lt 7) { throw '需要 PowerShell 7' }
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Set-Location -LiteralPath 'D:\FPGA\code\example'

& 'D:\miniconda3\python.exe' scripts/regression_native.py --sim-only --reuse
if ($LASTEXITCODE -ne 0) { throw '完整仿真失败，停止构建' }

& 'D:\miniconda3\python.exe' td_prj/build_native.py --output build/720p/td/20261021-menu-ui-p0
if ($LASTEXITCODE -ne 0) { throw '完整 TD 构建失败' }

& 'D:\miniconda3\python.exe' scripts/check_reports.py
if ($LASTEXITCODE -ne 0) { throw '源码、bit、资源或基础时序检查失败' }
& 'D:\miniconda3\python.exe' scripts/check_resize_timing.py
if ($LASTEXITCODE -ne 0) { throw '缩放路径时序检查失败' }
& 'D:\miniconda3\python.exe' scripts/check_subtitle_timing.py
if ($LASTEXITCODE -ne 0) { throw '菜单、字体或字幕路径时序检查失败' }

Get-FileHash -LiteralPath 'td_prj/av_media_Runs/phy_1/av_media.bit' -Algorithm SHA256
```

`build_native.py --output` 指定日志和清单目录；新 bit 实际位于 `td_prj/av_media_Runs/phy_1/av_media.bit`。
上述检查通过后仍须额外核对本方案更严格的门限：视频 setup≥0.15ns、BRAM9K≤57/64，并记录相对原 14875 LUT 的增量。
`check_reports.py` 的视频 setup 基础门限为非负，不能用其 PASS 替代 0.15ns 的要求。
若 setup 不足，方案规定先回退聚焦框至 2 逻辑像素后重测，不放宽门限。

## 备份、风险与停止点

修改前源码快照：`build/720p/backups/20261021-before-menu-p0/source-before-menu-p0.zip`；
保护输入清单：同目录 `protected-inputs.json`。历史 dirty/untracked 与 TD 工程入口差异保留。

| 风险/审查项 | 结论或后续工作 |
|---|---|
| 时序/资源 | 参数档位与状态在寄存器前计算，像素侧只选行/字和常量边界；实际 LUT/寄存器映射、BRAM推断及余量以新 P&R 为准 |
| 跨域/并发 | 无新增时钟域或配置跨域总线；原 toggle/ACK 与帧边界提交保持，现有回归验证其行为 |
| 寄存器/启动/中断/RTOS | 无 MMIO、CPU 中断、启动向量或 RTOS 改动；本轮对象为 FPGA 视觉渲染 |
| 边界/可移植性 | 非法参数显示 ERR；Verilog-2005 编译；脚本检查实际栅格、ROM尺寸与受保护文件哈希 |
| 实物显示 | 新bit已生成，尚未板验；需核对七寸屏可读性、长时间双屏运行及应急 |

**停止于P0菜单新bit交付，等待用户板验；不继续8.6/8.7，不提交或推送Git。早期不运行TD的停止点已由10月22日用户构建授权覆盖。**
