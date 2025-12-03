//-----------------------------------------------------------------------------
// CAPSImg Test Vectors
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Test vectors derived from CAPSImg library for verification
// These patterns represent actual disk data structures
//
// Updated: 2025-12-03 12:55
//-----------------------------------------------------------------------------

//=============================================================================
// MFM Encoding Test Vectors
// From CAPSImg Codec/DiskEncoding.cpp
//=============================================================================

// MFM encoding rules:
// - Data bit 1: always transition
// - Data bit 0: transition only if previous data bit was 0
//
// Example: 0x4E (gap byte) = 01001110
// MFM: 10 01 00 10 01 01 01 10 = 0x9254

// Known MFM encoded patterns:
// Byte 0x00 -> MFM 0xAAAA (all clock bits, prev_bit=0)
// Byte 0x4E -> MFM depends on previous bit
// Byte 0xA1 -> MFM 0x4489 (with missing clock - sync mark)
// Byte 0xFE -> ID Address Mark (after A1 sync)
// Byte 0xFB -> Data Address Mark (after A1 sync)
// Byte 0xF8 -> Deleted Data Address Mark

module capsimg_test_vectors;

    //-------------------------------------------------------------------------
    // MFM Encoding Lookup Table (first 16 values for verification)
    // From CAPSImg mfmcode[] table with prev_bit = 0
    //-------------------------------------------------------------------------
    reg [15:0] mfm_encode_table [0:15];
    initial begin
        mfm_encode_table[0]  = 16'hAAAA;  // 0x00
        mfm_encode_table[1]  = 16'hAAA9;  // 0x01
        mfm_encode_table[2]  = 16'hAAA4;  // 0x02
        mfm_encode_table[3]  = 16'hAAA5;  // 0x03
        mfm_encode_table[4]  = 16'hAA92;  // 0x04
        mfm_encode_table[5]  = 16'hAA91;  // 0x05
        mfm_encode_table[6]  = 16'hAA94;  // 0x06
        mfm_encode_table[7]  = 16'hAA95;  // 0x07
        mfm_encode_table[8]  = 16'hAA4A;  // 0x08
        mfm_encode_table[9]  = 16'hAA49;  // 0x09
        mfm_encode_table[10] = 16'hAA44;  // 0x0A
        mfm_encode_table[11] = 16'hAA45;  // 0x0B
        mfm_encode_table[12] = 16'hAA52;  // 0x0C
        mfm_encode_table[13] = 16'hAA51;  // 0x0D
        mfm_encode_table[14] = 16'hAA54;  // 0x0E
        mfm_encode_table[15] = 16'hAA55;  // 0x0F
    end

    //-------------------------------------------------------------------------
    // FM Encoding Lookup Table (first 16 values)
    // FM: clock always 1, so each bit becomes 1x
    //-------------------------------------------------------------------------
    reg [15:0] fm_encode_table [0:15];
    initial begin
        fm_encode_table[0]  = 16'hAAAA;  // 0x00: 10 10 10 10 10 10 10 10
        fm_encode_table[1]  = 16'hAAAB;  // 0x01: 10 10 10 10 10 10 10 11
        fm_encode_table[2]  = 16'hAAAE;  // 0x02: 10 10 10 10 10 10 11 10
        fm_encode_table[3]  = 16'hAAAF;  // 0x03
        fm_encode_table[4]  = 16'hAABA;  // 0x04
        fm_encode_table[5]  = 16'hAABB;  // 0x05
        fm_encode_table[6]  = 16'hAABE;  // 0x06
        fm_encode_table[7]  = 16'hAABF;  // 0x07
        fm_encode_table[8]  = 16'hAEAA;  // 0x08
        fm_encode_table[9]  = 16'hAEAB;  // 0x09
        fm_encode_table[10] = 16'hAEAE;  // 0x0A
        fm_encode_table[11] = 16'hAEAF;  // 0x0B
        fm_encode_table[12] = 16'hAEBA;  // 0x0C
        fm_encode_table[13] = 16'hAEBB;  // 0x0D
        fm_encode_table[14] = 16'hAEBE;  // 0x0E
        fm_encode_table[15] = 16'hAEBF;  // 0x0F
    end

    //-------------------------------------------------------------------------
    // GCR CBM Encoding Table (4-bit -> 5-bit)
    // From CAPSImg gcr_cbm[]
    //-------------------------------------------------------------------------
    reg [4:0] gcr_cbm_table [0:15];
    initial begin
        gcr_cbm_table[0]  = 5'h0A;  // 01010
        gcr_cbm_table[1]  = 5'h0B;  // 01011
        gcr_cbm_table[2]  = 5'h12;  // 10010
        gcr_cbm_table[3]  = 5'h13;  // 10011
        gcr_cbm_table[4]  = 5'h0E;  // 01110
        gcr_cbm_table[5]  = 5'h0F;  // 01111
        gcr_cbm_table[6]  = 5'h16;  // 10110
        gcr_cbm_table[7]  = 5'h17;  // 10111
        gcr_cbm_table[8]  = 5'h09;  // 01001
        gcr_cbm_table[9]  = 5'h19;  // 11001
        gcr_cbm_table[10] = 5'h1A;  // 11010
        gcr_cbm_table[11] = 5'h1B;  // 11011
        gcr_cbm_table[12] = 5'h0D;  // 01101
        gcr_cbm_table[13] = 5'h1D;  // 11101
        gcr_cbm_table[14] = 5'h1E;  // 11110
        gcr_cbm_table[15] = 5'h15;  // 10101
    end

    //-------------------------------------------------------------------------
    // GCR Apple 6-bit Encoding Table (partial, first 32 values)
    // From CAPSImg gcr_apple6[]
    //-------------------------------------------------------------------------
    reg [7:0] gcr_apple6_table [0:31];
    initial begin
        gcr_apple6_table[0]  = 8'h96;
        gcr_apple6_table[1]  = 8'h97;
        gcr_apple6_table[2]  = 8'h9A;
        gcr_apple6_table[3]  = 8'h9B;
        gcr_apple6_table[4]  = 8'h9D;
        gcr_apple6_table[5]  = 8'h9E;
        gcr_apple6_table[6]  = 8'h9F;
        gcr_apple6_table[7]  = 8'hA6;
        gcr_apple6_table[8]  = 8'hA7;
        gcr_apple6_table[9]  = 8'hAB;
        gcr_apple6_table[10] = 8'hAC;
        gcr_apple6_table[11] = 8'hAD;
        gcr_apple6_table[12] = 8'hAE;
        gcr_apple6_table[13] = 8'hAF;
        gcr_apple6_table[14] = 8'hB2;
        gcr_apple6_table[15] = 8'hB3;
        gcr_apple6_table[16] = 8'hB4;
        gcr_apple6_table[17] = 8'hB5;
        gcr_apple6_table[18] = 8'hB6;
        gcr_apple6_table[19] = 8'hB7;
        gcr_apple6_table[20] = 8'hB9;
        gcr_apple6_table[21] = 8'hBA;
        gcr_apple6_table[22] = 8'hBB;
        gcr_apple6_table[23] = 8'hBC;
        gcr_apple6_table[24] = 8'hBD;
        gcr_apple6_table[25] = 8'hBE;
        gcr_apple6_table[26] = 8'hBF;
        gcr_apple6_table[27] = 8'hCB;
        gcr_apple6_table[28] = 8'hCD;
        gcr_apple6_table[29] = 8'hCE;
        gcr_apple6_table[30] = 8'hCF;
        gcr_apple6_table[31] = 8'hD3;
    end

    //-------------------------------------------------------------------------
    // CRC-CCITT Test Vectors
    // From CAPSImg Core/CRC.cpp
    //-------------------------------------------------------------------------

    // CRC-CCITT Polynomial: x^16 + x^12 + x^5 + 1 = 0x1021
    // Initial value: 0xFFFF

    // Test: ID field "FE 00 00 01 02" (AM, Cyl=0, Head=0, Sect=1, Size=512)
    // Expected CRC calculated from CAPSImg

    //-------------------------------------------------------------------------
    // Typical IBM PC Floppy Track Structure
    //-------------------------------------------------------------------------
    // Gap 4a: 80 bytes of 0x4E
    // Sync: 12 bytes of 0x00
    // IAM: 3 bytes 0xC2 (with missing clock) + 0xFC
    // Gap 1: 50 bytes of 0x4E
    //
    // For each sector:
    //   Sync: 12 bytes of 0x00
    //   IDAM: 3 bytes 0xA1 (with missing clock) + 0xFE
    //   ID: 4 bytes (C, H, R, N)
    //   CRC: 2 bytes
    //   Gap 2: 22 bytes of 0x4E
    //   Sync: 12 bytes of 0x00
    //   DAM: 3 bytes 0xA1 (with missing clock) + 0xFB
    //   Data: 512 bytes (for N=2)
    //   CRC: 2 bytes
    //   Gap 3: 80 bytes of 0x4E
    //
    // Gap 4b: fill to end of track with 0x4E

    //-------------------------------------------------------------------------
    // MFM Address Mark Patterns (with missing clocks)
    //-------------------------------------------------------------------------
    localparam [15:0] MFM_A1_SYNC   = 16'h4489;  // A1 with missing clock
    localparam [15:0] MFM_C2_SYNC   = 16'h5224;  // C2 with missing clock
    localparam [15:0] MFM_NORMAL_A1 = 16'h44A9;  // Normal A1 (no missing clock)

    //-------------------------------------------------------------------------
    // FDC Command Codes (82077AA)
    //-------------------------------------------------------------------------
    localparam [7:0] CMD_READ_DATA    = 8'h46;  // MFM, skip
    localparam [7:0] CMD_WRITE_DATA   = 8'h45;  // MFM
    localparam [7:0] CMD_READ_ID      = 8'h4A;  // MFM
    localparam [7:0] CMD_FORMAT_TRACK = 8'h4D;  // MFM
    localparam [7:0] CMD_RECALIBRATE  = 8'h07;
    localparam [7:0] CMD_SEEK         = 8'h0F;
    localparam [7:0] CMD_SENSE_INT    = 8'h08;
    localparam [7:0] CMD_SENSE_DRIVE  = 8'h04;
    localparam [7:0] CMD_SPECIFY      = 8'h03;
    localparam [7:0] CMD_CONFIGURE    = 8'h13;
    localparam [7:0] CMD_VERSION      = 8'h10;

    //-------------------------------------------------------------------------
    // Step Rate Timing (from CAPSImg clockstep[])
    // In microseconds
    //-------------------------------------------------------------------------
    localparam [15:0] STEP_RATE_0 = 16'd6000;   // 6ms  (r=0)
    localparam [15:0] STEP_RATE_1 = 16'd12000;  // 12ms (r=1)
    localparam [15:0] STEP_RATE_2 = 16'd2000;   // 2ms  (r=2) - 82077AA only
    localparam [15:0] STEP_RATE_3 = 16'd3000;   // 3ms  (r=3) - 82077AA only
    localparam [15:0] HEAD_SETTLE = 16'd15000;  // 15ms head settle

    //-------------------------------------------------------------------------
    // Data Rate Timing
    //-------------------------------------------------------------------------
    // Data Rate  | Bit Cell  | Byte Time | Track Capacity
    // 500 Kbps   | 2us       | 16us      | 12500 bytes at 300 RPM
    // 300 Kbps   | 3.33us    | 26.67us   | 7500 bytes at 300 RPM
    // 250 Kbps   | 4us       | 32us      | 6250 bytes at 300 RPM
    // 1 Mbps     | 1us       | 8us       | 25000 bytes at 300 RPM

    localparam [15:0] BIT_CELL_500K = 16'd400;   // 2us at 200MHz
    localparam [15:0] BIT_CELL_300K = 16'd667;   // 3.33us at 200MHz
    localparam [15:0] BIT_CELL_250K = 16'd800;   // 4us at 200MHz
    localparam [15:0] BIT_CELL_1M   = 16'd200;   // 1us at 200MHz

