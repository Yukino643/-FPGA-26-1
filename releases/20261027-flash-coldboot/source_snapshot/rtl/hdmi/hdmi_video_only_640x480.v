// Lightweight DVI-compatible video path for HDMI-A.
// HDMI-A is a diagnostic monitor and carries no audio, EDID transaction or
// data-island packet.  It therefore needs only three TMDS encoders plus the
// fixed TMDS clock symbol, which removes the second transmitter's BRAM FIFOs.
module hdmi_video_only_640x480(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       hsync,
    input  wire       vsync,
    input  wire       de,
    input  wire [23:0] rgb,
    output wire [9:0] ch0_symbol,
    output wire [9:0] ch1_symbol,
    output wire [9:0] ch2_symbol,
    output reg  [9:0] clk_symbol
);
    wire [1:0] control = {vsync, hsync};

    hdmi_tmds_channel_encoder #(.CHANNEL(0)) u_ch0 (
        .clk(clk), .rst_n(rst_n), .video_enable(de),
        .video_data(rgb[7:0]), .control_data(control), .symbol(ch0_symbol)
    );
    hdmi_tmds_channel_encoder #(.CHANNEL(1)) u_ch1 (
        .clk(clk), .rst_n(rst_n), .video_enable(de),
        .video_data(rgb[15:8]), .control_data(2'b00), .symbol(ch1_symbol)
    );
    hdmi_tmds_channel_encoder #(.CHANNEL(2)) u_ch2 (
        .clk(clk), .rst_n(rst_n), .video_enable(de),
        .video_data(rgb[23:16]), .control_data(2'b00), .symbol(ch2_symbol)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_symbol <= 10'b0000011111;
        else
            clk_symbol <= 10'b0000011111;
    end
endmodule
