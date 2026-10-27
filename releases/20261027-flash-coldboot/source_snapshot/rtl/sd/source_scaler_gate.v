// source_scaler_gate.v — 源帧事务与 scaler 启动隔离门
//
// 设计目的：
//   1. write_req_ack 来自存储器时钟域，必须经过两级同步；
//   2. 新事务在 write_req/write_req_ack 握手前，丢弃旧事务迟到的完成事件；
//   3. 只有本次源解析完成和本次源缓存写完成都到达后，才产生一次 scaler 启动；
//   4. scaler_start_toggle 在复位后清零，但 SD 卡 deinit/reinit 不改历史，避免 CDC 伪边沿。
module source_scaler_gate(
    input  wire clk,
    input  wire rst,
    input  wire sd_init_done,

    // 新源事务或源错误/重试事件。该脉冲优先级高于所有完成事件。
    // restart 后需有 write_req=0 的空闲拍；BMP 在重读文件头期间满足此条件。
    input  wire source_restart,
    input  wire source_done,

    // write_req 与本模块同属 SD 时钟域；write_req_ack 来自 mem_clk 域。
    input  wire write_req,
    input  wire write_req_ack,

    // 源缓存写完成事件，已经在本时钟域形成单拍脉冲。
    input  wire frame_write_finish_pulse,

    // 仅在本次事务成功时产生一次 scaler 启动。
    output reg  scaler_start_toggle,
    output reg  scaler_start_pulse,

    // 可选诊断输出：当前事务是否已通过 write_req/ack 握手。
    output wire transaction_active,
    output wire source_seen,
    output wire writer_seen
);

    localparam [2:0] S_WAIT_REARM = 3'd0;
    localparam [2:0] S_WAIT_REQ   = 3'd1;
    localparam [2:0] S_WAIT_ACK   = 3'd2;
    localparam [2:0] S_ACTIVE     = 3'd3;
    localparam [2:0] S_DONE       = 3'd4;

    reg [2:0] state;
    reg       ack_meta;
    reg       ack_sync;
    reg       ack_sync_d;
    reg       req_seen;
    reg       source_done_seen;
    reg       writer_done_seen;

    wire ack_rise = ack_sync && !ack_sync_d;
    wire ack_accept = (state == S_WAIT_ACK) && req_seen && ack_rise;

    assign transaction_active = (state == S_ACTIVE);
    assign source_seen       = source_done_seen;
    assign writer_seen       = writer_done_seen;

    // 只同步异步 ACK；ACK 即使在 write_req 撤销后才到达，也由 req_seen 保留握手上下文。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ack_meta   <= 1'b0;
            ack_sync   <= 1'b0;
            ack_sync_d <= 1'b0;
        end else begin
            ack_meta   <= write_req_ack;
            ack_sync   <= ack_meta;
            ack_sync_d <= ack_sync;
        end
    end

    always @(posedge clk or posedge rst) begin : gate_state
        reg next_source_seen;
        reg next_writer_seen;

        if (rst) begin
            state              <= S_WAIT_REARM;
            req_seen           <= 1'b0;
            source_done_seen   <= 1'b0;
            writer_done_seen   <= 1'b0;
            scaler_start_toggle<= 1'b0;
            scaler_start_pulse <= 1'b0;
        end else begin
            scaler_start_pulse <= 1'b0;

            // SD deinit 只撤销当前事务，不清除 toggle 历史。
            if (!sd_init_done) begin
                state            <= S_WAIT_REARM;
                req_seen         <= 1'b0;
                source_done_seen <= 1'b0;
                writer_done_seen <= 1'b0;
            end else if (source_restart) begin
                // 错误/重试或新装载优先：旧 writer/scaler 的迟到事件不能进入新事务。
                state            <= S_WAIT_REARM;
                req_seen         <= 1'b0;
                source_done_seen <= 1'b0;
                writer_done_seen <= 1'b0;
            end else begin
                case (state)
                    S_WAIT_REARM: begin
                        // 既等请求撤销，也等同步后的旧 ACK 回到低电平，形成干净起点。
                        req_seen         <= 1'b0;
                        source_done_seen <= 1'b0;
                        writer_done_seen <= 1'b0;
                        if (!write_req && !ack_meta && !ack_sync && !ack_sync_d)
                            state <= S_WAIT_REQ;
                    end

                    S_WAIT_REQ: begin
                        if (write_req) begin
                            req_seen <= 1'b1;
                            state    <= S_WAIT_ACK;
                        end
                    end

                    S_WAIT_ACK: begin
                        // 请求保持期间或 ACK 延迟期间都保留 req_seen。
                        if (write_req)
                            req_seen <= 1'b1;
                        if (ack_accept) begin
                            state            <= S_ACTIVE;
                            next_source_seen = source_done;
                            next_writer_seen = frame_write_finish_pulse;
                            source_done_seen <= next_source_seen;
                            writer_done_seen <= next_writer_seen;
                            if (next_source_seen && next_writer_seen) begin
                                scaler_start_pulse  <= 1'b1;
                                scaler_start_toggle <= ~scaler_start_toggle;
                                state                <= S_DONE;
                                source_done_seen    <= 1'b0;
                                writer_done_seen    <= 1'b0;
                            end
                        end
                    end

                    S_ACTIVE: begin
                        next_source_seen = source_done_seen || source_done;
                        next_writer_seen = writer_done_seen || frame_write_finish_pulse;
                        source_done_seen <= next_source_seen;
                        writer_done_seen <= next_writer_seen;
                        if (next_source_seen && next_writer_seen) begin
                            scaler_start_pulse  <= 1'b1;
                            scaler_start_toggle <= ~scaler_start_toggle;
                            state                <= S_DONE;
                            source_done_seen    <= 1'b0;
                            writer_done_seen    <= 1'b0;
                        end
                    end

                    S_DONE: begin
                        // 事务结束后忽略重复完成脉冲，直到下一次 source_restart。
                        state <= S_DONE;
                    end

                    default: begin
                        state            <= S_WAIT_REARM;
                        req_seen         <= 1'b0;
                        source_done_seen <= 1'b0;
                        writer_done_seen <= 1'b0;
                    end
                endcase
            end
        end
    end
endmodule
