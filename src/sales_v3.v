`timescale 1ns / 1ps

module sales_v3 #(
    parameter TAKE_TIMEOUT = 32'd500_000_000,
    parameter IDLE_TIMEOUT = 32'd4_000_000_000,
    parameter MSG_TIMEOUT  = 32'd300_000_000,
    parameter LED_STEP     = 32'd12_500_000,
    parameter MAX_TOTAL    = 12'd999
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sales_en,

    input  wire        btn_confirm,
    input  wire        btn_prev,
    input  wire        btn_next,
    input  wire        btn_pay,      // checkout key in SELECT page
    input  wire        btn_cancel,

    input  wire [3:0]  kbd_data,
    input  wire        kbd_valid,

    input  wire [7:0]  price0,
    input  wire [7:0]  price1,
    input  wire [7:0]  price2,
    input  wire [7:0]  price3,
    input  wire [7:0]  stock0,
    input  wire [7:0]  stock1,
    input  wire [7:0]  stock2,
    input  wire [7:0]  stock3,
    input  wire [3:0]  enabled_mask,

    output reg  [1:0]  drink_id,
    output reg         sale_we,
    output reg  [1:0]  sale_idx,
    output reg  [7:0]  sale_amount,
    output reg         refund_pulse,
    output reg  [11:0] refund_amount,
    output reg         exit_to_main,

    output reg  [11:0] paid_amount,
    output reg  [11:0] total_amount,
    output reg  [7:0]  current_price,
    output reg  [7:0]  current_stock,
    output reg  [7:0]  cart0,
    output reg  [7:0]  cart1,
    output reg  [7:0]  cart2,
    output reg  [7:0]  cart3,

    output reg  [15:0] led_out,
    output reg  [39:0] view_data,
    output reg  [3:0]  state_code,
    output reg  [3:0]  error_code
);

    localparam ST_SELECT = 4'd0;
    localparam ST_CHECK  = 4'd1;
    localparam ST_QTY    = 4'd2;
    localparam ST_STOCK  = 4'd3;
    localparam ST_FULL   = 4'd4;
    localparam ST_ADDED  = 4'd5;
    localparam ST_PAY    = 4'd6;
    localparam ST_CHANGE = 4'd7;
    localparam ST_WAIT   = 4'd8;
    localparam ST_COMMIT = 4'd9;
    localparam ST_DONE   = 4'd10;
    localparam ST_REFUND = 4'd11;
    localparam ST_ERROR  = 4'd12;

    localparam ERR_NONE  = 4'd0;
    localparam ERR_OFF   = 4'd1;
    localparam ERR_EMPTY = 4'd2;
    localparam ERR_LESS  = 4'd3;
    localparam ERR_PRICE = 4'd4;
    localparam ERR_TIME  = 4'd5;

    localparam [4:0] C_0=5'd0,  C_1=5'd1,  C_2=5'd2,  C_3=5'd3,  C_4=5'd4;
    localparam [4:0] C_5=5'd5,  C_6=5'd6,  C_7=5'd7,  C_8=5'd8,  C_9=5'd9;
    localparam [4:0] C_A=5'd10, C_b=5'd11, C_C=5'd12, C_d=5'd13, C_E=5'd14;
    localparam [4:0] C_F=5'd15, C_H=5'd16, C_L=5'd17, C_O=5'd18, C_P=5'd19;
    localparam [4:0] C_S=5'd20, C_t=5'd21, C_r=5'd22, C_BLK=5'd23, C_U=5'd25;
    localparam [4:0] C_n=5'd26, C_Y=5'd28;

    reg [3:0]  state;
    reg [31:0] timer;
    reg [31:0] led_timer;
    reg [3:0]  led_pos;
    reg [7:0]  qty_input;
    reg [11:0] pay_entry;
    reg [11:0] paid_sum;
    reg [11:0] change_money;
    reg [11:0] need_money;
    reg [7:0]  current_cart;
    reg [7:0]  stock_left;
    reg [4:0]  name3, name2, name1, name0;
    reg [31:0] flow_limit;

    wire [15:0] total_raw = cart0 * price0 + cart1 * price1 + cart2 * price2 + cart3 * price3;
    wire [15:0] add_raw = total_raw + qty_input * current_price;
    wire [11:0] paid_show = ((paid_sum + pay_entry) > MAX_TOTAL) ? MAX_TOTAL : (paid_sum + pay_entry);

    function [4:0] num;
        input [3:0] x;
        begin
            case (x)
                4'd0: num=C_0; 4'd1: num=C_1; 4'd2: num=C_2; 4'd3: num=C_3; 4'd4: num=C_4;
                4'd5: num=C_5; 4'd6: num=C_6; 4'd7: num=C_7; 4'd8: num=C_8; 4'd9: num=C_9;
                default: num=C_BLK;
            endcase
        end
    endfunction

    function [39:0] pack8;
        input [4:0] d7,d6,d5,d4,d3,d2,d1,d0;
        begin
            pack8 = {d7,d6,d5,d4,d3,d2,d1,d0};
        end
    endfunction

    function [7:0] add_digit8;
        input [7:0] old_val;
        input [3:0] digit;
        reg [11:0] tmp;
        begin
            tmp = old_val * 10 + digit;
            add_digit8 = (tmp > 12'd99) ? 8'd99 : tmp[7:0];
        end
    endfunction

    function [11:0] add_digit12;
        input [11:0] old_val;
        input [3:0] digit;
        reg [15:0] tmp;
        begin
            tmp = old_val * 10 + digit;
            add_digit12 = (tmp > MAX_TOTAL) ? MAX_TOTAL : tmp[11:0];
        end
    endfunction

    function [15:0] pay_bar;
        input [11:0] paid;
        input [15:0] total;
        integer n;
        begin
            if (total == 0)
                pay_bar = 16'h0000;
            else if (paid >= total)
                pay_bar = 16'hffff;
            else begin
                n = (paid * 16) / total;
                pay_bar = (n == 0) ? 16'h0000 : (16'hffff >> (16 - n));
            end
        end
    endfunction

    always @(*) begin
        case (drink_id)
            2'd0: begin current_price = price0; current_stock = stock0; current_cart = cart0; end
            2'd1: begin current_price = price1; current_stock = stock1; current_cart = cart1; end
            2'd2: begin current_price = price2; current_stock = stock2; current_cart = cart2; end
            default: begin current_price = price3; current_stock = stock3; current_cart = cart3; end
        endcase

        stock_left = (current_stock > current_cart) ? (current_stock - current_cart) : 8'd0;
        total_amount = (total_raw > MAX_TOTAL) ? MAX_TOTAL : total_raw[11:0];
    end

    always @(*) begin
        case (drink_id)
            2'd0: begin name3=C_C; name2=C_O; name1=C_L; name0=C_A;   end
            2'd1: begin name3=C_S; name2=C_O; name1=C_d; name0=C_A;   end
            2'd2: begin name3=C_t; name2=C_E; name1=C_A; name0=C_BLK; end
            default: begin name3=C_H; name2=C_2; name1=C_O; name0=C_BLK; end
        endcase
    end

    always @(*) begin
        if (timer < TAKE_TIMEOUT / 2)
            flow_limit = LED_STEP;
        else if (timer < TAKE_TIMEOUT * 4 / 5)
            flow_limit = LED_STEP / 4;
        else
            flow_limit = LED_STEP / 8;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_SELECT;
            drink_id <= 2'd0;
            cart0 <= 8'd0; cart1 <= 8'd0; cart2 <= 8'd0; cart3 <= 8'd0;
            qty_input <= 8'd0;
            pay_entry <= 12'd0;
            paid_sum <= 12'd0;
            paid_amount <= 12'd0;
            change_money <= 12'd0;
            need_money <= 12'd0;
            timer <= 32'd0;
            led_timer <= 32'd0;
            led_pos <= 4'd0;
            error_code <= ERR_NONE;
            sale_we <= 1'b0;
            sale_idx <= 2'd0;
            sale_amount <= 8'd0;
            refund_pulse <= 1'b0;
            refund_amount <= 12'd0;
            exit_to_main <= 1'b0;
        end else begin
            sale_we <= 1'b0;
            refund_pulse <= 1'b0;
            exit_to_main <= 1'b0;
            paid_amount <= paid_show;

            if (!sales_en) begin
                state <= ST_SELECT;
                cart0 <= 8'd0; cart1 <= 8'd0; cart2 <= 8'd0; cart3 <= 8'd0;
                qty_input <= 8'd0;
                pay_entry <= 12'd0;
                paid_sum <= 12'd0;
                timer <= 32'd0;
                error_code <= ERR_NONE;
            end else begin
                case (state)
                    ST_SELECT: begin
                        qty_input <= 8'd0;
                        pay_entry <= 12'd0;
                        paid_sum <= 12'd0;
                        timer <= 32'd0;
                        error_code <= ERR_NONE;
                        if (btn_next)
                            drink_id <= (drink_id == 2'd3) ? 2'd0 : drink_id + 1'b1;
                        else if (btn_prev)
                            drink_id <= (drink_id == 2'd0) ? 2'd3 : drink_id - 1'b1;
                        else if (btn_confirm)
                            state <= ST_CHECK;
                        else if (btn_pay && total_raw != 0)
                            state <= ST_PAY;
                        else if (btn_cancel) begin
                            cart0 <= 8'd0; cart1 <= 8'd0; cart2 <= 8'd0; cart3 <= 8'd0;
                            exit_to_main <= 1'b1;
                        end
                    end

                    ST_CHECK: begin
                        timer <= 32'd0;
                        if (!enabled_mask[drink_id]) begin
                            error_code <= ERR_OFF;
                            state <= ST_ERROR;
                        end else if (stock_left == 8'd0) begin
                            error_code <= ERR_EMPTY;
                            state <= ST_ERROR;
                        end else if (current_price == 8'd0 || current_price > 8'd9) begin
                            error_code <= ERR_PRICE;
                            state <= ST_ERROR;
                        end else begin
                            state <= ST_QTY;
                        end
                    end

                    ST_QTY: begin
                        if (kbd_valid && kbd_data <= 4'd9) begin
                            qty_input <= add_digit8(qty_input, kbd_data);
                            timer <= 32'd0;
                        end else if (btn_cancel) begin
                            qty_input <= 8'd0;
                            state <= ST_SELECT;
                            timer <= 32'd0;
                        end else if (btn_confirm) begin
                            if (qty_input == 8'd0) begin
                                timer <= 32'd0;
                            end else if (qty_input > stock_left) begin
                                qty_input <= 8'd0;
                                state <= ST_STOCK;
                                timer <= 32'd0;
                            end else if (add_raw > MAX_TOTAL) begin
                                qty_input <= 8'd0;
                                state <= ST_FULL;
                                timer <= 32'd0;
                            end else begin
                                case (drink_id)
                                    2'd0: cart0 <= cart0 + qty_input;
                                    2'd1: cart1 <= cart1 + qty_input;
                                    2'd2: cart2 <= cart2 + qty_input;
                                    default: cart3 <= cart3 + qty_input;
                                endcase
                                qty_input <= 8'd0;
                                state <= ST_ADDED;
                                timer <= 32'd0;
                            end
                        end else if (timer >= IDLE_TIMEOUT) begin
                            cart0 <= 8'd0; cart1 <= 8'd0; cart2 <= 8'd0; cart3 <= 8'd0;
                            qty_input <= 8'd0;
                            state <= ST_SELECT;
                            timer <= 32'd0;
                        end else begin
                            timer <= timer + 1'b1;
                        end
                    end

                    ST_STOCK, ST_FULL, ST_ADDED: begin
                        if (btn_confirm || btn_cancel || timer >= MSG_TIMEOUT) begin
                            state <= ST_SELECT;
                            timer <= 32'd0;
                        end else if (btn_pay && total_raw != 0) begin
                            state <= ST_PAY;
                            timer <= 32'd0;
                        end else begin
                            timer <= timer + 1'b1;
                        end
                    end

                    ST_PAY: begin
                        if (kbd_valid && kbd_data <= 4'd9) begin
                            pay_entry <= add_digit12(pay_entry, kbd_data);
                            error_code <= ERR_NONE;
                            need_money <= 12'd0;
                            timer <= 32'd0;
                        end else if (btn_cancel) begin
                            if (paid_show != 0) begin
                                refund_pulse <= 1'b1;
                                refund_amount <= paid_show;
                            end
                            state <= ST_REFUND;
                            timer <= 32'd0;
                        end else if (btn_confirm) begin
                            if (paid_show < total_raw) begin
                                paid_sum <= paid_show;
                                pay_entry <= 12'd0;
                                need_money <= total_raw - paid_show;
                                error_code <= ERR_LESS;
                                timer <= 32'd0;
                            end else if (paid_show == total_raw) begin
                                paid_sum <= paid_show;
                                pay_entry <= 12'd0;
                                state <= ST_WAIT;
                                timer <= 32'd0;
                                led_timer <= 32'd0;
                                led_pos <= 4'd0;
                            end else begin
                                change_money <= paid_show - total_raw;
                                refund_pulse <= 1'b1;
                                refund_amount <= paid_show - total_raw;
                                paid_sum <= total_raw[11:0];
                                pay_entry <= 12'd0;
                                state <= ST_CHANGE;
                                timer <= 32'd0;
                            end
                        end else if (timer >= IDLE_TIMEOUT) begin
                            if (paid_show != 0) begin
                                refund_pulse <= 1'b1;
                                refund_amount <= paid_show;
                            end
                            error_code <= ERR_TIME;
                            state <= ST_REFUND;
                            timer <= 32'd0;
                        end else begin
                            timer <= timer + 1'b1;
                        end
                    end

                    ST_CHANGE: begin
                        if (btn_confirm || timer >= MSG_TIMEOUT) begin
                            state <= ST_WAIT;
                            timer <= 32'd0;
                            led_timer <= 32'd0;
                            led_pos <= 4'd0;
                        end else begin
                            timer <= timer + 1'b1;
                        end
                    end

                    ST_WAIT: begin
                        if (btn_confirm) begin
                            state <= ST_COMMIT;
                            timer <= 32'd0;
                        end else if (btn_cancel) begin
                            refund_pulse <= 1'b1;
                            refund_amount <= total_amount;
                            state <= ST_REFUND;
                            timer <= 32'd0;
                        end else if (timer >= TAKE_TIMEOUT) begin
                            refund_pulse <= 1'b1;
                            refund_amount <= total_amount;
                            error_code <= ERR_TIME;
                            state <= ST_REFUND;
                            timer <= 32'd0;
                        end else begin
                            timer <= timer + 1'b1;
                            if (led_timer >= flow_limit) begin
                                led_timer <= 32'd0;
                                led_pos <= (led_pos == 4'd15) ? 4'd0 : led_pos + 1'b1;
                            end else begin
                                led_timer <= led_timer + 1'b1;
                            end
                        end
                    end

                    ST_COMMIT: begin
                        timer <= 32'd0;
                        if (cart0 != 0) begin
                            sale_we <= 1'b1; sale_idx <= 2'd0; sale_amount <= price0; cart0 <= cart0 - 1'b1;
                        end else if (cart1 != 0) begin
                            sale_we <= 1'b1; sale_idx <= 2'd1; sale_amount <= price1; cart1 <= cart1 - 1'b1;
                        end else if (cart2 != 0) begin
                            sale_we <= 1'b1; sale_idx <= 2'd2; sale_amount <= price2; cart2 <= cart2 - 1'b1;
                        end else if (cart3 != 0) begin
                            sale_we <= 1'b1; sale_idx <= 2'd3; sale_amount <= price3; cart3 <= cart3 - 1'b1;
                        end else begin
                            paid_sum <= 12'd0;
                            pay_entry <= 12'd0;
                            state <= ST_DONE;
                        end
                    end

                    ST_DONE, ST_REFUND, ST_ERROR: begin
                        if (btn_confirm || btn_cancel || timer >= MSG_TIMEOUT) begin
                            cart0 <= 8'd0; cart1 <= 8'd0; cart2 <= 8'd0; cart3 <= 8'd0;
                            qty_input <= 8'd0;
                            pay_entry <= 12'd0;
                            paid_sum <= 12'd0;
                            error_code <= ERR_NONE;
                            state <= ST_SELECT;
                            timer <= 32'd0;
                        end else begin
                            timer <= timer + 1'b1;
                        end
                    end

                    default: state <= ST_SELECT;
                endcase
            end
        end
    end

    always @(*) begin
        state_code = state;
        led_out = 16'h0000;
        view_data = pack8(C_BLK,C_BLK,C_BLK,C_BLK,C_BLK,C_BLK,C_BLK,C_BLK);

        case (state)
            ST_SELECT: begin
                led_out = 16'h0001 << drink_id;
                view_data = pack8(name3,name2,name1,name0,num(current_price[3:0]),C_BLK,
                                  num((stock_left > 8'd99) ? 4'd9 : stock_left / 10),
                                  num((stock_left > 8'd99) ? 4'd9 : stock_left % 10));
            end
            ST_CHECK: begin
                view_data = pack8(C_BLK,C_C,C_H,C_E,C_C,C_BLK,C_BLK,C_BLK);
                led_out = 16'h000f;
            end
            ST_QTY: begin
                view_data = pack8(C_C,C_n,C_t,
                                  num(qty_input / 10), num(qty_input % 10),
                                  C_BLK,C_P,num(current_price[3:0]));
                led_out = 16'h000f << drink_id;
            end
            ST_STOCK: begin
                view_data = pack8(C_S,C_t,C_O,C_C,C_BLK,
                                  num(stock_left / 10), num(stock_left % 10), C_BLK);
                led_out = 16'hf0f0;
            end
            ST_FULL: begin
                view_data = pack8(C_F,C_U,C_L,C_L,C_BLK,C_9,C_9,C_9);
                led_out = 16'hffff;
            end
            ST_ADDED: begin
                view_data = pack8(C_t,C_O,C_t,C_BLK,
                                  num(total_amount / 100), num((total_amount / 10) % 10), num(total_amount % 10), C_BLK);
                led_out = 16'h00ff;
            end
            ST_PAY: begin
                led_out = pay_bar(paid_show, total_raw);
                if (error_code == ERR_LESS)
                    view_data = pack8(C_A,C_d,C_d,C_BLK,C_BLK,
                                      num(need_money / 100), num((need_money / 10) % 10), num(need_money % 10));
                else
                    view_data = pack8(num(paid_show / 1000), num((paid_show / 100) % 10),
                                      num((paid_show / 10) % 10), num(paid_show % 10), C_t,
                                      num(total_amount / 100), num((total_amount / 10) % 10), num(total_amount % 10));
            end
            ST_CHANGE: begin
                view_data = pack8(C_r,C_E,C_t,C_BLK,C_BLK,
                                  num(change_money / 100), num((change_money / 10) % 10), num(change_money % 10));
                led_out = 16'h00ff;
            end
            ST_WAIT: begin
                view_data = pack8(C_P,C_U,C_S,C_H,C_BLK,C_BLK,C_BLK,C_BLK);
                led_out = 16'h0001 << led_pos;
            end
            ST_COMMIT: begin
                view_data = pack8(C_BLK,C_BLK,C_O,C_U,C_t,C_BLK,C_BLK,C_BLK);
                led_out = 16'hffff;
            end
            ST_DONE: begin
                view_data = pack8(C_d,C_O,C_n,C_E,C_BLK,C_BLK,C_BLK,C_BLK);
                led_out = 16'haaaa;
            end
            ST_REFUND: begin
                view_data = pack8(C_r,C_E,C_t,C_BLK,C_BLK,
                                  num(refund_amount / 100), num((refund_amount / 10) % 10), num(refund_amount % 10));
                led_out = 16'h5555;
            end
            ST_ERROR: begin
                view_data = pack8(C_E,C_r,C_r,C_BLK,C_BLK,C_BLK,C_BLK,num(error_code));
                led_out = 16'hf00f;
            end
        endcase
    end

endmodule
