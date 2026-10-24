`timescale 1ns/1ps
`include "global_def.v"
// 实例来自当前IP的未加密前缀；不复制或替代其刷新计数/请求逻辑。
// ACK模型只模拟不可中断读写收尾，不能证明加密命令生成器或SDRAM物理时序。
module tb_sdram_refresh;
    parameter AUTO_REFRESH=1;
    reg clk=0, rst=1, app_req=0, ack=0;
    always #4 clk=~clk;
    wire init_done, request;
    sdr_init_ref #(.self_refresh_open(AUTO_REFRESH)) dut(
        .Sdr_clk(clk),.Rst(rst),.Sdr_init_req(1'b0),.Sdr_init_mode(4'd0),
        .Sdr_init_done(init_done),.App_ref_req(app_req),.Sdr_ref_req(request),
        .Sdr_ref_ack(ack),.Sdr_rw_vld(1'b0),.Sdr_init_ref_vld(),
        .Sdr_init_ref_ras(),.Sdr_init_ref_cas(),.Sdr_init_ref_we(),
        .Sdr_init_ref_ba(),.Sdr_init_ref_addr()
    );
    integer cycle=0, last_request=0, requests=0, acks=0;
    integer pending=0, delay_left=0, first_request=0;
    integer period_ns, slot_cycles;
    always @(negedge clk) begin
        cycle=cycle+1;
        ack=0;
        if(!rst && init_done) begin
            if(request) begin
                if(!AUTO_REFRESH) $fatal(1,"automatic refresh while disabled");
                if(pending) $fatal(1,"duplicate outstanding refresh request");
                // 独立常数参考：周期必须<=floor(64ms/2048/8ns)，而不是仅断言宏非零。
                if(last_request!=0 && cycle-last_request!=3906)
                    $fatal(1,"refresh spacing got=%0d expected=3906",cycle-last_request);
                if(requests==0) first_request=cycle;
                last_request=cycle; requests=requests+1;
                pending=1;
                // 覆盖短读、256字源写、640字输出行及其收尾。
                case(requests%4)
                    0: delay_left=1;
                    1: delay_left=140;
                    2: delay_left=268;
                    3: delay_left=660;
                endcase
            end else if(pending) begin
                if(delay_left==0) begin ack=1;pending=0;acks=acks+1;end
                else delay_left=delay_left-1;
            end
            if(AUTO_REFRESH && cycle-last_request>4000 &&
               (last_request!=0 || cycle>140000))
                $fatal(1,"periodic refresh missing period_ns=%0d slot_cycles=%0d requests=%0d",period_ns,slot_cycles,requests);
        end
    end
    initial begin
        period_ns=`SDR_CLK_PERIOD;
        slot_cycles=`SELF_REFRESH_INTERVAL;
        $display("SDRAM timing constants period_ns=%0d slot_cycles=%0d",period_ns,slot_cycles);
        repeat(8) @(posedge clk);
        @(negedge clk);rst=0;
        wait(init_done);
        if(AUTO_REFRESH) begin
            // 大于64ms，验证2048个不同刷新请求确实被产生和应答。
            repeat(8050000) @(posedge clk);
            @(posedge clk);
            if(period_ns!=8 || slot_cycles!=3905 || requests<2048 || acks<2048)
                $fatal(1,"retention-window coverage constants/requests invalid %0d %0d %0d %0d",period_ns,slot_cycles,requests,acks);
            // 再复位，确保既不保留在途请求，也不在重新初始化前发请求。
            @(negedge clk);rst=1;
            repeat(8) @(posedge clk);
            @(negedge clk);rst=0;
            repeat(50) @(negedge clk);
            if(init_done || request) $fatal(1,"refresh escaped reset/reinitialization");
            $display("TB_SDRAM_REFRESH PASS period=8ns terminal=3905 request_spacing=3906 requests=%0d acks=%0d",requests,acks);
        end else begin
            repeat(10000) @(posedge clk);
            @(negedge clk);app_req=1;
            #1;if(!request) $fatal(1,"explicit refresh request lost when automatic disabled");
            app_req=0;
            #1;if(request) $fatal(1,"explicit refresh did not deassert");
            $display("TB_SDRAM_REFRESH PASS automatic_disabled explicit_request_passthrough");
        end
        $finish;
    end
    initial begin #70000000; $fatal(1,"refresh timeout");end
endmodule
