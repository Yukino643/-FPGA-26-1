# C方向全幅菜单：实施与验证说明

> 此文记录先前纯RTL阶段。2026-10-24用户追加授权后，完整综合/P&R/bitgen及88/88回归已通过，
> 当前物理结果与新bit以[后续发布验收](PHYSICAL_RELEASE_20261024.md)为准；下文“未综合/Git”为历史阶段边界。

本轮依据 `../ui-review-20261023/proposal/IMPL_PROMPT_MENU_16x9.md` 实施六项修改。
改前依据为本轮备份，不以当前 Git diff 中的历史未提交文件冒充本轮变更。
验证统计以同目录最终 `REGRESSION_STATUS.json`、`REGRESSION_RESULTS.json` 与各证据清单为准。

最终源码验证于2026-10-24完成，任务目录沿用方案日期2026-10-23。

| 最终结果 | 实测 |
|---|---|
| 完整纯仿真回归 | **86/86通过**，`complete=true`、`filter=null`、`sim_only=true` |
| 字幕全周期 | **18/18通过**；71200590次像素核对、29255次VS（含额外复位/边界用例） |
| 明暗照片OSD | **16/16通过**，合计14745600像素 |
| 连续字幕细条 | **64/64帧通过**，5242880像素 |
| 菜单图集 | 13张1280×720 RTL栅格图 |
| 修改边界核对 | 改前215文件中14文件属于本轮修改，201文件哈希不变；另新增3个验证源文件 |
| 最终交付回读 | 819张整圈关键帧、64张连续帧；936个图像文件解码通过，215个基线输入在仿真后无漂移 |
| 物理验收 | 用户禁止本轮综合/P&R，资源与时序未测，不计入上述纯仿真通过数 |

## 1. 问题诊断与处理

| 原问题 | 本轮处理 | 实现边界 |
|---|---|---|
| 640×480居中菜单占不满720p，1.5×笔画复制不均 | 640×360整数2×全幅 | 不改输出720p时序、PLL、视频时钟、SDRAM带宽 |
| 数值在卡内左对齐且带星号 | 10格前导空格右对齐，取消星号 | 保持参数值、确认/取消、按键与页序 |
| 主屏存在16/32px两套边距 | 字幕、标签、时间改为16px框架 | 标题板/模式板、单次压暗及优先级保持 |
| 状态实底块较重 | 状态纯字，WAIT复用原底线变色 | 不增加动画、忙态延时或冻结 |
| 32格环形字幕可在左右两端分段 | 64格+有限位置周期 | 字模仍50字；不增加中文字库bank |
| ASCII字重与中文不一致 | 统一Consolas Bold，仍8×16/1bpp | 不拆分两套字库，未新增字号 |

## 2. 逐条旧值→新值

所有区间均左闭右开。菜单为640×360逻辑坐标；主屏为原生1280×720坐标。
部分规格中“旧值”早于本轮备份，因此下面优先记本轮实际旧源码；新值严格按权威规格。

### 2.1 `rtl/top/top_tf_hdmi_audio.v`

| 信号/结构 | 旧值 | 新值 |
|---|---|---|
| `mon_de_view` | `mon_de && x>=160 && x<1120` | `mon_de` |
| `mon_x_rel/mon_x_num/mon_y_num` | 去居中偏移、乘2中间量 | 删除三条中间信号 |
| `mon_x_logical` | 乘2后除3 | `[9:0] mon_x_full[10:1]` |
| `mon_y_logical` | 乘2后除3 | `[8:0] mon_y_full[9:1]` |
| 菜单坐标寄存器 | 已为10/9位 | 保持10/9位，与renderer一致 |
| 输出流水 | 3拍 | 保持3拍，RGB/DE/HS/VS相位不变 |

### 2.2 `rtl/video/monitor_menu_renderer.v`

