sd_arbiter #(.TIMEOUT_CYCLES(10_000_000)) u_sd_arbiter(
    .clk(sd_card_clk), .rst(rst_sd),
    .a_req(bmp_sd_sec_read), .a_addr(bmp_sd_sec_read_addr), .a_ack(),
    .a_data(bmp_sd_sec_read_data), .a_data_valid(bmp_sd_sec_read_data_valid),
    .a_done(bmp_sd_sec_read_end), .a_timeout(bmp_sd_timeout),
    .b_req(wav_sd_sec_read), .b_addr(wav_sd_sec_read_addr), .b_ack(),
    .b_data(wav_sd_sec_read_data), .b_data_valid(wav_sd_sec_read_data_valid),
    .b_done(wav_sd_sec_read_end), .b_timeout(wav_sd_timeout),
    .sd_sec_read(sd_phy_sec_read), .sd_sec_read_addr(sd_phy_sec_read_addr),
    .sd_sec_read_data(sd_phy_sec_read_data),
    .sd_sec_read_data_valid(sd_phy_sec_read_data_valid),
    .sd_sec_read_end(sd_phy_sec_read_end),
    .controller_reset_req(sd_controller_reset), .owner(sd_owner)
);