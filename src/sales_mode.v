`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: sales_mode
<<<<<<< HEAD
// Description : Sales-mode FSM for the FPGA vending machine project.
//
// Notes:
// 1. All button inputs are assumed to be debounced one-cycle pulses by top/C.
// 2. This module does not directly store price/stock/revenue. It reads the current
//    item information from the central register file and sends one-cycle pulses
//    back to top/register_file when an order is completed or refunded.
// 3. switch_in is reused:
//    - In SELECT state: switch_in[2:0] is the selected drink ID.
//    - In PAY state   : switch_in[7:0] is the amount added by one pay pulse.
//////////////////////////////////////////////////////////////////////////////////

module sales_mode #(
    parameter CLK_FREQ_HZ = 100_000_000,
    parameter TAKE_TIMEOUT_CYCLES = 500_000_000, // 5 seconds at 100 MHz
    parameter LED_STEP_CYCLES = 12_500_000       // base speed for running LED
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sales_en,       // 1 means the global controller is in sales mode

    // User inputs. These should be one-cycle pulses after debounce.
    input  wire [7:0]  switch_in,
    input  wire        btn_confirm,
    input  wire        btn_pay,
    input  wire        btn_take,
    input  wire        btn_cancel,

    // Current selected drink information from register_file / top.
    input  wire [7:0]  current_stock,
    input  wire [7:0]  current_price,
    input  wire [3:0]  sold_out_mask,  // 1 means the corresponding drink is off-sale

    // Query/control outputs to register_file / top.
    output reg  [2:0]  drink_id,
    output reg         order_done_pulse, // one-cycle pulse: decrease stock and add revenue
    output reg         refund_pulse,     // one-cycle pulse: timeout/cancel refund, no revenue
    output reg  [7:0]  paid_amount,
    output reg  [7:0]  sold_price,

    // Outputs for display/debug.
    output reg  [15:0] led_out,
    output reg  [31:0] view_data,   // 8 nibbles for seven-segment display driver
    output reg  [3:0]  state_code,
    output reg  [3:0]  error_code
=======
// Description : Sales-mode FSM for a 4-item FPGA vending machine on EGO1.
//
// Board operation convention:
//   S0 -> btn_confirm : confirm selection / confirm payment / take item
//   S1 -> btn_prev    : previous drink page in SELECT state
//   S2 -> btn_next    : next drink page in SELECT state
//   S3 -> btn_pay     : add switch_in[7:0] to balance in PAY state
//   S4 -> btn_cancel  : cancel current order / return from message states
//   SW[7:0] -> switch_in : amount input in PAY state
//
// Recommended four drinks and demo-friendly prices:
//   0 COLA: price 4, stock 5, display COLA04S5
//   1 SODA: price 5, stock 6, display SOdA05S6
//   2 TEA : price 3, stock 8, display tEA 03S8
//   3 H2O : price 2, stock 9, display H2O 02S9
//
// Display convention:
//   view_data is 8 characters packed as 8 x 5-bit character IDs.
//   The order is {digit7,digit6,...,digit0}, where digit7 is the leftmost digit.
//////////////////////////////////////////////////////////////////////////////////

module sales_mode #(
    parameter [31:0] CLK_FREQ_HZ                = 32'd100_000_000,
    parameter [31:0] TAKE_TIMEOUT_CYCLES        = 32'd500_000_000,  // 5 s @ 100 MHz
    parameter [31:0] INACTIVITY_TIMEOUT_CYCLES  = 32'd3_000_000_000, // 30 s @ 100 MHz
    parameter [31:0] MESSAGE_TIMEOUT_CYCLES     = 32'd300_000_000,  // 3 s @ 100 MHz
    parameter [31:0] LED_STEP_CYCLES            = 32'd12_500_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sales_en,

    // User inputs. These should be debounced one-cycle pulses by top/C.
    input  wire [7:0]  switch_in,
    input  wire        btn_confirm,
    input  wire        btn_prev,
    input  wire        btn_next,
    input  wire        btn_pay,
    input  wire        btn_cancel,

    // Product data from top/register_file. Four drinks only: 0~3.
    input  wire [7:0]  price0,
    input  wire [7:0]  price1,
    input  wire [7:0]  price2,
    input  wire [7:0]  price3,
    input  wire [3:0]  stock0,
    input  wire [3:0]  stock1,
    input  wire [3:0]  stock2,
    input  wire [3:0]  stock3,
    input  wire [3:0]  enabled_mask, // 1 means this drink is on sale

    // Outputs to register_file/top.
    output reg  [1:0]  drink_id,
    output reg         sale_we,
    output reg  [1:0]  sale_idx,
    output reg  [7:0]  sale_amount,
    output reg         refund_pulse,
    output reg  [7:0]  refund_amount,
    output reg         exit_to_main,

    // Outputs for display/debug.
    output reg  [7:0]  paid_amount,
    output reg  [7:0]  current_price,
    output reg  [3:0]  current_stock,
    output reg  [15:0] led_out,
    output reg  [39:0] view_data,     // 8 x 5-bit character IDs, digit7..digit0
    output reg  [3:0]  state_code,
    output reg  [3:0]  error_code,
    output reg  [3:0]  countdown_sec
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
);

    // State encoding
    localparam S_IDLE      = 4'd0;
    localparam S_SELECT    = 4'd1;
    localparam S_CHECK     = 4'd2;
    localparam S_PAY       = 4'd3;
    localparam S_DISPENSE  = 4'd4;
    localparam S_WAIT_TAKE = 4'd5;
    localparam S_COMPLETE  = 4'd6;
    localparam S_REFUND    = 4'd7;
    localparam S_ERROR     = 4'd8;

    // Error encoding
    localparam ERR_NONE        = 4'd0;
<<<<<<< HEAD
    localparam ERR_INVALID_ID  = 4'd1;
    localparam ERR_OFF_SALE    = 4'd2;
    localparam ERR_NO_STOCK    = 4'd3;
    localparam ERR_NOT_ENOUGH  = 4'd4;
    localparam ERR_BAD_PRICE   = 4'd5;

    reg [3:0] current_state;
    reg [31:0] take_timer;
    reg [31:0] led_timer;
    reg [3:0]  led_pos;

    reg [31:0] flow_limit;

    // LED running speed becomes faster when timeout is getting close.
    always @(*) begin
        if (take_timer < (TAKE_TIMEOUT_CYCLES / 2))
            flow_limit = (LED_STEP_CYCLES < 1) ? 1 : LED_STEP_CYCLES;
        else if (take_timer < ((TAKE_TIMEOUT_CYCLES * 4) / 5))
            flow_limit = (LED_STEP_CYCLES < 4) ? 1 : (LED_STEP_CYCLES / 4);
        else
            flow_limit = (LED_STEP_CYCLES < 8) ? 1 : (LED_STEP_CYCLES / 8);
    end

    // Convert payment progress to 16-bit LED progress bar.
=======
    localparam ERR_OFF_SALE    = 4'd1;
    localparam ERR_NO_STOCK    = 4'd2;
    localparam ERR_NOT_ENOUGH  = 4'd3;
    localparam ERR_BAD_PRICE   = 4'd4;
    localparam ERR_TIMEOUT     = 4'd5;

    // Character ID encoding for view_data. C/display driver maps these IDs to seg7 patterns.
    localparam [4:0] CH_0     = 5'd0;
    localparam [4:0] CH_1     = 5'd1;
    localparam [4:0] CH_2     = 5'd2;
    localparam [4:0] CH_3     = 5'd3;
    localparam [4:0] CH_4     = 5'd4;
    localparam [4:0] CH_5     = 5'd5;
    localparam [4:0] CH_6     = 5'd6;
    localparam [4:0] CH_7     = 5'd7;
    localparam [4:0] CH_8     = 5'd8;
    localparam [4:0] CH_9     = 5'd9;
    localparam [4:0] CH_A     = 5'd10;
    localparam [4:0] CH_B     = 5'd11;
    localparam [4:0] CH_C     = 5'd12;
    localparam [4:0] CH_D     = 5'd13;
    localparam [4:0] CH_E     = 5'd14;
    localparam [4:0] CH_F     = 5'd15;
    localparam [4:0] CH_H     = 5'd16;
    localparam [4:0] CH_L     = 5'd17;
    localparam [4:0] CH_O     = 5'd18;
    localparam [4:0] CH_P     = 5'd19;
    localparam [4:0] CH_S     = 5'd20;
    localparam [4:0] CH_T     = 5'd21;
    localparam [4:0] CH_R     = 5'd22;
    localparam [4:0] CH_BLANK = 5'd23;
    localparam [4:0] CH_DASH  = 5'd24;
    localparam [4:0] CH_U     = 5'd25;
    localparam [4:0] CH_N     = 5'd26;
    localparam [4:0] CH_I     = 5'd27;
    localparam [4:0] CH_Y     = 5'd28;

    reg [3:0]  current_state;
    reg [31:0] take_timer;
    reg [31:0] idle_timer;
    reg [31:0] led_timer;
    reg [3:0]  led_pos;
    reg [31:0] flow_limit;

    wire any_button = btn_confirm | btn_prev | btn_next | btn_pay | btn_cancel;

    function [4:0] digit_char;
        input [3:0] value;
        begin
            case (value)
                4'd0: digit_char = CH_0;
                4'd1: digit_char = CH_1;
                4'd2: digit_char = CH_2;
                4'd3: digit_char = CH_3;
                4'd4: digit_char = CH_4;
                4'd5: digit_char = CH_5;
                4'd6: digit_char = CH_6;
                4'd7: digit_char = CH_7;
                4'd8: digit_char = CH_8;
                4'd9: digit_char = CH_9;
                default: digit_char = CH_BLANK;
            endcase
        end
    endfunction

    function [39:0] pack8;
        input [4:0] d7, d6, d5, d4, d3, d2, d1, d0;
        begin
            pack8 = {d7, d6, d5, d4, d3, d2, d1, d0};
        end
    endfunction

>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
    function [15:0] progress_bar;
        input [7:0] paid;
        input [7:0] price;
        integer n;
        begin
            if (price == 0) begin
                progress_bar = 16'h0000;
            end else if (paid >= price) begin
                progress_bar = 16'hFFFF;
            end else begin
                n = (paid * 16) / price;
                if (n <= 0)
                    progress_bar = 16'h0000;
                else
                    progress_bar = (16'hFFFF >> (16 - n));
            end
        end
    endfunction

<<<<<<< HEAD
    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state    <= S_IDLE;
            drink_id         <= 3'd0;
            order_done_pulse <= 1'b0;
            refund_pulse     <= 1'b0;
            paid_amount      <= 8'd0;
            sold_price       <= 8'd0;
            error_code       <= ERR_NONE;
            state_code       <= S_IDLE;
            take_timer       <= 32'd0;
            led_timer        <= 32'd0;
            led_pos          <= 4'd0;
        end else begin
            // Default one-cycle pulses.
            order_done_pulse <= 1'b0;
            refund_pulse     <= 1'b0;
            state_code       <= current_state;
=======
    // Current product data mux
    always @(*) begin
        case (drink_id)
            2'd0: begin current_price = price0; current_stock = stock0; end
            2'd1: begin current_price = price1; current_stock = stock1; end
            2'd2: begin current_price = price2; current_stock = stock2; end
            2'd3: begin current_price = price3; current_stock = stock3; end
            default: begin current_price = 8'd0; current_stock = 4'd0; end
        endcase
    end

    // Pickup LED speed becomes faster when timeout is getting close.
    always @(*) begin
        if (take_timer < (TAKE_TIMEOUT_CYCLES / 2))
            flow_limit = (LED_STEP_CYCLES < 1) ? 1 : LED_STEP_CYCLES;
        else if (take_timer < ((TAKE_TIMEOUT_CYCLES * 4) / 5))
            flow_limit = (LED_STEP_CYCLES < 4) ? 1 : (LED_STEP_CYCLES / 4);
        else
            flow_limit = (LED_STEP_CYCLES < 8) ? 1 : (LED_STEP_CYCLES / 8);
    end

    // Display countdown as 5,4,3,2,1,0 by thresholds.
    always @(*) begin
        if (current_state != S_WAIT_TAKE)
            countdown_sec = 4'd0;
        else if (take_timer < (TAKE_TIMEOUT_CYCLES / 5))
            countdown_sec = 4'd5;
        else if (take_timer < ((TAKE_TIMEOUT_CYCLES * 2) / 5))
            countdown_sec = 4'd4;
        else if (take_timer < ((TAKE_TIMEOUT_CYCLES * 3) / 5))
            countdown_sec = 4'd3;
        else if (take_timer < ((TAKE_TIMEOUT_CYCLES * 4) / 5))
            countdown_sec = 4'd2;
        else if (take_timer < TAKE_TIMEOUT_CYCLES)
            countdown_sec = 4'd1;
        else
            countdown_sec = 4'd0;
    end

    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            drink_id     <= 2'd0;
            paid_amount  <= 8'd0;
            sale_we      <= 1'b0;
            sale_idx     <= 2'd0;
            sale_amount  <= 8'd0;
            refund_pulse <= 1'b0;
            refund_amount<= 8'd0;
            exit_to_main <= 1'b0;
            error_code   <= ERR_NONE;
            state_code   <= S_IDLE;
            take_timer   <= 32'd0;
            idle_timer   <= 32'd0;
            led_timer    <= 32'd0;
            led_pos      <= 4'd0;
        end else begin
            sale_we      <= 1'b0;
            refund_pulse <= 1'b0;
            exit_to_main <= 1'b0;
            state_code   <= current_state;
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9

            if (!sales_en) begin
                current_state <= S_IDLE;
                paid_amount   <= 8'd0;
                error_code    <= ERR_NONE;
                take_timer    <= 32'd0;
<<<<<<< HEAD
                led_timer     <= 32'd0;
                led_pos       <= 4'd0;
            end else begin
=======
                idle_timer    <= 32'd0;
                led_timer     <= 32'd0;
                led_pos       <= 4'd0;
            end else begin
                if (current_state == S_SELECT || current_state == S_IDLE || current_state == S_WAIT_TAKE) begin
                    idle_timer <= 32'd0;
                end else if (any_button) begin
                    idle_timer <= 32'd0;
                end else if (idle_timer < INACTIVITY_TIMEOUT_CYCLES - 1) begin
                    idle_timer <= idle_timer + 1'b1;
                end

>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                case (current_state)
                    S_IDLE: begin
                        current_state <= S_SELECT;
                        paid_amount   <= 8'd0;
                        error_code    <= ERR_NONE;
                    end

                    S_SELECT: begin
                        paid_amount <= 8'd0;
<<<<<<< HEAD
                        take_timer  <= 32'd0;
                        led_timer   <= 32'd0;
                        led_pos     <= 4'd0;
                        error_code  <= ERR_NONE;
                        if (btn_confirm) begin
                            drink_id      <= switch_in[2:0];
                            current_state <= S_CHECK;
=======
                        error_code  <= ERR_NONE;
                        take_timer  <= 32'd0;
                        led_timer   <= 32'd0;
                        led_pos     <= 4'd0;
                        if (btn_next) begin
                            drink_id <= (drink_id == 2'd3) ? 2'd0 : drink_id + 1'b1;
                        end else if (btn_prev) begin
                            drink_id <= (drink_id == 2'd0) ? 2'd3 : drink_id - 1'b1;
                        end else if (btn_confirm) begin
                            current_state <= S_CHECK;
                        end else if (btn_cancel) begin
                            exit_to_main <= 1'b1;
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                        end
                    end

                    S_CHECK: begin
<<<<<<< HEAD
                        if (drink_id > 3'd3) begin
                            error_code    <= ERR_INVALID_ID;
                            current_state <= S_ERROR;
                        end else if (sold_out_mask[drink_id]) begin
                            error_code    <= ERR_OFF_SALE;
                            current_state <= S_ERROR;
                        end else if (current_stock == 8'd0) begin
=======
                        if (!enabled_mask[drink_id]) begin
                            error_code    <= ERR_OFF_SALE;
                            current_state <= S_ERROR;
                        end else if (current_stock == 4'd0) begin
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                            error_code    <= ERR_NO_STOCK;
                            current_state <= S_ERROR;
                        end else if (current_price == 8'd0) begin
                            error_code    <= ERR_BAD_PRICE;
                            current_state <= S_ERROR;
                        end else begin
                            error_code    <= ERR_NONE;
                            current_state <= S_PAY;
                        end
                    end

                    S_PAY: begin
                        if (btn_cancel) begin
<<<<<<< HEAD
                            refund_pulse  <= (paid_amount != 8'd0);
                            current_state <= S_REFUND;
                        end else if (btn_pay) begin
                            // Saturating addition to avoid overflow.
=======
                            if (paid_amount != 8'd0) begin
                                refund_pulse  <= 1'b1;
                                refund_amount <= paid_amount;
                            end
                            current_state <= S_REFUND;
                        end else if (idle_timer >= INACTIVITY_TIMEOUT_CYCLES - 1) begin
                            if (paid_amount != 8'd0) begin
                                refund_pulse  <= 1'b1;
                                refund_amount <= paid_amount;
                            end
                            error_code    <= ERR_TIMEOUT;
                            current_state <= S_REFUND;
                        end else if (btn_pay) begin
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                            if (paid_amount + switch_in < paid_amount)
                                paid_amount <= 8'hFF;
                            else
                                paid_amount <= paid_amount + switch_in;
                        end else if (btn_confirm) begin
                            if (paid_amount >= current_price) begin
<<<<<<< HEAD
                                sold_price    <= current_price;
=======
                                sale_amount   <= current_price;
                                sale_idx      <= drink_id;
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                                take_timer    <= 32'd0;
                                led_timer     <= 32'd0;
                                led_pos       <= 4'd0;
                                error_code    <= ERR_NONE;
                                current_state <= S_DISPENSE;
                            end else begin
<<<<<<< HEAD
                                // Stay in payment state and show "not enough money" error.
=======
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                                error_code <= ERR_NOT_ENOUGH;
                            end
                        end
                    end

                    S_DISPENSE: begin
<<<<<<< HEAD
                        // One transition state: item is dispensed, then wait for user to take it.
=======
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                        take_timer    <= 32'd0;
                        led_timer     <= 32'd0;
                        led_pos       <= 4'd0;
                        current_state <= S_WAIT_TAKE;
                    end

                    S_WAIT_TAKE: begin
<<<<<<< HEAD
                        if (btn_take) begin
                            order_done_pulse <= 1'b1;
                            current_state    <= S_COMPLETE;
                        end else if (take_timer >= TAKE_TIMEOUT_CYCLES - 1) begin
                            refund_pulse  <= 1'b1;
                            current_state <= S_REFUND;
                        end else begin
                            take_timer <= take_timer + 1'b1;

                            if (led_timer >= flow_limit - 1) begin
                                led_timer <= 32'd0;
                                if (led_pos == 4'd15)
                                    led_pos <= 4'd0;
                                else
                                    led_pos <= led_pos + 1'b1;
=======
                        if (btn_confirm) begin
                            sale_we       <= 1'b1;
                            sale_idx      <= drink_id;
                            sale_amount   <= current_price;
                            current_state <= S_COMPLETE;
                        end else if (btn_cancel) begin
                            refund_pulse  <= 1'b1;
                            refund_amount <= paid_amount;
                            current_state <= S_REFUND;
                        end else if (take_timer >= TAKE_TIMEOUT_CYCLES - 1) begin
                            refund_pulse  <= 1'b1;
                            refund_amount <= paid_amount;
                            error_code    <= ERR_TIMEOUT;
                            current_state <= S_REFUND;
                        end else begin
                            take_timer <= take_timer + 1'b1;
                            if (led_timer >= flow_limit - 1) begin
                                led_timer <= 32'd0;
                                led_pos   <= (led_pos == 4'd15) ? 4'd0 : led_pos + 1'b1;
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                            end else begin
                                led_timer <= led_timer + 1'b1;
                            end
                        end
                    end

                    S_COMPLETE: begin
<<<<<<< HEAD
                        // Wait for confirm/cancel to return to selection.
                        if (btn_confirm || btn_cancel) begin
=======
                        if (btn_confirm || btn_cancel || idle_timer >= MESSAGE_TIMEOUT_CYCLES - 1) begin
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                            paid_amount   <= 8'd0;
                            current_state <= S_SELECT;
                        end
                    end

                    S_REFUND: begin
<<<<<<< HEAD
                        // No revenue is counted in this state.
                        if (btn_confirm || btn_cancel) begin
                            paid_amount   <= 8'd0;
                            current_state <= S_SELECT;
                        end
                    end

                    S_ERROR: begin
                        if (btn_confirm || btn_cancel) begin
=======
                        if (btn_confirm || btn_cancel || idle_timer >= MESSAGE_TIMEOUT_CYCLES - 1) begin
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                            paid_amount   <= 8'd0;
                            error_code    <= ERR_NONE;
                            current_state <= S_SELECT;
                        end
                    end

<<<<<<< HEAD
                    default: begin
                        current_state <= S_IDLE;
                    end
=======
                    S_ERROR: begin
                        if (btn_confirm || btn_cancel || idle_timer >= MESSAGE_TIMEOUT_CYCLES - 1) begin
                            paid_amount   <= 8'd0;
                            error_code    <= ERR_NONE;
                            current_state <= S_SELECT;
                        end
                    end

                    default: current_state <= S_IDLE;
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                endcase
            end
        end
    end

<<<<<<< HEAD
    // LED and seven-segment display data.
    // Nibble values 0-F are intended for a future seven-segment decoder.
    always @(*) begin
        led_out   = 16'h0000;
        view_data = 32'hFFFFFFFF; // F can be treated as blank by the display driver.
=======
    // Drink name characters optimized for seven-segment display.
    reg [4:0] n3, n2, n1, n0;
    always @(*) begin
        case (drink_id)
            2'd0: begin n3 = CH_C; n2 = CH_O; n1 = CH_L;     n0 = CH_A;     end
            2'd1: begin n3 = CH_S; n2 = CH_O; n1 = CH_D;     n0 = CH_A;     end
            2'd2: begin n3 = CH_T; n2 = CH_E; n1 = CH_A;     n0 = CH_BLANK; end
            2'd3: begin n3 = CH_H; n2 = CH_2; n1 = CH_O;     n0 = CH_BLANK; end
            default: begin n3 = CH_BLANK; n2 = CH_BLANK; n1 = CH_BLANK; n0 = CH_BLANK; end
        endcase
    end

    // LED and display output generation.
    always @(*) begin
        led_out   = 16'h0000;
        view_data = pack8(CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK);
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9

        case (current_state)
            S_IDLE: begin
                led_out   = 16'h0000;
<<<<<<< HEAD
                view_data = 32'h1D1E_FFFF; // approximate IDLE
            end

            S_SELECT: begin
                led_out   = 16'h0001;
                view_data = {4'h5, 4'hE, 4'h1, 4'hF, 4'hF, 1'b0, switch_in[2:0], 4'hF, 4'hF};
                // approximate "SEL item_id"
            end

            S_CHECK: begin
                led_out   = 16'h0003;
                view_data = {4'hC, 4'hE, 4'hC, 4'hF, 4'hF, 1'b0, drink_id, 4'hF, 4'hF};
            end

            S_PAY: begin
                led_out   = progress_bar(paid_amount, current_price);
                view_data = {8'h00, paid_amount[7:4], paid_amount[3:0],
                             8'h00, current_price[7:4], current_price[3:0]};
=======
                view_data = pack8(CH_BLANK,CH_BLANK,CH_S,CH_E,CH_L,CH_BLANK,CH_BLANK,CH_BLANK);
            end

            S_SELECT: begin
                // Layout: [name4][price2][S][stock], e.g. COLA04S5.
                led_out   = 16'h0001 << drink_id;
                view_data = pack8(n3, n2, n1, n0,
                                  digit_char((current_price / 10) % 10),
                                  digit_char(current_price % 10),
                                  CH_S,
                                  digit_char(current_stock));
            end

            S_CHECK: begin
                led_out   = 16'h000F;
                view_data = pack8(CH_BLANK,CH_BLANK,CH_C,CH_H,CH_E,CH_C,CH_BLANK,CH_BLANK);
            end

            S_PAY: begin
                // Layout: bAL[balance2]P[price2], e.g. bAL04P04.
                led_out   = progress_bar(paid_amount, current_price);
                view_data = pack8(CH_B, CH_A, CH_L,
                                  digit_char((paid_amount / 10) % 10),
                                  digit_char(paid_amount % 10),
                                  CH_P,
                                  digit_char((current_price / 10) % 10),
                                  digit_char(current_price % 10));
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            end

            S_DISPENSE: begin
                led_out   = 16'hFFFF;
<<<<<<< HEAD
                view_data = 32'hD15F_FFFF; // approximate DISP
            end

            S_WAIT_TAKE: begin
                led_out   = (16'h0001 << led_pos);
                view_data = {16'h0000, take_timer[15:0]}; // debug countdown/timer
=======
                view_data = pack8(CH_BLANK,CH_BLANK,CH_O,CH_U,CH_T,CH_BLANK,CH_BLANK,CH_BLANK);
            end

            S_WAIT_TAKE: begin
                led_out   = 16'h0001 << led_pos;
                view_data = pack8(CH_P,CH_U,CH_S,CH_H,CH_BLANK,CH_BLANK,CH_BLANK,digit_char(countdown_sec));
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            end

            S_COMPLETE: begin
                led_out   = 16'hAAAA;
<<<<<<< HEAD
                view_data = 32'hD0AE_FFFF; // approximate DONE
=======
                view_data = pack8(CH_D,CH_O,CH_N,CH_E,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK);
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            end

            S_REFUND: begin
                led_out   = 16'h5555;
<<<<<<< HEAD
                view_data = 32'h0EF0_DFFF; // approximate REFUND
=======
                view_data = pack8(CH_R,CH_E,CH_F,CH_U,CH_BLANK,
                                  digit_char((refund_amount / 10) % 10),
                                  digit_char(refund_amount % 10),
                                  CH_BLANK);
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            end

            S_ERROR: begin
                led_out   = 16'hF00F;
<<<<<<< HEAD
                view_data = {16'hE000, 12'h000, error_code};
=======
                view_data = pack8(CH_E,CH_R,CH_R,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,digit_char(error_code));
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            end

            default: begin
                led_out   = 16'h0000;
<<<<<<< HEAD
                view_data = 32'hFFFFFFFF;
=======
                view_data = pack8(CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK,CH_BLANK);
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            end
        endcase
    end

endmodule
