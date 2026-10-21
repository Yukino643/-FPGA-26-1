`timescale 1ns/1ps
module tb_monitor_menu_renderer;
    reg clk=0;
    always #5 clk=~clk;
    reg de=0, page=0, menu_active=1;
    reg screen_page=0, screen_edit=0;
    reg subtitle_page=0, subtitle_edit=0;
    reg [4:0] subtitle_shadow=5'h09;
    reg [9:0] screen_shadow=10'h144;
    reg [2:0] cursor=0;
    reg [39:0] number_text;
    reg [7:0] number_char, number_row;
    reg [23:0] number_expected;
    reg [9:0] x=0;
    reg [8:0] y=0;
    wire [23:0] rgb;
    monitor_menu_renderer dut(
        .clk(clk), .de(de), .x(x), .y(y), .page(page), .menu_active(menu_active),
        .cursor(cursor), .cfg_shadow(4'b0111), .cfg_active(4'b0111),
        .screen_page(screen_page), .screen_edit(screen_edit),
        .screen_shadow(screen_shadow), .screen_active(10'h144), .cfg_busy(1'b0),
        .subtitle_page(subtitle_page), .subtitle_edit(subtitle_edit),
        .subtitle_shadow(subtitle_shadow), .subtitle_active(5'h09),
        .period_shadow(2'd0), .period_active(2'd0),
        .cfg_dirty(1'b0), .commit_seen(1'b0), .buzzer_test(1'b0),
        .key_state(3'd0), .key_events(16'd0), .sd_init_done(1'b1),
        .img_count(4'd7), .led_state(4'b0011), .rgb(rgb));
    integer mode, row, col, dump;
    reg [7:0] reference_font [0:2047];
    reg [255:0] footer_line;
    reg [7:0] footer_char, footer_bits;
    reg [23:0] expected_footer;
    // Independent fixed reference for the first character, including blank rows.
    localparam [1023:0] TU_GLYPH = {
        32'h00000000,32'h00000000,32'h00000000,32'h0FFFFFF0,
        32'h0FFFFFF0,32'h0C060030,32'h0C070030,32'h0C0FFC30,
        32'h0C1FFC30,32'h0C1FFC30,32'h0C3C3830,32'h0C7E7030,
        32'h0C67E030,32'h0C03C030,32'h0C07F030,32'h0C3E7E30,
        32'h0CFC1FB0,32'h0CE3C730,32'h0C03F030,32'h0C00F030,
        32'h0C0C0030,32'h0C0FC030,32'h0C07F030,32'h0C00F030,
        32'h0C000030,32'h0FFFFFF0,32'h0FFFFFF0,32'h0E000070,
        32'h0C000030,32'h00000000,32'h00000000,32'h00000000};
    reg [31:0] cjk_reference_row;
    reg [23:0] expected_title;
    integer title_width;
    task char_at;
        input [9:0] px;
        input [8:0] py;
        input [7:0] expected;
        begin
            @(negedge clk); x=px; y=py; de=1;
            #1; if(dut.req_char!==expected) $fatal(1,"label (%0d,%0d) got=%h expected=%h",px,py,dut.req_char,expected);
        end
    endtask
    task cjk_at;
        input [9:0] px;
        input [8:0] py;
        input [5:0] expected;
        begin
            @(negedge clk); x=px; y=py; de=1;
            #1; if(dut.req_cjk_idx!==expected || !dut.req_cjk)
                $fatal(1,"CJK label (%0d,%0d) got=%d expected=%d",px,py,dut.req_cjk_idx,expected);
        end
    endtask
    initial begin
        $readmemh("D:/FPGA/code/example/rtl/ctrl/font_ascii_bram.hex", reference_font);
        // 显式坐标核对四卡片编号，防止底行再次复用顶行。
        cjk_at(40,104,5'd0); cjk_at(72,104,5'd1);
        cjk_at(448,104,5'd4); cjk_at(480,104,5'd5);
        cjk_at(40,288,6'd32); cjk_at(72,288,5'd20);
        cjk_at(244,288,5'd7); cjk_at(276,288,5'd8);
        cjk_at(448,288,5'd19); cjk_at(480,288,5'd20);
        char_at(32,444," "); char_at(32,460," ");
        menu_active=0;
        char_at(32,444,"K"); char_at(32,460,"H");
        menu_active=1;
        page=1;
        cjk_at(48,104,5'd9); cjk_at(80,104,5'd10);
        cjk_at(352,104,5'd11); cjk_at(384,104,5'd12);
        cjk_at(48,288,5'd14); cjk_at(80,288,5'd15);
        cjk_at(352,288,5'd16); cjk_at(384,288,5'd17);
        cjk_at(416,104,5'd13); cjk_at(416,288,5'd18);
        page=0; screen_page=1;
        cjk_at(48,104,5'd21); cjk_at(80,104,5'd22);
        cjk_at(352,104,5'd23); cjk_at(384,104,5'd24); cjk_at(416,104,5'd22);
        cjk_at(48,288,5'd25); cjk_at(80,288,5'd26);
        cjk_at(352,288,5'd27); cjk_at(384,288,5'd28);
        cjk_at(416,288,5'd29); cjk_at(448,288,5'd30);
        char_at(64,160,"0"); char_at(352,160,"1");
        screen_edit=1; cursor=1;
        char_at(352,344,"O");
        cursor=3;
        char_at(352,344,"R");
        screen_edit=0; cursor=0;
        subtitle_page=1; screen_page=0;
        cjk_at(48,104,6'd32); cjk_at(80,104,6'd20);
        cjk_at(352,104,6'd33); cjk_at(384,104,6'd34);
        cjk_at(48,288,6'd35); cjk_at(80,288,6'd22);
        cjk_at(352,288,6'd0); cjk_at(384,288,6'd6);
        for(mode=0;mode<8;mode=mode+1) begin
            page=(mode==1); menu_active=(mode!=2);
            screen_page=(mode==3 || mode==4); screen_edit=(mode==4);
            cursor=(mode==4) ? 1 : ((mode==5) ? 5 : 0);
            screen_shadow=(mode==4) ? 10'h154 : 10'h144;
            subtitle_page=(mode==6 || mode==7); subtitle_edit=(mode==7);
            subtitle_shadow=(mode==7) ? 5'h13 : 5'h09;
            if(mode==7) cursor=1;
            case(mode)
                0: dump=$fopen("menu_program.ppm","w");
                1: dump=$fopen("menu_peripheral.ppm","w");
                2: dump=$fopen("menu_playback.ppm","w");
                3: dump=$fopen("menu_screen.ppm","w");
                4: dump=$fopen("menu_screen_edit.ppm","w");
                5: dump=$fopen("menu_program_screen.ppm","w");
                6: dump=$fopen("menu_subtitle.ppm","w");
                7: dump=$fopen("menu_subtitle_edit.ppm","w");
            endcase
            $fwrite(dump,"P3\n640 480\n255\n");
            for(row=0;row<480;row=row+1)
                for(col=0;col<640;col=col+1) begin
                    @(negedge clk); de=1; x=col; y=row;
                    @(posedge clk); #1;
                    if(^rgb===1'bx) $fatal(1,"unknown UI pixel");
                    if(col==32 && row==88 && rgb !== ((menu_active && cursor==0) ? 24'hFFD166 : 24'h9BB8C4))
                        $fatal(1,"selection border");
                    if(!page && !screen_page && !subtitle_page && cursor==0 && col==168 && row==168 && menu_active && rgb!==24'hFFD166)
                        $fatal(1,"selection dot");
                    if(((!page && !screen_page && !subtitle_page && col==216) || ((page || screen_page || subtitle_page) && col==320)) && row==100 && rgb!==24'h07131D) $fatal(1,"card gutter");
                    // Check actual RGB, not only character requests: each source
                    // Native 32x32 bits must map 1:1 without old ASCII beneath them.
                    if(!page && !screen_page && !subtitle_page && col>=40 && col<72 && row>=104 && row<136) begin
                        cjk_reference_row=TU_GLYPH[(31-(row-104))*32 +: 32];
                        expected_title=cjk_reference_row[31-(col-40)] ? 24'hF5FBFF :
                                       ((menu_active && cursor==0) ? 24'h075E78 : 24'h102A3A);
                        if(rgb!==expected_title)
                            $fatal(1,"CJK native32 pixel x=%0d y=%0d got=%h expected=%h",col,row,rgb,expected_title);
                    end
                    // Check the entire old title footprint outside the CJK width.
                    if(dut.card_area && dut.local_y>=16 && dut.local_y<48) begin
                        title_width=screen_page ? ((dut.card_idx==3) ? 128 : ((dut.card_idx==1) ? 96 : 64)) :
                                    ((page && (dut.card_idx==1 || dut.card_idx==3)) ? 96 : 64);
                        if(dut.local_x>=16+title_width && dut.local_x<144) begin
                            expected_title=(menu_active && dut.card_idx==cursor) ? 24'h075E78 : 24'h102A3A;
                            if(rgb!==expected_title) $fatal(1,"residual ASCII title x=%0d y=%0d",col,row);
                        end
                    end
                    if(menu_active && row>=440 && rgb!==24'h0D2633)
                        $fatal(1,"menu footer must be empty x=%0d y=%0d",col,row);
                    if(!menu_active && row>=444 && row<476 && col>=32 && col<288) begin
                        footer_line=(row<460) ? "K2 NEXT IMAGE   K3 AUTO         " :
                                               "HOLD K3 MENU                    ";
                        footer_char=footer_line[(31-(col-32)/8)*8 +: 8];
                        footer_bits=reference_font[{footer_char[6:0],4'b0}+(row-444)%16];
                        expected_footer=footer_bits[7-(col-32)%8] ? 24'hF5FBFF : 24'h0D2633;
                        if(rgb!==expected_footer) $fatal(1,"playback footer glyph x=%0d y=%0d",col,row);
                    end
                    if(mode==5 && col==568 && row==352 && rgb!==24'hFFD166)
                        $fatal(1,"sixth card selection dot");
                    // 对比度的实际 RGB 字形，独立 ASCII 参考核对数值和缩放。
                    if(screen_page && col>=352 && col<416 && row>=160 && row<192) begin
                        number_text=screen_edit ? "113% " : "100% ";
                        number_char=number_text[(4-(col-352)/16)*8 +: 8];
                        number_row=reference_font[{number_char[6:0],4'b0}+(row-160)/2];
                        number_expected=number_row[7-((col-352)/2)%8] ?
                                        (screen_edit ? 24'hFFD166 : 24'h4BE38A) :
                                        ((cursor==1) ? 24'h075E78 : 24'h102A3A);
                        if(rgb!==number_expected) $fatal(1,"screen numeric RGB x=%0d y=%0d got=%h expected=%h",col,row,rgb,number_expected);
                    end
                    $fwrite(dump,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
                end
            $fclose(dump);
        end
        @(negedge clk); de=0;
        @(posedge clk); #1;
        if(rgb!==0) $fatal(1,"blanking");
        $display("TB_MONITOR_MENU_RENDERER PASS"); $finish;
    end
    initial begin #33000000; $fatal(1,"renderer timeout"); end
endmodule
