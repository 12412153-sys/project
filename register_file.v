`timescale 1ns / 1ps

// Drink data and system state register file.
// Provides concurrent read access to both admin_mode and sales_mode.
// Write priority: admin_we > sale_we (only one should write per cycle in normal operation).
//
// 4 drinks (indices 0-3): COLA, SODA, TEA, H2O
// Price range:  0-9 (stored as [7:0], effective lower nibble)
// Stock range:  0-99 (stored as [7:0]; two-digit decimal supported)
// enabled_mask: bit[i]=1 means drink i is on sale
// total_revenue: 16-bit binary accumulator
// password:      8-bit BCD (high nibble = first digit, low nibble = second digit)

module register_file (
    input  wire       clk,

    // admin_mode write port
    input  wire       admin_we,          // 1-cycle write pulse from admin_mode
    input  wire [1:0] admin_upd_type,    // 01=set price, 10=set stock (exact, cap 99), 11=toggle enabled
    input  wire [7:0] admin_upd_data,    // new price/stock as a binary value (decimal, not BCD)
    input  wire [1:0] admin_drink_id,    // target drink index (0-3)

    // sales_mode write port
    input  wire       sale_we,           // 1-cycle write pulse from sales_mode
    input  wire [1:0] sale_idx,          // drink index for deducting stock
    input  wire [7:0] sale_amount,       // amount to add to total_revenue

    // read outputs (combinatorial)
    output wire [7:0] price0, price1, price2, price3,
    output wire [7:0] stock0, stock1, stock2, stock3,   // 0-99 (two-digit)
    output wire [3:0] enabled_mask,      // bit[i]=1: drink i is on sale
    output wire [15:0] total_revenue,
    output wire [7:0]  password          // initial default: 8'h61 ("6" then "1" on keyboard)
);

    reg [7:0] r_price  [3:0];
    reg [7:0] r_stock  [3:0];            // 0-99
    reg [3:0] r_enabled;
    reg [15:0] r_revenue;
    reg [7:0]  r_password;

    // Startup defaults: loaded at FPGA configuration time (GSR) and simulation time-0.
    // Pressing S5 (PROG_B) reprograms the FPGA, restoring these values.
    initial begin
        r_price[0]  = 8'd4;   r_stock[0] = 8'd5;   // COLA: ¥4, stock 5
        r_price[1]  = 8'd5;   r_stock[1] = 8'd6;   // SODA: ¥5, stock 6
        r_price[2]  = 8'd3;   r_stock[2] = 8'd8;   // TEA:  ¥3, stock 8
        r_price[3]  = 8'd2;   r_stock[3] = 8'd9;   // H2O:  ¥2, stock 9
        r_enabled   = 4'b1111;
        r_revenue   = 16'd0;
        r_password  = 8'h61;
    end

    assign price0        = r_price[0];
    assign price1        = r_price[1];
    assign price2        = r_price[2];
    assign price3        = r_price[3];
    assign stock0        = r_stock[0];
    assign stock1        = r_stock[1];
    assign stock2        = r_stock[2];
    assign stock3        = r_stock[3];
    assign enabled_mask  = r_enabled;
    assign total_revenue = r_revenue;
    assign password      = r_password;

    always @(posedge clk) begin
        if (admin_we) begin
            case (admin_upd_type)
                2'b01: begin   // set price to exact value (decimal), capped at 9
                    r_price[admin_drink_id] <= (admin_upd_data > 8'd9) ? 8'd9 : admin_upd_data;
                end
                2'b10: begin   // set stock to exact value (decimal), capped at 99
                    r_stock[admin_drink_id] <= (admin_upd_data > 8'd99) ? 8'd99 : admin_upd_data;
                end
                2'b11: begin   // toggle enabled bit
                    r_enabled[admin_drink_id] <= ~r_enabled[admin_drink_id];
                end
                default: ;
            endcase
        end else if (sale_we) begin
            if (r_stock[sale_idx] > 0)
                r_stock[sale_idx] <= r_stock[sale_idx] - 1'b1;
            r_revenue <= r_revenue + {8'h00, sale_amount};
        end
    end

endmodule
