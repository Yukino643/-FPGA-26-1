
## 最终验收（2026-10-22）

全部本机发布门限通过，待用户双屏板验。正式文件：`build/720p/releases/20261022-main-ui/av_media.bit`；SHA256：`a87d1d0b280f66e6c12229b27f68e6bcd51586f8db23b489ae87097728723fbb`。

|项目|最终实测|
|---|---|
|完整回归|77/77：75项功能/生成检查＋当前源码报告与缩放物理时序2项；complete=true、filter=null、sim_only=false；只复用依赖哈希完全一致项|
|LUT|14161/19600，72.25%；比修改前15022减少861|
|寄存器|9366/19600，47.79%|
|BRAM9K / BRAM32K|57/64，89.06% / 4/16，25%|
|DSP / PLL|13/29 / 3/4|
|video_clk setup / hold|+0.274 / +0.024ns，满足setup≥+0.150ns|
|sd_card_clk setup / hold|+0.219 / +0.022ns|
|ext_mem_clk域内 setup / hold|+0.313 / +0.030ns|
|HDMI 5x域内 setup / hold|+0.958 / +0.223ns；local时钟汇总含其他检查的hold最低+0.041ns|
|全局hold|+0.022ns|
|旧加密SDRAM跨域全局setup|−6.565ns，必须单列；不声称全工程时序闭合|
|菜单/邮箱/渲染/颜色/OSD寄存器及字体RAM定向|全部通过；字体RAM入出检查均非负|
|缩放器寄存器/RAM定向|全部通过|
|字幕独立像素检查|8开关组合×3背景、3文案×3速度×2窗口共18整圈；4030991检查、21507VS，一拍ROM相位|
|真实顶层图层管线|两种字幕配置各12800像素/10行通过，RGB/DE/TLAST相位正确|
|明暗照片|三张照片输入OSD RTL，共2764800像素核对通过；波形关闭，非板拍|
|保护范围|菜单/中文字库/按键/邮箱/SDRAM读取及约束11文件与修改前备份哈希一致；原发布bit哈希不变|

最终完整构建日志：`build/720p/td/20261022-main-ui-logiclevel-hfn13`。最终flow使用TD本机官方LogicLevelOptimize综合选项，并开启官方TimingUltra中的`place hfn_opt_effort high`；seed13，route effort routability。中间失败策略全部撤下，未修改SDC、频率、引脚或RTL功能，不新增字体bank、帧缓存、PLL。原老师工程窄位宽/同步ROM/命中对齐经验延续；本轮最终资源数字来自实际P&R报告，不以估算替代。

未烧录、未Flash固化；没有提交或推送Git。默认标题/字幕仍关闭，需要在原有“字幕”二级页开启。新bit不替代板级验证；重点按本页八组合与板测清单检查。
