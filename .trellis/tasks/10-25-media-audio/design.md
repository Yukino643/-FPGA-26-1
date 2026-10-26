# 设计
备份backups/20261025-before-media-audio，稳定bit aed297ca23dd54f34cc28a94cdabac2e6b328d39260da7a73d6b3729900ca70b。
中文：删除外设页后回收10个专用汉字槽位，37字中36字放回原BRAM、1字逻辑绘制；基础/扩展银行尺寸不变。节目/媒体直接两页切换，保留设置二级页与真实LED/应急蜂鸣器。
保留页：显示读链保持全局复位，切换仅排空后复位源writer/scaler。VS捕获旧front；新源首帧写反页，加载期间页面mux保持旧front。第一张图片以旧front为转场起点。禁止清FIFO掩盖在途突发。
音轨：RV16 v2保持视频帧区不变，尾部追加48000Hz/s16le/stereo PCM；每帧4800样本。头携带音频起点、样本数、频率和格式。共享现wav_read扇区BRAM和audio_player FIFO，不增加音频大缓存。视频/音频各用独立簇链mapper，共享单扇区物理仲裁；WAV切换收尾后复位并在返回图片重启。
video_frame_commit每6VS采纳，音频每帧最多消费4800样本；迟到帧保持旧画面并在音频帧末等待，禁止音频先跑到下一帧。第一视频页待音频预取就绪才发布。暂停保持FIFO与样本序号，循环FIFO顺序跨尾首连续。音频源切换使用媒体复位flush两侧FIFO，但48kHz节拍/警笛不复位。
风险：新mapper/中文组合逻辑增加LUT；需实际综合核对。共享BRAM目标57/4，DSP15、PLL3不增加。旧SDRAM跨域负setup单列，不能称全时序闭合。
