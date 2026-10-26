`timescale 1ns/1ps
// 只量实有控制器的字节节拍，固定token/data用于隔离卡内容；不作为SD协议验证。
module tb_video_spi_budget;
    reg clk=0,rst=1,request=0;
    always #5 clk=~clk;
    wire spi_req,spi_ack,valid,done,ncs;
    wire [15:0] div;
    wire [7:0] tx;
    integer cycle=0,last=0,count=0,min_gap=1000,max_gap=0;
    sd_card_cmd command(.sys_clk(clk),.rst(rst),.spi_clk_div(16'd0),.cmd_req(1'b0),.cmd_req_ack(),.cmd_req_error(),
        .cmd(48'd0),.cmd_r1(8'd0),.cmd_data_len(16'd0),.cmd_data_valid(),.cmd_data_byte(),
        .block_read_req(request),.block_read_valid(valid),.block_read_data(),.block_read_req_ack(done),
        .block_write_req(1'b0),.block_write_data(8'd0),.block_write_data_rd(),.block_write_req_ack(),
        .nCS_ctrl(ncs),.clk_div(div),.spi_wr_req(spi_req),.spi_wr_ack(spi_ack),.spi_data_in(tx),.spi_data_out(8'hfe));
    spi_master spi(.sys_clk(clk),.rst(rst),.nCS(),.DCLK(),.MOSI(),.MISO(1'b1),.CPOL(1'b0),.CPHA(1'b0),
        .nCS_ctrl(ncs),.clk_div(div),.wr_req(spi_req),.wr_ack(spi_ack),.data_in(tx),.data_out());
    always @(posedge clk) if(!rst) begin
        cycle=cycle+1;
        if(valid) begin
            if(count>0) begin
                if(cycle-last<min_gap) min_gap=cycle-last;
                if(cycle-last>max_gap) max_gap=cycle-last;
            end
            last=cycle;count=count+1;
        end
        if(done) begin
            if(count!=512 || min_gap!=36 || max_gap!=36) $fatal(1,"FAIL SPI model budget count=%d gap=%d..%d",count,min_gap,max_gap);
            $display("PASS official SPI+block reader byte interval=%0d..%0d clocks payload=%0d",min_gap,max_gap,count);$finish;
        end
    end
    initial begin repeat(4) @(negedge clk);rst=0;repeat(500) @(negedge clk);request=1;end
    initial begin #500000;$fatal(1,"FAIL SPI budget timeout");end
endmodule
