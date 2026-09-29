// video_define.vh — 统一视频时序配置
// 所有视频相关模块共用，修改分辨率只需改这里

// 640×480 @ 60Hz (VIC=1)
`define H_ACTIVE    640
`define H_FP        16
`define H_SYNC      96
`define H_BP        48
`define H_TOTAL     800

`define V_ACTIVE    480
`define V_FP        10
`define V_SYNC      2
`define V_BP        33
`define V_TOTAL     525

`define PIXEL_CLK_MHZ   25.175
`define TMDS_CLK_MHZ    125.875
