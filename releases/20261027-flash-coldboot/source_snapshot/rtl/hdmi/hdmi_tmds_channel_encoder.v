// HDMI/DVI TMDS video encoder.
// The monitor output has no audio/data-island requirement, so this encoder
// only implements active-video and control-period symbols.  Keeping the
// running disparity local to each channel avoids the BRAM-heavy packet path
// in the general HDMI 1.4 transmitter.
module hdmi_tmds_channel_encoder #(
    parameter integer CHANNEL = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       video_enable,
    input  wire [7:0] video_data,
    input  wire [1:0] control_data,
    output reg  [9:0] symbol
);
    reg signed [5:0] disparity;
    reg signed [5:0] next_disparity;
    wire [8:0] q_m_input;
    reg [8:0] q_m;
    reg enable_q;
    reg [1:0] control_q;
    reg [9:0] video_symbol;
    reg [3:0] data_ones;
    reg [3:0] q_m_ones;
    reg signed [5:0] balance;
    reg use_xnor;
    integer index;

    always @* begin
        data_ones = 4'd0;
        for (index = 0; index < 8; index = index + 1)
            data_ones = data_ones + video_data[index];

        use_xnor = data_ones > 4 ||
                   (data_ones == 4 && video_data[0] == 1'b0);
    end
    // 前缀异或允许综合器平衡逻辑树；与逐位递推的 TMDS 变换等价。
    assign q_m_input[8] = !use_xnor;
    genvar bit_index;
    generate for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin : g_prefix
        assign q_m_input[bit_index] = (^video_data[bit_index:0]) ^
                                     (use_xnor && (bit_index % 2));
    end endgenerate

    always @* begin
        q_m_ones = 4'd0;
        for (index = 0; index < 8; index = index + 1)
            q_m_ones = q_m_ones + q_m[index];
        balance = $signed({1'b0, q_m_ones, 1'b0}) - 6'sd8;

        if (disparity == 0 || balance == 0) begin
            video_symbol[9] = !q_m[8];
            video_symbol[8] = q_m[8];
            video_symbol[7:0] = q_m[8] ? q_m[7:0] : ~q_m[7:0];
            next_disparity = q_m[8] ? disparity + balance :
                                     disparity - balance;
        end else if ((disparity > 0 && balance > 0) ||
                     (disparity < 0 && balance < 0)) begin
            video_symbol = {1'b1, q_m[8], ~q_m[7:0]};
            next_disparity = disparity - balance +
                             (q_m[8] ? 6'sd2 : 6'sd0);
        end else begin
            video_symbol = {1'b0, q_m[8], q_m[7:0]};
            next_disparity = disparity + balance -
                             (q_m[8] ? 6'sd0 : 6'sd2);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            symbol <= 10'b1101010100;
            disparity <= 6'sd0;
        end else if (enable_q) begin
            symbol <= video_symbol;
            disparity <= next_disparity;
        end else begin
            disparity <= 6'sd0;
            if (CHANNEL == 0) begin
                case (control_q)
                    2'b00: symbol <= 10'b1101010100;
                    2'b01: symbol <= 10'b0010101011;
                    2'b10: symbol <= 10'b0101010100;
                    default: symbol <= 10'b1010101011;
                endcase
            end else begin
                symbol <= 10'b1101010100;
            end
        end
    end

    // 像素、有效位和控制符同步延迟一拍，三通道保持一致。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_m <= 9'd0;
            enable_q <= 1'b0;
            control_q <= 2'd0;
        end else begin
            q_m <= q_m_input;
            enable_q <= video_enable;
            control_q <= control_data;
        end
    end
endmodule
