# 菜单防误操作版物理发布（2026-10-24）

## 烧录文件与操作

[av_media.bit](../../releases/20261024-menu-navigation/av_media.bit)

SHA256：`37f46d5f00b550914cf84679fe0a7281fdcd40a1fd099dd9edb78c2de6c60f31`。

主控制页图片、时间、周期：第一次KEY4预览，同卡第二次确认；KEY2/KEY3移开即取消未确认预览。已确认设置保留，二级编辑与长按不变。[简明操作说明](../KEY_GUIDE_20261017.md)。新bit尚待上板，未代替用户做烧录。

## 验证结果

| 项目 | 当前版本实测 |
|---|---|
| 完整范围回归 | 88/88；complete=true、filter=null、sim_only=false；86功能/生成+2当前源码物理检查 |
| 菜单导航 | 图片/时间/周期各双向移开、回绕、同卡两次确认、二级入口不误提交、忙时隔离、异步VS/ACK均通过 |
| 字幕 | 18完整周期、全部状态/像素断言保留；本轮重新执行，只关闭重复的大体积栅格导出；原三句字形证据与输入哈希一致 |
| 其余回归 | 仅对输入SHA完全一致的通过用例复用，未声称所有用例本轮重新运行 |
| TD构建 | 当前源码完整综合、布局布线、hold修复、bitgen；最终seed14 |
| 定向时序 | 菜单/配置/渲染/颜色/OSD/音量、两屏字体RAM引脚及缩放器路径通过 |
| LUT | 14815/19600（75.59%），比上一版实际布局少33；不归因于单一RTL改动 |
| REG | 9727/19600 |
| BRAM9K / BRAM32K | 57/64、4/16 |
| DSP / PLL | 15/29、3/4 |
| video_clk setup / hold | +0.478 / +0.022 ns |
| sd_card_clk setup / hold | +0.320 / +0.024 ns |
| ext_mem_clk setup / hold | +0.200 / +0.021 ns |
| hdmi_5x_clk setup / hold | +0.949 / +0.329 ns |
| 旧加密SDRAM跨域global setup | −6.565 ns，仍属已知基线；不能宣称全工程时序闭合 |

域内数值取最终Path Group，不与local时钟汇总混用。video setup门限≥0.15ns，其余域内setup/hold非负；资源上限与约束未放宽。

## 未发布候选与门禁修正

seed16候选SD域setup−0.298ns，最差路径从sd_card_bmp_g到load_select_idx寄存器，数据路径约80%为连线。最终严格签发门拒绝此候选；回归检查脚本补入SD域内部setup/hold，并以该候选完成负向验证，见logs/rejected-seed16-gate.log与logs/rejected-seed16.timing。

只将place seed从16改为14，保持功能RTL、时钟、SDC与门限；完整重新综合/P&R/bitgen后上述域全部通过。失败候选本地保存于build/720p/td/20261024-menu-navigation-seed16-rejected，不作为烧录交付。

回归脚本的SD门禁新增后，本轮最终88/88已包含此检查。初始大体积字幕导出被主动中止；清除对应通过缓存后，以保留全部断言的模式重新运行通过，不复用被中止日志。

## 复现入口

```powershell
& 'D:/miniconda3/python.exe' -B -X utf8 'td_prj/build_native.py' --output 'build/720p/td/20261024-menu-navigation'
& 'D:/miniconda3/python.exe' -B -X utf8 'scripts/regression_native.py' --reuse --subtitle-state-only --jobs 3
& 'D:/miniconda3/python.exe' -B -X utf8 'scripts/check_subtitle_timing.py'
& 'D:/miniconda3/python.exe' -B -X utf8 'scripts/package_menu_navigation.py'
```

签发脚本拒绝覆盖已存在发布目录；上面最后一步用于首次生成版本。发布内SOURCE_SHA256.json、source-and-bit.zip与SHA256SUMS.txt均已逐文件回读校验；bit与当前工程输入清单相符。上一版已板验空格字幕bit原样保留供回退。
