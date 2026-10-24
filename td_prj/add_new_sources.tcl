# add_new_sources.tcl — 添加 W6~W10 新模块到 TD 工程
open_project D:/FPGA/code/example/td_prj/av_media.al -update

# W3-W5 已有模块（确保在）
add_files D:/FPGA/code/example/rtl/sd/sd_card_bmp_g.v
add_files D:/FPGA/code/example/rtl/sd/bmp_read_g.v
add_files D:/FPGA/code/example/rtl/mem/mem_mpu.v
add_files D:/FPGA/code/example/rtl/mem/afifo_simple.v
add_files D:/FPGA/code/example/rtl/mem/disp_read_engine.v
add_files D:/FPGA/code/example/rtl/video/video_timing_gen.v
add_files D:/FPGA/code/example/rtl/video/pixel_pos_gen.v
add_files D:/FPGA/code/example/rtl/video/transition_ctrl.v
add_files D:/FPGA/code/example/rtl/video/disp_mixer.v
add_files D:/FPGA/code/example/rtl/video/osd_engine.v
add_files D:/FPGA/code/example/rtl/video/osd_text_rom.v
add_files D:/FPGA/code/example/rtl/video/font_rom_cjk.v
add_files D:/FPGA/code/example/rtl/video/monitor_cjk_rom.v
add_files D:/FPGA/code/example/rtl/video/monitor_compositor.v
add_files D:/FPGA/code/example/rtl/video/monitor_menu_renderer.v
add_files D:/FPGA/code/example/rtl/ctrl/font_rom_ascii.v
add_files D:/FPGA/code/example/rtl/ctrl/reset_sync.v
add_files D:/FPGA/code/example/rtl/ctrl/monitor_menu_ctrl.v
add_files D:/FPGA/code/example/rtl/ctrl/monitor_config_regs.v
add_files D:/FPGA/code/example/rtl/hdmi/hdmi_tmds_channel_encoder.v
add_files D:/FPGA/code/example/rtl/hdmi/hdmi_video_only_640x480.v

# W6 缩放引擎
add_files D:/FPGA/code/example/rtl/video/scaler.v
add_files D:/FPGA/code/example/rtl/video/resize_frame_720.v
add_files D:/FPGA/code/example/rtl/sd/src_packer.v

# W7 WAV 播放
add_files D:/FPGA/code/example/rtl/audio/wav_read.v
add_files D:/FPGA/code/example/rtl/audio/audio_player.v

# W8 FFT + 参数
add_files D:/FPGA/code/example/rtl/video/color_adjust.v
add_files D:/FPGA/code/example/rtl/video/fft_spectrum.v
add_files D:/FPGA/code/example/rtl/video/spectrum_layer.v

# W9 应急模式
add_files D:/FPGA/code/example/rtl/ctrl/emergency_ctrl.v
add_files D:/FPGA/code/example/rtl/video/emergency_render.v
add_files D:/FPGA/code/example/rtl/audio/siren_gen.v

# W10 字幕 + SD 仲裁
add_files D:/FPGA/code/example/rtl/video/subtitle_scroll.v
add_files D:/FPGA/code/example/rtl/video/subtitle_text_720.v
add_files D:/FPGA/code/example/rtl/sd/sd_arbiter.v

top_module top
save_design
exit
