# 老师与官方资料复核（2026-10-23）

本机源码与TD 6.2.168116安装资料；下面区分已经采用的做法与仅作备选的接口。

|来源|复核内容|本工程处理|
|---|---|---|
|`D:/FPGA/micu_FPGA_lesson/选题一完赛参考工程代码/米醋电子工作室忧郁完赛参考工程/topic1_student_reference/project_code/rtl/audio/pcm_media_tone.v`|`raw_sample * $signed({1'b0, volume})`，再算术右移8位，使用有符号PCM幅度缩放|采用同一数值原理，保留TF WAV播放器；输入已经左对齐到24位，故16位样本乘系数后的积直接作为24位输出。系数允许256以保证100%逐位一致，乘数必须扩成有符号10位；两个声道同增益，加入约21ms渐变与警笛旁路。未照搬老师的旋律发生器或8位音量上限。|
|`D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/strategies/official_strategy_ph1.json` 的 `LogicLevelOptimize`|one_hot、min_ripple_len18、balance_explore、mapper_lut_delay2200、merge_tiny_lut|保留当前已经验证可运行的官方综合选项；实际资源和时序以本轮布局后报告判断。|
|同文件的 `TimingUltra`|包含place hfn_opt_effort high、关键路径优化和布局后/布线后优化|当前已经使用hfn_opt_effort high。其他选项需要独立候选实测，不能仅因官方提供就宣称有效，也不修改时钟或SDC来隐藏违例。|
|`D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/template/verilog/Synthesis-Structure/Directive/max-fanout/max_fanout.v`|官方`(* max_fanout = N *)`寄存器属性示例|已核对语法；仅在实际报告确认高扇出瓶颈且需要RTL改变时考虑，不对全工程无差别添加。|
|同目录`retiming/forward-retiming/allow_forward_retiming.v`|官方允许寄存器前移的综合属性|已核对但未全局启用；音频、字模与valid必须同拍移动，不能为改善单一路径破坏流水相位。|

当前源码功能回归83/83通过，13场景菜单栅格通过；物理候选另行验收。资料中的优化建议不是资源、时序或板级验证结果。

## 官方策略的实际试验边界

- 在seed14上只增加官方route post_route_opt high / postrt_opt_extra_round 4，域内结果没有改善：video +0.124ns、SD +0.106ns、ext_mem −0.042ns，未通过本轮门限，候选隔离。
- 完整TimingUltra候选`build/720p/audio-volume/td-ultra14`在增量布线阶段报PHY-8023 / RUN-8102，局部连线占用冲突。工具返回码0不能掩盖错误：构建脚本通过error标记及日志拒绝，没有签发bit清单。
- 上述激进选项已撤回。保留原LogicLevelOptimize和hfn_opt_effort high，继续正常布局验收，不把“官方建议”当作可跳过实际验证的依据。
