// mem_map.vh — 片内 SDRAM (2M x 32bit) 地址映射（字地址，21bit）
// 布局原则（计划书 4.3 + bank 交织）：
//   控制器平坦地址按 {bank[1:0], row[10:0], col} 线性映射，bank 大小 = 2^19 字。
//   两块显示帧缓冲分别钉在 bank0 / bank1 起始 —— 转场期间 R0/R1 双流读
//   天然落在不同 bank，行激活零冲突（计划书 5.2）。
//
//  区域        字地址范围               容量          用途
//  BUF_DISP0   0x0_0000 ~ 0x4_AFFF     307,200 字    显示帧缓冲 A (640x480x32b, [31:8]=RGB)
//  BUF_DISP1   0x8_0000 ~ 0xC_AFFF     307,200 字    显示帧缓冲 B（= bank1 起点 0x80000）
//  BUF_SRC     0xC_B000 ~ 0x1F_FFFF   1,265,664 字   缩放源图暂存（W6: RGB565 打包 2 像素/字，
//                                                      1024x768 需 393,216 字 —— 充足）
//  （0x4_B000 ~ 0x8_0000 之间为空闲带 217,088 字，未用）
//
//  W6 修订: 源图区从 0x4_B000 挪到 0xC_B000 —— 原区间只有 217,088 字，
//  装不下 1024x768 RGB565 所需的 393,216 字。
localparam [20:0] MEM_BUF_DISP0_BASE = 21'h0_0000;
localparam [20:0] MEM_BUF_DISP1_BASE = 21'h8_0000;
localparam [20:0] MEM_BUF_SRC_BASE   = 21'hC_B000;   // W6: 原 0x4_B000，容量不足已迁址
localparam [20:0] MEM_FRAME_WORDS    = 21'h4_B000;   // 307200 = 640*480
