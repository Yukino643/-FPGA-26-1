# 实现约束

状态行、逐卡pending/edit/selected/action及值色类别在video_clk状态寄存器预计算，像素路径仅选行/选字；保留现有1拍同步字库，不新增流水级。逐卡pending比较对应shadow/active，不使用cfg_dirty整页警示。页眉EDIT覆盖二级编辑或当前聚焦卡pending，同拍计算避免旧pending配新cursor；WAIT优先，外设无pending。恢复默认编辑显示CONFIRM，参数变化由各自卡片pending表示。

2026-10-22用户复审修订：不改网格，播放提示合成单行8×16，x32、y456..472，上下8px安全边；文案K2 NEXT K3 AUTO HOLD K3 MENU。亮度零档仍为0。

本轮8.8验收按P0范围执行：主屏保持原样并以哈希证明；综合资源、setup>=0.15ns、bit哈希由用户后续运行TD取得，当前不声称通过。
