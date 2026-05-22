module btn_debounce #(
    parameter CNT_MAX = 2_000_000,  // 50Hz， 消抖时间20ms
    parameter CNT_WIDTH = 25
) (
    input clk,
    input rst_n,
    input btn_in,  // 高电平有效
    output reg btn_out
    );

    reg [CNT_WIDTH-1:0] cnt_20ms;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt_20ms <= 'b0;
        else if (btn_in == 1'b0)
            cnt_20ms <= 'b0;
        else if (cnt_20ms == CNT_MAX -1'b1 && btn_in ==1'b1)
            cnt_20ms <= cnt_20ms;
        else
            cnt_20ms <= cnt_20ms + 1'b1;    
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            btn_out <= 1'b0;
        else if (cnt_20ms == CNT_MAX -2'd2)
            btn_out <= 1'b1;
        else
            btn_out <= 1'b0;
    end
endmodule