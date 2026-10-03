// src_packer.v — W6: BMP 24bit 像素流 → RGB565 打包（2 像素/32bit 字）
//
// 输入: bmp_read_g 的 24bit {R,G,B} 像素流（sd_card_clk 域）
// 输出: 32bit 字，布局 word = {odd_px[15:0], even_px[15:0]}
//       RGB565 = {R[7:3], G[7:2], B[7:3]}
//
// 时序: 每收到 2 个像素输出 1 个字；奇数像素时最后一字的 odd 半字清零。
// 装载完成（load_done 脉冲）时强制排空残留像素。
module src_packer(
    input  wire        clk,
    input  wire        rst,
    input  wire        frame_restart, // 错误/重新开始时丢弃旧事务残留半字
    // 像素输入（来自 bmp_read_g）
    input  wire        px_valid,
    input  wire [23:0] px_rgb,       // {R,G,B}
    input  wire [15:0] row_width,    // 每行像素数；奇数宽时按行补齐半字
    input  wire        load_done,    // 装载完成脉冲（排空残留）
    // 打包输出（接 frame_read_write 的 write_en/write_data）
    output reg         out_valid,
    output reg  [31:0] out_data
);

    // RGB888 → RGB565
    function [15:0] rgb888_to_565;
        input [23:0] rgb;
        begin
            rgb888_to_565 = {rgb[23:19], rgb[15:10], rgb[7:3]};
        end
    endfunction

    reg        px_stored;      // 已缓存 1 个像素
    reg [15:0] px_even;        // 缓存的偶数像素
    reg [15:0] row_px_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            px_stored <= 1'b0;
            px_even   <= 16'd0;
            row_px_count <= 16'd0;
            out_valid <= 1'b0;
            out_data  <= 32'd0;
        end else if (frame_restart) begin
            px_stored <= 1'b0; px_even <= 16'd0; row_px_count <= 16'd0;
            out_valid <= 1'b0; out_data <= 32'd0;
        end else begin
            out_valid <= 1'b0;

            if (px_valid) begin
                if (!px_stored && (row_width != 16'd0) &&
                    (row_px_count == row_width - 16'd1)) begin
                    // 奇数宽行的最后一个像素立即补零，禁止跨行配对。
                    out_data  <= {16'd0, rgb888_to_565(px_rgb)};
                    out_valid <= 1'b1;
                    px_stored <= 1'b0;
                    row_px_count <= 16'd0;
                end else if (!px_stored) begin
                    // 第 1 个像素：缓存
                    px_even   <= rgb888_to_565(px_rgb);
                    px_stored <= 1'b1;
                    row_px_count <= row_px_count + 16'd1;
                end else begin
                    // 第 2 个像素：打包输出
                    out_data  <= {rgb888_to_565(px_rgb), px_even};
                    out_valid <= 1'b1;
                    px_stored <= 1'b0;
                    row_px_count <= (row_width != 16'd0) &&
                                    (row_px_count == row_width - 16'd1) ? 16'd0 : row_px_count + 16'd1;
                end
            end

            // 装载完成：排空残留奇数像素。兼容 load_done 与最后一个像素同拍，
            // 避免先缓存末像素、下一拍却再也收不到 flush 的边界死锁。
            if (load_done && !px_valid) begin
                if (px_valid && !px_stored) begin
                    out_data  <= {16'd0, rgb888_to_565(px_rgb)};
                    out_valid <= 1'b1;
                    px_stored <= 1'b0;
                    row_px_count <= 16'd0;
                end else if (!px_valid && px_stored) begin
                    out_data  <= {16'd0, px_even};
                    out_valid <= 1'b1;
                    px_stored <= 1'b0;
                    row_px_count <= 16'd0;
                end else if (!px_valid) begin
                    row_px_count <= 16'd0;
                end
            end
        end
    end

endmodule
