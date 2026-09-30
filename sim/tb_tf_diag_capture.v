// 异步采样与接收时钟暂停：确认故障证据不因软复位丢失，快照原子且握手有界。
`timescale 1ns/1ps
module tb_tf_diag_capture;
    reg sclk=0, vclk=0, srst=1, vrst=1, video_run=1;
    always #5 sclk=~sclk;
    always #17 if (video_run) vclk=~vclk;
    reg init_done=0, req=0, dv=0, sec_end=0, ctrl_reset=0, a_timeout=0, b_timeout=0;
    reg pixel=0, wrreq=0, wrfinish=0, commit=0;
    reg [31:0] status=0, addr=0;
    reg [7:0] data=0;
    wire [191:0] snap;
    tf_diag_capture #(.SNAPSHOT_CYCLES(10)) dut (
        .sd_clk(sclk),.sd_rst(srst),.video_clk(vclk),.video_rst(vrst),
        .sd_init_done(init_done),.bmp_status(status),.sd_req(req),.sd_addr(addr),
        .sd_data(data),.sd_data_valid(dv),.sd_end(sec_end),
        .controller_reset(ctrl_reset),.bmp_timeout(a_timeout),.wav_timeout(b_timeout),
        .pixel_valid(pixel),.write_req(wrreq),.frame_write_finish_pulse(wrfinish),
        .scaler_commit_toggle(commit),.video_snapshot(snap)
    );
    integer i;
    reg [191:0] frozen_mailbox;
    reg frozen_request;
    reg [191:0] observed_mailbox;
    reg [2:0] old_request_sync;
    reg old_ack;
    always @(negedge vclk) begin
        observed_mailbox = dut.mailbox;
        old_request_sync = dut.request_sync;
        old_ack = dut.ack_toggle;
    end
    always @(posedge vclk) begin
        #1;
        if (!vrst && old_request_sync[2] != old_ack && snap !== observed_mailbox)
            $fatal(1,"FAIL incoherent asynchronous mailbox snapshot");
    end
    task send_byte;
        input [7:0] value;
        begin
            @(negedge sclk); data=value;dv=1;
            @(negedge sclk);dv=0;
            repeat(3) @(negedge sclk);
        end
    endtask
    initial begin
        repeat(5) @(negedge sclk);srst=0;vrst=0;
        init_done=1;
        status=32'h00010387; // state1, found3, error0, anygood+done+busy+sourcedone
        addr=32784;req=1;
        @(negedge sclk);req=0;
        send_byte(8'h42);send_byte(8'h4d);send_byte(8'h36);send_byte(8'h10);
        @(negedge sclk);sec_end=1;wrreq=1;
        @(negedge sclk);sec_end=0;wrreq=0;
        for(i=0;i<6;i=i+1) begin
            @(negedge sclk);pixel=1;
            @(negedge sclk);pixel=0;
        end
        @(negedge sclk);wrfinish=1;commit=1;
        @(negedge sclk);wrfinish=0;ctrl_reset=1;a_timeout=1;b_timeout=1;
        @(negedge sclk);ctrl_reset=0;a_timeout=0;b_timeout=0;init_done=0;
        repeat(80) @(negedge sclk);
        // 模拟真实 SD 控制器软复位，只降 init；诊断数据仍需完整保留。
        if(snap[79:48] !== 32'h424d3610 || snap[47:16] !== 6 ||
           snap[127:96] !== 1 || snap[95:80] !== 1 || snap[15:0] !== 16'h0101 ||
           snap[0+176] !== 0 || snap[186:184] !== 3'b111 || snap[171:160] !== 12'h130)
            $fatal(1,"FAIL diagnostic fields or sticky fault history snap=%h",snap);
        // 接收时钟停顿后，生产者不得覆盖尚未接收的数据。
        @(negedge vclk);video_run=0;
        wait(dut.request_toggle != dut.ack_sync[2]);
        @(negedge sclk);frozen_mailbox=dut.mailbox;frozen_request=dut.request_toggle;
        repeat(60) begin
            @(negedge sclk);status=status+32'h100;addr=addr+1;
            if(dut.mailbox !== frozen_mailbox || dut.request_toggle !== frozen_request)
                $fatal(1,"FAIL source overwrote outstanding mailbox");
        end
        video_run=1;
        repeat(100) @(negedge sclk);
        if(dut.ack_sync[2] !== dut.request_toggle)
            $display("INFO another snapshot already in flight after clock resumed");
        $display("PASS TF diagnostic CDC: sparse probe, sticky faults, counters, receiver pause");
        $finish;
    end
    initial begin
        #1000000;$fatal(1,"FAIL diagnostic handshake timeout");
    end
endmodule
