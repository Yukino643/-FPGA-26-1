// 帧流发布：完整页才能进入邮箱，每6个60Hz VS更新一次；慢帧保持，不追赶。
module video_frame_commit #(
    parameter integer VS_PER_FRAME=6,
    parameter PAUSE_ENABLE=0,
    parameter AUDIO_ENABLE=0
)(
    input wire clk, rst, vs_rise,
    input wire pause,
    input wire audio_mode, audio_ready, audio_frame_done,
    input wire ready_pulse,
    input wire [1:0] ready_buf,
    output wire [20:0] page_base,
    output reg hold_load,
    output reg displayed,
    output reg applied_pulse
    ,output wire will_apply
);
    reg pending, front;
    reg [1:0] pending_buf;
    reg [2:0] phase;
    assign page_base=front ? 21'h80000 : 21'd0;
    assign will_apply=vs_rise && !(PAUSE_ENABLE && pause) && pending &&
        (!displayed || phase>=VS_PER_FRAME-1) &&
        (!(AUDIO_ENABLE && audio_mode) || (displayed ? audio_frame_done : audio_ready));
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            pending<=0; front<=0; pending_buf<=0; phase<=0;
            hold_load<=0; displayed<=0; applied_pulse<=0;
        end else begin
            applied_pulse<=0;
            if(ready_pulse && !pending) begin
                pending<=1; pending_buf<=ready_buf; hold_load<=1;
            end
            if(vs_rise && !(PAUSE_ENABLE && pause)) begin
                if(displayed && phase<VS_PER_FRAME-1) phase<=phase+1'b1;
                if(will_apply) begin
                    front<=pending_buf[0]; displayed<=1; applied_pulse<=1;
                    pending<=0; hold_load<=0; phase<=0;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(VS_PER_FRAME<2 || VS_PER_FRAME>8) $fatal(1,"Invalid video interval");
    always @(posedge clk) if(!rst && ready_pulse && pending)
        $fatal(1,"Video ready mailbox overwritten");
    // synthesis translate_on
endmodule
