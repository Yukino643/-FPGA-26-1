


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// 宏是文本替换：分母和整体必须加括号，否则刷新间隔会因连续整数除法变成0。
// 125MHz -> 8ns；64ms / 8ns / 2048行 = 3906拍。IP在比较后归零，终值须减1。
`define   SDR_CLK_PERIOD                   (1000000000 / 125000000)
`define   SELF_REFRESH_INTERVAL            ((64000000 / `SDR_CLK_PERIOD / (2 ** (`ROW_WIDTH))) - 1)

