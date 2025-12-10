//==============================================================================
// QIC-117 Data Streamer / Block Boundary Detector
//==============================================================================
// File: qic117_data_streamer.v
// Description: Detects block and segment boundaries in QIC tape MFM data stream.
//              QIC tapes don't have sector structure like floppies; instead they
//              use continuous data blocks with sync patterns.
//
// QIC Data Format:
//   - 512-byte data blocks
//   - Each block has 10-byte preamble + 2-byte sync + 1 header + 512 data + 3 ECC
//   - 32 blocks per segment (16KB per segment)
//   - Segments are separated by inter-record gaps (IRG)
//
// Sync Pattern Detection:
//   - Preamble: 10 bytes of 0x00 (MFM encoded as continuous clock bits)
//   - Sync mark: 0xA1, 0xA1 with missing clock (MFM 0x4489)
//   - After sync: block header byte identifies block type
//
// Block Types:
//   - 0x00: Normal data block
//   - 0x0F: End of data marker (EOD)
//   - 0x1F: File mark (tape file separator)
//   - 0xFF: Bad block marker
//
// Reference: QIC-80 Specification, QIC-117 Rev G
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */
module qic117_data_streamer #(
    parameter CLK_FREQ_HZ = 200_000_000   // 200 MHz clock (reserved for future)
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Control
    //=========================================================================
    input  wire        enable,            // Enable streamer
    input  wire        streaming,         // Tape is streaming (from FSM)
    input  wire        direction,         // 0=forward, 1=reverse (reserved for future)
    input  wire        clear_counters,    // Clear segment/error counters

    //=========================================================================
    // MFM Data Interface (from DPLL)
    //=========================================================================
    input  wire        mfm_data,          // Decoded MFM data bit
    input  wire        mfm_clock,         // MFM clock (data valid strobe)
    input  wire        dpll_locked,       // DPLL is locked

    //=========================================================================
    // Block Detection Outputs
    //=========================================================================
    output reg         block_sync,        // Block preamble/sync detected
    output reg  [8:0]  byte_in_block,     // Current byte position (0-511)
    output reg         block_start,       // Pulse at start of block data
    output reg         block_complete,    // Pulse when 512 bytes received
    output reg  [4:0]  block_in_segment,  // Block number within segment (0-31)
    output reg  [7:0]  block_header,      // Current block's header byte

    //=========================================================================
    // Segment Tracking
    //=========================================================================
    output reg         segment_start,     // Pulse at segment start
    output reg         segment_complete,  // Pulse when 32 blocks = 1 segment
    output reg  [15:0] segment_count,     // Total segments processed
    output reg         irg_detected,      // Inter-record gap detected

    //=========================================================================
    // Data Output
    //=========================================================================
    output reg  [7:0]  data_byte,         // Assembled data byte
    output reg         data_valid,        // Data byte valid strobe
    output reg         data_is_header,    // Current byte is block header
    output reg         data_is_ecc,       // Current byte is ECC

    //=========================================================================
    // ECC Output (for software validation)
    //=========================================================================
    output reg  [23:0] ecc_bytes,         // Captured ECC bytes (3 bytes)
    output reg         ecc_valid,         // ECC bytes are valid

    //=========================================================================
    // Block Type Detection
    //=========================================================================
    output reg         is_data_block,     // Normal data block
    output reg         is_file_mark,      // File mark detected
    output reg         is_eod_mark,       // End of data marker
    output reg         is_bad_block,      // Bad block marker

    //=========================================================================
    // Error Detection
    //=========================================================================
    output reg         sync_lost,         // Lost sync during block
    output reg         overrun_error,     // Data overrun (too many bits)
    output reg         preamble_error,    // Invalid preamble detected
    output reg  [15:0] error_count,       // Total errors
    output reg  [15:0] good_block_count,  // Successfully received blocks

    //=========================================================================
    // Debug/Status
    //=========================================================================
    output reg  [2:0]  state_out,         // Current FSM state
    output reg  [7:0]  preamble_count     // Consecutive preamble bytes seen
);

    //=========================================================================
    // QIC Format Constants (documenting the format even if not all are referenced)
    //=========================================================================
    /* verilator lint_off UNUSEDPARAM */
    localparam PREAMBLE_BYTES  = 10;      // Nominal preamble length
    localparam SYNC_BYTES      = 2;       // Sync mark length (0xA1, 0xA1)
    localparam HEADER_BYTES    = 1;       // Block header
    /* verilator lint_on UNUSEDPARAM */
    localparam PREAMBLE_MIN    = 6;       // Minimum valid preamble
    localparam DATA_BYTES      = 512;     // Data block size
    localparam ECC_BYTES       = 3;       // Error correction
    localparam BLOCKS_PER_SEG  = 32;      // Blocks per segment
    /* verilator lint_off WIDTHTRUNC */
    localparam [4:0] BLOCKS_PER_SEG_M1 = BLOCKS_PER_SEG - 1;  // For comparison
    /* verilator lint_on WIDTHTRUNC */

    // MFM Sync pattern: 0xA1 with missing clock = 0x4489 in MFM
    // The pattern 0100 0100 1000 1001 in MFM represents 0xA1 with clock violation
    localparam [15:0] SYNC_PATTERN_MFM = 16'h4489;

    // Preamble pattern: 0x00 in MFM = alternating clock bits = 0xAAAA
    localparam [15:0] PREAMBLE_PATTERN = 16'hAAAA;

    // Block type codes (in header byte)
    localparam [7:0] BLOCK_DATA      = 8'h00;  // Normal data block
    localparam [7:0] BLOCK_EOD       = 8'h0F;  // End of data
    localparam [7:0] BLOCK_FILE_MARK = 8'h1F;  // File mark
    localparam [7:0] BLOCK_BAD       = 8'hFF;  // Bad block marker

    // IRG timeout - if no valid data for this many bit times, consider it IRG
    // At 500Kbps, 1000 bits = 2ms
    localparam IRG_TIMEOUT_BITS = 1000;

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [2:0] ST_HUNT_PREAMBLE = 3'd0;  // Looking for preamble pattern
    localparam [2:0] ST_IN_PREAMBLE   = 3'd1;  // Receiving preamble bytes
    localparam [2:0] ST_HUNT_SYNC     = 3'd2;  // Looking for sync mark
    localparam [2:0] ST_SYNC_VERIFY   = 3'd3;  // Verify second sync byte
    localparam [2:0] ST_HEADER        = 3'd4;  // Reading block header
    localparam [2:0] ST_DATA          = 3'd5;  // Reading 512 data bytes
    localparam [2:0] ST_ECC           = 3'd6;  // Reading ECC bytes
    localparam [2:0] ST_INTER_BLOCK   = 3'd7;  // Inter-block gap

    reg [2:0] state;

    //=========================================================================
    // Shift Registers for Pattern Matching
    //=========================================================================
    reg [15:0] mfm_shift;                 // MFM bit shift register (16 bits)
    reg [7:0]  byte_shift;                // Byte assembly shift register
    reg [2:0]  bit_count;                 // Bits received in current byte (0-7)

    //=========================================================================
    // Counters
    //=========================================================================
    reg [9:0]  byte_count;                // Bytes in current phase
    reg [1:0]  ecc_byte_idx;              // ECC byte index (0-2)
    reg [10:0] irg_counter;               // IRG timeout counter

    //=========================================================================
    // Clock Edge Detection
    //=========================================================================
    reg mfm_clock_prev;
    wire mfm_clock_rising = mfm_clock && !mfm_clock_prev;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mfm_clock_prev <= 1'b0;
        end else begin
            mfm_clock_prev <= mfm_clock;
        end
    end

    //=========================================================================
    // Pattern Detection Logic
    //=========================================================================
    // Detect preamble pattern (0xAAAA in MFM = 0x00 data bytes)
    wire preamble_match = (mfm_shift == PREAMBLE_PATTERN) ||
                          (mfm_shift == 16'h5555);  // Inverted preamble

    // Detect sync pattern (0x4489 = 0xA1 with missing clock)
    wire sync_match = (mfm_shift == SYNC_PATTERN_MFM);

    //=========================================================================
    // MFM Shift Register
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mfm_shift <= 16'd0;
        end else if (enable && streaming && mfm_clock_rising) begin
            mfm_shift <= {mfm_shift[14:0], mfm_data};
        end else if (!streaming) begin
            mfm_shift <= 16'd0;
        end
    end

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= ST_HUNT_PREAMBLE;
            byte_shift       <= 8'd0;
            bit_count        <= 3'd0;
            byte_count       <= 10'd0;
            byte_in_block    <= 9'd0;
            block_in_segment <= 5'd0;
            block_header     <= 8'd0;
            segment_count    <= 16'd0;
            data_byte        <= 8'd0;
            data_valid       <= 1'b0;
            data_is_header   <= 1'b0;
            data_is_ecc      <= 1'b0;
            block_sync       <= 1'b0;
            block_start      <= 1'b0;
            block_complete   <= 1'b0;
            segment_start    <= 1'b0;
            segment_complete <= 1'b0;
            irg_detected     <= 1'b0;
            is_data_block    <= 1'b0;
            is_file_mark     <= 1'b0;
            is_eod_mark      <= 1'b0;
            is_bad_block     <= 1'b0;
            sync_lost        <= 1'b0;
            overrun_error    <= 1'b0;
            preamble_error   <= 1'b0;
            error_count      <= 16'd0;
            good_block_count <= 16'd0;
            state_out        <= 3'd0;
            preamble_count   <= 8'd0;
            ecc_bytes        <= 24'd0;
            ecc_valid        <= 1'b0;
            ecc_byte_idx     <= 2'd0;
            irg_counter      <= 11'd0;
        end else if (clear_counters) begin
            segment_count    <= 16'd0;
            error_count      <= 16'd0;
            good_block_count <= 16'd0;
        end else if (!enable || !streaming) begin
            // Not active - reset to hunt state but keep counters
            state          <= ST_HUNT_PREAMBLE;
            bit_count      <= 3'd0;
            byte_count     <= 10'd0;
            block_sync     <= 1'b0;
            preamble_count <= 8'd0;
            irg_counter    <= 11'd0;
        end else begin
            // Clear single-cycle strobes
            data_valid       <= 1'b0;
            data_is_header   <= 1'b0;
            data_is_ecc      <= 1'b0;
            block_sync       <= 1'b0;
            block_start      <= 1'b0;
            block_complete   <= 1'b0;
            segment_start    <= 1'b0;
            segment_complete <= 1'b0;
            irg_detected     <= 1'b0;
            sync_lost        <= 1'b0;
            overrun_error    <= 1'b0;
            preamble_error   <= 1'b0;
            ecc_valid        <= 1'b0;

            // Update state output for debug
            state_out <= state;

            // IRG detection - count bits without valid sync
            if (mfm_clock_rising) begin
                if (state == ST_HUNT_PREAMBLE || state == ST_IN_PREAMBLE) begin
                    if (irg_counter < IRG_TIMEOUT_BITS) begin
                        irg_counter <= irg_counter + 1'b1;
                    end else begin
                        irg_detected <= 1'b1;
                    end
                end else begin
                    irg_counter <= 11'd0;
                end
            end

            if (mfm_clock_rising && dpll_locked) begin
                case (state)
                    //=========================================================
                    ST_HUNT_PREAMBLE: begin
                        // Look for preamble pattern (0x00 bytes = 0xAAAA MFM)
                        if (preamble_match) begin
                            preamble_count <= 8'd1;
                            bit_count      <= 3'd0;
                            state          <= ST_IN_PREAMBLE;
                        end
                    end

                    //=========================================================
                    ST_IN_PREAMBLE: begin
                        // Count preamble bytes, wait for sync
                        bit_count <= bit_count + 1'b1;

                        if (bit_count == 3'd7) begin
                            bit_count <= 3'd0;

                            // Check if still in preamble
                            if (preamble_match) begin
                                if (preamble_count < 8'hFF) begin
                                    preamble_count <= preamble_count + 1'b1;
                                end
                            end
                        end

                        // Check for sync pattern
                        if (sync_match) begin
                            if (preamble_count >= PREAMBLE_MIN) begin
                                // Valid preamble followed by sync
                                block_sync <= 1'b1;
                                bit_count  <= 3'd0;
                                state      <= ST_SYNC_VERIFY;
                            end else begin
                                // Preamble too short
                                preamble_error <= 1'b1;
                                error_count    <= error_count + 1'b1;
                                state          <= ST_HUNT_PREAMBLE;
                            end
                        end
                    end

                    //=========================================================
                    ST_HUNT_SYNC: begin
                        // Direct sync search (fallback if preamble detection fails)
                        if (sync_match) begin
                            block_sync <= 1'b1;
                            bit_count  <= 3'd0;
                            state      <= ST_SYNC_VERIFY;
                        end
                    end

                    //=========================================================
                    ST_SYNC_VERIFY: begin
                        // Verify second 0xA1 sync byte
                        bit_count  <= bit_count + 1'b1;
                        byte_shift <= {byte_shift[6:0], mfm_data};

                        if (bit_count == 3'd7) begin
                            bit_count <= 3'd0;

                            // Check for second sync byte (0xA1)
                            if ({byte_shift[6:0], mfm_data} == 8'hA1) begin
                                // Valid sync sequence confirmed
                                byte_count <= 10'd0;
                                state      <= ST_HEADER;
                            end else begin
                                // Invalid sync - back to hunting
                                preamble_count <= 8'd0;
                                state          <= ST_HUNT_PREAMBLE;
                            end
                        end
                    end

                    //=========================================================
                    ST_HEADER: begin
                        // Read block header byte
                        bit_count  <= bit_count + 1'b1;
                        byte_shift <= {byte_shift[6:0], mfm_data};

                        if (bit_count == 3'd7) begin
                            // Header byte complete
                            block_header   <= {byte_shift[6:0], mfm_data};
                            data_byte      <= {byte_shift[6:0], mfm_data};
                            data_valid     <= 1'b1;
                            data_is_header <= 1'b1;
                            bit_count      <= 3'd0;
                            byte_count     <= 10'd0;
                            byte_in_block  <= 9'd0;

                            // Decode block type
                            is_data_block <= ({byte_shift[6:0], mfm_data} == BLOCK_DATA);
                            is_file_mark  <= ({byte_shift[6:0], mfm_data} == BLOCK_FILE_MARK);
                            is_eod_mark   <= ({byte_shift[6:0], mfm_data} == BLOCK_EOD);
                            is_bad_block  <= ({byte_shift[6:0], mfm_data} == BLOCK_BAD);

                            // Check for segment start (first block)
                            if (block_in_segment == 0) begin
                                segment_start <= 1'b1;
                            end

                            block_start    <= 1'b1;
                            preamble_count <= 8'd0;
                            irg_counter    <= 11'd0;
                            state          <= ST_DATA;
                        end
                    end

                    //=========================================================
                    ST_DATA: begin
                        // Read 512 data bytes
                        bit_count  <= bit_count + 1'b1;
                        byte_shift <= {byte_shift[6:0], mfm_data};

                        if (bit_count == 3'd7) begin
                            // Byte complete
                            data_byte     <= {byte_shift[6:0], mfm_data};
                            data_valid    <= 1'b1;
                            bit_count     <= 3'd0;
                            byte_count    <= byte_count + 1'b1;
                            byte_in_block <= byte_in_block + 1'b1;

                            if (byte_count >= DATA_BYTES - 1) begin
                                // All data bytes received
                                byte_count   <= 10'd0;
                                ecc_byte_idx <= 2'd0;
                                ecc_bytes    <= 24'd0;
                                state        <= ST_ECC;
                            end
                        end
                    end

                    //=========================================================
                    ST_ECC: begin
                        // Read and capture ECC bytes
                        bit_count  <= bit_count + 1'b1;
                        byte_shift <= {byte_shift[6:0], mfm_data};

                        if (bit_count == 3'd7) begin
                            bit_count  <= 3'd0;
                            byte_count <= byte_count + 1'b1;

                            // Capture ECC byte
                            data_byte    <= {byte_shift[6:0], mfm_data};
                            data_valid   <= 1'b1;
                            data_is_ecc  <= 1'b1;

                            case (ecc_byte_idx)
                                2'd0: ecc_bytes[7:0]   <= {byte_shift[6:0], mfm_data};
                                2'd1: ecc_bytes[15:8]  <= {byte_shift[6:0], mfm_data};
                                2'd2: ecc_bytes[23:16] <= {byte_shift[6:0], mfm_data};
                                default: ; // Should not occur - only 3 ECC bytes
                            endcase
                            ecc_byte_idx <= ecc_byte_idx + 1'b1;

                            if (byte_count >= ECC_BYTES - 1) begin
                                // Block complete
                                ecc_valid        <= 1'b1;
                                block_complete   <= 1'b1;
                                good_block_count <= good_block_count + 1'b1;
                                block_in_segment <= block_in_segment + 1'b1;

                                // Check for segment complete
                                if (block_in_segment >= BLOCKS_PER_SEG_M1) begin
                                    segment_complete <= 1'b1;
                                    segment_count    <= segment_count + 1'b1;
                                    block_in_segment <= 5'd0;
                                end

                                byte_count <= 10'd0;
                                state      <= ST_INTER_BLOCK;
                            end
                        end
                    end

                    //=========================================================
                    ST_INTER_BLOCK: begin
                        // Brief inter-block processing, then hunt for next block
                        // Clear block type flags
                        is_data_block <= 1'b0;
                        is_file_mark  <= 1'b0;
                        is_eod_mark   <= 1'b0;
                        is_bad_block  <= 1'b0;

                        state <= ST_HUNT_PREAMBLE;
                    end

                    //=========================================================
                    default: begin
                        state <= ST_HUNT_PREAMBLE;
                    end
                endcase
            end

            // Sync loss detection - if we're reading data and lose DPLL lock
            if ((state == ST_DATA || state == ST_ECC || state == ST_HEADER) && !dpll_locked) begin
                sync_lost   <= 1'b1;
                error_count <= error_count + 1'b1;
                state       <= ST_HUNT_PREAMBLE;
                preamble_count <= 8'd0;
            end
        end
    end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on UNUSEDPARAM */
