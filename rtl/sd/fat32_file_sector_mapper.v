// 将 BMP 解析器的逻辑文件扇区请求转换成 FAT32 物理 LBA。
module fat32_file_sector_mapper #(
    parameter integer MAX_CHAIN_STEPS = 32768,
    parameter integer TIMEOUT_CYCLES = 11_000_000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        file_start,
    input  wire [31:0] first_cluster,
    input  wire [31:0] file_size,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [2:0]  sectors_per_cluster_shift,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,
    input  wire        client_req,
    input  wire [31:0] client_sector_index,
    output wire        busy,
    output reg         client_done,
    output reg         client_error,
    output wire [7:0]  client_data,
    output wire        client_data_valid,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [8:0]  sector_byte_index,
    input  wire [7:0]  sector_byte,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);
    localparam [7:0] ERR_NONE       = 8'h00;
    localparam [7:0] ERR_CLUSTER    = 8'h24;
    localparam [7:0] ERR_EARLY_EOC  = 8'h25;
    localparam [7:0] ERR_CHAIN_LOOP = 8'h26;
    localparam [7:0] ERR_TIMEOUT    = 8'h30;
    localparam [7:0] ERR_SECTOR     = 8'h31;

    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_CHECK       = 4'd1;
    localparam [3:0] ST_FAT_REQ     = 4'd2;
    localparam [3:0] ST_FAT_WAIT    = 4'd3;
    localparam [3:0] ST_FAT_PARSE   = 4'd4;
    localparam [3:0] ST_DATA_REQ    = 4'd5;
    localparam [3:0] ST_DATA_WAIT   = 4'd6;
    localparam [3:0] ST_WAIT_RELEASE= 4'd7;
    localparam [3:0] ST_REQUEST_PREP= 4'd8;
    localparam [3:0] ST_DATA_SHIFT  = 4'd9;
    localparam [3:0] ST_DATA_BASE   = 4'd10;
    localparam [3:0] ST_DATA_OFFSET = 4'd11;

    reg [3:0] state;
    reg [31:0] first_cluster_r;
    reg [23:0] file_sector_count_r;
    reg [7:0] sectors_per_cluster_r;
    reg [2:0] spc_shift_r;
    reg [31:0] fat_start_lba_r;
    reg [31:0] data_start_lba_r;
    reg [31:0] max_cluster_r;

    reg [31:0] current_cluster;
    reg [31:0] current_cluster_index;
    reg [31:0] requested_sector;
    reg [31:0] chain_steps;
    reg [8:0] fat_entry_offset;
    reg [7:0] fat_byte0, fat_byte1, fat_byte2, fat_byte3;
    reg [31:0] timeout_count;

    wire wait_sector = (state == ST_FAT_WAIT) || (state == ST_DATA_WAIT);
    wire timeout_hit = wait_sector && !sector_done &&
                       (timeout_count >= TIMEOUT_CYCLES - 1);
    reg request_invalid;
    reg [31:0] desired_cluster_index;
    reg [6:0] desired_sector_in_cluster;
    wire [31:0] next_cluster_value =
        {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
    assign busy = (state != ST_IDLE);
    assign client_data = sector_byte;
    assign client_data_valid = (state == ST_DATA_WAIT) && sector_valid;

    task finish_with_error;
        input [7:0] error_value;
        begin
            client_done <= 1'b1;
            client_error <= (error_value != ERR_NONE);
            state <= ST_WAIT_RELEASE;
        end
    endtask

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            first_cluster_r <= 32'd0;
            file_sector_count_r <= 24'd0;
            sectors_per_cluster_r <= 8'd0;
            spc_shift_r <= 3'd0;
            fat_start_lba_r <= 32'd0;
            data_start_lba_r <= 32'd0;
            max_cluster_r <= 32'd0;
            current_cluster <= 32'd0;
            current_cluster_index <= 32'd0;
            requested_sector <= 32'd0;
            request_invalid <= 1'b0;
            desired_cluster_index <= 32'd0;
            desired_sector_in_cluster <= 7'd0;
            chain_steps <= 32'd0;
            fat_entry_offset <= 9'd0;
            fat_byte0 <= 8'd0; fat_byte1 <= 8'd0;
            fat_byte2 <= 8'd0; fat_byte3 <= 8'd0;
            timeout_count <= 32'd0;
            client_done <= 1'b0;
            client_error <= 1'b0;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
        end else begin
            client_done <= 1'b0;
            client_error <= 1'b0;
            sector_req <= 1'b0;

            if (wait_sector && !sector_done) begin
                if (timeout_count < TIMEOUT_CYCLES)
                    timeout_count <= timeout_count + 1'b1;
            end else begin
                timeout_count <= 32'd0;
            end

            if (sector_valid && state == ST_FAT_WAIT) begin
                if (sector_byte_index == fat_entry_offset)
                    fat_byte0 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 9'd1)
                    fat_byte1 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 9'd2)
                    fat_byte2 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 9'd3)
                    fat_byte3 <= sector_byte;
            end

            if (file_start) begin
                first_cluster_r <= first_cluster;
                file_sector_count_r <= {1'b0, file_size[31:9]} +
                                       {{23{1'b0}}, (|file_size[8:0])};
                sectors_per_cluster_r <= sectors_per_cluster;
                spc_shift_r <= sectors_per_cluster_shift;
                fat_start_lba_r <= fat_start_lba;
                data_start_lba_r <= data_start_lba;
                max_cluster_r <= max_cluster;
                current_cluster <= first_cluster;
                current_cluster_index <= 32'd0;
                requested_sector <= 32'd0;
                chain_steps <= 32'd1;
                if (state == ST_IDLE || state == ST_WAIT_RELEASE)
                    state <= ST_IDLE;
            end else if (timeout_hit) begin
                finish_with_error(ERR_TIMEOUT);
            end else begin
                case (state)
                    ST_IDLE: if (client_req) begin
                        requested_sector <= client_sector_index;
                        state <= ST_REQUEST_PREP;
                    end
                    // 请求先锁存，再计算边界与簇内位置；后续FAT遍历复用这些稳定结果，
                    // 不让32位移位/范围比较继续串入LBA和错误输出的公共使能。
                    ST_REQUEST_PREP: begin
                        request_invalid <= (file_sector_count_r == 0) ||
                            (sectors_per_cluster_r == 0) ||
                            ({1'b0, requested_sector} >= {9'd0, file_sector_count_r}) ||
                            (first_cluster_r < 2) || (first_cluster_r > max_cluster_r);
                        desired_cluster_index <= requested_sector >> spc_shift_r;
                        desired_sector_in_cluster <= requested_sector[6:0] &
                                                     (sectors_per_cluster_r[6:0] - 7'd1);
                        state <= ST_CHECK;
                    end
                    ST_CHECK: begin
                        if (request_invalid) begin
                            finish_with_error(ERR_CLUSTER);
                        end else if (desired_cluster_index < current_cluster_index) begin
                            current_cluster <= first_cluster_r;
                            current_cluster_index <= 32'd0;
                            chain_steps <= 32'd1;
                        end else if (desired_cluster_index > current_cluster_index) begin
                            if (chain_steps >= MAX_CHAIN_STEPS) begin
                                finish_with_error(ERR_CHAIN_LOOP);
                            end else begin
                                fat_entry_offset <= {current_cluster[6:0], 2'b00};
                                sector_lba <= fat_start_lba_r + (current_cluster >> 7);
                                state <= ST_FAT_REQ;
                            end
                        end else if ((current_cluster < 2) ||
                                     (current_cluster > max_cluster_r)) begin
                            finish_with_error(ERR_CLUSTER);
                        end else begin
                            // 复用地址寄存器拆开减法、移位和两次加法，避免100MHz下串联。
                            // 中间值不发sector_req；仅最终LBA稳定后才进入请求状态。
                            sector_lba <= current_cluster - 32'd2;
                            state <= ST_DATA_SHIFT;
                        end
                    end
                    ST_DATA_SHIFT: begin
                        sector_lba <= sector_lba << spc_shift_r;
                        state <= ST_DATA_BASE;
                    end
                    ST_DATA_BASE: begin
                        sector_lba <= data_start_lba_r + sector_lba;
                        state <= ST_DATA_OFFSET;
                    end
                    ST_DATA_OFFSET: begin
                        sector_lba <= sector_lba + desired_sector_in_cluster;
                        state <= ST_DATA_REQ;
                    end
                    ST_FAT_REQ: if (!sector_busy) begin
                        sector_req <= 1'b1;
                        state <= ST_FAT_WAIT;
                    end
                    ST_FAT_WAIT: if (sector_done) begin
                        if (sector_error != 0)
                            finish_with_error(ERR_SECTOR);
                        else
                            state <= ST_FAT_PARSE;
                    end
                    ST_FAT_PARSE: begin
                        if (next_cluster_value >= 28'hffffff8) begin
                            finish_with_error(ERR_EARLY_EOC);
                        end else if ((next_cluster_value < 2) ||
                                     (next_cluster_value > max_cluster_r)) begin
                            finish_with_error(ERR_CLUSTER);
                        end else if (next_cluster_value == current_cluster) begin
                            finish_with_error(ERR_CHAIN_LOOP);
                        end else begin
                            current_cluster <= next_cluster_value;
                            current_cluster_index <= current_cluster_index + 1'b1;
                            chain_steps <= chain_steps + 1'b1;
                            state <= ST_CHECK;
                        end
                    end
                    ST_DATA_REQ: if (!sector_busy) begin
                        sector_req <= 1'b1;
                        state <= ST_DATA_WAIT;
                    end
                    ST_DATA_WAIT: if (sector_done) begin
                        if (sector_error != 0) begin
                            finish_with_error(ERR_SECTOR);
                        end else begin
                            client_done <= 1'b1;
                            client_error <= 1'b0;
                            state <= ST_WAIT_RELEASE;
                        end
                    end
                    ST_WAIT_RELEASE: if (!client_req)
                        state <= ST_IDLE;
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
