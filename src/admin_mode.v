`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: admin_mode
// Description:
//   Admin-mode controller for the FPGA vending machine: 8-bit password
//   verification, consecutive-error alarm, and data-update command dispatch.
//   Supports 4 drinks: COLA, SODA, TEA, H2O.
//
//   view_data uses the 40-bit char-ID format (8 x 5-bit), identical to
//   seg7_mux / sales_v3: {id7, id6, id5, id4, id3, id2, id1, id0},
//   id7 = leftmost digit.
//   (Old version used 32-bit nibble encoding that could not represent
//    H/L/O/S/t, causing garbled COLA/H2O names -- now fixed.)
//
//   Char-ID encoding: 0-9=digits, 10=A 11=b 12=C 13=d 14=E 15=F
//                     16=H 17=L 18=O 19=P 20=S 21=t 22=r 23=blank
//                     24=- 25=U 26=n 27=I 28=Y
//
// Note: all btn inputs are already debounced and converted to single-cycle
//       rising-edge pulses by the parent module.
//////////////////////////////////////////////////////////////////////////////////

module admin_mode #(
    // Number of clock cycles to display "FAIL" after a single wrong password
    // (5 s at 100 MHz = 500_000_000). Override with a smaller value in simulation.
    parameter [29:0] FAIL_HOLD = 30'd500_000_000
)(
    input clk,
    input rst_n,
    input admin_en,             // asserted by top when SW[0]=1 (admin selected)
    input sw_modify,            // SW[1]=1: enter modify sub-state

    // PS/2 keyboard interface
    input [3:0] kbd_data,       // decoded digit 0-9
    input kbd_valid,            // one-cycle pulse when a digit key is pressed

    // button inputs (debounced, single-cycle pulses)
    input btn_confirm,          // confirm / save / dismiss alarm
    input btn_next_attr,        // step forward through attributes
    input btn_prev_attr,        // step backward through attributes
    input btn_id_inc,           // increment drink ID
    input btn_id_dec,           // decrement drink ID

    // register file data
    input [7:0] current_stock,
    input [7:0] current_price,
    input [3:0] sold_out_mask,  // enabled_mask from top: bit=1 means on-sale
    input [15:0] total_revenue,
    input [7:0] password_in,    // correct password from register file

    // outputs
    output reg [39:0] view_data,    // 8 x 5-bit char-ID packed display word
    output reg write_en,
    output reg [1:0]  update_type_out,
    output reg [7:0]  update_data,
    output reg [2:0]  drink_id,
    output reg alarm_trigger,
    output reg exit_to_main,

    // state exports for VGA display
    output [1:0] attr_sel_out,    // current attribute: 0=stock 1=price 2=status
    output       show_total_out,  // 1: currently showing cumulative revenue
    output [2:0] state_out        // current FSM state
);

    // FSM states
    localparam S_IDLE   = 3'd0;
    localparam S_AUTH   = 3'd1;
    localparam S_VIEW   = 3'd2;
    localparam S_MODIFY = 3'd3;
    localparam S_SAVE   = 3'd4;
    localparam S_ALARM  = 3'd5;
    localparam S_FAIL   = 3'd6;   // single wrong password: show FAIL for FAIL_HOLD cycles, then return to S_AUTH

    // char-ID constants (matching seg7_mux encoding)
    localparam [4:0] C_0=5'd0,  C_1=5'd1,  C_2=5'd2,  C_3=5'd3,  C_4=5'd4;
    localparam [4:0] C_5=5'd5,  C_6=5'd6,  C_7=5'd7,  C_8=5'd8,  C_9=5'd9;
    localparam [4:0] C_A=5'd10, C_b=5'd11, C_C=5'd12, C_d=5'd13, C_E=5'd14;
    localparam [4:0] C_F=5'd15, C_H=5'd16, C_L=5'd17, C_O=5'd18, C_P=5'd19;
    localparam [4:0] C_S=5'd20, C_t=5'd21, C_r=5'd22, C_BLK=5'd23, C_dash=5'd24;
    localparam [4:0] C_U=5'd25, C_n=5'd26, C_I=5'd27, C_Y=5'd28;

    reg [2:0] state, next_state;
    reg [7:0] pwd_buffer;
    reg [7:0] kbd_buffer;
    reg [1:0] error_cnt;
    reg [1:0] attr_sel;         // 0=stock, 1=price, 2=on-sale status
    reg       show_total;       // 1: show cumulative revenue instead of attribute
    reg [29:0] fail_timer;      // hold-time counter for S_FAIL
    wire fail_done = (fail_timer >= FAIL_HOLD - 1'b1);

    // state exports
    assign attr_sel_out   = attr_sel;
    assign show_total_out = show_total;
    assign state_out      = state;

    // decimal digit extraction for 7-segment display.
    // stock/price/kbd are <=8-bit (cheap constant divides, fine on 100 MHz).
    wire [3:0] stock_tens = (current_stock / 10) % 10;
    wire [3:0] stock_ones = current_stock % 10;
    wire [3:0] price_ones = current_price % 10;
    wire [3:0] kbd_tens   = (kbd_buffer / 10) % 10;
    wire [3:0] kbd_ones   = kbd_buffer % 10;

    // Revenue is 16-bit; dividing it into 5 decimal digits combinationally
    // (the old "/10000" etc.) was a long path into view_data. Replace with a
    // division-free comparison chain, pipelined over 2 clocks. total_revenue
    // changes only on a sale, so the 2-cycle latency is invisible.
    reg [3:0] rev_ten_thousands, rev_thousands, rev_hundreds, rev_tens, rev_ones;
    reg [3:0] rv_d4, rv_d3;
    reg [15:0] rv_rem;
    always @(posedge clk) begin : REV_S1   // extract top two digits + remainder
        reg [15:0] r; reg [3:0] d4, d3;
        r = total_revenue; d4 = 0; d3 = 0;
        if      (r>=16'd60000) begin d4=6; r=r-16'd60000; end
        else if (r>=16'd50000) begin d4=5; r=r-16'd50000; end
        else if (r>=16'd40000) begin d4=4; r=r-16'd40000; end
        else if (r>=16'd30000) begin d4=3; r=r-16'd30000; end
        else if (r>=16'd20000) begin d4=2; r=r-16'd20000; end
        else if (r>=16'd10000) begin d4=1; r=r-16'd10000; end
        if      (r>=16'd9000)  begin d3=9; r=r-16'd9000;  end
        else if (r>=16'd8000)  begin d3=8; r=r-16'd8000;  end
        else if (r>=16'd7000)  begin d3=7; r=r-16'd7000;  end
        else if (r>=16'd6000)  begin d3=6; r=r-16'd6000;  end
        else if (r>=16'd5000)  begin d3=5; r=r-16'd5000;  end
        else if (r>=16'd4000)  begin d3=4; r=r-16'd4000;  end
        else if (r>=16'd3000)  begin d3=3; r=r-16'd3000;  end
        else if (r>=16'd2000)  begin d3=2; r=r-16'd2000;  end
        else if (r>=16'd1000)  begin d3=1; r=r-16'd1000;  end
        rv_d4 <= d4; rv_d3 <= d3; rv_rem <= r;
    end
    always @(posedge clk) begin : REV_S2   // extract lower three digits
        reg [15:0] r; reg [3:0] d2, d1;
        r = rv_rem; d2 = 0; d1 = 0;
        if      (r>=16'd900) begin d2=9; r=r-16'd900; end
        else if (r>=16'd800) begin d2=8; r=r-16'd800; end
        else if (r>=16'd700) begin d2=7; r=r-16'd700; end
        else if (r>=16'd600) begin d2=6; r=r-16'd600; end
        else if (r>=16'd500) begin d2=5; r=r-16'd500; end
        else if (r>=16'd400) begin d2=4; r=r-16'd400; end
        else if (r>=16'd300) begin d2=3; r=r-16'd300; end
        else if (r>=16'd200) begin d2=2; r=r-16'd200; end
        else if (r>=16'd100) begin d2=1; r=r-16'd100; end
        if      (r>=16'd90)  begin d1=9; r=r-16'd90;  end
        else if (r>=16'd80)  begin d1=8; r=r-16'd80;  end
        else if (r>=16'd70)  begin d1=7; r=r-16'd70;  end
        else if (r>=16'd60)  begin d1=6; r=r-16'd60;  end
        else if (r>=16'd50)  begin d1=5; r=r-16'd50;  end
        else if (r>=16'd40)  begin d1=4; r=r-16'd40;  end
        else if (r>=16'd30)  begin d1=3; r=r-16'd30;  end
        else if (r>=16'd20)  begin d1=2; r=r-16'd20;  end
        else if (r>=16'd10)  begin d1=1; r=r-16'd10;  end
        rev_ten_thousands <= rv_d4; rev_thousands <= rv_d3;
        rev_hundreds <= d2; rev_tens <= d1; rev_ones <= r[3:0];
    end

    // decimal digit -> char-ID
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

    // pack eight 5-bit char-IDs into one 40-bit word
    function [39:0] pack8;
        input [4:0] d7,d6,d5,d4,d3,d2,d1,d0;
        begin
            pack8 = {d7,d6,d5,d4,d3,d2,d1,d0};
        end
    endfunction

    // resolve 4-character drink name from drink_id
    reg [4:0] name3, name2, name1, name0;
    always @(*) begin
        case (drink_id[1:0])
            2'd0: begin name3=C_C; name2=C_O; name1=C_L; name0=C_A;   end // COLA
            2'd1: begin name3=C_S; name2=C_O; name1=C_d; name0=C_A;   end // SODA
            2'd2: begin name3=C_t; name2=C_E; name1=C_A; name0=C_BLK; end // TEA
            default: begin name3=C_H; name2=C_2; name1=C_O; name0=C_BLK; end // H2O
        endcase
    end

    // drink number (1-4) as char-ID for display
    wire [4:0] drink_num = num(drink_id[1:0] + 1'b1);
    // on-sale flag for current drink (1=on-sale)
    wire enabled_bit = sold_out_mask[drink_id[1:0]];

    // sequential: state register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // combinational: next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (admin_en) next_state = S_AUTH;
            end
            S_AUTH: begin
                if (!admin_en) next_state = S_IDLE;
                else if (btn_confirm) begin
                    if (pwd_buffer == password_in) next_state = S_VIEW; // correct password
                    else if (error_cnt >= 2'd2) next_state = S_ALARM;   // 3rd wrong attempt -> alarm
                    else next_state = S_FAIL;                            // 1st/2nd wrong -> show FAIL 5 s
                end
            end
            S_FAIL: begin
                if (!admin_en) next_state = S_IDLE;
                else if (fail_done) next_state = S_AUTH;  // hold expired; back to password entry
            end
            S_VIEW: begin
                if (!admin_en) next_state = S_IDLE;
                else if (sw_modify && !show_total) next_state = S_MODIFY;
            end
            S_MODIFY: begin
                if (!sw_modify) next_state = S_VIEW;
                else if (btn_confirm) next_state = S_SAVE;
            end
            S_SAVE: begin
                next_state = S_VIEW;
            end
            S_ALARM: begin
                if (btn_confirm) next_state = S_IDLE;
            end
            default: next_state = S_IDLE;
        endcase
    end

    // sequential: keyboard input buffers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwd_buffer <= 8'h0;
            kbd_buffer <= 8'h0;
        end else if (kbd_valid) begin
            // password uses BCD nibble-shift to match 8'h61 format of password_in
            if (state == S_AUTH) pwd_buffer <= {pwd_buffer[3:0], kbd_data};
            // modify value uses true decimal accumulation (not BCD concatenation);
            // e.g. typing "1","2" -> 12 (old BCD approach gave 0x12=18, the +6 bug). Cap at 99.
            else if (state == S_MODIFY)
                kbd_buffer <= (kbd_buffer * 8'd10 + {4'd0, kbd_data} > 8'd99)
                              ? 8'd99
                              : (kbd_buffer * 8'd10 + {4'd0, kbd_data});
        end else if (state == S_IDLE || state == S_SAVE) begin
            kbd_buffer <= 8'h0;
            if (state == S_IDLE) pwd_buffer <= 8'h0;
        end
    end

    // sequential: counters, control signals, display output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drink_id <= 3'd0;
            attr_sel <= 2'd0;
            show_total <= 1'b0;
            error_cnt <= 2'd0;
            alarm_trigger <= 1'b0;
            write_en <= 1'b0;
            exit_to_main <= 1'b0;
            update_type_out <= 2'b00;
            update_data <= 8'h00;
            view_data <= 40'd0;
            fail_timer <= 30'd0;
        end else begin
            write_en <= 1'b0;
            exit_to_main <= 1'b0;
            // S_FAIL hold counter: increment in S_FAIL, reset otherwise
            fail_timer <= (state == S_FAIL) ? (fail_timer + 1'b1) : 30'd0;

            case (state)
                S_IDLE: begin
                    alarm_trigger <= 1'b0;
                    show_total <= 1'b0;
                    attr_sel <= 2'd0;
                    drink_id <= 3'd0;
                    error_cnt <= (next_state == S_AUTH) ? error_cnt : 2'd0;
                end

                S_AUTH: begin
                    // "COdE" + the two BCD digits entered so far
                    view_data <= pack8(C_C, C_O, C_d, C_E, C_BLK, C_BLK,
                                       num(pwd_buffer[7:4]), num(pwd_buffer[3:0]));
                    if (btn_confirm && pwd_buffer != password_in) error_cnt <= error_cnt + 1;
                end

                S_ALARM: begin
                    // "FAIL" alarm (buzzer active until confirmed)
                    view_data <= pack8(C_F, C_A, C_I, C_L, C_BLK, C_BLK, C_BLK, C_BLK);
                    alarm_trigger <= 1'b1;
                    if (btn_confirm) exit_to_main <= 1'b1;
                end

                S_FAIL: begin
                    // single wrong password: show "FAIL" for 5 s, no buzzer
                    view_data <= pack8(C_F, C_A, C_I, C_L, C_BLK, C_BLK, C_BLK, C_BLK);
                    alarm_trigger <= 1'b0;
                end

                S_VIEW: begin
                    // step right (next attribute)
                    if (btn_next_attr) begin
                        if (!show_total) begin
                            if (attr_sel < 2) attr_sel <= attr_sel + 1;
                            else if (drink_id < 3) begin drink_id <= drink_id + 1; attr_sel <= 0; end
                            else show_total <= 1'b1;
                        end
                    end
                    // step left (previous attribute)
                    if (btn_prev_attr) begin
                        if (show_total) begin
                            show_total <= 1'b0;
                            drink_id <= 3;
                            attr_sel <= 2;
                        end
                        else if (drink_id == 3'd0 && attr_sel == 2'd0) begin
                            // at first item / first attribute: do nothing
                        end
                        else if (attr_sel > 0)
                            attr_sel <= attr_sel - 1;
                        else if (drink_id > 0) begin
                            drink_id <= drink_id - 1;
                            attr_sel <= 2;
                        end
                    end
                    // direct drink-ID jump via buttons
                    if (btn_id_inc && !show_total && drink_id < 3) drink_id <= drink_id + 1;
                    if (btn_id_dec && !show_total && drink_id > 0) drink_id <= drink_id - 1;

                    // keyboard quick-jump: 1-4 selects drink, 5 shows revenue
                    if (kbd_valid) begin
                        if (kbd_data >= 4'd1 && kbd_data <= 4'd4) begin
                            drink_id   <= {1'b0, kbd_data[1:0]} - 1'b1;
                            show_total <= 1'b0;
                        end else if (kbd_data == 4'd5) begin
                            show_total <= 1'b1;
                        end
                    end

                    // display output
                    if (show_total)
                        // "t" marker + 5-digit cumulative revenue (right-aligned)
                        view_data <= pack8(C_t, C_BLK, C_BLK,
                                           num(rev_ten_thousands), num(rev_thousands),
                                           num(rev_hundreds), num(rev_tens), num(rev_ones));
                    else begin
                        case (attr_sel)
                            // stock: number + name + 2-digit stock
                            2'd0: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, num(stock_tens), num(stock_ones));
                            // price: number + name + 'P' + price
                            2'd1: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, C_P, num(price_ones));
                            // status: number + name + 1 (on-sale) or 0 (off-sale)
                            2'd2: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                     C_BLK, C_BLK, num({3'b0, enabled_bit}));
                            default: view_data <= pack8(drink_num, name3, name2, name1, name0,
                                                        C_BLK, num(stock_tens), num(stock_ones));
                        endcase
                    end
                end

                S_MODIFY: begin
                    // modify mode: number + name + current decimal input buffer
                    view_data <= pack8(drink_num, name3, name2, name1, name0,
                                       C_BLK, num(kbd_tens), num(kbd_ones));
                    if (btn_confirm) begin
                        update_data <= kbd_buffer;
                        case (attr_sel)
                            2'd0: update_type_out <= 2'b10; // restock
                            2'd1: update_type_out <= 2'b01; // reprice
                            2'd2: update_type_out <= 2'b11; // toggle enabled
                            default: update_type_out <= 2'b00;
                        endcase
                    end
                end

                S_SAVE: begin
                    write_en <= 1'b1;
                end
                default: ;
            endcase
        end
    end

endmodule
