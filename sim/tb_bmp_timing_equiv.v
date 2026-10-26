`timescale 1ns/1ps
// 用修改前解析器逐拍对照，并以独立像素公式检查有效输出。
// 参考模块由验证脚本从归档生成；不得把新实现复制成参考模型。
module tb_bmp_timing_equiv;
    parameter integer BYTE_GAP = 0;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg start=0, ack=0, dv=0, sec_end=0;
    reg [7:0] data=0;
    wire ready, done, error, active, req, wr_req, wr_en;
    wire ref_ready, ref_done, ref_error, ref_active, ref_req, ref_wr_req, ref_wr_en;
    wire [31:0] addr, ref_addr;
    wire [23:0] pixel, ref_pixel;
    wire [15:0] width, height, ref_width, ref_height;
    wire [3:0] code, ref_code, state_code, ref_state_code;
`define BMP_PORTS(READY,DONE,ERROR,ACTIVE,REQ,WREQ,WEN,ADDR,PIXEL,W,H,CODE,STATE) \
        .clk(clk),.rst(rst),.ready(READY), \
        .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0), \
        .scan_target_count(4'd0),.scan_done(),.scan_found_valid(),.scan_found_sector(), \
        .scan_found_total(),.scan_found_w(),.scan_found_h(), \
        .load_start(start),.load_sector(32'd0),.load_done(DONE),.load_error(ERROR), \
        .error_code(CODE),.load_active(ACTIVE),.load_img_w(W),.load_img_h(H), \
        .sd_init_done(1'b1),.state_code(STATE),.write_req(WREQ),.write_req_ack(ack), \
        .sd_sec_read(REQ),.sd_sec_read_addr(ADDR),.sd_sec_read_data(data), \
        .sd_sec_read_data_valid(dv),.sd_sec_read_end(sec_end),.sd_sec_read_error(1'b0), \
        .bmp_data_wr_en(WEN),.bmp_data(PIXEL)
    bmp_read_g dut (`BMP_PORTS(ready,done,error,active,req,wr_req,wr_en,addr,pixel,width,height,code,state_code));
    bmp_read_g_ref reference (`BMP_PORTS(ref_ready,ref_done,ref_error,ref_active,ref_req,ref_wr_req,ref_wr_en,ref_addr,ref_pixel,ref_width,ref_height,ref_code,ref_state_code));
