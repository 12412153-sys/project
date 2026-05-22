`timescale 1ns / 1ps

// Top-level module for the FPGA vending machine on EGO1 (xc7a35tcsg324-1).
//
// Top-level FSM has three states:
//   MAIN_MENU : display "r1-0S-1A", SW[0]=0->Sale SW[0]=1->Admin, confirm with S2
//   SALE_MODE : delegates to sales_mode.v
//   ADMIN_MODE: delegates to admin_mode.v (with PS/2 password entry)
//
// Button mapping (all modes share physical buttons; logical meaning differs):
//   S2 (BTN[2], R15): confirm / save / dismiss alarm
//   S0 (BTN[0], R11): next-attr (admin) / add-payment (sale)
//   S1 (BTN[1], R17): drink ID dec (admin) / next drink (sale)
//   S3 (BTN[3], V1) : prev-attr / exit-admin (admin) / cancel order (sale)
//   S4 (BTN[4], U4) : drink ID inc (admin) / prev drink (sale)
//
// Switch mapping:
//   SW[0] (R1) : mode select in MAIN_MENU (0=Sale, 1=Admin)
//   SW[1] (N4) : modify enable in ADMIN_MODE
//   SW[7:0]    : amount input in SALE_MODE (PAY state)

module drink_vending_top (
    input  wire       clk,       // 100 MHz, P17
    input  wire       rst_n,     // CPU_RESETN active-low, S6 P15

    // General-purpose buttons (active-high when pressed, require debounce)
    input  wire [4:0] btn,       // [0]=S0/R11 [1]=S1/R17 [2]=S2/R15 [3]=S3/V1 [4]=S4/U4

    // DIP switches
    input  wire [7:0] sw,        // [0]=R1 .. [7]=P5

    // PS/2 keyboard
    input  wire       ps2_clk,   // K5
    input  wire       ps2_data,  // L4

    // 7-segment display
    output wire [7:0] seg0,      // DN0 segment lines (right 4 digits), active-high
    output wire [7:0] seg1,      // DN1 segment lines (left 4 digits),  active-high
    output wire [7:0] an,        // position select, active-high, an[0]=rightmost

    // LEDs (active-high)
    output wire [15:0] led,

    // Audio
    output wire       aud_pwm,   // T1
    output wire       aud_sd     // M6
);

    // ----------------------------------------------------------------
    // System FSM
    // ----------------------------------------------------------------
    localparam MAIN_MENU = 2'd0, SALE_MODE = 2'd1, ADMIN_MODE = 2'd2;
    reg [1:0] sys_state;

    // ----------------------------------------------------------------
    // Button debounce (one instance per button)
    // ----------------------------------------------------------------
    wire [4:0] btn_d;  // debounced 1-cycle pulses

    btn_debounce u_deb0 (.clk(clk), .rst_n(rst_n), .btn_in(btn[0]), .btn_out(btn_d[0]));
    btn_debounce u_deb1 (.clk(clk), .rst_n(rst_n), .btn_in(btn[1]), .btn_out(btn_d[1]));
    btn_debounce u_deb2 (.clk(clk), .rst_n(rst_n), .btn_in(btn[2]), .btn_out(btn_d[2]));
    btn_debounce u_deb3 (.clk(clk), .rst_n(rst_n), .btn_in(btn[3]), .btn_out(btn_d[3]));
    btn_debounce u_deb4 (.clk(clk), .rst_n(rst_n), .btn_in(btn[4]), .btn_out(btn_d[4]));

    // ----------------------------------------------------------------
    // PS/2 keyboard decoder
    // ----------------------------------------------------------------
    wire [3:0] kbd_data;
    wire       kbd_valid;

    ps2_keyboard u_ps2 (
        .clk       (clk),
        .rst_n     (rst_n),
        .ps2_clk   (ps2_clk),
        .ps2_data  (ps2_data),
        .kbd_data  (kbd_data),
        .kbd_valid (kbd_valid)
    );

    // ----------------------------------------------------------------
    // Register file (central storage)
    // ----------------------------------------------------------------
    wire [7:0]  rf_price0, rf_price1, rf_price2, rf_price3;
    wire [3:0]  rf_stock0, rf_stock1, rf_stock2, rf_stock3;
    wire [3:0]  rf_enabled_mask;
    wire [15:0] rf_total_revenue;
    wire [7:0]  rf_password;

    wire        admin_we;
    wire [1:0]  admin_upd_type;
    wire [7:0]  admin_upd_data;
    wire [2:0]  admin_drink_id_raw;  // 3-bit from admin_mode, only [1:0] used

    wire        sale_we;
    wire [1:0]  sale_idx;
    wire [7:0]  sale_amount;

    register_file u_rf (
        .clk            (clk),
        .rst_n          (rst_n),
        .admin_we       (admin_we),
        .admin_upd_type (admin_upd_type),
        .admin_upd_data (admin_upd_data),
        .admin_drink_id (admin_drink_id_raw[1:0]),
        .sale_we        (sale_we),
        .sale_idx       (sale_idx),
        .sale_amount    (sale_amount),
        .price0         (rf_price0),
        .price1         (rf_price1),
        .price2         (rf_price2),
        .price3         (rf_price3),
        .stock0         (rf_stock0),
        .stock1         (rf_stock1),
        .stock2         (rf_stock2),
        .stock3         (rf_stock3),
        .enabled_mask   (rf_enabled_mask),
        .total_revenue  (rf_total_revenue),
        .password       (rf_password)
    );

    // ----------------------------------------------------------------
    // Mux current drink data for admin_mode (indexed by admin_drink_id)
    // ----------------------------------------------------------------
    reg [7:0] admin_cur_stock;
    reg [7:0] admin_cur_price;
    always @(*) begin
        case (admin_drink_id_raw[1:0])
            2'd0: begin admin_cur_stock = {4'h0, rf_stock0}; admin_cur_price = rf_price0; end
            2'd1: begin admin_cur_stock = {4'h0, rf_stock1}; admin_cur_price = rf_price1; end
            2'd2: begin admin_cur_stock = {4'h0, rf_stock2}; admin_cur_price = rf_price2; end
            2'd3: begin admin_cur_stock = {4'h0, rf_stock3}; admin_cur_price = rf_price3; end
            default: begin admin_cur_stock = 8'h00; admin_cur_price = 8'h00; end
        endcase
    end

    // sold_out_mask is the complement of enabled_mask
    wire [3:0] sold_out_mask = ~rf_enabled_mask;

    // ----------------------------------------------------------------
    // admin_mode
    // ----------------------------------------------------------------
    wire        admin_en       = (sys_state == ADMIN_MODE);
    wire [31:0] admin_view_data;
    wire        admin_alarm;
    wire        admin_exit;

    admin_mode u_admin (
        .clk             (clk),
        .rst_n           (rst_n),
        .admin_en        (admin_en),
        .sw_modify       (sw[1]),
        .kbd_data        (kbd_data),
        .kbd_valid       (kbd_valid),
        .btn_confirm     (btn_d[2]),
        .btn_next_attr   (btn_d[0]),
        .btn_prev_attr   (btn_d[3]),
        .btn_id_inc      (btn_d[4]),
        .btn_id_dec      (btn_d[1]),
        .current_stock   (admin_cur_stock),
        .current_price   (admin_cur_price),
        .sold_out_mask   (sold_out_mask),
        .total_revenue   (rf_total_revenue),
        .password_in     (rf_password),
        .view_data       (admin_view_data),
        .write_en        (admin_we),
        .update_type_out (admin_upd_type),
        .update_data     (admin_upd_data),
        .drink_id        (admin_drink_id_raw),
        .alarm_trigger   (admin_alarm),
        .exit_to_main    (admin_exit)
    );

    // ----------------------------------------------------------------
    // sales_mode
    // ----------------------------------------------------------------
    wire       sales_en     = (sys_state == SALE_MODE);
    wire [39:0] sale_view_data;
    wire [15:0] sale_led_out;
    wire        sale_exit;
    wire [1:0]  sale_drink_id_w;  // unused in top but needed by port

    sales_mode u_sale (
        .clk          (clk),
        .rst_n        (rst_n),
        .sales_en     (sales_en),
        .switch_in    (sw),
        .btn_confirm  (btn_d[2]),
        .btn_prev     (btn_d[4]),
        .btn_next     (btn_d[1]),
        .btn_pay      (btn_d[0]),
        .btn_cancel   (btn_d[3]),
        .price0       (rf_price0),
        .price1       (rf_price1),
        .price2       (rf_price2),
        .price3       (rf_price3),
        .stock0       (rf_stock0),
        .stock1       (rf_stock1),
        .stock2       (rf_stock2),
        .stock3       (rf_stock3),
        .enabled_mask (rf_enabled_mask),
        .drink_id     (sale_drink_id_w),
        .sale_we      (sale_we),
        .sale_idx     (sale_idx),
        .sale_amount  (sale_amount),
        .refund_pulse (),
        .refund_amount(),
        .exit_to_main (sale_exit),
        .paid_amount  (),
        .current_price(),
        .current_stock(),
        .led_out      (sale_led_out),
        .view_data    (sale_view_data),
        .state_code   (),
        .error_code   (),
        .countdown_sec()
    );

    // ----------------------------------------------------------------
    // Top-level FSM: MAIN_MENU / SALE_MODE / ADMIN_MODE
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sys_state <= MAIN_MENU;
        end else begin
            case (sys_state)
                MAIN_MENU: begin
                    if (btn_d[2])  // S2: confirm selection
                        sys_state <= sw[0] ? ADMIN_MODE : SALE_MODE;
                end
                SALE_MODE: begin
                    if (sale_exit)  sys_state <= MAIN_MENU;
                end
                ADMIN_MODE: begin
                    if (admin_exit) sys_state <= MAIN_MENU;
                end
                default: sys_state <= MAIN_MENU;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Display data mux
    // Main menu: "r1-0S-1A"  (character IDs per sales_mode encoding)
    //   d7=r(22) d6=1(1) d5=-(24) d4=0(0) d3=S(20) d2=-(24) d1=1(1) d0=A(10)
    // ----------------------------------------------------------------

    // Convert admin's 32-bit nibble display to 40-bit char-ID format for seg7_mux.
    // Nibble 4'hF -> blank (char ID 23); nibble 4'h0-4'hE -> char ID {1'b0, nibble}.
    function [4:0] nib2id;
        input [3:0] n;
        nib2id = (n == 4'hF) ? 5'd23 : {1'b0, n};
    endfunction

    wire [39:0] admin_disp = {
        nib2id(admin_view_data[31:28]),
        nib2id(admin_view_data[27:24]),
        nib2id(admin_view_data[23:20]),
        nib2id(admin_view_data[19:16]),
        nib2id(admin_view_data[15:12]),
        nib2id(admin_view_data[11:8]),
        nib2id(admin_view_data[7:4]),
        nib2id(admin_view_data[3:0])
    };

    localparam [39:0] MENU_DISP =
        {5'd22, 5'd1, 5'd24, 5'd0, 5'd20, 5'd24, 5'd1, 5'd10};
        // r     1     -     0     S     -     1     A

    reg [39:0] disp_data;
    always @(*) begin
        case (sys_state)
            MAIN_MENU:  disp_data = MENU_DISP;
            SALE_MODE:  disp_data = sale_view_data;
            ADMIN_MODE: disp_data = admin_disp;
            default:    disp_data = 40'd0;
        endcase
    end

    // ----------------------------------------------------------------
    // 7-segment display driver
    // ----------------------------------------------------------------
    seg7_mux u_seg (
        .clk       (clk),
        .rst_n     (rst_n),
        .disp_data (disp_data),
        .seg0      (seg0),
        .seg1      (seg1),
        .an        (an)
    );

    // ----------------------------------------------------------------
    // LED mux
    // ----------------------------------------------------------------
    reg [15:0] led_reg;
    always @(*) begin
        case (sys_state)
            MAIN_MENU:  led_reg = sw[0] ? 16'hFF00 : 16'h00FF;  // half bar: left=admin right=sale
            SALE_MODE:  led_reg = sale_led_out;
            ADMIN_MODE: led_reg = admin_alarm ? 16'hAAAA : 16'h0000;
            default:    led_reg = 16'h0000;
        endcase
    end
    assign led = led_reg;

    // ----------------------------------------------------------------
    // Buzzer
    // ----------------------------------------------------------------
    buzzer_driver u_buzz (
        .clk           (clk),
        .rst_n         (rst_n),
        .alarm_trigger (admin_alarm),
        .aud_pwm       (aud_pwm),
        .aud_sd        (aud_sd)
    );

endmodule
