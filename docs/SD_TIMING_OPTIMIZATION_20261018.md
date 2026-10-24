# SD装载路径资源与时序优化（2026-10-18）

## 状态

本轮评估已结束。完整功能回归72/72通过，`optimization-bounds12/14`隔离综合和布线均已完成。bounds14随后通过逐引脚寄存器hold报告补齐验收证据：SD setup为+0.001ns，缩放寄存器最小hold为+0.038ns，检查器`failures=[]`。但SD余量极薄，且资源比已验证交付版增加156 LUT和155个寄存器；按稳定完成赛题的目标，不采用该候选替换已验证版本，也不再继续追逐边际余量。SPC合法性预计算实验为负余量，RTL已撤回，只保留非法SPC回归用例。原发布bit未变，本轮未生成候选bit、未烧录。

## 参考依据与实现

本机老师工程：`D:/FPGA/micu_FPGA_lesson/选题一完赛参考工程代码/米醋电子工作室忧郁完赛参考工程/topic1_student_reference`。

| 本机证据 | 本工程采用方式 |
|---|---|
| `fat32_file_streamer.v`使用寄存读口、单写端口以及`ST_LOOP_READ/ST_LOOP_CHECK`分拍处理历史表，避免2048路异步mux | 图片候选索引预计算，目标索引与簇号/文件长度查表分拍；保留原有8图能力，不增加BRAM |
| 老师README限定四张640×480 BMP；SDC采用不同的像素/存储时钟及具体同步级约束 | 只借鉴时序分解原则；保留本工程双720p链路、多尺寸适配及现有时钟、约束 |
| 本轮前17:18的布线报告：`img_found_count -> load_file_size`，8级LUT、SD域setup −0.671 ns | 切断状态译码到元数据mux的单拍路径 |
| 新增准备拍遇SD失效会残留一次启动，定向测试实际失败 | 失效优先清除`load_select_pending`和`load_start_pulse`；负例日志和修复后正例日志保留 |
| 后续布局候选暴露MBR参数保持mux深控制路径 | `fat32_bmp_index.v`将MBR采样/新扫描清零独立为单写时序块，四槽位和不复位重扫验证 |
| 再次布线暴露BMP `width -> W*3 -> row_pos比较 -> pixel_count使能` | `bmp_read_g.v`在已有头校验准备拍寄存`pixel_row_bytes`，不增加数据阶段延迟，不改变padding/稀疏有效时序 |
| 后续布线暴露超时计数比较器到头部参数控制的组合路径 | 按下一计数值预测并寄存到期标志，保持原超时触发拍数，将宽比较与事务控制分离 |
| 图片路径缩短后，最差路径转到WAV 64位签名比较及扫描提交使能 | 将RIFF和WAVE各32位比较分组寄存；利用原有sec_ready至检查状态的稳定窗口，不增加PCM读口或缓存 |
| seed12仍有requested_sector到LBA使能7级路径，seed13暴露BMP长度加法串比较 | FAT请求锁存后增加准备拍，寄存请求合法性/目标簇/簇内位置；BMP乘法累加完成后独立比较可用文件字节数 |
| 新增长度边界反例实际复现BMP偏移+字节数32位回绕，误接受截断头 | 改为基础合法性通过后计算file_len-offset并与像素长度比较；扇区数改为商加非零余数，避免file_len+511溢出 |

## 回归与中断恢复

- `scripts/regression_native.py --sim-only`完整功能回归72/72通过，含基础/并发缩放显示各7帧、各6451200像素核对及无新增欠载。
- 最新源文件修改后，以`--sim-only --reuse`逐项核验输入哈希，受影响的BMP/FAT32/提交/预取用例实际重跑。
- `tb_prefetch720.v`增加非零且互异的簇号/文件长度，验证普通启动、重试和准备拍SD失效；先复现失败，再验证修复通过。
- `tb_fat32_bmp_index.v`增加四个分区槽位、无复位连续重扫；保留superfloppy、碎片根目录、空卡等用例。
- `tb_bmp_read_g_timeout.v`增加原超时表达式逐拍等价检查、到期前SD失效取消和重初始化后完整超时窗口；故意晚一拍的变异体被断言拒绝，日志保留。
- `tb_wav_read.v`增加有效头之后无复位重扫坏头/好头相邻扇区；继续验证242组跨扇区PCM样本及背压序列。
- `tb_fat32_file_sector_mapper.v`增加接受后客户端地址变化、同一文件后退再前进跨碎片簇；请求位置和文件范围必须锁定到本次事务。
- `tb_bmp_exact720.v`的固定/多尺寸模式均覆盖末端偏移回绕、最大32位长度扇区取整、少一字节拒绝、完整文件接受；回绕修复前失败日志保存于`build/720p/optimization-seed13/header_overflow_negative.log`。
- 回归每项结束写`results.json`，`run_status.json.complete`明确表示整轮是否完成，防止中断后误读上轮结果。

## 隔离构建

