`timescale 1ns/1ps
// 独立环境注入验证：握手前旧完成丢弃、三种完成顺序、错误优先和重复脉冲隔离。
module tb_source_scaler_gate;
    reg clk=0, rst=1, initialized=1, restart=0;
    reg source_done=0, req=0, ack=0, writer_done=0;
    wire start_toggle, start_pulse, active, source_seen, writer_seen;
    integer starts=0, i, before_count, cycles;
    reg previous_toggle=0;
    always #5 clk=~clk;

    source_scaler_gate dut(
        .clk(clk), .rst(rst), .sd_init_done(initialized),
        .source_restart(restart), .source_done(source_done),
        .write_req(req), .write_req_ack(ack),
        .frame_write_finish_pulse(writer_done),
        .scaler_start_toggle(start_toggle), .scaler_start_pulse(start_pulse),
        .transaction_active(active), .source_seen(source_seen), .writer_seen(writer_seen)
    );

    always @(posedge clk) begin
        #1;
        if (!rst) begin
            if (start_pulse) begin
                starts=starts+1;
                if (start_toggle===previous_toggle)
                    $fatal(1,"FAIL successful pulse without toggle");
            end else if (start_toggle!==previous_toggle)
                $fatal(1,"FAIL toggle changed without successful pulse");
            previous_toggle=start_toggle;
        end else previous_toggle=start_toggle;
    end

    task tick;
        begin @(negedge clk); end
    endtask
    task new_transaction;
        begin
            tick;restart=1;source_done=0;writer_done=0;req=0;ack=0;
            tick;restart=0;
            repeat(4) tick;
        end
    endtask
    task handshake;
        input integer delay_cycles;
        begin
            tick;req=1;
            repeat(delay_cycles) tick;
            // ACK 来自另一个时钟域，偏移于 SD 时钟沿；BMP可在原始ACK到达后立即撤请求。
            #2;ack=1;
            tick;req=0;
            cycles=0;
            while(!active) begin tick;cycles=cycles+1;
                if(cycles>12)$fatal(1,"FAIL synchronized ACK lost after request release");
            end
            tick;ack=0;
        end
    endtask
    task completions;
        input integer order;
        begin
            before_count=starts;
            if(order==0)begin
                tick;source_done=1;tick;source_done=0;
                repeat(3)tick;
                if(starts!=before_count || !source_seen)$fatal(1,"FAIL source prematurely started");
                writer_done=1;tick;writer_done=0;
            end else if(order==1)begin
                tick;writer_done=1;tick;writer_done=0;
                repeat(3)tick;
                if(starts!=before_count || !writer_seen)$fatal(1,"FAIL writer prematurely started");
                source_done=1;tick;source_done=0;
            end else begin
                tick;source_done=1;writer_done=1;
                tick;source_done=0;writer_done=0;
            end
            repeat(2)tick;
            if(starts!=before_count+1 || active || source_seen || writer_seen)
                $fatal(1,"FAIL completion order=%0d count=%0d expected=%0d",order,starts,before_count+1);
            // 任意重复/持续完成信号不允许重新启动同一事务。
            source_done=1;writer_done=1;
            repeat(5)tick;
            source_done=0;writer_done=0;
            if(starts!=before_count+1)$fatal(1,"FAIL repeated completions restart scaler");
        end
    endtask

    initial begin
        repeat(3)tick;rst=0;
        for(i=0;i<3;i=i+1)begin
            new_transaction;
            // 头部迟到的旧完成全部丢弃，不能继承为后续事务完成。
            source_done=1;writer_done=1;tick;source_done=0;writer_done=0;
            if(source_seen || writer_seen || starts!=i)$fatal(1,"FAIL stale pre-handshake completion");
            handshake(i+1);
            if(source_seen || writer_seen)$fatal(1,"FAIL stale finish inherited at new ACK");
            completions(i);
        end

        // 旧 ACK 持续高时不能把其当作新的ACK；先回低，再接受下一次请求。
        tick;ack=1;repeat(4)tick;
        restart=1;tick;restart=0;req=0;
        repeat(5)tick;
        writer_done=1;source_done=1;tick;writer_done=0;source_done=0;
        if(active || starts!=3)$fatal(1,"FAIL stale ACK armed new transaction");
        ack=0;repeat(5)tick;
        handshake(2);completions(2);

        // 错误与完成同拍必须优先取消；toggle历史不改变。
        new_transaction;handshake(2);
        before_count=starts;
        tick;restart=1;source_done=1;writer_done=1;
        tick;restart=0;source_done=0;writer_done=0;
        repeat(4)tick;
        if(starts!=before_count || active || source_seen || writer_seen)
            $fatal(1,"FAIL error/completion priority");
        handshake(1);completions(1);

        // SD deinit取消事务，但不清成功toggle历史；重初始化后依然只启动一次。
        new_transaction;handshake(1);
        tick;source_done=1;tick;source_done=0;
        before_count=starts;previous_toggle=start_toggle;
        initialized=0;writer_done=1;
        repeat(4)tick;writer_done=0;
        if(starts!=before_count || start_toggle!==previous_toggle || active || source_seen || writer_seen)
            $fatal(1,"FAIL deinit creates fake toggle or preserves transaction");
        initialized=1;repeat(4)tick;
        handshake(1);completions(0);
        // 两完成在同步ACK接受同拍到达，也必须启动一次而不丢脉冲。
        new_transaction;
        tick;req=1;repeat(2)tick;#2;ack=1;
        tick;req=0;
        wait(dut.ack_sync && !dut.ack_sync_d);
        tick;source_done=1;writer_done=1;before_count=starts;
        tick;source_done=0;writer_done=0;ack=0;
        repeat(3)tick;
        if(starts!=before_count+1 || active)
            $fatal(1,"FAIL ACK and both completions in same cycle");
        $display("TB_SOURCE_SCALER_GATE PASS starts=%0d orders=3 stale_finish=blocked delayed_ack=accepted ack_same_cycle=accepted deinit=stable",starts);
        $finish;
    end
    initial begin #50000;$fatal(1,"FAIL source scaler gate timeout");end
endmodule
