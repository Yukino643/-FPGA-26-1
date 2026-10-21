`timescale 1ns/1ps
module tb_resize_frame_720;
    parameter W=640, H=480, FLOW=0;
    reg clk=0, rst=1, start=0, cancel=0;
    reg [10:0] cfg_w=W, cfg_h=H;
    reg [20:0] dst_base=21'h80000;
    reg read_hold=0;
    always #4 clk=~clk;
    wire cv, cr, rv, rl, write_request, wr, busy, done, error;
    wire [20:0] ca, wa;
    wire [7:0] cl;
    wire [31:0] rd, wd;
    reg [31:0] source_mem[0:460799];
    reg [20:0] read_addr;
    integer left_rsp=0, cycle=0, writes=0, i,j, rowwords, fitw,fith,left,top;
    integer xx,yy,sx,sy,expected_addr,word_index,in_burst=0,bursts=0;
    reg [15:0] p0,p1;
    reg [31:0] expected_word;
    assign cr=!read_hold && (left_rsp==0) && (cycle%7!=0);
    assign rv=(left_rsp!=0) && (cycle%3!=0);
    assign rl=rv && (left_rsp==1);
    assign rd=source_mem[read_addr-21'h100000];
    resize_frame_720 dut(.clk(clk),.rst(rst),.cancel(cancel),.start_toggle(start),
        .cfg_w(cfg_w),.cfg_h(cfg_h),.cfg_src_base(21'h100000),.cfg_dst_base(dst_base),
        .cmd_valid(cv),.cmd_addr(ca),.cmd_len(cl),.cmd_ready(cr),.rsp_valid(rv),.rsp_last(rl),.rsp_data(rd),
        .write_request(write_request),.write_ready(left_rsp==0 && cycle%5!=0),
        .wr_en(wr),.wr_addr(wa),.wr_data(wd),.busy(busy),.done_toggle(done),.error(error));
    function [15:0] pattern;
        input integer x,y;
        begin pattern={x[4:0]^5'h15,y[5:0]^6'h2a,x[4:0]^y[4:0]^5'h0f}; end
    endfunction
    function [15:0] expected_pixel;
        input integer x,y;
        begin
            if(x<left || x>=left+fitw || y<top || y>=top+fith) expected_pixel=0;
            else expected_pixel=pattern(((x-left)*W)/fitw,((y-top)*H)/fith);
        end
    endfunction
    always @(posedge clk) begin
        if(!rst) begin
            cycle=cycle+1;
            if(cv && cr) begin
                if(ca<21'h100000 || ca+cl>21'h100000+rowwords*H || cl==0 || cl>128)
                    $fatal(1,"source command bounds");
                read_addr<=ca; left_rsp<=cl;
            end else if(rv) begin read_addr<=read_addr+1'b1; left_rsp<=left_rsp-1; end
            if(wr) begin
                if(!write_request || left_rsp!=0) $fatal(1,"read/write exclusion");
                xx=(writes%640)*2; yy=writes/640;
                expected_word={expected_pixel(xx+1,yy),expected_pixel(xx,yy)};
                if(wa!==dst_base+writes || wd!==expected_word)
                    $fatal(1,"resize %0dx%0d word=%0d xy=%0d,%0d addr=%h got=%h expected=%h",W,H,writes,xx,yy,wa,wd,expected_word);
                writes=writes+1; in_burst=in_burst+1;
            end else if(in_burst!=0) begin
                if(in_burst!=640) $fatal(1,"non-contiguous row %0d",in_burst);
                bursts=bursts+1; in_burst=0;
            end
        end
    end
    task restart;
        begin
            @(negedge clk); start=~start;
            repeat(6) @(negedge clk);
        end
    endtask
    task abort_transaction;
        begin
            cancel=1; read_hold=0;
            wait(!busy); repeat(5) @(negedge clk);
            if(done || left_rsp!=0 || in_burst!=0 || writes%640!=0)
                $fatal(1,"cancel published or left a partial transaction");
            cancel=0; writes=0; bursts=0;
        end
    endtask
    task invalid_config;
        input integer w,h;
        begin
            cfg_w=w; cfg_h=h; restart;
            repeat(10) @(negedge clk);
            if(!error || busy || done || writes!=0 || cv || write_request)
                $fatal(1,"invalid config touched memory %0dx%0d",w,h);
        end
    endtask
    initial begin
        rowwords=(W+1)/2;
        if(W*720>=H*1280) begin fitw=1280; fith=(H*1280)/W; end
        else begin fitw=(W*720)/H; fith=720; end
        if(fitw==0) fitw=1;
        if(fith==0) fith=1;
        left=(1280-fitw)/2; top=(720-fith)/2;
        for(j=0;j<H;j=j+1)
            for(i=0;i<W;i=i+2) source_mem[(H-1-j)*rowwords+i/2]={i+1<W ? pattern(i+1,j):16'hdead,pattern(i,j)};
        repeat(5) @(negedge clk); rst=0;
        if(FLOW) begin
            invalid_config(0,H); invalid_config(1281,H);
            invalid_config(W,0); invalid_config(W,721);
            cfg_w=W; cfg_h=H; dst_base=0;
            read_hold=1; restart; wait(cv); @(negedge clk); abort_transaction;
            restart; wait(dut.state==6); @(negedge clk); abort_transaction;
            restart; wait(wr); repeat(37) @(negedge clk); abort_transaction;
        end
        restart;
        wait(done);
        repeat(5) @(negedge clk);
        if(error || writes!=460800 || bursts!=720 || busy) $fatal(1,"resize completion coverage");
        if(FLOW) begin
            // 连续成功帧必须使完成事件翻回0，并可更换目标页；不得复用上一帧cache状态。
            writes=0;bursts=0;dst_base=21'h80000;restart;
            wait(!done);repeat(5) @(negedge clk);
            if(error || writes!=460800 || bursts!=720 || busy) $fatal(1,"second page reverse toggle coverage");
        end
        $display("TB_RESIZE_FRAME_720 PASS %0dx%0d fit=%0dx%0d pixels=921600 flow=%0d",W,H,fitw,fith,FLOW); $finish;
    end
    initial begin #60000000; $fatal(1,"resize timeout"); end
endmodule
