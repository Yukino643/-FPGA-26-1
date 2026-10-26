// 共享FAT32服务。video_mode仅允许在rst保持时改变，所有扇区请求锁住至结束。
module media_fat_service(
    input wire clk,rst,sd_init_done,video_mode,sd_abort,
    input wire scan_start,file_start,client_req,
    input wire [31:0] first_cluster,file_size,client_sector,
    output wire fs_busy,fs_done,fs_found,
    output wire [7:0] fs_error,
    output wire [3:0] fs_total,
    output wire [31:0] found_cluster,found_size,
    output wire [7:0] client_data,
    output wire client_valid,client_done,client_error,
    output wire wav_found,
    output wire [31:0] wav_sector,
    output wire idle,
    output wire [7:0] audio_spc,
    output wire [2:0] audio_shift,
    output wire [31:0] audio_fat_lba,audio_data_lba,audio_max_cluster,
    output reg sd_req,
    output reg [31:0] sd_addr,
    input wire [7:0] sd_data,
    input wire sd_valid,sd_done
);
    wire [7:0] spc;
    wire [2:0] spc_shift;
    wire [31:0] fat_lba,data_lba,max_cluster,fs_addr,map_addr;
    assign audio_spc=spc;assign audio_shift=spc_shift;
    assign audio_fat_lba=fat_lba;assign audio_data_lba=data_lba;assign audio_max_cluster=max_cluster;
    wire fs_req,map_req,map_busy;
    reg owner_map;
    reg [8:0] physical_byte;
    wire ended=sd_done || sd_abort;
    assign idle=!sd_req && !fs_req && !map_req && !map_busy && !fs_busy && !client_req;
    fat32_bmp_index #(.MAX_IMAGES(8),.INDEX_WAV(1),.RUNTIME_EXT(1)) indexer(
        .file_ext(video_mode ? "R16" : "BMP"),
        .clk(clk),.rst(rst || !sd_init_done),.scan_start(scan_start),.target_count(video_mode ? 4'd1 : 4'd8),
        .busy(fs_busy),.scan_done(fs_done),.error_code(fs_error),.partition_lba(),
        .sectors_per_cluster(spc),.sectors_per_cluster_shift(spc_shift),
        .fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
        .found_total(fs_total),.found_valid(fs_found),.found_cluster(found_cluster),.found_size(found_size),
        .wav_found(wav_found),.wav_sector(wav_sector),.sector_req(fs_req),.sector_lba(fs_addr),.sector_busy(sd_req),
        .sector_valid(sd_req && !owner_map && sd_valid),.sector_byte_index(physical_byte),.sector_byte(sd_data),
        .sector_done(sd_req && !owner_map && ended),.sector_error(sd_abort ? 8'd1 : 8'd0));
    fat32_file_sector_mapper mapper(
        .clk(clk),.rst(rst || !sd_init_done),.file_start(file_start),
        .first_cluster(first_cluster),.file_size(file_size),.sectors_per_cluster(spc),
        .sectors_per_cluster_shift(spc_shift),.fat_start_lba(fat_lba),.data_start_lba(data_lba),.max_cluster(max_cluster),
        .client_req(client_req),.client_sector_index(client_sector),.busy(map_busy),
        .client_done(client_done),.client_error(client_error),.client_data(client_data),.client_data_valid(client_valid),
        .sector_req(map_req),.sector_lba(map_addr),.sector_busy(sd_req),
        .sector_valid(sd_req && owner_map && sd_valid),.sector_byte_index(physical_byte),.sector_byte(sd_data),
        .sector_done(sd_req && owner_map && ended),.sector_error(sd_abort ? 8'd1 : 8'd0));
    always @(posedge clk or posedge rst) begin
        if(rst) begin sd_req<=0;sd_addr<=0;physical_byte<=0;owner_map<=0;end
        else if(!sd_init_done) begin sd_req<=0;physical_byte<=0;end
        else if(sd_req) begin
            if(sd_valid) physical_byte<=physical_byte+1'b1;
            if(ended) sd_req<=0;
        end else if(fs_req || map_req) begin
            sd_req<=1;owner_map<=!fs_req;sd_addr<=fs_req ? fs_addr : map_addr;physical_byte<=0;
        end
    end
endmodule
