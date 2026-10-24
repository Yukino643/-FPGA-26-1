// monitor_menu_ctrl.v - HDMI-A monitor menu input and shadow configuration
//
// The monitor console is active immediately after reset. KEY3 short press
// moves the cursor and KEY3 long press switches the two monitor pages. KEY4
// remains reserved for the emergency long-press path and short-press actions
// in the selected card. Configuration changes are committed as a toggle and
// are applied by the HDMI-B video domain at VS.
module monitor_menu_ctrl #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_PRESS_MS = 1000,
    parameter integer TEST_MS = 200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       key_next,       // physical KEY2, active low
    input  wire       key_auto,       // physical KEY3, active low
    input  wire       key_emergency,  // physical KEY4, active low
    input  wire       emergency_active,
    input  wire       cfg_commit_ack_toggle,
    output reg        menu_active,
    output reg        menu_page,      // 0: HDMI-B controls, 1: peripheral test
    output reg [2:0]  cursor,
    output reg [3:0]  cfg_shadow,
    output wire [3:0] cfg_payload,
    output reg [1:0]  period_shadow,
    output reg [1:0]  period_active,
    output reg        screen_page,
    output reg        screen_edit,
    output reg [9:0]  screen_shadow,
    output reg [9:0]  screen_payload,
    output reg        subtitle_page,
    output reg        subtitle_edit,
    output reg [4:0]  subtitle_shadow,
    output reg [4:0]  subtitle_payload,
    output wire       cfg_commit_busy,
    output reg        cfg_commit_toggle,
    output reg        cfg_dirty,
    output reg        buzzer_test,
    output wire [2:0] key_state,
    output reg        key_next_pulse,
    output reg        key_auto_pulse,
    output reg [15:0] key_event_count
);
    localparam integer DB_CNT = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer LONG_CNT = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;
    localparam integer TEST_CNT = (CLK_FREQ_HZ / 1000) * TEST_MS;

    reg [2:0] key_next_sync, key_auto_sync, key_emg_sync;
    reg key_next_stable, key_auto_stable, key_emg_stable;
    reg [31:0] next_db, auto_db, emg_db;
    reg next_was_down, auto_was_down, emg_was_down;
    reg [31:0] next_press_len;
    reg [31:0] auto_press_len;
    reg [31:0] emg_press_len;
    reg [31:0] test_count;
    reg [3:0] cfg_committed;
    // 预览可继续编辑；邮箱正文独立保持到下一次有效提交（必须先收到 ACK）。
    assign cfg_payload = cfg_committed;

    wire next_down = !key_next_stable;
    wire auto_down = !key_auto_stable;
    wire emg_down  = !key_emg_stable;
    assign key_state = {emg_down, auto_down, next_down};
    assign cfg_commit_busy = cfg_commit_ack_toggle != cfg_commit_toggle;
    // {temperature 0..2, contrast 0..8, brightness 0..8}; neutral = {1,4,4}.
    localparam [9:0] SCREEN_DEFAULT = {2'd1, 4'd4, 4'd4};
    wire next_short = next_was_down && !next_down && (next_press_len < LONG_CNT);
    wire next_long  = next_was_down && !next_down && (next_press_len >= LONG_CNT);
    wire auto_short = auto_was_down && !auto_down && (auto_press_len < LONG_CNT);
    wire auto_long  = auto_was_down && !auto_down && (auto_press_len >= LONG_CNT);
    wire emg_short  = emg_was_down && !emg_down && (emg_press_len < LONG_CNT);
    wire emg_long   = emg_was_down && !emg_down && (emg_press_len >= LONG_CNT);

    function [2:0] cursor_up;
        input [2:0] value;
        input       peripheral_page;
        begin
            if (value == 3'd0)
                cursor_up = peripheral_page ? 3'd3 : 3'd5;
            else
                cursor_up = value - 1'b1;
        end
    endfunction
    function [2:0] cursor_down;
        input [2:0] value;
        input       peripheral_page;
        begin
            if (peripheral_page)
                cursor_down = (value >= 3'd3) ? 3'd0 : value + 1'b1;
            else
                cursor_down = (value >= 3'd5) ? 3'd0 : value + 1'b1;
        end
    endfunction

    // Synchronize and debounce all keys. A short event is emitted on release,
    // so a long press can be classified before it reaches the player control.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key_next_sync <= 3'b111;
            key_auto_sync <= 3'b111;
            key_emg_sync  <= 3'b111;
            key_next_stable <= 1'b1;
            key_auto_stable <= 1'b1;
            key_emg_stable  <= 1'b1;
            next_db <= 0; auto_db <= 0; emg_db <= 0;
            next_was_down <= 0; auto_was_down <= 0; emg_was_down <= 0;
            next_press_len <= 0; auto_press_len <= 0; emg_press_len <= 0;
        end else begin
            key_next_sync <= {key_next_sync[1:0], key_next};
            key_auto_sync <= {key_auto_sync[1:0], key_auto};
            key_emg_sync  <= {key_emg_sync[1:0], key_emergency};

            if (key_next_sync[2] == key_next_stable) next_db <= 0;
            else if (next_db >= DB_CNT-1) begin key_next_stable <= key_next_sync[2]; next_db <= 0; end
            else next_db <= next_db + 1'b1;
            if (key_auto_sync[2] == key_auto_stable) auto_db <= 0;
            else if (auto_db >= DB_CNT-1) begin key_auto_stable <= key_auto_sync[2]; auto_db <= 0; end
            else auto_db <= auto_db + 1'b1;
            if (key_emg_sync[2] == key_emg_stable) emg_db <= 0;
            else if (emg_db >= DB_CNT-1) begin key_emg_stable <= key_emg_sync[2]; emg_db <= 0; end
            else emg_db <= emg_db + 1'b1;

            next_was_down <= next_down;
            auto_was_down <= auto_down;
            emg_was_down <= emg_down;
            if (next_down && next_press_len < LONG_CNT) next_press_len <= next_press_len + 1'b1;
            else if (!next_down) next_press_len <= 0;
            if (auto_down && auto_press_len < LONG_CNT) auto_press_len <= auto_press_len + 1'b1;
            else if (!auto_down) auto_press_len <= 0;
            if (emg_down && emg_press_len < LONG_CNT) emg_press_len <= emg_press_len + 1'b1;
            else if (!emg_down) emg_press_len <= 0;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // HDMI-A 上电直接进入节目控制页；退出仅切换按键归属。
            menu_active <= 1'b1;
            menu_page <= 1'b0;
            cursor <= 3'd0;
            cfg_shadow <= 4'b0111;
            cfg_committed <= 4'b0111;
            period_shadow <= 2'd0;
            period_active <= 2'd0;
            screen_page <= 1'b0;
            screen_edit <= 1'b0;
            screen_shadow <= SCREEN_DEFAULT;
            screen_payload <= SCREEN_DEFAULT;
            subtitle_page <= 1'b0;
            subtitle_edit <= 1'b0;
            subtitle_shadow <= 5'h08;
            subtitle_payload <= 5'h08;
            cfg_commit_toggle <= 1'b0;
            cfg_dirty <= 1'b0;
            buzzer_test <= 1'b0;
            test_count <= 0;
            key_next_pulse <= 1'b0;
            key_auto_pulse <= 1'b0;
            key_event_count <= 0;
        end else begin
            key_next_pulse <= 1'b0;
            key_auto_pulse <= 1'b0;
            if (buzzer_test) begin
                if (test_count >= TEST_CNT-1) begin buzzer_test <= 1'b0; test_count <= 0; end
                else test_count <= test_count + 1'b1;
            end

            // KEY4 long-press remains owned by emergency_ctrl. It is only
            // counted here for diagnostics and never changes the menu.
            if (emg_long) key_event_count <= key_event_count + 1'b1;

            if (!menu_active) begin
                if (next_short) begin
                    key_next_pulse <= 1'b1;
                    key_event_count <= key_event_count + 1'b1;
                end
                // Normal KEY3 short press is still handled by the player.
                if (auto_short) key_event_count <= key_event_count + 1'b1;
                if (auto_long) begin
                    menu_active <= 1'b1;
                    menu_page <= 1'b0;
                    cursor <= 3'd0;
                    cfg_dirty <= 1'b0;
                    cfg_shadow <= cfg_committed;
                    period_shadow <= period_active;
                    screen_page <= 1'b0;
                    screen_edit <= 1'b0;
                    screen_shadow <= screen_payload;
                    subtitle_page <= 1'b0;
                    subtitle_edit <= 1'b0;
                    subtitle_shadow <= subtitle_payload;
                end
                // The player receives a classified short KEY3 event. This
                // prevents a long press from toggling autoplay before menu entry.
                if (auto_short) key_auto_pulse <= 1'b1;
            end else begin
                if (next_long) begin
                    // 逐级返回：编辑取消 -> 二级页返回 -> 播放按键。
                    if (subtitle_edit) subtitle_edit <= 1'b0;
                    else if (subtitle_page) begin
                        subtitle_page <= 1'b0;
                        cursor <= 3'd3;
                    end else if (screen_edit) screen_edit <= 1'b0;
                    else if (screen_page) begin
                        screen_page <= 1'b0;
                        cursor <= 3'd5;
                    end else menu_active <= 1'b0;
                    cfg_dirty <= 1'b0;
                    cfg_shadow <= cfg_committed;
                    period_shadow <= period_active;
                    screen_shadow <= screen_payload;
                    subtitle_shadow <= subtitle_payload;
                end else if (auto_long) begin
                    // Long KEY3 switches between the two monitor pages while
                    // the menu is open. This keeps KEY4 available for commit
                    // and for the emergency long-press path.
                    menu_page <= (screen_page || subtitle_page) ? 1'b0 : ~menu_page;
                    screen_page <= 1'b0;
                    screen_edit <= 1'b0;
                    cursor <= 3'd0;
                    cfg_dirty <= 1'b0;
                    // 翻页等同于放弃当前预览，避免回到节目页时把旧的
                    // shadow 值误显示成已生效配置。
                    cfg_shadow <= cfg_committed;
                    period_shadow <= period_active;
                    screen_shadow <= screen_payload;
                    subtitle_page <= 1'b0;
                    subtitle_edit <= 1'b0;
                    subtitle_shadow <= subtitle_payload;
                end else if (next_short) begin
                    if (subtitle_edit) begin
                        case (cursor)
                            0: subtitle_shadow[0] <= 1'b0;
                            1: if (subtitle_shadow[2:1] > 0) subtitle_shadow[2:1] <= subtitle_shadow[2:1] - 1'b1;
                            2: if (subtitle_shadow[4:3] > 0) subtitle_shadow[4:3] <= subtitle_shadow[4:3] - 1'b1;
                            3: cfg_shadow[3] <= 1'b0;
                        endcase
                    end else if (screen_edit) begin
                        case (cursor)
                            0: if (screen_shadow[3:0] > 0) screen_shadow[3:0] <= screen_shadow[3:0] - 1'b1;
                            1: if (screen_shadow[7:4] > 0) screen_shadow[7:4] <= screen_shadow[7:4] - 1'b1;
                            2: if (screen_shadow[9:8] > 0) screen_shadow[9:8] <= screen_shadow[9:8] - 1'b1;
                            default: begin end // 恢复默认预览不可逐档编辑。
                        endcase
                    end else cursor <= cursor_up(cursor, menu_page || screen_page || subtitle_page);
                end else if (auto_short) begin
                    if (subtitle_edit) begin
                        case (cursor)
                            0: subtitle_shadow[0] <= 1'b1;
                            1: if (subtitle_shadow[2:1] < 2) subtitle_shadow[2:1] <= subtitle_shadow[2:1] + 1'b1;
                            2: if (subtitle_shadow[4:3] < 2) subtitle_shadow[4:3] <= subtitle_shadow[4:3] + 1'b1;
                            3: cfg_shadow[3] <= 1'b1;
                        endcase
                    end else if (screen_edit) begin
                        case (cursor)
                            0: if (screen_shadow[3:0] < 8) screen_shadow[3:0] <= screen_shadow[3:0] + 1'b1;
                            1: if (screen_shadow[7:4] < 8) screen_shadow[7:4] <= screen_shadow[7:4] + 1'b1;
                            2: if (screen_shadow[9:8] < 2) screen_shadow[9:8] <= screen_shadow[9:8] + 1'b1;
                            default: begin end
                        endcase
                    end else cursor <= cursor_down(cursor, menu_page || screen_page || subtitle_page);
                end else if (emg_short) begin
                    if (subtitle_page) begin
                        if (!subtitle_edit) begin
                            subtitle_edit <= 1'b1;
                            cfg_dirty <= 1'b1;
                        end else if (!cfg_commit_busy) begin
                            subtitle_payload <= subtitle_shadow;
                            cfg_committed <= cfg_shadow;
                            cfg_commit_toggle <= ~cfg_commit_toggle;
                            subtitle_edit <= 1'b0;
                            cfg_dirty <= 1'b0;
                        end
                    end else if (screen_page) begin
                        if (!screen_edit) begin
                            screen_edit <= 1'b1;
                            cfg_dirty <= 1'b1;
                            if (cursor == 3'd3) screen_shadow <= SCREEN_DEFAULT;
                        end else if (!cfg_commit_busy) begin
                            // 与图层共用握手邮箱，正文只能在上一笔 ACK 后更新。
                            screen_payload <= screen_shadow;
                            cfg_commit_toggle <= ~cfg_commit_toggle;
                            screen_edit <= 1'b0;
                            cfg_dirty <= 1'b0;
                        end
                    end else if (!menu_page && cursor == 3'd3) begin
                        subtitle_page <= 1'b1;
                        subtitle_edit <= 1'b0;
                        cursor <= 3'd0;
                        cfg_dirty <= 1'b0;
                        cfg_shadow <= cfg_committed;
                        period_shadow <= period_active;
                        screen_shadow <= screen_payload;
                        subtitle_shadow <= subtitle_payload;
                    end else if (!menu_page && cursor == 3'd5) begin
                        screen_page <= 1'b1;
                        screen_edit <= 1'b0;
                        cursor <= 3'd0;
                        cfg_dirty <= 1'b0;
                        cfg_shadow <= cfg_committed;
                        period_shadow <= period_active;
                        screen_shadow <= screen_payload;
                    end else if (!menu_page) begin
                        if (!cfg_dirty) begin
                            // 第一次短按只改 shadow，监视画面立即显示预览。
                            // 即使上一笔提交的 ACK 尚未返回，也不能吞掉这次预览。
                            if (cursor == 3'd4)
                                period_shadow <= (period_shadow == 2'd3) ? 2'd0 : period_shadow + 1'b1;
                            else begin
                                case (cursor[1:0])
                                    2'd0: cfg_shadow[0] <= ~cfg_shadow[0];
                                    2'd1: cfg_shadow[1] <= ~cfg_shadow[1];
                                    2'd2: cfg_shadow[2] <= ~cfg_shadow[2];
                                    default: cfg_shadow[3] <= ~cfg_shadow[3];
                                endcase
                            end
                            cfg_dirty <= 1'b1;
                        end else if (!cfg_commit_busy) begin
                            // 第二次短按才发出 toggle；视频域会在下一帧边界应用。
                            cfg_commit_toggle <= ~cfg_commit_toggle;
                            cfg_committed <= cfg_shadow;
                            period_active <= period_shadow;
                            cfg_dirty <= 1'b0;
                        end
                    end else if (cursor == 2'd1) begin
                        if (!emergency_active) begin
                            buzzer_test <= 1'b1;
                            test_count <= 0;
                        end
                    end
                end
            end
        end
    end
endmodule
