# Phase A 实现规格 — 资源抢救

> **A1 状态**：✅ 已完成（2026-09-13）。LUT 80.1% → **45.26%**（-6,829），BRAM 28→32。
> **A2 状态**：待执行。本规格已根据 A1 的 TD 6.2 实战教训修订。
> **协作**：完成一项就在 `PROGRESS.md` 对应条目打 `[x]` 并追加变更日志。

---

## A1 审查结论（已完成，存档参考）

### 实测资源（gate.area / route.qor / final_timing.rpt）

| 资源 | A1 前 | A1 后 | 变化 |
|---|---|---|---|
| LUT | 15,700 (80.1%) | **8,871 (45.26%)** | **-6,829** |
| BRAM9K | 28 (43.8%) | 32 (50.0%) | +4 |
| Slices | 8,799 (89.79%) | 5,404 (55.14%) | -3,395 |
| SWNS | -6.699ns | -6.699ns | 不变（基线） |
| HWNS | +0.003ns | +0.003ns | 不变 |

### 关键模块变化

| 模块 | A1 前 LUT | A1 后 LUT | A1 后 BRAM |
|---|---|---|---|
| `u_fifo_a` (afifo_simple) | 2,440 | **45** | 2 |
| `u_fifo_b` (afifo_simple) | 2,436 | **44** | 2 |
| `u_video_rgb_to_axis_640x480` | 3,835 | **1,764** | 0 |

### A1 实际采用方案（与原规格不同）

原规格推荐的 `wfifo_32_32_512` 官方 IP 在 TD 6.2 下**推断失败**（存储变寄存器堆，26K LUT）。最终方案：

- `afifo_simple` 保留，AW 从 10 改为 9（深度 512）
- 存储体用 `EG_LOGIC_BRAM` 原语例化（`ifdef SIMULATION` 双视图）
- `HIGH_WATER` 从 512 改为 256
- `disp_read_engine` 的 `fifo_wusedw` 位宽 11→10

### TD 6.2 关键教训（A2 必须遵守）

| # | 教训 | 影响 |
|---|---|---|
| 1 | `(* ram_style = "block" *)` 属性**无效** | 不能靠属性强制 BRAM |
| 2 | 双时钟阵列同步读**推断不出 BRAM**（1,743 LUT mux 树） | 异步 FIFO 必须用原语 |
| 3 | `EG_LOGIC_BRAM` 原语**可靠落 BRAM** | A2 兜底方案 |
| 4 | 单时钟同步读 `$readmemh` 是最经典推断模式 | A2 首选方案，值得先试 |
| 5 | bash heredoc 写 Python 脚本会被转义坑坏 | 用 Write 工具直接写文件 |

---

## A2：字库 ROM 迁 BRAM

### 当前状态

`font_rom_cjk.v`（85 字形 × 16 行 × 16bit）和 `font_rom_ascii.v`（95 字形 × 16 行 × 8bit）用 case 语句实现。在 gate.area 中它们不单独出现——被综合器合并进 `u_video_rgb_to_axis_640x480`（1,764 LUT）的层级。迁 BRAM 后预计再省 1,500~2,000 LUT。

### 方案分两步走

**Step 1（首选，5 分钟可验证）**：单时钟同步读 + `$readmemh` —— 这是 TD 最经典的 BRAM 推断模式，A1 的教训是双时钟不行，但单时钟可能行。

**Step 2（兜底）**：如果 Step 1 综合后 BRAM 没涨、LUT 没降，改用 `EG_LOGIC_BRAM` 原语 + INIT_FILE 参数（与 A1 的 FIFO 同套路）。

### A2.1：修改生成脚本（用 Write 工具，不要用 heredoc）

#### 文件 1：`scripts/gen_font_cjk.py`

在 `emit_hex` 函数后追加以下函数，并在 `__main__` 的 `emit_hex(char_index, glyphs)` 之后加一行 `emit_bram_hex(char_index, glyphs)`：

```python
def emit_bram_hex(char_index, glyphs):
    """BRAM 初始化 hex：地址 = index*16+row，每行一个 16bit hex 值"""
    depth = 4096  # 256 index * 16 row
    out = os.path.join(HERE, "..", "rtl", "video", "font_cjk_bram.hex")
    with open(out, "w", newline="\n") as f:
        # index 0 = blank（16 行全 0）
        for _ in range(16):
            f.write("0000\n")
        # 实际字形
        for ch, idx in sorted(char_index.items(), key=lambda kv: kv[1]):
            for r, bits in enumerate(glyphs[ch]):
                f.write("%04X\n" % bits)
        # 填充剩余到 4096
        written = (max(char_index.values()) + 1) * 16
        for _ in range(depth - written):
            f.write("0000\n")
```

