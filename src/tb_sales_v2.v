`timescale 1ns / 1ps

module tb_sales_v2();

    reg clk, rst_n, sales_en;
    reg btn_confirm, btn_prev, btn_next, btn_pay, btn_cancel;
    reg [3:0] kbd_data;
    reg kbd_valid;

    reg [7:0] price0, price1, price2, price3;
    reg [7:0] stock0, stock1, stock2, stock3;
    reg [3:0] enabled_mask;

    wire [1:0] drink_id, sale_idx;
    wire sale_we, refund_pulse, exit_to_main;
    wire [7:0] sale_amount, refund_amount;
    wire [7:0] paid_amount, current_price, current_stock;
    wire [15:0] led_out;
    wire [39:0] view_data;
    wire [3:0] state_code, error_code;

    integer fail_count;

    localparam ST_SELECT = 4'd0;
    localparam ST_PAY    = 4'd2;
    localparam ST_CHANGE = 4'd3;
    localparam ST_WAIT   = 4'd4;
    localparam ST_DONE   = 4'd5;
    localparam ST_REFUND = 4'd6;
    localparam ST_ERROR  = 4'd7;

    localparam ERR_OFF   = 4'd1;
    localparam ERR_EMPTY = 4'd2;
    localparam ERR_LESS  = 4'd3;
    localparam ERR_TIME  = 4'd5;

    sales_v2 #(
        .TAKE_TIMEOUT(50),
        .IDLE_TIMEOUT(40),
        .MSG_TIMEOUT(20),
        .LED_STEP(4)
    ) uut (
        .clk(clk), .rst_n(rst_n), .sales_en(sales_en),
        .btn_confirm(btn_confirm), .btn_prev(btn_prev), .btn_next(btn_next),
        .btn_pay(btn_pay), .btn_cancel(btn_cancel),
        .kbd_data(kbd_data), .kbd_valid(kbd_valid),
        .price0(price0), .price1(price1), .price2(price2), .price3(price3),
        .stock0(stock0), .stock1(stock1), .stock2(stock2), .stock3(stock3),
        .enabled_mask(enabled_mask),
        .drink_id(drink_id), .sale_we(sale_we), .sale_idx(sale_idx), .sale_amount(sale_amount),
        .refund_pulse(refund_pulse), .refund_amount(refund_amount), .exit_to_main(exit_to_main),
        .paid_amount(paid_amount), .current_price(current_price), .current_stock(current_stock),
        .led_out(led_out), .view_data(view_data), .state_code(state_code), .error_code(error_code)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            price0 <= 8'd4;  stock0 <= 8'd25;
            price1 <= 8'd5;  stock1 <= 8'd12;
            price2 <= 8'd3;  stock2 <= 8'd8;
            price3 <= 8'd2;  stock3 <= 8'd30;
        end else if (sale_we) begin
            case (sale_idx)
                2'd0: stock0 <= stock0 - 1'b1;
                2'd1: stock1 <= stock1 - 1'b1;
                2'd2: stock2 <= stock2 - 1'b1;
                2'd3: stock3 <= stock3 - 1'b1;
            endcase
        end
    end

    task press_confirm; begin @(posedge clk); btn_confirm=1; @(posedge clk); btn_confirm=0; end endtask
    task press_prev;    begin @(posedge clk); btn_prev=1;    @(posedge clk); btn_prev=0;    end endtask
    task press_next;    begin @(posedge clk); btn_next=1;    @(posedge clk); btn_next=0;    end endtask
    task press_cancel;  begin @(posedge clk); btn_cancel=1;  @(posedge clk); btn_cancel=0;  end endtask

    task key_digit;
        input [3:0] d;
        begin
            @(posedge clk); kbd_data=d; kbd_valid=1;
            @(posedge clk); kbd_valid=0;
        end
    endtask

    task wait_state;
        input [3:0] s;
        integer i;
        begin
            for (i=0; i<20 && state_code!=s; i=i+1)
                @(posedge clk);
        end
    endtask

    task back_select;
        begin
            if (state_code==ST_DONE || state_code==ST_REFUND || state_code==ST_ERROR)
                press_confirm;
            repeat(3) @(posedge clk);
        end
    endtask

    initial begin
        rst_n=0; sales_en=0;
        btn_confirm=0; btn_prev=0; btn_next=0; btn_pay=0; btn_cancel=0;
        kbd_data=0; kbd_valid=0;
        enabled_mask=4'b1111;
        fail_count=0;

        #30; rst_n=1; #20; sales_en=1;
        repeat(5) @(posedge clk);

        $display("=== Test 1: page change ===");
        press_next; press_next; press_prev;
        repeat(2) @(posedge clk);
        if (drink_id != 2'd1) begin
            $display("FAIL: page change error"); fail_count=fail_count+1;
        end else $display("PASS: page change works");

        press_prev;
        repeat(2) @(posedge clk);

        $display("=== Test 2: exact payment ===");
        press_confirm; wait_state(ST_PAY);
        key_digit(4); press_confirm; wait_state(ST_WAIT);
        press_confirm;
        repeat(3) @(posedge clk);
        if (state_code!=ST_DONE || sale_idx!=2'd0 || sale_amount!=8'd4) begin
            $display("FAIL: exact payment sale error"); fail_count=fail_count+1;
        end else $display("PASS: exact payment works");
        back_select;

        $display("=== Test 3: not enough money ===");
        press_confirm; wait_state(ST_PAY);
        key_digit(1); press_confirm;
        repeat(3) @(posedge clk);
        if (state_code!=ST_PAY || error_code!=ERR_LESS) begin
            $display("FAIL: should stay in PAY and ask for more money"); fail_count=fail_count+1;
        end else $display("PASS: not enough money detected");
        key_digit(3); press_confirm; wait_state(ST_WAIT); press_confirm; back_select;

        $display("=== Test 4: over payment and change ===");
        press_next; repeat(2) @(posedge clk); // item 1, price 5
        press_confirm; wait_state(ST_PAY);
        key_digit(7); press_confirm; wait_state(ST_CHANGE);
        if (state_code!=ST_CHANGE || refund_amount!=8'd2) begin
            $display("FAIL: change should be 2"); fail_count=fail_count+1;
        end else $display("PASS: change refund works");
        press_confirm; wait_state(ST_WAIT); press_confirm; back_select;

        $display("=== Test 5: pickup timeout ===");
        press_next; press_next; repeat(2) @(posedge clk); // item 3, price 2
        press_confirm; wait_state(ST_PAY);
        key_digit(2); press_confirm; wait_state(ST_WAIT);
        repeat(70) @(posedge clk);
        if (state_code!=ST_REFUND || error_code!=ERR_TIME) begin
            $display("FAIL: pickup timeout error"); fail_count=fail_count+1;
        end else $display("PASS: pickup timeout works");
        back_select;

        $display("=== Test 6: off sale ===");
        enabled_mask=4'b1101; // item 1 disabled
        press_next; press_next; repeat(2) @(posedge clk); // from item3 -> item1
        press_confirm; wait_state(ST_ERROR);
        if (state_code!=ST_ERROR || error_code!=ERR_OFF) begin
            $display("FAIL: off-sale error"); fail_count=fail_count+1;
        end else $display("PASS: off-sale detected");
        enabled_mask=4'b1111; back_select;

        $display("=== Test 7: no stock ===");
        stock2=0;
        press_next; repeat(2) @(posedge clk); // item2
        press_confirm; wait_state(ST_ERROR);
        if (state_code!=ST_ERROR || error_code!=ERR_EMPTY) begin
            $display("FAIL: no-stock error"); fail_count=fail_count+1;
        end else $display("PASS: no-stock detected");

        if (fail_count==0)
            $display("=== ALL SALES_V2 TESTS PASSED ===");
        else
            $display("=== TEST FINISHED WITH %0d FAILURE(S) ===", fail_count);

        #50; $stop;
    end

endmodule
