`timescale 1ns/1ps
// 同拍驱动两条路径，逐节点/逐列比对：分时读取不得改变算术结果。
module tb_waveform_tdm;
    wire a,b,c,d;
    tb_waveform_tdm_case #(.WIDTH(32)) t0(a);
    tb_waveform_tdm_case #(.WIDTH(512)) t1(b);
    tb_waveform_tdm_case #(.WIDTH(640)) t2(c);
    tb_waveform_tdm_case #(.WIDTH(1024)) t3(d);
    initial begin
        wait(a && b && c && d);
        $display("TB_WAVEFORM_TDM PASS exact_columns=%0d",t0.checks+t1.checks+t2.checks+t3.checks);
        $finish;
    end
    initial begin #20000000; $fatal(1,"FAIL waveform TDM timeout"); end
endmodule

module tb_waveform_tdm_case #(parameter WIDTH=1024)(output reg done=0);
    reg clk=0,rst=1,vs=0,valid=0;
    reg signed [15:0] pcm=0;
    integer group_no,n,column,cycles,checks=0;
    reg [31:0] random_state=32'hc7359021;
    always #5 clk=~clk;
    promax_audio_waveform #(.WAVE_X(0),.WAVE_Y(576),.WAVE_WIDTH(WIDTH),
        .WAVE_HEIGHT(88),.DECIMATE(1),.VIDEO_WIDTH(1280),.VIDEO_HEIGHT(720),
        .X_BITS(11),.Y_BITS(10),.PIPELINED_GEOMETRY(0)) reference_path(
        .clk(clk),.rst(rst),.vs_pulse(vs),.de(1'b0),.enable(1'b1),
        .pixel_x(11'd0),.pixel_y(10'd0),.rgb_in(24'd0),
        .pcm_tap_valid(valid),.pcm_tap_left(pcm),.rgb_out(),.waveform_active());
    promax_audio_waveform #(.WAVE_X(0),.WAVE_Y(576),.WAVE_WIDTH(WIDTH),
        .WAVE_HEIGHT(88),.DECIMATE(1),.VIDEO_WIDTH(1280),.VIDEO_HEIGHT(720),
        .X_BITS(11),.Y_BITS(10),.PIPELINED_GEOMETRY(1)) tdm_path(
        .clk(clk),.rst(rst),.vs_pulse(vs),.de(1'b0),.enable(1'b1),
        .pixel_x(11'd0),.pixel_y(10'd0),.rgb_in(24'd0),
        .pcm_tap_valid(valid),.pcm_tap_left(pcm),.rgb_out(),.waveform_active());
    task compare_frame;
    begin
        @(negedge clk); vs=1;
        @(negedge clk); vs=0; cycles=0;
        while(reference_path.build_state!=0 || tdm_path.build_state!=0) begin
            @(negedge clk); cycles=cycles+1;
            if(cycles>=25*1650) $fatal(1,"FAIL TDM missed real 720p blanking");
        end
        for(n=0;n<32;n=n+1)
            if(tdm_path.smooth_nodes[n] !== reference_path.smooth_nodes[n])
                $fatal(1,"FAIL TDM node width=%0d group=%0d node=%0d",WIDTH,group_no,n);
        for(column=0;column<WIDTH;column=column+1) begin
            if(tdm_path.curve_bounds[column] !== reference_path.curve_bounds[column] ||
               ^tdm_path.curve_bounds[column] === 1'bx)
                $fatal(1,"FAIL TDM bounds width=%0d group=%0d column=%0d",WIDTH,group_no,column);
            checks=checks+1;
        end
    end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        // 先建立静音节点；随后包含负满幅、交替极值、端点脉冲和确定性随机数。
        group_no=-1; compare_frame;
        for(group_no=0;group_no<64;group_no=group_no+1) begin
            for(column=0;column<32;column=column+1) begin
                @(negedge clk); valid=1;
                random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                case(group_no)
                    0: pcm=-16'sd32768;
                    1: pcm=16'sd32512;
                    2: pcm=column%2 ? -16'sd32768:16'sd32512;
                    3: pcm=(column==0 || column==31) ? 16'sd32512:16'sd0;
                    default: pcm={random_state[7:0],8'd0};
                endcase
                @(negedge clk); valid=0;
            end
            compare_frame;
        end
        $display("TB_WAVEFORM_TDM width=%0d exact_columns=%0d PASS",WIDTH,checks);
        done=1;
    end
endmodule
