`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_sales_mode
// Description : Testbench for sales_mode.
//
// Tested scenarios:
// 1. Normal purchase: select -> pay enough -> take within timeout.
// 2. Insufficient payment: confirm before enough money.
// 3. Timeout refund: paid enough but not taken within timeout.
// 4. Invalid ID / off-sale / no-stock exceptions.
//////////////////////////////////////////////////////////////////////////////////

module tb_sales_mode();

    reg clk;
    reg rst_n;
    reg sales_en;

    reg [7:0] switch_in;
    reg btn_confirm;
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
    localparam S_IDLE      = 4'd0;
    localparam S_SELECT    = 4'd1;
    localparam S_CHECK     = 4'd2;
    localparam S_PAY       = 4'd3;
    localparam S_DISPENSE  = 4'd4;
    localparam S_WAIT_TAKE = 4'd5;
    localparam S_COMPLETE  = 4'd6;
    localparam S_REFUND    = 4'd7;
    localparam S_ERROR     = 4'd8;

    localparam ERR_INVALID_ID = 4'd1;
    localparam ERR_OFF_SALE   = 4'd2;
    localparam ERR_NO_STOCK   = 4'd3;
    localparam ERR_NOT_ENOUGH = 4'd4;

    sales_mode #(
        .TAKE_TIMEOUT_CYCLES(40),
        .LED_STEP_CYCLES(4)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .sales_en(sales_en),
        .switch_in(switch_in),
        .btn_confirm(btn_confirm),
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
    );

    // 100 MHz clock in simulation: 10 ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

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
                default: ;
            endcase
        end
    end

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

    task add_money;
        input [7:0] amount;
        begin
            switch_in = amount;
            press_pay;
            repeat (1) @(posedge clk);
        end
    endtask

    initial begin
        // Initial signals
        rst_n = 0;
        sales_en = 0;
        switch_in = 8'd0;
        btn_confirm = 0;
        btn_pay = 0;
        btn_take = 0;
        btn_cancel = 0;
        sold_out_mask = 4'b0010; // item 1 is off-sale
        fail_count = 0;

        #30;
        rst_n = 1;
        #20;
        sales_en = 1;
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
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: normal purchase completed.");
        end
        reset_to_select;

        $display("=== Test 2: insufficient payment ===");
        select_item(3'd0);
        add_money(8'd5);
        press_confirm;
        repeat (2) @(posedge clk);
        if (state_code != S_PAY || error_code != ERR_NOT_ENOUGH) begin
            $display("FAIL: insufficient payment should stay in PAY with error_code=4.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: insufficient payment detected.");
        end
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
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: off-sale item detected.");
        end
        reset_to_select;

        $display("=== Test 6: no stock ===");
        sold_out_mask = 4'b0000;
        select_item(3'd2);
        if (state_code != S_ERROR || error_code != ERR_NO_STOCK) begin
            $display("FAIL: no-stock item should enter ERROR with error_code=3.");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: no-stock item detected.");
        end

        if (fail_count == 0)
            $display("=== ALL SALES_MODE TESTS PASSED ===");
        else
            $display("=== TEST FINISHED WITH %0d FAILURE(S) ===", fail_count);

        #50;
        $stop;
    end

endmodule
