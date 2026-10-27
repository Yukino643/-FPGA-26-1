// 运行时媒体切换：停止新帧 -> VS黑场 -> 排空实际突发 -> 两端复位握手。
// 请求/应答均为持久电平；mode在复位保持时更新，至下一次切换保持不变。
module media_runtime_ctrl # (parameter DEFAULT_VIDEO=0)(
    input wire sd_clk, mem_clk, video_clk,
    input wire rst_sd, rst_mem, rst_video,
    input wire requested_video, requested_pause,
    input wire source_idle, storage_idle, pipeline_idle,
    input wire vs_rise,
    output reg active_video,
    output wire busy, hold_source,
    output wire media_rst_sd, media_rst_mem, media_rst_video,
    output wire drain_mem,
    output reg blank_video,
    output reg video_mode, pause_video,
    output wire switching_video
);
    localparam RUN=0, STOP=1, BLANK=2, DRAIN=3, RESET=4, RELEASE=5, RESUME=6;
    reg [2:0] state;
    reg target, reset_req;
    wire blank_req=(state>=BLANK && state<=RELEASE);
    wire drain_req=(state>=DRAIN && state<=RELEASE);
    assign busy=state!=RUN;
    // 同拍发现请求就阻止新帧，避免STOP前多启动一次预取。
    assign hold_source=busy || requested_video!=active_video;
    reset_sync rs(.clk(sd_clk),.arst(rst_sd|reset_req),.rst(media_rst_sd));
    reset_sync rm(.clk(mem_clk),.arst(rst_mem|reset_req),.rst(media_rst_mem));
    reset_sync rv(.clk(video_clk),.arst(rst_video|reset_req),.rst(media_rst_video));
    reg [1:0] drain_sync, blank_sync, mode_sync, pause_sync, busy_sync;
    // 已同步的停止请求：收尾页不能等待已被停止的音频生产者。
    assign switching_video=busy_sync[1];
    reg drain_ack;
    assign drain_mem=drain_sync[1];
    always @(posedge mem_clk or posedge rst_mem) begin
        if(rst_mem) begin drain_sync<=0;drain_ack<=0;end
        else begin
            drain_sync<={drain_sync[0],drain_req};
            if(!drain_sync[1]) drain_ack<=0;
            else if(storage_idle) drain_ack<=1;
        end
    end
    always @(posedge video_clk or posedge rst_video) begin
        if(rst_video) begin
            blank_sync<=0;mode_sync<={2{DEFAULT_VIDEO!=0}};pause_sync<=0;busy_sync<=0;
            blank_video<=0;video_mode<=DEFAULT_VIDEO;pause_video<=0;
        end else begin
            blank_sync<={blank_sync[0],blank_req};
            mode_sync<={mode_sync[0],active_video};
            pause_sync<={pause_sync[0],requested_pause};
            busy_sync<={busy_sync[0],hold_source};
            if(media_rst_video) video_mode<=mode_sync[1];
            if(vs_rise) begin
                blank_video<=blank_sync[1];
                // 切换时必须放行暂停邮箱，否则完整待提交页将无法释放。
                pause_video<=pause_sync[1] && !busy_sync[1];
            end
        end
    end
    reg [1:0] blank_ack_sync,drain_ack_sync,mem_reset_sync,video_reset_sync;
    always @(posedge sd_clk or posedge rst_sd) begin
        if(rst_sd) begin
            state<=RUN;target<=DEFAULT_VIDEO;active_video<=DEFAULT_VIDEO;reset_req<=0;
            blank_ack_sync<=0;drain_ack_sync<=0;mem_reset_sync<=2'b11;video_reset_sync<=2'b11;
        end else begin
            blank_ack_sync<={blank_ack_sync[0],blank_video};
            drain_ack_sync<={drain_ack_sync[0],drain_ack};
            mem_reset_sync<={mem_reset_sync[0],media_rst_mem};
            video_reset_sync<={video_reset_sync[0],media_rst_video};
            case(state)
                RUN: if(requested_video!=active_video) begin target<=requested_video;state<=STOP;end
                STOP: if(source_idle && pipeline_idle) state<=BLANK;
                BLANK: if(blank_ack_sync[1]) state<=DRAIN;
                DRAIN: if(drain_ack_sync[1]) begin
                    reset_req<=1;active_video<=target;state<=RESET;
                end
                RESET: if(mem_reset_sync[1] && video_reset_sync[1]) begin reset_req<=0;state<=RELEASE;end
                RELEASE: if(!mem_reset_sync[1] && !video_reset_sync[1] && !media_rst_sd) state<=RESUME;
                // RESUME释放请求，但等待返回低电平，不能沿用上次ACK。
                RESUME: if(!blank_ack_sync[1] && !drain_ack_sync[1]) state<=RUN;
                default: begin state<=RUN;reset_req<=0;end
            endcase
        end
    end
endmodule
