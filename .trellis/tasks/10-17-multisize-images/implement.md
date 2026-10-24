# 实施与验收清单

- [x] 核对官方、老师资料及现有720p缓存/发布契约。
- [x] 动态BMP尺寸、紧凑源写入和独立720p目标转换。
- [x] 源/目标行缓存分拍，启动几何计算与读命令寄存。
- [x] 菜单退出与应急条纹修复；HDMI-A坐标/RGB/同步信号对齐。
- [x] HDMI-A TMDS两级流水及独立逆解码/偏差验证。
- [x] 源writer预先锁定下一簇长度，寄存FIFO资格，保持当拍读写互斥。
- [x] 增加尾突发、分批供数和读/刷新阻塞用例。
- [x] 最终版本完整功能回归（按输入hash复用已验证项），72/72含报告门通过。
- [x] 完整TD构建和源/bit清单签发。
- [x] 新视频、串行和缩放入/出路径setup/hold非负；明确披露旧TF/FAT及SDRAM基线。
- [x] 归档同版本bit、源码、报告、测试结果和素材说明，交付入口见PROGRESS。
- [ ] 用户板级测试：双屏、混合尺寸、音频、预取、菜单退出和应急。

## 验证入口

PowerShell 7中调用本机Python：

```powershell
& 'D:/miniconda3/python.exe' -X utf8 scripts/regression_native.py --sim-only --reuse
& 'D:/miniconda3/python.exe' -X utf8 td_prj/build_native.py --output build/720p/td/20261017-multisize-tmds-ready
& 'D:/miniconda3/python.exe' -X utf8 scripts/check_reports.py
& 'D:/miniconda3/python.exe' -X utf8 scripts/check_resize_timing.py
```

构建期间不修改RTL/约束；未闭合路径不能靠放宽约束放行。取消时源/目标事务必须收尾，不允许发布部分目标页。Flash固化与硬件测试不能用功能仿真代替。
