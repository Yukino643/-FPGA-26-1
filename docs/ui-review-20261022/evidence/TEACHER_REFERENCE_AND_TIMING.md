# 本机老师资料对照与菜单时序收敛

用户要求生成菜单新bit，并追加“参考老师资料优化”。未扩展到8.6/8.7。

资料根目录：`D:/FPGA/micu_FPGA_lesson/选题一完赛参考工程代码/米醋电子工作室忧郁完赛参考工程/topic1_student_reference`。
本轮实际阅读 `project_code/rtl/display/brand_watermark_24.v`、`subtitle_scroll_24.v`，来源为本机代码，不是网上摘要。

| 老师实现证据 | 本工程使用方式 |
|---|---|
| brand_watermark_24固定glyph_rom，位宽12、实际144行，force_ram标记 | 继续复用现有菜单ASCII与36字形ROM，不增加bank或字体缓存 |
| glyph_index/glyph_col/glyph_row_index与glyph_address使用明确窄位宽，字距16用位移 | 菜单各卡按绝对字格先选8位字符，只使用必要位宽；独立核对800个文字横坐标索引与原定义一致 |
| 同一拍寄存字模、列号、bounds和视频信号，读BRAM后按bounds决定合成 | ASCII字库选字与卡片命中/中文优先级解耦，字库可持续读；glyph_hit_d按原拍屏蔽无关读取，不增加像素级延迟 |
| subtitle_scroll_24用diff[7:4]/[3:0]分开字索引与列，行偏移截断到4位 | 避免卡片原点的宽减法、80位整行选择、动态字符位选连续串联；用每卡并行选字再作8位选择 |

## 实际物理证据

- 初始P0：视频setup −0.207ns，ASCII字库地址路径11级，LUT14932，BRAM57，拒绝发布。
- 仅解耦命中：视频setup −0.419ns，LUT15007，BRAM57，拒绝发布。
- 每卡并行选字+seed12：视频setup +0.287ns，但ext_mem内部 −0.624ns，LUT15043，BRAM57，拒绝发布。
- 相同并行RTL+既有seed11：视频setup/hold +0.184/+0.024ns，HDMI串行 +0.962/+0.049ns，ext_mem内部 +0.143/+0.022ns；LUT15022、reg9371、BRAM57。数字已核对最终area报告；基础报告零失败，菜单/字体与缩放定向检查通过。

未修改SDC、时钟频率、控制器或HDMI-B，未新增帧缓存/PLL。常规2px/聚焦4px边框保持：失败路径已证明为ASCII地址而非边框，按路径定位修复后达到视频≥0.15ns门限。
旧加密SDRAM跨域全局setup −6.565ns继续单列，不能把域内通过写成全工程闭合。

最终当前源码75/75完整回归通过，10场景及48卡实际RTL栅格由发布检查核验；最终发布目录20261022-menu-ui-p0和SHA256以交付报告为准，不使用失败中间bit。
