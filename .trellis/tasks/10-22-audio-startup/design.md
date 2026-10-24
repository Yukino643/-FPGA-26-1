# 设计

## 依据
- 本机当前 WAV 从 LBA0 顺序检查最多65536扇区；原顶层等 display_valid 后才开始。
- 老师 `topic1_student_reference/project_code/rtl/filesystem/fat32_volume_scanner.v:140` 从目录项取得首簇/大小，`fat32_file_streamer.v:148` 用 data_start_lba+(first_cluster-2)*sectors_per_cluster 寻址。这是文件定位参考，不是老师的 WAV 启动实测。
- 当前 BMP 索引已有几何检查和根目录簇链遍历，可复用且无需第二个扇区缓存。

## 接口与同步
- fat32_bmp_index 新增默认关闭的 INDEX_WAV 参数；开启时扫描至图片目标和 WAV 均满足，或正常目录结束/上限/错误。
- WAV 候选复用目录字段，拒绝结束标记之后、删除/LFN/目录/卷标、越界簇和小于44字节文件。
- 元数据只在扫描无错误完成（允许仅无BMP）后发布。首簇减2、移位、加 data_start 分拍；valid 在完整地址稳定后置位。
- sd_card_bmp_g 导出只读 wav_index_found/wav_index_sector；与 top/wav_read 同为 sd_card_clk，无新增 CDC。
- 顶层等待目录发布后，立即在候选LBA验证单个头，取消等首图和LBA0原始扫描；现有单扇区轮转仲裁保留。
- wav_read 新增 SCAN_MAX_SECTORS 参数，默认65536兼容旧例；当前顶层设1，坏头不能回落为无界原始扫描。
- SD掉初始化与复位清地址和有效标志，禁止重用旧卡地址。原短PCM/FIFO方式保持。
- 第一候选P&R暴露原根目录FAT下一簇寻址的单拍减/移/加路径负余量；ST_ROOT_REQ内以phase0/1/2分拍换算，phase3才发请求，同簇后续扇区复用root_lba。完整定向与物理报告验证通过。

## 取舍
- 只提前原始扫描会争抢首图带宽且仍浪费大量读取，本方案替换该候选。
- 没有 WAV 时继续目录扫描可能增加少量目录开销，但不扫描媒体像素。
- WAV 碎片支持、非44字节头、子目录递归另立任务，不能借启动优化悄悄宣称支持。
