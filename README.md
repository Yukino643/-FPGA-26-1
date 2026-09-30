# 基于 EG4S20 的 HDMI 多媒体播放系统（2026 安路赛道 · 选题一）

数字广告屏 + 应急信息发布终端：TF 卡素材 → 片内 SDRAM 伪双端口帧缓存 → 多图层 alpha 合成 → 双 HDMI 异显（主通道广告内容 / 副通道监视台），并提供 WAV/警笛音频、Goertzel 频谱和帧边界应急切换。

- 平台：HX4S20C 开发板（EG4S20BG256，TD 6.2.1）
- 实施计划：[docs/计划书-基于EG4S20的HDMI多媒体播放系统.md](docs/计划书-基于EG4S20的HDMI多媒体播放系统.md)
- 参考工程：`D:\FPGA\ref\lab_ex5_i2s`（官方赛题样例，自 `D:\FPGA\HX4S20_Contest_202606\7_lab_ex_2026_nosoft` 解压）

## 目录

```
rtl\        top/ sd/ mem/ video/ audio/ ctrl/ pll   （模块划分见计划书第 6 章）
constraints\   pin.adc / timing.sdc
scripts\       prepare_media.py（素材转换）/ gen_font.py（中文字库）
sim\           ModelSim 测试激励
media\         演示素材
td_prj\        TD 工程
docs\          计划书 / 设计说明书 / 测试报告
```

## 关键引脚速查（详见计划书 3.2）

| 信号 | 引脚 | 信号 | 引脚 |
|---|---|---|---|
| 50M 时钟 | R7 | HDMI_B TMDS | E1/F1/G5/C3 (LVDS33) + DDC P2/R2 |
| KEY1~4 | A2/B2/B1/C1（KEY1 为复位；KEY4 短按转场、长按应急） | HDMI_A TMDS | B3/E3/F5/K1 (LVDS33) + DDC P1/R1 |
| SW1~4 | C8/C7/C6/C5 | TF (SPI) | CS=A12 CLK=A14 MOSI=A13 MISO=B14 |
| 蜂鸣器 | H11 (低有效) | UART | RXD=F12 TXD=D12 |

## 工作流约定（已跑通）

**双入口，单一事实源**：所有 RTL/约束都在本仓库目录里，TD 工程 `td_prj/av_media.al` 以相对路径引用它们。GUI 和命令行打开的是同一个工程。

- **我（命令行）**：改代码 → 一键编译 `bash td_prj/build_all.sh` → 检查时序/资源报告 → 出 bit。
  - 工程创建/加文件脚本：`td_prj/create_project.tcl`、`td_prj/add_sources.tcl`（TCL shell 逐行解析，禁止多行块）
  - 编译机制：run 目录下 `settings.cfg` + 基于 TD 官方流程的 `flow_fixhold.tcl`（syn_1: elaborate→opt_rtl→opt_gate；phy_1: opt_place→opt_route→bitgen，自动导入 syn 的 gate.db）
  - 产物：`td_prj/av_media_Runs/phy_1/av_media.bit`
  - 注意：`wait_run` 在 run 完成后会死循环，勿用；`launch_runs` 的子进程活不过会话退出，因此用 DefaultFlow 直跑。
- **你（GUI）**：TD 打开 `td_prj/av_media.al` 看工程树/调 IP/在线调试（CWC），TD 里配置 VSCode 编辑器即可；bit 下载可用 GUI 的 Download，也可以等我接 `download` 命令。
- 当前构建（2026-10-01 TF-D2）：basic 26/26、full 27/27、独立报告 fails=0；bit 生成于 02:21:02，SHA256 `3301637cbafa98d79996854dc7dffe48bc71d1bfc64c18453a86072b70a13515`。LUT15997/19600（81.62%）、BRAM9K46/64（71.9%），SWNS=-6.565ns、HWNS=+0.022ns。TF-D1 板级照片已确认三图被找到、首图307200像素及源缓存写入完成；本轮修复缩放启动、目标页和重复任务地址，TF-D2 图片显示仍待下载实测。setup 仍有负余量；详见 [TF缩放修复](docs/TF缩放修复-20261001.md)。

