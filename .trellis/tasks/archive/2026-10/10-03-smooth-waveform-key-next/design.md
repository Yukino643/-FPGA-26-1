# 设计：平滑 PCM 波形与可靠按键切图

## 波形

保留老师第十二讲真实 PCM valid、32点采集双 bank 和完整组 VS 发布。显示节点使用 Q4，每个 VS 向最近完整组的目标推进误差的1/4；无新完整组也继续收敛。空间绘图用统一三次 B 样条，非负权重抑制尖峰；末区间保持边界值。定点结果裁剪至窗口。消隐期以三拍 Horner 乘加流水预计算每列上下界，32点更新+列数+6拍，640列最多678拍。曲线表同步读引入一拍，替代顶层原 waveform_q 寄存，总 RGB/DE/坐标相位保持。

## 请求与完成

8位 next_req_count 表示尚未启动的手动请求，最多积压255，累计切图次数无限。启动减1，同拍按下与消费净变化0。源解析与目标写入完成分别锁存，两者均到达才提交，容许任意先后或同拍。错误同拍优先清锁存，不提交失败页。所有图被本轮失败屏蔽后，只有新手动按键清屏蔽一次，避免自动无限读坏卡。后继搜索无其他候选时回退第一个真实好图。

## 顶层实际显示门

原始 scaler_done_toggle 只作为管理器写完成，不能直接提交视频。成功判定导出同 SD 域组合 display_commit_pulse，与manager结束同拍锁住display_submit_pending_sd；持久display_commit_toggle送视频CDC。payload在下一次装载前由loader_hold保证稳定。视频结束/释放toggle返回SD后才允许下一事务。复位清toggle；SD卡重新初始化时保持事件toggle历史，避免将下降沿误认为新显示提交。

## 缩放启动隔离

新source_scaler_gate只在本次源写请求应答后armed；锁存本次源解析成功和源SDRAM写完，两者齐才启动一次scaler，随即撤销armed。错误/restart/deinit优先撤销；头部阶段旧writer完成丢弃。失败BMP不会启动scaler，因此不会留下错误后才到达的旧scalerdone。

## 错误恢复依赖

source_restart=load_start_pulse|bmp_load_error，送至 src_packer 的 frame_restart，优先清除残留半像素和行计数。源写尾突发以 min(剩余字数,BURST_SIZE) 完成，禁止不足整突发后永远忙。

## 证据范围

环境注入反例证明旧管理器可永久忙、全坏图无恢复、唯一好图候选错误；当前三张640x480板测还未确定实际触发顺序。尾突发问题与当前整数倍长度无关，但属于重试/任意尺寸的明确缺陷。不得把仿真通过宣称成上板通过，setup仍按已有基线报告并列出限制。