endmodule


//=============================================================================
// Flux Transition Test Pattern Generator
// Generates realistic MFM flux patterns for testing
//=============================================================================

module flux_pattern_generator (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        start,
    input  wire [1:0]  pattern_sel,    // 0=gap, 1=sync, 2=AM, 3=data
    input  wire [7:0]  data_byte,
    input  wire [15:0] bit_cell_time,  // Clocks per bit cell
    output reg         flux_out,
    output reg         pattern_done
);

    localparam PAT_GAP  = 2'b00;
    localparam PAT_SYNC = 2'b01;
    localparam PAT_AM   = 2'b10;
    localparam PAT_DATA = 2'b11;

    reg [15:0] mfm_word;
    reg [4:0]  bit_count;
    reg [15:0] time_count;
    reg        active;
    reg        prev_data_bit;

    // Simple MFM encoder for test pattern generation
    function [15:0] mfm_encode;
        input [7:0] data;
        input prev_bit;
        reg [15:0] result;
        reg clock_bit;
        integer i;
        begin
            result = 16'h0000;
            for (i = 7; i >= 0; i = i - 1) begin
                result = result << 2;
                clock_bit = ~prev_bit & ~data[i];
                result = result | {clock_bit, data[i]};
                prev_bit = data[i];
            end
            mfm_encode = result;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            flux_out      <= 1'b0;
            pattern_done  <= 1'b0;
            mfm_word      <= 16'h0000;
            bit_count     <= 5'd0;
            time_count    <= 16'd0;
            active        <= 1'b0;
            prev_data_bit <= 1'b0;
        end
        else if (enable) begin
            pattern_done <= 1'b0;
            flux_out     <= 1'b0;

            if (start && !active) begin
                active <= 1'b1;
                bit_count <= 5'd0;
                time_count <= 16'd0;

                case (pattern_sel)
                    PAT_GAP:  mfm_word <= mfm_encode(8'h4E, prev_data_bit);
                    PAT_SYNC: mfm_word <= mfm_encode(8'h00, prev_data_bit);
                    PAT_AM:   mfm_word <= 16'h4489;  // A1 sync with missing clock
                    PAT_DATA: mfm_word <= mfm_encode(data_byte, prev_data_bit);
                endcase
            end
            else if (active) begin
                time_count <= time_count + 1'b1;

                // Generate flux at half bit cell (for MFM)
                if (time_count == (bit_cell_time >> 1)) begin
                    if (mfm_word[15 - bit_count])
                        flux_out <= 1'b1;
                end
                else if (time_count >= bit_cell_time) begin
                    time_count <= 16'd0;
                    bit_count  <= bit_count + 1'b1;

                    if (bit_count == 5'd15) begin
                        active       <= 1'b0;
                        pattern_done <= 1'b1;
                        prev_data_bit <= mfm_word[0];
                    end
                end
            end
        end
    end

endmodule
