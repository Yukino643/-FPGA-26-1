`timescale 1ns/1ps
module tb_emergency_render;
    reg clk=0;
    always #5 clk=~clk;
    reg de_in=0, emergency_mode=0;
    reg [10:0] x=0;
    reg [9:0] y=0;
    reg [23:0] normal_rgb=24'h123456;
    wire [23:0] rgb_out;
    emergency_render #(.X_BITS(11),.Y_BITS(10)) dut(
        .clk(clk), .de_in(de_in), .x(x), .y(y),
        .emergency_mode(emergency_mode), .normal_rgb(normal_rgb), .rgb_out(rgb_out));
    integer frame, row, col, phase, pixels=0, dump;
    reg [23:0] expected;
    initial begin
        repeat(2) @(negedge clk);
        if(rgb_out!==normal_rgb) $fatal(1,"normal passthrough");
        emergency_mode=1;
        dump=$fopen("emergency720.ppm","w");
        $fwrite(dump,"P3\n1280 720\n255\n");
        // 全宽覆盖 1024 列以上及行消隐；独立参考要求每帧相位恒定。
        for(frame=0;frame<2;frame=frame+1) begin
            phase=(frame+1)*2;
            for(row=0;row<720;row=row+1) begin
                for(col=0;col<1280;col=col+1) begin
                    @(negedge clk); de_in=1; x=col; y=row;
                    #1;
                    expected=24'hC00000;
                    if(row>=180 && row<220) expected=24'hFFFFFF;
                    if(row>=280 && row<300 && ((col+phase)%32)<16) expected=24'hFFDD00;
                    if(rgb_out!==expected) $fatal(1,"raster f=%0d x=%0d y=%0d got=%h expected=%h",frame,col,row,rgb_out,expected);
                    if(frame==0) $fwrite(dump,"%0d %0d %0d\n",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
                    pixels=pixels+1;
                end
                @(negedge clk); de_in=0;
                repeat(4) @(negedge clk);
            end
        end
        $fclose(dump); emergency_mode=0;
        #1; if(rgb_out!==normal_rgb) $fatal(1,"normal return");
        $display("TB_EMERGENCY_RENDER PASS pixels=%0d",pixels); $finish;
    end
    initial begin #30000000; $fatal(1,"emergency timeout"); end
endmodule
