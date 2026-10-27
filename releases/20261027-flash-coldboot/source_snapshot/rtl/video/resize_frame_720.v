// 完整源帧 -> 720p RGB565显示页。最近邻、等比居中，不在像素时钟域做除法。
// 源图按BMP底向上紧凑存储，每行ceil(width/2)字；目标固定640字/行。
// 命令接受后必须收齐响应；输出行先缓存，再以不可暂停的640字突发写入。
module resize_frame_720(
    input wire clk, rst, cancel,
    input wire start_toggle,
    input wire [10:0] cfg_w, cfg_h,
    input wire [20:0] cfg_src_base, cfg_dst_base,
    output wire cmd_valid,
    output wire [20:0] cmd_addr,
    output wire [7:0] cmd_len,
    input wire cmd_ready, rsp_valid, rsp_last,
    input wire [31:0] rsp_data,
    output wire write_request,
    input wire write_ready,
    output wire wr_en,
    output wire [20:0] wr_addr,
    output wire [31:0] wr_data,
    output wire busy,
    output reg done_toggle,
    output reg error
);
    localparam IDLE=0, GEOMETRY=1, DIVIDE=2, RECT=3, ROW=4,
               READ_CMD=5, READ_DATA=6, BUILD=7, FLUSH=8,
               WRITE_WAIT=9, WRITE_PRIME=10, WRITE=11, ROW_END=12, SOURCE_OFFSET=13, READ_PREP=14;
    reg [3:0] state;
    reg [2:0] start_sync;
    reg cancelled;
    reg [10:0] width, height, row_words, fit_w, fit_h, left, top, right, bottom;
    reg [10:0] y_step_threshold;
    reg [20:0] source_row_addr, dest_row_addr;
    reg [20:0] area_w, area_h;
    reg [20:0] source_last_offset;
    reg [9:0] source_last_row;
    reg wide_fit;
    reg [20:0] div_work, div_quotient;
    // 每轮余数严格小于divisor<=1280，只需11bit；试除时再扩一位。
    reg [10:0] div_rem;
    reg [10:0] divisor;
    reg [4:0] div_count;
    wire [11:0] div_trial={div_rem,div_work[20]};
    wire div_ge=div_trial >= {1'b0,divisor};
    wire [20:0] div_next_q={div_quotient[19:0],div_ge};
    reg [9:0] out_y, source_y;
    reg [10:0] y_phase;
    reg cache_valid;
    reg [9:0] cache_y;
    reg [9:0] fetch_index;
    reg [7:0] burst_left;
    reg [20:0] read_burst_addr;
    reg [7:0] read_burst_len;
    reg read_burst_final;
    wire [10:0] fetch_remaining=row_words-{1'b0,fetch_index};
    reg [10:0] out_x, source_x, x_phase;
    reg [10:0] x_step_threshold;
    reg pixel_valid, pixel_inside, pixel_odd;
    reg [10:0] pixel_x;
    reg [15:0] even_pixel;
    reg output_valid;
    reg [9:0] output_addr;
    reg [31:0] output_pack;
    reg [9:0] write_index;
    wire inside_row=out_y>=top && out_y<bottom;
    wire inside_pixel=inside_row && out_x>=left && out_x<right;
    wire [11:0] next_x_phase={1'b0,x_phase}+{1'b0,width};
    wire [11:0] next_y_phase={1'b0,y_phase}+{1'b0,height};
    wire [31:0] source_data, output_data;
    wire [15:0] selected_pixel=!pixel_inside ? 16'd0 :
                              pixel_odd ? source_data[31:16] : source_data[15:0];
    wire source_we=(state==READ_DATA) && rsp_valid;
    wire source_re=(state==BUILD);
    wire output_we=output_valid;
    wire output_re=(state==WRITE_PRIME) || (state==WRITE);
    wire [9:0] output_read_addr=(state==WRITE) ? write_index+10'd1 : 10'd0;
    assign cmd_valid=(state==READ_CMD);
    assign cmd_addr=read_burst_addr;
    assign cmd_len=read_burst_len;
    assign write_request=(state==WRITE_WAIT)||(state==WRITE_PRIME)||(state==WRITE);
    assign wr_en=(state==WRITE);
    assign wr_addr=dest_row_addr+{11'd0,write_index};
    assign wr_data=output_data;
    assign busy=(state!=IDLE);

`ifdef SIMULATION
    reg [31:0] source_ram[0:1023], output_ram[0:1023];
    reg [31:0] source_q, output_q;
    assign source_data=source_q;
    assign output_data=output_q;
    always @(posedge clk) begin
        if(source_we) source_ram[fetch_index]<=rsp_data;
        if(source_re) source_q<=source_ram[source_x[10:1]];
        if(output_we) output_ram[output_addr]<=output_pack;
        if(output_re) output_q<=output_ram[output_read_addr];
    end
`else
    // 32K资源与现有BRAM9K字库/FIFO分开，避免占用紧张的9K块。
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.RESETMODE("ASYNC"),.IMPLEMENT("32K")) u_source_line(
        .dia(rsp_data),.addra(fetch_index),.cea(source_we),.ocea(1'b0),.clka(clk),.wea(source_we),.rsta(1'b0),.bea(1'b0),
        .dib(32'd0),.addrb(source_x[10:1]),.ceb(source_re),.oceb(1'b1),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.doa(),.dob(source_data));
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.RESETMODE("ASYNC"),.IMPLEMENT("32K")) u_output_line(
        .dia(output_pack),.addra(output_addr),.cea(output_we),.ocea(1'b0),.clka(clk),.wea(output_we),.rsta(1'b0),.bea(1'b0),
        .dib(32'd0),.addrb(output_read_addr),.ceb(output_re),.oceb(1'b1),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),.doa(),.dob(output_data));
`endif

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            start_sync<=0; state<=IDLE; done_toggle<=0; error<=0; cancelled<=0;
            width<=1; height<=1; row_words<=1; fit_w<=1; fit_h<=1; y_step_threshold<=0;
            left<=0; top<=0; right<=0; bottom<=0;
            source_row_addr<=0; dest_row_addr<=0; area_w<=0; area_h<=0;
            source_last_offset<=0; source_last_row<=0;
            wide_fit<=0; div_work<=0; div_quotient<=0; div_rem<=0; divisor<=1; div_count<=0;
            out_y<=0; source_y<=0; y_phase<=0; cache_valid<=0; cache_y<=0;
            fetch_index<=0; burst_left<=0; read_burst_addr<=0; read_burst_len<=0; read_burst_final<=0;
            out_x<=0; source_x<=0; x_phase<=0; x_step_threshold<=0;
            pixel_valid<=0; pixel_inside<=0; pixel_odd<=0; pixel_x<=0;
            even_pixel<=0; write_index<=0;
            output_valid<=0; output_addr<=0; output_pack<=0;
        end else begin
            start_sync<={start_sync[1:0],start_toggle};
            if(cancel && busy) cancelled<=1;
            pixel_valid<=(state==BUILD);
            if(pixel_valid && !pixel_x[0]) even_pixel<=selected_pixel;
            // 32K RAM到32K RAM的路径需要独立寄存，不能把读出/选半字/写入塞进8ns。
            // 最后一个打包字在WRITE_WAIT写入，先于WRITE_PRIME开始读取整行。
            output_valid<=pixel_valid && pixel_x[0];
            if(pixel_valid && pixel_x[0]) begin
                output_addr<=pixel_x[10:1]; output_pack<={selected_pixel,even_pixel};
            end
            case(state)
                IDLE: begin
                    pixel_valid<=0;
                    if((start_sync[2]^start_sync[1]) && !cancel) begin
                        error<=0; cancelled<=0; cache_valid<=0;
                        if(cfg_w==0 || cfg_w>1280 || cfg_h==0 || cfg_h>720) error<=1;
                        else begin
                            width<=cfg_w; height<=cfg_h; row_words<=(cfg_w+1'b1)>>1;
                            source_last_row<=cfg_h[9:0]-10'd1;
                            source_row_addr<=cfg_src_base;
                            dest_row_addr<=cfg_dst_base;
                            area_w<=cfg_w*21'd720; area_h<=cfg_h*21'd1280;
                            state<=GEOMETRY;
                        end
                    end
                end
                GEOMETRY: begin
                    // 减1已在锁存配置时完成，本拍只保留乘法，下一拍再加源基址。
                    source_last_offset<=source_last_row*row_words;
                    state<=SOURCE_OFFSET;
                end
                SOURCE_OFFSET: begin
                    source_row_addr<=source_row_addr+source_last_offset;
                    wide_fit<=area_w>=area_h;
                    div_work<=area_w>=area_h ? area_h : area_w;
                    divisor<=area_w>=area_h ? width : height;
                    div_rem<=0; div_quotient<=0; div_count<=0;
                    state<=DIVIDE;
                end
                DIVIDE: begin
                    div_work<={div_work[19:0],1'b0};
                    div_rem<=div_ge ? div_trial-{1'b0,divisor} : div_trial;
                    div_quotient<=div_next_q;
                    if(div_count==20) begin
                        fit_w<=wide_fit ? 11'd1280 : (div_next_q==0 ? 11'd1 : div_next_q[10:0]);
                        fit_h<=wide_fit ? (div_next_q==0 ? 11'd1 : div_next_q[10:0]) : 11'd720;
                        state<=RECT;
                    end else div_count<=div_count+1'b1;
                end
                RECT: begin
                    // 输入不超过1280x720，等比适配只放大/等大，fit_w>=width。
                    // phase+width>=fit_w 等价 phase>=fit_w-width；阈值预存，
                    // 移除每像素加法后再比较的8ns关键路径，不降低吞吐。
                    x_step_threshold<=fit_w-width;
                    // 同理fit_h>=height：预减阈值，隔离逐行加法和地址使能比较。
                    y_step_threshold<=fit_h-height;
                    left<=(1280-fit_w)>>1; top<=(720-fit_h)>>1;
                    right<=((1280-fit_w)>>1)+fit_w; bottom<=((720-fit_h)>>1)+fit_h;
                    out_y<=0; source_y<=0; y_phase<=0;
                    state<=ROW;
                end
                ROW: begin
                    if(cancelled || cancel) state<=IDLE;
                    else if(inside_row && (!cache_valid || cache_y!=source_y)) begin
                        fetch_index<=0; state<=READ_PREP;
                    end else begin
                        out_x<=0; source_x<=0; x_phase<=0; state<=BUILD;
                    end
                end
                // 命令地址/长度先寄存，隔离剩余字数减法与mem_mpu的仲裁/命令寄存路径。
                READ_PREP: begin
                    read_burst_addr<=source_row_addr+{11'd0,fetch_index};
                    read_burst_len<=fetch_remaining>128 ? 8'd128 : fetch_remaining[7:0];
                    // 在命令发出前锁存末突发，响应末拍只用单比特发布行缓存。
                    // 避免fetch_index加一/比较再串入cache_y写使能。
                    read_burst_final<=fetch_remaining<=11'd128;
                    state<=READ_CMD;
                end
                READ_CMD: if(cmd_ready) begin burst_left<=cmd_len; state<=READ_DATA; end
                READ_DATA: if(rsp_valid) begin
                    fetch_index<=fetch_index+1'b1;
                    burst_left<=burst_left-1'b1;
                    if(burst_left==1) begin
                        if(read_burst_final) begin
                            cache_valid<=1; cache_y<=source_y; state<=ROW;
                        end else state<=READ_PREP;
                    end
                end
                BUILD: begin
                    pixel_inside<=inside_pixel; pixel_odd<=source_x[0]; pixel_x<=out_x;
                    if(inside_pixel) begin
                        if(x_phase>=x_step_threshold) begin
                            x_phase<=x_phase-x_step_threshold; source_x<=source_x+1'b1;
                        end else x_phase<=next_x_phase[10:0];
                    end
                    if(out_x==1279) state<=FLUSH;
                    else out_x<=out_x+1'b1;
                end
                FLUSH: state<=WRITE_WAIT;
                WRITE_WAIT: if(write_ready) begin write_index<=0; state<=WRITE_PRIME; end
                WRITE_PRIME: state<=WRITE;
                WRITE: begin
                    if(write_index==639) state<=ROW_END;
                    else write_index<=write_index+1'b1;
                end
                ROW_END: begin
                    if(out_y==719) begin
                        if(!cancelled && !cancel) done_toggle<=~done_toggle;
                        state<=IDLE;
                    end else begin
                        dest_row_addr<=dest_row_addr+21'd640;
                        out_y<=out_y+1'b1;
                        if(inside_row) begin
                            if(y_phase>=y_step_threshold) begin
                                y_phase<=y_phase-y_step_threshold; source_y<=source_y+1'b1;
                                source_row_addr<=source_row_addr-row_words;
                            end else y_phase<=next_y_phase[10:0];
                        end
                        state<=ROW;
                    end
                end
                default: begin error<=1; state<=IDLE; end
            endcase
        end
    end
`ifdef SIMULATION
    always @(posedge clk) if(!rst) begin
        if(rsp_valid && state!=READ_DATA) $fatal(1,"resize response without command");
        if(rsp_valid && (rsp_last !== (burst_left==1))) $fatal(1,"resize response length mismatch");
        if(wr_en && source_we) $fatal(1,"resize source/output memory overlap");
        if((start_sync[2]^start_sync[1]) && busy) $fatal(1,"resize overlapping transactions");
    end
`endif
endmodule
