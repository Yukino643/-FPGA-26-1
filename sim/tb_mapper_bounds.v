`timescale 1ns/1ps
// 公共接口边界验证：最大文件的最后扇区、非法高位、簇链上限、精确超时。
module mapper_timeout_check #(parameter T=17)(output reg finished=0);
    reg clk=0,rst=1,start=0,req=0,done=0;
    always #5 clk=~clk;
    wire sector_req,client_done,client_error;
    fat32_file_sector_mapper #(.TIMEOUT_CYCLES(T)) dut(
        .clk(clk),.rst(rst),.file_start(start),.first_cluster(32'd2),.file_size(32'd512),
        .sectors_per_cluster(8'd1),.sectors_per_cluster_shift(3'd0),
        .fat_start_lba(32'd128),.data_start_lba(32'd4096),.max_cluster(32'd100),
        .client_req(req),.client_sector_index(32'd0),.client_done(client_done),.client_error(client_error),
        .sector_req(sector_req),.sector_busy(1'b0),.sector_valid(1'b0),
        .sector_byte_index(9'd0),.sector_byte(8'd0),.sector_done(done),.sector_error(8'd0));
    integer trial,n;
    initial begin
        for(trial=0;trial<2;trial=trial+1)begin
            rst=1;repeat(3)@(negedge clk);rst=0;start=1;
            @(negedge clk);start=0;req=1;
            wait(sector_req);@(negedge clk);
            for(n=1;n<=T;n=n+1)begin
                if(trial==1 && n==T)done=1;
                @(posedge clk);#1;
                if(n<T && client_done)$fatal(1,"mapper early timeout %0d",T);
                if(n==T && (!client_done || client_error!==(trial==0)))
                    $fatal(1,"mapper timeout/done priority T=%0d trial=%0d",T,trial);
                @(negedge clk);
            end
            req=0;done=0;
        end
        finished=1;
    end
endmodule

module mapper_range_check #(parameter MAX_CHAIN=65536)(output reg finished=0);
    reg clk=0,rst=1,start=0,req=0;
    always #5 clk=~clk;
    reg [31:0] size=0,index=0;
    reg [7:0] spc=1;
    reg [2:0] shift=0;
    wire sector_req,client_done,client_error;
    wire [31:0] lba;
    reg valid=0,done=0;
    reg [8:0] byte_index=0;
    reg [7:0] data=0;
    fat32_file_sector_mapper #(.MAX_CHAIN_STEPS(MAX_CHAIN),.TIMEOUT_CYCLES(17)) dut(
        .clk(clk),.rst(rst),.file_start(start),.first_cluster(32'd2),.file_size(size),
        .sectors_per_cluster(spc),.sectors_per_cluster_shift(shift),
        .fat_start_lba(32'd128),.data_start_lba(32'd4096),.max_cluster(32'h0fffffff),
        .client_req(req),.client_sector_index(index),.client_done(client_done),.client_error(client_error),
        .sector_req(sector_req),.sector_lba(lba),.sector_busy(1'b0),.sector_valid(valid),
        .sector_byte_index(byte_index),.sector_byte(data),.sector_done(done),.sector_error(8'd0));
    integer links,requests,j,k;
    reg [31:0] model_cluster,next_cluster;
    task begin_file;
        input [31:0] bytes;
        input [7:0] cluster_sectors;
        input [2:0] cluster_shift;
        begin
            @(negedge clk);size=bytes;spc=cluster_sectors;shift=cluster_shift;start=1;
            @(negedge clk);start=0;model_cluster=2;
        end
    endtask
    task read_sector;
        input [31:0] sector,expected_lba;
        input expect_error;
        begin
            @(negedge clk);index=sector;req=1;links=0;requests=0;
            while(!client_done)begin
                @(negedge clk);
                if(sector_req)begin
                    requests=requests+1;
                    if(lba<4096)begin
                        if(lba!==128+(model_cluster>>7))$fatal(1,"FAT LBA %h cluster %h",lba,model_cluster);
                        next_cluster=model_cluster+1;
                        for(j=0;j<4;j=j+1)begin
                            valid=1;byte_index=(model_cluster%128)*4+j;data=next_cluster>>(j*8);
                            @(negedge clk);
                        end
                        valid=0;links=links+1;model_cluster=next_cluster;
                    end else if(lba!==expected_lba)$fatal(1,"data LBA %h expected %h",lba,expected_lba);
                    done=1;@(negedge clk);done=0;
                end
            end
            if(client_error!==expect_error)$fatal(1,"range/chain result sector=%h error=%b",sector,client_error);
            if(expect_error && sector[31:23]!=0 && requests!=0)$fatal(1,"invalid high bits issued IO");
            req=0;repeat(3)@(negedge clk);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        begin_file(0,1,0);read_sector(0,0,1);
        begin_file(512,1,0);read_sector(0,4096,0);read_sector(1,0,1);
        begin_file(513,1,0);read_sector(1,4097,0);
        if(MAX_CHAIN==65536)begin
            begin_file(32'hffffffff,128,7);
            read_sector(32'h007fffff,32'h00800fff,0);
            if(links!=65535)$fatal(1,"maximum sector did not traverse complete chain");
            read_sector(32'h00800000,0,1);read_sector(32'h01000000,0,1);
            read_sector(32'h80000000,0,1);read_sector(32'hffffffff,0,1);
        end else begin
            begin_file(4096,1,0);read_sector(MAX_CHAIN-1,4096+MAX_CHAIN-1,0);
            if(links!=MAX_CHAIN-1)$fatal(1,"chain limit reached early");
            read_sector(MAX_CHAIN,0,1);
            if(links!=0)$fatal(1,"chain guard allowed one extra link");
        end
        finished=1;
    end
endmodule

module tb_mapper_bounds;
    wire a,b,c,d,e;
    mapper_timeout_check #(.T(1)) t1(a);
    mapper_timeout_check #(.T(2)) t2(b);
    mapper_timeout_check #(.T(17)) t17(c);
    mapper_range_check large_file(d);
    mapper_range_check #(.MAX_CHAIN(4)) small_chain(e);
    initial begin
        wait(a&&b&&c&&d&&e);
        $display("PASS mapper_bounds max4GiB tail 65535 FAT links, high-bit rejection, exact chain cap, timeout 1/2/17 done priority");
        $finish;
    end
    initial begin #30000000;$fatal(1,"mapper bounds hung");end
endmodule
