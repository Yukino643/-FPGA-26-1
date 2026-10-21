## 按键切图审查（2026-10-03）

### 确定缺陷 A：frame_fifo_write 对非突发整数长度会永久卡死
`rtl/sd/frame_fifo_write.v`: `S_WRITE_BURST` 仅以 `wr_burst_finish = (burst_cnt >= BURST_SIZE)` 结束突发；`App_wr_en` 在 `burst_cnt + write_cnt + App_wr_en < write_len_latch` 后停止。若最后剩余字数小于 `BURST_SIZE`，最后几拍写完后 `App_wr_en=0`，`burst_cnt` 无法达到 `BURST_SIZE`，状态永远停在 `S_WRITE_BURST`，`write_finish` 永不产生，后续 `write_req_ack` 也不再响应。独立 Icarus 复现：`write_len=17, BURST_SIZE=16`，写出17字后 `state=3, burst_cnt=1, busy=1`，新请求无 ack。640x480 RGB565 源长度为153600（320*480，恰为128的整数倍），所以当前三张640x480图不满足该触发条件；换尺寸素材或任一动态尺寸缩放会触发。

建议：给当前突发长度 `min(BURST_SIZE, write_len_latch-write_cnt)`，并用短突发完成条件 `burst_cnt >= burst_len_current`，或使用现有 mem_mpu 的逐拍写协议；增加17字/129字等边界回归。

### 确定缺陷 B：src_packer 未在 BMP 失败/重试之间清理残留半像素
`rtl/sd/src_packer.v` 只有 `rst` 和 `load_done` 清理 `px_stored`，而 `bmp_read_g.load_error` 没有连接给 packer。错误发生在奇数像素或半行后，`px_stored=1` 会跨重试保留，下一次图片第一个像素与旧图末像素配对，形成错位/坏源缓存。独立 Icarus 复现：旧事务留1像素，下一次4像素装载，输出3个32位字（干净应2个），并额外输出0填充字。该问题会造成源缓存错位和额外打包字；当前640x480素材成功路径每帧的像素数为偶数，尚无证据本次正常多次切图进入了错误重试。

建议：在 bmp_load_error 或 load_start_pulse 通过单拍 `packer_abort` 清空 packer；最好增加 `abort` 输入优先于像素，清空 `px_stored,row_px_count,out_valid`，并确保错误事务不把残留写进下一个源页。

### 确定缺陷 C：sd_card_bmp_g 的 source_done_seen/finish 同拍会丢完成事件（需确认实际时序）
在同一 always 块：
```
if (load_busy && load_done) source_done_seen <= 1;
if (load_busy && source_done_seen && write_finish_pulse) commit;
```
两条件同拍时后者读到旧值0，若 `write_finish_pulse` 只持续一拍，提交事件丢失；若 write_finish 在 load_done 之前，也会丢失。独立强制事件仿真复现 `load_busy`永久保持。当前 `frame_fifo_write` 根据像素字数完成，不等待 BMP `load_done`；`bmp_read_g` 根据 `file_len` 决定 load_done，并允许 file_len 大于像素末尾。因此对合法含尾部数据的BMP，最后像素写完后frame_writer与scaler可以先结束，解析器仍在读尾部数据，early finish的实际触发条件成立。但当前三张卡内文件是否带大量尾部数据尚未核实，不能认定是板测根因。

建议双完成事件都锁存，新增 `write_finish_seen`，提交条件 `(source_done_seen || load_done) && (write_finish_seen || write_finish_pulse)`，每次装载开始/错误/提交时清零，支持任意事件先后和同拍。若只改 `(source_done_seen || load_done) && write_finish_pulse`，仅解决同拍而没有解决早到事件。

### 失败图屏蔽状态风险
`failed_mask` 在同一 SD 初始化周期内持久化；所有图失败后 `any_good_image=0`，手动请求只会在 `next_req_count` 饱和累积，不会恢复。独立 forced 仿真复现 `failed_mask=7, any_good_image=0, next_req_count=21` 且没有 load_start。当前正常图片应不进入该状态；若板上诊断码显示失败掩码非0，应优先查失败根因，而不是按键。

### 请求计数器澄清
当前 WIP `next_req_count` 是8位饱和计数，最大255次待处理，不是15次，也不是总切换上限。它只记录尚未启动的请求；`img_idx`/`next_good_index` 负责图号循环，正常3张图不会因达到某个阈值永久停止。计数不会因成功切图清零，而是每启动一张减少1；这是为了保留连按事件。

### 建议板上诊断
观察 `debug_status[27:20]=failed_mask`、`[7]=any_good_image,[6]=first_image_committed,[5]=display_valid,[4]=load_retry_used,[3]=load_fault,[2]=source_done_seen,[1]=load_busy,[0]=scan_done`。按键无响应时拍下数码管状态：`load_busy=1` 代表装载/写入/缩放握手未结束；`load_busy=0且failed_mask!=0` 代表失败图屏蔽；`next_req_count`当前不在debug_status中，建议临时扩展或用逻辑分析仪。

### 确定缺陷 D：只剩当前图片可用且cur>0时，next_good_index回退到已屏蔽图0
函数默认值为0，搜索链没有包含“保持当前可用图”的尾部候选。例：`cur=2,count=3,bad=8'h03`，实际唯一可用图是2，但输出0并启动装载已知失败图0。独立强制管理器状态仿真输出 `REPRO CURRENT_ONLY_GOOD cur=2 bad=03 chosen=0`。最小修正把默认值设为 `first_good_index(count,bad)`，然后继续正常的后继优先case搜索；或每个case末尾添加当前图未坏时保持当前图。仍需覆盖单一可用图三种位置。

