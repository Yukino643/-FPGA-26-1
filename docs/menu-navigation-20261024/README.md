# 主控制页跨卡预览取消修复（2026-10-24）

## 行为

图片、时间、周期卡：第一次 KEY4 预览，同卡第二次 KEY4 确认；未确认时 KEY2/KEY3 移动光标，取消预览并恢复最近确认值。音频、字幕、屏幕入口与二级页编辑方式不变。

原问题：cfg_dirty 是主卡共用状态，移到其他主卡后 KEY4 会提交先前卡片预览。修复在两个导航分支恢复 shadow 并清 dirty，不写提交正文、toggle 或已确认周期，因此不会撤销在途事务。

用户操作见 [简明操作说明](../KEY_GUIDE_20261017.md)。源码备份：`backups/20261024-before-menu-cancel-172813/`。旧发布 bit 原样保留。

## 验证

| 用例 | 覆盖与结果 |
|---|---|
| monitor_menu_ctrl | 图片/时间/周期各双向取消共六路径、六卡回绕、进入二级页不误提交、返回卡片重新预览/确认、忙时导航隔离；既有长短按、返回、屏幕/字幕和蜂鸣器场景全部通过 |
| audio_menu | 真实异步双时钟下取消预览不改 active，移到时间卡后只预览时间；已确认图片设置等待 VS，忙时导航不改正文/toggle，随后 VS/ACK 正常完成；既有音频测试通过 |
| monitor_config_regs | 配置邮箱与帧边界提交回归通过 |
| screen_color | 屏幕参数真实顶层连接与提交链路回归通过 |

先只修改测试、保持旧 RTL：monitor_menu_ctrl 与 audio_menu 均在新增取消断言失败，日志为 logs/before-*.log；修复后上述四项通过（4/4）。这是本轮定向功能仿真，不是全工程回归或物理验收。

复现命令（PowerShell 7）：

```powershell
& 'D:/miniconda3/python.exe' -B -X utf8 'scripts/regression_native.py' --sim-only --filter '^(monitor_menu_ctrl|audio_menu|monitor_config_regs|screen_color)$'
```

初始修复阶段只完成上述4项仿真；随后用户授权构建与推送，现已完成88/88完整范围回归及综合/P&R/bitgen，详见[物理发布记录](PHYSICAL_RELEASE.md)。烧录[新bit](../../releases/20261024-menu-navigation/av_media.bit)后，测试“图片卡一次KEY4→移到时间→KEY4”，主屏不得误关闭图片。新bit尚待上板确认。

## 验证输入 SHA256

- `rtl/ctrl/monitor_menu_ctrl.v`：`098b7479cb4ea798e2a6a706a9d6ee242fc21d14de004abebc798fb26feef53a`
- `sim/tb_monitor_menu_ctrl.v`：`7df13d5f28b9efad48377b78d4d2eae8f288277d1257b05e6582fcc1658b2a9f`
- `sim/tb_audio_menu.v`：`cea1bff07cf23f5b3b68fe2a11ef5f941f3fac3f8298e7aae86befe10db3828e`
- `rtl/ctrl/monitor_config_regs.v`：`8977168813f3c793201b4dba80160480f3cd7702fe3a1dd0fa4132a6a5f4b3d5`
