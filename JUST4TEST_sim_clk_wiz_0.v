`timescale 1ns / 1ps
//
// Simulation behavioural stub for clk_wiz_0 (Clocking Wizard / MMCM).
//
// In SYNTHESIS (Vivado): do NOT include this file. Instead, use the real
// IP core generated via IP Catalog > Clocking Wizard (see drink_vending_top.v
// for step-by-step instructions). Vivado finds that IP automatically.
//
// In SIMULATION (iverilog / tb_drink_vending_top.v): include this file.
// It divides clk_in1 by 4 to approximate the 25 MHz pixel clock.
// The exact frequency doesn't matter for functional simulation because
// the testbench does not exercise any VGA pixel-timing checks.
//
// To keep the file out of synthesis: in Vivado, right-click the file in
// Sources -> Set File Type to "Verilog Simulation Only", or exclude it
// from the synthesis fileset (uncheck "Used in synthesis" in File
// Properties). This prevents a "multiple definition of clk_wiz_0" error.
//
module clk_wiz_0 (
    input  wire clk_in1,   // 100 MHz board clock
    input  wire reset,     // active-high; unused in this stub
    output wire locked,    // always 1 in simulation
    output wire clk_out1   // ~25 MHz (100 / 4) pixel clock approximation
);
    assign locked = 1'b1;

    // Divide clk_in1 by 4: cnt[1] toggles every 2 cycles of clk_in1,
    // giving a 25 MHz square wave from a 100 MHz input.
    reg [1:0] cnt = 2'd0;
    always @(posedge clk_in1) cnt <= cnt + 1'b1;
    assign clk_out1 = cnt[1];

endmodule
