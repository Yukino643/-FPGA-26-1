import_device eagle_s20.db -package EG4S20BG256
import_db {D:/FPGA/code/example/td_prj/av_media_Runs/phy_1/av_media_pr.db}
update_timing -mode final
set regs [get_regs {u_monitor_menu_ctrl/*}]
puts "REG_COUNT|menu|[llength $regs]"
if {[llength $regs] == 0} {error "Empty timing target"}
report_timing_path -from $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/menu_from.timing}
report_timing_path -to $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/menu_to.timing}
set regs [get_regs {u_monitor_config_regs/*}]
puts "REG_COUNT|config|[llength $regs]"
if {[llength $regs] == 0} {error "Empty timing target"}
report_timing_path -from $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/config_from.timing}
report_timing_path -to $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/config_to.timing}
set regs [get_regs {u_mon_menu_renderer/*}]
puts "REG_COUNT|renderer|[llength $regs]"
if {[llength $regs] == 0} {error "Empty timing target"}
report_timing_path -from $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/renderer_from.timing}
report_timing_path -to $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/renderer_to.timing}
set regs [get_regs {u_color_adjust/*}]
puts "REG_COUNT|color|[llength $regs]"
if {[llength $regs] == 0} {error "Empty timing target"}
report_timing_path -from $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/color_from.timing}
report_timing_path -to $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/color_to.timing}
set regs [get_regs {u_osd/*}]
puts "REG_COUNT|osd|[llength $regs]"
if {[llength $regs] == 0} {error "Empty timing target"}
report_timing_path -from $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/osd_from.timing}
report_timing_path -to $regs -ep_num 5 -file {D:/FPGA/code/example/build/720p/subtitle_timing/osd_to.timing}
set font_cells [concat [get_cells -hier *u_osd/u_font*] [get_cells -hier *u_mon_menu_renderer/u_font_cjk*]]
if {[llength $font_cells] == 0} {error "Empty font RAM target"}
foreach cell $font_cells {foreach check {setup hold} {
puts "FONT_BEGIN|$check|$cell"
if {$check eq "hold"} {report_cells $cell -timing -hold -mode final} else {report_cells $cell -timing -mode final}
puts "FONT_END"
}}
exit
