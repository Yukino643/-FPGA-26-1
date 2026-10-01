// tb_wav_read.v — wav_read 单元仿真
// 验证: WAV 头解析、PCM 流式输出、扇区切换
`timescale 1ns/1ps
module tb_wav_read;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;   // 100MHz

    // DUT 信号
    wire ready;
    reg  scan_start = 0;
    reg  [31:0] scan_start_sector = 0;
    wire scan_done, scan_found_valid;
    wire [31:0] scan_found_sector;
    reg  load_start = 0;
    reg  [31:0] load_sector = 0;
    wire load_done, load_active;
    wire [31:0] load_pcm_bytes;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    reg  [7:0] sd_sec_read_data = 0;
    reg  sd_sec_read_data_valid = 0;
    reg  sd_sec_read_end = 0;
    wire pcm_valid;
    wire [15:0] pcm_left, pcm_right;
    reg  pcm_ready = 1'b1;

    wav_read u_wav(
        .clk(clk), .rst(rst), .ready(ready),
        .scan_start(scan_start), .scan_start_sector(scan_start_sector),
        .scan_done(scan_done), .scan_found_valid(scan_found_valid),
        .scan_found_sector(scan_found_sector),
        .load_start(load_start), .load_sector(load_sector),
        .load_done(load_done), .load_active(load_active),
        .load_pcm_bytes(load_pcm_bytes),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .pcm_valid(pcm_valid), .pcm_left(pcm_left), .pcm_right(pcm_right),
        .pcm_ready(pcm_ready)
    );

    // ---- 行为级 SD 卡扇区模型 ----
    // 扇区 0: WAV 文件头 + 前 468 字节 PCM
    // 扇区 1: 后续 PCM
    reg [7:0] sd_mem [0:1023];

    // WAV 头（44 字节）
    task init_wav_header;
        begin
            // "RIFF"
            sd_mem[0]="R"; sd_mem[1]="I"; sd_mem[2]="F"; sd_mem[3]="F";
            // file size (小端, 不重要)
            sd_mem[4]=8'h24; sd_mem[5]=8'h08; sd_mem[6]=8'h00; sd_mem[7]=8'h00;
            // "WAVE"
            sd_mem[8]="W"; sd_mem[9]="A"; sd_mem[10]="V"; sd_mem[11]="E";
            // "fmt "
            sd_mem[12]="f"; sd_mem[13]="m"; sd_mem[14]="t"; sd_mem[15]=" ";
            // fmt size = 16
            sd_mem[16]=8'h10; sd_mem[17]=8'h00; sd_mem[18]=8'h00; sd_mem[19]=8'h00;
            // format = 1 (PCM)
            sd_mem[20]=8'h01; sd_mem[21]=8'h00;
            // channels = 2
            sd_mem[22]=8'h02; sd_mem[23]=8'h00;
            // sample rate = 48000
            sd_mem[24]=8'h80; sd_mem[25]=8'hBB; sd_mem[26]=8'h00; sd_mem[27]=8'h00;
            // byte rate = 192000
            sd_mem[28]=8'h00; sd_mem[29]=8'hEE; sd_mem[30]=8'h02; sd_mem[31]=8'h00;
            // block align = 4
            sd_mem[32]=8'h04; sd_mem[33]=8'h00;
            // bits = 16
            sd_mem[34]=8'h10; sd_mem[35]=8'h00;
            // "data"
            sd_mem[36]="d"; sd_mem[37]="a"; sd_mem[38]="t"; sd_mem[39]="a";
            // data size = 968 (242 sample pairs, 跨 2 个扇区: 44+968=1012 < 1024)
            sd_mem[40]=8'hC8; sd_mem[41]=8'h03; sd_mem[42]=8'h00; sd_mem[43]=8'h00;
        end
    endtask

    // 不同样本检出 BRAM 预取重复/丢字；跨扇区保持同一个序列。
    task init_pcm_data;
        integer i, index;
        reg [15:0] left, right;
        begin
            for (i = 44; i < 1024; i = i + 4) begin
                index=(i-44)/4;
                left=16'h1200+index; right=16'h5600^index;
                sd_mem[i]=left[7:0]; sd_mem[i+1]=left[15:8];
                sd_mem[i+2]=right[7:0]; sd_mem[i+3]=right[15:8];
            end
        end
    endtask

    // 扇区读响应模型
    reg [31:0] rsp_addr;
    reg [8:0]  rsp_idx;
    reg        rsp_active;
    reg        rsp_seen;

    always @(posedge clk) begin
        if (rst) begin
            sd_sec_read_data_valid <= 0;
            sd_sec_read_end <= 0;
            rsp_active <= 0;
            rsp_seen <= 0;
            rsp_idx <= 0;
        end else begin
            sd_sec_read_data_valid <= 0;
            sd_sec_read_end <= 0;
            if (!sd_sec_read)
                rsp_seen <= 1'b0;
            if (sd_sec_read && !rsp_active && !rsp_seen) begin
                rsp_addr <= sd_sec_read_addr;
                rsp_idx <= 0;
                rsp_active <= 1;
                rsp_seen <= 1'b1;
            end else if (rsp_active) begin
                sd_sec_read_data_valid <= 1;
                sd_sec_read_data <= sd_mem[rsp_addr * 512 + rsp_idx];
                if (rsp_idx == 9'd511) begin
                    rsp_active <= 0;
                    sd_sec_read_end <= 1;
                end else begin
                    rsp_idx <= rsp_idx + 1;
                end
            end
        end
    end

    // PCM 输出计数
    integer pcm_count = 0;
    reg [15:0] last_l, last_r;
    integer stall_cycle=0;
    reg [15:0] expected_left, expected_right;
    always @(negedge clk) begin
        stall_cycle=stall_cycle+1;
        pcm_ready=(stall_cycle%11>=4);
    end
    always @(posedge clk) begin
        if (pcm_valid) begin
            pcm_count = pcm_count + 1;
            last_l = pcm_left;
            last_r = pcm_right;
            expected_left=16'h1200+pcm_count-1;
            expected_right=16'h5600^(pcm_count-1);
            if(pcm_left !== expected_left || pcm_right !== expected_right) begin
                $display("FAIL PCM[%0d] L=%h R=%h",pcm_count,pcm_left,pcm_right); $fatal(1);
            end
            if (pcm_count <= 3)
                $display("PCM #%0d: L=%h R=%h", pcm_count, pcm_left, pcm_right);
        end
    end

    // ---- 激励 ----
    integer errors = 0;

    initial begin
        init_wav_header;
        init_pcm_data;

        rst = 1;
        #100;
        @(posedge clk); rst = 0;
        #100;

        // Test 1: 扫描扇区 0（应找到 WAV）
        $display("TEST1: scan sector 0");
        @(posedge clk); scan_start <= 1; scan_start_sector <= 0;
        @(posedge clk); scan_start <= 0;
        wait(scan_done);
        #100;
        if (!scan_found_valid || scan_found_sector != 0) begin
            $display("FAIL: scan not found");
            errors = errors + 1;
        end else
            $display("TEST1 PASS: found WAV at sector 0");

        // Test 2: 装载并检查 PCM 输出
        $display("TEST2: load and stream PCM");
        pcm_count = 0;
        @(posedge clk); load_start <= 1; load_sector <= 0;
        @(posedge clk); load_start <= 0;
        wait(load_done);
        #200;
        $display("PCM count=%0d, bytes=%0d", pcm_count, load_pcm_bytes);
        if (pcm_count != 242) begin
            $display("FAIL: PCM count %0d expected 242",pcm_count);
            errors = errors + 1;
        end else if (last_l !== 16'h12F1 || last_r !== 16'h56F1) begin
            $display("FAIL: PCM data mismatch L=%h R=%h", last_l, last_r);
            errors = errors + 1;
        end else
            $display("TEST2 PASS: %0d samples, L=%h R=%h", pcm_count, last_l, last_r);

        if (errors == 0) $display("TB_WAV_READ PASS");
        else $display("TB_WAV_READ FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("TB_WAV_READ TIMEOUT state=%0d", u_wav.state);
        $finish;
    end

endmodule
