# 构建证据

构建来源：`build/stable-coldboot-20261027/source_snapshot/td_prj/av_media_Runs/phy_1/`

| 项目 | 实测值 |
|---|---:|
| LUT | 16578 / 19600（84.58%） |
| 寄存器 | 11034 / 19600（56.30%） |
| BRAM9K | 57 / 64（89.06%） |
| BRAM32K | 4 / 16（25.00%） |
| DSP | 15 / 29（51.72%） |
| PLL | 3 / 4（75.00%） |
| bit 大小 | 648248 bytes |
| bit SHA-256 | `08FB2D34D16536D2D74CB753FC438774188DADBAFDAC2D853CBC9421107426CA` |

时序报告：`source_snapshot/td_prj/av_media_Runs/phy_1/final_timing.rpt`。

- 全局 SWNS：`-6.565 ns`，对应历史加密 SDRAM 跨域路径，单列记录，不代表新增冷启动逻辑的时序。
- 全局 HWNS：`-0.005 ns`，HTNS：`-0.021 ns`。
- 报告中仍有少量路径负余量，不能写成“全工程时序闭合”。

冷启动专项报告：`validation/coldboot/summary.json` 和 `validation/coldboot/NEW_TESTS.md`。覆盖正常卡、OCR/CMD58/CMD16 失败、无应答、ACMD41 忙、多轮迟到卡和外部复位，定向用例 10/10 通过。
