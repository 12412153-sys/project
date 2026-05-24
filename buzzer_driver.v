`timescale 1ns / 1ps

// Buzzer alarm driver for EGO1 audio output.
//
// Generates an ascending three-tone siren when alarm_trigger is high.
//
//   Tone 0 : 1320 Hz  (low tone)
//   Tone 1 : 1760 Hz  (mid tone)
//   Tone 2 : 2200 Hz  (high tone)
//
// Each tone lasts ~150 ms; the sequence 0→1→2→0→… repeats continuously.
// Higher frequencies and faster cycling make the alarm noticeably more
// irritating/distinctive than a simple two-tone 440/880 Hz pattern.
//
// Output is a 50 % duty-cycle square wave (hardware maximum for EGO1).
// aud_sd is held high to keep the on-board audio amplifier enabled.

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

    // Half-periods (cycles between PWM toggles) for each tone at 100 MHz
    localparam HALF_0 = CLK_HZ / (2 * 1320);  // ~37 879 cycles  → 1320 Hz
    localparam HALF_1 = CLK_HZ / (2 * 1760);  // ~28 409 cycles  → 1760 Hz
    localparam HALF_2 = CLK_HZ / (2 * 2200);  // ~22 727 cycles  → 2200 Hz

    // Duration of each tone: 150 ms = 100 MHz × 0.15 = 15 000 000 cycles
    localparam TONE_DUR = CLK_HZ / 1000 * 150; // 15 000 000  (fits in 24 bits)

    reg [16:0] tone_cnt;    // half-period counter  (≤ 37 879 → 17 bits)
    reg [23:0] dur_cnt;     // tone-duration counter (≤ 15 000 000 → 24 bits)
    reg [1:0]  tone_sel;    // current tone: 0, 1, or 2

    // Select the half-period for the active tone
    reg [16:0] half_period;
    always @(*) begin
        case (tone_sel)
            2'd0:    half_period = HALF_0[16:0];
            2'd1:    half_period = HALF_1[16:0];
            2'd2:    half_period = HALF_2[16:0];
            default: half_period = HALF_0[16:0];
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tone_cnt  <= 17'd0;
            dur_cnt   <= 24'd0;
            tone_sel  <= 2'd0;
            aud_pwm   <= 1'b0;
        end else if (!alarm_trigger) begin
            // Alarm inactive: silence and reset to initial state
            tone_cnt  <= 17'd0;
            dur_cnt   <= 24'd0;
            tone_sel  <= 2'd0;
            aud_pwm   <= 1'b0;
        end else begin
            // ---- Tone rotation counter ----
            if (dur_cnt >= TONE_DUR - 1) begin
                dur_cnt  <= 24'd0;
                // Advance: 0 → 1 → 2 → 0 → …
                tone_sel <= (tone_sel == 2'd2) ? 2'd0 : tone_sel + 2'd1;
            end else begin
                dur_cnt <= dur_cnt + 24'd1;
            end

            // ---- Square wave generator (50 % duty cycle) ----
            if (tone_cnt >= half_period - 17'd1) begin
                tone_cnt <= 17'd0;
                aud_pwm  <= ~aud_pwm;
            end else begin
                tone_cnt <= tone_cnt + 17'd1;
            end
        end
    end

endmodule
