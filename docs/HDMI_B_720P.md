# HDMI-B 720p 首版

输出 1280×720、16:9、60Hz；像素时钟74.25MHz，TMDS串行371.25MHz。
工程入口 `td_prj/av_media.al`，固件 `td_prj/av_media_Runs/phy_1/av_media.bit`。

## 素材与板测

1. TF卡维持FAT32。先在电脑备份卡内容，再移走旧640×480 BMP。
2. 从 `D:\FPGA\音频\图片比例补偿\素材汇总_20261012\处理图` 复制以下七张到卡根目录：
   BEACH720、NAIL720、ROOM720、NIGHT720、NAIL1720、NAIL2720、MONST720，扩展名 `.BMP`。
3. 本版仅接受1280×720、24位无压缩、正高度BMP；其他尺寸会报头部错误并跳过。
   不会在板上自动把2K/JPEG/PNG缩到720p，必须先在电脑处理。
4. WAV沿用之前已经验证的PCM文件。安全弹出卡，插入开发板，再下载本轮新bit。
5. 显示器连接HDMI-B，菜单应显示1280×720/60Hz，选择原始/自动/16:9显示。
   HDMI-A首版暂停；不能用A口判断本版是否正常。
6. 检查七图颜色、方向、无蓝边/撕裂，物理KEY2连续40次切图；KEY3控制自动播放；
   KEY4长按2秒进入/退出应急，短按不再改变转场。
7. 检查交叉淡化约0.55秒，无黑场或残留；音频连续，波形圆润且逐帧变化。
8. 冷启动录像测量首图出现时间，上电3秒是目标，软件验证不能代替实测。

几何校准图在 `build/720p/previews/GRID720.BMP`。单独替换卡中的一张测试，
检查圆形横纵直径误差≤5%、红色四边完整；不要同时把所有预览文件复制到卡里。

## 实现与老师资料的对应关系

| 资料 | 吸收的设计原则 | 本工程适配 |
|---|---|---|
| 第八讲 media_frame_loader/media_frame_reader | 整帧成功才发布、在途突发不可撤销、FIFO容量预留 | 原有ACK隔离和双完成门、128字突发、2048字显示FIFO |
| 第十讲 frame_blend | 双页互补权重、帧边界推进alpha | 两级RGB565解包/混合、精确端点、交接后才释放旧页 |
| 第十二讲 promax_audio_waveform | 采集/显示双bank、有效PCM抽取、完整组发布 | 32点/80ms窗口、逐帧平滑、B样条消隐构建、同步BRAM查表 |

两显示页每页460800个32位字，地址0与0x80000，各约1.76MiB。
BMP24在写入时转RGB565，每字低半字为偶列、高半字为奇列，writer反转行地址抵消BMP底向上存储。
首版取消scaler和HDMI-A实例，以减少LUT及读写带宽。静态只读A，淡化才开启B；
首个alpha=0帧预取B，alpha=255帧完成交接后才停止B并释放loader。
外部面板缩放不会恢复RGB565的颜色精度；720p提高像素细节，渐变仍可能有量化色阶。

## 原生Windows验证

所有终端操作使用PowerShell 7。基础检查若提示旧manifest，需要以当前工程完整重建。
`-SimOnly` 明确只验证源码仿真，不用于宣称固件有效。

```powershell
pwsh.exe -NoLogo -NoProfile -File scripts/regression.ps1 -SimOnly
pwsh.exe -NoLogo -NoProfile -File scripts/regression.ps1
pwsh.exe -NoLogo -NoProfile -File scripts/regression.ps1 -Full -ReuseVerified
D:\miniconda3\python.exe -X utf8 scripts/check_reports.py
```

`-ReuseVerified`只复用输入SHA完全一致且运行成功后写入通过标记的仿真；
完整TD构建仍执行。回归覆盖全部原模块用例，旧640顶层连接明确作为fixture，
720当前顶层另做独立流水/事务测试，不能用旧连接证明新链路正确。
输出集中 `build/720p`；构建记录输入SHA、新产物、工程快照及bit清单。

## 回退

基线提交 `4e35e9e015c4c414d0e24d164e39165d2f9d2436`，tag `backup/pre-720p-20261012`。
本地完整基线 `D:\FPGA\backups\pre-720p-20261012\project`；离线Git bundle也在同目录。
恢复时使用独立目录/worktree，不执行覆盖当前工作的reset/clean。
基线固件SHA256：bea60503a33d2ead1e7ab1e4cd90363a1b39c74820010fcdc4dc026cbc72e2ac。

## 物理验证边界

TD报告以当前构建清单为准。新增video/serial域必须setup、hold均≥0；
SD/SDRAM仍按已保存基线约束验收，不等于所有时序闭合。
官方SDRAM ECO位置调整、shifted SDRAM clock局部布线两类关键警告保留在构建日志，
其他关键警告拒绝。不得降低报告门限或用false path隐藏新视频违例。
行为模型不能证明真实SDRAM刷新、显示器握手、PLL锁定及板级信号完整性。

## 嵌入式审查

| 维度 | 本轮结论 |
|---|---|
| 硬核接口与位定义 | 保留官方SDRAM/HDMI wrapper；RGB565顺序、DQM整字写及BMP格式独立核对 |
| 内存与DMA可见性 | FPGA无CPU缓存/DMA；双时钟FIFO、页payload与toggle同步负责跨域可见性 |
| 中断与RTOS | 纯RTL，无软件ISR、栈、任务调度；按时钟域审查状态机和握手 |
| 时序 | 新视频setup/hold独立门禁；SD/SDRAM继承负余量，不能声称全闭合 |
| 启动 | 前级PLL锁定稳定后释放后级，各功能域异步复位、同步解除；3秒出图待实测 |
| 边界安全 | 两页末字地址、首末像素、错误尺寸拒绝、旧ACK隔离、41次切图均有仿真 |
| 可移植性 | BMP小端正高度；本机TD6.2.168116和字体工具实测，字库ROM路径依赖当前工程目录 |

本轮工程保持 `D:\FPGA\code\example` 路径；迁移时需调整font_rom_720的初始化路径并重新构建，
不能直接拷贝旧bit清单声称迁移源码已验证。

## 本轮验证记录（2026-10-13）

| 检查 | 结果 |
|---|---|
| 当前源码仿真 | 50/50；旧模块覆盖及当前720p专项全部通过 |
| 基础回归 | 51/51；包含当前固件报告与清单 |
| 完整回归 | 52/52；实际TD综合、布局布线、bitgen重新执行 |
| 显示压力 | 7帧6451200像素，静态、混合、交接及刷新阻塞，无欠载 |
| 事务/地址 | 41次切图、迟到ACK/错误阻断；两页921600逐字地址正确 |
| 音频 | 3帧2400tick，1546/1547拍间隔，VS碰撞计入新帧 |
| 新视频时序 | pixel setup+0.115ns/hold+0.022ns；serial setup+0.905ns/hold+0.041ns |
| 总时序 | SWNS−6.565ns，HWNS+0.022ns；SD/SDRAM继承负setup |
| 资源 | LUT11567/19600（59.02%），BRAM9K49/64（76.56%），PLL3/4 |
| 素材/字库 | 七张实际BMP独立解码预览；原生字库和旧生成物逐字节一致 |

最终bit SHA256：`a6c8fe68c45aa1507e9d4ada36108b259a39b9a8c4ace0e614383e488485fb90`。
完整机器结果保存在`build/720p/regression/results.json`，基础结果在`build/720p/basic-results.json`。
输入SHA一致时复用通过仿真，所有TD构建实际执行。板级项目尚未验收。
