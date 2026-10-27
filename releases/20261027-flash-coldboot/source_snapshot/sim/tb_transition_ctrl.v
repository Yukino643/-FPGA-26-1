`timescale 1ns/1ps
// 仅 VS 更新可见状态；覆盖无黑场交叉淡化、横向接缝和两页交接。
module tb_transition_ctrl;
    reg clk=0, rst=1, vs=0, commit=0, de=1, b_empty=0;
    reg [1:0] buf_idx=1, mode=0;
    reg [9:0] x=0;
    reg [8:0] y=0;
    wire tr, fade, upd_a, upd_b, hold_load, a_re, b_re;
    wire [7:0] alpha;
    wire [9:0] boundary;
    wire [1:0] axis;
    wire [20:0] page_a, page_b;
    wire [23:0] rgb;
    wire [31:0] underflow;
    wire [23:0] pa = page_a==0 ? 24'hc86432 : 24'h204080;
    wire [23:0] pb = page_b==0 ? 24'hc86432 : 24'h204080;
    integer previous, frames, k;
    reg [23:0] expected;
    always #5 clk=~clk;
    transition_ctrl dut(.clk(clk), .rst(rst), .vs_rise(vs), .x(x), .y(y),
        .commit_toggle(commit), .commit_buf(buf_idx), .tr_mode(mode), .tr_active(tr),
        .alpha(alpha), .boundary(boundary), .slide_axis(axis), .page_a_base(page_a),
        .page_b_base(page_b), .page_upd_a(upd_a), .page_upd_b(upd_b),
        .hold_load(hold_load), .fade_black(fade));
    disp_mixer mix(.clk(clk), .rst(rst), .de_al(de), .x(x), .y(y),
        .a_rd_en(a_re), .a_rd_data({pa,8'd0}), .a_empty(1'b0),
        .b_rd_en(b_re), .b_rd_data({pb,8'd0}), .b_empty(b_empty),
        .tr_active(tr), .fade_black(fade), .alpha(alpha), .boundary(boundary),
        .slide_axis(axis), .rgb(rgb), .underflow_cnt(underflow));
    function [23:0] mixed;
        input [23:0] foreground;
        input [23:0] background;
        input integer weight;
        reg [7:0] r,g,b;
        begin
            r=(foreground[23:16]*weight+background[23:16]*(255-weight)+127)>>8;
            g=(foreground[15:8]*weight+background[15:8]*(255-weight)+127)>>8;
            b=(foreground[7:0]*weight+background[7:0]*(255-weight)+127)>>8;
            mixed=weight==255 ? foreground : weight==0 ? background : {r,g,b};
        end
    endfunction
    task frame_boundary;
        begin
            @(negedge clk); vs=1;
            @(negedge clk); vs=0;
            #1;
        end
    endtask
    task submit;
        input [1:0] target;
        input [1:0] effect;
        reg [20:0] old_page;
        begin
            old_page=page_a;
            @(negedge clk); buf_idx=target; mode=effect; commit=1;
            @(negedge clk); commit=0;
            repeat(3) @(negedge clk);
            if(page_a!==old_page || !hold_load) $fatal(1,"FAIL mid-frame page switch");
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        for(k=0;k<6;k=k+1) begin
            submit((k%2)==0 ? 1 : 0,0);
            frame_boundary;
            if(tr || hold_load || rgb!==pa || page_a!==((k%2)==0 ? 21'h80000 : 21'd0))
                $fatal(1,"FAIL direct cut %0d",k);
        end
        submit(1,1); frame_boundary;
        if(!tr || fade || alpha!=0 || page_a!=0) $fatal(1,"FAIL crossfade start");
        // B 权重为零时无需 B 数据；输入模式改动不能影响已锁存事务。
        b_empty=1; mode=3; #1;
        if(rgb!==pa) $fatal(1,"FAIL unused B FIFO caused black pixel");
        b_empty=0; previous=0; frames=0;
        while(dut.state==1) begin
            frame_boundary; frames=frames+1;
            if(alpha<=previous || frames>32 || fade || rgb!==mixed(pb,pa,alpha) || rgb==0)
                $fatal(1,"FAIL crossfade monotonic alpha=%0d previous=%0d",alpha,previous);
            if(alpha!=255 && page_a!=0) $fatal(1,"FAIL old page changed during blend");
            previous=alpha;
        end
        if(alpha!=255 || rgb!==pb || page_a!=21'h80000 || !hold_load)
            $fatal(1,"FAIL crossfade settle");
        frame_boundary;
        if(tr || alpha!=255 || hold_load || underflow!=0) $fatal(1,"FAIL crossfade completion");
        repeat(3) begin frame_boundary; if(rgb!==pa) $fatal(1,"FAIL crossfade flashed after complete"); end
        b_empty=0;
        for(k=2;k<=3;k=k+1) begin
            submit(k==2 ? 0 : 1,k); frame_boundary;
            if(!tr || axis!=(k==2 ? 1 : 2) || boundary!=0 || rgb!==pa)
                $fatal(1,"FAIL reveal start");
            frame_boundary;
            x=0; y=0; #1;
            if(rgb!==pa) $fatal(1,"FAIL slide leading pixels");
            x=639; y=479; #1;
            if(rgb!==pb) $fatal(1,"FAIL slide inserted pixels");
            x=640-boundary-1; y=480-boundary-1; #1;
            if(rgb!==pa) $fatal(1,"FAIL old side of seam");
            x=640-boundary; y=480-boundary; #1;
            if(rgb!==pb) $fatal(1,"FAIL new side of seam");
            frames=1;
            while(dut.state==2) begin
                frame_boundary; frames=frames+1;
                if(frames>40 || fade || rgb==0) $fatal(1,"FAIL slide timeout/black");
            end
            if(rgb!==pb || alpha!=255 || axis!=0 || !hold_load)
                $fatal(1,"FAIL reveal settle frame");
            frame_boundary;
            if(tr || hold_load || rgb!==pa || pa!==pb) $fatal(1,"FAIL reveal completion");
        end
        // 交接时 alpha=255 完全依赖 B；空 A 不能产生误报或黑像素。
        de=0; #1;
        if(rgb!=0 || a_re || b_re) $fatal(1,"FAIL blanking");
        $display("TB_TRANSITION_CTRL PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"FAIL transition timeout"); end
endmodule
