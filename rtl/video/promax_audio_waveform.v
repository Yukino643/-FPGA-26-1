// 参考老师第十二讲 promax_audio_waveform.v：抽取、32点双缓冲、帧边界交换。
// 采集窗口跨视频帧保持，避免 32 点只覆盖几毫秒导致波形快速扫动。
// 完整组发布后逐帧平滑，消隐期计算三次 B 样条；同步查表输出带一拍延迟。
module promax_audio_waveform #(
    parameter integer WAVE_X = 64,
    parameter integer WAVE_Y = 384,
    parameter integer WAVE_WIDTH = 512,
    parameter integer WAVE_HEIGHT = 64,
    parameter integer DECIMATE = 12,
    parameter integer VIDEO_WIDTH=640, VIDEO_HEIGHT=480, X_BITS=10, Y_BITS=9,
    parameter integer PIPELINED_GEOMETRY=0
)(
    input wire clk, rst, vs_pulse, de, enable,
    input wire [X_BITS-1:0] pixel_x,
    input wire [Y_BITS-1:0] pixel_y,
    input wire [23:0] rgb_in,
    input wire pcm_tap_valid,
    input wire signed [15:0] pcm_tap_left,
    output wire [23:0] rgb_out,
    output wire waveform_active
);
    localparam integer SAMPLE_COUNT = 32;
    localparam integer SAMPLE_SPACING = WAVE_WIDTH / SAMPLE_COUNT;
    localparam integer CENTER_Y = WAVE_Y + WAVE_HEIGHT/2;
    localparam integer MAX_OFFSET = WAVE_HEIGHT/2 - 2;
    reg signed [7:0] sample_bank0 [0:31];
    reg signed [7:0] sample_bank1 [0:31];
    reg write_bank, display_bank, display_valid;
    reg [5:0] capture_count;
    reg [7:0] decimate_count;
    reg [7:0] peak_bank0, peak_bank1, display_peak;
    wire [7:0] sample_abs = pcm_tap_left[15] ?
                            (~pcm_tap_left[15:8] + 1'b1) : pcm_tap_left[15:8];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_bank <= 0; display_bank <= 1; display_valid <= 0;
            capture_count <= 0; decimate_count <= 0;
            peak_bank0 <= 0; peak_bank1 <= 0; display_peak <= 0;
        end else if (vs_pulse) begin
            // 仅完整的 32 点采样组可在帧边界发布；未采满时保留采集状态跨帧继续。
            if (capture_count == SAMPLE_COUNT) begin
                display_bank <= write_bank;
                display_valid <= 1;
                display_peak <= write_bank ? peak_bank1 : peak_bank0;
                write_bank <= ~write_bank;
                capture_count <= 0;
                decimate_count <= 0;
                // 清理下一组将写入 bank 的峰值累积器。
                if (write_bank) peak_bank0 <= 0;
                else peak_bank1 <= 0;
            end
        end else if (pcm_tap_valid && capture_count < SAMPLE_COUNT) begin
            if (decimate_count == 0) begin
                if (write_bank) sample_bank1[capture_count[4:0]] <= pcm_tap_left[15:8];
                else sample_bank0[capture_count[4:0]] <= pcm_tap_left[15:8];
                capture_count <= capture_count + 1'b1;
                decimate_count <= DECIMATE-1;
                if (write_bank) begin
                    if (sample_abs > peak_bank1) peak_bank1 <= sample_abs;
                end else begin
                    if (sample_abs > peak_bank0) peak_bank0 <= sample_abs;
                end
            end else decimate_count <= decimate_count - 1'b1;
        end
    end

    // 显示节点采用 Q4 像素：每个 VS 向新完整采样组推进 1/4。
    // 采样组约 80ms 发布一次，但曲线每个视频帧都变化；不改动播放 PCM。
    reg signed [11:0] smooth_nodes [0:31];
    reg nodes_initialized;
    reg [3:0] build_state;
    reg [4:0] node_index;
    reg [9:0] build_x;
    reg signed [15:0] h0, h1, h2, h3;
    reg signed [15:0] c1q, c2q0, c2q1, c3q0, c3q1, c3q2;
    reg [7:0] f0, f1, f2;
    reg [6:0] pipe_valid;
    reg [9:0] x0, x1, x2, x3;
    reg [9:0] x4,x5,x6;
    reg [10:0] magnitude_div32;
    reg [21:0] reciprocal_product;
    reg sign4,sign5;
    reg signed [15:0] quotient6;
    reg signed [15:0] p0_q,p1_q,p2_q,p3_q;
    reg signed [11:0] node_target_q;
    reg signed [12:0] node_error_q;
    reg [7:0] fraction_q;
    wire [15:0] h3_magnitude=h3[15] ? -h3 : h3;
    wire signed [15:0] geometric_raw = PIPELINED_GEOMETRY ? quotient6 : curve_raw;
    wire geometry_valid = PIPELINED_GEOMETRY ? pipe_valid[6] : pipe_valid[3];
    wire [9:0] geometry_x = PIPELINED_GEOMETRY ? x6 : x3;

    reg [Y_BITS-1:0] previous_y;
    reg curve_valid;
    localparam B_IDLE=0, B_NODES=1, B_LOAD=2, B_DRAIN=3, B_LAST=4, B_FETCH=5, B_NODE_FETCH=6;
    // 同步读列上下界，适配 BRAM；有效区只查表和比较，避免像素路径串接乘法。
    localparam CURVE_DW = 2*Y_BITS;
    localparam CURVE_AW = $clog2(WAVE_WIDTH);
    wire signed [7:0] node_sample = !display_valid ? 8'sd0 :
                      display_bank ? sample_bank1[node_index] : sample_bank0[node_index];
    wire signed [11:0] node_target_raw = $signed(node_sample) * 12'sd8;
    wire signed [11:0] node_target = (node_target_raw > MAX_OFFSET*16) ? MAX_OFFSET*16 :
                     (node_target_raw < -MAX_OFFSET*16) ? -MAX_OFFSET*16 : node_target_raw;
    wire signed [12:0] node_error = $signed(node_target) - $signed(smooth_nodes[node_index]);
    wire [4:0] build_index = build_x / SAMPLE_SPACING;
    wire [4:0] i0 = build_index == 0 ? 5'd0 : build_index-1'b1;
    wire [4:0] i2 = build_index == 31 ? 5'd31 : build_index+1'b1;
    wire [4:0] i3 = build_index >= 30 ? 5'd31 : build_index+2'd2;
    wire signed [15:0] p0 = {{4{smooth_nodes[i0][11]}}, smooth_nodes[i0]};
    wire signed [15:0] p1 = {{4{smooth_nodes[build_index][11]}}, smooth_nodes[build_index]};
    wire signed [15:0] p2 = {{4{smooth_nodes[i2][11]}}, smooth_nodes[i2]};
    wire signed [15:0] p3 = {{4{smooth_nodes[i3][11]}}, smooth_nodes[i3]};
    wire signed [15:0] q0=PIPELINED_GEOMETRY ? p0_q:p0;
    wire signed [15:0] q1=PIPELINED_GEOMETRY ? p1_q:p1;
    wire signed [15:0] q2=PIPELINED_GEOMETRY ? p2_q:p2;
    wire signed [15:0] q3=PIPELINED_GEOMETRY ? p3_q:p3;
    wire signed [15:0] three_q0=(q0<<<1)+q0, three_q1=(q1<<<1)+q1, three_q2=(q2<<<1)+q2;
    wire signed [24:0] product0 = h0 * $signed({1'b0, f0});
    wire signed [24:0] product1 = h1 * $signed({1'b0, f1});
    wire signed [24:0] product2 = h2 * $signed({1'b0, f2});
    wire signed [15:0] curve_raw = h3 / 16'sd96; // B 样条 /6，再将 Q4 转像素。
    wire signed [15:0] curve_clipped = geometric_raw > MAX_OFFSET ? MAX_OFFSET :
                                      geometric_raw < -MAX_OFFSET ? -MAX_OFFSET : geometric_raw;
    wire [Y_BITS-1:0] current_y = CENTER_Y - curve_clipped;
    wire [Y_BITS-1:0] top_y = (current_y < previous_y ? current_y : previous_y) - 9'd1;
    wire [Y_BITS-1:0] bottom_y = (current_y > previous_y ? current_y : previous_y) + 9'd1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            build_state <= B_IDLE; node_index <= 0; build_x <= 0;
            nodes_initialized <= 0; curve_valid <= 0;
            h0 <= 0; h1 <= 0; h2 <= 0; h3 <= 0;
            c1q <= 0; c2q0 <= 0; c2q1 <= 0;
            c3q0 <= 0; c3q1 <= 0; c3q2 <= 0;
            f0 <= 0; f1 <= 0; f2 <= 0; pipe_valid <= 0;
            x0 <= 0; x1 <= 0; x2 <= 0; x3 <= 0;
            x4<=0;x5<=0;x6<=0;magnitude_div32<=0;reciprocal_product<=0;sign4<=0;sign5<=0;quotient6<=0;
            p0_q<=0;p1_q<=0;p2_q<=0;p3_q<=0;node_target_q<=0;node_error_q<=0;fraction_q<=0;
            previous_y <= CENTER_Y;
        end else if (vs_pulse) begin
            // 采集 bank 在同一 VS 发布；下一拍才访问新的显示 bank。
            build_state <= PIPELINED_GEOMETRY ? B_NODE_FETCH:B_NODES;
            node_index <= 0; build_x <= 0; pipe_valid <= 0;
        end else begin
            pipe_valid <= {pipe_valid[5:0], build_state == B_LOAD};
            if (pipe_valid[0]) begin
                h1 <= product0/128 + c1q; f1 <= f0; x1 <= x0;
                c2q1 <= c2q0; c3q1 <= c3q0;
            end
            if (pipe_valid[1]) begin
                h2 <= product1/128 + c2q1; f2 <= f1; x2 <= x1; c3q2 <= c3q1;
            end
            if (pipe_valid[2]) begin h3 <= product2/128 + c3q2; x3 <= x2; end
            // floor(|h3|/96)=floor(floor(|h3|/32)/3)。u<=1024时
            // floor(u*683/2048)精确等于floor(u/3)，符号恢复保留向零截断。
            // 将长组合除法拆成三拍，曲线只在消隐期建立。
            if (pipe_valid[3]) begin magnitude_div32<=h3_magnitude>>5;sign4<=h3[15];x4<=x3;end
            if (pipe_valid[4]) begin reciprocal_product<=magnitude_div32*11'd683;sign5<=sign4;x5<=x4;end
            if (pipe_valid[5]) begin
                quotient6<=sign5 ? -$signed({5'd0,reciprocal_product[21:11]}) : $signed({5'd0,reciprocal_product[21:11]});
                x6<=x5;
            end
            if (geometry_valid) begin
                previous_y <= current_y;
                if (geometry_x == WAVE_WIDTH-1) build_state <= B_LAST;
            end
            case (build_state)
                B_NODE_FETCH: begin
                    node_target_q<=node_target;
                    node_error_q<=node_error;
                    build_state<=B_NODES;
                end
                B_NODES: begin
                    if (!nodes_initialized)
                        smooth_nodes[node_index] <= PIPELINED_GEOMETRY ? node_target_q:node_target;
                    else
                        smooth_nodes[node_index] <= smooth_nodes[node_index] +
                            (PIPELINED_GEOMETRY ? node_error_q/4:node_error/4);
                    if (node_index == 31) begin
                        nodes_initialized <= 1;
                        build_state <= PIPELINED_GEOMETRY ? B_FETCH:B_LOAD;
                    end else begin
                        node_index <= node_index + 1'b1;
                        if (PIPELINED_GEOMETRY) build_state<=B_NODE_FETCH;
                    end
                end
                B_FETCH: begin
                    // 查节点与系数运算分拍，避免地址mux、节点RAM和乘加串联。
                    p0_q<=p0;p1_q<=p1;p2_q<=p2;p3_q<=p3;
                    fraction_q<=build_index==31 ? 8'd0:((build_x%SAMPLE_SPACING)*128)/SAMPLE_SPACING;
                    build_state<=B_LOAD;
                end
                B_LOAD: begin
                    // 统一三次 B 样条，节点处二阶导数连续，非负权重抑制尖峰及过冲。
                    // 三拍乘加流水每拍输出一列；640列也能在不足700拍内构建完成。
                    h0 <= -q0+three_q1-three_q2+q3;
                    c1q <= three_q0-(three_q1<<<1)+three_q2;
                    c2q0 <= -three_q0+three_q2;
                    c3q0 <= q0+(q1<<<2)+q2;
                    f0 <= PIPELINED_GEOMETRY ? fraction_q :
                          build_index == 31 ? 8'd0 : ((build_x % SAMPLE_SPACING)*128)/SAMPLE_SPACING;
                    x0 <= build_x;
                    if (build_x == WAVE_WIDTH-1) build_state <= B_DRAIN;
                    else begin
                        build_x <= build_x+1'b1;
                        if(PIPELINED_GEOMETRY) build_state<=B_FETCH;
                    end
                end
                B_DRAIN: begin end // 等待流水最后一列落入表。
                B_LAST: begin
                    curve_valid <= 1;
                    build_state <= B_IDLE;
                end
                default: build_state <= B_IDLE;
            endcase
        end
    end

    wire in_wave_x = pixel_x >= WAVE_X && pixel_x < WAVE_X+WAVE_WIDTH;
    wire [9:0] local_x = in_wave_x ? pixel_x-WAVE_X : 10'd0;
    wire [CURVE_DW-1:0] bounds_q;
    wire table_write = (geometry_valid && geometry_x != 0) || build_state == B_LAST;
    wire [CURVE_AW-1:0] table_addr = build_state == B_LAST ? WAVE_WIDTH-1 : geometry_x-1'b1;
    wire [CURVE_DW-1:0] table_data = build_state == B_LAST ?
                           {previous_y+9'd1, previous_y-9'd1} : {bottom_y, top_y};
    // 安路推断器不能合并动态列与末列的两个写端口；显式单写端口块 RAM。
    // 仿真模型保持相同同步读时序，首张表完成前由 curve_valid 屏蔽。
`ifdef SIMULATION
    reg [CURVE_DW-1:0] curve_bounds [0:(1<<CURVE_AW)-1];
    reg [CURVE_DW-1:0] bounds_model;
    always @(posedge clk) begin
        if (table_write) curve_bounds[table_addr] <= table_data;
        bounds_model <= curve_bounds[local_x[CURVE_AW-1:0]];
    end
    assign bounds_q = bounds_model;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(CURVE_DW), .DATA_WIDTH_B(CURVE_DW),
        .ADDR_WIDTH_A(CURVE_AW), .ADDR_WIDTH_B(CURVE_AW),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .RESETMODE("ASYNC"), .IMPLEMENT("9K")
    ) u_curve_table (
        .dia(table_data), .addra(table_addr), .cea(1'b1), .ocea(1'b0),
        .clka(clk), .wea(table_write), .rsta(1'b0), .bea(1'b0), .doa(),
        .dib({CURVE_DW{1'b0}}), .addrb(local_x[CURVE_AW-1:0]), .ceb(1'b1), .oceb(1'b1),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0), .dob(bounds_q)
    );
`endif
    reg [23:0] rgb_q;
    reg [Y_BITS-1:0] y_q;
    reg in_wave_q, draw_q;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rgb_q <= 0; y_q <= 0; in_wave_q <= 0; draw_q <= 0;
        end else begin
            rgb_q <= rgb_in; y_q <= pixel_y; draw_q <= enable && de;
            in_wave_q <= in_wave_x && pixel_y >= WAVE_Y && pixel_y < WAVE_Y+WAVE_HEIGHT;
        end
    end
    wire wave_pixel = draw_q && in_wave_q && display_valid && curve_valid &&
                      y_q >= bounds_q[Y_BITS-1:0] && y_q <= bounds_q[CURVE_DW-1:Y_BITS];
    wire axis_pixel = draw_q && in_wave_q && y_q == CENTER_Y;
    // 保留采集/双bank发布，移除波形外孤立的峰值条；连续曲线边界不变。
    assign waveform_active = wave_pixel || axis_pixel;
    assign rgb_out = wave_pixel ? 24'h3BF0A5 : axis_pixel ? 24'h2A4E58 : rgb_q;

    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst && de && build_state != B_IDLE)
            $fatal(1, "Waveform build exceeds vertical blanking");
        if (!rst && vs_pulse && build_state != B_IDLE)
            $fatal(1, "Waveform build incomplete at next VS");
    end
    initial begin
        if (WAVE_WIDTH < SAMPLE_COUNT || WAVE_WIDTH % SAMPLE_COUNT != 0 ||
            WAVE_X < 0 || WAVE_X+WAVE_WIDTH > VIDEO_WIDTH || WAVE_HEIGHT < 4 ||
            WAVE_Y < 0 || WAVE_Y+WAVE_HEIGHT > VIDEO_HEIGHT || DECIMATE < 1 || DECIMATE > 256)
            $fatal(1, "Invalid waveform geometry or decimation");
    end
    // synthesis translate_on
endmodule
