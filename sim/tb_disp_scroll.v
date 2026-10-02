`timescale 1ns/1ps
// 保留真实行宽；检查非整突发偏移、行内回绕、帧间偏移改变及仲裁停顿。
module tb_disp_scroll;
    localparam WORDS=640*3;
    reg clk=0, rst=1, frame_toggle=0;
    reg [9:0] scroll=0;
    reg [20:0] page=21'h1000;
    wire cv, fw;
    wire [20:0] ca;
    wire [7:0] cl;
    wire [31:0] fd;
    reg cr=0, rv=0, rl=0;
    reg [31:0] rd=0;
    reg [9:0] used=0;
    integer words=0, expected_scroll=0, expected_page=0, k, cycles=0;
    integer left=0, model_addr=0, delay_count=0, expected_addr;
    always #4 clk=~clk;
    disp_read_engine #(.FRAME_WORDS(WORDS), .ENABLE_SCROLL(1)) dut(
        .clk(clk),.rst(rst),.vs_toggle(frame_toggle),.page_base(page),.scroll_x(scroll),
        .fifo_we(fw),.fifo_wdata(fd),.fifo_wusedw(used),
        .cmd_valid(cv),.cmd_addr(ca),.cmd_len(cl),.cmd_ready(cr),
        .rsp_valid(rv),.rsp_data(rd),.rsp_last(rl));
    always @(negedge clk) begin
        cycles=cycles+1;
        // 在命令接收前插入停顿；应保持地址、长度及 valid。
        cr=cv && left==0 && cycles%7==0;
        rv=0; rl=0;
        used=(cycles%29==0 && left==0) ? 10'd300 : 10'd0;
        if(left>0 && delay_count==0 && cycles%5!=0) begin
            rv=1; rd=model_addr; rl=(left==1);
            model_addr=model_addr+1; left=left-1;
        end
        if(delay_count>0) delay_count=delay_count-1;
    end
    always @(posedge clk) if(!rst) begin
        if(cv && cr) begin
            if(cl==0 || cl>128) $fatal(1,"FAIL invalid scroll burst=%0d",cl);
            if((ca-expected_page)%640+cl>640)
                $fatal(1,"FAIL burst crosses source row");
            model_addr=ca; left=cl; delay_count=3;
        end
        if(fw) begin
            expected_addr=expected_page+(words/640)*640+(words%640+expected_scroll)%640;
            if(fd!==expected_addr) $fatal(1,"FAIL scroll=%0d word=%0d addr=%0d expected=%0d",expected_scroll,words,fd,expected_addr);
            words=words+1;
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst=0;
        for(k=0;k<7;k=k+1) begin
            case(k)
                0: expected_scroll=0;
                1: expected_scroll=1;
                2: expected_scroll=16;
                3: expected_scroll=127;
                4: expected_scroll=128;
                5: expected_scroll=639;
                6: expected_scroll=0;
            endcase
            @(negedge clk); scroll=expected_scroll; page=21'h1000+k*21'h80000;
            expected_page=page; words=0;
            frame_toggle=~frame_toggle;
            wait(words==WORDS); wait(!dut.frame_act);
            repeat(10) @(negedge clk);
            if(words!=WORDS) $fatal(1,"FAIL extra frame words");
        end
        $display("TB_DISP_SCROLL PASS cases=7 exact_words=%0d",7*WORDS); $finish;
    end
    initial begin #2000000; $fatal(1,"FAIL scroll timeout"); end
endmodule
