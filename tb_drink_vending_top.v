`timescale 1ns / 1ps
//==============================================================================
// tb_drink_vending_top.v  –  Top-level testbench for FPGA drink vending machine
//
// Compatible with:  drink_vending_top + sales_v3 + admin_mode + register_file
//
// Groups:
//   1.  Reset & register-file initial values
//   2.  Main-menu LED indication
//   3.  Full shopping-cart purchase (1 COLA + 2 TEA) via keyboard qty+payment
//   4.  Overpayment -> change display -> complete
//   5.  Cancel during payment -> refund
//   6.  Insufficient payment -> add_more display -> exact pay -> complete
//   7.  btn_cancel at ST_SELECT clears cart, stays SALE_MODE; S5 exits to MAIN_MENU
//   8.  Drink navigation (next/prev with wrap-around)
//   9.  S5 soft exit: SALE_MODE -> MAIN_MENU, registers preserved; rst_n resets all
//   10. Admin: correct password -> S_VIEW
//   11. Admin: view-data content & navigation (next_attr / prev_attr / id_inc / id_dec)
//   12. Admin: modify price via keyboard (COLA 4->7)
//   13. Admin: toggle enabled status (COLA off then on)
//   14. Admin: set stock via keyboard (type "9" -> stock=9)
//   15. Admin: prev at first position -> no exit; S5 exits ADMIN_MODE -> MAIN_MENU
//   16. Admin: 3 wrong passwords -> S_ALARM -> dismiss -> stays ADMIN_MODE -> S5 exits
//
// Timing overrides (defparam) keep simulation fast:
//   btn_debounce   CNT_MAX=5, CNT_WIDTH=4
//   sales_v3       TAKE_TIMEOUT=100, IDLE_TIMEOUT=500, MSG_TIMEOUT=50, LED_STEP=10
//==============================================================================

module tb_drink_vending_top;

    // ----------------------------------------------------------------
    // DUT ports
    // ----------------------------------------------------------------
    reg        clk;
    reg  [5:0] btn;
    reg  [7:0] sw;
    reg        ps2_clk_tb;
    reg        ps2_data_tb;

    wire [7:0]  seg0, seg1;
    wire [7:0]  an;
    wire [15:0] led;
    wire        aud_pwm, aud_sd;

    // ----------------------------------------------------------------
    // Clock: 10 ns period (100 MHz)
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Timing parameter overrides
    // ----------------------------------------------------------------
    defparam u_dut.u_deb0.CNT_MAX   = 5;
    defparam u_dut.u_deb0.CNT_WIDTH = 4;
    defparam u_dut.u_deb1.CNT_MAX   = 5;
    defparam u_dut.u_deb1.CNT_WIDTH = 4;
    defparam u_dut.u_deb2.CNT_MAX   = 5;
    defparam u_dut.u_deb2.CNT_WIDTH = 4;
    defparam u_dut.u_deb3.CNT_MAX   = 5;
    defparam u_dut.u_deb3.CNT_WIDTH = 4;
    defparam u_dut.u_deb4.CNT_MAX   = 5;
    defparam u_dut.u_deb4.CNT_WIDTH = 4;
    defparam u_dut.u_deb5.CNT_MAX   = 5;
    defparam u_dut.u_deb5.CNT_WIDTH = 4;

    // sales_v3 timeouts: shorten to tens/hundreds of cycles
    defparam u_dut.u_sale.TAKE_TIMEOUT = 32'd100;
    defparam u_dut.u_sale.IDLE_TIMEOUT = 32'd500;
    defparam u_dut.u_sale.MSG_TIMEOUT  = 32'd50;
    defparam u_dut.u_sale.LED_STEP     = 32'd10;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    drink_vending_top u_dut (
        .clk      (clk),
        .btn      (btn),
        .sw       (sw),
        .ps2_clk  (ps2_clk_tb),
        .ps2_data (ps2_data_tb),
        .seg0     (seg0),
        .seg1     (seg1),
        .an       (an),
        .led      (led),
        .aud_pwm  (aud_pwm),
        .aud_sd   (aud_sd)
    );

    // ----------------------------------------------------------------
    // Test counters
    // ----------------------------------------------------------------
    integer test_num, pass_cnt, fail_cnt;

    // ----------------------------------------------------------------
    // check task
    // ----------------------------------------------------------------
    task check;
        input       cond;
        input [255:0] label;
        begin
            if (cond) begin
                $display("  [PASS] #%0d %s", test_num, label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] #%0d %s  (got=%0h)", test_num, label,
                         cond);
                fail_cnt = fail_cnt + 1;
            end
            test_num = test_num + 1;
        end
    endtask

    // ----------------------------------------------------------------
    // press_btn: assert btn_mask for 10 clocks, then release + settle.
    //   Debounce CNT_MAX=5 fires after ~6 cycles -> single-cycle pulse.
    // ----------------------------------------------------------------
    task press_btn;
        input [5:0] mask;
        begin
            @(posedge clk); #1;
            btn = mask;
            repeat(10) @(posedge clk); #1;
            btn = 6'b000000;
            repeat(8) @(posedge clk);
        end
    endtask

    // ----------------------------------------------------------------
    // do_reset: simulate FPGA reprogram (S5/PROG_B) by force-driving
    //   the internal rst_n wire low for 10 cycles, then releasing.
    //   On real hardware, pressing S5 reconfigures the FPGA (= power-on reset).
    // ----------------------------------------------------------------
    task do_reset;
        begin
            force u_dut.rst_n = 1'b0;
            repeat(10) @(posedge clk);
            release u_dut.rst_n;
            repeat(5)  @(posedge clk);
        end
    endtask

    // ----------------------------------------------------------------
    // send_ps2_byte: drive one PS/2 11-bit frame.
    //   Frame: [0]=start(0), [1..8]=data LSB-first, [9]=odd-parity, [10]=stop(1)
    // ----------------------------------------------------------------
    task send_ps2_byte;
        input [7:0] data;
        integer     i;
        reg         par;
        reg [10:0]  frame;
        begin
            par   = ~(^data);
            frame = {1'b1, par, data, 1'b0};
            for (i = 0; i < 11; i = i + 1) begin
                @(posedge clk); #1;
                ps2_data_tb = frame[i];
                @(posedge clk); #1;
                ps2_clk_tb  = 1'b0;
                repeat(4) @(posedge clk);
                ps2_clk_tb  = 1'b1;
                repeat(4) @(posedge clk);
            end
            ps2_data_tb = 1'b1;
            repeat(8) @(posedge clk);
        end
    endtask

    // ----------------------------------------------------------------
    // kbd_digit: send PS/2 make-code for digit 0-9 (Set 2 scan codes)
    // ----------------------------------------------------------------
    task kbd_digit;
        input [3:0] d;
        reg   [7:0] sc;
        begin
            case (d)
                4'd0: sc = 8'h45;  4'd1: sc = 8'h16;
                4'd2: sc = 8'h1E;  4'd3: sc = 8'h26;
                4'd4: sc = 8'h25;  4'd5: sc = 8'h2E;
                4'd6: sc = 8'h36;  4'd7: sc = 8'h3D;
                4'd8: sc = 8'h3E;  4'd9: sc = 8'h46;
                default: sc = 8'h00;
            endcase
            send_ps2_byte(sc);
        end
    endtask

    // ----------------------------------------------------------------
    // State localparams (mirrors sales_v3)
    // ----------------------------------------------------------------
    localparam [3:0]
        ST_SELECT = 4'd0,  ST_CHECK  = 4'd1,  ST_QTY    = 4'd2,
        ST_STOCK  = 4'd3,  ST_FULL   = 4'd4,  ST_ADDED  = 4'd5,
        ST_PAY    = 4'd6,  ST_CHANGE = 4'd7,  ST_WAIT   = 4'd8,
        ST_COMMIT = 4'd9,  ST_DONE   = 4'd10, ST_REFUND = 4'd11,
        ST_ERROR  = 4'd12;

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        btn         = 6'b000000;
        sw          = 8'h00;
        ps2_clk_tb  = 1'b1;
        ps2_data_tb = 1'b1;
        test_num    = 0;
        pass_cnt    = 0;
        fail_cnt    = 0;

        // ============================================================
        // GROUP 1 – Reset & register-file initial values
        // ============================================================
        $display("\n=== GROUP 1: Reset & initial register values ===");
        do_reset;

        check(u_dut.sys_state         == 2'd0,   "sys_state = MAIN_MENU after reset");
        check(u_dut.u_rf.r_price[0]  == 8'd4,   "price[0] = 4 (COLA)");
        check(u_dut.u_rf.r_price[1]  == 8'd5,   "price[1] = 5 (SODA)");
        check(u_dut.u_rf.r_price[2]  == 8'd3,   "price[2] = 3 (TEA)");
        check(u_dut.u_rf.r_price[3]  == 8'd2,   "price[3] = 2 (H2O)");
        check(u_dut.u_rf.r_stock[0]  == 4'd5,   "stock[0] = 5 (COLA)");
        check(u_dut.u_rf.r_stock[1]  == 4'd6,   "stock[1] = 6 (SODA)");
        check(u_dut.u_rf.r_stock[2]  == 4'd8,   "stock[2] = 8 (TEA)");
        check(u_dut.u_rf.r_stock[3]  == 4'd9,   "stock[3] = 9 (H2O)");
        check(u_dut.u_rf.r_enabled   == 4'hF,   "all drinks enabled");
        check(u_dut.u_rf.r_revenue   == 16'd0,  "revenue = 0");
        check(u_dut.u_rf.r_password  == 8'h42,  "password = 0x42");

        // ============================================================
        // GROUP 2 – Main-menu LED
        // ============================================================
        $display("\n=== GROUP 2: Main-menu LED ===");
        sw = 8'h00; repeat(3) @(posedge clk);
        check(led == 16'h00FF, "SW[0]=0: lower LED byte lit (sale mode)");
        sw = 8'h01; repeat(3) @(posedge clk);
        check(led == 16'hFF00, "SW[0]=1: upper LED byte lit (admin mode)");
        sw = 8'h00;

        // ============================================================
        // GROUP 3 – Full shopping-cart purchase: 1 COLA + 2 TEA
        //   btn_next = S1 = btn[1], btn_confirm = S2 = btn[2]
        //   btn_cancel = S0 = btn[0], btn_pay = S3 = btn[3]
        // ============================================================
        $display("\n=== GROUP 3: Shopping-cart purchase (1 COLA + 2 TEA) ===");
        sw = 8'h00;
        // Enter sale mode (S2 confirm)
        press_btn(6'b000100);
        check(u_dut.sys_state == 2'd1, "Entered SALE_MODE");
        check(u_dut.u_sale.state == ST_SELECT, "Sales at ST_SELECT");
        check(u_dut.u_sale.drink_id == 2'd0, "drink_id = 0 (COLA)");

        // Select COLA: confirm -> ST_CHECK -> ST_QTY
        press_btn(6'b000100);
        repeat(4) @(posedge clk);  // ST_CHECK resolves in one cycle
        check(u_dut.u_sale.state == ST_QTY, "After confirm: in ST_QTY");

        // Type qty "1"
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        check(u_dut.u_sale.qty_input == 8'd1, "qty_input = 1");

        // Confirm -> ST_ADDED (cart0 += 1)
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_ADDED, "Qty confirmed: ST_ADDED");
        check(u_dut.u_sale.cart0 == 8'd1, "cart0 = 1");

        // btn_cancel from ADDED -> back to ST_SELECT
        press_btn(6'b000001);
        check(u_dut.u_sale.state == ST_SELECT, "Back to ST_SELECT");

        // Navigate to TEA: btn_next x2 (S1 = btn[1])
        press_btn(6'b000010);  // drink0 -> drink1
        press_btn(6'b000010);  // drink1 -> drink2 (TEA)
        check(u_dut.u_sale.drink_id == 2'd2, "drink_id = 2 (TEA)");

        // Select TEA -> QTY
        press_btn(6'b000100);
        repeat(4) @(posedge clk);
        check(u_dut.u_sale.state == ST_QTY, "TEA: in ST_QTY");

        // Type qty "2"
        kbd_digit(4'd2); repeat(5) @(posedge clk);
        check(u_dut.u_sale.qty_input == 8'd2, "qty_input = 2");

        // Confirm -> ST_ADDED
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_ADDED, "TEA confirmed: ST_ADDED");
        check(u_dut.u_sale.cart2 == 8'd2, "cart2 = 2");

        // btn_cancel -> ST_SELECT
        press_btn(6'b000001);
        check(u_dut.u_sale.state == ST_SELECT, "Back to SELECT");

        // total = 1*4 + 2*3 = 10; btn_pay (S3=btn[3]) -> ST_PAY
        press_btn(6'b001000);
        check(u_dut.u_sale.state == ST_PAY, "btn_pay -> ST_PAY");

        // Type payment "1","0"
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        kbd_digit(4'd0); repeat(5) @(posedge clk);
        check(u_dut.u_sale.pay_entry == 12'd10, "pay_entry = 10");

        // Confirm: paid == total -> ST_WAIT
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_WAIT, "Exact payment -> ST_WAIT");

        // Confirm pickup -> ST_COMMIT -> ST_DONE (3 sale_we pulses)
        press_btn(6'b000100);
        repeat(20) @(posedge clk);  // wait for all ST_COMMIT iterations
        check(u_dut.u_sale.state == ST_DONE, "ST_COMMIT complete -> ST_DONE");
        check(u_dut.u_rf.r_stock[0] == 4'd4, "COLA stock 5->4 after purchase");
        check(u_dut.u_rf.r_stock[2] == 4'd6, "TEA  stock 8->6 after purchase");
        check(u_dut.u_rf.r_revenue  == 16'd10, "revenue = 10 (4+3+3)");

        // Dismiss done -> ST_SELECT
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_SELECT, "Dismissed DONE -> ST_SELECT");

        // ============================================================
        // GROUP 4 – Overpayment -> change display -> take
        //   Current state: SALE_MODE, drink2=TEA
        // ============================================================
        $display("\n=== GROUP 4: Overpayment -> change ===");
        // Navigate to H2O (drink3, price=2): btn_next from drink2
        press_btn(6'b000010);
        check(u_dut.u_sale.drink_id == 2'd3, "drink_id = 3 (H2O)");

        // Select -> QTY "1" -> confirm -> ADDED
        press_btn(6'b000100);
        repeat(4) @(posedge clk);
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        press_btn(6'b000100);
        check(u_dut.u_sale.cart3 == 8'd1, "cart3 = 1 (H2O)");
        press_btn(6'b000001);  // back to SELECT

        // btn_pay -> ST_PAY; type "5" (overpay by 3)
        press_btn(6'b001000);
        kbd_digit(4'd5); repeat(5) @(posedge clk);
        check(u_dut.u_sale.pay_entry == 12'd5, "pay_entry = 5 (overpay)");

        // Confirm: paid(5) > total(2) -> ST_CHANGE, change=3
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_CHANGE, "Overpay -> ST_CHANGE");
        check(u_dut.u_sale.change_money == 12'd3, "change_money = 3");

        // Auto-advance (MSG_TIMEOUT=50) or confirm -> ST_WAIT
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_WAIT, "After change ACK -> ST_WAIT");

        // Confirm pickup -> commit -> done
        press_btn(6'b000100);
        repeat(10) @(posedge clk);
        check(u_dut.u_sale.state == ST_DONE, "Committed -> ST_DONE");
        check(u_dut.u_rf.r_stock[3] == 4'd8, "H2O stock 9->8");
        check(u_dut.u_rf.r_revenue  == 16'd12, "revenue = 12 (10+2)");

        // Dismiss
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_SELECT, "Back to ST_SELECT");

        // ============================================================
        // GROUP 5 – Cancel in payment -> refund
        //   Navigate to SODA (drink1, price=5)
        // ============================================================
        $display("\n=== GROUP 5: Cancel during payment -> refund ===");
        // From drink3: btn_next wraps to drink0, then btn_next -> drink1
        press_btn(6'b000010);  // 3->0
        press_btn(6'b000010);  // 0->1 (SODA)
        check(u_dut.u_sale.drink_id == 2'd1, "drink_id = 1 (SODA)");

        // Add 1 SODA to cart
        press_btn(6'b000100);
        repeat(4) @(posedge clk);
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        press_btn(6'b000100);
        check(u_dut.u_sale.cart1 == 8'd1, "cart1 = 1 (SODA queued)");
        press_btn(6'b000001);  // back to SELECT

        // btn_pay -> ST_PAY, type partial payment "3"
        press_btn(6'b001000);
        kbd_digit(4'd3); repeat(5) @(posedge clk);

        // btn_cancel -> ST_REFUND
        press_btn(6'b000001);
        check(u_dut.u_sale.state == ST_REFUND, "Cancel in PAY -> ST_REFUND");
        check(u_dut.u_sale.refund_amount == 12'd3, "refund_amount = 3");

        // Dismiss refund -> ST_SELECT (cart cleared)
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_SELECT, "After refund -> ST_SELECT");
        check(u_dut.u_sale.cart1 == 8'd0, "cart1 cleared after refund");
        check(u_dut.u_rf.r_revenue == 16'd12, "revenue unchanged (no commit)");

        // ============================================================
        // GROUP 6 – Insufficient payment -> complement -> complete
        //   COLA, price=4 (unchanged)
        // ============================================================
        $display("\n=== GROUP 6: Insufficient payment -> add more -> complete ===");
        // Navigate to COLA (drink0): from drink1, btn_prev (S4=btn[4])
        press_btn(6'b010000);  // 1->0 (COLA)
        check(u_dut.u_sale.drink_id == 2'd0, "drink_id = 0 (COLA)");

        // Add 1 COLA
        press_btn(6'b000100);
        repeat(4) @(posedge clk);
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        press_btn(6'b000100);
        check(u_dut.u_sale.cart0 == 8'd1, "cart0 = 1");
        press_btn(6'b000001);

        // btn_pay -> ST_PAY; type "2" (need 4)
        press_btn(6'b001000);
        kbd_digit(4'd2); repeat(5) @(posedge clk);

        // Confirm: paid(2) < total(4) -> ERR_LESS
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_PAY, "Still ST_PAY (insufficient)");
        check(u_dut.u_sale.error_code == 4'd3, "error_code = ERR_LESS (3)");
        check(u_dut.u_sale.need_money == 12'd2, "need_money = 2");
        check(u_dut.u_sale.paid_sum   == 12'd2, "paid_sum = 2 accumulated");

        // Type remaining "2" -> total paid = 4
        kbd_digit(4'd2); repeat(5) @(posedge clk);

        // Confirm: exact -> ST_WAIT
        press_btn(6'b000100);
        check(u_dut.u_sale.state == ST_WAIT, "Full payment reached -> ST_WAIT");

        // Take -> commit -> done
        press_btn(6'b000100);
        repeat(10) @(posedge clk);
        check(u_dut.u_sale.state == ST_DONE, "Committed -> ST_DONE");
        check(u_dut.u_rf.r_stock[0] == 4'd3, "COLA stock 4->3");
        check(u_dut.u_rf.r_revenue  == 16'd16, "revenue = 16 (12+4)");

        // Dismiss
        press_btn(6'b000100);

        // ============================================================
        // GROUP 7 – btn_cancel at SELECT clears cart; S5 exits to MAIN_MENU
        // ============================================================
        $display("\n=== GROUP 7: Cancel at SELECT clears cart; S5 soft exit ===");
        // Add 2 COLA to cart (still at COLA, drink0)
        check(u_dut.u_sale.drink_id == 2'd0, "Still at drink0");
        press_btn(6'b000100);
        repeat(4) @(posedge clk);
        kbd_digit(4'd2); repeat(5) @(posedge clk);
        press_btn(6'b000100);
        check(u_dut.u_sale.cart0 == 8'd2, "cart0 = 2 (staged)");
        press_btn(6'b000001);  // back to SELECT
        check(u_dut.u_sale.cart0 == 8'd2, "cart0 still 2 in SELECT");

        // btn_cancel at SELECT -> cart cleared, stays in SELECT
        press_btn(6'b000001);
        check(u_dut.u_sale.cart0 == 8'd0, "cart0 = 0 after cancel at SELECT");
        check(u_dut.u_sale.state == ST_SELECT, "State still ST_SELECT");
        check(u_dut.sys_state    == 2'd1, "sys_state still SALE_MODE (no exit)");

        // S5 soft exit: SALE_MODE -> MAIN_MENU, register data preserved
        press_btn(6'b100000);
        check(u_dut.sys_state        == 2'd0,  "S5 -> MAIN_MENU from SALE_MODE");
        check(u_dut.u_rf.r_revenue   == 16'd16, "revenue preserved (16) after S5 exit");
        check(u_dut.u_rf.r_stock[0]  == 4'd3,  "COLA stock preserved (3) after S5 exit");

        // ============================================================
        // GROUP 8 – Drink navigation (next/prev with wrap)
        //   Re-enter SALE_MODE from MAIN_MENU (SW[0]=0 still)
        // ============================================================
        $display("\n=== GROUP 8: Drink navigation ===");
        sw = 8'h00;
        press_btn(6'b000100);  // S2 -> enter SALE_MODE
        check(u_dut.sys_state == 2'd1, "Re-entered SALE_MODE for nav test");
        check(u_dut.u_sale.drink_id == 2'd0, "Start at drink0");

        press_btn(6'b000010);  // btn_next (S1)
        check(u_dut.u_sale.drink_id == 2'd1, "next -> drink1 (SODA)");
        press_btn(6'b000010);
        check(u_dut.u_sale.drink_id == 2'd2, "next -> drink2 (TEA)");
        press_btn(6'b000010);
        check(u_dut.u_sale.drink_id == 2'd3, "next -> drink3 (H2O)");
        press_btn(6'b000010);
        check(u_dut.u_sale.drink_id == 2'd0, "next wraps to drink0");

        press_btn(6'b010000);  // btn_prev (S4)
        check(u_dut.u_sale.drink_id == 2'd3, "prev wraps to drink3");
        press_btn(6'b010000);
        check(u_dut.u_sale.drink_id == 2'd2, "prev -> drink2");

        // ============================================================
        // GROUP 9 – S5 soft exit: MAIN_MENU, registers preserved
        //           rst_n full reset: MAIN_MENU, registers back to defaults
        // ============================================================
        $display("\n=== GROUP 9: S5 soft exit (preserves data); rst_n full reset ===");
        // Currently in SALE_MODE; S5 -> MAIN_MENU, registers preserved
        press_btn(6'b100000);
        check(u_dut.sys_state         == 2'd0,  "S5 -> MAIN_MENU from SALE_MODE");
        check(u_dut.u_rf.r_revenue    == 16'd16, "revenue still 16 after S5 exit");
        check(u_dut.u_rf.r_stock[0]   == 4'd3,  "COLA stock still 3 after S5 exit");
        check(u_dut.u_rf.r_price[0]   == 8'd4,  "COLA price still 4 after S5 exit");

        // Simulate FPGA reprogram (S5/PROG_B): all registers back to power-on defaults
        do_reset;
        check(u_dut.sys_state         == 2'd0,  "sys_state = MAIN_MENU after reprogram");
        check(u_dut.u_rf.r_stock[0]   == 4'd5,  "COLA stock reset to 5 after reprogram");
        check(u_dut.u_rf.r_revenue    == 16'd0, "revenue reset to 0 after reprogram");
        check(u_dut.u_rf.r_price[0]   == 8'd4,  "COLA price reset to 4 after reprogram");

        // ============================================================
        // GROUP 10 – Admin: correct password -> S_VIEW
        //   Default password = 0x42 ("4" then "2" on keyboard)
        // ============================================================
        $display("\n=== GROUP 10: Admin password auth -> S_VIEW ===");
        sw = 8'h01;  // SW[0]=1 -> admin
        press_btn(6'b000100);  // S2 -> ADMIN_MODE
        check(u_dut.sys_state     == 2'd2, "Entered ADMIN_MODE");
        check(u_dut.u_admin.state == 3'd1, "Admin in S_AUTH");

        kbd_digit(4'd4); repeat(5) @(posedge clk);
        kbd_digit(4'd2); repeat(5) @(posedge clk);
        check(u_dut.u_admin.pwd_buffer == 8'h42, "pwd_buffer = 0x42");

        press_btn(6'b000100);  // confirm
        check(u_dut.u_admin.state == 3'd2, "Correct password -> S_VIEW");

        // ============================================================
        // GROUP 11 – Admin view-data content & navigation
        //   After rst_n: COLA stock=5. At drink0/attr0 (stock).
        //   name_nibbles for COLA = {C,0,D,A} = {4'hC,4'h0,4'hD,4'hA}
        //   view_data = {4'hC,4'h0,4'hD,4'hA, 4'hF,4'hF, tens(5)=0, ones(5)=5}
        // ============================================================
        $display("\n=== GROUP 11: Admin view navigation ===");
        check(u_dut.u_admin.drink_id[1:0] == 2'd0, "drink_id = 0 at entry");
        check(u_dut.u_admin.attr_sel      == 2'd0, "attr_sel = 0 (stock)");

        // COLA view_data[31:28] = 'C' (4'hC), [3:0] = ones digit of stock=5
        check(u_dut.admin_view_data[31:28] == 4'hC, "view d7 = C (COLA initial)");
        check(u_dut.admin_view_data[27:24] == 4'h0, "view d6 = 0 (COLA)");
        check(u_dut.admin_view_data[3:0]   == 4'd5, "view d0 = stock ones = 5");

        // btn_next_attr = S0 = btn[0]
        press_btn(6'b000001);
        check(u_dut.u_admin.attr_sel == 2'd1, "Next attr -> price");
        press_btn(6'b000001);
        check(u_dut.u_admin.attr_sel == 2'd2, "Next attr -> status");
        press_btn(6'b000001);
        check(u_dut.u_admin.drink_id[1:0] == 2'd1, "Carried to drink1 (SODA)");
        check(u_dut.u_admin.attr_sel      == 2'd0, "attr_sel reset to 0");

        // btn_id_inc = S4 = btn[4]; btn_id_dec = S1 = btn[1]
        press_btn(6'b010000);
        check(u_dut.u_admin.drink_id[1:0] == 2'd2, "id_inc -> drink2 (TEA)");
        press_btn(6'b000010);
        check(u_dut.u_admin.drink_id[1:0] == 2'd1, "id_dec -> drink1 (SODA)");

        // Navigate to show_total: from drink1/attr0, advance 9 more times
        // drink1/attr0->1->2, drink2/attr0->1->2, drink3/attr0->1->2, then show_total
        repeat(9) press_btn(6'b000001);
        check(u_dut.u_admin.show_total == 1'b1, "show_total after full sweep");
        // view_data[31:16] = total_revenue = 0 (after rst_n), [15:0] = 0xFFFF
        check(u_dut.admin_view_data[31:16] == 16'd0,    "Revenue display = 0");
        check(u_dut.admin_view_data[15:0]  == 16'hFFFF, "Revenue lower half = blank");

        // btn_prev_attr = S3 = btn[3]; from show_total -> drink3/attr2
        press_btn(6'b001000);
        check(u_dut.u_admin.show_total        == 1'b0, "show_total cleared");
        check(u_dut.u_admin.drink_id[1:0]     == 2'd3, "drink_id=3 after prev from total");
        check(u_dut.u_admin.attr_sel          == 2'd2, "attr_sel=2 after prev from total");

        // ============================================================
        // GROUP 12 – Admin modify price: COLA price 4->7
        // ============================================================
        $display("\n=== GROUP 12: Admin modify price ===");
        // Navigate from drink3/attr2 to drink0/attr1 (price):
        //   id_dec x3 -> drink0, attr stays 2; then btn_prev -> attr1
        press_btn(6'b000010);  // drink3->drink2
        press_btn(6'b000010);  // drink2->drink1
        press_btn(6'b000010);  // drink1->drink0 (attr=2)
        press_btn(6'b001000);  // attr2->attr1 (price)
        check(u_dut.u_admin.drink_id[1:0] == 2'd0, "At drink0");
        check(u_dut.u_admin.attr_sel      == 2'd1, "At price attr");

        // SW[1]=1 to enter S_MODIFY (SW[0]=1 still set)
        sw = 8'h03;
        repeat(5) @(posedge clk);
        check(u_dut.u_admin.state == 3'd3, "Entered S_MODIFY");

        kbd_digit(4'd7); repeat(5) @(posedge clk);
        check(u_dut.u_admin.kbd_buffer[3:0] == 4'd7, "kbd_buffer lower nibble = 7");

        press_btn(6'b000100);  // confirm -> S_SAVE -> S_VIEW
        check(u_dut.u_admin.state   == 3'd2, "Back in S_VIEW after save");
        check(u_dut.u_rf.r_price[0] == 8'd7, "COLA price updated to 7");

        sw = 8'h01;  // disable modify

        // ============================================================
        // GROUP 13 – Admin toggle enabled status
        // ============================================================
        $display("\n=== GROUP 13: Admin toggle enabled ===");
        // Advance to attr2 (status): attr1->attr2
        press_btn(6'b000001);
        check(u_dut.u_admin.attr_sel == 2'd2, "At status attr");

        // Toggle COLA off
        sw = 8'h03;
        repeat(5) @(posedge clk);
        check(u_dut.u_admin.state == 3'd3, "In S_MODIFY for toggle");
        press_btn(6'b000100);  // confirm -> save (toggle off)
        check(u_dut.u_rf.r_enabled[0] == 1'b0, "COLA disabled after toggle");

        // Toggle COLA back on (still SW[1]=1, re-enters S_MODIFY)
        press_btn(6'b000100);  // confirm again -> save (toggle on)
        check(u_dut.u_rf.r_enabled[0] == 1'b1, "COLA re-enabled");
        sw = 8'h01;

        // ============================================================
        // GROUP 14 – Admin set stock: type "9" -> stock=9
        //   admin_upd_type=2'b10: stock = lower nibble of kbd_buffer (capped at 9)
        // ============================================================
        $display("\n=== GROUP 14: Admin set stock ===");
        // Go back to stock attr: status(2)->price(1)->stock(0)
        press_btn(6'b001000);  // attr2->attr1
        press_btn(6'b001000);  // attr1->attr0
        check(u_dut.u_admin.attr_sel == 2'd0, "At stock attr");

        sw = 8'h03;
        repeat(5) @(posedge clk);
        kbd_digit(4'd9); repeat(5) @(posedge clk);
        check(u_dut.u_admin.kbd_buffer[3:0] == 4'd9, "kbd_buffer = 9");

        press_btn(6'b000100);  // confirm -> save
        sw = 8'h01;
        check(u_dut.u_admin.state   == 3'd2, "Back in S_VIEW after stock set");
        check(u_dut.u_rf.r_stock[0] == 4'd9, "COLA stock SET to 9");

        // ============================================================
        // GROUP 15 – Admin: prev at first position -> no exit;
        //            S5 exits ADMIN_MODE -> MAIN_MENU with data preserved
        // ============================================================
        $display("\n=== GROUP 15: Admin prev at first position; S5 soft exit ===");
        check(u_dut.u_admin.drink_id[1:0] == 2'd0, "At drink0/attr0 (first)");
        check(u_dut.u_admin.attr_sel      == 2'd0, "attr_sel = 0");

        // btn_prev at very first item: designed as no-op
        press_btn(6'b001000);
        check(u_dut.u_admin.state == 3'd2, "S_VIEW unchanged (no exit)");
        check(u_dut.sys_state     == 2'd2, "sys_state still ADMIN_MODE");

        // S5 exits ADMIN_MODE -> MAIN_MENU; register data preserved
        press_btn(6'b100000);
        check(u_dut.sys_state        == 2'd0, "S5 -> MAIN_MENU from ADMIN_MODE");
        check(u_dut.u_rf.r_price[0]  == 8'd7, "COLA price still 7 after S5 exit");
        check(u_dut.u_rf.r_stock[0]  == 4'd9, "COLA stock still 9 after S5 exit");

        // ============================================================
        // GROUP 16 – Admin: 3 wrong passwords -> S_ALARM -> dismiss
        //             -> admin returns to S_AUTH -> sys_state stays ADMIN_MODE
        //             -> S5 exits to MAIN_MENU
        // ============================================================
        $display("\n=== GROUP 16: Admin alarm & S5 exit ===");
        // Reset for fresh admin session (registers go back to defaults)
        do_reset;
        check(u_dut.sys_state == 2'd0, "Back to MAIN_MENU after reprogram (do_reset)");

        sw = 8'h01;
        press_btn(6'b000100);  // enter ADMIN_MODE
        check(u_dut.u_admin.state == 3'd1, "Admin in S_AUTH");

        // Wrong attempt 1: "11"
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        press_btn(6'b000100);
        check(u_dut.u_admin.state     == 3'd1, "S_AUTH after 1st wrong pw");
        check(u_dut.u_admin.error_cnt == 2'd1, "error_cnt = 1");

        // Wrong attempt 2: "11"
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        press_btn(6'b000100);
        check(u_dut.u_admin.state     == 3'd1, "S_AUTH after 2nd wrong pw");
        check(u_dut.u_admin.error_cnt == 2'd2, "error_cnt = 2");

        // Wrong attempt 3: error_cnt >= 2 -> S_ALARM
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        kbd_digit(4'd1); repeat(5) @(posedge clk);
        press_btn(6'b000100);
        check(u_dut.u_admin.state        == 3'd5, "S_ALARM after 3 wrong attempts");
        check(u_dut.u_admin.alarm_trigger == 1'b1, "alarm_trigger asserted");
        check(aud_sd                      == 1'b1, "aud_sd = 1 (buzzer enabled)");

        // Dismiss alarm with S2: admin -> S_IDLE -> S_AUTH (admin_en still 1)
        press_btn(6'b000100);
        repeat(5) @(posedge clk);  // S_IDLE -> S_AUTH transition
        check(u_dut.sys_state == 2'd2, "sys_state still ADMIN_MODE after alarm dismiss");
        check(u_dut.u_admin.alarm_trigger == 1'b0, "alarm_trigger deasserted");
        check(u_dut.u_admin.state == 3'd1, "Admin back in S_AUTH after dismiss");

        // S5 exits ADMIN_MODE -> MAIN_MENU (data preserved, no full reset)
        press_btn(6'b100000);
        check(u_dut.sys_state == 2'd0, "S5 exits ADMIN_MODE -> MAIN_MENU");

        // ============================================================
        // Final summary
        // ============================================================
        $display("\n============================================");
        $display("  Total: %0d  Pass: %0d  Fail: %0d",
                 test_num, pass_cnt, fail_cnt);
        $display("============================================");
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TEST(S) FAILED ***", fail_cnt);
        $display("");

        $finish;
    end

    // ----------------------------------------------------------------
    // Watchdog – abort if simulation takes too long
    // ----------------------------------------------------------------
    initial begin
        #50_000_000;   // 50 ms = 5 000 000 cycles at 100 MHz
        $display("[TIMEOUT] Simulation exceeded 50 ms – aborting.");
        $finish;
    end

    // ----------------------------------------------------------------
    // Waveform dump (uncomment for VCD/GTKWave)
    // ----------------------------------------------------------------
    // initial begin
    //     $dumpfile("tb_drink_vending_top.vcd");
    //     $dumpvars(0, tb_drink_vending_top);
    // end

endmodule