| 元素/表达式 | 旧值 | 新值 |
|---|---|---|
| 逻辑画布 | 640×480 | 640×360 |
| 页眉/底线 | `y<64` / `[62,64)` | `y<48` / `[46,48)` |
| 页名区域 | x32起，y[16,48) | x[24,264)、y[8,40) |
| `header_pos` / 行 | `x[7:4]-2` / `(y-16)>>1` | `(x-24)>>4` / `(y-8)>>1` |
| 状态区域 | x[512,592)、y[16,48) | x[536,616)、y[8,40) |
| `status_pos` | `x[6:4]` | `(x-536)>>4` |
| 卡片两行起点/高度 | 88、272 / 160 | 64、204 / 124 |
| `program_top`行分界 | y<260 | y<196 |
| 卡片y命中 | [88,248)、[272,432) | [64,188)、[204,328) |
| 卡标题与箭头local y | [16,48) | [12,44) |
| 中文字模行 | `local_y[4:0]-16` | `local_y[4:0]-12` |
| 数值窗口local x | 两种卡均[16,176) | 窄卡[8,168)、宽卡[96,256) |
| 数值local y/行 | [104,136) / `(local_y-104)>>1` | [78,110) / `(local_y-78)>>1` |
| 数值列 | 卡左侧起算 | 各窗口起点相减后右移4位 |
| 字符选择 | 逐卡8bit字符再选卡 | 保持此结构，不引入先选80bit整行的长路径 |
| 所有值字面量 | `ON        `、`100%      `等 | `        ON`、`      100%`等，均10字符 |
| 动态值 | 数字后补空格 | 音量、CNT高字节、LED编码均前补空格 |
| `pending_label` | 插入`*` | 删除函数及调用；保留值/边框琥珀语义 |
| 薄/厚框local y底部 | `>=158` / `>=156` | `>=122` / `>=120`；框厚2/4逻辑像素 |
| 卡宽/列位 | 窄184宽x24/228/432，宽272宽x32/336 | 不变 |
| 入口箭头local x | 窄[148,164)、宽[236,252) | 不变，仍只在既有可操作聚焦卡显示 |
| 音量条 | local x[16,216)、y[72,84)，16px段/4px间隔 | local x[16,252)、y[56,66)，20px段/4px间隔 |
| 播放提示 | x[32,288)、y[456,472) | x[24,280)、y[336,352)；单行8×16 |
| 状态背景 | CHIP/WAIT实底 | 直接HEADER，删除CHIP与WAIT_FG，DIS保留 |
| `status_fg` | READY/EDIT/WAIT旧色逻辑 | READY=MUTED，EDIT/WAIT=AMBER |
| `header_rule_color` | 整条RULE | WAIT且x[536,616)为AMBER，其余RULE |

未新增按键、页面或外设功能；外设CNT/LED仍为原有编码口径，不改成未经接线确认的新硬件能力。

### 2.3 `rtl/video/osd_engine_720.v`

| 区域/信号 | 旧值 | 新值 |
|---|---|---|
| 字幕板x | [32,1248) | [16,1264) |
| 标签板x | [32,128) | [16,112) |
| 标签字x/切字边界 | [48,112) / 80 | [32,96) / 64 |
| 标签`cell_x` | 低5位减16 | 直接低5位 |
| 正文x | [144,clock?832:1168) | [128,clock?864:1152) |
| 时间板x | [848,1248) | [880,1264) |
| 时间字x | [864,1216) | [896,1248) |
| `clock_col` | x[10:5]-27 | x[10:5]-28 |
| `CLOCK_FG` | C8F75A | C9DBE5 |
| 字幕周期/源坐标 | 32格/1024px、10位 | 64格/2048px、11位 |
| 位置寄存器 | 旧自由回绕origin | `scroll_position[10:0]`，从0开始 |
| `scroll_base` | 旧复位origin880 | clock开1184、关896 |
| `scroll_limit` | 1024自然回绕 | clock开1248、关1536 |
| 源坐标/文本列 | 10位加法、5位列 | 11位`x+origin`自然截断，列src[10:5]、单元内src[4:0] |
| 推进规则 | 原速度自然回绕 | 旧p>=limit时归0，否则慢/常/快0.5/1/2px每VS |
| 复位条件 | 关闭/5位配置变化 | 加入时间开关变化；同时清慢速相位 |

保持标题板x[16,496)、模式板x[1104,1264)、y[16,64)；底部板y[664,712)、文字y[672,704)；
保持顶线y[664,666)/38BDF8、标签底0E3A4C、各底板并集对原背景只右移2位一次。
像素链未新增除法、乘法、帧缓存或多层混合；origin/base加法属于位置变换，宽度限定11位。

### 2.4 字库与生成器

| 文件 | 旧值 | 新值/检查 |
|---|---|---|
| `scripts/gen_font.py` | consola.ttf | consolab.ttf；hex显式ASCII编码、LF |
| `rtl/ctrl/font_ascii_bram.hex` | 细体初始化 | 粗体初始化；2048×8不变 |
| `rtl/ctrl/font_rom_ascii.v` | 同步2048×8 ROM封装 | 重新生成后字节一致，因此不产生源码差异 |
| `sim/font_ascii.hex` | 细体仿真字形 | 与粗体生成器同步 |
| `scripts/gen_font_720.py` | 每句32格、col5位 | 每句64格、col6位；正文后全空白 |
| `rtl/video/subtitle_text_720.v` | 3×32文本索引 | 3×64文本索引；不是新增字模ROM |
| 菜单中文生成器/ROM | 40字，主bank1024×32+扩展128×32 | 未改，哈希保护 |
| 主屏字库 | 50实际单元、64分配、2048×32 | 未改，哈希保护 |

## 3. 验证方法与图集

