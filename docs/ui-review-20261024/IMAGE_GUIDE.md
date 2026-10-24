# 每组图应当如何看

所有菜单/主屏/字幕图都是RTL输出或明确注明的派生预览，没有本版实体屏照片。
画廊链接均可打开原图，浏览器“适应窗口”会缩放，判断笔画时需以100%像素查看。

|菜单文件（images/menu/）|夹具状态|优先审查|
|---|---|---|
|menu_program_720.png|字幕ON、图片/时间ON、100%、2S，聚焦图片|六卡构图、中文字重、右值对齐；字幕ON不是上电默认|
|menu_program_screen_720.png|聚焦屏幕入口|右下箭头、内边、卡值HDMI-B|
|menu_peripheral_720.png|TF READY、IDLE、CNTAB、LED3|只读/可操作、调试感|
|menu_playback_720.png|菜单退出、按键控制播放|无焦点/状态、小提示可读性；没有Auto ON专属标识|
|menu_screen_720.png|0、100%、NORM、RESET|不同长度和值类型的视觉重量|
|menu_screen_edit_720.png|对比113%预览、聚焦编辑|琥珀状态，已无星号|
|menu_screen_pending_720.png|对比仍113%待确认，焦点移到亮度|未聚焦琥珀细边/值，页眉READY；不同于全局dirty语义|
|menu_subtitle_720.png|字幕ON、1/3、NORM、标题OFF|内容缺全文、开关/数值层级|
|menu_subtitle_edit_720.png|内容2/3、速度FAST均与active不同|多个差异是夹具直接设定，不声称一定由一串真实按键产生|
|menu_wait_720.png|强制cfg_busy|WAIT字和原底线一段变琥珀，无实底块；不能据图测实际等待时长|
|menu_audio_720.png|100%、静音OFF、波形ON|十段条/数值/标题密度|
|menu_audio_edit_720.png|50%编辑预览|绿条与琥珀值是否协调|
|menu_audio_mute_720.png|80%已生效、静音ON|灰条、静音ON绿、静音焦点语义|

`images/logical/`是上述图精确抽取回640×360，并核对再次2×可逐像素恢复720p原图，不是另一种布局。

|其他目录|来源与场景|建议查看|
|---|---|---|
|images/main/BEACH720_TxCySz_OSD_RTL.png|同一明亮照片全部8组合；每图921600像素独立参考|同图横比底板、时间、字幕占位|
|images/main/NIGHT720_TxCySz_OSD_RTL.png|同一暗照片全部8组合；波形关闭|暗场抢镜、无字幕时孤立时间|
|images/subtitle/preset1/2/3_white_RTL.png|新增白背景OSD取证，p=1024、无时间|完整三句、32px格、标签与正文、HDMI/破折号/空格|
|images/waveform_current_RTL.png|新增实际波形夹具，合成PCM、固定#876543背景、1072×104|曲线、轴线、厚度；不是照片联合效果|
|images/scroll/presetN_speedV_clockC/|18圈的819个关键帧|入场/完全可见/退场/空白/归零；帧名含VS与p|
|images/scroll/*_keyframes.gif|上面关键帧按VS间隔保持|便于预览；不是全帧60fps录像|
|images/scroll/all_vs_trace.csv|每次VS状态，共29268行数据记录|三速度/两窗口、p/base/limit/重启，精确动态依据|
|images/scroll/segment/|64连续RTL帧、APNG/GIF，FAST+时间ON，p512..638|连续位移，5242880像素独立比较通过|
|images/typography/menu_cjk40_ROM_2x.png|实际同步ROM/逻辑字回读40字，逐行与字体阈值参考核对|中文完整笔画；外加索引标注不是UI|
|images/typography/ascii95_ROM_4x.png|95ASCII字模实际回读放大4×，独立参考通过|M/W/%/数字/标点，标签是外加说明|
|images/previews_800x450/|真实RTL PNG的LANCZOS软件缩小|只估计低像素显示可读性，不假定用户屏幕分辨率|

主屏照片中字幕取滚动中途：无时间p1056、有时间p768，句首可能刚被左端裁掉一个格，这是已记录的合法动态瞬间。
完整作品名笔画请看白底条或整圈关键帧，不把截到句首的照片误判为漏字。
三条白底条内部p的force只在取证testbench，不是产品有“暂停滚动/自由输入”的能力。

标称60Hz时，慢速字幕一圈无时间约51.217秒、有时间约41.617秒；普通约25.617/20.817秒，快速约12.817/10.417秒。
完整周期GIF浏览器可能降帧或按10ms量化，速度以CSV/源码为准；播放APNG也不能证明实体屏拖影、手机摩尔纹等。
