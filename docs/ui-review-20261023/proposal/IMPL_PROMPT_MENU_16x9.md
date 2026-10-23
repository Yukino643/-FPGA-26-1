# 实施提示词：炬屏菜单 16:9 全幅重排（C 方向）

> 直接交给工程智能体。五条决策已由用户于 2026-10-23 全部确认：A 640×360@2×、B 时间改 #C9DBE5、
> C 字幕循环 64 格、D 菜单 ASCII 换粗体、E 外设页保持现状。本文件是唯一实施依据，
> 设计意图与理由见 `UI_AESTHETIC_REVIEW.md`。

---

## 0. 前置上下文

```text
工作目录：D:\FPGA\code\example（真实 FPGA 工程，Trellis 管理；先读 .trellis/workflow.md 与 .trellis/spec）
参考：docs/ui-review-20261023/CURRENT_UI_REVIEW.md（现状口径）
      docs/ui-review-20261023/proposal/UI_AESTHETIC_REVIEW.md（坐标表、状态表、验收）
      docs/ui-review-20261023/proposal/images/proposal_c_*.png（提案示意，HTML 近似，非 RTL）
      提案源：docs/ui-review-20261023/proposal/explore/c-full.html（?state=program|audio|subtitle|screen|peripheral|playback，-editN/-pendingN/-wait）
先读再改：rtl/top/top_tf_hdmi_audio.v、rtl/video/monitor_menu_renderer.v、rtl/video/osd_engine_720.v、
          scripts/gen_font_720.py、scripts/gen_font.py、scripts/gen_monitor_cjk.py、
          sim/tb_monitor_menu_renderer.v、sim/tb_monitor_pipeline.v、sim/tb_subtitle720.v
本轮范围：下列 6 项变更全部完成；改完输出改动清单与截图，停下等我构建，不自行综合/烧录/Git。
证据边界：提案图是 HTML 近似（系统字体、抗锯齿），不是 RTL，也不是板拍；不得写成已上板验证。
未定义细节：停下来问我，不要自行发挥。
```

硬约束（违反即回退）：

1. 菜单逻辑画布 640×360，2× 整数映射到 1280×720；HDMI-B 仍原生 1280×720。两套坐标不得混用。
2. 菜单中文字库已满（36 ROM + 音/频/量/静 4 个逻辑字形 = 40 字）。**不得新增任何菜单中文**。
3. BRAM9K ≤ 57、BRAM32K ≤ 4、DSP ≤ 15、PLL ≤ 3；video setup ≥ +0.15ns；SD/ext_mem/HDMI5x 域内 setup/hold ≥ 0；旧 SDRAM 全局 −6.565ns 单列。
4. 按键语义（KEY2 上一项/减小、KEY3 下一项/增大、KEY4 编辑/确认、KEY2 长按返回、KEY3 长按切页、KEY4 长按 2s 应急）、页序（节目/音频/字幕/屏幕/外设/播放）一律不变。
5. 像素路径不得新增除法、宽乘法、多层混合；状态与字面量先在寄存器里算好。

---

## 1. 变更 1：画布 640×480 → 640×360，1.5× → 2× 整数（最大项）

### 1.1 `rtl/top/top_tf_hdmi_audio.v`（替换菜单映射，删除 /3 除法）

| 现在 | 改成 |
|---|---|
| `wire mon_de_view = mon_de && (mon_x_full >= 160) && (mon_x_full < 1120);` | `wire mon_de_view = mon_de;` |
| `wire [10:0] mon_x_rel = (mon_x_full >= 160) ? (mon_x_full - 160) : 0;` | 删除 |
| `wire [11:0] mon_x_num = {1'b0, mon_x_rel} << 1;` | 删除 |
| `wire [10:0] mon_x_logical = (mon_x_num / 12'd3);` | `wire [9:0] mon_x_logical = mon_x_full[10:1];` |
| `wire [10:0] mon_y_num = {1'b0, mon_y_full} << 1;` | 删除 |
| `wire [10:0] mon_y_logical = (mon_y_num / 11'd3);` | `wire [8:0] mon_y_logical = mon_y_full[9:1];` |

