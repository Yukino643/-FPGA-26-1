`timescale 1ns/1ps
module tb_video_axis;
    reg clk=0, rst=1, vs=0, de=0;
    reg [23:0] rgb=0;
    wire user, valid, last;
    wire [23:0] data;
    integer row, x;
    always #5 clk=~clk;
    video_rgb_to_axis_640x480 dut(
        .I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de), .I_rgb(rgb),
        .O_video_user(user), .O_video_valid(valid), .O_video_last(last), .O_video_data(data));
    initial begin
        #12; rst=0;
        for(row=0;row<2;row=row+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk); de=1; rgb=row*640+x;
                @(posedge clk); #1;
                // 行尾必须与第 640 个有效像素同拍，帧首仅出现一次。
                if(!valid || data !== row*640+x || last !== (x==639) || user !== (row==0 && x==0))
                    $fatal(1,"FAIL AXIS row=%0d x=%0d last=%b user=%b",row,x,last,user);
            end
            @(negedge clk); de=0;
            @(posedge clk); #1;
            if(valid || last || user) $fatal(1,"FAIL AXIS blanking");
        end
        $display("TB_VIDEO_AXIS PASS"); $finish;
    end
    initial begin #100000; $fatal(1,"FAIL AXIS timeout"); end
endmodule