#### 文件 2：`scripts/gen_font.py`

在 `emit_hex` 函数后追加，并在 `__main__` 中调用：

```python
def emit_bram_hex(glyphs):
    """ASCII BRAM hex：地址 = char*16+row，每行一个 8bit hex 值"""
    depth = 2048  # 128 char * 16 row
    out = os.path.join(os.path.dirname(__file__), "..", "rtl", "ctrl", "font_ascii_bram.hex")
    with open(out, "w", newline="\n") as f:
        # 0x00-0x1F blank
        for _ in range(FIRST * 16):
            f.write("00\n")
        # 0x20-0x7E 实际字形
        for code in range(FIRST, LAST + 1):
            for r, bits in enumerate(glyphs[code]):
                f.write("%02X\n" % bits)
        # 0x7F-0xFF blank
        for _ in range((128 - LAST - 1) * 16):
            f.write("00\n")
```

**注意**：生成的 hex 文件名带 `_bram` 后缀，与仿真用的 `font_cjk.hex` / `font_ascii.hex` 不冲突。

### A2.2：重写字库模块

#### 文件 3：`rtl/video/font_rom_cjk.v`

**Step 1 版本（先试这个）**：

```verilog
// font_rom_cjk.v — A2: BRAM 版中文字库（同步读，1 周期延迟）
// 数据: rtl/video/font_cjk_bram.hex（scripts/gen_font_cjk.py 生成）
module font_rom_cjk(
    input  wire        I_clk,
    input  wire [7:0]  I_index,
    input  wire [3:0]  I_row,
    output reg  [15:0] O_bits
);
    reg [15:0] mem [0:4095];
    initial $readmemh("rtl/video/font_cjk_bram.hex", mem);

    wire [11:0] addr = {I_index, I_row};
    always @(posedge I_clk)
        O_bits <= mem[addr];
endmodule
```

**Step 2 版本（如果 Step 1 不推断 BRAM）**：

```verilog
module font_rom_cjk(
    input  wire        I_clk,
    input  wire [7:0]  I_index,
    input  wire [3:0]  I_row,
    output reg  [15:0] O_bits
);
    wire [11:0] addr = {I_index, I_row};
    wire [15:0] dob;

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A (16),
        .DATA_WIDTH_B (16),
        .ADDR_WIDTH_A (12),
        .ADDR_WIDTH_B (12),
        .MODE         ("PDP"),      // 伪双口：A 只写不用，B 读
        .REGMODE_A    ("NOREG"),
        .REGMODE_B    ("NOREG"),
        .RESETMODE    ("SYNC"),
        .IMPLEMENT    ("9K"),
        .INIT_FILE    ("rtl/video/font_cjk_bram.hex")
    ) u_bram (
        .dia   (16'd0),
        .addra (12'd0),
        .cea   (1'b0),
        .ocea  (1'b0),
        .clka  (I_clk),
        .wea   (1'b0),
        .rsta  (1'b0),
        .bea   (1'b0),
        .dib   (16'd0),
        .addrb (addr),
        .ceb   (1'b1),
        .oceb  (1'b1),
        .clkb  (I_clk),
        .web   (1'b0),
        .rstb  (1'b0),
        .beb   (1'b0),
        .doa   (),
        .dob   (dob)
    );

    always @(posedge I_clk)
        O_bits <= dob;
endmodule
```

**注意**：如果 `INIT_FILE` 参数在 TD 6.2 的 `EG_LOGIC_BRAM` 中不生效，需要改用 `ifdef SIMULATION` 双视图（行为模型 `$readmemh` + 综合视图原语无初始化），然后在 bitstream 生成前用 TD 的 BRAM 初始化工具写入数据。这是最后手段。

#### 文件 4：`rtl/ctrl/font_rom_ascii.v`

结构同上，数据宽度 8bit，深度 2048，地址 11bit：

