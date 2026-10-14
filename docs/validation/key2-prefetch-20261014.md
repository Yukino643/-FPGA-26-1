# KEY2预取与单板资源验收（2026-10-14）

## 问题诊断

| 问题 | 本机代码/报告证据 | 结论 |
|---|---|---|
| KEY2等待1~2秒 | 20ms消抖后原逻辑才启动整帧BMP装载；SD域100MHz、SPI分频0，约25MHz | 纯RTL无软件中断优先级；读卡装载是主要等待来源 |
| 每图数据量 | 1280×720 BMP24含头约2764854字节 | 仅串行数据理论下限0.885秒，FAT/WAV共享/协议开销另计；分段耗时未板测 |
| 工作中断 | 最终RTL种子5出现PHY-8023/RUN-8102，涉及height[6]与rst_dup_50_holdbuf0 | 最新bit未生成，首次成功构建不足以证明最终修正 |
| 原预取测试 | 目标页预填最终期望图案 | 可能掩盖实际漏写，已改为毒值并添加真实存储接口计数 |

## 实现

| 步骤 | 完成内容 |
|---|---|
| Step 1 | 保留已上板成功的720p标签、Git bundle、bit及GUI入口备份 |
| Step 2 | 对照老师第八讲media_frame_loader完整页标记和media_player_control帧边界选择 |
| Step 3 | 顶层开启PREFETCH_NEXT=1；空闲页后台装载完成仅置ready，KEY2才发布 |
| Step 4 | 保留双完成门、事务req/ACK隔离、转场锁页/释放CDC、饱和队列和错误恢复 |
| Step 5 | 根据本机官方MultiSeed.tcl改变布局种子为6，完整重建且不放宽时序/警告门禁 |

正式实现位于`rtl/sd/sd_card_bmp_g.v`、`rtl/top/top_tf_hdmi_audio.v`及`td_prj/flow_fixhold.tcl`。
独立审查记录位于`.trellis/tasks/10-14-key2-next-prefetch/review.md`。

## 验证

| 检查 | 证据与边界 |
|---|---|
| 当前源码仿真 | 52/52通过；仅输入SHA完全一致的成功用例复用，补强的显示测试重新执行 |
| 基础回归 | 53/53通过，覆盖全部源码门与当前固件报告 |
| 完整构建回归 | 53/53通过；独立运行的display720从并行TD回归中排除，随后基础回归再次核对其成功输入SHA |
| 热/冷请求 | 首图、41次热切换、冷请求、缩比物理消抖、255饱和排空、错误、自动取消和SD重初始化 |
| 完整显示 | 实际1650×750时序，7个完整720p活动帧，共6451200像素；补强后重新执行通过，耗时829.3秒 |
| 预取与显示并行 | 1280列、8活动行、11帧112640像素，实际5120字后台写入、刷新阻塞、零新增欠载；不冒充完整720行带写实物验证 |
| 漏写负例 | 临时测试副本关闭SDRAM模型wr_en；第6帧(0,0)像素参考检出错误并非零退出 |
| TD | 当前源码种子6综合、布局布线、显式fix_hold及bitgen通过；独立报告fails=0 |
| 新视频时序 | pixel setup+0.144ns/hold+0.022ns；serial setup+0.977ns/hold+0.068ns |
| 总时序 | SWNS=-6.565ns，HWNS=+0.022ns；既有SD/SDRAM负setup仍未完全闭合 |
| 源码/固件 | 当前工程入口、两个run快照、RTL、构建脚本、bit与SHA-256清单一致 |

## 完整资源快照

数据来自本轮TD物理报告`td_prj/av_media_Runs/phy_1/av_media_phy.area`。

| 资源 | 使用 | 总量 | 占比 | 剩余 |
|---|---:|---:|---:|---:|
| LUT | 11564 | 19600 | 59.00% | 8036 |
| 寄存器 | 7903 | 19600 | 40.32% | 11697 |
| BRAM9K | 49 | 64 | 76.56% | 15 |
| BRAM32K | 0 | 16 | 0% | 16 |
| DSP | 9 | 29 | 31.03% | 20 |
| PLL | 3 | 4 | 75.00% | 1 |
| GCLK | 3 | 16 | 18.75% | 13 |
| 物理PAD | 48 | 188 | 25.53% | 140 |
| 逻辑IO端口 | 40 | 188 | 21.28% | 148 |

