`timescale 1ns/1ps
// 独立固定坐标和字模参考：媒体页所有像素均核对，不借用DUT命中信号。
module tb_media_renderer;
    reg clk=0; always #5 clk=~clk;
    reg de=1,menu_active=1,media_edit=0,media_shadow=0,media_active=0,media_busy=0,media_paused=0;
    reg [7:0] media_error=0;
    reg [2:0] cursor=0;
    reg [9:0] x=0;reg [8:0] y=0;
    wire [23:0] rgb;
    monitor_menu_renderer #(.ENABLE_MEDIA(1)) dut(
        .clk(clk),.de(de),.x(x),.y(y),.page(1'b0),.menu_active(menu_active),.cursor(cursor),
        .media_page(1'b1),.media_edit(media_edit),.media_shadow(media_shadow),.media_active(media_active),
        .media_busy(media_busy),.media_paused(media_paused),.media_error(media_error),
        .audio_page(1'b0),.audio_edit(1'b0),.audio_shadow(5'd10),.audio_active(5'd10),
        .screen_page(1'b0),.screen_edit(1'b0),.screen_shadow(10'h144),.screen_active(10'h144),
        .subtitle_page(1'b0),.subtitle_edit(1'b0),.subtitle_shadow(5'h09),.subtitle_active(5'h09),
        .cfg_busy(1'b0),.cfg_dirty(1'b0),.cfg_shadow(4'd7),.cfg_active(4'd7),
        .period_shadow(2'd0),.period_active(2'd0),.commit_seen(1'b0),.buzzer_test(1'b0),
        .sd_init_done(1'b1),.key_state(3'd0),.key_events(16'd0),.img_count(4'd7),.rgb(rgb));
    localparam [23:0] BG=24'h07131D,HEADER=24'h0B1D28,RULE=24'h2A5A70,SURF=24'h142F40,
        SEL=24'h1B4658,FRAME=24'h3A6478,FG=24'hE9F4FA,VALUE=24'hC9DBE5,MUTED=24'h8FA9B8,
        FOCUS=24'h38BDF8,AMBER=24'hFFB84D,OFF=24'hFF7B72;
    reg [7:0] font[0:2047];
    reg [31:0] cjk_rows[0:255];
    reg cjk_hit;
    reg [79:0] labels[0:3];reg [63:0] titles[0:3];
    reg [127:0] heading;
    reg [255:0] footer;
    reg [39:0] status;
    reg [23:0] expected,ink,fill,value_ink;
    reg [7:0] character,bits;
    integer n,xx,yy,fd,idx,lx,ly,cx,cy,k,thick;
    reg card,selected,editing,pending,hit;
    task reference_pixel;
        begin
            idx=(yy<196?0:2)+(xx<320?0:1);
            lx=xx-(xx<320?32:336);ly=yy-(yy<196?64:204);
            card=lx>=0 && lx<272 && ly>=0 && ly<124;
            selected=menu_active && idx==cursor;editing=selected && media_edit;
            pending=idx==0 && media_shadow!=media_active;
            fill=selected?SEL:SURF;expected=yy<48?HEADER:card?fill:BG;
            cjk_hit=0;hit=0;character=" ";ink=FG;cx=0;cy=0;
            if(xx>=24 && xx<264 && yy>=8 && yy<40)begin
                hit=1;k=(xx-24)/16;character=heading[(15-k)*8+:8];
                cx=((xx-24)/2)%8;cy=(yy-8)/2;ink=MUTED;
            end
            if(menu_active && xx>=536 && xx<616 && yy>=8 && yy<40)begin
                hit=1;k=(xx-536)/16;character=status[(4-k)*8+:8];
                cx=((xx-536)/2)%8;cy=(yy-8)/2;ink=(media_busy || media_edit || (cursor==0 && pending))?AMBER:MUTED;
            end
            if(card && lx>=16 && lx<80 && ly>=12 && ly<44)begin
                cjk_hit=cjk_rows[idx*64+((lx-16)/32)*32+ly-12][31-((lx-16)%32)];
            end
            if(card && selected && idx<2 && lx>=236 && lx<252 && ly>=12 && ly<44)begin
                hit=1;character=">";cx=(lx-236)/2;cy=(ly-12)/2;ink=editing?AMBER:FOCUS;
            end
            if(card && lx>=96 && lx<256 && ly>=78 && ly<110)begin
                hit=1;k=(lx-96)/16;character=labels[idx][(9-k)*8+:8];cx=((lx-96)/2)%8;cy=(ly-78)/2;
                ink=(media_error!=0 && idx==3 && !media_busy)?OFF:(editing||pending||media_busy)?AMBER:VALUE;
            end
            if(!menu_active && xx>=24 && xx<280 && yy>=336 && yy<352)begin
                hit=1;k=(xx-24)/8;character=footer[(31-k)*8+:8];cx=(xx-24)%8;cy=yy-336;ink=MUTED;
            end
            bits=font[{character[6:0],4'b0}+cy];if(hit && bits[7-cx])expected=ink;
            if(cjk_hit)expected=FG;
            thick=selected?4:2;
            if(card && (lx<thick||lx>=272-thick||ly<thick||ly>=124-thick))
                expected=selected?(editing?AMBER:FOCUS):(pending?AMBER:FRAME);
            if(yy>=46 && yy<48)expected=media_busy && menu_active && xx>=536 && xx<616?AMBER:RULE;
        end
    endtask
    initial begin
        $readmemh("D:/FPGA/code/example/rtl/ctrl/font_ascii_bram.hex",font);
        $readmemh("D:/FPGA/code/example/sim/fixtures/media_cjk_rows.hex",cjk_rows);
        titles[0]="MODE    ";titles[1]="PLAYBACK";titles[2]="FORMAT  ";titles[3]="STATUS  ";
        for(n=0;n<7;n=n+1)begin
            menu_active=1;media_edit=0;media_shadow=0;media_active=0;media_busy=0;media_paused=0;media_error=0;cursor=0;
            case(n)
                1:begin media_shadow=1;media_edit=1;end
                2:begin media_shadow=1;media_active=1;cursor=1;end
                3:begin media_shadow=1;media_active=1;media_paused=1;cursor=1;end
                4:begin media_shadow=1;media_active=1;media_busy=1;end
                5:begin media_shadow=1;media_active=1;media_error=8'h31;cursor=3;end
                6:begin media_shadow=1;media_active=1;menu_active=0;end
            endcase
            labels[0]=media_shadow?"     VIDEO":"   PICTURE";
            labels[1]=!media_active?"       N/A":media_paused?"    PAUSED":"   PLAYING";
            labels[2]=media_active?" 320X180 10":"       BMP";
            labels[3]=media_busy?"      WAIT":media_error!=0?"     ERR31":"     READY";
            status=media_busy?"WAIT ":media_edit?"EDIT ":"READY";
            heading=menu_active?"MEDIA PLAYBACK  ":"PLAYBACK KEYS   ";
            // 独立以首字节检查RTL常量，避免参考字符串也被等宽截断而漏检。
            if(dut.STR_VIDEO_KEYS[255:248]!==8'h4B)
                $fatal(1,"FAIL video footer must start with K");
            footer="K3 PAUSE HOLD K3 MENU           ";
            repeat(5)@(negedge clk);
            case(n)
                0:fd=$fopen("media_picture.ppm","w");1:fd=$fopen("media_edit.ppm","w");
                2:fd=$fopen("media_playing.ppm","w");3:fd=$fopen("media_paused.ppm","w");
                4:fd=$fopen("media_wait.ppm","w");5:fd=$fopen("media_error.ppm","w");
                6:fd=$fopen("media_playback.ppm","w");
            endcase
            if(!fd)$fatal(1,"FAIL screenshot open");$fwrite(fd,"P3\n640 360\n255\n");
            for(yy=0;yy<360;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
                @(negedge clk);x=xx;y=yy;reference_pixel;
                @(posedge clk);#1;
                if(rgb!==expected)$fatal(1,"FAIL media renderer scene=%0d xy=%0d,%0d got=%h expected=%h",n,xx,yy,rgb,expected);
                $fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
            end
            $fclose(fd);$display("PASS media renderer scene %0d",n);
        end
        @(negedge clk);de=0;@(posedge clk);#1;if(rgb!==0)$fatal(1,"FAIL blanking");
        $display("PASS media_renderer 7 scenes full raster");$finish;
    end
    initial begin #20000000;$fatal(1,"FAIL media renderer timeout");end
endmodule
