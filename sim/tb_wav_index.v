`timescale 1ns/1ps
module tb_wav_index;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, scan_start=0;
    reg [3:0] target_count=8;
    wire done, found, req;
    wire [31:0] lba, wav_sector;
    wire [7:0] error_code;
    wire [3:0] images;
    reg active=0, valid=0, sector_done=0, stall=0;
    reg [7:0] data=0, sector_error=0;
    reg [8:0] pos=0, byte_index=0;
    reg [31:0] current_lba=0;
    reg [7:0] disk[0:16383];
    integer i,j,n,reads=0;
    fat32_bmp_index #(.INDEX_WAV(1),.TIMEOUT_CYCLES(1024),.MAX_ROOT_CLUSTERS(8)) dut(
        .clk(clk),.rst(rst),.scan_start(scan_start),.target_count(target_count),
        .scan_done(done),.error_code(error_code),.found_total(images),
        .wav_found(found),.wav_sector(wav_sector),
        .sector_req(req),.sector_lba(lba),.sector_busy(active),
        .sector_valid(valid),.sector_byte_index(byte_index),.sector_byte(data),
        .sector_done(sector_done),.sector_error(current_lba==7 ? sector_error : 8'd0));
    always @(posedge clk) begin
        valid<=0; sector_done<=0;
        if (rst) begin active<=0; pos<=0; end
        else if (!active && req) begin
            if (lba>=32) $fatal(1,"FAIL directory read out of range %d",lba);
            active<=1; current_lba<=lba; pos<=0; reads<=reads+1;
        end else if (active && !stall) begin
            valid<=1; byte_index<=pos; data<=disk[current_lba*512+pos];
            if (pos==511) begin active<=0; sector_done<=1; end
            else pos<=pos+1'b1;
        end
    end
    task entry;
        input integer sector,slot;
        input [7:0] name0,attr,e0,e1,e2;
        input [31:0] cluster,size;
        integer b,k;
        begin
            b=sector*512+slot*32;
            for(k=0;k<32;k=k+1) disk[b+k]=0;
            disk[b]=name0; disk[b+8]=e0; disk[b+9]=e1; disk[b+10]=e2;
            disk[b+11]=attr;
            disk[b+20]=cluster[23:16]; disk[b+21]=cluster[31:24];
            disk[b+26]=cluster[7:0]; disk[b+27]=cluster[15:8];
            disk[b+28]=size[7:0]; disk[b+29]=size[15:8];
            disk[b+30]=size[23:16]; disk[b+31]=size[31:24];
        end
    endtask
    task layout;
        begin
            for(i=0;i<16384;i=i+1) disk[i]=0;
            disk[450]=8'h0c; disk[454]=1; disk[510]=8'h55; disk[511]=8'haa;
            disk[512]=8'heb; disk[523]=0; disk[524]=2; disk[525]=2;
            disk[526]=1; disk[528]=1; disk[544]=100; disk[548]=1;
            disk[556]=2; disk[1022]=8'h55; disk[1023]=8'haa;
            disk[1032]=4; // FAT: 根目录簇2 -> 簇4
            disk[1040]=8'hff; disk[1041]=8'hff; disk[1042]=8'hff; disk[1043]=8'h0f;
            for(j=0;j<16;j=j+1) begin
                entry(3,j,"X",8'h20,"T","X","T",0,0);
                entry(4,j,"X",8'h20,"T","X","T",0,0);
            end
            for(j=0;j<8;j=j+1) entry(3,j,"P",8'h20,"B","M","P",10+j,54);
            entry(7,0,"A",8'h20,"w","a","v",9,1000);
        end
    endtask
    task run_scan;
        begin
            @(negedge clk); scan_start=1;
            @(negedge clk); scan_start=0;
            if(found) $fatal(1,"FAIL stale address survived restart");
            n=0;
            while(!done && n<12000) begin @(negedge clk); n=n+1; end
            if(!done) $fatal(1,"FAIL scan unbounded");
            repeat(5) @(negedge clk);
        end
    endtask
    initial begin
        layout(); repeat(3) @(negedge clk); rst=0;
        run_scan();
        if(!found || wav_sector!=17 || images!=8 || error_code!=0 || reads!=6)
            $fatal(1,"FAIL after eighth BMP/multicluster/lowercase found=%d lba=%d images=%d reads=%d",found,wav_sector,images,reads);
        // 首个有效WAV不被后续WAV覆盖，删除/LFN/目录/卷标/非法簇/短文件均不接受。
        entry(7,0,8'he5,8'h20,"W","A","V",8,1000);
        entry(7,1,"L",8'h0f,"W","A","V",8,1000);
        entry(7,2,"D",8'h10,"W","A","V",8,1000);
        entry(7,3,"V",8'h08,"W","A","V",8,1000);
        entry(7,4,"Z",8'h20,"W","A","V",1,1000);
        entry(7,5,"Z",8'h20,"W","A","V",1000,1000);
        entry(7,6,"Z",8'h20,"W","A","V",8,43);
        entry(7,7,"Z",8'h20,"W","A","V",8,0);
        entry(7,8,"A",8'h20,"W","A","V",11,44);
        entry(7,9,"B",8'h20,"W","A","V",12,1000);
        run_scan(); if(!found || wav_sector!=21) $fatal(1,"FAIL invalid entries/first match");
        // 00终止标记之后的残留数据必须无效。
        disk[7*512]=0;
        run_scan(); if(found || error_code!=0) $fatal(1,"FAIL end marker or missing WAV");
        // 扫描错误不得发布曾见过的候选。
        disk[7*512]="A"; sector_error=8'h10;
        run_scan(); if(found || error_code!=8'h10) $fatal(1,"FAIL failed sector metadata");
        sector_error=0;
        // 无BMP也可正常定位WAV（允许ERR_NO_BMP），不因图片缺失静默丢失音频。
        for(j=0;j<8;j=j+1) entry(3,j,"X",8'h20,"T","X","T",0,0);
        entry(7,0,"A",8'h20,"W","A","V",9,1000);
        run_scan(); if(!found || error_code!=8'h22 || wav_sector!=17) $fatal(1,"FAIL WAV-only card");
        // 超时及复位清除旧地址，重新初始化可恢复。
        stall=1; run_scan(); if(found || error_code!=8'h30) $fatal(1,"FAIL timeout");
        @(negedge clk); rst=1; stall=0;
        repeat(3) @(negedge clk);
        if(found || wav_sector!=0) $fatal(1,"FAIL reset retained metadata");
        rst=0; run_scan(); if(!found || wav_sector!=17) $fatal(1,"FAIL reinit");
        $display("TB_WAV_INDEX PASS: late WAV, root chain, invalid entries, end, missing, errors, restart");
        $finish;
    end
endmodule
