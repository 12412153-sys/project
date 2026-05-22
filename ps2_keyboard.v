`timescale 1ns / 1ps

// PS/2 keyboard receiver for EGO1 (USB keyboard via on-board PIC24FJ128 converter).
// Decodes PS/2 serial frames and outputs a BCD digit (0-9) with a 1-cycle valid pulse
// whenever a number key is pressed (make code, not break).
//
// PS/2 frame: start(0) + 8 data bits LSB-first + odd-parity + stop(1)
// Break sequence: 0xF0 byte followed by the make scan code.
//
// Number key scan codes (standard Set 2):
//   0:0x45  1:0x16  2:0x1E  3:0x26  4:0x25
//   5:0x2E  6:0x36  7:0x3D  8:0x3E  9:0x46

module ps2_keyboard (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    output reg  [3:0] kbd_data,   // BCD digit 0-9
    output reg        kbd_valid   // high for one clk cycle when a digit key is pressed
);

    // Three-stage synchroniser for PS2_CLK to avoid metastability
    reg [2:0] clk_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_sr <= 3'b111;
        else        clk_sr <= {clk_sr[1:0], ps2_clk};
    end
    wire ps2_fall = clk_sr[2] & ~clk_sr[1];  // falling edge of PS2_CLK

    // Registered PS2_DATA (one extra stage for stability)
    reg ps2d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ps2d <= 1'b1;
        else        ps2d <= ps2_data;
    end

    // Receive state machine
    reg [3:0] bit_cnt;   // 0=wait start, 1-8=data bits, 9=parity, 10=stop
    reg [7:0] shift;     // shift register, LSB filled first

    reg       byte_rdy;  // pulsed for one cycle when a full byte is ready
    reg [7:0] byte_val;  // the received byte

    reg got_f0;          // previous byte was 0xF0 (break prefix)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt  <= 4'd0;
            shift    <= 8'h00;
            byte_rdy <= 1'b0;
            byte_val <= 8'h00;
            got_f0   <= 1'b0;
            kbd_data  <= 4'd0;
            kbd_valid <= 1'b0;
        end else begin
            byte_rdy  <= 1'b0;
            kbd_valid <= 1'b0;

            // Bit reception on every falling edge of PS2_CLK
            if (ps2_fall) begin
                if (bit_cnt == 0) begin
                    if (!ps2d) bit_cnt <= 4'd1;  // valid start bit
                end else if (bit_cnt <= 8) begin
                    shift[bit_cnt - 1] <= ps2d;  // d0 first → d7 last
                    bit_cnt <= bit_cnt + 1'b1;
                end else if (bit_cnt == 9) begin
                    bit_cnt <= 4'd10;             // skip parity
                end else begin                    // bit_cnt == 10: stop bit
                    byte_rdy <= 1'b1;
                    byte_val <= shift;
                    bit_cnt  <= 4'd0;
                end
            end

            // Decode complete byte
            if (byte_rdy) begin
                if (byte_val == 8'hF0) begin
                    got_f0 <= 1'b1;
                end else if (got_f0) begin
                    got_f0 <= 1'b0;              // consume the break code, ignore key release
                end else begin
                    // Make code: check for digit keys
                    case (byte_val)
                        8'h45: begin kbd_data <= 4'd0; kbd_valid <= 1'b1; end
                        8'h16: begin kbd_data <= 4'd1; kbd_valid <= 1'b1; end
                        8'h1E: begin kbd_data <= 4'd2; kbd_valid <= 1'b1; end
                        8'h26: begin kbd_data <= 4'd3; kbd_valid <= 1'b1; end
                        8'h25: begin kbd_data <= 4'd4; kbd_valid <= 1'b1; end
                        8'h2E: begin kbd_data <= 4'd5; kbd_valid <= 1'b1; end
                        8'h36: begin kbd_data <= 4'd6; kbd_valid <= 1'b1; end
                        8'h3D: begin kbd_data <= 4'd7; kbd_valid <= 1'b1; end
                        8'h3E: begin kbd_data <= 4'd8; kbd_valid <= 1'b1; end
                        8'h46: begin kbd_data <= 4'd9; kbd_valid <= 1'b1; end
                        default: ;
                    endcase
                end
            end
        end
    end

endmodule
