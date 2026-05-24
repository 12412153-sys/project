`timescale 1ns / 1ps

// ============================================================
// vga_display.v  --  VGA output module for the FPGA vending machine
// EGO1 (xc7a35tcsg324-1), 100 MHz system clock
//
// Standard:  640×480 @ 60 Hz  (pixel clock = 25 MHz = 100 MHz ÷ 4)
//
// Visual layout (all y values are VGA scan-line numbers, 0=top):
//   y =   0 ..  59 : header bar  (colour depends on sys_state)
//   y =  60 ..  61 : white separator line  (2 px)
//   y =  62 .. 417 : dark content area
//       y = 208 .. 271 : 8 large characters  (8×8 font, 8× scale → 64×64 px each)
//                        x = 64 .. 575  (512 px total, centred in 640)
//   y = 418 .. 419 : white separator line  (2 px)
//   y = 420 .. 479 : footer bar  (same colour as header)
//
// Foreground (lit font pixels) : white  (R=F G=F B=F)
// Background colour per state  : see bg_r/g/b logic below
//   MAIN_MENU  (2'd0) : dark navy   R=0 G=0 B=5
//   SALE_MODE  (2'd1) : dark teal   R=0 G=3 B=3
//   ADMIN_MODE (2'd2) : dark purple R=4 G=0 B=5
//
// Character-ID encoding (identical to seg7_mux / sales_v3.v):
//   0-9  = digits 0–9
//   10=A  11=b  12=C  13=d  14=E  15=F
//   16=H  17=L  18=n  19=o  20=S  21=t  22=r
//   23=blank  24=-
//
// disp_data[39:0] packing: {id7, id6, id5, id4, id3, id2, id1, id0}
//   id7 = leftmost character on screen (x=64)
//   id0 = rightmost character on screen (x=512)
//
// VGA pin mapping (EGO1):
//   vga_r[3:0] → F5/C6/C5/B7
//   vga_g[3:0] → B6/A6/A5/D8
//   vga_b[3:0] → C7/E6/E5/E7
//   vga_hs     → D7    (active-LOW, negative polarity)
//   vga_vs     → C4    (active-LOW, negative polarity)
// ============================================================

module vga_display (
    input  wire        clk,         // 100 MHz system clock
    input  wire        rst_n,       // synchronous reset, active-low
    input  wire [39:0] disp_data,   // 8 × 5-bit char IDs {id7..id0}
    input  wire [1:0]  sys_state,   // 2'd0=MAIN 2'd1=SALE 2'd2=ADMIN
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hs,      // active-LOW sync
    output wire        vga_vs       // active-LOW sync
);

    // ----------------------------------------------------------
    // VGA 640×480 @ 60 Hz timing (pixel clock = 25 MHz)
    // ----------------------------------------------------------
    localparam H_ACTIVE = 640;
    localparam H_FP     = 16;    // front porch
    localparam H_SYNC   = 96;    // sync pulse
    localparam H_BP     = 48;    // back porch
    localparam H_TOTAL  = 800;   // 640+16+96+48

    localparam V_ACTIVE = 480;
    localparam V_FP     = 10;
    localparam V_SYNC   = 2;
    localparam V_BP     = 33;
    localparam V_TOTAL  = 525;   // 480+10+2+33

    // ----------------------------------------------------------
    // Pixel clock enable: 100 MHz ÷ 4 = 25 MHz
    // ----------------------------------------------------------
    reg [1:0] pclk_cnt;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pclk_cnt <= 2'd0;
        else        pclk_cnt <= pclk_cnt + 2'd1;

    wire pclk_en = (pclk_cnt == 2'd3);   // one pulse every 4 clocks

    // ----------------------------------------------------------
    // Horizontal / vertical counters
    // ----------------------------------------------------------
    reg [9:0] hc;   // 0 .. H_TOTAL-1 = 0..799
    reg [9:0] vc;   // 0 .. V_TOTAL-1 = 0..524

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hc <= 10'd0;
            vc <= 10'd0;
        end else if (pclk_en) begin
            if (hc == H_TOTAL - 1) begin
                hc <= 10'd0;
                vc <= (vc == V_TOTAL - 1) ? 10'd0 : vc + 10'd1;
            end else begin
                hc <= hc + 10'd1;
            end
        end
    end

    // ----------------------------------------------------------
    // Sync signals (active-LOW, combinational from counters)
    // Both HS and VS are registered together with RGB to keep
    // the 1-clock pipeline delay consistent.
    // ----------------------------------------------------------
    wire hs_comb = ~( (hc >= H_ACTIVE + H_FP) &&
                      (hc <  H_ACTIVE + H_FP + H_SYNC) );
    wire vs_comb = ~( (vc >= V_ACTIVE + V_FP) &&
                      (vc <  V_ACTIVE + V_FP + V_SYNC) );

    // Active-area flag
    wire active = (hc < H_ACTIVE) && (vc < V_ACTIVE);

    // ----------------------------------------------------------
    // Font ROM — 256 entries × 8 bits
    // Address format: {char_id[4:0], font_row[2:0]}
    //   → 25 chars × 8 rows = 200 entries used (entries 200-255 = 0)
    // Bit 7 of each byte is the LEFTMOST column of that row.
    // Attribute "distributed" forces LUTRAM (async read, no latency).
    // ----------------------------------------------------------
    (* rom_style = "distributed" *)
    reg [7:0] font_rom [0:255];

    initial begin
        // ----- digit 0 (char_id = 0) -----
        font_rom[8'd0 ]=8'h3C; font_rom[8'd1 ]=8'h66; font_rom[8'd2 ]=8'h6E;
        font_rom[8'd3 ]=8'h76; font_rom[8'd4 ]=8'h66; font_rom[8'd5 ]=8'h66;
        font_rom[8'd6 ]=8'h3C; font_rom[8'd7 ]=8'h00;
        // ----- digit 1 (char_id = 1) -----
        font_rom[8'd8 ]=8'h18; font_rom[8'd9 ]=8'h38; font_rom[8'd10]=8'h18;
        font_rom[8'd11]=8'h18; font_rom[8'd12]=8'h18; font_rom[8'd13]=8'h18;
        font_rom[8'd14]=8'h7E; font_rom[8'd15]=8'h00;
        // ----- digit 2 (char_id = 2) -----
        font_rom[8'd16]=8'h3C; font_rom[8'd17]=8'h66; font_rom[8'd18]=8'h06;
        font_rom[8'd19]=8'h1C; font_rom[8'd20]=8'h30; font_rom[8'd21]=8'h66;
        font_rom[8'd22]=8'h7E; font_rom[8'd23]=8'h00;
        // ----- digit 3 (char_id = 3) -----
        font_rom[8'd24]=8'h3C; font_rom[8'd25]=8'h66; font_rom[8'd26]=8'h06;
        font_rom[8'd27]=8'h1C; font_rom[8'd28]=8'h06; font_rom[8'd29]=8'h66;
        font_rom[8'd30]=8'h3C; font_rom[8'd31]=8'h00;
        // ----- digit 4 (char_id = 4) -----
        font_rom[8'd32]=8'h0E; font_rom[8'd33]=8'h1E; font_rom[8'd34]=8'h36;
        font_rom[8'd35]=8'h66; font_rom[8'd36]=8'h7F; font_rom[8'd37]=8'h06;
        font_rom[8'd38]=8'h06; font_rom[8'd39]=8'h00;
        // ----- digit 5 (char_id = 5) -----
        font_rom[8'd40]=8'h7E; font_rom[8'd41]=8'h60; font_rom[8'd42]=8'h7C;
        font_rom[8'd43]=8'h06; font_rom[8'd44]=8'h06; font_rom[8'd45]=8'h66;
        font_rom[8'd46]=8'h3C; font_rom[8'd47]=8'h00;
        // ----- digit 6 (char_id = 6) -----
        font_rom[8'd48]=8'h3C; font_rom[8'd49]=8'h66; font_rom[8'd50]=8'h60;
        font_rom[8'd51]=8'h7C; font_rom[8'd52]=8'h66; font_rom[8'd53]=8'h66;
        font_rom[8'd54]=8'h3C; font_rom[8'd55]=8'h00;
        // ----- digit 7 (char_id = 7) -----
        font_rom[8'd56]=8'h7E; font_rom[8'd57]=8'h66; font_rom[8'd58]=8'h0C;
        font_rom[8'd59]=8'h18; font_rom[8'd60]=8'h18; font_rom[8'd61]=8'h18;
        font_rom[8'd62]=8'h18; font_rom[8'd63]=8'h00;
        // ----- digit 8 (char_id = 8) -----
        font_rom[8'd64]=8'h3C; font_rom[8'd65]=8'h66; font_rom[8'd66]=8'h66;
        font_rom[8'd67]=8'h3C; font_rom[8'd68]=8'h66; font_rom[8'd69]=8'h66;
        font_rom[8'd70]=8'h3C; font_rom[8'd71]=8'h00;
        // ----- digit 9 (char_id = 9) -----
        font_rom[8'd72]=8'h3C; font_rom[8'd73]=8'h66; font_rom[8'd74]=8'h66;
        font_rom[8'd75]=8'h3E; font_rom[8'd76]=8'h06; font_rom[8'd77]=8'h66;
        font_rom[8'd78]=8'h3C; font_rom[8'd79]=8'h00;
        // ----- A (char_id = 10) -----
        font_rom[8'd80]=8'h18; font_rom[8'd81]=8'h3C; font_rom[8'd82]=8'h66;
        font_rom[8'd83]=8'h7E; font_rom[8'd84]=8'h66; font_rom[8'd85]=8'h66;
        font_rom[8'd86]=8'h66; font_rom[8'd87]=8'h00;
        // ----- b (char_id = 11) -----
        font_rom[8'd88]=8'h60; font_rom[8'd89]=8'h60; font_rom[8'd90]=8'h7C;
        font_rom[8'd91]=8'h66; font_rom[8'd92]=8'h66; font_rom[8'd93]=8'h66;
        font_rom[8'd94]=8'h7C; font_rom[8'd95]=8'h00;
        // ----- C (char_id = 12) -----
        font_rom[8'd96]=8'h3C; font_rom[8'd97]=8'h66; font_rom[8'd98]=8'h60;
        font_rom[8'd99]=8'h60; font_rom[8'd100]=8'h60; font_rom[8'd101]=8'h66;
        font_rom[8'd102]=8'h3C; font_rom[8'd103]=8'h00;
        // ----- d (char_id = 13) -----
        font_rom[8'd104]=8'h06; font_rom[8'd105]=8'h06; font_rom[8'd106]=8'h3E;
        font_rom[8'd107]=8'h66; font_rom[8'd108]=8'h66; font_rom[8'd109]=8'h66;
        font_rom[8'd110]=8'h3E; font_rom[8'd111]=8'h00;
        // ----- E (char_id = 14) -----
        font_rom[8'd112]=8'h7E; font_rom[8'd113]=8'h60; font_rom[8'd114]=8'h60;
        font_rom[8'd115]=8'h7C; font_rom[8'd116]=8'h60; font_rom[8'd117]=8'h60;
        font_rom[8'd118]=8'h7E; font_rom[8'd119]=8'h00;
        // ----- F (char_id = 15) -----
        font_rom[8'd120]=8'h7E; font_rom[8'd121]=8'h60; font_rom[8'd122]=8'h60;
        font_rom[8'd123]=8'h7C; font_rom[8'd124]=8'h60; font_rom[8'd125]=8'h60;
        font_rom[8'd126]=8'h60; font_rom[8'd127]=8'h00;
        // ----- H (char_id = 16) -----
        font_rom[8'd128]=8'h66; font_rom[8'd129]=8'h66; font_rom[8'd130]=8'h66;
        font_rom[8'd131]=8'h7E; font_rom[8'd132]=8'h66; font_rom[8'd133]=8'h66;
        font_rom[8'd134]=8'h66; font_rom[8'd135]=8'h00;
        // ----- L (char_id = 17) -----
        font_rom[8'd136]=8'h60; font_rom[8'd137]=8'h60; font_rom[8'd138]=8'h60;
        font_rom[8'd139]=8'h60; font_rom[8'd140]=8'h60; font_rom[8'd141]=8'h60;
        font_rom[8'd142]=8'h7E; font_rom[8'd143]=8'h00;
        // ----- n (char_id = 18) -----
        font_rom[8'd144]=8'h00; font_rom[8'd145]=8'h00; font_rom[8'd146]=8'h6C;
        font_rom[8'd147]=8'h76; font_rom[8'd148]=8'h66; font_rom[8'd149]=8'h66;
        font_rom[8'd150]=8'h66; font_rom[8'd151]=8'h00;
        // ----- o (char_id = 19) -----
        font_rom[8'd152]=8'h00; font_rom[8'd153]=8'h00; font_rom[8'd154]=8'h3C;
        font_rom[8'd155]=8'h66; font_rom[8'd156]=8'h66; font_rom[8'd157]=8'h66;
        font_rom[8'd158]=8'h3C; font_rom[8'd159]=8'h00;
        // ----- S (char_id = 20) -----
        font_rom[8'd160]=8'h3C; font_rom[8'd161]=8'h66; font_rom[8'd162]=8'h60;
        font_rom[8'd163]=8'h3C; font_rom[8'd164]=8'h06; font_rom[8'd165]=8'h66;
        font_rom[8'd166]=8'h3C; font_rom[8'd167]=8'h00;
        // ----- t (char_id = 21) -----
        font_rom[8'd168]=8'h18; font_rom[8'd169]=8'h18; font_rom[8'd170]=8'h7E;
        font_rom[8'd171]=8'h18; font_rom[8'd172]=8'h18; font_rom[8'd173]=8'h18;
        font_rom[8'd174]=8'h0E; font_rom[8'd175]=8'h00;
        // ----- r (char_id = 22) -----
        font_rom[8'd176]=8'h00; font_rom[8'd177]=8'h00; font_rom[8'd178]=8'h6C;
        font_rom[8'd179]=8'h76; font_rom[8'd180]=8'h60; font_rom[8'd181]=8'h60;
        font_rom[8'd182]=8'h60; font_rom[8'd183]=8'h00;
        // ----- blank (char_id = 23) -----
        font_rom[8'd184]=8'h00; font_rom[8'd185]=8'h00; font_rom[8'd186]=8'h00;
        font_rom[8'd187]=8'h00; font_rom[8'd188]=8'h00; font_rom[8'd189]=8'h00;
        font_rom[8'd190]=8'h00; font_rom[8'd191]=8'h00;
        // ----- minus '-' (char_id = 24) -----
        font_rom[8'd192]=8'h00; font_rom[8'd193]=8'h00; font_rom[8'd194]=8'h00;
        font_rom[8'd195]=8'h7E; font_rom[8'd196]=8'h00; font_rom[8'd197]=8'h00;
        font_rom[8'd198]=8'h00; font_rom[8'd199]=8'h00;
        // entries 200-255 default to 0 (blank)
    end

    // ----------------------------------------------------------
    // Character display region
    //   8 chars × 64 px/char = 512 px wide  →  x = [64, 576)
    //   8×8 font × 8 scale  = 64 px tall    →  y = [208, 272)
    // ----------------------------------------------------------
    localparam [9:0] CX0 = 10'd64;   // char area left edge
    localparam [9:0] CX1 = 10'd576;  // char area right edge (exclusive)
    localparam [9:0] CY0 = 10'd208;  // char area top edge
    localparam [9:0] CY1 = 10'd272;  // char area bottom edge (exclusive)

    wire in_char_rgn = (hc >= CX0) && (hc < CX1) &&
                       (vc >= CY0) && (vc < CY1);

    // Coordinates relative to char region (only valid when in_char_rgn)
    wire [9:0] rel_x = hc - CX0;   // 0..511
    wire [9:0] rel_y = vc - CY0;   // 0..63

    // Decompose position:
    //   char_idx = rel_x[8:6]  (which of the 8 chars, 0=leftmost)
    //   font_col = rel_x[5:3]  (column within 8×8 glyph, 0=left)
    //   font_row = rel_y[5:3]  (row within 8×8 glyph, 0=top)
    wire [2:0] char_idx = rel_x[8:6];
    wire [2:0] font_col = rel_x[5:3];
    wire [2:0] font_row = rel_y[5:3];

    // Select the 5-bit char ID for the current character slot
    reg [4:0] char_id;
    always @(*) begin
        case (char_idx)
            3'd0: char_id = disp_data[39:35];  // id7 = leftmost
            3'd1: char_id = disp_data[34:30];
            3'd2: char_id = disp_data[29:25];
            3'd3: char_id = disp_data[24:20];
            3'd4: char_id = disp_data[19:15];
            3'd5: char_id = disp_data[14:10];
            3'd6: char_id = disp_data[9:5];
            3'd7: char_id = disp_data[4:0];    // id0 = rightmost
            default: char_id = 5'd23;           // blank fallback
        endcase
    end

    // Font ROM lookup: address = {char_id[4:0], font_row[2:0]}
    wire [7:0] faddr     = {char_id, font_row};
    wire [2:0] col_inv   = 3'd7 - font_col;    // MSB = leftmost pixel
    wire       font_pixel = font_rom[faddr][col_inv];

    // ----------------------------------------------------------
    // Colour palettes (4-bit per channel)
    // ----------------------------------------------------------
    // Background colour (dark, content area)
    reg [3:0] bg_r, bg_g, bg_b;
    always @(*) begin
        case (sys_state)
            2'd0:    {bg_r, bg_g, bg_b} = {4'h0, 4'h0, 4'h5}; // MAIN: dark navy
            2'd1:    {bg_r, bg_g, bg_b} = {4'h0, 4'h3, 4'h3}; // SALE: dark teal
            2'd2:    {bg_r, bg_g, bg_b} = {4'h4, 4'h0, 4'h5}; // ADMIN: dark purple
            default: {bg_r, bg_g, bg_b} = {4'h0, 4'h0, 4'h0};
        endcase
    end

    // Header/footer bar colour (brighter accent)
    reg [3:0] bar_r, bar_g, bar_b;
    always @(*) begin
        case (sys_state)
            2'd0:    {bar_r, bar_g, bar_b} = {4'h0, 4'h2, 4'hA}; // MAIN: bright blue
            2'd1:    {bar_r, bar_g, bar_b} = {4'h0, 4'h8, 4'h6}; // SALE: bright teal
            2'd2:    {bar_r, bar_g, bar_b} = {4'h8, 4'h0, 4'hA}; // ADMIN: bright purple
            default: {bar_r, bar_g, bar_b} = {4'h0, 4'h0, 4'h0};
        endcase
    end

    // ----------------------------------------------------------
    // Region flags
    // ----------------------------------------------------------
    wire in_header  = (vc < 10'd60);
    wire in_footer  = (vc >= 10'd420);
    wire in_hsep    = (vc == 10'd60 || vc == 10'd61 ||
                       vc == 10'd418 || vc == 10'd419);

    // ----------------------------------------------------------
    // Pixel colour (combinational)
    // ----------------------------------------------------------
    reg [3:0] pix_r, pix_g, pix_b;
    always @(*) begin
        pix_r = 4'h0;
        pix_g = 4'h0;
        pix_b = 4'h0;
        if (active) begin
            if (in_hsep) begin
                // White separator lines
                pix_r = 4'hF; pix_g = 4'hF; pix_b = 4'hF;
            end else if (in_header || in_footer) begin
                pix_r = bar_r; pix_g = bar_g; pix_b = bar_b;
            end else if (in_char_rgn) begin
                if (font_pixel) begin
                    // Character foreground: bright white
                    pix_r = 4'hF; pix_g = 4'hF; pix_b = 4'hF;
                end else begin
                    pix_r = bg_r; pix_g = bg_g; pix_b = bg_b;
                end
            end else begin
                pix_r = bg_r; pix_g = bg_g; pix_b = bg_b;
            end
        end
        // else: blanking interval → 0 (already default)
    end

    // ----------------------------------------------------------
    // Output registers (all signals registered at 100 MHz for
    // clean output drive; 1-cycle = 10 ns shift is imperceptible
    // at 25 MHz pixel rate / 40 ns pixel period)
    // ----------------------------------------------------------
    reg [3:0] r_vga_r, r_vga_g, r_vga_b;
    reg       r_vga_hs, r_vga_vs;

    always @(posedge clk) begin
        r_vga_r  <= pix_r;
        r_vga_g  <= pix_g;
        r_vga_b  <= pix_b;
        r_vga_hs <= hs_comb;
        r_vga_vs <= vs_comb;
    end

    assign vga_r  = r_vga_r;
    assign vga_g  = r_vga_g;
    assign vga_b  = r_vga_b;
    assign vga_hs = r_vga_hs;
    assign vga_vs = r_vga_vs;

endmodule