| 检查 | 判据/证据 |
|---|---|
| 字库生成 | `gen_monitor_cjk.py --check`、`gen_font_720.py --check`；ASCII隔离重生成逐字节一致 |
| 菜单像素 | 13个场景独立几何/字形/颜色参考，包含原要求10场景与3个音频场景 |
| 全幅真实顶层连接 | 921600有效像素、2×2逐像素重复、边缘1440、聚焦8/普通4物理像素、3拍相位 |
| 控制回归 | 六页导航、二级编辑、确认/取消、长短按抑制、播放及应急语义回归 |
| 主屏组合 | 标题/时间/字幕8种组合×黑/白/彩色底，完整文字带逐像素检查 |
| 照片输入 | 明/暗各8组合，16×921600像素独立核对；波形关闭，不等价于完整TF/SDRAM仿真 |
| 字幕整圈 | 三句×三速×两窗口18圈，每个VS记录位置/裁剪，末尾64px空白、归零无正文跳变 |
| 字幕关键帧 | 每32px和首尾抓真实RTL1280×64细条，附逐像素核对；GIF按关键帧保持，不冒充60fps原始帧 |
| 连续字幕段 | 64个连续VS帧，位置512..638、步长2；实际RTL5242880像素独立核对 |
| 保护范围 | 与本轮改前215文件SHA清单比较；控制器、中文、约束、TD/bit保持 |

- 菜单：`images/menu/`；总览：`images/menu_contact_sheet.png`。
- 主屏：`images/main/*_OSD_RTL.png`；总览：`images/main_contact_sheet.png`；逐图来源见其`verification.json`。
- ASCII细节：`images/ascii_bold_4x.png`，实际1bpp字模放大；已查看页眉与M/W/%，无不可辨粘连，保留统一粗体。
- 字幕：`images/scroll/`中的18组关键帧/GIF、`all_vs_trace.csv`、`verification.json`。
- 连续帧：`images/scroll/segment/frame_*.png`、`segment_rtl.apng`、`segment_rtl.gif`、`verification.json`；GIF仅供预览，VS计数为速度证据。
- 回归日志：`logs/`；完整机器结果：`REGRESSION_STATUS.json`与`REGRESSION_RESULTS.json`。
- 精确源码差异：`diffs/`，以本轮改前ZIP为基准。
- 最终机器核验：`FINAL_VERIFICATION.json`；输入与保护范围：`SOURCE_AUDIT.json`。

全部菜单图是RTL栅格整数放大，照片主屏图是照片输入OSD RTL；两者均不是板拍，也不是提案HTML截图。
菜单测试对通用区域、ASCII字形、首个“图”字与边框作独立RGB比对；其余中文标题以固定坐标字索引断言、未改ROM哈希及图集人工检查交叉验证，不把这些标题说成每字都有第二份独立位图参考。

## 4. 资源与时序边界

| 项目 | 已板验旧基线 | 本轮结果 |
|---|---|---|
| LUT | 14839 | **未综合，未知；增量不得估算成实测值** |
| BRAM9K | 57 | **未综合，实际占用未测；声明bank深度、数量保持** |
| BRAM32K / DSP / PLL | 4 / 15 / 3 | 未改相关模块；实际后续构建核对 |
| video setup / hold | +0.680 / +0.021ns | **未P&R，未测** |
| 旧SDRAM全局setup | −6.565ns | 历史跨域问题单列，不表示本轮全工程闭合 |

本轮允许做Verilog-2005编译/展开、仿真与生成物核对；这些不能证明TD的资源映射或物理时序。
后续构建必须满足BRAM9K≤57、BRAM32K≤4、DSP≤15、PLL≤3；video setup≥+0.15ns，
SD/ext_mem/HDMI5x域内setup/hold非负，并记录LUT相对14839的真实增量。

## 5. 复现命令

在PowerShell7、UTF-8无BOM环境运行；此处只列允许本轮执行的验证命令。

```powershell
Set-Location -LiteralPath 'D:\FPGA\code\example'
& 'D:\miniconda3\python.exe' -B scripts/gen_monitor_cjk.py --check
& 'D:\miniconda3\python.exe' -B scripts/gen_font_720.py --check
& 'D:\miniconda3\python.exe' -B scripts/regression_native.py --sim-only --reuse --jobs 4
& 'D:\miniconda3\python.exe' -B scripts/render_main_ui.py --output docs/menu-16x9-20261023/images/main
& 'D:\miniconda3\python.exe' -B scripts/capture_subtitle_segment.py --output docs/menu-16x9-20261023/images/scroll/segment
& 'D:\miniconda3\python.exe' -B scripts/export_menu_16x9_evidence.py --output docs/menu-16x9-20261023
```

任何命令失败都不能标记相应证据完成；中断后不得沿用旧PASS或部分RGB数据冒充整圈。
没有运行综合/P&R/bitgen、没有烧录、没有提交或推送Git；稳定bit保留在原发布目录，本轮不产生新bit。
