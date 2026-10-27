`timescale 1ns/1ps
module tb_mixer565;
    reg clk=0,rst=1,de=0,vs=0,active=0;
    always #6.734 clk=~clk;
    reg [10:0] x=0;
    reg [9:0] y=0;
    reg [31:0] a=0,b=0;
    reg [7:0] alpha=0;
    wire ap,bp,dout,vout;
    wire [10:0] xo;
    wire [9:0] yo;
    wire [23:0] rgb;
    wire [31:0] underflow;
    disp_mixer_565 dut(.clk(clk),.rst(rst),.de_in(de),.vs_in(vs),.x(x),.y(y),
        .a_data(a),.b_data(b),.a_empty(1'b0),.b_empty(1'b0),.tr_active(active),.alpha(alpha),
        .a_pop(ap),.b_pop(bp),.de_out(dout),.vs_out(vout),.x_out(xo),.y_out(yo),.rgb_out(rgb),.underflow_cnt(underflow));
    function [23:0] expand;
        input [15:0] p;
        integer r,g,bl;
        reg [7:0] rr,gg,bb;
        begin r=(p>>11)&31; g=(p>>5)&63; bl=p&31;
            rr=r*8+r/4; gg=g*4+g/16; bb=bl*8+bl/4; expand={rr,gg,bb}; end
    endfunction
    reg [23:0] expected[0:1];
    reg [1:0] valid=0;
    reg [10:0] expected_x[0:1];
    reg [9:0] expected_y[0:1];
    reg [23:0] pa,pb;
    integer r,g,bl,i,n;
    always @(posedge clk) begin
        if (!rst) begin
            expected[1]=expected[0]; expected_x[1]=expected_x[0]; expected_y[1]=expected_y[0];
            pa=expand(x[0] ? a[31:16]:a[15:0]); pb=expand(x[0] ? b[31:16]:b[15:0]);
            r=(pa[23:16]*(256-alpha)+pb[23:16]*alpha+128)/256;
            g=(pa[15:8]*(256-alpha)+pb[15:8]*alpha+128)/256;
            bl=(pa[7:0]*(256-alpha)+pb[7:0]*alpha+128)/256;
            expected[0]= !active || alpha==0 ? pa : alpha==255 ? pb : {r[7:0],g[7:0],bl[7:0]};
            expected_x[0]=x;expected_y[0]=y;
            valid={valid[0],de};
            if(ap!==(de && x[0]) || bp!==(de && x[0] && active)) $fatal(1,"FAIL halfword pop");
            #1;
            if(dout!==valid[1]) $fatal(1,"FAIL mixer DE latency");
            if(dout && (rgb!==expected[1] || xo!==expected_x[1] || yo!==expected_y[1]))
                $fatal(1,"FAIL RGB565 weights/geometry alpha=%d rgb=%h expected=%h",alpha,rgb,expected[1]);
        end
    end
    initial begin
        repeat(3) @(negedge clk);rst=0;
        for(n=0;n<256;n=n+1) begin
            @(negedge clk);alpha=n;active=1;
            for(i=0;i<6;i=i+1) begin
                @(negedge clk);de=1;x=i==5 ? 1279:i; y=719;
                a={$random};b={$random};
            end
        end
        @(negedge clk);de=0;repeat(5) @(negedge clk);
        if(underflow!=0) $fatal(1,"FAIL unexpected underflow");
        $display("TB_MIXER565 PASS all256 weights, odd/even halves, x1279 y719, aligned latency");$finish;
    end
endmodule
