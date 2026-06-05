`timescale 1ns / 1ps

// ============================================================
// vga_display.v  --  Rich VGA UI for the FPGA vending machine
// EGO1 (xc7a35tcsg324-1), 100 MHz system clock
//
// Standard:  640x480 @ 60 Hz  (pixel clock = 25 MHz = 100 MHz / 4)
//
// The screen is organised as a 40 x 30 character grid (each cell is
// 16 x 16 px = an 8x8 ASCII glyph scaled x2). Three full-screen
// layouts are rendered depending on sys_state:
//
//   MAIN_MENU : mode chooser + R1 switch hint + "PRESS S2"
//   SALE_MODE : product table (live) + shopping cart (live) + guide,
//               plus a yellow/red error banner when an error occurs.
//   ADMIN_MODE: product table (live) + total revenue + admin guide.
//
// The contents (stock, price, on/off, cart, totals, revenue) update in
// real time from the register-file / sales / admin buses. The drink that
// is currently selected (shown on the 7-segment display) is highlighted.
//
// VGA pin mapping (EGO1):
//   vga_r[3:0] -> F5/C6/C5/B7   vga_g[3:0] -> B6/A6/A5/D8
//   vga_b[3:0] -> C7/E6/E5/E7   vga_hs -> D7  vga_vs -> C4 (both active-LOW)
// ============================================================

module vga_display (
    input  wire        clk,      // 100 MHz system clock (for BCD precompute registers)
    input  wire        pclk,     // 25.175 MHz pixel clock from MMCM (for pixel scan + output)
    input  wire        rst_n,
    input  wire [1:0]  sys_state,    // 0=MAIN 1=SALE 2=ADMIN
    input  wire        sw_sel,       // sw[0]: main-menu hint (0=SALE,1=ADMIN)

    // register-file data (shared by both modes)
    // prices are single-digit (1-9) so only 4 bits are used; narrowing the
    // port to [3:0] avoids "unconnected port priceN[7:4]" synthesis warnings.
    input  wire [3:0]  price0, price1, price2, price3,
    input  wire [7:0]  stock0, stock1, stock2, stock3,   // 0-99 (two-digit)
    input  wire [3:0]  enabled_mask,
    input  wire [15:0] total_revenue,

    // sales mode
    input  wire [1:0]  sale_drink_id,
    input  wire [3:0]  sale_state,
    input  wire [3:0]  sale_error,
    input  wire [7:0]  cart0, cart1, cart2, cart3,
    input  wire [11:0] sale_total,
    input  wire [11:0] sale_paid,

    // admin mode
    input  wire [1:0]  admin_drink_id,
    input  wire        admin_show_total,
    input  wire [2:0]  admin_state,

    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs
);

    // ----------------------------------------------------------
    // 640x480 @ 60 Hz timing (pixel clock = 25.175 MHz from MMCM)
    // The hc/vc counters run directly on pclk — one counter increment
    // per pixel, one pixel per pclk cycle. No clock-enable divider needed.
    // ----------------------------------------------------------
    localparam H_ACTIVE=640, H_FP=16, H_SYNC=96, H_BP=48, H_TOTAL=800;
    localparam V_ACTIVE=480, V_FP=10, V_SYNC=2,  V_BP=33, V_TOTAL=525;

    reg [9:0] hc, vc;
    always @(posedge pclk) begin
        if (hc == H_TOTAL-1) begin
            hc <= 10'd0;
            vc <= (vc == V_TOTAL-1) ? 10'd0 : vc + 10'd1;
        end else begin
            hc <= hc + 10'd1;
        end
    end

    wire hs_comb = ~((hc >= H_ACTIVE+H_FP) && (hc < H_ACTIVE+H_FP+H_SYNC));
    wire vs_comb = ~((vc >= V_ACTIVE+V_FP) && (vc < V_ACTIVE+V_FP+V_SYNC));
    wire active  = (hc < H_ACTIVE) && (vc < V_ACTIVE);

    // ----------------------------------------------------------
    // Character grid: 40 cols x 30 rows, 16x16 px cells
    // ----------------------------------------------------------
    wire [5:0] ccol = hc[9:4];      // 0..39
    wire [4:0] crow = vc[8:4];      // 0..29
    wire [2:0] fcol = hc[3:1];      // font column 0..7
    wire [2:0] frow = vc[3:1];      // font row 0..7

    // ----------------------------------------------------------
    // 8x8 ASCII font ROM. Address = {ascii[6:0], frow[2:0]}.
    // Only the glyphs we use are populated; the rest are blank.
    // Bit 7 of each byte = leftmost pixel.
    // ----------------------------------------------------------
    (* rom_style = "distributed" *)   // LUTRAM: async read; BRAM would need sync pipeline
    reg [7:0] font [0:1023];
    integer fi;
    initial begin
        for (fi=0; fi<1024; fi=fi+1) font[fi] = 8'h00;
        // ---- digits 0-9 (ASCII 48-57) ----
        font[48*8+0]=8'h3C; font[48*8+1]=8'h66; font[48*8+2]=8'h6E; font[48*8+3]=8'h76;
        font[48*8+4]=8'h66; font[48*8+5]=8'h66; font[48*8+6]=8'h3C; font[48*8+7]=8'h00; // 0
        font[49*8+0]=8'h18; font[49*8+1]=8'h38; font[49*8+2]=8'h18; font[49*8+3]=8'h18;
        font[49*8+4]=8'h18; font[49*8+5]=8'h18; font[49*8+6]=8'h7E; font[49*8+7]=8'h00; // 1
        font[50*8+0]=8'h3C; font[50*8+1]=8'h66; font[50*8+2]=8'h06; font[50*8+3]=8'h1C;
        font[50*8+4]=8'h30; font[50*8+5]=8'h66; font[50*8+6]=8'h7E; font[50*8+7]=8'h00; // 2
        font[51*8+0]=8'h3C; font[51*8+1]=8'h66; font[51*8+2]=8'h06; font[51*8+3]=8'h1C;
        font[51*8+4]=8'h06; font[51*8+5]=8'h66; font[51*8+6]=8'h3C; font[51*8+7]=8'h00; // 3
        font[52*8+0]=8'h0E; font[52*8+1]=8'h1E; font[52*8+2]=8'h36; font[52*8+3]=8'h66;
        font[52*8+4]=8'h7F; font[52*8+5]=8'h06; font[52*8+6]=8'h06; font[52*8+7]=8'h00; // 4
        font[53*8+0]=8'h7E; font[53*8+1]=8'h60; font[53*8+2]=8'h7C; font[53*8+3]=8'h06;
        font[53*8+4]=8'h06; font[53*8+5]=8'h66; font[53*8+6]=8'h3C; font[53*8+7]=8'h00; // 5
        font[54*8+0]=8'h3C; font[54*8+1]=8'h66; font[54*8+2]=8'h60; font[54*8+3]=8'h7C;
        font[54*8+4]=8'h66; font[54*8+5]=8'h66; font[54*8+6]=8'h3C; font[54*8+7]=8'h00; // 6
        font[55*8+0]=8'h7E; font[55*8+1]=8'h66; font[55*8+2]=8'h0C; font[55*8+3]=8'h18;
        font[55*8+4]=8'h18; font[55*8+5]=8'h18; font[55*8+6]=8'h18; font[55*8+7]=8'h00; // 7
        font[56*8+0]=8'h3C; font[56*8+1]=8'h66; font[56*8+2]=8'h66; font[56*8+3]=8'h3C;
        font[56*8+4]=8'h66; font[56*8+5]=8'h66; font[56*8+6]=8'h3C; font[56*8+7]=8'h00; // 8
        font[57*8+0]=8'h3C; font[57*8+1]=8'h66; font[57*8+2]=8'h66; font[57*8+3]=8'h3E;
        font[57*8+4]=8'h06; font[57*8+5]=8'h66; font[57*8+6]=8'h3C; font[57*8+7]=8'h00; // 9
        // ---- letters A-Z (ASCII 65-90) ----
        font[65*8+0]=8'h18; font[65*8+1]=8'h3C; font[65*8+2]=8'h66; font[65*8+3]=8'h7E;
        font[65*8+4]=8'h66; font[65*8+5]=8'h66; font[65*8+6]=8'h66; font[65*8+7]=8'h00; // A
        font[66*8+0]=8'h7C; font[66*8+1]=8'h66; font[66*8+2]=8'h66; font[66*8+3]=8'h7C;
        font[66*8+4]=8'h66; font[66*8+5]=8'h66; font[66*8+6]=8'h7C; font[66*8+7]=8'h00; // B
        font[67*8+0]=8'h3C; font[67*8+1]=8'h66; font[67*8+2]=8'h60; font[67*8+3]=8'h60;
        font[67*8+4]=8'h60; font[67*8+5]=8'h66; font[67*8+6]=8'h3C; font[67*8+7]=8'h00; // C
        font[68*8+0]=8'h78; font[68*8+1]=8'h6C; font[68*8+2]=8'h66; font[68*8+3]=8'h66;
        font[68*8+4]=8'h66; font[68*8+5]=8'h6C; font[68*8+6]=8'h78; font[68*8+7]=8'h00; // D
        font[69*8+0]=8'h7E; font[69*8+1]=8'h60; font[69*8+2]=8'h60; font[69*8+3]=8'h7C;
        font[69*8+4]=8'h60; font[69*8+5]=8'h60; font[69*8+6]=8'h7E; font[69*8+7]=8'h00; // E
        font[70*8+0]=8'h7E; font[70*8+1]=8'h60; font[70*8+2]=8'h60; font[70*8+3]=8'h7C;
        font[70*8+4]=8'h60; font[70*8+5]=8'h60; font[70*8+6]=8'h60; font[70*8+7]=8'h00; // F
        font[71*8+0]=8'h3C; font[71*8+1]=8'h66; font[71*8+2]=8'h60; font[71*8+3]=8'h6E;
        font[71*8+4]=8'h66; font[71*8+5]=8'h66; font[71*8+6]=8'h3C; font[71*8+7]=8'h00; // G
        font[72*8+0]=8'h66; font[72*8+1]=8'h66; font[72*8+2]=8'h66; font[72*8+3]=8'h7E;
        font[72*8+4]=8'h66; font[72*8+5]=8'h66; font[72*8+6]=8'h66; font[72*8+7]=8'h00; // H
        font[73*8+0]=8'h7E; font[73*8+1]=8'h18; font[73*8+2]=8'h18; font[73*8+3]=8'h18;
        font[73*8+4]=8'h18; font[73*8+5]=8'h18; font[73*8+6]=8'h7E; font[73*8+7]=8'h00; // I
        font[74*8+0]=8'h1E; font[74*8+1]=8'h0C; font[74*8+2]=8'h0C; font[74*8+3]=8'h0C;
        font[74*8+4]=8'h0C; font[74*8+5]=8'h6C; font[74*8+6]=8'h38; font[74*8+7]=8'h00; // J
        font[75*8+0]=8'h66; font[75*8+1]=8'h6C; font[75*8+2]=8'h78; font[75*8+3]=8'h70;
        font[75*8+4]=8'h78; font[75*8+5]=8'h6C; font[75*8+6]=8'h66; font[75*8+7]=8'h00; // K
        font[76*8+0]=8'h60; font[76*8+1]=8'h60; font[76*8+2]=8'h60; font[76*8+3]=8'h60;
        font[76*8+4]=8'h60; font[76*8+5]=8'h60; font[76*8+6]=8'h7E; font[76*8+7]=8'h00; // L
        font[77*8+0]=8'h63; font[77*8+1]=8'h77; font[77*8+2]=8'h7F; font[77*8+3]=8'h6B;
        font[77*8+4]=8'h63; font[77*8+5]=8'h63; font[77*8+6]=8'h63; font[77*8+7]=8'h00; // M
        font[78*8+0]=8'h66; font[78*8+1]=8'h76; font[78*8+2]=8'h7E; font[78*8+3]=8'h7E;
        font[78*8+4]=8'h6E; font[78*8+5]=8'h66; font[78*8+6]=8'h66; font[78*8+7]=8'h00; // N
        font[79*8+0]=8'h3C; font[79*8+1]=8'h66; font[79*8+2]=8'h66; font[79*8+3]=8'h66;
        font[79*8+4]=8'h66; font[79*8+5]=8'h66; font[79*8+6]=8'h3C; font[79*8+7]=8'h00; // O
        font[80*8+0]=8'h7C; font[80*8+1]=8'h66; font[80*8+2]=8'h66; font[80*8+3]=8'h7C;
        font[80*8+4]=8'h60; font[80*8+5]=8'h60; font[80*8+6]=8'h60; font[80*8+7]=8'h00; // P
        font[81*8+0]=8'h3C; font[81*8+1]=8'h66; font[81*8+2]=8'h66; font[81*8+3]=8'h66;
        font[81*8+4]=8'h6E; font[81*8+5]=8'h6C; font[81*8+6]=8'h36; font[81*8+7]=8'h00; // Q
        font[82*8+0]=8'h7C; font[82*8+1]=8'h66; font[82*8+2]=8'h66; font[82*8+3]=8'h7C;
        font[82*8+4]=8'h78; font[82*8+5]=8'h6C; font[82*8+6]=8'h66; font[82*8+7]=8'h00; // R
        font[83*8+0]=8'h3C; font[83*8+1]=8'h66; font[83*8+2]=8'h60; font[83*8+3]=8'h3C;
        font[83*8+4]=8'h06; font[83*8+5]=8'h66; font[83*8+6]=8'h3C; font[83*8+7]=8'h00; // S
        font[84*8+0]=8'h7E; font[84*8+1]=8'h18; font[84*8+2]=8'h18; font[84*8+3]=8'h18;
        font[84*8+4]=8'h18; font[84*8+5]=8'h18; font[84*8+6]=8'h18; font[84*8+7]=8'h00; // T
        font[85*8+0]=8'h66; font[85*8+1]=8'h66; font[85*8+2]=8'h66; font[85*8+3]=8'h66;
        font[85*8+4]=8'h66; font[85*8+5]=8'h66; font[85*8+6]=8'h3C; font[85*8+7]=8'h00; // U
        font[86*8+0]=8'h66; font[86*8+1]=8'h66; font[86*8+2]=8'h66; font[86*8+3]=8'h66;
        font[86*8+4]=8'h66; font[86*8+5]=8'h3C; font[86*8+6]=8'h18; font[86*8+7]=8'h00; // V
        font[87*8+0]=8'h63; font[87*8+1]=8'h63; font[87*8+2]=8'h63; font[87*8+3]=8'h6B;
        font[87*8+4]=8'h7F; font[87*8+5]=8'h77; font[87*8+6]=8'h63; font[87*8+7]=8'h00; // W
        font[88*8+0]=8'h66; font[88*8+1]=8'h66; font[88*8+2]=8'h3C; font[88*8+3]=8'h18;
        font[88*8+4]=8'h3C; font[88*8+5]=8'h66; font[88*8+6]=8'h66; font[88*8+7]=8'h00; // X
        font[89*8+0]=8'h66; font[89*8+1]=8'h66; font[89*8+2]=8'h66; font[89*8+3]=8'h3C;
        font[89*8+4]=8'h18; font[89*8+5]=8'h18; font[89*8+6]=8'h18; font[89*8+7]=8'h00; // Y
        font[90*8+0]=8'h7E; font[90*8+1]=8'h06; font[90*8+2]=8'h0C; font[90*8+3]=8'h18;
        font[90*8+4]=8'h30; font[90*8+5]=8'h60; font[90*8+6]=8'h7E; font[90*8+7]=8'h00; // Z
        // ---- symbols ----
        font[36*8+0]=8'h18; font[36*8+1]=8'h3E; font[36*8+2]=8'h60; font[36*8+3]=8'h3C;
        font[36*8+4]=8'h06; font[36*8+5]=8'h7C; font[36*8+6]=8'h18; font[36*8+7]=8'h00; // $
        font[45*8+0]=8'h00; font[45*8+1]=8'h00; font[45*8+2]=8'h00; font[45*8+3]=8'h7E;
        font[45*8+4]=8'h00; font[45*8+5]=8'h00; font[45*8+6]=8'h00; font[45*8+7]=8'h00; // -
        font[46*8+0]=8'h00; font[46*8+1]=8'h00; font[46*8+2]=8'h00; font[46*8+3]=8'h00;
        font[46*8+4]=8'h00; font[46*8+5]=8'h18; font[46*8+6]=8'h18; font[46*8+7]=8'h00; // .
        font[47*8+0]=8'h02; font[47*8+1]=8'h06; font[47*8+2]=8'h0C; font[47*8+3]=8'h18;
        font[47*8+4]=8'h30; font[47*8+5]=8'h60; font[47*8+6]=8'h40; font[47*8+7]=8'h00; // /
        font[58*8+0]=8'h00; font[58*8+1]=8'h18; font[58*8+2]=8'h18; font[58*8+3]=8'h00;
        font[58*8+4]=8'h18; font[58*8+5]=8'h18; font[58*8+6]=8'h00; font[58*8+7]=8'h00; // :
        font[62*8+0]=8'h60; font[62*8+1]=8'h30; font[62*8+2]=8'h18; font[62*8+3]=8'h0C;
        font[62*8+4]=8'h18; font[62*8+5]=8'h30; font[62*8+6]=8'h60; font[62*8+7]=8'h00; // >
        font[35*8+0]=8'h66; font[35*8+1]=8'hFF; font[35*8+2]=8'h66; font[35*8+3]=8'h66;
        font[35*8+4]=8'h66; font[35*8+5]=8'hFF; font[35*8+6]=8'h66; font[35*8+7]=8'h00; // #
    end

    // ----------------------------------------------------------
    // Helper functions
    // ----------------------------------------------------------
    // char from a string literal s, given total length and 0-based position from left
    function [7:0] sch;
        input [255:0] s;
        input integer  len;
        input integer  pos;
        begin
            sch = s[(len-1-pos)*8 +: 8];
        end
    endfunction

    // ---- Division-free BCD conversion (comparison chains, no / or % operators) ----
    // 8-bit value 0-99  -> {tens[3:0], ones[3:0]}
    function [7:0] bcd2;
        input [7:0] v;
        reg [7:0] r; reg [3:0] t;
        begin
            r=v; t=0;
            if      (r>=8'd90) begin t=9; r=r-8'd90; end
            else if (r>=8'd80) begin t=8; r=r-8'd80; end
            else if (r>=8'd70) begin t=7; r=r-8'd70; end
            else if (r>=8'd60) begin t=6; r=r-8'd60; end
            else if (r>=8'd50) begin t=5; r=r-8'd50; end
            else if (r>=8'd40) begin t=4; r=r-8'd40; end
            else if (r>=8'd30) begin t=3; r=r-8'd30; end
            else if (r>=8'd20) begin t=2; r=r-8'd20; end
            else if (r>=8'd10) begin t=1; r=r-8'd10; end
            bcd2 = {t, r[3:0]};
        end
    endfunction

    // 12-bit value 0-999 -> {hundreds[3:0], tens[3:0], ones[3:0]}
    function [11:0] bcd3;
        input [11:0] v;
        reg [11:0] r; reg [3:0] h, t;
        begin
            r=v; h=0; t=0;
            if      (r>=12'd900) begin h=9; r=r-12'd900; end
            else if (r>=12'd800) begin h=8; r=r-12'd800; end
            else if (r>=12'd700) begin h=7; r=r-12'd700; end
            else if (r>=12'd600) begin h=6; r=r-12'd600; end
            else if (r>=12'd500) begin h=5; r=r-12'd500; end
            else if (r>=12'd400) begin h=4; r=r-12'd400; end
            else if (r>=12'd300) begin h=3; r=r-12'd300; end
            else if (r>=12'd200) begin h=2; r=r-12'd200; end
            else if (r>=12'd100) begin h=1; r=r-12'd100; end
            if      (r>=12'd90)  begin t=9; r=r-12'd90;  end
            else if (r>=12'd80)  begin t=8; r=r-12'd80;  end
            else if (r>=12'd70)  begin t=7; r=r-12'd70;  end
            else if (r>=12'd60)  begin t=6; r=r-12'd60;  end
            else if (r>=12'd50)  begin t=5; r=r-12'd50;  end
            else if (r>=12'd40)  begin t=4; r=r-12'd40;  end
            else if (r>=12'd30)  begin t=3; r=r-12'd30;  end
            else if (r>=12'd20)  begin t=2; r=r-12'd20;  end
            else if (r>=12'd10)  begin t=1; r=r-12'd10;  end
            bcd3 = {h, t, r[3:0]};
        end
    endfunction
    // (revenue 5-digit conversion is done as a 2-stage pipeline below,
    //  not as a single combinational function, to meet timing.)

    // 4-char drink name char (j: 0=left .. 3)
    function [7:0] namech;
        input [1:0] di;
        input [1:0] j;
        reg [31:0] s;
        begin
            case (di)
                2'd0: s = "COLA";
                2'd1: s = "SODA";
                2'd2: s = "TEA ";
                default: s = "H2O ";
            endcase
            namech = s[(3-j)*8 +: 8];
        end
    endfunction

    // ----------------------------------------------------------
    // sales sub-state codes (mirror sales_v3.v)
    // ----------------------------------------------------------
    localparam ST_SELECT=4'd0, ST_CHECK=4'd1, ST_QTY=4'd2, ST_STOCK=4'd3,
               ST_FULL=4'd4, ST_ADDED=4'd5, ST_PAY=4'd6, ST_CHANGE=4'd7,
               ST_WAIT=4'd8, ST_COMMIT=4'd9, ST_DONE=4'd10, ST_REFUND=4'd11,
               ST_ERROR=4'd12;

    // attribute codes for colouring
    localparam A_NORM=3'd0, A_TITLE=3'd1, A_HEAD=3'd2, A_SEL=3'd3,
               A_GUIDE=3'd4, A_ERR=3'd5;

    // need-to-pay (sale)
    wire [11:0] sale_need = (sale_paid >= sale_total) ? 12'd0 : (sale_total - sale_paid);

    // admin authenticated? (S_VIEW=2, S_MODIFY=3, S_SAVE=4). Before the
    // password is accepted (S_IDLE/S_AUTH/S_ALARM/S_FAIL) the product table,
    // revenue and management guide are hidden — only the password prompt shows.
    wire admin_authed = (admin_state >= 3'd2) && (admin_state <= 3'd4);

    // ----------------------------------------------------------
    // Pre-registered BCD digits for numeric displays.
    // Computed once per clock; rendering block reads these regs
    // (simple mux) instead of doing heavy arithmetic combinationally.
    // ----------------------------------------------------------
    // --- pipeline stage A: register raw cart×price products, so the
    //     multiplier and the bcd3 converter sit in separate clock cycles ---
    reg [11:0] m_sum0, m_sum1, m_sum2, m_sum3;   // max 99×9 = 891 -> 12 bits
    always @(posedge clk) begin
        m_sum0 <= cart0 * price0;
        m_sum1 <= cart1 * price1;
        m_sum2 <= cart2 * price2;
        m_sum3 <= cart3 * price3;
    end

    // register sale_need (subtract) before its BCD, to keep that path short
    reg [11:0] m_need;
    always @(posedge clk) m_need <= sale_need;

    // --- pipeline stage B: short BCD conversions (each < 10 ns) ---
    reg [11:0] b_total, b_paid, b_need;            // sale totals, 3-digit BCD {h,t,o}
    reg [11:0] b_sum0, b_sum1, b_sum2, b_sum3;     // cart×price per drink, 3-digit BCD
    reg [ 7:0] b_ct0,  b_ct1,  b_ct2,  b_ct3;     // cart quantities, 2-digit BCD {t,o}
    reg [ 7:0] b_stk0, b_stk1, b_stk2, b_stk3;     // stock 0-99, 2-digit BCD {t,o}
    always @(posedge clk) begin
        b_total <= bcd3(sale_total);
        b_paid  <= bcd3(sale_paid);
        b_need  <= bcd3(m_need);
        b_sum0  <= bcd3(m_sum0);
        b_sum1  <= bcd3(m_sum1);
        b_sum2  <= bcd3(m_sum2);
        b_sum3  <= bcd3(m_sum3);
        b_ct0   <= bcd2(cart0);
        b_ct1   <= bcd2(cart1);
        b_ct2   <= bcd2(cart2);
        b_ct3   <= bcd2(cart3);
        b_stk0  <= bcd2(stock0);
        b_stk1  <= bcd2(stock1);
        b_stk2  <= bcd2(stock2);
        b_stk3  <= bcd2(stock3);
    end

    // --- revenue BCD (5 digits): the serial subtract chain is too long for
    //     one 100 MHz cycle, so split it across two clocked stages.
    //     Stage 1 extracts the top two digits (d4,d3) and registers the
    //     remainder; stage 2 extracts d2,d1,d0. b_rev = {d4,d3,d2,d1,d0}. ---
    reg [19:0] b_rev;
    reg [ 3:0] rv_d4, rv_d3;
    reg [15:0] rv_rem;
    always @(posedge clk) begin : REV_STAGE1
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
    always @(posedge clk) begin : REV_STAGE2
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
        b_rev <= {rv_d4, rv_d3, d2, d1, r[3:0]};
    end

    // ----------------------------------------------------------
    // Content decode: produce ascii char + attribute for (crow,ccol)
    // ----------------------------------------------------------
    reg  [7:0] ch;
    reg  [2:0] cattr;
    reg        err_band;        // this row is the error banner (yellow bg)

    reg [1:0]  di;              // drink index for the current table row
    reg [7:0]  pr;  reg en;  reg [7:0] ct;
    // Pre-registered BCD mux outputs for current drink row (set inside always @(*))
    reg [ 7:0] ct_bcd_r;   // current drink's cart qty BCD
    reg [11:0] sum_bcd_r;  // current drink's cart×price BCD
    reg [ 7:0] stk_bcd_r;  // current drink's stock 2-digit BCD {tens,ones}

    always @(*) begin
        ch       = 8'h20;   // space
        cattr    = A_NORM;
        err_band = 1'b0;
        di       = 2'd0;
        pr=8'd0; en=1'b0; ct=8'd0;
        ct_bcd_r=8'd0; sum_bcd_r=12'd0; stk_bcd_r=8'd0;

        case (sys_state)
        // ==================================================== MAIN MENU
        2'd0: begin
            if (crow==1 && ccol>=9 && ccol<30) begin
                ch = sch("DRINK VENDING MACHINE",21,ccol-9); cattr=A_TITLE;
            end else if (crow==4 && ccol>=15 && ccol<24) begin
                ch = sch("MAIN MENU",9,ccol-15); cattr=A_HEAD;
            end else if (crow==8 && ccol>=10 && ccol<29) begin
                ch = sch("R1 DOWN : SALE MODE",19,ccol-10);
                cattr = (sw_sel==1'b0) ? A_SEL : A_NORM;
            end else if (crow==10 && ccol>=10 && ccol<30) begin
                ch = sch("R1 UP   : ADMIN MODE",20,ccol-10);
                cattr = (sw_sel==1'b1) ? A_SEL : A_NORM;
            end else if (crow==13 && ccol>=10 && ccol<29) begin
                ch = sch("PRESS S2 TO CONFIRM",19,ccol-10); cattr=A_GUIDE;
            end
        end

        // ==================================================== SALE MODE
        2'd1: begin
            // --- per-row drink data (table rows 4..7) ---
            di = crow - 5'd4;
            case (di)
                2'd0: begin pr=price0; stk_bcd_r=b_stk0; en=enabled_mask[0]; ct=cart0;
                            ct_bcd_r=b_ct0;  sum_bcd_r=b_sum0; end
                2'd1: begin pr=price1; stk_bcd_r=b_stk1; en=enabled_mask[1]; ct=cart1;
                            ct_bcd_r=b_ct1;  sum_bcd_r=b_sum1; end
                2'd2: begin pr=price2; stk_bcd_r=b_stk2; en=enabled_mask[2]; ct=cart2;
                            ct_bcd_r=b_ct2;  sum_bcd_r=b_sum2; end
                default: begin pr=price3; stk_bcd_r=b_stk3; en=enabled_mask[3]; ct=cart3;
                            ct_bcd_r=b_ct3;  sum_bcd_r=b_sum3; end
            endcase
            // sumv removed: replaced by pre-registered sum_bcd_r

            // ---------- title ----------
            if (crow==0 && ccol>=15 && ccol<24) begin
                ch = sch("SALE MODE",9,ccol-15); cattr=A_TITLE;
            end
            // ---------- left table header ----------
            else if (crow==2) begin
                cattr=A_HEAD;
                if      (ccol==1)               ch="#";
                else if (ccol>=3 && ccol<7)     ch=sch("NAME",4,ccol-3);
                else if (ccol>=8 && ccol<11)    ch=sch("STK",3,ccol-8);
                else if (ccol>=12 && ccol<14)   ch=sch("PR",2,ccol-12);
                else if (ccol>=15 && ccol<18)   ch=sch("SEL",3,ccol-15);
                // ---------- cart header (right) ----------
                else if (ccol>=22 && ccol<26)   ch=sch("ITEM",4,ccol-22);
                else if (ccol>=28 && ccol<31)   ch=sch("QTY",3,ccol-28);
                else if (ccol>=33 && ccol<36)   ch=sch("SUM",3,ccol-33);
                else cattr=A_NORM;
            end
            // ---------- left product rows ----------
            else if (crow>=4 && crow<=7) begin
                cattr = (di==sale_drink_id) ? A_SEL : A_NORM;
                if (ccol==1)                 ch = 8'h31 + di;            // 1..4
                else if (ccol>=3 && ccol<7)  ch = namech(di, ccol-3);
                else if (ccol>=8 && ccol<10) begin
                    if (!en) ch = "-";                                   // sold out: "--"
                    // two-digit stock from pre-registered BCD {tens,ones}
                    else ch = (ccol==8) ? (8'h30 + {4'd0, stk_bcd_r[7:4]})
                                        : (8'h30 + {4'd0, stk_bcd_r[3:0]});
                end
                else if (ccol==12)           ch = "$";
                else if (ccol==13)           ch = 8'h30 + {4'd0, pr[3:0]};
                else if (ccol>=15 && ccol<18) ch = en ? sch("ON ",3,ccol-15)
                                                       : sch("OFF",3,ccol-15);
                // ---------- right cart rows (only if item in cart) ----------
                else if (ct!=8'd0) begin
                    if (di==sale_drink_id) cattr=A_SEL; else cattr=A_NORM;
                    if (ccol>=22 && ccol<26)      ch = namech(di, ccol-22);
                    // cart qty: use pre-registered ct_bcd_r = {tens[3:0], ones[3:0]}
                    else if (ccol>=28 && ccol<30)
                        ch = (ccol==28) ? (8'h30 + {4'd0, ct_bcd_r[7:4]})
                                        : (8'h30 + {4'd0, ct_bcd_r[3:0]});
                    // cart sum: use pre-registered sum_bcd_r = {h[3:0],t[3:0],o[3:0]}
                    else if (ccol>=33 && ccol<36)
                        ch = (ccol==35) ? (8'h30 + {4'd0, sum_bcd_r[ 3: 0]}) :
                             (ccol==34) ? (8'h30 + {4'd0, sum_bcd_r[ 7: 4]}) :
                                          (8'h30 + {4'd0, sum_bcd_r[11: 8]});
                end
            end
            // ---------- totals (right) ----------
            else if (crow==9) begin
                if (ccol>=22 && ccol<29) begin ch=sch("TOTAL $",7,ccol-22); cattr=A_HEAD; end
                // b_total = {h[11:8], t[7:4], o[3:0]}, ccol 29..31 = h,t,o
                else if (ccol>=29 && ccol<32) begin
                    ch = (ccol==31) ? (8'h30+{4'd0,b_total[ 3: 0]}) :
                         (ccol==30) ? (8'h30+{4'd0,b_total[ 7: 4]}) :
                                      (8'h30+{4'd0,b_total[11: 8]});
                    cattr=A_NORM;
                end
            end
            else if (crow==10) begin
                if (ccol>=22 && ccol<29) begin ch=sch("PAID  $",7,ccol-22); cattr=A_HEAD; end
                else if (ccol>=29 && ccol<32) begin
                    ch = (ccol==31) ? (8'h30+{4'd0,b_paid[ 3: 0]}) :
                         (ccol==30) ? (8'h30+{4'd0,b_paid[ 7: 4]}) :
                                      (8'h30+{4'd0,b_paid[11: 8]});
                    cattr=A_NORM;
                end
            end
            else if (crow==11) begin
                if (ccol>=22 && ccol<29) begin ch=sch("NEED  $",7,ccol-22); cattr=A_HEAD; end
                else if (ccol>=29 && ccol<32) begin
                    ch = (ccol==31) ? (8'h30+{4'd0,b_need[ 3: 0]}) :
                         (ccol==30) ? (8'h30+{4'd0,b_need[ 7: 4]}) :
                                      (8'h30+{4'd0,b_need[11: 8]});
                    cattr=A_NORM;
                end
            end
            // ---------- error banner ----------
            else if (crow==14 && sale_error!=4'd0) begin
                err_band=1'b1; cattr=A_ERR;
                // centered error name
                case (sale_error)
                    4'd1: if (ccol>=16 && ccol<24) ch=sch("SOLD OUT",8,ccol-16);
                    4'd2: if (ccol>=14 && ccol<26) ch=sch("OUT OF STOCK",12,ccol-14);
                    4'd3: if (ccol>=13 && ccol<27) ch=sch("PAY NOT ENOUGH",14,ccol-13);
                    4'd4: if (ccol>=15 && ccol<26) ch=sch("PRICE ERROR",11,ccol-15);
                    4'd5: if (ccol>=16 && ccol<24) ch=sch("TIME OUT",8,ccol-16);
                    default: if (ccol>=14 && ccol<26) ch=sch("INVALID CODE",12,ccol-14);
                endcase
            end
            // ---------- operation guide ----------
            else if (crow==26) begin
                cattr=A_GUIDE;
                case (sale_state)
                    ST_QTY:  if (ccol>=2 && ccol<28) ch=sch("KEY 0-9 QTY  S2 ADD ITEM",24,ccol-2);
                    ST_PAY:  if (ccol>=2 && ccol<29) ch=sch("KEY 0-9 CASH  S2 CONFIRM",24,ccol-2);
                    ST_WAIT: if (ccol>=2 && ccol<26) ch=sch("S2 TAKE DRINK NOW",17,ccol-2);
                    ST_DONE: if (ccol>=2 && ccol<22) ch=sch("S2 CONTINUE SHOP",16,ccol-2);
                    default: if (ccol>=2 && ccol<30) ch=sch("KEY 1-4 OR S1/S4 TO SELECT",26,ccol-2);
                endcase
            end
            else if (crow==27) begin
                cattr=A_GUIDE;
                case (sale_state)
                    ST_QTY:  if (ccol>=2 && ccol<18) ch=sch("S0 BACK TO LIST",15,ccol-2);
                    ST_PAY:  if (ccol>=2 && ccol<22) ch=sch("S0 CANCEL  REFUND",17,ccol-2);
                    ST_WAIT: if (ccol>=2 && ccol<22) ch=sch("S0 REFUND ALL CASH",18,ccol-2);
                    ST_DONE: if (ccol>=2 && ccol<2) ch=8'h20;
                    default: if (ccol>=2 && ccol<33) ch=sch("S2 BUY  S3 PAY  S0 CANCEL CART",30,ccol-2);
                endcase
            end
        end

        // ==================================================== ADMIN MODE
        2'd2: begin
            di = crow - 5'd5;
            case (di)
                2'd0: begin pr=price0; stk_bcd_r=b_stk0; en=enabled_mask[0]; end
                2'd1: begin pr=price1; stk_bcd_r=b_stk1; en=enabled_mask[1]; end
                2'd2: begin pr=price2; stk_bcd_r=b_stk2; en=enabled_mask[2]; end
                default: begin pr=price3; stk_bcd_r=b_stk3; en=enabled_mask[3]; end
            endcase

            // ---------- title ----------
            if (crow==0 && ccol>=14 && ccol<24) begin
                ch = sch("ADMIN MODE",10,ccol-14); cattr=A_TITLE;
            end
            // ---------- subtitle ----------
            else if (crow==1) begin
                cattr=A_HEAD;
                if (admin_state==3'd1) begin
                    if (ccol>=13 && ccol<27) ch=sch("ENTER PASSWORD",14,ccol-13);
                end else if (admin_state==3'd5 || admin_state==3'd6) begin
                    if (ccol>=12 && ccol<28) ch=sch("WRONG PASSWORD !",16,ccol-12);
                end else if (admin_state==3'd3) begin
                    if (ccol>=14 && ccol<25) ch=sch("MODIFY MODE",11,ccol-14);
                end else if (admin_show_total) begin
                    if (ccol>=14 && ccol<26) ch=sch("REVENUE VIEW",12,ccol-14);
                end else begin
                    if (ccol>=15 && ccol<24) ch=sch("VIEW MODE",9,ccol-15);
                end
            end
            // ---------- password-entry hint (only before authentication) ----------
            else if (!admin_authed && crow==4) begin
                cattr=A_GUIDE;
                if (ccol>=6 && ccol<34) ch=sch("KEY 2-DIGIT CODE THEN PRESS S2",30,ccol-6);
            end
            // ===== everything below is shown ONLY after a correct password =====
            // ---------- table header ----------
            else if (admin_authed && crow==3) begin
                cattr=A_HEAD;
                if      (ccol==1)             ch="#";
                else if (ccol>=3 && ccol<7)   ch=sch("NAME",4,ccol-3);
                else if (ccol>=8 && ccol<11)  ch=sch("STK",3,ccol-8);
                else if (ccol>=12 && ccol<14) ch=sch("PR",2,ccol-12);
                else if (ccol>=15 && ccol<18) ch=sch("SEL",3,ccol-15);
                else cattr=A_NORM;
            end
            // ---------- product rows 5..8 ----------
            else if (admin_authed && crow>=5 && crow<=8) begin
                cattr = (di==admin_drink_id && !admin_show_total) ? A_SEL : A_NORM;
                if (ccol==1)                  ch = 8'h31 + di;
                else if (ccol>=3 && ccol<7)   ch = namech(di, ccol-3);
                // two-digit stock from pre-registered BCD {tens,ones}
                else if (ccol>=8 && ccol<10)  ch = (ccol==8) ? (8'h30+{4'd0,stk_bcd_r[7:4]})
                                                             : (8'h30+{4'd0,stk_bcd_r[3:0]});
                else if (ccol==12)            ch = "$";
                else if (ccol==13)            ch = 8'h30 + {4'd0, pr[3:0]};
                else if (ccol>=15 && ccol<18) ch = en ? sch("ON ",3,ccol-15)
                                                       : sch("OFF",3,ccol-15);
            end
            // ---------- total revenue ----------
            else if (admin_authed && crow==10) begin
                if (ccol>=2 && ccol<17) begin
                    ch=sch("TOTAL REVENUE $",15,ccol-2);
                    cattr = admin_show_total ? A_SEL : A_HEAD;
                end else if (ccol>=17 && ccol<22) begin
                    // b_rev = {d4[19:16], d3[15:12], d2[11:8], d1[7:4], d0[3:0]}
                    // ccol 17..21 -> places 4..0
                    case (21-ccol)
                        5'd4: ch = 8'h30+{4'd0,b_rev[19:16]};
                        5'd3: ch = 8'h30+{4'd0,b_rev[15:12]};
                        5'd2: ch = 8'h30+{4'd0,b_rev[11: 8]};
                        5'd1: ch = 8'h30+{4'd0,b_rev[ 7: 4]};
                        default: ch = 8'h30+{4'd0,b_rev[ 3: 0]};
                    endcase
                    cattr = admin_show_total ? A_SEL : A_NORM;
                end
            end
            // ---------- admin guide (authenticated only) ----------
            else if (admin_authed && crow==26) begin
                cattr=A_GUIDE;
                if (ccol>=2 && ccol<30) ch=sch("KEY 1-4 OR S1/S4 TO SELECT",26,ccol-2);
            end
            else if (admin_authed && crow==27) begin
                cattr=A_GUIDE;
                if (ccol>=2 && ccol<32) ch=sch("S0/S3 ATTR  SW2 MODIFY  KEY5",28,ccol-2);
            end
            else if (admin_authed && crow==28) begin
                cattr=A_GUIDE;
                if (ccol>=2 && ccol<29) ch=sch("S2 SAVE/CONFIRM  S6 EXIT",24,ccol-2);
            end
        end
        default: ch = 8'h20;
        endcase
    end

    // ----------------------------------------------------------
    // Pixel pipeline stage 1 (clocked on pclk).
    //
    // The path: (hc,vc) -> content decode -> font ROM -> colour -> output
    // is split into two pclk-clocked stages so each half fits in one
    // pixel period (39.7 ns at 25.175 MHz, very comfortable).
    // All signals (RGB and sync) are delayed by 2 pclk cycles equally,
    // so the relative timing seen by the monitor is identical to
    // a zero-latency design.
    // ----------------------------------------------------------
    reg [6:0] p_ch;             // ASCII < 128, only 7 bits feed the font ROM
    reg [2:0] p_cattr;
    reg       p_errband;
    reg [2:0] p_fcol, p_frow;
    reg       p_active;
    reg [4:0] p_crow;
    reg [1:0] p_sys;
    reg       p_hs, p_vs;
    always @(posedge pclk) begin
        p_ch      <= ch[6:0];
        p_cattr   <= cattr;
        p_errband <= err_band;
        p_fcol    <= fcol;
        p_frow    <= frow;
        p_active  <= active;
        p_crow    <= crow;
        p_sys     <= sys_state;
        p_hs      <= hs_comb;
        p_vs      <= vs_comb;
    end

    // ----------------------------------------------------------
    // Font lookup for the resolved char (uses stage-1 registered signals)
    // ----------------------------------------------------------
    wire [9:0] faddr     = {p_ch, p_frow};
    wire [2:0] col_inv   = 3'd7 - p_fcol;
    wire       font_px   = font[faddr][col_inv];

    // ----------------------------------------------------------
    // Colour resolution
    // ----------------------------------------------------------
    // mode background (dark)
    reg [3:0] bg_r,bg_g,bg_b;
    always @(*) begin
        case (p_sys)
            2'd0:    {bg_r,bg_g,bg_b} = {4'h0,4'h0,4'h2};
            2'd1:    {bg_r,bg_g,bg_b} = {4'h0,4'h1,4'h1};
            2'd2:    {bg_r,bg_g,bg_b} = {4'h1,4'h0,4'h2};
            default: {bg_r,bg_g,bg_b} = {4'h0,4'h0,4'h0};
        endcase
    end

    // title bar (row 0) colour
    reg [3:0] bar_r,bar_g,bar_b;
    always @(*) begin
        case (p_sys)
            2'd0:    {bar_r,bar_g,bar_b} = {4'h0,4'h2,4'hA};
            2'd1:    {bar_r,bar_g,bar_b} = {4'h0,4'h7,4'h5};
            2'd2:    {bar_r,bar_g,bar_b} = {4'h6,4'h0,4'hA};
            default: {bar_r,bar_g,bar_b} = {4'h0,4'h0,4'h0};
        endcase
    end

    // foreground colour by attribute
    reg [3:0] fg_r,fg_g,fg_b;
    always @(*) begin
        case (p_cattr)
            A_TITLE: {fg_r,fg_g,fg_b} = {4'hF,4'hF,4'hF};
            A_HEAD:  {fg_r,fg_g,fg_b} = {4'hF,4'hF,4'h2};
            A_SEL:   {fg_r,fg_g,fg_b} = {4'h0,4'hF,4'h4};
            A_GUIDE: {fg_r,fg_g,fg_b} = {4'h7,4'hD,4'hF};
            A_ERR:   {fg_r,fg_g,fg_b} = {4'hF,4'h0,4'h0};
            default: {fg_r,fg_g,fg_b} = {4'hF,4'hF,4'hF};
        endcase
    end

    // cell background: title bar / error band / selected row / default
    reg [3:0] cell_r,cell_g,cell_b;
    always @(*) begin
        if (p_errband) begin
            cell_r=4'hF; cell_g=4'hF; cell_b=4'h0;       // yellow error band
        end else if (p_crow==5'd0) begin
            cell_r=bar_r; cell_g=bar_g; cell_b=bar_b;     // title bar
        end else if (p_cattr==A_SEL) begin
            cell_r=4'h0; cell_g=4'h3; cell_b=4'h1;        // selected-row highlight
        end else begin
            cell_r=bg_r; cell_g=bg_g; cell_b=bg_b;
        end
    end

    reg [3:0] pr_r,pr_g,pr_b;
    always @(*) begin
        pr_r=4'h0; pr_g=4'h0; pr_b=4'h0;
        if (p_active) begin
            if (font_px) begin
                pr_r=fg_r; pr_g=fg_g; pr_b=fg_b;
            end else begin
                pr_r=cell_r; pr_g=cell_g; pr_b=cell_b;
            end
        end
    end

    // ----------------------------------------------------------
    // Output registers (pclk domain -- one register per pixel)
    // ----------------------------------------------------------
    reg [3:0] q_r,q_g,q_b;
    reg       q_hs,q_vs;
    always @(posedge pclk) begin
        q_r<=pr_r; q_g<=pr_g; q_b<=pr_b; q_hs<=p_hs; q_vs<=p_vs;
    end
    assign vga_r=q_r; assign vga_g=q_g; assign vga_b=q_b;
    assign vga_hs=q_hs; assign vga_vs=q_vs;

endmodule
