`timescale 1ns/1ps
// 独立坐标/色值/ASCII字模参考；整页逐像素检查，不以DUT内部命中信号作判据。
module tb_monitor_menu_renderer #(
    parameter integer FIRST_SCENE=0,
    parameter integer LAST_SCENE=12
);
    reg clk=0; always #5 clk=~clk;
    reg de=1, page=0, menu_active=1;
    reg screen_page=0, screen_edit=0, subtitle_page=0, subtitle_edit=0;
    reg audio_page=0,audio_edit=0;
    reg [4:0] audio_shadow=10,audio_active=10;
    reg cfg_busy=0, cfg_dirty=0, buzzer_test=0, sd_init_done=1;
    reg [2:0] cursor=0;
    reg [3:0] cfg_shadow=7, cfg_active=7;
    reg [1:0] period_shadow=0, period_active=0;
    reg [9:0] screen_shadow=10'h144, screen_active=10'h144;
    reg [4:0] subtitle_shadow=5'h09, subtitle_active=5'h09;
    reg [15:0] key_events=16'hAB00;
    reg [3:0] led_state=3;
    reg [9:0] x=0; reg [8:0] y=0;
    wire [23:0] rgb;
    monitor_menu_renderer dut(
        .clk(clk),.de(de),.x(x),.y(y),.page(page),.menu_active(menu_active),.cursor(cursor),
        .cfg_shadow(cfg_shadow),.cfg_active(cfg_active),.period_shadow(period_shadow),.period_active(period_active),
        .screen_page(screen_page),.screen_edit(screen_edit),.screen_shadow(screen_shadow),.screen_active(screen_active),
        .subtitle_page(subtitle_page),.subtitle_edit(subtitle_edit),.subtitle_shadow(subtitle_shadow),.subtitle_active(subtitle_active),
        .audio_page(audio_page),.audio_edit(audio_edit),.audio_shadow(audio_shadow),.audio_active(audio_active),
        .cfg_busy(cfg_busy),.cfg_dirty(cfg_dirty),.commit_seen(1'b0),.buzzer_test(buzzer_test),
        .sd_init_done(sd_init_done),.key_state(3'd0),.key_events(key_events),.img_count(4'd7),.led_state(led_state),.rgb(rgb));
    localparam [23:0] BG=24'h07131D, HEADER=24'h0B1D28, RULE=24'h2A5A70,
                     SURF=24'h142F40, SEL=24'h1B4658, FRAME=24'h3A6478,
                     FG=24'hE9F4FA, VALUE=24'hC9DBE5, MUTED=24'h8FA9B8,
                     FOCUS=24'h38BDF8, ON=24'h5BE39B, OFF=24'hFF7B72,
                     AMBER=24'hFFB84D, CHIP=24'h16394A, WAIT_FG=24'h16232B;
    localparam [1023:0] TU_GLYPH={
        32'h00000000,32'h00000000,32'h00000000,32'h0FFFFFF0,
        32'h0FFFFFF0,32'h0C060030,32'h0C070030,32'h0C0FFC30,
        32'h0C1FFC30,32'h0C1FFC30,32'h0C3C3830,32'h0C7E7030,
        32'h0C67E030,32'h0C03C030,32'h0C07F030,32'h0C3E7E30,
        32'h0CFC1FB0,32'h0CE3C730,32'h0C03F030,32'h0C00F030,
        32'h0C0C0030,32'h0C0FC030,32'h0C07F030,32'h0C00F030,
        32'h0C000030,32'h0FFFFFF0,32'h0FFFFFF0,32'h0E000070,
        32'h0C000030,32'h00000000,32'h00000000,32'h00000000};
    reg [7:0] reference_font[0:2047];
    reg [79:0] labels[0:5];
    reg [23:0] value_colors[0:5];
    reg [5:0] pending_bits=0, editing_bits=0;
    reg [127:0] heading;
    reg [39:0] status_label;
    reg [23:0] status_ink,status_fill;
    integer mode,row,col,dump,i,ix,iy,cell_index,ref_col,ref_row;
    integer column,card_row,idx,x0,y0,w,lx,ly,title_width,thickness;
    reg wide,card,selected,editing,arrow,verify_pixel;
    reg [23:0] expected,ink;
    reg [7:0] character,bits;
    reg [31:0] cjk_row;
    reg [255:0] footer;

    task settle;
        begin repeat(4) @(negedge clk); end
    endtask
    task scene;
        input integer n;
        begin
            audio_page=0;audio_edit=0;audio_shadow=10;audio_active=10;
            page=0;menu_active=1;screen_page=0;screen_edit=0;subtitle_page=0;subtitle_edit=0;
            cfg_busy=0;cfg_dirty=0;buzzer_test=0;sd_init_done=1;
            cfg_shadow=7;cfg_active=7;period_shadow=0;period_active=0;
            screen_shadow=10'h144;screen_active=10'h144;subtitle_shadow=5'h09;subtitle_active=5'h09;
            cursor=0;pending_bits=0;editing_bits=0;
            heading="PROGRAM CONTROL ";status_label="READY";status_ink=MUTED;status_fill=CHIP;
            labels[0]="ON        ";labels[1]="100%      ";labels[2]="ON        ";
            labels[3]="ON        ";labels[4]="1S        ";labels[5]="HDMI-B    ";
            for(i=0;i<6;i=i+1) value_colors[i]=(i<4 && i!=1) ? ON : VALUE;
            if(n==1) begin
                page=1;heading="PERIPHERAL TEST ";
                labels[0]="READY     ";labels[1]="IDLE      ";labels[2]="CNTAB     ";labels[3]="LED3      ";
                for(i=0;i<4;i=i+1) value_colors[i]=(i==0) ? ON : VALUE;
            end
            if(n==2) begin menu_active=0;heading="PLAYBACK KEYS   ";end
            if(n==3 || n==4 || n==8) begin
                screen_page=1;heading="HDMI-B SETTINGS ";
                labels[0]="0         ";labels[1]="100%      ";labels[2]="NORM      ";labels[3]="RESET     ";
                for(i=0;i<4;i=i+1)value_colors[i]=VALUE;
                if(n==4 || n==8) begin
                    screen_shadow=10'h154;pending_bits=6'b000010;
                    labels[1]="113% *    ";value_colors[1]=AMBER;
                end
                if(n==4) begin
                    screen_edit=1;cursor=1;editing_bits=6'b000010;
                    status_label="EDIT ";status_ink=AMBER;
                end
            end
            if(n==5)cursor=5;
            if(n==6 || n==7) begin
                subtitle_page=1;heading="HDMI-B SUBTITLE ";
                labels[0]="ON        ";labels[1]="1/3       ";labels[2]="NORM      ";labels[3]="OFF       ";
                value_colors[0]=ON;value_colors[1]=VALUE;value_colors[2]=VALUE;value_colors[3]=OFF;
                if(n==7) begin
                    subtitle_edit=1;cursor=1;subtitle_shadow=5'h13;
                    pending_bits=6'b000110;editing_bits=6'b000010;
                    labels[1]="2/3 *     ";labels[2]="FAST *    ";value_colors[1]=AMBER;value_colors[2]=AMBER;
                    status_label="EDIT ";status_ink=AMBER;
                end
            end
            if(n>=10)begin
                audio_page=1;heading="HDMI-B AUDIO    ";
                labels[0]="100%      ";labels[1]="OFF       ";labels[2]="ON        ";labels[3]="RESET     ";
                value_colors[0]=VALUE;value_colors[1]=OFF;value_colors[2]=ON;value_colors[3]=VALUE;
                if(n==11)begin
                    audio_shadow=5;audio_edit=1;pending_bits=1;editing_bits=1;
                    labels[0]="50% *     ";value_colors[0]=AMBER;status_label="EDIT ";status_ink=AMBER;
                end
                if(n==12)begin
                    audio_shadow=5'h18;audio_active=5'h18;cursor=1;
                    labels[0]="80%       ";labels[1]="ON        ";value_colors[1]=ON;
                end
            end
            if(n==9)begin cfg_busy=1;status_label="WAIT ";status_ink=WAIT_FG;status_fill=AMBER;end
            settle;
        end
    endtask

    // 只以固定规格坐标选择字形，所有边框/留白/页眉/状态/箭头/值都核对RGB。
    task reference_pixel;
        input integer xx,yy;
        begin
            verify_pixel=1;expected=BG;ink=FG;character=" ";ref_col=0;ref_row=0;
            wide=page || screen_page || subtitle_page || audio_page;
            column=wide ? ((xx<320) ? 0 : 1) : ((xx<220) ? 0 : ((xx<424) ? 1 : 2));
            card_row=(yy<272) ? 0 : 1;
            idx=card_row*(wide ? 2 : 3)+column;
            x0=wide ? ((column==0) ? 32 : 336) : ((column==0) ? 24 : ((column==1) ? 228 : 432));
            y0=(card_row==0) ? 96 : 288; w=wide ? 272 : 184;lx=xx-x0;ly=yy-y0;
            card=(lx>=0 && lx<w && ly>=0 && ly<160);
            selected=menu_active && idx==cursor;editing=editing_bits[idx];
            if(yy<64)expected=HEADER;
            if(card)expected=selected ? SEL : SURF;
            if(menu_active && xx>=496 && xx<608 && yy>=16 && yy<48)expected=status_fill;
            if(xx>=32 && xx<288 && yy>=16 && yy<48)begin
                cell_index=(xx-32)/16;character=heading[(15-cell_index)*8 +: 8];
                ref_col=((xx-32)/2)%8;ref_row=(yy-16)/2;ink=MUTED;
            end
            if(menu_active && xx>=512 && xx<592 && yy>=16 && yy<48)begin
                cell_index=(xx-512)/16;character=status_label[(4-cell_index)*8 +: 8];
                ref_col=((xx-512)/2)%8;ref_row=(yy-16)/2;ink=status_ink;
            end
            if(card && lx>=16 && lx<176 && ly>=104 && ly<136)begin
                cell_index=(lx-16)/16;character=labels[idx][(9-cell_index)*8 +: 8];
                ref_col=((lx-16)/2)%8;ref_row=(ly-104)/2;ink=value_colors[idx];
            end
            arrow=card && selected && (!page || screen_page || subtitle_page || idx==1) &&
                  lx>=w-36 && lx<w-20 && ly>=16 && ly<48;
            if(arrow)begin
                character=">";ref_col=(lx-(w-36))/2;ref_row=(ly-16)/2;ink=editing ? AMBER : FOCUS;
            end
            if(!menu_active && xx>=32 && xx<288 && yy>=456 && yy<472)begin
                footer="K2 NEXT K3 AUTO HOLD K3 MENU    ";
                character=footer[(31-(xx-32)/8)*8 +: 8];ref_col=(xx-32)%8;ref_row=yy-456;ink=MUTED;
            end
            bits=reference_font[{character[6:0],4'b0}+ref_row];
            if(bits[7-ref_col])expected=ink;
            if(audio_page && idx==0 && card && lx>=16 && lx<216 && ly>=72 && ly<84 && ((lx-16)%20)<16)
                expected=(lx<16+20*audio_shadow[3:0]) ? (audio_shadow[4] ? MUTED : ON) : FRAME;
            title_width=audio_page ? ((idx==3) ? 128 : 64) : screen_page ? ((idx==3) ? 128 : ((idx==1) ? 96 : 64)) :
                         ((page && (idx==1 || idx==3)) ? 96 : 64);
            if(card && lx>=16 && lx<16+title_width && ly>=16 && ly<48)begin
                // 第一字独立常量参考；其他中文字形在字符索引测试核对。
                if(!wide && idx==0 && lx<48)begin
                    cjk_row=TU_GLYPH[(31-(ly-16))*32 +: 32];
                    expected=cjk_row[31-(lx-16)] ? FG : (selected ? SEL : SURF);
                end else verify_pixel=0;
            end
            thickness=selected ? 4 : 2;
            if(card && (lx<thickness || lx>=w-thickness || ly<thickness || ly>=160-thickness))begin
                verify_pixel=1;expected=selected ? (editing ? AMBER : FOCUS) : (pending_bits[idx] ? AMBER : FRAME);
            end
            if(yy>=62 && yy<64)begin verify_pixel=1;expected=RULE;end
        end
    endtask
    task cjk_at;
        input integer xx,yy;
        input [5:0] glyph;
        begin
            @(negedge clk);x=xx;y=yy;
            #1;if(!dut.req_cjk || dut.req_cjk_idx!==glyph)$fatal(1,"CJK index xy=%0d,%0d",xx,yy);
        end
    endtask
    task check_cell;
        input integer left,top;
        input [79:0] line;
        input [23:0] color,fill;
        integer xx,yy,k;
        reg [7:0] c,rr;
        reg [23:0] target;
        begin
            for(yy=0;yy<32;yy=yy+1)
                for(xx=0;xx<160;xx=xx+1)begin
                    @(negedge clk);x=left+xx;y=top+yy;
                    k=xx/16;c=line[(9-k)*8 +: 8];rr=reference_font[{c[6:0],4'b0}+yy/2];
                    target=rr[7-(xx/2)%8] ? color : fill;
                    @(posedge clk);#1;
                    if(rgb!==target)$fatal(1,"value glyph/state xy=%0d,%0d got=%h expected=%h",x,y,rgb,target);
                end
        end
    endtask
    task check_status;
        input [39:0] label;
        input [23:0] color,fill;
        integer xx,yy,k;
        reg [7:0] c,rr;
        reg [23:0] target;
        begin
            // 固定坐标核对真实字模及底色，不以DUT内部状态作通过条件。
            for(yy=0;yy<32;yy=yy+1)
                for(xx=0;xx<80;xx=xx+1)begin
                    @(negedge clk);x=512+xx;y=16+yy;
                    k=xx/16;c=label[(4-k)*8 +: 8];rr=reference_font[{c[6:0],4'b0}+yy/2];
                    target=rr[7-(xx/2)%8] ? color : fill;
                    @(posedge clk);#1;
                    if(rgb!==target)$fatal(1,"header focus/state xy=%0d,%0d got=%h expected=%h",x,y,rgb,target);
                end
        end
    endtask
    initial begin
        $readmemh("D:/FPGA/code/example/rtl/ctrl/font_ascii_bram.hex",reference_font);
        scene(0);
        cjk_at(40,112,0);cjk_at(72,112,1);cjk_at(448,112,4);cjk_at(480,112,5);
        cjk_at(40,304,32);cjk_at(72,304,20);cjk_at(244,304,7);cjk_at(276,304,8);
        cjk_at(448,304,19);cjk_at(480,304,20);
        scene(1);cjk_at(48,112,9);cjk_at(416,112,13);cjk_at(48,304,14);cjk_at(416,304,18);
        scene(3);cjk_at(48,112,21);cjk_at(416,112,22);cjk_at(448,304,30);
        scene(6);cjk_at(48,112,32);cjk_at(384,112,34);cjk_at(48,304,35);cjk_at(352,304,6);cjk_at(384,304,31);
        scene(10);cjk_at(48,112,36);cjk_at(80,112,38);cjk_at(352,112,39);cjk_at(384,112,36);
        cjk_at(48,304,2);cjk_at(80,304,3);cjk_at(448,304,30);
        scene(0);cjk_at(244,112,36);cjk_at(276,112,37);
        // 固定坐标只切状态，覆盖组合敏感列表与状态寄存边界。
        scene(3);cursor=3;settle;check_cell(352,392,"RESET     ",VALUE,SEL);
        screen_edit=1;settle;check_cell(352,392,"CONFIRM   ",AMBER,SEL);
        screen_edit=0;cursor=0;screen_shadow=10'h140;screen_active=10'h140;settle;
        check_cell(48,200,"-64       ",VALUE,SEL);
        screen_shadow=10'h148;screen_active=10'h148;settle;check_cell(48,200,"+64       ",VALUE,SEL);
        cursor=1;screen_shadow=10'h104;screen_active=10'h104;settle;check_cell(352,200,"50%       ",VALUE,SEL);
        screen_shadow=10'h124;screen_active=10'h124;settle;check_cell(352,200,"75%       ",VALUE,SEL);
        screen_shadow=10'h1F4;screen_active=10'h1F4;settle;check_cell(352,200,"ERR       ",OFF,SEL);
        scene(1);sd_init_done=0;settle;check_cell(48,200,"WAIT      ",AMBER,SEL);
        cursor=1;buzzer_test=1;settle;check_cell(352,200,"TEST      ",ON,SEL);
        scene(6);subtitle_shadow=5'h08;subtitle_active=5'h08;settle;check_cell(48,200,"OFF       ",OFF,SEL);
        cursor=1;subtitle_shadow=5'h0F;subtitle_active=5'h0F;settle;check_cell(352,200,"ERR       ",OFF,SEL);
        scene(0);cfg_shadow=6;cfg_dirty=1;settle;check_cell(40,200,"OFF *     ",AMBER,SEL);
        @(negedge clk);x=229;y=97;@(posedge clk);#1;
        if(rgb!==FRAME)$fatal(1,"cfg_dirty contaminated unchanged border");
        cfg_shadow=7;cfg_dirty=0;settle;check_cell(40,200,"ON        ",ON,SEL);
        // 全局dirty保持时，页眉必须跟随各页当前聚焦卡，不能泄漏。
        scene(0);cfg_shadow=6;cfg_dirty=1;settle;check_status("EDIT ",AMBER,CHIP);
        cursor=1;settle;check_status("READY",MUTED,CHIP);
        cursor=0;settle;check_status("EDIT ",AMBER,CHIP);
        cfg_busy=1;settle;check_status("WAIT ",WAIT_FG,AMBER);
        cfg_busy=0;screen_page=1;cursor=0;settle;check_status("READY",MUTED,CHIP);
        screen_shadow=10'h154;cursor=1;settle;check_status("EDIT ",AMBER,CHIP);
        cursor=0;settle;check_status("READY",MUTED,CHIP);
        screen_edit=1;settle;check_status("EDIT ",AMBER,CHIP);
        screen_edit=0;screen_page=0;subtitle_page=1;cursor=0;settle;check_status("READY",MUTED,CHIP);
        subtitle_shadow=5'h0B;cursor=1;settle;check_status("EDIT ",AMBER,CHIP);
        cursor=0;settle;check_status("READY",MUTED,CHIP);
        subtitle_edit=1;settle;check_status("EDIT ",AMBER,CHIP);
        subtitle_edit=0;subtitle_page=0;page=1;settle;check_status("READY",MUTED,CHIP);
        cfg_busy=1;settle;check_status("WAIT ",WAIT_FG,AMBER);
        for(mode=FIRST_SCENE;mode<=LAST_SCENE;mode=mode+1)begin
            scene(mode);
            case(mode)
                0:dump=$fopen("menu_program.ppm","w");1:dump=$fopen("menu_peripheral.ppm","w");
                2:dump=$fopen("menu_playback.ppm","w");3:dump=$fopen("menu_screen.ppm","w");
                4:dump=$fopen("menu_screen_edit.ppm","w");5:dump=$fopen("menu_program_screen.ppm","w");
                6:dump=$fopen("menu_subtitle.ppm","w");7:dump=$fopen("menu_subtitle_edit.ppm","w");
                10:dump=$fopen("menu_audio.ppm","w");11:dump=$fopen("menu_audio_edit.ppm","w");
                12:dump=$fopen("menu_audio_mute.ppm","w");
                8:dump=$fopen("menu_screen_pending.ppm","w");9:dump=$fopen("menu_wait.ppm","w");
            endcase
            if(!dump)$fatal(1,"cannot open screenshot");
            $fwrite(dump,"P3\n640 480\n255\n");
            for(row=0;row<480;row=row+1)
                for(col=0;col<640;col=col+1)begin
                    @(negedge clk);x=col;y=row;de=1;
                    reference_pixel(col,row);
                    @(posedge clk);#1;
                    if(^rgb===1'bx)$fatal(1,"unknown pixel");
                    if(verify_pixel && rgb!==expected)
                        $fatal(1,"P0 pixel scene=%0d xy=%0d,%0d got=%h expected=%h",mode,col,row,rgb,expected);
                    $fwrite(dump,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
                end
            $fclose(dump);
            $display("P0 scene %0d RGB PASS",mode);
        end
        @(negedge clk);de=0;@(posedge clk);#1;if(rgb!==0)$fatal(1,"blanking");
        $display("TB_MONITOR_MENU_RENDERER PASS P0 scenes=13 state_colors stars arrows borders footer native32");$finish;
    end
    initial begin #40000000;$fatal(1,"P0 renderer timeout");end
endmodule
