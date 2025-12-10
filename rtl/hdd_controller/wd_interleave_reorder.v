//==============================================================================
// WD Controller Interleave Reorder Engine
//==============================================================================
// File: wd_interleave_reorder.v
// Description: Reorders sectors from logical to physical order for write-back.
//              Given a track buffer with sectors in logical order (1,2,3...),
//              outputs them in the correct physical order based on interleave.
//
// Operation:
//   1. Host writes sectors to track buffer in logical order (1, 2, 3, ...)
//   2. When flushing to disk, this module provides sector addresses
//      in the physical write order based on the interleave factor.
//
// For interleave I and N sectors:
//   Physical slot 0 -> Logical sector 1
//   Physical slot 1 -> Logical sector (1 + I - 1) mod N + 1 = I mod N + 1
//   Physical slot n -> Logical sector (n * I) mod N + 1
//
// Example (3:1 interleave, 17 sectors):
//   Slot 0: Sector 1   (0*3 mod 17 + 1 = 1)
//   Slot 1: Sector 4   (1*3 mod 17 + 1 = 4)
//   Slot 2: Sector 7   (2*3 mod 17 + 1 = 7)
//   ...
//   Slot 16: Sector 15 (16*3 mod 17 + 1 = 15)
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-09
//==============================================================================

`timescale 1ns / 1ps

module wd_interleave_reorder #(
    parameter MAX_SECTORS = 36     // Maximum sectors per track (ESDI)
)(
    input  wire        clk,
    input  wire        reset_n,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        start,             // Start reorder sequence
    input  wire        next_sector,       // Advance to next physical slot
    output reg         done,              // All sectors processed
    output reg         ready,             // Current sector address valid

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    input  wire [7:0]  sectors_per_track, // Total sectors (17, 26, 32, etc.)
    input  wire [3:0]  interleave,        // Interleave factor (1-8)
    input  wire        use_interleave,    // 1 = apply interleave, 0 = sequential

    //-------------------------------------------------------------------------
    // Output: Logical Sector for Current Physical Slot
    //-------------------------------------------------------------------------
    output reg  [7:0]  logical_sector,    // Logical sector number (1-based)
    output reg  [5:0]  physical_slot      // Current physical slot (0-based)
);

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [1:0] ST_IDLE     = 2'd0;
    localparam [1:0] ST_ACTIVE   = 2'd1;
    localparam [1:0] ST_DONE     = 2'd2;

    reg [1:0] state;

    //=========================================================================
    // Interleave Calculation
    //=========================================================================
    // For physical slot P, logical sector = (P * interleave) mod sectors + 1
    //
    // We use iterative calculation to avoid expensive modulo:
    // Starting at sector 1, each step adds interleave (with wrap).

    reg [7:0] current_logical;   // Current logical sector (1-based)
    reg [7:0] interleave_8;      // Interleave extended to 8 bits

    //=========================================================================
    // Main FSM
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state          <= ST_IDLE;
            done           <= 1'b0;
            ready          <= 1'b0;
            logical_sector <= 8'd1;
            physical_slot  <= 6'd0;
            current_logical <= 8'd1;
            interleave_8   <= 8'd1;
        end else begin
            // Default: clear single-cycle signals
            done <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    ready <= 1'b0;
                    if (start) begin
                        physical_slot   <= 6'd0;
                        current_logical <= 8'd1;  // Start at sector 1
                        interleave_8    <= use_interleave ? {4'h0, interleave} : 8'd1;

                        // First sector is always logical sector 1
                        logical_sector <= 8'd1;
                        ready          <= 1'b1;
                        state          <= ST_ACTIVE;
                    end
                end

                //-------------------------------------------------------------
                ST_ACTIVE: begin
                    if (next_sector) begin
                        // Advance to next physical slot
                        physical_slot <= physical_slot + 1'b1;

                        if (physical_slot + 1 >= sectors_per_track[5:0]) begin
                            // All sectors processed
                            ready <= 1'b0;
                            done  <= 1'b1;
                            state <= ST_DONE;
                        end else begin
                            // Calculate next logical sector
                            // next = (current + interleave - 1) mod sectors + 1
                            // Simplified: next = current + interleave, wrap if > sectors

                            reg [7:0] next_logical;
                            next_logical = current_logical + interleave_8;

                            // Handle wrap-around
                            if (next_logical > sectors_per_track) begin
                                next_logical = next_logical - sectors_per_track;
                            end

                            current_logical <= next_logical;
                            logical_sector  <= next_logical;
                            ready           <= 1'b1;
                        end
                    end
                end

                //-------------------------------------------------------------
                ST_DONE: begin
                    // Wait for next start
                    if (start) begin
                        physical_slot   <= 6'd0;
                        current_logical <= 8'd1;
                        interleave_8    <= use_interleave ? {4'h0, interleave} : 8'd1;
                        logical_sector  <= 8'd1;
                        ready           <= 1'b1;
                        state           <= ST_ACTIVE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    //=========================================================================
    // Buffer Address Calculation (combinational)
    //=========================================================================
    // Given logical_sector, calculate byte offset in track buffer
    // Offset = (logical_sector - 1) * 512
    wire [13:0] buffer_byte_offset;
    assign buffer_byte_offset = ({6'b0, logical_sector} - 1) * 512;

endmodule