## 回归门（每轮改动后必跑）

```bash
bash scripts/regression.sh          # 模块/通路仿真 + 生成物同步 + 报告门限（含慢速仿真）
bash scripts/regression.sh --full   # 上述 + 从当前源码重新全编译出 bit
```

检查项：①顶层端口与 `pin.adc` 完整性/LOCATION 冲突；②字库生成物；③模块、BMP 超时、全路径和真实顶层缩放连接仿真；④PNG 刷新；⑤bit 新鲜度、SWNS/HWNS、LUT≤85%、BRAM9K≤90%。当前完整回归为 27/27 PASS。任何一项失败脚本退出码非 0。门限配置在 `scripts/baseline.rpt`，报告解析在 `scripts/check_reports.py`。

## 状态

- [x] 资料研读（选题指南 / 板卡手册 / 原理图 / lab_ex4、lab_ex5 源码 / APUG092）
- [x] 计划书
- [x] W1 工程基建：lab_ex5 基线跑通（命令行编译出 bit，时序对齐官方）
- [ ] W1 硬件验证（等有板子：下载 bit + TF 卡图片轮播确认）
- [x] W2 双 HDMI（纯软件完成）：
  - `rtl/ctrl/font_rom_ascii.v` — ASCII 8×16 字库 ROM（`scripts/gen_font.py` 生成）
  - `rtl/video/video_timing_gen.v` — 参数化时序发生器（含 x/y 坐标）
  - `rtl/video/monitor_compositor.v` — 监视台渲染器 v1（UPTIME/FRAMES/AV-SYNC/MODE/图层色块/活动彩条）
  - 顶层接入第二路 HDMI1.4b 核 + PHY（HDMI_A: K1/B3/E3/F5 + DDC P1/R1）
  - **仿真验收**：`sim/tb_monitor.v`（iverilog）整帧渲染见 `sim/monitor_frame.png`
  - 编译：LUT 30.9%、BRAM 46.9%、DSP 0%，最终时序与基线签名一致
- [x] W3 存储层改造（纯软件完成）：
  - `rtl/mem/mem_map.vh` — SDRAM 地址映射：显示双缓冲钉在 bank0/bank1 起点（0x0_0000 / 0x8_0000），转场双流读零 bank 冲突
  - `rtl/mem/mem_mpu.v` — 读口双请求方仲裁器（A 显示优先 + 防饿死 + 簇间 10 拍静默对齐官方协议）；仿真 `sim/tb_mem_mpu.v` 全过（优先级/防饿死/无串扰）
  - `rtl/sd/bmp_read_g.v` — 泛化 BMP 解析器：任意宽高（≤2047）+ 行尾 padding 剥离 + 每图元数据（8 张）+ 严格头校验/像素完整性/超时错误码；修复官方遗留的跨扇区头采样不复位 bug；仿真 `sim/tb_bmp_read_g.v` 与 `sim/tb_bmp_read_g_timeout.v` 全过
  - `rtl/sd/sd_card_bmp_g.v` — 轮播 4 图 → 8 图，元数据透传（img_count/cur_img_w/h 给监视台）；坏图自动重试一次，失败后标记并跳过，保留当前显示
  - 编译：LUT 33.3%、BRAM 30/64、DSP 0，bit 已出，时序与基线一致
