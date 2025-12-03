//-----------------------------------------------------------------------------
// CRC-16 CCITT Module for FluxRipper
// Ported from CAPSImg Core/CRC.cpp
// Polynomial: x^16 + x^12 + x^5 + 1 (0x1021)
//
// Updated: 2025-12-02 16:25
//-----------------------------------------------------------------------------

module crc16_ccitt (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,         // Process data when high
    input  wire        init,           // Initialize CRC to 0xFFFF
    input  wire [7:0]  data_in,        // Input byte
    output reg  [15:0] crc_out,        // Current CRC value
    output wire        crc_valid       // CRC == 0x0000 indicates valid
);

    // CRC-CCITT lookup table (256 entries)
    // Generated from CAPSImg CRC.cpp MakeCRCTable() algorithm
    // Polynomial bits: {0, 5, 12} -> 0x1021
    reg [15:0] crctab [0:255];

    // Table lookup result
    wire [7:0]  table_index;
    wire [15:0] table_value;

    assign table_index = data_in ^ crc_out[15:8];
    assign table_value = crctab[table_index];

    // CRC is valid when it equals zero (after processing check bytes)
    assign crc_valid = (crc_out == 16'h0000);

    // CRC calculation
    always @(posedge clk) begin
        if (reset) begin
            crc_out <= 16'hFFFF;
        end else if (init) begin
            crc_out <= 16'hFFFF;
        end else if (enable) begin
            // CRC-CCITT: crc = table[data ^ crc_hi] ^ (crc << 8)
            crc_out <= table_value ^ {crc_out[7:0], 8'h00};
        end
    end

    // Initialize CRC-CCITT lookup table
    // Calculated using polynomial 0x1021
    initial begin
        crctab[8'h00] = 16'h0000; crctab[8'h01] = 16'h1021; crctab[8'h02] = 16'h2042; crctab[8'h03] = 16'h3063;
        crctab[8'h04] = 16'h4084; crctab[8'h05] = 16'h50A5; crctab[8'h06] = 16'h60C6; crctab[8'h07] = 16'h70E7;
        crctab[8'h08] = 16'h8108; crctab[8'h09] = 16'h9129; crctab[8'h0A] = 16'hA14A; crctab[8'h0B] = 16'hB16B;
        crctab[8'h0C] = 16'hC18C; crctab[8'h0D] = 16'hD1AD; crctab[8'h0E] = 16'hE1CE; crctab[8'h0F] = 16'hF1EF;
        crctab[8'h10] = 16'h1231; crctab[8'h11] = 16'h0210; crctab[8'h12] = 16'h3273; crctab[8'h13] = 16'h2252;
        crctab[8'h14] = 16'h52B5; crctab[8'h15] = 16'h4294; crctab[8'h16] = 16'h72F7; crctab[8'h17] = 16'h62D6;
        crctab[8'h18] = 16'h9339; crctab[8'h19] = 16'h8318; crctab[8'h1A] = 16'hB37B; crctab[8'h1B] = 16'hA35A;
        crctab[8'h1C] = 16'hD3BD; crctab[8'h1D] = 16'hC39C; crctab[8'h1E] = 16'hF3FF; crctab[8'h1F] = 16'hE3DE;
        crctab[8'h20] = 16'h2462; crctab[8'h21] = 16'h3443; crctab[8'h22] = 16'h0420; crctab[8'h23] = 16'h1401;
        crctab[8'h24] = 16'h64E6; crctab[8'h25] = 16'h74C7; crctab[8'h26] = 16'h44A4; crctab[8'h27] = 16'h5485;
        crctab[8'h28] = 16'hA56A; crctab[8'h29] = 16'hB54B; crctab[8'h2A] = 16'h8528; crctab[8'h2B] = 16'h9509;
        crctab[8'h2C] = 16'hE5EE; crctab[8'h2D] = 16'hF5CF; crctab[8'h2E] = 16'hC5AC; crctab[8'h2F] = 16'hD58D;
        crctab[8'h30] = 16'h3653; crctab[8'h31] = 16'h2672; crctab[8'h32] = 16'h1611; crctab[8'h33] = 16'h0630;
        crctab[8'h34] = 16'h76D7; crctab[8'h35] = 16'h66F6; crctab[8'h36] = 16'h5695; crctab[8'h37] = 16'h46B4;
        crctab[8'h38] = 16'hB75B; crctab[8'h39] = 16'hA77A; crctab[8'h3A] = 16'h9719; crctab[8'h3B] = 16'h8738;
        crctab[8'h3C] = 16'hF7DF; crctab[8'h3D] = 16'hE7FE; crctab[8'h3E] = 16'hD79D; crctab[8'h3F] = 16'hC7BC;
        crctab[8'h40] = 16'h48C4; crctab[8'h41] = 16'h58E5; crctab[8'h42] = 16'h6886; crctab[8'h43] = 16'h78A7;
        crctab[8'h44] = 16'h0840; crctab[8'h45] = 16'h1861; crctab[8'h46] = 16'h2802; crctab[8'h47] = 16'h3823;
        crctab[8'h48] = 16'hC9CC; crctab[8'h49] = 16'hD9ED; crctab[8'h4A] = 16'hE98E; crctab[8'h4B] = 16'hF9AF;
        crctab[8'h4C] = 16'h8948; crctab[8'h4D] = 16'h9969; crctab[8'h4E] = 16'hA90A; crctab[8'h4F] = 16'hB92B;
        crctab[8'h50] = 16'h5AF5; crctab[8'h51] = 16'h4AD4; crctab[8'h52] = 16'h7AB7; crctab[8'h53] = 16'h6A96;
        crctab[8'h54] = 16'h1A71; crctab[8'h55] = 16'h0A50; crctab[8'h56] = 16'h3A33; crctab[8'h57] = 16'h2A12;
        crctab[8'h58] = 16'hDBFD; crctab[8'h59] = 16'hCBDC; crctab[8'h5A] = 16'hFBBF; crctab[8'h5B] = 16'hEB9E;
        crctab[8'h5C] = 16'h9B79; crctab[8'h5D] = 16'h8B58; crctab[8'h5E] = 16'hBB3B; crctab[8'h5F] = 16'hAB1A;
        crctab[8'h60] = 16'h6CA6; crctab[8'h61] = 16'h7C87; crctab[8'h62] = 16'h4CE4; crctab[8'h63] = 16'h5CC5;
        crctab[8'h64] = 16'h2C22; crctab[8'h65] = 16'h3C03; crctab[8'h66] = 16'h0C60; crctab[8'h67] = 16'h1C41;
        crctab[8'h68] = 16'hEDAE; crctab[8'h69] = 16'hFD8F; crctab[8'h6A] = 16'hCDEC; crctab[8'h6B] = 16'hDDCD;
        crctab[8'h6C] = 16'hAD2A; crctab[8'h6D] = 16'hBD0B; crctab[8'h6E] = 16'h8D68; crctab[8'h6F] = 16'h9D49;
        crctab[8'h70] = 16'h7E97; crctab[8'h71] = 16'h6EB6; crctab[8'h72] = 16'h5ED5; crctab[8'h73] = 16'h4EF4;
        crctab[8'h74] = 16'h3E13; crctab[8'h75] = 16'h2E32; crctab[8'h76] = 16'h1E51; crctab[8'h77] = 16'h0E70;
        crctab[8'h78] = 16'hFF9F; crctab[8'h79] = 16'hEFBE; crctab[8'h7A] = 16'hDFDD; crctab[8'h7B] = 16'hCFFC;
        crctab[8'h7C] = 16'hBF1B; crctab[8'h7D] = 16'hAF3A; crctab[8'h7E] = 16'h9F59; crctab[8'h7F] = 16'h8F78;
        crctab[8'h80] = 16'h9188; crctab[8'h81] = 16'h81A9; crctab[8'h82] = 16'hB1CA; crctab[8'h83] = 16'hA1EB;
        crctab[8'h84] = 16'hD10C; crctab[8'h85] = 16'hC12D; crctab[8'h86] = 16'hF14E; crctab[8'h87] = 16'hE16F;
        crctab[8'h88] = 16'h1080; crctab[8'h89] = 16'h00A1; crctab[8'h8A] = 16'h30C2; crctab[8'h8B] = 16'h20E3;
        crctab[8'h8C] = 16'h5004; crctab[8'h8D] = 16'h4025; crctab[8'h8E] = 16'h7046; crctab[8'h8F] = 16'h6067;
        crctab[8'h90] = 16'h83B9; crctab[8'h91] = 16'h9398; crctab[8'h92] = 16'hA3FB; crctab[8'h93] = 16'hB3DA;
        crctab[8'h94] = 16'hC33D; crctab[8'h95] = 16'hD31C; crctab[8'h96] = 16'hE37F; crctab[8'h97] = 16'hF35E;
        crctab[8'h98] = 16'h02B1; crctab[8'h99] = 16'h1290; crctab[8'h9A] = 16'h22F3; crctab[8'h9B] = 16'h32D2;
        crctab[8'h9C] = 16'h4235; crctab[8'h9D] = 16'h5214; crctab[8'h9E] = 16'h6277; crctab[8'h9F] = 16'h7256;
        crctab[8'hA0] = 16'hB5EA; crctab[8'hA1] = 16'hA5CB; crctab[8'hA2] = 16'h95A8; crctab[8'hA3] = 16'h8589;
        crctab[8'hA4] = 16'hF56E; crctab[8'hA5] = 16'hE54F; crctab[8'hA6] = 16'hD52C; crctab[8'hA7] = 16'hC50D;
        crctab[8'hA8] = 16'h34E2; crctab[8'hA9] = 16'h24C3; crctab[8'hAA] = 16'h14A0; crctab[8'hAB] = 16'h0481;
        crctab[8'hAC] = 16'h7466; crctab[8'hAD] = 16'h6447; crctab[8'hAE] = 16'h5424; crctab[8'hAF] = 16'h4405;
        crctab[8'hB0] = 16'hA7DB; crctab[8'hB1] = 16'hB7FA; crctab[8'hB2] = 16'h8799; crctab[8'hB3] = 16'h97B8;
        crctab[8'hB4] = 16'hE75F; crctab[8'hB5] = 16'hF77E; crctab[8'hB6] = 16'hC71D; crctab[8'hB7] = 16'hD73C;
        crctab[8'hB8] = 16'h26D3; crctab[8'hB9] = 16'h36F2; crctab[8'hBA] = 16'h0691; crctab[8'hBB] = 16'h16B0;
        crctab[8'hBC] = 16'h6657; crctab[8'hBD] = 16'h7676; crctab[8'hBE] = 16'h4615; crctab[8'hBF] = 16'h5634;
        crctab[8'hC0] = 16'hD94C; crctab[8'hC1] = 16'hC96D; crctab[8'hC2] = 16'hF90E; crctab[8'hC3] = 16'hE92F;
        crctab[8'hC4] = 16'h99C8; crctab[8'hC5] = 16'h89E9; crctab[8'hC6] = 16'hB98A; crctab[8'hC7] = 16'hA9AB;
        crctab[8'hC8] = 16'h5844; crctab[8'hC9] = 16'h4865; crctab[8'hCA] = 16'h7806; crctab[8'hCB] = 16'h6827;
        crctab[8'hCC] = 16'h18C0; crctab[8'hCD] = 16'h08E1; crctab[8'hCE] = 16'h3882; crctab[8'hCF] = 16'h28A3;
        crctab[8'hD0] = 16'hCB7D; crctab[8'hD1] = 16'hDB5C; crctab[8'hD2] = 16'hEB3F; crctab[8'hD3] = 16'hFB1E;
        crctab[8'hD4] = 16'h8BF9; crctab[8'hD5] = 16'h9BD8; crctab[8'hD6] = 16'hABBB; crctab[8'hD7] = 16'hBB9A;
        crctab[8'hD8] = 16'h4A75; crctab[8'hD9] = 16'h5A54; crctab[8'hDA] = 16'h6A37; crctab[8'hDB] = 16'h7A16;
        crctab[8'hDC] = 16'h0AF1; crctab[8'hDD] = 16'h1AD0; crctab[8'hDE] = 16'h2AB3; crctab[8'hDF] = 16'h3A92;
        crctab[8'hE0] = 16'hFD2E; crctab[8'hE1] = 16'hED0F; crctab[8'hE2] = 16'hDD6C; crctab[8'hE3] = 16'hCD4D;
        crctab[8'hE4] = 16'hBDAA; crctab[8'hE5] = 16'hAD8B; crctab[8'hE6] = 16'h9DE8; crctab[8'hE7] = 16'h8DC9;
        crctab[8'hE8] = 16'h7C26; crctab[8'hE9] = 16'h6C07; crctab[8'hEA] = 16'h5C64; crctab[8'hEB] = 16'h4C45;
        crctab[8'hEC] = 16'h3CA2; crctab[8'hED] = 16'h2C83; crctab[8'hEE] = 16'h1CE0; crctab[8'hEF] = 16'h0CC1;
        crctab[8'hF0] = 16'hEF1F; crctab[8'hF1] = 16'hFF3E; crctab[8'hF2] = 16'hCF5D; crctab[8'hF3] = 16'hDF7C;
        crctab[8'hF4] = 16'hAF9B; crctab[8'hF5] = 16'hBFBA; crctab[8'hF6] = 16'h8FD9; crctab[8'hF7] = 16'h9FF8;
        crctab[8'hF8] = 16'h6E17; crctab[8'hF9] = 16'h7E36; crctab[8'hFA] = 16'h4E55; crctab[8'hFB] = 16'h5E74;
        crctab[8'hFC] = 16'h2E93; crctab[8'hFD] = 16'h3EB2; crctab[8'hFE] = 16'h0ED1; crctab[8'hFF] = 16'h1EF0;
    end

endmodule

//-----------------------------------------------------------------------------
// CRC-16 CCITT with bit-serial interface for use with data separator
// Processes one bit at a time using LFSR implementation
//-----------------------------------------------------------------------------
module crc16_ccitt_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,         // Process bit when high
    input  wire        init,           // Initialize CRC to 0xFFFF
    input  wire        bit_in,         // Input bit (MSB first)
    output reg  [15:0] crc_out,        // Current CRC value
    output wire        crc_valid       // CRC == 0x0000 indicates valid
);

    // LFSR feedback for polynomial x^16 + x^12 + x^5 + 1
    wire feedback;

    assign feedback = bit_in ^ crc_out[15];
    assign crc_valid = (crc_out == 16'h0000);

    always @(posedge clk) begin
        if (reset || init) begin
            crc_out <= 16'hFFFF;
        end else if (enable) begin
            // Shift with feedback taps at positions 0, 5, 12
            crc_out[0]  <= feedback;
            crc_out[1]  <= crc_out[0];
            crc_out[2]  <= crc_out[1];
            crc_out[3]  <= crc_out[2];
            crc_out[4]  <= crc_out[3];
            crc_out[5]  <= crc_out[4] ^ feedback;  // Tap at x^5
            crc_out[6]  <= crc_out[5];
            crc_out[7]  <= crc_out[6];
            crc_out[8]  <= crc_out[7];
            crc_out[9]  <= crc_out[8];
            crc_out[10] <= crc_out[9];
            crc_out[11] <= crc_out[10];
            crc_out[12] <= crc_out[11] ^ feedback; // Tap at x^12
            crc_out[13] <= crc_out[12];
            crc_out[14] <= crc_out[13];
            crc_out[15] <= crc_out[14];
        end
    end

endmodule
