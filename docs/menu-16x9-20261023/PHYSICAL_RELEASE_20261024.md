# 全幅菜单：物理构建与发布验收

2026-10-24，用户在RTL阶段完成后追加授权：复核监视界面、完整综合/P&R/bitgen、提交本地Git。
本文件是本次物理构建的现状口径。原IMPLEMENTATION_REPORT、SOURCE_AUDIT、FINAL_VERIFICATION中的
“未综合/不提交Git”描述的是此前纯RTL阶段，保留作历史证据；不能据此否认本次实际构建。

## 1. 问题诊断

| 项目 | 取证与结论 |
|---|---|
| 监视画面是否全幅 | HDMI-A仍输出1280×720；640×360逻辑画布整数2×，DE全幅，无原160px居中黑边 |
| 布局与清晰度 | 已查看13场景RTL图；菜单字库尺寸不增，值右对齐、状态无底块、卡片与提示在安全边内 |
| 顶层映射 | 921600有效像素、2×2复制、1440边缘像素、3拍RGB/同步相位、4/8物理像素边框均通过 |
| 7寸屏最终显示 | 输出比例匹配16:9，RTL全幅验证通过；本轮尚未烧录，不声称已在实体屏验证 |

## 2. 执行与正式实现

| 步骤 | 本轮结果 |
|---|---|
| 完整综合 | TD 6.2.1原生Windows流程成功，非复用旧gate数据库 |
| 布局布线与bitgen | 当前源码新鲜数据库与bit成功；入口工程回写后恢复并核验快照 |
| 资源/时序 | 实际报告满足原门限，未放宽SDC、时钟或门限，沿用前置轮播修复seed14 |
| 发布 | 独立目录releases/20261024-menu-16x9；旧已板验版完整保留 |
| Git | 提交本轮源码、验证材料及可构建所需的前置轮播修复；不推送、不烧录 |

六项具体RTL/生成器旧值→新值见[原实施报告](IMPLEMENTATION_REPORT.md)第2节；本阶段未再修改RTL。
新增scripts/package_menu_16x9.py检查仿真输入哈希、实际门限、回归及定向路径，再复制发布文件、归档并逐文件回读SHA256。
图集生成的输入hex、RGB中间数据、vvp和临时testbench留本地；PNG、轨迹、GIF/APNG与验证清单纳入Git。

## 3. 资源实测

| 资源 | 当前 | 轮播旧基线 | 增量/门限 |
|---|---:|---:|---:|
| LUT | 14837/19600（75.70%） | 14839 | −2；≤16660 |
| 寄存器 | 9728/19600（49.63%） | 9732 | −4 |
| BRAM9K | 57/64（89.06%） | 57 | 0；≤57 |
| BRAM32K | 4/16 | 4 | 0；≤4 |
| DSP | 15/29 | 15 | 0；≤15 |
| PLL | 3/4 | 3 | 0；≤3 |

## 4. 验证方法与时序实测

| 同域路径组 | setup | hold | 验收 |
|---|---:|---:|---|
| video_clk→video_clk | +0.290ns | +0.020ns | setup≥+0.15ns、hold≥0，通过 |
| sd_card_clk→sd_card_clk | +0.466ns | +0.024ns | 均≥0，通过 |
| ext_mem_clk→ext_mem_clk | +0.126ns | +0.096ns | 均≥0，通过；不套用0.15ns |
| hdmi_5x_clk→hdmi_5x_clk | +0.969ns | +0.214ns | 均≥0，通过 |

上表为详细报告的同域Path Group；check_reports的每时钟local汇总还包含相关跨域/恢复等检查，
其HDMI5x hold为+0.025ns，不能与上表同域+0.214ns混作同一口径。
全局hold为+0.020ns。**旧加密SDRAM跨域全局setup仍−6.565ns，不能声称全工程时序闭合。**
旧U3/sdram ECO重定位与唯一SDRAM_CLK局部时钟警告按既有精确白名单单列在构建日志，未引入其他关键警告。

| 验证 | 结果与边界 |
|---|---|
| 完整纯仿真 | 前阶段86/86；本阶段逐输入SHA核对后复用，源文件与字库无漂移 |
| 当前完整回归 | **88/88**，complete=true、filter=null、sim_only=false；含2项当前源码物理检查 |
| 定向物理时序 | 菜单/配置/renderer/色彩/OSD/音量寄存器入出、主屏与菜单中文字体RAM引脚均非负 |
| 缩放器物理时序 | 寄存器入出与4个BRAM32K所有指定引脚setup/hold均非负 |
| 字幕 | 前阶段三句×三速×两窗口18完整圈、71200590像素；另64连续帧5242880像素 |
| 主屏组合 | 8组合×明暗照片共16图，14745600像素，实际OSD RTL输出 |
| 构建一致性 | 当前硬件输入、两份TD工程快照、bit SHA与构建manifest一致；独立发布逐文件回读 |

实际命令：build_native.py --output build/720p/td/20261024-menu-16x9；
check_reports.py；check_resize_timing.py；check_subtitle_timing.py；
regression_native.py --reuse --jobs 4；package_menu_16x9.py。
89项的旧轮播版本统计包含其当次TD_BUILD用例；本轮88项加独立TD构建及字幕定向检查，不能把两版条目数量直接比较为覆盖减少。

## 5. 交付与板验边界

- 新bit：[av_media.bit](../../releases/20261024-menu-16x9/av_media.bit)
- SHA256：`afe5562c7740a7d93a4e1c3884770b9572332b8cb2a349fc5e2ea125922b138c`
- 当前报告：[verification.json](../../releases/20261024-menu-16x9/verification.json)
- 回退：[已板验轮播版本](../../releases/20261023-autoplay-period/av_media.bit)
- 图集：[菜单总览](images/menu_contact_sheet.png)、images/menu/各完整720p场景。

烧录新bit后连接双屏：检查HDMI-A四边都正常、六卡与四卡页中文和数值清楚、长短按与确认/取消正常；
HDMI-B检查图片/音频/波形/字幕与2/3/5/10秒轮播。若屏幕启用overscan，先选“点对点/原始比例/全像素”显示；
RTL保证信号全幅，实体屏缩放策略仍以屏幕实际设置为准。本轮未进行Flash固化、断电启动或板级测试。