- [x] W4 合成管线（纯软件完成）：
  - `scripts/gen_font_cjk.py` + `scripts/osd_strings.txt` — 中文字库光栅化（黑体 16×16，85 字形，改文案重跑即可）
  - `rtl/video/font_rom_cjk.v` / `osd_text_rom.v` — 生成的字模 ROM 与文本窗 ROM
  - `rtl/video/blend_fn.vh` — 通用 alpha 混合函数 `(fg*a+bg*(255-a)+127)>>8`，各图层共用
  - `rtl/video/osd_engine.v` — 主通道 OSD：顶部半透明标题条（中文标题+模式文本）+ 底部信息条（BCD 实时时钟）
  - `rtl/video/pixel_pos_gen.v` — 既有视频路径上的 x/y 坐标派生（注意：消费方必须用它输出的 O_de，与 x/y 同拍）
  - 仿真验收 `sim/tb_osd.v` → `sim/osd_frame.png`（中文渲染/半透明混合/时钟均正确）
  - 编译：LUT 48.5%（字模 ROM 走了 LUT，若后续吃紧改同步读 BRAM 可省 ~2K LUT），时序签名不变
- [x] W5 转场引擎（纯软件完成）：
  - `rtl/mem/afifo_simple.v` — 自研异步 FIFO（Cummings 灰码指针；注意: 空/满判定必须用未门控使能的 next 指针，否则构成组合环，TD 优化器直接终止综合）
  - `rtl/mem/disp_read_engine.v` — 帧门控行预取引擎 ×2（mem_mpu 的 A/B 请求方；帧同步走"挂起-突发收尾后应用"，绝不打断突发）
  - `rtl/video/transition_ctrl.v` — 转场状态机：淡入淡出(32帧)/滑动左/滑动上 + **沉降期**（完成后再以 α=255 混一帧，消除提交边界残留旧页数据带）
  - `rtl/video/disp_mixer.v` — 双流混合器（α=0/255 快速直通精确无舍入；下溢计数供监视台）
  - 顶层：主通道读出路径整体切换为新管线；显示双缓冲钉 bank0/bank1（`BUF1=0x80000`）；装载器加 `hold_load` 转场互斥
  - `sim/tb_disp_path.v` — **全路径仿真**（行为级 SDRAM 带存储）：直通帧/中点混合帧/转场后帧三帧 307,200 像素逐位精确 PASS
  - `constraints/timing.sdc` — 启用官方预留的异步时钟组（条件已满足：跨域仅剩 FIFO 灰码/toggle 同步/准静态总线），hold 违例 -1.347ns → +0.021ns
  - `td_prj/flow_fixhold.tcl` — 自定义流程（DefaultFlow + 路由后无条件 fix_hold）
  - 编译：LUT 83.2%、BRAM 28/64，时序签名与基线一致
  - ⚠ 假绿教训：曾出现综合失败但布线用旧库出 bit、报告数字全旧、回归门 PASS——已加**产物新鲜度门**（gate.db 必须新于快照 .prj、步骤 error 标记检查、日志 ERROR 扫描）堵死
- [x] W6-W10 RTL 模块与顶层链已接入，并有模块/全路径仿真证据；不能替代板级验收
- [ ] 板级验证：双 HDMI、TF 图片/WAV、按键/拨码、蜂鸣器和应急切换
- [ ] setup 时序收敛：当前 `SWNS=-6.565ns`，需继续定位有效路径
- [ ] 稳定性与交付：至少 8 小时上板烤机、素材卡和现场演示记录

## 仿真

```bash
# 推荐：直接跑回归门（含全部仿真）
bash scripts/regression.sh

# 单独跑某个仿真（示例：监视台渲染，输出 sim/monitor_frame.ppm / .png）
cd sim
 /mnt/c/iverilog/bin/iverilog.exe -g2005 -o tb_monitor.vvp tb_monitor.v \
    ../rtl/video/video_timing_gen.v ../rtl/video/monitor_compositor.v ../rtl/ctrl/font_rom_ascii.v
/mnt/c/iverilog/bin/vvp.exe tb_monitor.vvp
python -X utf8 -c "from PIL import Image; Image.open('monitor_frame.ppm').save('monitor_frame.png')"
```
（注意：HDMI 核与 SDRAM 控制器是 TD 加密文件，无法参与第三方仿真；仿真只覆盖自研模块。）