```verilog
// Step 1 版本
module font_rom_ascii(
    input  wire       I_clk,
    input  wire [7:0] I_char,
    input  wire [3:0] I_row,
    output reg  [7:0] O_bits
);
    reg [7:0] mem [0:2047];
    initial $readmemh("rtl/ctrl/font_ascii_bram.hex", mem);

    wire [10:0] addr = I_char * 16 + I_row;  // 或 {I_char, I_row} 如果 I_char 是 7bit
    always @(posedge I_clk)
        O_bits <= mem[addr];
endmodule
```

**地址计算注意**：`{I_char, I_row}` 需要 I_char 是 7bit。当前 I_char 是 8bit（0x20~0x7E），所以用 `I_char * 16 + I_row` 更安全，或者用 `{I_char[6:0], I_row}`（ASCII 范围内 I_char[7] 恒 0）。

### A2.3：OSD 引擎适配（1 周期流水线）

#### 文件 5：`rtl/video/osd_engine.v`

核心改动：加 `I_clk` 端口；BRAM 地址路径用原始坐标；混合路径用延迟 1 拍的坐标。

```verilog
module osd_engine(
    input  wire        I_clk,          // 新增
    input  wire [9:0]  I_x,
    input  wire [8:0]  I_y,
    input  wire [23:0] I_bg_rgb,
    input  wire [23:0] I_uptime_bcd,
    input  wire [1:0]  I_mode,
    output wire [23:0] O_rgb
);
`include "blend_fn.vh"

    // ...（localparam 不变）...

    // ---- 流水线第 1 级：锁存坐标与背景（与 BRAM 读延迟对齐） ----
    reg [9:0]  x_d;
    reg [8:0]  y_d;
    reg [23:0] bg_d;
    reg [1:0]  mode_d;
    reg [23:0] bcd_d;
    always @(posedge I_clk) begin
        x_d    <= I_x;
        y_d    <= I_y;
        bg_d   <= I_bg_rgb;
        mode_d <= I_mode;
        bcd_d  <= I_uptime_bcd;
    end

    // ---- 窗口几何（用原始 I_x/I_y，作为 BRAM 地址输入） ----
    wire in_title_bar  = (I_y >= 9'd4)  && (I_y <= 9'd23);
    wire in_title_txt  = (I_y >= 9'd4)  && (I_y <= 9'd19);
    wire in_info_bar   = (I_y >= 9'd452)&& (I_y <= 9'd475);
    wire in_info_txt   = (I_y >= 9'd456)&& (I_y <= 9'd471);

    // ...（t_col / m_col / osd_cell 选择逻辑不变，用 I_x/I_y/I_mode/I_uptime_bcd）...

    // ---- 字库实例（BRAM 同步读，输出延迟 1 拍） ----
    wire [3:0] crow = in_info_txt ? (I_y - 9'd456) : (I_y - 9'd4);

    wire [15:0] cjk_bits;
    font_rom_cjk u_cjk(
        .I_clk  (I_clk),
        .I_index(osd_cell[7:0]),
        .I_row  (crow),
        .O_bits (cjk_bits)          // 延迟 1 拍
    );
    wire [7:0] a_bits;
    font_rom_ascii u_ascii(
        .I_clk  (I_clk),
        .I_char (osd_cell[7:0]),
        .I_row  (crow),
        .O_bits (a_bits)            // 延迟 1 拍
    );

    // ---- 混合逻辑（用延迟 1 拍的坐标/背景/模式，与字库数据同拍） ----
    wire in_title_bar_d  = (y_d >= 9'd4)  && (y_d <= 9'd23);
    wire in_info_bar_d   = (y_d >= 9'd452)&& (y_d <= 9'd475);
    wire in_info_txt_d   = (y_d >= 9'd456)&& (y_d <= 9'd471);
    wire [3:0] cellx = x_d[3:0];
    wire cell_is_ascii_d = (osd_cell[15:8] == 8'h01);  // osd_cell 也需要延迟！
    // ...
    // glyph_on / blend 用 x_d, y_d, bg_d, mode_d, bcd_d

    assign O_rgb = /* ... */;
endmodule
```

**关键细节**：`osd_cell` 本身也需要打 1 拍（因为它是从 `I_x`/`I_y`/`I_mode`/`I_uptime_bcd` 组合算出的，用于 BRAM 地址）。所以需要：

```verilog
reg [15:0] osd_cell_d;
always @(posedge I_clk) osd_cell_d <= osd_cell;
```

然后混合逻辑用 `osd_cell_d` 而不是 `osd_cell`。

#### 文件 6：`rtl/video/monitor_compositor.v`

同样需要适配。`monitor_compositor` 内部例化了 `font_rom_ascii`（L114-118）。

改动：
1. 加 `I_clk` 端口
2. `ch`、`font_row` 作为 BRAM 地址用原始坐标
3. `glyph_on`、`ccol`、颜色选择用延迟 1 拍的坐标

```verilog
module monitor_compositor(
    input  wire        I_clk,      // 新增
    input  wire        I_de,
    input  wire [9:0]  I_x,
    input  wire [8:0]  I_y,
    // ...（其余端口不变）...
);

    // ...（字符串/函数逻辑不变）...

    // 字符网格坐标（原始，用于 BRAM 地址）
    wire [6:0] col  = I_x[9:3];
    wire [4:0] line = I_y[8:4];
    wire [2:0] ccol = I_x[2:0];
    wire [3:0] crow = I_y[3:0];
    // ...（ch / font_row 计算不变）...

    wire [7:0] glyph_bits;
    font_rom_ascii u_font(
        .I_clk  (I_clk),           // 新增
        .I_char (ch),
        .I_row  (font_row),
        .O_bits (glyph_bits)       // 延迟 1 拍
    );

    // ---- 延迟坐标用于混合 ----
    reg        de_d;
    reg [9:0]  x_d;
    reg [8:0]  y_d;
    reg [31:0] fc_d;
    reg [1:0]  mode_d;
    reg [15:0] sync_d;
    reg [31:0] uptime_d;
    always @(posedge I_clk) begin
        de_d    <= I_de;
        x_d     <= I_x;
        y_d     <= I_y;
        fc_d    <= I_frame_cnt;
        mode_d  <= I_mode;
        sync_d  <= I_sync_dev;
        uptime_d<= I_uptime_sec;
    end

    // 混合逻辑改用 _d 信号
    wire [2:0] ccol_d = x_d[2:0];
    // ... glyph_on / strip_col / 颜色选择全部用 _d ...
    assign O_rgb = de_d ? rgb_c : 24'd0;
endmodule
```

#### 文件 7：`rtl/top/top_tf_hdmi_audio.v`

**改动 A — OSD 实例加 I_clk**：

```verilog
osd_engine u_osd(
    .I_clk(video_clk),                          // 新增
    .I_x(main_x), .I_y(main_y), .I_bg_rgb(vout_data),
    .I_uptime_bcd({clk_hh, clk_mm, clk_ss}), .I_mode(mode_v1), .O_rgb(vout_osd)
);
```

**改动 B — 主通道 AXIS 的 de/vs 延迟 1 拍**：

```verilog
// 在 video_rgb_to_axis 实例之前新增
reg de_d1, vs_d1;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin de_d1 <= 1'b0; vs_d1 <= 1'b0; end
    else begin de_d1 <= de; vs_d1 <= vs; end
end

video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk(video_clk), .I_rst(rst_all),
    .I_vs(vs_d1),          // ← 延迟 1 拍
    .I_de(de_d1),          // ← 延迟 1 拍
    .I_rgb(vout_osd),      // OSD 输出已延迟 1 拍
    ...
);
```

**改动 C — monitor_compositor 实例加 I_clk**：

```verilog
monitor_compositor u_mon_compositor(
    .I_clk(video_clk),                          // 新增
    .I_de(mon_de), .I_x(mon_x), .I_y(mon_y),
    .I_uptime_sec(uptime_sec), .I_frame_cnt(frame_cnt),
    .I_sync_dev(sync_dev_v1), .I_mode(mode_v1), .O_rgb(mon_rgb)
);
```

**改动 D — monitor AXIS 的 de/vs 延迟 1 拍**：

```verilog
reg mon_de_d1, mon_vs_d1;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin mon_de_d1 <= 1'b0; mon_vs_d1 <= 1'b0; end
    else begin mon_de_d1 <= mon_de; mon_vs_d1 <= mon_vs; end
