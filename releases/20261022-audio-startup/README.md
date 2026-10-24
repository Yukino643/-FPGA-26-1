# 20261022-audio-startup

烧录文件：`av_media.bit`。完整说明见`AUDIO_STARTUP_20261022.md`。

FAT32根目录直接定位WAV，不再等待首图或从LBA0逐扇区扫描。完整回归及严格域内时序通过；尚待上板测首声时间。

WAV保持原有标准44字节头、48kHz/16bit/双声道、物理连续存放要求。本轮不改TF卡文件。

旧加密SDRAM跨域setup负余量仍单列，不能声称全工程时序闭合。

`source-and-bit.zip`含本轮RTL/工程输入、仿真、脚本与任务快照，非TD安装包；重建仍需本机工具链。
