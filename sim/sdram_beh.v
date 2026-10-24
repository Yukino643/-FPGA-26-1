// sdram_beh.v — sdr_as_ram App 口行为级模型（仿真专用）
// 写: 当拍入存储；读: 记录 en 拍的地址序列，末拍后 LAT 拍开始按序返还存储内容
// 单簇在途（mem_mpu 保证），地址即索引
`timescale 1ns/1ps
module sdram_beh #(
    parameter LAT = 8
)(
    input  wire        clk,
    input  wire        rst,
    // 写口
    input  wire        wr_en,
    input  wire [20:0] wr_addr,
    input  wire [31:0] wr_data,
    input  wire [3:0]  wr_dm,
    // 读口
    input  wire        rd_en,
    input  wire [20:0] rd_addr,
    output reg         rd_vld,
    output reg  [31:0] rd_dout
);

    reg [31:0] mem [0:2**21-1];

    reg  [20:0] cap [0:255];
    integer     cap_n = 0, sent = 0, timer = -1;
    reg         en_d = 0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_vld <= 0; rd_dout <= 0;
            cap_n <= 0; sent <= 0; timer <= -1; en_d <= 0;
        end else begin
            // 单端口控制器：在读命令/返回尚未收尾时写入，板上可能丢命令或破坏数据。
            if (wr_en && (rd_en || en_d || cap_n != 0 || rd_vld)) begin
                $display("FAIL SDRAM read/write ownership collision");
                $fatal(1);
            end
            en_d <= rd_en;
            if (wr_en) begin
                if (!wr_dm[0]) mem[wr_addr][7:0]   <= wr_data[7:0];
                if (!wr_dm[1]) mem[wr_addr][15:8]  <= wr_data[15:8];
                if (!wr_dm[2]) mem[wr_addr][23:16] <= wr_data[23:16];
                if (!wr_dm[3]) mem[wr_addr][31:24] <= wr_data[31:24];
            end

            if (rd_en) begin
                cap[cap_n] <= rd_addr;
                cap_n <= cap_n + 1;
                timer <= LAT;
                rd_vld <= 0;
            end else if (en_d) begin
                timer <= LAT;            // 末拍后启动延迟
            end else if (timer >= 0) begin
                if (timer == 0) begin
                    if (sent < cap_n) begin
                        rd_vld  <= 1'b1;
                        rd_dout <= mem[cap[sent]];
                        sent    <= sent + 1;
                    end else begin
                        rd_vld <= 1'b0;
                        cap_n  <= 0;
                        sent   <= 0;
                        timer  <= -1;
                    end
                end else begin
                    timer <= timer - 1;
                    rd_vld <= 1'b0;
                end
            end else begin
                rd_vld <= 1'b0;
            end
        end
    end

endmodule
