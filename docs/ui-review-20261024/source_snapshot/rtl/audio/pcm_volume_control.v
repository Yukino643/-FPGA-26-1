// HDMI-B节目音量。输入来自audio_player：有符号16位PCM左对齐到24位。
// 100%逐位保持；增益上限256，因此16x10位积必落在有符号24位范围。
// 警笛与正常音频共用两级流水/valid相位，警笛绕过节目静音与衰减。
module pcm_volume_control(
    input wire clk, rst,
    input wire [4:0] audio_config, // {mute, volume_level[3:0]}, level 0..10
    input wire in_valid, in_data_valid,
    input wire [23:0] in_left, in_right,
    input wire emergency_mode, siren_valid,
    input wire [23:0] siren_left, siren_right,
    output reg out_valid, out_data_valid,
    output reg [23:0] out_left, out_right
);
    reg [8:0] gain_current;
    reg [1:0] ramp_div;
    reg [8:0] gain_target;
    always @* begin
        case(audio_config[3:0])
            0:gain_target=0; 1:gain_target=26; 2:gain_target=51;
            3:gain_target=77; 4:gain_target=102; 5:gain_target=128;
            6:gain_target=154; 7:gain_target=179; 8:gain_target=205;
            9:gain_target=230; 10:gain_target=256;
            default:gain_target=0; // 非法档位静音，不溢出或放大。
        endcase
        if(audio_config[4]) gain_target=0;
    end
    reg signed [25:0] product_left, product_right;
    reg [23:0] siren_left_d, siren_right_d;
    reg bypass_d, valid_d, data_valid_d;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            gain_current<=9'd256; ramp_div<=0;
            product_left<=0; product_right<=0;
            siren_left_d<=0; siren_right_d<=0;
            bypass_d<=0; valid_d<=0; data_valid_d<=0;
            out_valid<=0; out_data_valid<=0; out_left<=0; out_right<=0;
        end else begin
            if(in_valid) begin
                if(gain_current==gain_target) ramp_div<=0;
                else begin
                    ramp_div<=ramp_div+1'b1;
                    if(ramp_div==3) begin
                        if(gain_current<gain_target) gain_current<=gain_current+1'b1;
                        else gain_current<=gain_current-1'b1;
                    end
                end
                product_left <= $signed(in_left[23:8]) * $signed({1'b0,gain_current});
                product_right <= $signed(in_right[23:8]) * $signed({1'b0,gain_current});
            end
            bypass_d<=emergency_mode;
            valid_d<=emergency_mode ? siren_valid : in_valid;
            data_valid_d<=emergency_mode ? siren_valid : (in_valid && in_data_valid);
            siren_left_d<=siren_left; siren_right_d<=siren_right;
            out_valid<=valid_d; out_data_valid<=data_valid_d;
            if(valid_d) begin
                out_left<=bypass_d ? siren_left_d : product_left[23:0];
                out_right<=bypass_d ? siren_right_d : product_right[23:0];
            end
        end
    end
endmodule
