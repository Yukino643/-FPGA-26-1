import_device eagle_s20.db -package EG4S20BG256
import_db {D:/FPGA/code/example/td_prj/av_media_Runs/phy_1/av_media_pr.db}
update_timing -mode final
puts REGS
puts [get_regs {u_resize_frame/*}]
puts CELLS
puts [get_cells -hier *source_line*]
puts PINS
puts [get_pins -hier *source_line*]
report_timing_path -from [get_pins {u_resize_frame/u_source_line_syn_1.clkb}] -ep_num 2 -file {D:/FPGA/code/example/build/720p/resize_timing/probe_clk.timing}
report_timing_path -to [get_pins {u_resize_frame/u_source_line_syn_1.dia[0]}] -ep_num 2 -file {D:/FPGA/code/example/build/720p/resize_timing/probe_data.timing}
report_timing_path -through [get_cells -hier *source_line*] -ep_num 2 -file {D:/FPGA/code/example/build/720p/resize_timing/probe_through.timing}
exit
