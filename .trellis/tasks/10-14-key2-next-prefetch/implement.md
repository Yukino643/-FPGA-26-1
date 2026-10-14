# 实施清单

- [x] 保存用户上板成功的720p tag、Git bundle、GUI入口和bit副本。
- [x] 阅读老师第八讲loader/control及当前按键、SPI/仲裁/发布路径。
- [x] 参数化下一张预取，保留旧默认行为和错误隔离。
- [x] 独立测试首图、预取不自发提交、热请求、冷请求、队列、自动开关、坏图、SD重新初始化及hold页所有权。
- [x] 当前顶层gate/CDC真实连接回归，完整默认覆盖，TD当前源码重建及报告检查。
- [x] 记录完整资源表、实物720p结果、优化边界，上板需复核音频/连续预取显示。
- [x] Git本地提交，交付当前版本bit及回退方法（功能提交52cd68f）。
- [ ] Git推送：github.com:443无法连接，已配置的本机代理端口7897未监听；网络恢复后重试。

原生PowerShell7入口：scripts/regression.ps1 -SimOnly/-Full/-ReuseVerified。
输出集中build/720p和当前task；不操作TF卡，不以旧bit报告验证新RTL。

恢复复核：种子5最终RTL的局部hold-buffer冲突已通过官方place seed6解决，保持全部门限。
独立审查发现的预填正确图案缺口已修正；毒值目标页、实际存储写字数/DQM及漏写负例通过。
完整显示重新执行6451200像素；带写用例独立报告为8行112640像素，均零新增欠载。
源码52项与最终TD/报告分别确认，详细资源及板级边界见docs/validation/key2-prefetch-20261014.md。