寄存器 `mon_x / mon_y` 位宽可缩为 `[9:0] / [8:0]`；`monitor_menu_renderer` 的 `x/y` 端口位宽相应改为 `[9:0] / [8:0]`。
两个 `/3` 除法器整段消失，时序应更宽松——但**仍要按 §7 验收**。

### 1.2 `rtl/video/monitor_menu_renderer.v` 几何常量（旧 → 新）

| 元素 | 旧 | 新 |
|---|---|---|
| 页眉底 | y < 64 | y < 48 |
| 页眉底线 | y ∈ [62,64) | y ∈ [46,48) |
| 页名 | x 32 起，y [16,48)，命中 x [32,288) | x 24 起，y [8,40)，命中 x [24,264) |
| 页名取列 | `header_pos = x[7:4] - 4'd2` | `header_pos = (x - 10'd24) >> 4`（24 不是 16 的倍数，用减法） |
| 页名取行 | `req_row = (y - 16) >> 1` | `(y - 8) >> 1` |
| 状态字 | x [512,592)，y [16,48) | x [536,616)，y [8,40) |
| 状态取列 | `status_pos = x[6:4]`，`status_rev = 4 - status_pos` | `status_pos = (x - 10'd536) >> 4`，`status_rev = 4 - status_pos` |
| 卡行 1/2 | y 88 / 272 | y 64 / 204 |
| 行分界 | `program_top = y < 260` | `program_top = y < 9'd196` |
| 卡片命中 y | [88,248) / [272,432) | [64,188) / [204,328) |
| 卡标题 | local y [16,48)；行 = local_y[4:0]-16 | local y [12,44)；行 = local_y[4:0]-12 |
| 卡数值 | local x [16,176)，y [72,104)；`value_pos = local_x[7:4]-1`；行 `(local_y-72)>>1` | local x [8,168)，y [78,110)；`value_pos = (local_x - 10'd8) >> 4`；行 `(local_y - 9'd78) >> 1` |
| 入口箭头 | local x [148,164)/[236,252)，y [16,48) | local x 同，y [12,44) |
| 边框厚度 | 2 / 4（内缘） | 不变；底部判定 `local_y >= 157` → `>= 122`，粗框 `>= 156` → `>= 120` |
| 播放提示 | x [32,288)，y [456,472)，行 `y-456` | x [24,280)，y [336,352)，行 `y-336` |
| 卡宽/列位 | 184 宽，x 24/228/432；272 宽，x 32/336 | **不变** |

数值右对齐：见变更 2；`*` 星号逻辑删除，见变更 2。

### 1.3 验收（变更 1）

- 720p 输出中左右**没有黑列**；任一逻辑像素对应 2×2 物理像素。
- 常规边框恒 4 物理像素、聚焦恒 8，四面等宽。
- 六卡 y = 64/204、高 124，行距 16；四卡 x = 32/336，宽 272。
- `tb_monitor_menu_renderer.v` 的 10 套整页参考按新几何重生成；`tb_monitor_pipeline.v` 的黑边断言删除、改为全幅相位断言。

---

## 2. 变更 2：数值右对齐 + 删除星号

1. **窗口右移**：值窗口改为 `[卡右−176, 卡右−16)`（逻辑），即 local x ∈ [8,168)（184 宽卡）/[96,256)（272 宽卡）。
   取列用 `(local_x − 8) >> 4`，取行 `(local_y − 78) >> 1`，`value_rev = 9 − value_pos` 不变。
