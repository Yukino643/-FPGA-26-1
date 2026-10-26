import_device eagle_s20.db -package EG4S20BG256
import_db {D:/FPGA/code/example/td_prj/av_media_Runs/phy_1/av_media_pr.db}
update_timing -mode final
report_timing_path -from [get_regs {u_resize_frame/*}] -ep_num 10 -file {D:/FPGA/code/example/build/720p/resize_timing/from_regs.timing}
report_timing_path -to [get_regs {u_resize_frame/*}] -ep_num 10 -file {D:/FPGA/code/example/build/720p/resize_timing/to_regs.timing}
set ram_cells [concat [get_cells -hier *source_line*] [get_cells -hier *output_line*]]
if {[llength $ram_cells] != 4} {error "Expected four physical resize RAM cells"}
foreach cell $ram_cells {foreach check {setup hold} {
puts "RAM_BEGIN|$check|$cell"
if {$check eq "hold"} {report_cells $cell -timing -hold -mode final} else {report_cells $cell -timing -mode final}
puts "RAM_END"
}}
exit
