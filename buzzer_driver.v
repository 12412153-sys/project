`timescale 1ns / 1ps

// Buzzer alarm driver for EGO1 audio output.
// Generates a two-tone alternating alarm when alarm_trigger is high.
// Output: PWM square wave on aud_pwm, aud_sd held high to enable the amplifier.
//
// Tone A: ~880 Hz  (high beep)
// Tone B: ~440 Hz  (low beep)
// Alternates every ~250 ms for a classic two-tone alarm effect.

module buzzer_driver #(
    parameter CLK_HZ = 100_000_000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire alarm_trigger,
    output reg  aud_pwm,
    output wire aud_sd
);

    assign aud_sd = 1'b1;  // always enable audio amplifier

    // Tone half-periods at 100 MHz
    localparam TONE_A_HALF = CLK_HZ / (2 * 880);   // ~56818 cycles
    localparam TONE_B_HALF = CLK_HZ / (2 * 440);   // ~113636 cycles
    localparam TONE_SWITCH = CLK_HZ / 4;            // 250ms between tone changes

    reg [16:0] tone_cnt;     // counts to half-period for square wave toggle
    reg [24:0] switch_cnt;   // counts to TONE_SWITCH
    reg        tone_sel;     // 0=tone A, 1=tone B

    wire [16:0] half_period = tone_sel ? TONE_B_HALF[16:0] : TONE_A_HALF[16:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tone_cnt   <= 17'd0;
            switch_cnt <= 25'd0;
            tone_sel   <= 1'b0;
            aud_pwm    <= 1'b0;
        end else if (!alarm_trigger) begin
            tone_cnt   <= 17'd0;
            switch_cnt <= 25'd0;
            tone_sel   <= 1'b0;
            aud_pwm    <= 1'b0;
        end else begin
            // Tone alternation counter
            if (switch_cnt >= TONE_SWITCH - 1) begin
                switch_cnt <= 25'd0;
                tone_sel   <= ~tone_sel;
            end else begin
                switch_cnt <= switch_cnt + 1'b1;
            end

            // Square wave generator
            if (tone_cnt >= half_period - 1) begin
                tone_cnt <= 17'd0;
                aud_pwm  <= ~aud_pwm;
            end else begin
                tone_cnt <= tone_cnt + 1'b1;
            end
        end
    end

endmodule
