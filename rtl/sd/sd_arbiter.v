// sd_arbiter.v — BMP/WAV 共享 SD 单扇区读仲裁器
// 请求方保持 req 到 done；仲裁器每完成一个扇区必须等待该请求释放，防止重复发起。
module sd_arbiter #(
    parameter integer TIMEOUT_CYCLES = 10_000_000
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        a_req,
    input  wire [31:0] a_addr,
    output reg         a_ack,
    output reg  [7:0]  a_data,
    output reg         a_data_valid,
    output reg         a_done,
    output reg         a_timeout,

    input  wire        b_req,
    input  wire [31:0] b_addr,
    output reg         b_ack,
    output reg  [7:0]  b_data,
    output reg         b_data_valid,
    output reg         b_done,
    output reg         b_timeout,

    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output reg         controller_reset_req,
    output reg  [1:0]  owner
);
    localparam S_IDLE       = 3'd0;
    localparam S_A_ACTIVE   = 3'd1;
    localparam S_A_RELEASE  = 3'd2;
    localparam S_B_ACTIVE   = 3'd3;
    localparam S_B_RELEASE  = 3'd4;

    reg [2:0] state;
    reg [31:0] timeout_cnt;
    reg last_grant_b;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                <= S_IDLE;
            timeout_cnt          <= 32'd0;
            last_grant_b         <= 1'b0;
            a_ack                <= 1'b0;
            a_data               <= 8'd0;
            a_data_valid         <= 1'b0;
            a_done               <= 1'b0;
            a_timeout            <= 1'b0;
            b_ack                <= 1'b0;
            b_data               <= 8'd0;
            b_data_valid         <= 1'b0;
            b_done               <= 1'b0;
            b_timeout            <= 1'b0;
            sd_sec_read          <= 1'b0;
            sd_sec_read_addr     <= 32'd0;
            controller_reset_req <= 1'b0;
            owner                <= 2'd0;
        end else begin
            a_ack                <= 1'b0;
            a_data_valid         <= 1'b0;
            a_done               <= 1'b0;
            a_timeout            <= 1'b0;
            b_ack                <= 1'b0;
            b_data_valid         <= 1'b0;
            b_done               <= 1'b0;
            b_timeout            <= 1'b0;
            sd_sec_read          <= 1'b0;
            controller_reset_req <= 1'b0;

            case (state)
                S_IDLE: begin
                    timeout_cnt <= 32'd0;
                    owner <= 2'd0;
                    // 两方同时等待时轮转，避免长时间图片扫描饿死 WAV。
                    if (a_req && (!b_req || last_grant_b)) begin
                        sd_sec_read      <= 1'b1;
                        sd_sec_read_addr <= a_addr;
                        a_ack            <= 1'b1;
                        owner            <= 2'd1;
                        last_grant_b     <= 1'b0;
                        state            <= S_A_ACTIVE;
                    end else if (b_req) begin
                        sd_sec_read      <= 1'b1;
                        sd_sec_read_addr <= b_addr;
                        b_ack            <= 1'b1;
                        owner            <= 2'd2;
                        last_grant_b     <= 1'b1;
                        state            <= S_B_ACTIVE;
                    end
                end

                S_A_ACTIVE: begin
                    owner <= 2'd1;
                    if (sd_sec_read_data_valid) begin
                        a_data       <= sd_sec_read_data;
                        a_data_valid <= 1'b1;
                    end
                    if (sd_sec_read_end) begin
                        a_done <= 1'b1;
                        state  <= S_A_RELEASE;
                    end else if (timeout_cnt >= TIMEOUT_CYCLES - 1) begin
                        a_done               <= 1'b1;
                        a_timeout            <= 1'b1;
                        controller_reset_req <= 1'b1;
                        state                <= S_A_RELEASE;
                    end else begin
                        timeout_cnt <= timeout_cnt + 32'd1;
                    end
                end

                S_A_RELEASE: begin
                    owner <= 2'd0;
                    if (!a_req)
                        state <= S_IDLE;
                end

                S_B_ACTIVE: begin
                    owner <= 2'd2;
                    if (sd_sec_read_data_valid) begin
                        b_data       <= sd_sec_read_data;
                        b_data_valid <= 1'b1;
                    end
                    if (sd_sec_read_end) begin
                        b_done <= 1'b1;
                        state  <= S_B_RELEASE;
                    end else if (timeout_cnt >= TIMEOUT_CYCLES - 1) begin
                        b_done               <= 1'b1;
                        b_timeout            <= 1'b1;
                        controller_reset_req <= 1'b1;
                        state                <= S_B_RELEASE;
                    end else begin
                        timeout_cnt <= timeout_cnt + 32'd1;
                    end
                end

                S_B_RELEASE: begin
                    owner <= 2'd0;
                    if (!b_req)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
