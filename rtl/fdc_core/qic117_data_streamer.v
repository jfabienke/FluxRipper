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
//   - Each block has 10-byte preamble + 2-byte sync + 512 data + 3 ECC
//   - 32 blocks per segment (16KB per segment)
//   - Segments are separated by inter-record gaps
//
// Sync Pattern Detection:
//   - Preamble: 10 bytes of 0x00 (generates specific MFM pattern)
//   - Sync mark: 0xA1, 0xA1 with missing clock (same as floppy)
//   - After sync: block header byte identifies block type
//
// Reference: QIC-80 Specification, QIC-117 Rev G
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module qic117_data_streamer #(
    parameter CLK_FREQ_HZ = 200_000_000   // 200 MHz clock
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Control
    //=========================================================================
    input  wire        enable,            // Enable streamer
    input  wire        streaming,         // Tape is streaming (from FSM)
    input  wire        direction,         // 0=forward, 1=reverse

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

    //=========================================================================
    // Segment Tracking
    //=========================================================================
    output reg         segment_start,     // Pulse at segment start
    output reg         segment_complete,  // Pulse when 32 blocks = 1 segment
    output reg  [15:0] segment_count,     // Total segments processed

    //=========================================================================
    // Data Output
    //=========================================================================
    output reg  [7:0]  data_byte,         // Assembled data byte
    output reg         data_valid,        // Data byte valid strobe
    output reg         data_is_header,    // Current byte is block header

    //=========================================================================
    // File Mark Detection
    //=========================================================================
    output reg         file_mark_detect,  // File mark block detected

    //=========================================================================
    // Error Detection
    //=========================================================================
    output reg         sync_lost,         // Lost sync during block
    output reg         overrun_error,     // Data overrun (too many bits)
    output reg  [15:0] error_count        // Total errors
);

    //=========================================================================
    // QIC Format Constants
    //=========================================================================
    localparam PREAMBLE_BYTES  = 10;      // Preamble length
    localparam SYNC_BYTES      = 2;       // Sync mark length (0xA1, 0xA1)
    localparam HEADER_BYTES    = 1;       // Block header
    localparam DATA_BYTES      = 512;     // Data block size
    localparam ECC_BYTES       = 3;       // Error correction
    localparam BLOCKS_PER_SEG  = 32;      // Blocks per segment

    // Total block size in bytes
    localparam BLOCK_TOTAL = PREAMBLE_BYTES + SYNC_BYTES + HEADER_BYTES +
                             DATA_BYTES + ECC_BYTES;

    // Sync pattern: 0xA1 with missing clock = 0x4489 in MFM
    localparam [15:0] SYNC_PATTERN = 16'h4489;

    // Block type codes (in header byte)
    localparam [7:0] BLOCK_DATA      = 8'h00;  // Normal data block
    localparam [7:0] BLOCK_FILE_MARK = 8'h1F;  // File mark
    localparam [7:0] BLOCK_EOD       = 8'h0F;  // End of data
    localparam [7:0] BLOCK_BAD       = 8'hFF;  // Bad block marker

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [2:0] ST_HUNT_SYNC   = 3'd0;   // Hunting for sync pattern
    localparam [2:0] ST_SYNC_FOUND  = 3'd1;   // Sync detected, getting header
    localparam [2:0] ST_HEADER      = 3'd2;   // Reading block header
    localparam [2:0] ST_DATA        = 3'd3;   // Reading 512 data bytes
    localparam [2:0] ST_ECC         = 3'd4;   // Reading ECC bytes
    localparam [2:0] ST_INTER_BLOCK = 3'd5;   // Inter-block gap

    reg [2:0] state;

    //=========================================================================
    // Shift Register for Pattern Matching
    //=========================================================================
    reg [15:0] mfm_shift;                 // MFM bit shift register
    reg [7:0]  byte_shift;                // Byte assembly shift register
    reg [2:0]  bit_count;                 // Bits received in current byte

    //=========================================================================
    // Counters
    //=========================================================================
    reg [9:0]  byte_count;                // Bytes in current phase
    reg [7:0]  block_header;              // Stored block header

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
    // MFM Shift Register
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mfm_shift <= 16'd0;
        end else if (enable && streaming && mfm_clock_rising) begin
            mfm_shift <= {mfm_shift[14:0], mfm_data};
        end
    end

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= ST_HUNT_SYNC;
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
            block_sync       <= 1'b0;
            block_start      <= 1'b0;
            block_complete   <= 1'b0;
            segment_start    <= 1'b0;
            segment_complete <= 1'b0;
            file_mark_detect <= 1'b0;
            sync_lost        <= 1'b0;
            overrun_error    <= 1'b0;
            error_count      <= 16'd0;
        end else if (!enable || !streaming) begin
            // Not active - reset to hunt state
            state      <= ST_HUNT_SYNC;
            bit_count  <= 3'd0;
            byte_count <= 10'd0;
            block_sync <= 1'b0;
        end else begin
            // Clear single-cycle strobes
            data_valid       <= 1'b0;
            data_is_header   <= 1'b0;
            block_sync       <= 1'b0;
            block_start      <= 1'b0;
            block_complete   <= 1'b0;
            segment_start    <= 1'b0;
            segment_complete <= 1'b0;
            file_mark_detect <= 1'b0;
            sync_lost        <= 1'b0;
            overrun_error    <= 1'b0;

            if (mfm_clock_rising && dpll_locked) begin
                case (state)
                    //-----------------------------------------------------
                    ST_HUNT_SYNC: begin
                        // Look for sync pattern in MFM stream
                        if (mfm_shift == SYNC_PATTERN) begin
                            // Found first sync byte
                            block_sync <= 1'b1;
                            bit_count  <= 3'd0;
                            byte_count <= 10'd1;  // One sync byte seen
                            state      <= ST_SYNC_FOUND;
                        end
                    end

                    //-----------------------------------------------------
                    ST_SYNC_FOUND: begin
                        // Assemble bytes, look for second sync
                        bit_count <= bit_count + 1'b1;
                        byte_shift <= {byte_shift[6:0], mfm_data};

                        if (bit_count == 3'd7) begin
                            // Byte complete
                            bit_count <= 3'd0;

                            if (byte_shift == 8'hA1 && byte_count == 1) begin
                                // Second sync byte confirmed
                                byte_count <= 10'd0;
                                state      <= ST_HEADER;
                            end else begin
                                // Not valid sync sequence - go back to hunting
                                state <= ST_HUNT_SYNC;
                            end
                        end
                    end

                    //-----------------------------------------------------
                    ST_HEADER: begin
                        // Read block header byte
                        bit_count <= bit_count + 1'b1;
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

                            // Check for file mark
                            if ({byte_shift[6:0], mfm_data} == BLOCK_FILE_MARK) begin
                                file_mark_detect <= 1'b1;
                            end

                            // Check for segment start (first block)
                            if (block_in_segment == 0) begin
                                segment_start <= 1'b1;
                            end

                            block_start <= 1'b1;
                            state       <= ST_DATA;
                        end
                    end

                    //-----------------------------------------------------
                    ST_DATA: begin
                        // Read 512 data bytes
                        bit_count <= bit_count + 1'b1;
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
                                byte_count <= 10'd0;
                                state      <= ST_ECC;
                            end
                        end
                    end

                    //-----------------------------------------------------
                    ST_ECC: begin
                        // Read ECC bytes (not validated, just consumed)
                        bit_count <= bit_count + 1'b1;
                        byte_shift <= {byte_shift[6:0], mfm_data};

                        if (bit_count == 3'd7) begin
                            bit_count  <= 3'd0;
                            byte_count <= byte_count + 1'b1;

                            if (byte_count >= ECC_BYTES - 1) begin
                                // Block complete
                                block_complete   <= 1'b1;
                                block_in_segment <= block_in_segment + 1'b1;

                                // Check for segment complete
                                if (block_in_segment >= BLOCKS_PER_SEG - 1) begin
                                    segment_complete <= 1'b1;
                                    segment_count    <= segment_count + 1'b1;
                                    block_in_segment <= 5'd0;
                                end

                                byte_count <= 10'd0;
                                state      <= ST_INTER_BLOCK;
                            end
                        end
                    end

                    //-----------------------------------------------------
                    ST_INTER_BLOCK: begin
                        // Brief inter-block gap, then hunt for next sync
                        // In practice, immediately start hunting
                        state <= ST_HUNT_SYNC;
                    end

                    //-----------------------------------------------------
                    default: begin
                        state <= ST_HUNT_SYNC;
                    end
                endcase
            end

            // Sync loss detection - if we're in data/ecc and lose DPLL lock
            if ((state == ST_DATA || state == ST_ECC) && !dpll_locked) begin
                sync_lost   <= 1'b1;
                error_count <= error_count + 1'b1;
                state       <= ST_HUNT_SYNC;
            end
        end
    end

endmodule
