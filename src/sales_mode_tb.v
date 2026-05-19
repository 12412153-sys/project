`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_sales_mode
<<<<<<< HEAD
// Description : Testbench for sales_mode.
//
// Tested scenarios:
// 1. Normal purchase: select -> pay enough -> take within timeout.
// 2. Insufficient payment: confirm before enough money.
// 3. Timeout refund: paid enough but not taken within timeout.
// 4. Invalid ID / off-sale / no-stock exceptions.
=======
// Description : Testbench for the improved 4-item sales_mode.
//
// Tested scenarios:
// 1. Page navigation by previous/next buttons.
// 2. Normal purchase: select -> pay enough -> pickup.
// 3. Insufficient payment.
// 4. Inactivity timeout during payment.
// 5. Pickup timeout refund.
// 6. Off-sale and no-stock exceptions.
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
//////////////////////////////////////////////////////////////////////////////////

module tb_sales_mode();

    reg clk;
    reg rst_n;
    reg sales_en;

    reg [7:0] switch_in;
    reg btn_confirm;
<<<<<<< HEAD
    reg btn_pay;
    reg btn_take;
    reg btn_cancel;

    reg [7:0] stock0, stock1, stock2, stock3;
    reg [7:0] price0, price1, price2, price3;
    reg [3:0] sold_out_mask;

    reg [7:0] current_stock;
    reg [7:0] current_price;

    wire [2:0]  drink_id;
    wire        order_done_pulse;
    wire        refund_pulse;
    wire [7:0]  paid_amount;
    wire [7:0]  sold_price;
    wire [15:0] led_out;
    wire [31:0] view_data;
    wire [3:0]  state_code;
    wire [3:0]  error_code;

    integer fail_count;

    // State encoding copied from sales_mode for checking waveforms.
=======
    reg btn_prev;
    reg btn_next;
    reg btn_pay;
    reg btn_cancel;

    reg [7:0] price0, price1, price2, price3;
    reg [3:0] stock0, stock1, stock2, stock3;
    reg [3:0] enabled_mask;

    wire [1:0]  drink_id;
    wire        sale_we;
    wire [1:0]  sale_idx;
    wire [7:0]  sale_amount;
    wire        refund_pulse;
    wire [7:0]  refund_amount;
    wire        exit_to_main;
    wire [7:0]  paid_amount;
    wire [7:0]  current_price;
    wire [3:0]  current_stock;
    wire [15:0] led_out;
    wire [39:0] view_data;
    wire [3:0]  state_code;
    wire [3:0]  error_code;
    wire [3:0]  countdown_sec;

    integer fail_count;

>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
    localparam S_IDLE      = 4'd0;
    localparam S_SELECT    = 4'd1;
    localparam S_CHECK     = 4'd2;
    localparam S_PAY       = 4'd3;
    localparam S_DISPENSE  = 4'd4;
    localparam S_WAIT_TAKE = 4'd5;
    localparam S_COMPLETE  = 4'd6;
    localparam S_REFUND    = 4'd7;
    localparam S_ERROR     = 4'd8;

<<<<<<< HEAD
    localparam ERR_INVALID_ID = 4'd1;
    localparam ERR_OFF_SALE   = 4'd2;
    localparam ERR_NO_STOCK   = 4'd3;
    localparam ERR_NOT_ENOUGH = 4'd4;

    sales_mode #(
        .TAKE_TIMEOUT_CYCLES(40),
=======
    localparam ERR_OFF_SALE   = 4'd1;
    localparam ERR_NO_STOCK   = 4'd2;
    localparam ERR_NOT_ENOUGH = 4'd3;
    localparam ERR_TIMEOUT    = 4'd5;

    sales_mode #(
        .TAKE_TIMEOUT_CYCLES(50),
        .INACTIVITY_TIMEOUT_CYCLES(40),
        .MESSAGE_TIMEOUT_CYCLES(20),
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
        .LED_STEP_CYCLES(4)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .sales_en(sales_en),
        .switch_in(switch_in),
        .btn_confirm(btn_confirm),
<<<<<<< HEAD
        .btn_pay(btn_pay),
        .btn_take(btn_take),
        .btn_cancel(btn_cancel),
        .current_stock(current_stock),
        .current_price(current_price),
        .sold_out_mask(sold_out_mask),
        .drink_id(drink_id),
        .order_done_pulse(order_done_pulse),
        .refund_pulse(refund_pulse),
        .paid_amount(paid_amount),
        .sold_price(sold_price),
        .led_out(led_out),
        .view_data(view_data),
        .state_code(state_code),
        .error_code(error_code)
=======
        .btn_prev(btn_prev),
        .btn_next(btn_next),
        .btn_pay(btn_pay),
        .btn_cancel(btn_cancel),
        .price0(price0),
        .price1(price1),
        .price2(price2),
        .price3(price3),
        .stock0(stock0),
        .stock1(stock1),
        .stock2(stock2),
        .stock3(stock3),
        .enabled_mask(enabled_mask),
        .drink_id(drink_id),
        .sale_we(sale_we),
        .sale_idx(sale_idx),
        .sale_amount(sale_amount),
        .refund_pulse(refund_pulse),
        .refund_amount(refund_amount),
        .exit_to_main(exit_to_main),
        .paid_amount(paid_amount),
        .current_price(current_price),
        .current_stock(current_stock),
        .led_out(led_out),
        .view_data(view_data),
        .state_code(state_code),
        .error_code(error_code),
        .countdown_sec(countdown_sec)
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
    );

    // 100 MHz clock in simulation: 10 ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

<<<<<<< HEAD
    // Mock register_file: provide current price/stock according to drink_id.
    always @(*) begin
        case (drink_id)
            3'd0: begin current_stock = stock0; current_price = price0; end
            3'd1: begin current_stock = stock1; current_price = price1; end
            3'd2: begin current_stock = stock2; current_price = price2; end
            3'd3: begin current_stock = stock3; current_price = price3; end
            default: begin current_stock = 8'd0; current_price = 8'd0; end
        endcase
    end

    // Mock register_file update: decrease stock only after a completed order.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stock0 <= 8'd10;
            stock1 <= 8'd10;
            stock2 <= 8'd0;   // item 2 starts with no stock for exception test
            stock3 <= 8'd5;
            price0 <= 8'd12;
            price1 <= 8'd15;
            price2 <= 8'd8;
            price3 <= 8'd20;
        end else if (order_done_pulse) begin
            case (drink_id)
                3'd0: stock0 <= stock0 - 1'b1;
                3'd1: stock1 <= stock1 - 1'b1;
                3'd2: stock2 <= stock2 - 1'b1;
                3'd3: stock3 <= stock3 - 1'b1;
=======
    // Mock register_file update.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Demo-friendly prices within 0~10:
            // 0=COLA price 4, 1=SODA price 5, 2=TEA price 3, 3=H2O price 2
            price0 <= 8'd4; stock0 <= 4'd5;
            price1 <= 8'd5; stock1 <= 4'd6;
            price2 <= 8'd3; stock2 <= 4'd8;
            price3 <= 8'd2; stock3 <= 4'd9;
        end else if (sale_we) begin
            case (sale_idx)
                2'd0: stock0 <= stock0 - 1'b1;
                2'd1: stock1 <= stock1 - 1'b1;
                2'd2: stock2 <= stock2 - 1'b1;
                2'd3: stock3 <= stock3 - 1'b1;
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
                default: ;
            endcase
        end
    end

<<<<<<< HEAD
    task press_confirm;
        begin
            @(posedge clk); btn_confirm = 1'b1;
            @(posedge clk); btn_confirm = 1'b0;
        end
    endtask

    task press_pay;
        begin
            @(posedge clk); btn_pay = 1'b1;
            @(posedge clk); btn_pay = 1'b0;
        end
    endtask

    task press_take;
        begin
            @(posedge clk); btn_take = 1'b1;
            @(posedge clk); btn_take = 1'b0;
        end
    endtask

    task press_cancel;
        begin
            @(posedge clk); btn_cancel = 1'b1;
            @(posedge clk); btn_cancel = 1'b0;
        end
    endtask

    task reset_to_select;
        begin
            if (state_code == S_ERROR || state_code == S_COMPLETE || state_code == S_REFUND)
                press_confirm;
            repeat (3) @(posedge clk);
        end
    endtask

    task select_item;
        input [2:0] item_id;
        begin
            switch_in = {5'b00000, item_id};
            press_confirm;
            repeat (3) @(posedge clk); // allow SELECT -> CHECK -> PAY/ERROR
        end
    endtask
=======
    task press_confirm; begin @(posedge clk); btn_confirm = 1; @(posedge clk); btn_confirm = 0; end endtask
    task press_prev;    begin @(posedge clk); btn_prev    = 1; @(posedge clk); btn_prev    = 0; end endtask
    task press_next;    begin @(posedge clk); btn_next    = 1; @(posedge clk); btn_next    = 0; end endtask
    task press_pay;     begin @(posedge clk); btn_pay     = 1; @(posedge clk); btn_pay     = 0; end endtask
    task press_cancel;  begin @(posedge clk); btn_cancel  = 1; @(posedge clk); btn_cancel  = 0; end endtask
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9

    task add_money;
        input [7:0] amount;
        begin
            switch_in = amount;
            press_pay;
            repeat (1) @(posedge clk);
        end
    endtask

<<<<<<< HEAD
    initial begin
        // Initial signals
=======
    task wait_state;
        input [3:0] target_state;
        integer k;
        begin
            for (k = 0; k < 20 && state_code != target_state; k = k + 1)
                @(posedge clk);
        end
    endtask

    task back_to_select;
        begin
            if (state_code == S_ERROR || state_code == S_COMPLETE || state_code == S_REFUND)
                press_confirm;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
        rst_n = 0;
        sales_en = 0;
        switch_in = 8'd0;
        btn_confirm = 0;
<<<<<<< HEAD
        btn_pay = 0;
        btn_take = 0;
        btn_cancel = 0;
        sold_out_mask = 4'b0010; // item 1 is off-sale
=======
        btn_prev = 0;
        btn_next = 0;
        btn_pay = 0;
        btn_cancel = 0;
        enabled_mask = 4'b1111;
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
        fail_count = 0;

        #30;
        rst_n = 1;
        #20;
        sales_en = 1;
<<<<<<< HEAD
        repeat (3) @(posedge clk);

        $display("=== Test 1: normal purchase ===");
        sold_out_mask = 4'b0000;
        select_item(3'd0);
        if (state_code != S_PAY) begin
            $display("FAIL: item 0 should enter PAY state.");
            fail_count = fail_count + 1;
        end
        add_money(8'd5);
        add_money(8'd7);
        press_confirm;          // enough money, go to DISPENSE/WAIT_TAKE
        repeat (3) @(posedge clk);
        if (state_code != S_WAIT_TAKE) begin
            $display("FAIL: paid enough, should wait for taking item.");
            fail_count = fail_count + 1;
        end
        press_take;
        repeat (2) @(posedge clk);
        if (state_code != S_COMPLETE) begin
            $display("FAIL: take pulse should complete order.");
=======
        repeat (5) @(posedge clk);

        $display("=== Test 1: page navigation ===");
        if (state_code != S_SELECT || drink_id != 2'd0) begin
            $display("FAIL: should start at SELECT page of item 0.");
            fail_count = fail_count + 1;
        end
        press_next; repeat (2) @(posedge clk);
        press_next; repeat (2) @(posedge clk);
        press_prev; repeat (2) @(posedge clk);
        if (drink_id != 2'd1) begin
            $display("FAIL: next/prev navigation should land on item 1.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: page navigation works.");
        end

        // Return to item 0 for normal purchase.
        press_prev; repeat (2) @(posedge clk);

        $display("=== Test 2: normal purchase ===");
        press_confirm;
        wait_state(S_PAY);
        add_money(8'd1);
        add_money(8'd3);
        press_confirm;
        wait_state(S_WAIT_TAKE);
        if (state_code != S_WAIT_TAKE) begin
            $display("FAIL: enough payment should enter WAIT_TAKE.");
            fail_count = fail_count + 1;
        end
        press_confirm; // S0 means take item in WAIT_TAKE
        repeat (3) @(posedge clk);
        if (state_code != S_COMPLETE || sale_idx != 2'd0 || sale_amount != 8'd4) begin
            $display("FAIL: pickup should complete sale for item 0 amount 4.");
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: normal purchase completed.");
        end
<<<<<<< HEAD
        reset_to_select;

        $display("=== Test 2: insufficient payment ===");
        select_item(3'd0);
        add_money(8'd5);
        press_confirm;
        repeat (2) @(posedge clk);
        if (state_code != S_PAY || error_code != ERR_NOT_ENOUGH) begin
            $display("FAIL: insufficient payment should stay in PAY with error_code=4.");
=======
        back_to_select;

        $display("=== Test 3: insufficient payment ===");
        press_confirm;
        wait_state(S_PAY);
        add_money(8'd1);
        press_confirm;
        repeat (3) @(posedge clk);
        if (state_code != S_PAY || error_code != ERR_NOT_ENOUGH) begin
            $display("FAIL: insufficient payment should stay in PAY with ERR_NOT_ENOUGH.");
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: insufficient payment detected.");
        end
<<<<<<< HEAD
        add_money(8'd7);
        press_confirm;
        repeat (3) @(posedge clk);
        press_take;
        repeat (2) @(posedge clk);
        reset_to_select;

        $display("=== Test 3: timeout refund ===");
        select_item(3'd3);
        add_money(8'd20);
        press_confirm;
        repeat (60) @(posedge clk); // longer than TAKE_TIMEOUT_CYCLES
        if (state_code != S_REFUND) begin
            $display("FAIL: timeout should enter REFUND state.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: timeout refund triggered.");
        end
        reset_to_select;

        $display("=== Test 4: invalid ID ===");
        select_item(3'd7);
        if (state_code != S_ERROR || error_code != ERR_INVALID_ID) begin
            $display("FAIL: invalid item ID should enter ERROR with error_code=1.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: invalid ID detected.");
        end
        reset_to_select;

        $display("=== Test 5: off-sale item ===");
        sold_out_mask = 4'b0010; // item 1 off-sale
        select_item(3'd1);
        if (state_code != S_ERROR || error_code != ERR_OFF_SALE) begin
            $display("FAIL: off-sale item should enter ERROR with error_code=2.");
=======
        press_cancel;
        wait_state(S_REFUND);
        back_to_select;

        $display("=== Test 4: inactivity timeout in PAY ===");
        press_next; repeat (2) @(posedge clk); // item 1, price 5
        press_confirm;
        wait_state(S_PAY);
        add_money(8'd2);
        repeat (50) @(posedge clk);
        if (state_code != S_REFUND || error_code != ERR_TIMEOUT) begin
            $display("FAIL: inactivity in PAY should refund and show timeout.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: inactivity timeout refund works.");
        end
        back_to_select;

        $display("=== Test 5: pickup timeout refund ===");
        press_next; repeat (2) @(posedge clk); // item 2, price 3
        press_next; repeat (2) @(posedge clk); // item 3, price 2
        press_confirm;
        wait_state(S_PAY);
        add_money(8'd2);
        press_confirm;
        wait_state(S_WAIT_TAKE);
        repeat (70) @(posedge clk);
        if (state_code != S_REFUND || error_code != ERR_TIMEOUT) begin
            $display("FAIL: no pickup within timeout should refund.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: pickup timeout refund works.");
        end
        back_to_select;

        $display("=== Test 6: off-sale item ===");
        // previous test leaves us on item 3, so two NEXT pulses wrap to item 1
        press_next; repeat (2) @(posedge clk); // item 0
        press_next; repeat (2) @(posedge clk); // item 1
        enabled_mask = 4'b1101; // item 1 disabled
        press_confirm;
        wait_state(S_ERROR);
        if (state_code != S_ERROR || error_code != ERR_OFF_SALE) begin
            $display("FAIL: disabled item should enter ERROR with ERR_OFF_SALE.");
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: off-sale item detected.");
        end
<<<<<<< HEAD
        reset_to_select;

        $display("=== Test 6: no stock ===");
        sold_out_mask = 4'b0000;
        select_item(3'd2);
        if (state_code != S_ERROR || error_code != ERR_NO_STOCK) begin
            $display("FAIL: no-stock item should enter ERROR with error_code=3.");
=======
        enabled_mask = 4'b1111;
        back_to_select;

        $display("=== Test 7: no stock ===");
        // select item 2 and set stock to 0
        press_next; repeat (2) @(posedge clk); // item 2
        stock2 = 4'd0;
        press_confirm;
        wait_state(S_ERROR);
        if (state_code != S_ERROR || error_code != ERR_NO_STOCK) begin
            $display("FAIL: no-stock item should enter ERROR with ERR_NO_STOCK.");
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: no-stock item detected.");
        end

        if (fail_count == 0)
<<<<<<< HEAD
            $display("=== ALL SALES_MODE TESTS PASSED ===");
=======
            $display("=== ALL IMPROVED SALES_MODE TESTS PASSED ===");
>>>>>>> cdd0698d0210e4ce6517e3408bdd62a8a88668a9
        else
            $display("=== TEST FINISHED WITH %0d FAILURE(S) ===", fail_count);

        #50;
        $stop;
    end

endmodule
