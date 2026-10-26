`timescale 1ns/1ps
// 周期卡四档逐像素核对；参考为独立ASCII字模与固定文案，不读取DUT标签函数。
module tb_autoplay_labels;
    reg clk=0;
    always #5 clk=~clk;
    reg [1:0] period_sel=0;
    reg [9:0] x=0;
    reg [8:0] y=0;
    wire [23:0] rgb;
    reg [7:0] font [0:2047];
    reg [79:0] label;
    reg [7:0] ch,bits;
    reg [23:0] expected;
    integer sel,xx,yy;
    monitor_menu_renderer dut(
        .clk(clk),.de(1'b1),.x(x),.y(y),.page(1'b0),.menu_active(1'b1),.cursor(3'd4),
        .audio_page(1'b0),.audio_edit(1'b0),.audio_shadow(5'd10),.audio_active(5'd10),
        .screen_page(1'b0),.screen_edit(1'b0),.screen_shadow(10'h144),.screen_active(10'h144),
        .subtitle_page(1'b0),.subtitle_edit(1'b0),.subtitle_shadow(5'h09),.subtitle_active(5'h09),
        .cfg_busy(1'b0),.cfg_shadow(4'd7),.cfg_active(4'd7),
        .period_shadow(period_sel),.period_active(period_sel),.cfg_dirty(1'b0),
        .commit_seen(1'b0),.buzzer_test(1'b0),.key_state(3'd0),.key_events(16'd0),
        .sd_init_done(1'b1),.img_count(4'd7),.rgb(rgb));
    initial begin
        $readmemh("D:/FPGA/code/example/rtl/ctrl/font_ascii_bram.hex",font);
        for(sel=0;sel<4;sel=sel+1)begin
            @(negedge clk);period_sel=sel;
            case(sel)
                0:label="        2S";1:label="        3S";
                2:label="        5S";3:label="       10S";
            endcase
            for(yy=0;yy<32;yy=yy+1)begin
                for(xx=0;xx<160;xx=xx+1)begin
                    @(negedge clk);x=236+xx;y=282+yy;
                    repeat(4)@(negedge clk);
                    ch=label[(9-xx/16)*8 +: 8];
                    bits=font[ch[6:0]*16+yy/2];
                    expected=bits[7-(xx%16)/2] ? 24'hC9DBE5 : 24'h1B4658;
                    if(rgb!==expected)$fatal(1,"period label %0d pixel %0d,%0d expected %h actual %h",sel,xx,yy,expected,rgb);
                end
            end
            $display("PERIOD_LABEL preset=%0d text=%s pixels=5120 PASS",sel,label);
        end
        $display("TB_AUTOPLAY_LABELS PASS all_four_presets");
        $finish;
    end
    initial begin #2000000;$fatal(1,"period label timeout");end
endmodule
