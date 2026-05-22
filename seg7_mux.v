`timescale 1ns / 1ps

// 8-digit multiplexed 7-segment display driver for EGO1.
//
// EGO1 has two separate 4-digit groups sharing position-select lines:
//   DN0 (right 4 digits): positions 0-3, segment bus SEG0, position selects AN[3:0]
//   DN1 (left  4 digits): positions 4-7, segment bus SEG1, position selects AN[7:4]
// All signals are active-high (common-cathode displays driven active-high).
//
// disp_data[39:0]: 8 x 5-bit character IDs packed as
//   {id7[4:0], id6[4:0], id5[4:0], id4[4:0], id3[4:0], id2[4:0], id1[4:0], id0[4:0]}
//   id7 = leftmost digit (AN[7]), id0 = rightmost digit (AN[0]).
//
// Character ID encoding matches sales_mode.v localparams:
//   0-9  = digits 0-9      10=A 11=b 12=C 13=d 14=E 15=F
//   16=H  17=L  18=O  19=P  20=S  21=t  22=r  23=blank  24=-
//   25=U  26=n  27=I  28=Y

module seg7_mux #(
    parameter CLK_HZ  = 100_000_000,
    parameter SCAN_HZ = 800          // 800Hz scan => ~100Hz per digit flicker-free
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [39:0] disp_data,
    output reg  [7:0]  seg0,     // DN0 segment lines {dp,g,f,e,d,c,b,a}, high active
    output reg  [7:0]  seg1,     // DN1 segment lines {dp,g,f,e,d,c,b,a}, high active
    output reg  [7:0]  an        // position select, high active, an[0]=rightmost
);

    localparam SCAN_CNT = CLK_HZ / SCAN_HZ;  // cycles per digit slot (8 slots total)
    localparam CNT_W    = 17;                 // ceil(log2(100M/800))=17 bits

    reg [CNT_W-1:0] cnt;
    reg [2:0]       digit;   // 0=rightmost, 7=leftmost

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt   <= 0;
            digit <= 0;
        end else if (cnt >= SCAN_CNT - 1) begin
            cnt   <= 0;
            digit <= digit + 1'b1;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    // Mux character ID for current digit position
    reg [4:0] char_id;
    always @(*) begin
        case (digit)
            3'd0: char_id = disp_data[4:0];
            3'd1: char_id = disp_data[9:5];
            3'd2: char_id = disp_data[14:10];
            3'd3: char_id = disp_data[19:15];
            3'd4: char_id = disp_data[24:20];
            3'd5: char_id = disp_data[29:25];
            3'd6: char_id = disp_data[34:30];
            3'd7: char_id = disp_data[39:35];
            default: char_id = 5'd23;
        endcase
    end

    // Character ID to 7-segment pattern {dp,g,f,e,d,c,b,a}, active-high
    function [7:0] id_to_seg;
        input [4:0] id;
        begin
            case (id)
                5'd0:  id_to_seg = 8'h3F; // 0
                5'd1:  id_to_seg = 8'h06; // 1
                5'd2:  id_to_seg = 8'h5B; // 2
                5'd3:  id_to_seg = 8'h4F; // 3
                5'd4:  id_to_seg = 8'h66; // 4
                5'd5:  id_to_seg = 8'h6D; // 5
                5'd6:  id_to_seg = 8'h7D; // 6
                5'd7:  id_to_seg = 8'h07; // 7
                5'd8:  id_to_seg = 8'h7F; // 8
                5'd9:  id_to_seg = 8'h6F; // 9
                5'd10: id_to_seg = 8'h77; // A
                5'd11: id_to_seg = 8'h7C; // b
                5'd12: id_to_seg = 8'h39; // C
                5'd13: id_to_seg = 8'h5E; // d
                5'd14: id_to_seg = 8'h79; // E
                5'd15: id_to_seg = 8'h71; // F
                5'd16: id_to_seg = 8'h76; // H
                5'd17: id_to_seg = 8'h38; // L
                5'd18: id_to_seg = 8'h3F; // O (same pattern as 0)
                5'd19: id_to_seg = 8'h73; // P
                5'd20: id_to_seg = 8'h6D; // S (same pattern as 5)
                5'd21: id_to_seg = 8'h78; // t
                5'd22: id_to_seg = 8'h50; // r
                5'd23: id_to_seg = 8'h00; // blank
                5'd24: id_to_seg = 8'h40; // - (dash)
                5'd25: id_to_seg = 8'h3E; // U
                5'd26: id_to_seg = 8'h54; // n
                5'd27: id_to_seg = 8'h06; // I (same as 1)
                5'd28: id_to_seg = 8'h6E; // Y
                default: id_to_seg = 8'h00;
            endcase
        end
    endfunction

    wire [7:0] seg_pat = id_to_seg(char_id);

    // Drive outputs: one digit active at a time, segments on the matching bus
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            an   <= 8'h00;
            seg0 <= 8'h00;
            seg1 <= 8'h00;
        end else begin
            an <= (8'h01 << digit);
            if (digit[2] == 1'b0) begin  // digits 0-3: right group DN0
                seg0 <= seg_pat;
                seg1 <= 8'h00;
            end else begin               // digits 4-7: left group DN1
                seg0 <= 8'h00;
                seg1 <= seg_pat;
            end
        end
    end

endmodule