```powershell
& 'D:/miniconda3/python.exe' -X utf8 td_prj/evaluate_route.py --name optimization-wav-signature
& 'D:/miniconda3/python.exe' -X utf8 scripts/check_optimization_evaluation.py --name optimization-wav-signature
```

评估名不可覆盖已有输出，重做时使用新的名字。两条命令在工程根目录由PowerShell 7执行。

- 新run位于`td_prj/optimization-wav-signature_Runs/`，保留默认布局seed 11、route effort和hold修复。
- 流程只到`opt_route`，不运行bitgen，也不改原`av_media_Runs`、工程入口、时序约束或已发布bit。
- `build/720p/optimization-wav-signature/inputs.json`记录构建输入；构建和定向检查前后均核对哈希，包含原发布bit。
- 定向检查覆盖SD/存储域内部、视频与串行时钟摘要、缩放寄存器入出以及四块物理32K RAM的全部入出setup/hold。
- 全局SDRAM旧跨时钟负余量单独报告，域内违例不能由旧全局基线放行。

## 迭代记录

| 候选 | 实测结果 |
|---|---|
| `optimization_Runs` | 新准备拍取消问题被测试发现后，主动停止该候选物理流程，日志保留，不作为交付 |
| `optimization-final` | SD域 −0.043 ns，仍未闭合；LUT13765，视频/串行/存储域内部及缩放RAM通过 |
| `optimization-mbr` | MBR控制拆分后LUT13665；最差SD路径移至BMP行字节数计算，−0.250 ns，未签发bit |
| `optimization-pixel-row` | SD −0.615 ns、视频 −0.130 ns，定向检查明确拒绝；LUT13742，不作为交付 |
| `optimization-timeout` | 视频/串行/存储域内部及缩放RAM通过；剩余SD路径为WAV签名比较，−0.341 ns，未签发bit |
| `optimization-wav-signature` | SD −0.326 ns、存储域内部 −0.546 ns、缩放寄存器入出 −0.062 ns；LUT13785，定向检查拒绝，未签发bit |
| `optimization-seed12` | SD −0.128 ns，其他域和缩放寄存器/RAM通过；LUT13765，未签发bit |
| `optimization-seed13` | SD −0.172 ns、存储域 −0.039 ns；LUT13814，未签发bit |
| `optimization-bounds12` | LUT13960、REG9064；SD −0.255ns、存储域 −0.087ns；缩放寄存器和四块RAM定向路径均正；检查器拒绝，未签发bit |
| `optimization-bounds14` | LUT13974、REG9063；SD +0.001ns、存储域 +0.093ns、video +0.158ns、HDMI串行 +0.950ns；缩放器from setup/hold +0.620/+1.276ns、to setup +0.750ns；逐引脚缩放寄存器hold最小+0.038ns，覆盖237个单元/2034个引脚，四块RAM最小setup/hold +1.189/+0.461ns。最终检查器`failures=[]`，输入哈希匹配；但SD余量极薄且资源增加，不替换已验证版本 |
| `optimization-spc-prefilter` | 非法SPC 0/3/255拒绝和合法重扫功能回归通过；SD setup −0.539ns，LUT13994、REG9086，候选拒绝。预计算RTL已撤回，非法SPC回归用例保留 |

## 边界与后续

| 底层审查维度 | 本轮结论 |
|---|---|
| 寄存器访问 | 纯RTL；MBR字段只有一个时序写入块，按字节使能更新，复位/新扫描优先级明确 |
| 内存模型 | 不增加帧缓存或改变SDRAM页所有权；簇号/长度先锁存再启动同域事务 |
| 中断系统 | 本工程为硬件状态机，没有CPU中断优先级；按键请求/预取机制保留 |
| 时序 | bounds14隔离评估的受检时钟域及缩放寄存器/RAM路径均为正，最小SD setup +0.001ns、最小缩放寄存器hold +0.038ns；旧全局跨域余量仍为−6.565ns。该候选余量过薄，不作为当前交付 |
| 启动流程 | PLL与整体复位链不变；新增准备拍在SD失效时显式撤销 |
| RTOS | 不适用，工程无RTOS调度器 |
| 安全性 | 保留有界错误重试、坏图屏蔽、饱和请求队列及帧完整提交；取消边界、四分区和重扫已定向验证 |
| 可移植性 | 沿用Verilog-2005、Icarus仿真与本机TD 6.2.168116；BMP字段与padding格式不变 |

这是当前源码的仿真及隔离P&R评估，不是板级验证。72/72回归通过，bounds14输入哈希与当前工程一致，完整定向检查通过；但SD setup只有+0.001ns，缩放寄存器最小hold为+0.038ns，余量过薄。相对2026-10-17交付版增加156 LUT和155寄存器，BRAM/DSP/PLL不变，因此不承担替换稳定版本的风险。至此结束本轮优化评估，不继续新增RTL时序实验；已验证bit保持不变。未生成候选bit、未烧录、未写TF卡、未执行Flash固化。板级验证仍以已验证交付bit及用户现场检查为准。
