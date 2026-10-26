import_device eagle_s20.db -package EG4S20BG256
import_db {D:/FPGA/code/example/td_prj/av_media_Runs/phy_1/av_media_pr.db}
update_timing -mode final
set regs [get_regs {*g_raw_video*}]
puts "REG_COUNT|player|[llength $regs]"
if {[llength $regs] == 0} {error "Empty raw-video timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/raw_video/timing/player_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/raw_video/timing/player_to.timing}
set regs [get_regs {*g_video_commit*}]
puts "REG_COUNT|commit|[llength $regs]"
if {[llength $regs] == 0} {error "Empty raw-video timing target"}
report_timing_path -from $regs -ep_num 10 -file {D:/FPGA/code/example/build/raw_video/timing/commit_from.timing}
report_timing_path -to $regs -ep_num 10 -file {D:/FPGA/code/example/build/raw_video/timing/commit_to.timing}
exit
