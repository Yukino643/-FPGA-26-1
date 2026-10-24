# W1 baseline: create TD project for lab_ex5 official code restructured under rtl/
set PRJ_DIR D:/FPGA/code/example/td_prj
set RT D:/FPGA/code/example

create_project -family EG4 -device EG4S20BG256 av_media $PRJ_DIR

# ---- RTL sources (Verilog only, no .vhd duplicates) ----
foreach f {
    rtl/top/top_tf_hdmi_audio.v
    rtl/sd/sd_card_bmp.v
    rtl/sd/sd_card_top.v
    rtl/sd/sd_card_cmd.v
    rtl/sd/sd_card_sec_read_write.v
    rtl/sd/spi_master.v
    rtl/sd/bmp_read.v
    rtl/sd/frame_read_write.v
    rtl/sd/frame_fifo_read.v
    rtl/sd/frame_fifo_write.v
    rtl/sd/ax_debounce.v
    rtl/mem/sdram.v
    rtl/mem/include/global_def.v
    rtl/mem/include/sdr_as_ram.enc.v
    rtl/mem/include/sdr_init_ref.enc.v
    rtl/mem/include/sdr_wrrd.enc.v
    rtl/video/video_timing_data.v
    rtl/video/video_delay.v
    rtl/video/video_define.v
    rtl/video/color_bar.v
    rtl/video/video_rgb_to_axis_640x480.v
    rtl/video/monitor_compositor.v
    rtl/video/monitor_menu_renderer.v
    rtl/video/monitor_cjk_rom.v
    rtl/video/subtitle_text_720.v
    rtl/video/resize_frame_720.v
    rtl/audio/I2S_receiver.v
    rtl/audio/audio_arc_calculate.v
    rtl/audio/hdmi_audio_tone_i2s_64fs.v
    rtl/audio/hdmi_audio_tone_pcm_scale.v
    rtl/ctrl/key_remove_shakes.v
    rtl/ctrl/startup_pulse.v
    rtl/ctrl/seg_decoder.v
    rtl/ctrl/seg_scan.v
    rtl/ctrl/monitor_menu_ctrl.v
    rtl/ctrl/monitor_config_regs.v
    rtl/hdmi/hdmi_phy_warpper.v
    rtl/hdmi/lane_lvds_10_1.v
    rtl/hdmi/hdmi_tmds_channel_encoder.v
    rtl/hdmi/hdmi_video_only_640x480.v
    rtl/hdmi/hdmi_1_4b_transmitter_core_wrapper.enc.v
    rtl/pll/sys_pll.v
    rtl/pll/video_pll.v
    rtl/pll/afifo_16_32_256.v
    rtl/pll/afifo_32_16_256.v
} {
    add_files $RT/$f
}

# ---- constraints ----
add_files $RT/constraints/pin.adc
add_files $RT/constraints/timing.sdc
add_files $RT/constraints/edid_debug.cwc

top_module top
save_design
exit
