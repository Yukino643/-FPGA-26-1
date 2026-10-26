`timescale 1ns/1ps
// FAT32超级软盘，8个不连续数据簇；接口按官方SPI高速档每字节36个100MHz周期建模。
module raw_video_card_model #(
    parameter CASE=0, BYTE_CYCLES=36
)(input wire clk,rst,req,input wire [31:0] addr,
   output reg [7:0] data,output reg valid,done,abort,
   output integer transactions);
    reg [7:0] header[0:511],pixels[0:230399],boot[0:511],root[0:511];
    integer clusters[0:7];
    integer i,j,active=0,wait_release=0,idx=0,delay_count=0,lba=0,logical,entry,nextc;
    reg [31:0] val;
    task put32;
        input integer offset;input [31:0] value;
        begin for(j=0;j<4;j=j+1) boot[offset+j]=value>>(8*j);end
    endtask
    task direntry;
        input integer slot;input [23:0] ext;input [31:0] size;
        begin
            for(j=0;j<11;j=j+1) root[slot*32+j]=8'h20;
            root[slot*32]="V";root[slot*32+8]=ext[23:16];root[slot*32+9]=ext[15:8];root[slot*32+10]=ext[7:0];
            root[slot*32+11]=8'h20;root[slot*32+26]=4;
            for(j=0;j<4;j=j+1) root[slot*32+28+j]=size>>(8*j);
        end
    endtask
    initial begin
        $readmemh("header.hex",header);
        $readmemh("frame0.hex",pixels,0,115199);$readmemh("frame1.hex",pixels,115200,230399);
        for(i=0;i<512;i=i+1) begin boot[i]=0;root[i]=0;end
        boot[0]=8'heb;boot[11]=0;boot[12]=2;boot[13]=64;boot[14]=1;boot[16]=1;
        put32(32,4096);put32(36,4);put32(44,2);boot[510]=8'h55;boot[511]=8'haa;
        direntry(0,"BMP",921654);direntry(1,"WAV",1000);
        direntry(2,CASE==5 ? "TXT":"r16",CASE==6 ? 230400:230912);
        header[12]=2;header[13]=0;header[14]=0;header[15]=0;
        if(CASE==1) header[0]="X";
        clusters[0]=4;clusters[1]=9;clusters[2]=5;clusters[3]=12;
        clusters[4]=6;clusters[5]=15;clusters[6]=7;clusters[7]=18;
        data=0;valid=0;done=0;abort=0;transactions=0;
    end
    function [7:0] disk_byte;
        input integer sector,offset;
        integer n,logical_sector,e,next_cluster;
        reg [31:0] fatval;
        begin
            disk_byte=0;
            if(sector==0) disk_byte=boot[offset];
            else if(sector==5) disk_byte=root[offset];
            else if(sector>=1 && sector<=4) begin
                e=(sector-1)*128+offset/4;fatval=32'h0fffffff;
                for(n=0;n<7;n=n+1) if(e==clusters[n]) fatval=clusters[n+1];
                disk_byte=fatval>>(8*(offset%4));
            end else begin
                logical_sector=-1;
                for(n=0;n<8;n=n+1)
                    if(sector>=5+(clusters[n]-2)*64 && sector<5+(clusters[n]-1)*64)
                        logical_sector=n*64+sector-(5+(clusters[n]-2)*64);
                if(logical_sector==0) disk_byte=header[offset];
                else if(logical_sector>0 && logical_sector<=450)
                    disk_byte=pixels[(logical_sector-1)*512+offset];
                else $fatal(1,"FAIL file read outside allocated sectors lba=%d",sector);
            end
        end
    endfunction
    always @(posedge clk) begin
        valid<=0;done<=0;abort<=0;
        if(rst) begin active<=0;wait_release<=0;idx<=0;delay_count<=0;transactions<=0;end
        else if(wait_release) begin if(!req) wait_release<=0;end
        else if(!active && req) begin active<=1;lba<=addr;idx<=0;delay_count<=256;transactions<=transactions+1;end
        else if(active) begin
            if(addr!=lba || !req) $fatal(1,"FAIL physical request changed in flight");
            if(CASE==3 && lba==134) begin end // 数据扇区挂起，验证有界超时。
            else if(delay_count!=0) delay_count<=delay_count-1;
            else if(CASE==4 && lba==134 && idx==50) begin abort<=1;active<=0;wait_release<=1;end
            else begin
                valid<=1;data<=disk_byte(lba,idx);delay_count<=BYTE_CYCLES-1;
                if(idx==((CASE==2 && lba==134)?510:511)) begin done<=1;active<=0;wait_release<=1;end
                else idx<=idx+1;
            end
        end
    end
endmodule
