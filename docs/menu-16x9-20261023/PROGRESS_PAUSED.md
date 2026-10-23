# 暂停进度：C方向菜单16:9 RTL实施

用户于2026-10-23要求暂停时的历史记录。用户随后已说“继续”，当前正在恢复验证；最终结果以IMPLEMENTATION_REPORT.md和REGRESSION_STATUS.json为准，本文件保留暂停时事实。

## 范围与禁止
- 权威：docs/ui-review-20261023/proposal/IMPL_PROMPT_MENU_16x9.md。
- 6项修改已写入RTL/生成脚本，但验证尚未全部完成，不能宣称交付完成或生成新烧录文件。
- 不综合、不P&R、不bitgen、不烧录、不提交/推送Git。实际BRAM/LUT/时序未测，不得写“新版本BRAM57已验证”。旧基线LUT14839、BRAM9K57。
- 控制器、页序、按键语义、40字中文、ROM bank尺寸禁止改动。

## 已完成
1. top：菜单640×360→720p整数2×全幅，去/3和居中黑边，x10bit/y9bit。
2. monitor_menu_renderer：48高页眉、卡y64/204高124、新标题/数值/提示坐标；宽卡值[96,256)、窄卡[8,168)，10字符右对齐、无星号；READY灰蓝，EDIT/WAIT琥珀，WAIT只替换原底线右段；音量条y56..66避让值区。
3. osd_engine_720：16px内框、时间#C9DBE5，正文窗口128..864或1152；64格/11bit字幕，p按VS推进，配置/时间变化/关闭重置，base1184/896，limit1248/1536。
4. gen_font.py统一consolab.ttf；生成ASCII bank尺寸不变。gen_font_720.py生成64格文本，仍50字/2048×32字模。
5. 更新菜单、全幅管线、主屏管线、自播放标签测试；重写字幕测试并更新render_main_ui.py（后两项尚待完整跑通）。
6. gen_monitor_cjk.py --check和gen_font_720.py --check此前均通过。

## 已通过验证与证据
- monitor_menu_renderer四组全部通过：13个场景，整页独立坐标像素检查；PPM在build/720p/regression。
- monitor_pipeline通过：921600有效像素、边缘1440、全幅2×2重复、常规4/聚焦8物理像素、3拍相位。
- 首轮其余9项通过（控制、提交、音频菜单、主屏/字幕管线、自播放标签、生成一致性等）；以对应日志为证据，尚未完整纯仿真回归。
- 13张菜单1280×720 PNG：images/menu/；已人工看program和ASCII放大sheet，字形可区分，暂未触发糊字停点；其他菜单图仍需人工查看。
- images/ascii_bold_4x.png：实际生成1bpp字模4×最近邻放大，非板拍。
- images/main/现有BEACH720的8种T/C/S组合PNG（照片输入真实OSD RTL、波形关闭、非板拍），按独立参考逐像素比对后才保存。

## 暂停时未完成
1. tb_subtitle720.v新测试运行被用户暂停，没有PASS，日志可能为空，RGB/CSV是部分产物不能当完整圈证据。需检查测试本身正确性，再重跑18圈。
   - 18圈=3句×3速×2窗口；每VS状态/端点验证，每32px及首尾实际RTL全高字幕截图。CSV是逐帧轨迹，截图不是60fps每帧全图，交付须明确区分。
   - 逐帧cycle_frames=(clock?1248:1536)*(slow?2:1)/(fast?2:1)+1；含回到0的最后VS。
   - 需要注意当前timeout设#2000000000可能超出Verilog32位延迟范围对应运行时间；按实际失败修，不盲重跑。
2. render_main_ui.py在明亮照片8组合完成后暂停，暗照片8组合尚未生成，最终verification.json未落盘，需重新跑完并查看结果图。
3. 尚未做完整纯仿真回归（--sim-only --reuse --jobs 4，不加--full）。
4. 尚未做字幕条RGB→PNG/GIF/接触表及全圈覆盖统计；不能声称已通过。
5. 尚未做完整旧→新逐条变更表、全部保护范围哈希核对、最终资源声明银行尺寸检查、Trellis规格补充与收尾。

## 续做建议顺序
1. 读本文件和权威实施规格；确认pwsh7/UTF8。不要重跑build/apply_menu_16x9.py、build/update_menu_16x9_tests.py（一次性旧文本替换已运行）。
2. 运行纯仿真定向字幕；修真实问题与测试参考，完成循环抓图与8组合暗图。
3. 完整纯仿真回归；截图人工QA，生成逐条报告。
4. 核对中文、控制器、约束、TD文件、已板验bit与改前清单哈希一致，记录新资源/时序待后续构建。
5. 交付到源码/仿真为止，等用户自行构建。

## 路径
- 改前源码+稳定bit备份：backups/before-menu-16x9-20261023/source-and-stable-bit.zip。
- 改前逐文件SHA：同目录INPUT_SHA256.json。
- 当前暂停快照：backups/menu-16x9-pause-20261023.zip（源码/测试/脚本/任务/本文件，不包含大型中间像素流）。
- 任务：.trellis/tasks/10-23-menu-16x9-rtl/，仍in_progress，notes注明用户暂停。
- 稳定烧录文件仍是releases/20261023-autoplay-period/av_media.bit；本轮没有新bit。
