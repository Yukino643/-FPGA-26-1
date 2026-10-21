// monitor_config_regs.v - CDC mailbox for HDMI-B display options.
// The committed payload is held until ACK; shadow is display preview only.
// The video domain samples it twice and applies it only at vertical blanking.
module monitor_config_regs(
    input  wire       video_clk,
    input  wire       video_rst,
    input  wire       vs_rise,
    input  wire [3:0] cfg_shadow_sd,
    input  wire [3:0] cfg_payload_sd,
    input  wire [9:0] screen_shadow_sd,
    input  wire [9:0] screen_payload_sd,
    input  wire [4:0] subtitle_shadow_sd,
    input  wire [4:0] subtitle_payload_sd,
    input  wire       cfg_commit_toggle_sd,
    output reg  [3:0] cfg_active_video,
    output reg  [3:0] cfg_preview_video,
    output reg  [9:0] screen_active_video,
    output reg  [9:0] screen_preview_video,
    output reg  [4:0] subtitle_active_video,
    output reg  [4:0] subtitle_preview_video,
    output reg        cfg_commit_seen_video,
    output reg        cfg_applied_toggle_video
);
    reg [2:0] commit_sync;
    reg [3:0] payload_sync1, payload_sync2;
    reg [3:0] preview_sync1;
    reg [9:0] screen_payload_sync1, screen_payload_sync2, screen_preview_sync1;
    reg [4:0] subtitle_payload_sync1, subtitle_payload_sync2, subtitle_preview_sync1;
    reg commit_pending;

    always @(posedge video_clk or posedge video_rst) begin
        if (video_rst) begin
            commit_sync <= 3'b000;
            payload_sync1 <= 4'b0111;
            payload_sync2 <= 4'b0111;
            preview_sync1 <= 4'b0111;
            commit_pending <= 1'b0;
            cfg_active_video <= 4'b0111;
            cfg_preview_video <= 4'b0111;
            screen_payload_sync1 <= 10'h144;
            screen_payload_sync2 <= 10'h144;
            screen_preview_sync1 <= 10'h144;
            screen_active_video <= 10'h144;
            screen_preview_video <= 10'h144;
            subtitle_payload_sync1 <= 5'h08;
            subtitle_payload_sync2 <= 5'h08;
            subtitle_preview_sync1 <= 5'h08;
            subtitle_active_video <= 5'h08;
            subtitle_preview_video <= 5'h08;
            cfg_commit_seen_video <= 1'b0;
            cfg_applied_toggle_video <= 1'b0;
        end else begin
            commit_sync <= {commit_sync[1:0], cfg_commit_toggle_sd};
            payload_sync1 <= cfg_payload_sd;
            payload_sync2 <= payload_sync1;
            preview_sync1 <= cfg_shadow_sd;
            cfg_preview_video <= preview_sync1;
            screen_payload_sync1 <= screen_payload_sd;
            screen_payload_sync2 <= screen_payload_sync1;
            screen_preview_sync1 <= screen_shadow_sd;
            screen_preview_video <= screen_preview_sync1;
            subtitle_payload_sync1 <= subtitle_payload_sd;
            subtitle_payload_sync2 <= subtitle_payload_sync1;
            subtitle_preview_sync1 <= subtitle_shadow_sd;
            subtitle_preview_video <= subtitle_preview_sync1;
            cfg_commit_seen_video <= 1'b0;
            if (commit_sync[2] ^ commit_sync[1])
                commit_pending <= 1'b1;
            if (vs_rise && commit_pending) begin
                cfg_active_video <= payload_sync2;
                screen_active_video <= screen_payload_sync2;
                subtitle_active_video <= subtitle_payload_sync2;
                cfg_commit_seen_video <= 1'b1;
                cfg_applied_toggle_video <= commit_sync[2];
                commit_pending <= 1'b0;
            end
        end
    end
endmodule