物理PAD包含差分引脚，逻辑IO含输入10/输出28/双向2；两行不能相加。
LE使用13223：LUT-only5320、寄存器-only1659、共享6244；报告未给LE总量，不另造利用率。
IO寄存器输入3/输出21/三态1；FIFO9K独立原语0，FIFO数据RAM已计入BRAM。
当前显示双页RGB565像素载荷约3.52MiB，21bit×32bit接口寻址8MiB；
七张全缓存约12.30MiB，超过当前接口范围。接口寻址范围与物理芯片容量分别判断。

## 风险与上板复核

| 项目 | 判断/验证方法 |
|---|---|
| 是否需要双板 | 当前HDMI-B 720p、WAV、波形、淡化及应急功能单板资源够用，暂不需要 |
| 恢复完整HDMI-A | 本版A口暂停；第二读流、视频FIFO/HDMI IP、PLL和带宽需要另做预算及并行压力验证 |
| 热响应 | 首图/转场结束后停留至少2秒，再按KEY2；设计预算约20~55ms开始可见变化，须视频计时实测 |
| 冷请求/快按 | 未缓存时仍等剩余读卡时间；转场中请求排队，读卡吞吐不因预取而提高 |
| 动画时间 | 交叉淡化约0.55秒；分别测动画开始和完成，不能把后者误当按键启动延迟 |
| 板级验收 | HDMI-B七图循环至少40次、连续快按、WAV播放时切图、长期待机、冷启动；预取版尚未上板 |
| 时序限制 | 新视频域通过，旧SD/SDRAM负setup仍存在；资源余量不能代替时序闭合与物理稳定性 |
| BRAM扩展 | BRAM9K与PLL较紧；BRAM32K须按端口/时钟/IP限制适配，不能直接等价替换 |

## 交付与回退

- 工程入口：`td_prj/av_media.al`。
- 当前固件：`td_prj/av_media_Runs/phy_1/av_media.bit`。
- 预取前板级成功标签：`backup/pre-key2-prefetch-20261014`，提交`bd3db21`。
- 本地备份：`D:/FPGA/backups/pre-key2-prefetch-20261014`。
- 已上板原bit SHA256：`a6c8fe68c45aa1507e9d4ada36108b259a39b9a8c4ace0e614383e488485fb90`。
- 用独立checkout恢复标签，或从备份目录选择原bit；禁止reset/clean覆盖当前改动。

最终bit SHA256：`35b5bde642317516216f8f2e3ce66d18486e4857ec659a1b1f5dc1b43a2b2410`。

本轮实际执行命令（PowerShell7，均退出0）：

```powershell
pwsh -NoLogo -NoProfile -File scripts/regression.ps1 -SimOnly -Filter '^(prefetch_display720|display720)$'
pwsh -NoLogo -NoProfile -File scripts/regression.ps1 -SimOnly -ReuseVerified
# 完整显示已单独运行，其余门与TD构建并行；没有跳过最终源码显示验证。
pwsh -NoLogo -NoProfile -File scripts/regression.ps1 -Full -ReuseVerified -Filter '^(?!display720$).*'
pwsh -NoLogo -NoProfile -File scripts/regression.ps1 -ReuseVerified
D:/miniconda3/python.exe -X utf8 scripts/check_reports.py
```

机器结果：`build/720p/key2-sim-final-results.json`、`key2-full-final-results.json`、
`key2-basic-final-results.json`及`key2_resources.json`。最后一次TD完整日志在
`build/720p/td`；源码、工程快照、bit及构建脚本的SHA清单位于物理run目录。

Git功能提交：`52cd68f`，本地分支`feat/key2-next-prefetch`。
GitHub推送尚未完成：首次连接重置，HTTP/1.1通道检查显示github.com:443无法连接；
本机记录的127.0.0.1:7897代理端口未监听。未改变系统代理、全局Git配置或远端。
网络恢复后在PowerShell7中执行`git push -u origin feat/key2-next-prefetch`。
本轮新固件与完整Git bundle离线备份目录：`D:/FPGA/backups/key2-prefetch-20261014`。
