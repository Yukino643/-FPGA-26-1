# 验证证据说明

发布是否完成以同目录`verification.json`的`passed:true`及当前源/bit清单一致为准。以下为验收项目，具体PASS和数值须由报告回读，不以本清单代替运行结果。

| 检查 | 证据 |
|---|---|
| 中文四卡七场景、独立字形、真实长短按、节目/媒体两页与媒体四卡双向回绕 | `build/media_runtime/test/unit_results.json`及`media_*.png` |
| 暂停pending、切换排空、异步时钟、六次切换 | `media_runtime_ctrl.log` |
| 真实720p存储/缩放/共享SD/图像像素 | `pipeline0/1/2/7_results.json`及日志 |
| 视频原轨、碎片FAT、尾首两圈、背压、在途停止 | `audio_results.json`、`media_audio.log` |
| 每页4800样本、6VS、暂停继续、慢帧等待 | `audio_frame_budget.log` |
| 最后周期音轨读错、短扇区拒绝 | `raw_audio_error.log` |
| v1/v2头字段/帧数边界/长度溢出、4GiB末扇区、65535个FAT链接、非法高位、链长及精确超时 | `build/media_runtime/bounds/results.json` |
| 原视频SPI/错误/换页 | `build/raw_video/test/unit_results.json` |
| 原图片/WAV/菜单/字幕/720p完整回归 | `build/720p/regression/results.json`与`run_status.json` |
| 独立解原MP4、全帧/PCM逐字节比对 | `build/media_audio/asset_verification.json` |
| 波形节点分时读取等价 | `build/media_audio/waveform-tdm/`；4种窗口共143520列，包含首帧及极值/脉冲/随机输入 |
| BMP读取逐拍等价与独立像素 | `build/media_audio/bmp-timing/results.json`，13组尺寸/偏移、valid间隔0/1/7、300163组无符号比较，参考SHA固定为修改前归档 |
| 完整综合/P&R/bitgen | 正式构建 `build/media_audio/td-stream-bounds-seed15/`，须等本轮完成后检查；`td-seed15/physical-final/`仅为受控布局评估；`td-stream-bounds/`被中断，没有bit；其他失败候选均不可作为发布 |
| 音频/媒体控制/页提交/FAT定向时序 | `build/media_runtime/timing/summary.json` |
| 字幕/缩放定向时序及bit绑定 | `build/720p/{subtitle_timing,resize_timing}/`及binding |

整机CASE7必须覆盖暂停且pending返回图片，以及仅切换收尾允许的一次非4800样本边界提交。普通播放仍断言完整4800样本。持页期间逐像素检查可见页不被新源写入、显示不被复位为黑场；新页未完整不提交。

本轮当前RTL测试已完成：原回归88/88；媒体控制/按键/中文7场景；pipeline0/1/2/7。正常与有声整机各核对11980800个图片像素和61747200个视频像素，三个模式复位循环；错误恢复两组各核对11059200个图片像素。CASE7读取801个WAV/PCM事务，生产97162、实际消费96650个样本，播放开始后零欠载；消费差额保留于FIFO，不是丢样本。独立输入SHA回读通过。完整字库生成检查均PASS。正式bit另须完成当前数据库定向时序和发布门限，不以功能测试替代。

正式seed15完整综合/P&R/bitgen已完成，14个档案文件SHA回读通过：LUT16508/19600（84.22%）、REG10991/19600、BRAM9K57/64、BRAM32K4/16、DSP15/29、PLL3/4。相对图片发布LUT14815增加1693（与删除部分图片功能的纯视频实验版不可直接相比）。

| 实际同域 | setup ns | hold ns |
|---|---:|---:|
| video_clk | +0.375 | +0.027 |
| sd_card_clk | +0.187 | +0.072 |
| ext_mem_clk | +0.133 | +0.024 |
| hdmi_5x_clk | +1.056 | +0.282 |

上述为Path Group同名时钟的域内统计；工具汇总还包含其他串行路径，发布器同时检查实际全局hold。旧加密SDRAM跨域全局setup仍为−6.565ns，维持原基线，不表示全工程setup闭合。最终发布必须额外通过媒体、缩放、字幕/菜单/字体定向检查，并绑定本bit SHA。

正式bit的媒体控制/视频/FAT/音轨路由/PCM读写、缩放器寄存器和四块行缓存、菜单/字幕/音量与中文字体RAM定向检查均已PASS。最终88/88完整回归的物理检查重新针对本bit执行，未改用例仅按真实输入SHA复用；两份额外定向报告已保存bit/摘要SHA绑定。bit SHA256为`c5fe18ec9fc1994bed637432764f19ce825209f1a1bb84f789e0b85721f21186`。

报告保存测试实际输入SHA。发布器核对依赖未变、回归完整≥88项、当前bit与综合输入一致、实际资源及同域setup/hold通过，最后独立回读ZIP与发布文件SHA。停止或超时不算PASS，旧all_results不能替代本轮各case报告。

素材：97帧/9.7秒，13037568字节；RV16 SHA256 `921a60c3efdbe130ec19f971cd92705123083b51528a7d88ba81f936c76a1309`。原音轨465600个双声道样本，PCM SHA256 `ac51165ec561643fcf7e8768d39b6d7478dad4febb4682653653b9b6a1e5043a`。独立解码确认有非零音频，不代表扬声器已实际发声。

失败候选留档：`td-bpb-row` LUT16658、video setup +0.289ns、ext_mem +0.153ns，但SD setup −0.949ns；`td-bmp-compare` LUT16506、video +0.246ns、ext_mem +0.097ns，但SD −0.723ns。前者瓶颈在BMP宽比较，后者转移至FAT游标比较；均不满足发布门限，不能用它们的bit烧录验收。

`td-mapper-compare/physical-final/`已独立归档并回读12个文件的SHA：LUT16535、video +0.166ns、BRAM9K57，但SD −0.381ns、ext_mem −0.348ns，仍不达标。对应瓶颈分别是BMP字节边界比较和缩放逐行加法/比较，当前候选针对这两条真实路径修改。构建开始后锁定RTL/约束/TD输入，仿真报告必须匹配最终源SHA。

边界标志/缩放阈值版本seed16（`td-stream-bounds-resume/`）LUT16541、video +0.140ns、SD +0.141ns、ext_mem +0.020ns，差0.010ns未达视频发布门限。该失败候选在归档bit/数据库前已被下一候选替换，只保留console及输入清单，`physical-final/ARCHIVE.json`明确标为不完整档案，不能冒充已回读bit的归档。seed15评估随后通过资源与域内余量检查，7文件归档SHA回读通过；正式完整构建另存，禁止用评估报告代替发布证据。

本轮不烧录、不写TF卡、不自动提交Git。用户先前板测的是无声版本；新版本的声音、卡速、暂停/循环与持页效果仍需实际检查。