end

video_rgb_to_axis_640x480 u_mon_rgb_to_axis(
    .I_clk(video_clk), .I_rst(rst_all),
    .I_vs(mon_vs_d1),      // ← 延迟 1 拍
    .I_de(mon_de_d1),      // ← 延迟 1 拍
    .I_rgb(mon_rgb),       // monitor_compositor 输出已延迟 1 拍
    ...
);
```

### A2.4：仿真更新

#### 文件 8：`sim/tb_osd.v`

- 编译命令需传 `-DSIMULATION`（如果字库用 `ifdef SIMULATION` 双视图）
- 或者直接编译新的 `font_rom_cjk.v` / `font_rom_ascii.v`（Step 1 版本无需 ifdef）
- 仿真中 BRAM 同步读需要多等 1 拍：在采样 `O_rgb` 时延迟 1 个时钟周期

#### 文件 9：`sim/tb_monitor.v`

同上，`font_rom_ascii` 加了 `I_clk` 端口，tb 需要连接。

#### 文件 10：`scripts/regression.sh`

`run_sim osd` 和 `run_sim monitor` 的编译命令中：
- 字库 .v 文件路径不变（模块名不变）
- 如果用 Step 2 版本（`EG_LOGIC_BRAM` 原语），仿真需要 `-DSIMULATION` 并提供行为模型
- 如果用 Step 1 版本（`$readmemh`），仿真直接可用

### A2.5：TD 工程文件列表

如果用 `$readmemh`，TD 综合器需要能找到 `.hex` 文件。检查 `td_prj` 的源文件列表，确保 `rtl/video/font_cjk_bram.hex` 和 `rtl/ctrl/font_ascii_bram.hex` 被加入。如果 TD 不支持 hex 作为源文件，需要改用绝对路径或把 hex 放在工程目录下。

### A2 验收清单

- [ ] `python -X utf8 scripts/gen_font_cjk.py` 成功，`rtl/video/font_cjk_bram.hex` 存在且非空
- [ ] `python -X utf8 scripts/gen_font.py` 成功，`rtl/ctrl/font_ascii_bram.hex` 存在且非空
- [ ] `bash scripts/regression.sh` 全 PASS（含 tb_osd / tb_monitor）
- [ ] `bash scripts/regression.sh --full` 成功出 bit
- [ ] gate.area 中 BRAM9K 增加 2~3 块（CJK 4096×16bit ≈ 2 块，ASCII 2047×8bit ≈ 1 块）
- [ ] LUT 在 A1 基础上再降（目标 ≤40%，即 ≤7,840）
- [ ] `sim/osd_frame.png` 中文渲染正确（人工目检）
- [ ] `sim/monitor_frame.png` 文本渲染正确（人工目检）
- [ ] HWNS ≥0
- [ ] tb_disp_path 不受影响（OSD 在其下游）

---

## 执行流程

```
1. 用 Write 工具修改 gen_font_cjk.py 和 gen_font.py（追加 emit_bram_hex）
2. 运行两个脚本，确认 .hex 文件生成
3. 用 Write 工具重写 font_rom_cjk.v 和 font_rom_ascii.v（Step 1 版本）
4. 用 Edit 工具修改 osd_engine.v（加 I_clk + 流水线）
5. 用 Edit 工具修改 monitor_compositor.v（加 I_clk + 流水线）
6. 用 Edit 工具修改 top_tf_hdmi_audio.v（4 处：OSD I_clk、主 AXIS de/vs 延迟、monitor I_clk、monitor AXIS de/vs 延迟）
7. 更新 tb_osd.v 和 tb_monitor.v（I_clk 连接）
8. 运行 bash scripts/regression.sh（快速验证仿真）
9. 运行 bash scripts/regression.sh --full（全编译出 bit）
10. 检查 gate.area：BRAM 是否涨了？LUT 是否降了？
    - 如果 BRAM 涨了 → Step 1 成功，继续
    - 如果 BRAM 没涨 → 切换到 Step 2（EG_LOGIC_BRAM 原语），回到步骤 3
11. 人工目检 sim/osd_frame.png 和 sim/monitor_frame.png
12. 更新 PROGRESS.md
```

---

## 风险与回退

| 风险 | 概率 | 回退方案 |
|---|---|---|
| `$readmemh` 单时钟也不推断 BRAM | 中 | 切 Step 2：`EG_LOGIC_BRAM` 原语 + INIT_FILE |
| INIT_FILE 参数在 TD 6.2 不生效 | 中 | `ifdef SIMULATION` 双视图 + TD BRAM 初始化工具 |
| .hex 路径 TD 综合器找不到 | 中 | 改绝对路径或把 hex 复制到 td_prj 目录 |
| OSD 流水线引入 1 像素偏移 | 低 | 仿真对比 PNG，调整 de/vs 延迟拍数 |
| monitor_compositor 遗漏 I_clk | 低 | 编译报错即可发现 |
| heredoc 转义坑坏脚本 | 已知 | **必须用 Write 工具写文件，不要用 bash heredoc** |
