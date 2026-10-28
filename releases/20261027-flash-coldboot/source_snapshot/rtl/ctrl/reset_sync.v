// reset_sync.v — 异步断言、同步释放的时钟域复位器
module reset_sync #(
    parameter STAGES = 3
)(
    input  wire clk,
    input  wire arst,
    output wire rst
);
    reg [STAGES-1:0] sync_ff;

    always @(posedge clk or posedge arst) begin
        if (arst)
            sync_ff <= {STAGES{1'b1}};
        else
            sync_ff <= {sync_ff[STAGES-2:0], 1'b0};
    end

    assign rst = sync_ff[STAGES-1];
endmodule
