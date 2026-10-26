# 320×180无声视频实验

这是独立实验分支 `feat/raw-video-320x180`，第一阶段开机循环播放视频。原图片/WAV稳定版已经单独归档，未删除。

## 使用前提

实验bit发布路径：`D:/FPGA/code/example/releases/20261025-raw-video/av_media.bit`。完整功能回归88/88、新增视频测试、综合/P&R/bitgen与资源时序门限已经通过，尚待上板验证。

TF卡仍使用现有可正常读取的FAT32格式。把 `D:/FPGA/code/example/releases/20261025-raw-video/media/VIDEO.R16` 复制到卡根目录；不要把MP4直接改后缀，必须使用转换脚本。卡上原BMP/WAV无需删除，实验只寻找R16文件。无需更改两块屏幕的连接。

同一块开发板仍连接两个屏幕：HDMI-B为1280×720视频节目，HDMI-A为现有菜单。素材320×180，经4倍整数缩放铺满HDMI-B；清晰度受源320×180限制。

首阶段无视频音轨，也关闭普通WAV自动播放；已有应急模式和警笛路径保留。HDMI-A图片显示开关、颜色参数、标题/时间/字幕仍是节目图层控制；图片切换、自动轮播周期以及普通节目音量对本阶段无声视频无作用。尚未增加播放/暂停、视频音画同步和菜单返回图片模式，不要把这些列为已实现功能。

## 转换素材

```powershell
& 'D:/miniconda3/python.exe' -B -X utf8 'scripts/prepare_raw_video.py' `
  --input 'D:/FPGA/音频/big-blue-fish.mp4' `
  --ffmpeg 'build/raw_video/tools/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe' `
  --output 'build/raw_video/media/big-blue-fish'
```

脚本拒绝覆盖已有VIDEO.R16；另选空输出目录可重新转换。当前素材97帧、9.7秒、11,174,912字节，SHA256为 `e1c6c1e12a9393cb1e685de4706f85c71c5e652c18df102d951c8a8062b05dbd`。

帧流格式：512字节RV16 v1头，固定320×180、10fps，每帧225扇区，RGB565小端、自底向上。目录碎片簇链受支持；头不符、文件长度不符、短读或超时停止加载，并保留上一完整显示页。错误后需复位恢复。

## 回退

烧录 `D:/FPGA/code/example/releases/20261024-menu-navigation/av_media.bit` 即可恢复原图片/WAV系统。稳定commit为 `1cacb41d34910553b52a49ccd69b275303539910`。

备份目录为 `D:/FPGA/code/example/backups/20261025-before-raw-video/`，包含源码压缩包和经SHA256核对的稳定bit。源码参数 `RAW_VIDEO_MODE=0` 也保留旧方案，但修改参数后必须重新构建，不能与现有实验bit混用。

## 上板验收（尚未执行）

1. 上电后HDMI-A菜单和HDMI-B视频均能显示；确认画面方向、颜色及全幅比例。
2. 播完整9.7秒并跨一次循环，确认帧序、无残帧和明显停顿。
3. 打开/关闭图片图层、字幕和时间，确认配置在帧边界生效。
4. 进入/退出应急模式，确认警报优先；返回后视频继续。
5. 核对实际一圈播放时间。模型10fps不等于实卡性能已通过。
