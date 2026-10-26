`timescale 1ns/1ps
// 顶层真实WAV控制/解析器与真实仲裁器；SD字节响应和100扇区图片负载为行为模型。
// 此测试计量请求数和首PCM时间，不声称覆盖SD SPI电气时序/HDMI接收器解码延迟。
module tb_wav_startup;
    wire media_active_sd=0,media_hold_sd=0;
    wire media_rst_sd=rst_sd;
    wire video_metadata_ready=0,video_audio_present=0;
    wire [31:0] video_audio_sector=0,video_audio_samples=0,video_file_cluster=0,video_file_size=0;
    wire [31:0] audio_fat_lba=0,audio_data_lba=0,audio_max_cluster=0;
    wire [7:0] audio_spc=0;
    wire [2:0] audio_shift=0;
    wire audio_quiescent,audio_router_idle;
    wire [7:0] audio_load_error;
    parameter LEGACY=0, BAD_HEADER=0, NO_WAV=0;
    localparam WAV_LBA=2057;
    reg sd_card_clk=0;
    always #5 sd_card_clk=~sd_card_clk;
    reg rst_sd=1, sd_init_done=0;
    wire wav_ready, wav_scan_done, wav_scan_found, wav_load_done, wav_load_active;
    wire [31:0] wav_scan_sector,wav_pcm_bytes,wav_sd_sec_read_addr;
    wire wav_sd_sec_read,wav_sd_sec_read_data_valid,wav_sd_sec_read_end;
    wire [7:0] wav_sd_sec_read_data;
    wire wav_pcm_valid;
    wire [15:0] wav_pcm_left,wav_pcm_right;
    wire wav_index_found;
    wire [31:0] wav_index_sector;
    integer cycle=0, pcm_count=0,first_pcm=0,first_image=0;
    integer wav_reads=0,reads_before_pcm=0,total_reads=0;
    // 模拟512样本FIFO饱和后的48kHz消费资格，防止无限快样本源掩盖带宽竞争。
    wire wav_fifo_full=(pcm_count>=512) && ((cycle%2083)!=0);
    reg display_valid=0;
    generate if(LEGACY) begin: old_path
        `include "reg_wav_startup_legacy.vh"
    end else begin: current_path
        `include "reg_wav_startup.vh"
    end endgenerate

    wire idx_req,idx_done;
    wire [31:0] idx_lba;
    wire [7:0] idx_error;
    reg idx_start=0,index_kicked=0;
    reg [8:0] idx_byte=0;
    wire bmp_sd_sec_read;
    wire [31:0] bmp_sd_sec_read_addr;
    wire [7:0] bmp_sd_sec_read_data;
    wire bmp_sd_sec_read_data_valid,bmp_sd_sec_read_end,bmp_sd_timeout;
    wire wav_sd_timeout,sd_controller_reset;
    wire [1:0] sd_owner;
    wire sd_phy_sec_read;
    wire [31:0] sd_phy_sec_read_addr;
    reg [7:0] sd_phy_sec_read_data=0;
    reg sd_phy_sec_read_data_valid=0,sd_phy_sec_read_end=0;
    reg image_req=0;
    integer image_sectors=0,gap=0;
    assign bmp_sd_sec_read=idx_done ? image_req : idx_req;
    assign bmp_sd_sec_read_addr=idx_done ? 32'd40 : idx_lba;
    `include "reg_wav_arbiter.vh"
    fat32_bmp_index #(.INDEX_WAV(!LEGACY),.TIMEOUT_CYCLES(20000)) indexer(
        .clk(sd_card_clk),.rst(rst_sd|!sd_init_done),.scan_start(idx_start),.target_count(4'd1),
        .scan_done(idx_done),.error_code(idx_error),.wav_found(wav_index_found),.wav_sector(wav_index_sector),
        .sector_req(idx_req),.sector_lba(idx_lba),.sector_busy(1'b0),
        .sector_valid(bmp_sd_sec_read_data_valid),.sector_byte_index(idx_byte),
        .sector_byte(bmp_sd_sec_read_data),.sector_done(bmp_sd_sec_read_end),.sector_error(8'd0));
    always @(posedge sd_card_clk) begin
        if(rst_sd || !sd_init_done) begin
            idx_start<=0; index_kicked<=0; idx_byte<=0;
            image_req<=0;image_sectors<=0;gap<=0;display_valid<=0;
        end else begin
            idx_start<=0;
            if(!index_kicked) begin idx_start<=1;index_kicked<=1;end
            if(bmp_sd_sec_read_data_valid) idx_byte<=idx_byte+1'b1;
            if(bmp_sd_sec_read_end) idx_byte<=0;
            if(idx_done && image_sectors<100) begin
                if(image_req && bmp_sd_sec_read_end) begin
                    image_req<=0;image_sectors<=image_sectors+1;gap<=3;
                    if(image_sectors==99) begin display_valid<=1; if(first_image==0) first_image=cycle;end
                end else if(!image_req) begin
                    if(gap!=0) gap<=gap-1; else image_req<=1;
                end
            end
        end
    end

    reg [7:0] disk[0:16383];
    function [7:0] card_byte;
        input [31:0] sector;
        input [8:0] offset;
        begin
            card_byte=0;
            if(sector<32) card_byte=disk[sector*512+offset];
            if(sector==WAV_LBA) begin
                case(offset)
                    0:card_byte=BAD_HEADER ? "X" : "R";
                    1:card_byte="I"; 2,3:card_byte="F";
                    8:card_byte="W";9:card_byte="A";10:card_byte="V";11:card_byte="E";
                    40:card_byte=0;41:card_byte=8'h20;42,43:card_byte=0;
                    default: if(offset>=44) begin
                        case(offset[1:0])
                            0:card_byte=8'h34;1:card_byte=8'h12;2:card_byte=8'h78;3:card_byte=8'h56;
                        endcase
                    end
                endcase
            end else if(sector>WAV_LBA && sector<WAV_LBA+17) begin
                case(offset[1:0])
                    0:card_byte=8'h34;1:card_byte=8'h12;2:card_byte=8'h78;3:card_byte=8'h56;
                endcase
            end
        end
    endfunction
    reg response_active=0;
    reg [8:0] response_byte=0;
    reg [31:0] response_lba=0;
    always @(posedge sd_card_clk) begin
        cycle<=cycle+1;
        sd_phy_sec_read_data_valid<=0;sd_phy_sec_read_end<=0;
        if(rst_sd) response_active<=0;
        else if(sd_phy_sec_read) begin
            if(response_active) $fatal(1,"FAIL overlapping SD requests");
            response_active<=1;response_byte<=0;response_lba<=sd_phy_sec_read_addr;
            total_reads=total_reads+1;
            if(sd_owner==2) begin
                wav_reads=wav_reads+1;
                if(!LEGACY && sd_phy_sec_read_addr<WAV_LBA)
                    $fatal(1,"FAIL current top reverted to raw scan");
            end
        end else if(response_active) begin
            sd_phy_sec_read_data<=card_byte(response_lba,response_byte);
            sd_phy_sec_read_data_valid<=1;
            if(response_byte==511) begin response_active<=0;sd_phy_sec_read_end<=1;end
            else response_byte<=response_byte+1'b1;
        end
        if(wav_pcm_valid) begin
            if(wav_pcm_left!==16'h1234 || wav_pcm_right!==16'h5678)
                $fatal(1,"FAIL wrong first/stream PCM %h %h",wav_pcm_left,wav_pcm_right);
            if(first_pcm==0) begin
                first_pcm=cycle;reads_before_pcm=total_reads;
                if(!LEGACY && display_valid) $fatal(1,"FAIL still waited for first image");
                if(LEGACY && !display_valid) $fatal(1,"FAIL baseline lost first image gate");
            end
            pcm_count=pcm_count+1;
        end
        if(sd_controller_reset || wav_sd_timeout || bmp_sd_timeout) $fatal(1,"FAIL unexpected timeout");
    end
    integer i,n,saved_reads,saved_pcm;
    initial begin
        for(i=0;i<16384;i=i+1) disk[i]=0;
        // 超级软盘FAT32: reserved1 + FAT8，SPC8，根目录簇2在LBA9。
        disk[0]=8'heb;disk[11]=0;disk[12]=2;disk[13]=8;disk[14]=1;disk[16]=1;
        disk[33]=8'h10;disk[36]=8;disk[44]=2;disk[510]=8'h55;disk[511]=8'haa;
        disk[9*512]="P";disk[9*512+8]="B";disk[9*512+9]="M";disk[9*512+10]="P";
        disk[9*512+11]=8'h20;disk[9*512+26]=3;disk[9*512+28]=54;
        if(!NO_WAV) begin
            disk[9*512+32]="A";disk[9*512+40]="W";disk[9*512+41]="A";disk[9*512+42]="V";
            disk[9*512+43]=8'h20;disk[9*512+58]=2;disk[9*512+59]=1;
            disk[9*512+60]=44;disk[9*512+61]=8'h20;
        end
        repeat(4) @(negedge sd_card_clk);rst_sd=0;sd_init_done=1;
        n=0;
        while((!display_valid || ((!BAD_HEADER && !NO_WAV) && first_pcm==0)) && n<1500000) begin
            @(negedge sd_card_clk);n=n+1;
        end
        if(!display_valid || idx_error!=0) $fatal(1,"FAIL image blocked/error %h",idx_error);
        if(BAD_HEADER || NO_WAV) begin
            repeat(2000) @(negedge sd_card_clk);
            if(pcm_count!=0 || wav_reads!=(BAD_HEADER ? 1:0))
                $fatal(1,"FAIL bad/missing WAV unbounded reads=%d pcm=%d",wav_reads,pcm_count);
        end else begin
            if(first_pcm==0) $fatal(1,"FAIL no PCM");
            if(!LEGACY && (first_pcm>6000 || reads_before_pcm>10 || first_image>65000))
                $fatal(1,"FAIL startup/image contention budget pcm=%d image=%d reads=%d",first_pcm,first_image,reads_before_pcm);
            if(LEGACY && first_pcm<1000000) $fatal(1,"FAIL baseline did not scan skipped sectors");
            $display("MEASURE legacy=%0d first_pcm_cycles=%0d first_image_cycles=%0d reads_to_pcm=%0d",LEGACY,first_pcm,first_image,reads_before_pcm);
            if(!LEGACY) begin
                // 等同卡重新初始化，不用系统复位来掩盖顶层一次性门控未清除的问题。
                @(negedge sd_card_clk);sd_init_done=0;
                repeat(2000) @(negedge sd_card_clk);
                if(wav_index_found || wav_pcm_valid) $fatal(1,"FAIL stale index/PCM after deinit");
                saved_reads=wav_reads;saved_pcm=pcm_count;sd_init_done=1;
                repeat(6000) @(negedge sd_card_clk);
                if(wav_reads<=saved_reads || pcm_count<=saved_pcm)
                    $fatal(1,"FAIL reinit did not restart WAV/PCM");
            end
        end
        $display("TB_WAV_STARTUP PASS legacy=%0d bad=%0d missing=%0d",LEGACY,BAD_HEADER,NO_WAV);
        $finish;
    end
endmodule
