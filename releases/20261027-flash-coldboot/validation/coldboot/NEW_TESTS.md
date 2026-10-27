# 冷启动定向测试说明

参数缩短仅用于数字仿真，不代表实物启动时间。

| 用例 | 检查 |
|---|---|
| sd_guard_boundary | 精确等待/超时边界、同拍成功优先、成功后不复位、外部复位重新武装 |
| sd_guard_minimum | WAIT=1、TIMEOUT=1 边界 |
| sd_guard_wide_wait | WAIT=9、TIMEOUT=2，计数器宽度覆盖较大参数 |
| sd_coldboot_ocr | 第一次 OCR 上电就绪位错误后重新初始化 |
| sd_coldboot_cmd58 | 第一次 CMD58 返回错误后重新初始化 |
| sd_coldboot_cmd16 | SDSC 第一次 CMD16 错误后重新初始化 |
| sd_coldboot_no_response | 第一次 CMD0 无应答，监督超时恢复 |
| sd_coldboot_acmd41_busy | ACMD41 连续三次忙响应，第四次完成，不误复位 |
| sd_coldboot_late_card | 连续三轮 CMD0 无应答，第四轮恢复，不发布假成功 |
| sd_coldboot_external_reset | 初始化过程中外部复位后重新启动 |

正常 SDHC/SDSC 与所有故障恢复用例均在 SPI 引脚层响应，不伪造内部 ACK；恢复后逐字节核对三个完整 512 字节扇区，并跨两个监督超时窗口确认无误复位。边界单测单独注入完成信号，验证监督器本身的成功优先规则。

旧源码固定副本：baseline/rtl/sd/sd_card_top.v。旧版坏 OCR 预期失败见 baseline-ocr.log：仅 5 条初始化命令，init=0，20ms 仿真内永久停滞。该时间不是实板时间。
