import_device eagle_s20.db -package EG4S20BG256
import_db {D:/FPGA/code/example/td_prj/av_media_Runs/phy_1/av_media_pr.db}
update_timing -mode final
report_cells u_resize_frame/u_source_line_syn_1 -connection -timing -mode final
report_cells u_resize_frame/u_source_line_syn_1 -timing -hold -mode final
report_timing_path -from {u_resize_frame/u_source_line_syn_1} -ep_num 2 -file {D:/FPGA/code/example/build/720p/resize_timing/probe_raw.timing}
report_timing_path -to {u_resize_frame/u_source_line_syn_1} -ep_num 2 -file {D:/FPGA/code/example/build/720p/resize_timing/probe_raw_to.timing}
exit
