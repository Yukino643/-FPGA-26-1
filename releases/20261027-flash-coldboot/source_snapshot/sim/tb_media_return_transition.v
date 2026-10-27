`timescale 1ns/1ps
// 独立旧版逐拍参考验证默认行为；返回首张另按VS数及饱和权重验收。
module tb_media_return_transition;
    reg clk=0,rst=1,vs=0,commit=0,returning=0,seed=0;
    reg [1:0] target=1,mode=1;
    wire [71:0] legacy_bus,default_bus;
    wire active,hold_load,fade,up_a,up_b;
    wire [7:0] alpha;
    wire [9:0] boundary;
    wire [1:0] axis;
    wire [20:0] page_a,page_b;
    integer comparisons=0,checks=0;
    always #5 clk=~clk;
    transition_ctrl_legacy #(.SEED_ENABLE(1)) legacy(
        .clk(clk),.rst(rst),.vs_rise(vs),.initial_front(seed),.x(10'd0),.y(9'd0),
        .commit_toggle(commit),.commit_buf(target),.tr_mode(mode),
        .tr_active(legacy_bus[0]),.alpha(legacy_bus[8:1]),.boundary(legacy_bus[18:9]),
        .slide_axis(legacy_bus[20:19]),.page_a_base(legacy_bus[41:21]),
        .page_b_base(legacy_bus[62:42]),.page_upd_a(legacy_bus[63]),
        .page_upd_b(legacy_bus[64]),.hold_load(legacy_bus[65]),.fade_black(legacy_bus[66]));
    transition_ctrl #(.SEED_ENABLE(1)) defaults(
        .clk(clk),.rst(rst),.vs_rise(vs),.initial_front(seed),.return_from_video(returning),
        .x(10'd0),.y(9'd0),.commit_toggle(commit),.commit_buf(target),.tr_mode(mode),
        .tr_active(default_bus[0]),.alpha(default_bus[8:1]),.boundary(default_bus[18:9]),
        .slide_axis(default_bus[20:19]),.page_a_base(default_bus[41:21]),
        .page_b_base(default_bus[62:42]),.page_upd_a(default_bus[63]),
        .page_upd_b(default_bus[64]),.hold_load(default_bus[65]),.fade_black(default_bus[66]));
    transition_ctrl #(.SEED_ENABLE(1),.RETURN_SPEEDUP(1),.RETURN_ALPHA_STEP(32)) fast(
        .clk(clk),.rst(rst),.vs_rise(vs),.initial_front(seed),.return_from_video(returning),
        .x(10'd0),.y(9'd0),.commit_toggle(commit),.commit_buf(target),.tr_mode(mode),
        .tr_active(active),.alpha(alpha),.boundary(boundary),.slide_axis(axis),
        .page_a_base(page_a),.page_b_base(page_b),.page_upd_a(up_a),.page_upd_b(up_b),
        .hold_load(hold_load),.fade_black(fade));
    always @(posedge clk) begin
        #1;
        if(default_bus[66:0]!==legacy_bus[66:0]) $fatal(1,"FAIL default/legacy cycle mismatch");
        comparisons=comparisons+1;
    end
    task reset_case;
        input initial_page,return_flag;
        begin
            @(negedge clk);rst=1;vs=0;commit=0;seed=initial_page;returning=return_flag;
            repeat(3)@(negedge clk);rst=0;
            repeat(3)@(negedge clk);
            if(page_a!==(seed?21'h80000:21'd0))$fatal(1,"FAIL seed");
        end
    endtask
    task frame;
        reg [20:0] held_a;
        reg [7:0] held_alpha;
        begin
            held_a=page_a;held_alpha=alpha;
            repeat(4)@(negedge clk);
            if(page_a!==held_a || alpha!==held_alpha)$fatal(1,"FAIL changed outside VS");
            vs=1;@(negedge clk);vs=0;
        end
    endtask
    task submit;
        input [1:0] dest,effect;
        begin
            @(negedge clk);target=dest;mode=effect;commit=1;
            @(negedge clk);commit=0;
            if(!hold_load)$fatal(1,"FAIL mailbox not held");
        end
    endtask
    task blend;
        input [1:0] dest;
        input integer step_size,expected_frames;
        integer i,expected;
        reg [20:0] old;
        begin
            old=page_a;submit(dest,1);
            // 提交后反转外部条件，验证已锁存的首帧属性不会被撤销或追加。
            returning=~returning;
            frame;
            if(!active || alpha!=0 || !up_b || page_a!=old)$fatal(1,"FAIL blend start");
            for(i=1;i<=expected_frames;i=i+1)begin
                frame;expected=i*step_size;if(expected>255)expected=255;
                if(alpha!==expected || !active || !hold_load || fade)$fatal(1,"FAIL alpha/frame=%0d value=%0d expected=%0d",i,alpha,expected);
                if(i<expected_frames && page_a!=old)$fatal(1,"FAIL early front change");
            end
            if(alpha!=255 || page_a!==(dest[0]?21'h80000:21'd0) || !up_a)$fatal(1,"FAIL saturated front");
            frame;
            if(active || hold_load || page_a!=page_b)$fatal(1,"FAIL settle/release");
            // 默认版仍须跑完，下一事务才不会覆盖参考的在途转场。
            while(defaults.hold_load)frame;
            checks=checks+1;
            $display("MEASURE blend check=%0d frames=%0d step=%0d",checks,expected_frames,step_size);
        end
    endtask
    integer k;
    initial begin
        reset_case(0,0);blend(1,8,32);returning=1;blend(0,8,32);
        reset_case(1,1);blend(0,32,8);returning=1;blend(1,8,32);
        reset_case(0,1);blend(1,32,8);
        // 直切和滑动模式保持原行为，不将首帧标志误用为全局步长。
        for(k=0;k<4;k=k+1)begin
            reset_case(k[0],1);submit(k[0]?0:1,k[1:0]);
            frame;while(hold_load || defaults.hold_load)frame;
            if(page_a!==default_bus[41:21] || active)$fatal(1,"FAIL effect compatibility");
        end
        $display("TB_MEDIA_RETURN_TRANSITION PASS slow=32 fast=8 saved_vs=24 checks=%0d comparisons=%0d",checks,comparisons);
        $finish;
    end
    initial begin #1000000;$fatal(1,"FAIL timeout");end
endmodule
