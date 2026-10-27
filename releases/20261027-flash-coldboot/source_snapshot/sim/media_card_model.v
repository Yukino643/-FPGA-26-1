`timescale 1ns/1ps
// FAT32超级软盘，8个不连续数据簇；接口按官方SPI高速档每字节36个100MHz周期建模。
module media_card_model #(
    parameter CASE=0, BYTE_CYCLES=36, HOLD_REQ=1
)(input wire clk,rst,req,input wire [31:0] addr,
   output reg [7:0] data,output reg valid,done,abort,
   output integer transactions);
    reg [7:0] header[0:511],pixels[0:230399],boot[0:511],root[0:511];
    integer clusters[0:8];
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
        direntry(0,"BMP",172854);direntry(1,"WAV",384044);
        root[26]=20;root[58]=30;
        direntry(2,CASE==5 ? "TXT":"r16",CASE==6 ? 230400 : CASE==7 ? 269312:230912);
        header[12]=2;header[13]=0;header[14]=0;header[15]=0;
        if(CASE==1) header[0]="X";
        if(CASE==2) root[2*32+8]="X";
        clusters[0]=4;clusters[1]=9;clusters[2]=5;clusters[3]=12;
        clusters[4]=6;clusters[5]=15;clusters[6]=7;clusters[7]=18;
        clusters[8]=10;
        if(CASE==7) begin
            header[4]=2;
            for(i=28;i<44;i=i+1)header[i]=0;
            header[28]=8'hc3;header[29]=1; // 音轨始于文件扇区451。
            header[32]=8'h80;header[33]=8'h25; // 9600立体声样本。
            header[36]=8'h80;header[37]=8'hbb;
            header[40]=16;header[42]=2;
        end
        data=0;valid=0;done=0;abort=0;transactions=0;
    end
    // 有效320x180 BMP24，底朝上行序，所有像素可独立计算验证。
    function [15:0] bmp_pixel;
        input integer px,py;
        begin bmp_pixel={px[4:0]^5'h15,py[5:0]^6'h2a,px[4:0]^py[4:0]^5'h0f};end
    endfunction
    // 标准44字节头、48kHz/双声道/16bit，两秒连续WAV。
    // 独立样本常量方便检查真实解析器、异步FIFO及48kHz消费。
    function [7:0] wav_byte;
        input integer pos;
        reg [31:0] v;
        begin
            wav_byte=0;
            if(pos>=44 && pos<384044) begin
                case(pos%4)
                    0:wav_byte=8'h34;1:wav_byte=8'h12;
                    2:wav_byte=8'h78;3:wav_byte=8'h56;
                endcase
            end else case(pos)
                0:wav_byte="R";1:wav_byte="I";2,3:wav_byte="F";
                8:wav_byte="W";9:wav_byte="A";10:wav_byte="V";11:wav_byte="E";
                12:wav_byte="f";13:wav_byte="m";14:wav_byte="t";15:wav_byte=" ";
                16:wav_byte=16;20:wav_byte=1;22:wav_byte=2;
                24,25,26,27:begin v=48000;wav_byte=v>>(8*(pos-24));end
                28,29,30,31:begin v=192000;wav_byte=v>>(8*(pos-28));end
                32:wav_byte=4;34:wav_byte=16;
                36:wav_byte="d";37:wav_byte="a";38:wav_byte="t";39:wav_byte="a";
                40,41,42,43:begin v=384000;wav_byte=v>>(8*(pos-40));end
                4,5,6,7:begin v=384036;wav_byte=v>>(8*(pos-4));end
            endcase
        end
    endfunction
    function [7:0] bmp_byte;
        input integer pos;
        integer off,px,py;
        reg [15:0] p;
        reg [31:0] v;
        begin
            bmp_byte=0;
            if(pos<54) begin
                if(pos==0)bmp_byte="B";else if(pos==1)bmp_byte="M";
                else if(pos>=2 && pos<6) begin v=172854;bmp_byte=v>>(8*(pos-2));end
                else if(pos==10)bmp_byte=54;
                else if(pos==14)bmp_byte=40;
                else if(pos>=18 && pos<22) begin v=320;bmp_byte=v>>(8*(pos-18));end
                else if(pos>=22 && pos<26) begin v=180;bmp_byte=v>>(8*(pos-22));end
                else if(pos==26)bmp_byte=1;else if(pos==28)bmp_byte=24;
            end else if(pos<172854) begin
                off=pos-54;px=(off/3)%320;py=179-off/960;p=bmp_pixel(px,py);
                case(off%3)
                    0:bmp_byte={p[4:0],p[4:2]};
                    1:bmp_byte={p[10:5],p[10:9]};
                    2:bmp_byte={p[15:11],p[15:13]};
                endcase
            end
        end
    endfunction
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
                for(n=0;n<(CASE==7 ? 8:7);n=n+1) if(e==clusters[n]) fatval=clusters[n+1];
                if(e>=20 && e<25) fatval=e+1;
                disk_byte=fatval>>(8*(offset%4));
            end else if(sector>=1157 && sector<1541) begin
                logical_sector=sector-1157;
                disk_byte=bmp_byte(logical_sector*512+offset);
            end else if(sector>=1797 && sector<2548) begin
                disk_byte=wav_byte((sector-1797)*512+offset);
            end else begin
                logical_sector=-1;
                for(n=0;n<(CASE==7 ? 9:8);n=n+1)
                    if(sector>=5+(clusters[n]-2)*64 && sector<5+(clusters[n]-1)*64)
                        logical_sector=n*64+sector-(5+(clusters[n]-2)*64);
                if(logical_sector==0) disk_byte=header[offset];
                else if(logical_sector>0 && logical_sector<=450)
                    disk_byte=pixels[(logical_sector-1)*512+offset];
                else if(CASE==7 && logical_sector>=451 && logical_sector<526) begin
                    // 左样本按序号增长，右样本取反：可查跨扇区、回环、暂停丢重样本。
                    fatval=(logical_sector-451)*128+offset/4;
                    case(offset%4)
                        0:disk_byte=fatval[7:0];1:disk_byte=fatval[15:8];
                        2:disk_byte=~fatval[7:0];3:disk_byte=~fatval[15:8];
                    endcase
                end
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
            if(HOLD_REQ && (addr!=lba || !req)) $fatal(1,"FAIL physical request changed in flight");
            if(!HOLD_REQ && req) $fatal(1,"FAIL overlapping physical SD command");
            if(CASE==3 && lba==134) begin end // 数据扇区挂起，验证有界超时。
            else if(delay_count!=0) delay_count<=delay_count-1;
            else if(CASE==4 && lba==134 && idx==50) begin abort<=1;active<=0;wait_release<=1;end
            else begin
                valid<=1;data<=disk_byte(lba,idx);delay_count<=BYTE_CYCLES-1;
                if(idx==511) begin done<=1;active<=0;wait_release<=1;end
                else idx<=idx+1;
            end
        end
    end
endmodule