2. **字面量右对齐**：所有 10 字符值改为"前导空格补到 10 格"，例如
   `"        ON"`、`"       OFF"`、`"        2S"`、`"    HDMI-B"`、`"      100%"`、`"       -64"`、
   `"         0"`、`"     RESET"`、`"   CONFIRM"`、`"     READY"`、`"       ERR"`。
   规则：右端对齐第 10 格，长度不足补前导空格，长度必须恒为 10。
   `card_value_label` / `subtitle` 与 `screen` 两组的 label 全部适用。
3. **删除星号**：`pending_label` 函数里 `pending` 参数与 `"*"` 写入整段删除（或恒传 0）。
   待确认的语义改由：值变 AMBER + 未聚焦时边框 AMBER —— 后一条现有 `border` 表达式已实现，无需改。
4. 验收：任取一页，所有值右端落在同一竖线（卡右−16）；`*` 不再出现；待确认卡边框为 2px 琥珀。

---

## 3. 变更 3：HDMI-B 四块板统一 16px 内框 + 时间改色

`rtl/video/osd_engine_720.v`：

| 常量/区域 | 旧 | 新 |
|---|---|---|
| 字幕条 | x [32,1248) | x [16,1264) |
| 标签块 | x [32,128) | x [16,112) |
| 标签文字 | x [48,112)，`cell_x = I_x[4:0]-16` | x [32,96)，`cell_x = I_x[4:0]`（起点 32 已 32 对齐） |
| 正文窗口 | x [144, (时钟开 ? 832 : 1168)) | x [128, (时钟开 ? 864 : 1152)) |
| 时间板 | x [848,1248) | x [880,1264) |
| 时间文字 | x [864,1216) | x [896,1248)，`clock_col = I_x[10:5] - 6'd28` |
| `SCROLL_ORIGIN` | `10'd880` | `10'd896`（时间关） |
| `CLOCK_FG` | `24'hC8F75A` | `24'hC9DBE5` |

其余不变：标题板 [16,496)、模式板 [1104,1264)、顶部/底部压暗 `>>2`、并集只压暗一次、顶线 [664,666) 2px #38BDF8、标签底 #0E3A4C。

验收：四块板左缘同为 16、右缘同为 1264；时间字与时间板左右各 16；8 种开关组合重出图；题目要求的"只压暗一次"用像素计数验证。

---

## 4. 变更 4：页眉状态去填充

`monitor_menu_renderer.v`：

1. `base` 不再有 `CHIP` 分支：状态区直接是 `HEADER`。
2. `status_fg`：READY → MUTED；EDIT → AMBER；WAIT → AMBER。
3. WAIT 额外把**页眉底线在 x∈[536,616) 的那一段**改为 AMBER（同一 2px 线换色，不额外画线）：
   `header_rule_color = (wait && x>=536 && x<616) ? AMBER : RULE`。
4. 删除 `WAIT_FG` 常量与 CHIP 填充（`DIS` 保留为未使用常量）。

验收：三个状态字位置完全不动（只在 x 536..616 内换字与换色）；WAIT 时底线右段变琥珀，无新增方块。

---

## 5. 变更 5：字幕循环 32 → 64 格

1. `scripts/gen_font_720.py`：`subtitle_text_720` 的每条正文从 32 格补到 **64 格**（0..63，14..63 全空白），
   模块端口 `input wire [5:0] col`。除此之外不改字集（仍 50 单元）。
2. `rtl/video/osd_engine_720.v`：
   - `subtitle_source_x` 改 11 位：`wire [10:0] src = I_x[10:0] + origin;`，`col = src[10:5]`，`cell_x = src[4:0]`。
   - 位置计数 `p`（11 位）替代自由回绕：
     - `base = clock_enable_i ? 11'd1184 : 11'd896`
     - `origin = (base + p) & 11'h7FF`
     - `p` 上限 `limit = clock_enable_i ? 11'd1248 : 11'd1536`（= W + 448 + 64；W=736 或 1024）
     - 每帧按现有速度累加 `p`（慢 1/2 帧、常 1/帧、快 2/帧），`p >= limit` 时归零。
   - 复位条件：字幕关闭、5 位字幕配置变化、**时间开关变化**（新增），均令 `p=0`。
