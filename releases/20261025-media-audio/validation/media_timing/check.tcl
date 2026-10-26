import_device eagle_s20.db -package EG4S20BG256
import_db {D:/FPGA/code/example/td_prj/av_media_Runs/phy_1/av_media_pr.db}
update_timing -mode final
set regs [get_regs {*u_media_source/video/*}]
puts "REG_COUNT|player|[llength $regs]"
if {[llength $regs] == 0} {error "Empty media-runtime timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/player_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/player_to.timing}
set regs [get_regs {*u_media_source/fs/*}]
puts "REG_COUNT|filesystem|[llength $regs]"
if {[llength $regs] == 0} {error "Empty media-runtime timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/filesystem_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/filesystem_to.timing}
set regs [get_regs {*u_frame_commit/*}]
puts "REG_COUNT|commit|[llength $regs]"
if {[llength $regs] == 0} {error "Empty media-runtime timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/commit_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/commit_to.timing}
set regs [get_regs {*u_media_runtime/*}]
puts "REG_COUNT|runtime|[llength $regs]"
if {[llength $regs] == 0} {error "Empty media-runtime timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/runtime_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/runtime_to.timing}
set regs [get_regs {*u_media_audio_router/*}]
puts "REG_COUNT|audio_router|[llength $regs]"
if {[llength $regs] == 0} {error "Empty media-runtime timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/audio_router_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/audio_router_to.timing}
set regs [get_regs {*u_wav_read/*}]
puts "REG_COUNT|audio_reader|[llength $regs]"
if {[llength $regs] == 0} {error "Empty media-runtime timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/audio_reader_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/audio_reader_to.timing}
set regs [get_regs {*u_audio_player/*}]
puts "REG_COUNT|audio_fifo_player|[llength $regs]"
if {[llength $regs] == 0} {error "Empty media-runtime timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/audio_fifo_player_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/media_runtime/timing/audio_fifo_player_to.timing}
exit
