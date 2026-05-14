`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: sales_mode
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

            if (!sales_en) begin
                current_state <= S_IDLE;
                paid_amount   <= 8'd0;
                error_code    <= ERR_NONE;
                take_timer    <= 32'd0;
                led_timer     <= 32'd0;
                led_pos       <= 4'd0;
            end else begin
                case (current_state)
                    S_IDLE: begin
                        current_state <= S_SELECT;
                        paid_amount   <= 8'd0;
                        error_code    <= ERR_NONE;
                    end

                    S_SELECT: begin
                        paid_amount <= 8'd0;
                        take_timer  <= 32'd0;
                        led_timer   <= 32'd0;
                        led_pos     <= 4'd0;
                        error_code  <= ERR_NONE;
                        if (btn_confirm) begin
                            drink_id      <= switch_in[2:0];
                            current_state <= S_CHECK;
                        end
                    end

                    S_CHECK: begin
                        if (drink_id > 3'd3) begin
                            error_code    <= ERR_INVALID_ID;
                            current_state <= S_ERROR;
                        end else if (sold_out_mask[drink_id]) begin
                            error_code    <= ERR_OFF_SALE;
                            current_state <= S_ERROR;
                        end else if (current_stock == 8'd0) begin
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
                            refund_pulse  <= (paid_amount != 8'd0);
                            current_state <= S_REFUND;
                        end else if (btn_pay) begin
                            // Saturating addition to avoid overflow.
                            if (paid_amount + switch_in < paid_amount)
                                paid_amount <= 8'hFF;
                            else
                                paid_amount <= paid_amount + switch_in;
                        end else if (btn_confirm) begin
                            if (paid_amount >= current_price) begin
                                sold_price    <= current_price;
                                take_timer    <= 32'd0;
                                led_timer     <= 32'd0;
                                led_pos       <= 4'd0;
                                error_code    <= ERR_NONE;
                                current_state <= S_DISPENSE;
                            end else begin
                                // Stay in payment state and show "not enough money" error.
                                error_code <= ERR_NOT_ENOUGH;
                            end
                        end
                    end

                    S_DISPENSE: begin
                        // One transition state: item is dispensed, then wait for user to take it.
                        take_timer    <= 32'd0;
                        led_timer     <= 32'd0;
                        led_pos       <= 4'd0;
                        current_state <= S_WAIT_TAKE;
                    end

                    S_WAIT_TAKE: begin
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
                            end else begin
                                led_timer <= led_timer + 1'b1;
                            end
                        end
                    end

                    S_COMPLETE: begin
                        // Wait for confirm/cancel to return to selection.
                        if (btn_confirm || btn_cancel) begin
                            paid_amount   <= 8'd0;
                            current_state <= S_SELECT;
                        end
                    end

                    S_REFUND: begin
                        // No revenue is counted in this state.
                        if (btn_confirm || btn_cancel) begin
                            paid_amount   <= 8'd0;
                            current_state <= S_SELECT;
                        end
                    end

                    S_ERROR: begin
                        if (btn_confirm || btn_cancel) begin
                            paid_amount   <= 8'd0;
                            error_code    <= ERR_NONE;
                            current_state <= S_SELECT;
                        end
                    end

                    default: begin
                        current_state <= S_IDLE;
                    end
                endcase
            end
        end
    end

    // LED and seven-segment display data.
    // Nibble values 0-F are intended for a future seven-segment decoder.
    always @(*) begin
        led_out   = 16'h0000;
        view_data = 32'hFFFFFFFF; // F can be treated as blank by the display driver.

        case (current_state)
            S_IDLE: begin
                led_out   = 16'h0000;
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
            end

            S_DISPENSE: begin
                led_out   = 16'hFFFF;
                view_data = 32'hD15F_FFFF; // approximate DISP
            end

            S_WAIT_TAKE: begin
                led_out   = (16'h0001 << led_pos);
                view_data = {16'h0000, take_timer[15:0]}; // debug countdown/timer
            end

            S_COMPLETE: begin
                led_out   = 16'hAAAA;
                view_data = 32'hD0AE_FFFF; // approximate DONE
            end

            S_REFUND: begin
                led_out   = 16'h5555;
                view_data = 32'h0EF0_DFFF; // approximate REFUND
            end

            S_ERROR: begin
                led_out   = 16'hF00F;
                view_data = {16'hE000, 12'h000, error_code};
            end

            default: begin
                led_out   = 16'h0000;
                view_data = 32'hFFFFFFFF;
            end
        endcase
    end

endmodule