3. 验收：三句 × 三档速度各跑完整一圈，任何时刻都不出现"句首在右端、句尾在左端"同时可见；
   每圈结尾有 64px 留白；归零瞬间画面无可察觉跳动（因为此时句子已完全离开窗口）。

---

## 6. 变更 6：菜单 ASCII 换粗体（有回退条件）

1. `scripts/gen_font.py`：字体路径由 `consola.ttf` 改 `consolab.ttf`，仍 8×16、1bpp，重新生成
   `rtl/ctrl/font_rom_ascii.v` 与 `font_ascii_bram.hex`（尺寸不变，BRAM 不增）。
2. 在 2× 输出下检查：页眉 15 个字母（PROGRAM CONTROL 等）与 5 状态字是否过粗糊字、`M/W/%` 是否粘连。
3. **回退**：若页眉过重，保留细体字库给页眉、值另用一份粗体——但这会多一个 2048×8 ROM（+2 BRAM9K，**不允许**）。
   因此回退只能二选一：(a) 全页统一粗体并接受页眉变粗；(b) 放弃本条，保持细体。
   由我根据你提供的 2× 截图决定，不要自行拆两套字库。

---

## 7. 验收（缺一不可）

| # | 项目 | 通过标准 |
|---|---|---|
| 1 | 菜单字库 | `python scripts/gen_monitor_cjk.py --check` 通过，仍 40 字 |
| 2 | 主屏字库 | `python scripts/gen_font_720.py` 重新生成后 `--check` 通过；`font_720.hex` 仍 64 单元 |
| 3 | ASCII 字库 | `scripts/gen_font.py` 生成物与仓库一致；ROM 尺寸 2048×8 不变 |
| 4 | 定向回归 | 菜单 6 页导航、二级页 4 卡、预览/确认/取消、长按返回/切页、播放页按键、应急长按全部与改前一致 |
| 5 | 像素 | 无黑列；2×2 = 1 逻辑像素；边框 4/8 物理；值右端同一条竖线 |
| 6 | 主屏 | 8 种标题/时间/字幕组合重出；四板 16/1264；时间字 16/16 内边距；时间色 #C9DBE5 |
| 7 | 滚动 | 3 句 × 3 速整圈，无两端分段，留白 64px |
| 8 | 资源/时序 | BRAM9K ≤ 57、BRAM32K ≤ 4、DSP ≤ 15、PLL ≤ 3；video ≥ +0.15ns；其余域 ≥ 0；记录 LUT 相对 14839 的增量 |
| 9 | 交付物 | 改动清单（旧值→新值逐条）、10 张菜单图、8 张主屏组合图、1 段滚动的逐帧抓图 |

## 8. 不做

不新增菜单中文、不新增字号、不改画布为其它比例、不做阴影/模糊/渐变、不做光标动画、
不改按键与页序、不新增诊断功能、不跑综合/烧录/Git。

---

## 9. 给用户的构建命令（改完后由我执行）

```powershell
Set-Location -LiteralPath 'D:\FPGA\code\example'
& 'D:\miniconda3\python.exe' scripts/regression_native.py --sim-only --reuse
& 'D:\miniconda3\python.exe' td_prj/build_native.py --output build/720p/td/20261023-menu-16x9
& 'D:\miniconda3\python.exe' scripts/check_reports.py
& 'D:\miniconda3\python.exe' scripts/check_resize_timing.py
& 'D:\miniconda3\python.exe' scripts/check_subtitle_timing.py
Get-FileHash -LiteralPath 'td_prj/av_media_Runs/phy_1/av_media.bit' -Algorithm SHA256
```

任一步非零退出即停止；`check_reports.py` 的基础门限是非负，**不能**替代 +0.15ns 的要求。
