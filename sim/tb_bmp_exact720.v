`timescale 1ns/1ps
// 在write_req之前拒绝不兼容素材，防止错误尺寸破坏空闲页边界。
module tb_bmp_exact720;
    reg clk=0,rst=1,start=0,dv=0,end_sector=0;
    always #5 clk=~clk;
    reg [7:0] data=0,header[0:511];
    wire ready,req,error,write_req,active;
    wire [3:0] code;
    bmp_read_g #(.EXACT_WIDTH(1280),.EXACT_HEIGHT(720)) dut(
        .clk(clk),.rst(rst),.ready(ready),.scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),
        .scan_target_count(4'd0),.scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),.scan_found_w(),.scan_found_h(),
        .load_start(start),.load_sector(32'd0),.load_done(),.load_error(error),.error_code(code),.load_active(active),.load_img_w(),.load_img_h(),
        .sd_init_done(1'b1),.state_code(),.write_req(write_req),.write_req_ack(1'b0),.sd_sec_read(req),.sd_sec_read_addr(),
        .sd_sec_read_data(data),.sd_sec_read_data_valid(dv),.sd_sec_read_end(end_sector),.sd_sec_read_error(1'b0),.bmp_data_wr_en(),.bmp_data());
    integer i,w,h,size,cycles;
    task put32;
        input integer offset,value;
        begin header[offset]=value;header[offset+1]=value>>8;header[offset+2]=value>>16;header[offset+3]=value>>24;end
    endtask
    task check;
        input integer width,height,expect_success;
        begin
            rst=1;repeat(3) @(negedge clk);rst=0;
            for(i=0;i<512;i=i+1) header[i]=0;
            header[0]="B";header[1]="M";put32(2,54+width*3*height);put32(10,54);put32(14,40);
            put32(18,width);put32(22,height);header[26]=1;header[28]=24;
            wait(ready);@(negedge clk);start=1;@(negedge clk);start=0;
            wait(req);repeat(3) @(negedge clk);
            for(i=0;i<512;i=i+1) begin @(negedge clk);data=header[i];dv=1;end
            @(negedge clk);dv=0;end_sector=1;@(negedge clk);end_sector=0;
            cycles=0;
            while(!error && !write_req && cycles<100) begin @(negedge clk);cycles=cycles+1;end
            if(expect_success && (!write_req || error)) $fatal(1,"FAIL valid720 header rejected");
            if(!expect_success && (!error || write_req || code!=1)) $fatal(1,"FAIL incompatible header accepted %d %d",width,height);
        end
    endtask
    initial begin
        check(640,480,0);check(1920,1080,0);check(1280,719,0);check(1280,720,1);
        $display("TB_BMP_EXACT720 PASS incompatible sizes rejected before writer request");$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL exact720 timeout");end
endmodule
