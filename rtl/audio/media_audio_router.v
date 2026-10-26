// 原轨尾部使用独立FAT簇链游标。与视频逐扇区仲裁，不假定TF文件连续。
module media_audio_router(
    input wire clk,rst,video_mode,metadata_ready,
    input wire [31:0] first_cluster,file_size,fat_lba,data_lba,max_cluster,
    input wire [7:0] spc,
    input wire [2:0] spc_shift,
    input wire reader_req,
    input wire [31:0] reader_sector,
    output wire [7:0] reader_data,
    output wire reader_valid,reader_done,reader_error,idle,
    output wire physical_req,
    output wire [31:0] physical_addr,
    input wire [7:0] physical_data,
    input wire physical_valid,physical_done,physical_error
);
    reg opened,req;
    reg [31:0] addr;
    reg [8:0] byte_index;
    wire map_req,map_busy,map_valid,map_done,map_error;
    wire [31:0] map_addr;
    wire [7:0] map_data;
    wire file_start=metadata_ready && !opened;
    assign physical_req=video_mode ? req : reader_req;
    assign physical_addr=video_mode ? addr : reader_sector;
    assign reader_data=video_mode ? map_data : physical_data;
    assign reader_valid=video_mode ? map_valid : physical_valid;
    assign reader_done=video_mode ? map_done : physical_done;
    assign reader_error=video_mode ? map_error : physical_error;
    assign idle=!req && !map_busy && !map_req && !reader_req;
    fat32_file_sector_mapper mapper(
        .clk(clk),.rst(rst),.file_start(file_start),.first_cluster(first_cluster),.file_size(file_size),
        .sectors_per_cluster(spc),.sectors_per_cluster_shift(spc_shift),
        .fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
        .client_req(video_mode && reader_req),.client_sector_index(reader_sector),.busy(map_busy),
        .client_done(map_done),.client_error(map_error),.client_data(map_data),.client_data_valid(map_valid),
        .sector_req(map_req),.sector_lba(map_addr),.sector_busy(req),
        .sector_valid(req && physical_valid),.sector_byte_index(byte_index),.sector_byte(physical_data),
        .sector_done(req && (physical_done || physical_error)),.sector_error(physical_error ? 8'd1 : 8'd0));
    always @(posedge clk or posedge rst) begin
        if(rst) begin opened<=0;req<=0;addr<=0;byte_index<=0;end
        else begin
            if(file_start)opened<=1;
            if(req)begin
                if(physical_valid)byte_index<=byte_index+1'b1;
                if(physical_done || physical_error)req<=0;
            end else if(map_req && video_mode)begin req<=1;addr<=map_addr;byte_index<=0;end
        end
    end
endmodule