`undef BMP_PORTS

    reg [7:0] card [0:32767];
    integer count=0, compare_cycles=0, expected_pixels=0;
    reg checking=0;
    reg [23:0] expected;
    // 两份RTL用同一输入；除有效像素外，也比较协议/完成/错误的每一拍。
    always @(negedge clk) begin
        if (!rst) begin
            compare_cycles=compare_cycles+1;
            if ({ready,done,error,active,req,wr_req,wr_en,addr,width,height,code,state_code} !==
                {ref_ready,ref_done,ref_error,ref_active,ref_req,ref_wr_req,ref_wr_en,ref_addr,ref_width,ref_height,ref_code,ref_state_code})
                $fatal(1,"FAIL BMP cycle equivalence at %t",$time);
            if(wr_en) begin
                if(pixel !== ref_pixel) $fatal(1,"FAIL reference pixel mismatch");
                if(checking) begin
                    expected={8'h01+count[6:0],8'h40+count[6:0],8'h80+count[6:0]};
                    if(pixel!==expected || count>=expected_pixels)
                        $fatal(1,"FAIL independent pixel #%0d got=%h expected=%h",count,pixel,expected);
                end
                count=count+1;
            end
        end
    end

    // 独立扇区模型：严格连续供数或固定空拍；end在最后一个字节之后单独一拍。
    integer sector_index=0, byte_index=0, gap_left=0, delay_left=-1;
    reg end_sent=0;
    always @(posedge clk) begin
        if(rst) begin
            dv<=0;sec_end<=0;delay_left<=-1;
        end else if(req && delay_left==-1) begin
            if(addr>=64) $fatal(1,"FAIL unexpected sector address %d",addr);
            sector_index<=addr*512;byte_index<=0;gap_left<=0;
            delay_left<=3;end_sent<=0;dv<=0;sec_end<=0;
        end else if(delay_left>0) begin
            delay_left<=delay_left-1;
        end else if(delay_left==0) begin
            if(gap_left>0) begin dv<=0;gap_left<=gap_left-1;end
            else if(byte_index<512) begin
                dv<=1;data<=card[sector_index+byte_index];
                byte_index<=byte_index+1;gap_left<=BYTE_GAP;
            end else if(!end_sent) begin dv<=0;sec_end<=1;end_sent<=1;end
            else begin sec_end<=0;delay_left<=-1;end
        end else begin dv<=0;sec_end<=0;end
    end

    task put32;
        input integer pos;
        input [31:0] value;
        begin
            card[pos]=value[7:0];card[pos+1]=value[15:8];
            card[pos+2]=value[23:16];card[pos+3]=value[31:24];
        end
    endtask
    integer cases=0;
    task check_image;
        input integer w,h,offset;
        integer n,r,c,rb,k,base;
        begin
            @(negedge clk);#1;rst=1;start=0;ack=0;
            repeat(4)@(negedge clk);
            for(n=0;n<32768;n=n+1) card[n]=8'hA5;
            for(n=0;n<54;n=n+1)card[n]=0;
            rb=(w*3+3)&~3;
            card[0]="B";card[1]="M";
            put32(2,offset+rb*h);put32(10,offset);put32(14,40);
            put32(18,w);put32(22,h);card[26]=1;card[28]=24;
            k=0;
            for(r=0;r<h;r=r+1)for(c=0;c<w;c=c+1)begin
                base=offset+r*rb+c*3;
                card[base]=8'h80+k[6:0];card[base+1]=8'h40+k[6:0];card[base+2]=8'h01+k[6:0];
                k=k+1;
            end
            count=0;expected_pixels=w*h;checking=1;
            #1;rst=0;
            @(negedge clk);#1;start=1;@(negedge clk);#1;start=0;
            wait(wr_req);@(negedge clk);#1;ack=1;@(negedge clk);#1;ack=0;
            wait(done || error);@(negedge clk);#1;
            if(error || count!=w*h || width!=w || height!=h)
                $fatal(1,"FAIL BMP geometry/count w=%d h=%d offset=%d pixels=%d code=%d",w,h,offset,count,code);
            cases=cases+1;
        end
    endtask

    integer n,bitno,seed=32'h16352025;
    reg [31:0] a,b;
    task check_compare;
        input [31:0] left,right;
        begin
            if(dut.less_u32(left,right)!==(left<right))
                $fatal(1,"FAIL unsigned comparison %h %h",left,right);
        end
    endtask
    initial begin
        // 高字节相等/不等和跨进位边界；包括32位文件偏移高位，不能只测小图片。
        check_compare(0,0);check_compare(0,32'hffffffff);check_compare(32'hffffffff,0);
        for(bitno=0;bitno<32;bitno=bitno+1)begin
            a=32'd1<<bitno;
            check_compare(a-1,a);check_compare(a,a);check_compare(a,a-1);
            check_compare(a,a+1);check_compare(a+1,a);
        end
        for(n=0;n<100000;n=n+1)begin
            a=$random(seed);b=$random(seed);
            check_compare(a,b);check_compare(b,a);check_compare(a,a);
        end
        check_image(1,2,54);check_image(2,2,255);check_image(3,2,256);
        check_image(4,3,511);check_image(5,2,512);check_image(7,3,513);
        check_image(8,2,1023);check_image(31,3,1024);
        check_image(170,3,54);check_image(171,3,54);
        check_image(1280,2,54);check_image(2047,2,54);
        check_image(1,720,54);
        $display("TB_BMP_TIMING_EQUIV PASS cases=%0d cycles=%0d gap=%0d compares=300163",cases,compare_cycles,BYTE_GAP);
        $finish;
    end
    initial begin #200000000;$fatal(1,"FAIL BMP equivalence timeout");end
endmodule
