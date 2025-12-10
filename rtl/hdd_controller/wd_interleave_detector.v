//==============================================================================
// WD Controller Interleave Detector
//==============================================================================
// File: wd_interleave_detector.v
// Description: Detects sector interleave pattern during track reads.
//              Analyzes the sequence of sector IDs as they appear in the
//              physical layout to determine the interleave factor.
//
// Algorithm:
//   - Record sector ID positions as sectors are encountered
//   - After full track read, calculate interleave from sector 1 & 2 positions
//   - Interleave = (position_of_sector_2 - position_of_sector_1) mod count
//
// Example (3:1 interleave on 17-sector track):
//   Physical order: 1,12,6,17,11,5,16,10,4,15,9,3,14,8,2,13,7
//   Sector 1 at position 0, Sector 2 at position 14
//   Delta = 14, but interleave is actually 3 (inverse relationship)
//   Formula: interleave = (position_2 * inverse_of_position_2) mod 17 = 3
//
// Simplified approach:
//   Track the gap between sector 1 and sector 2 in the physical stream.
//   interleave = gcd-based calculation or lookup table for common patterns.
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-09
//==============================================================================

`timescale 1ns / 1ps

module wd_interleave_detector #(
    parameter MAX_SECTORS = 36     // Maximum sectors per track (ESDI)
)(
    input  wire        clk,
    input  wire        reset_n,

    //-------------------------------------------------------------------------
    // Sector Stream Input
    //-------------------------------------------------------------------------
    input  wire        sector_valid,      // Sector header decoded
    input  wire [7:0]  sector_id,         // Sector ID from header (1-based)
    input  wire        track_start,       // Start of new track
    input  wire        track_complete,    // Track read complete

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    input  wire [7:0]  sectors_per_track, // Expected sectors (17, 26, 32, etc.)

    //-------------------------------------------------------------------------
    // Results
    //-------------------------------------------------------------------------
    output reg  [3:0]  detected_interleave, // Detected interleave (1-8)
    output reg         detection_valid,      // Detection result is valid
    output reg         detection_error       // Inconsistent pattern detected
);

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_COLLECTING = 3'd1;
    localparam [2:0] ST_CALCULATE  = 3'd2;
    localparam [2:0] ST_DONE       = 3'd3;

    reg [2:0] state;

    //=========================================================================
    // Sector Position Tracking
    //=========================================================================
    // Position map: position_of[sector_id] = physical_position
    // We only need to track first few sectors to determine interleave
    reg [5:0] position_of_1;        // Physical position of sector 1
    reg [5:0] position_of_2;        // Physical position of sector 2
    reg       found_sector_1;
    reg       found_sector_2;
    reg [5:0] physical_position;    // Current position counter (0-35)
    reg [5:0] sector_count;         // Number of sectors seen

    //=========================================================================
    // Main FSM
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state              <= ST_IDLE;
            detected_interleave <= 4'd1;  // Default to 1:1
            detection_valid    <= 1'b0;
            detection_error    <= 1'b0;
            position_of_1      <= 6'd0;
            position_of_2      <= 6'd0;
            found_sector_1     <= 1'b0;
            found_sector_2     <= 1'b0;
            physical_position  <= 6'd0;
            sector_count       <= 6'd0;
        end else begin
            // Default: clear single-cycle signals
            detection_valid <= 1'b0;
            detection_error <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    if (track_start) begin
                        // Reset for new track
                        position_of_1     <= 6'd0;
                        position_of_2     <= 6'd0;
                        found_sector_1    <= 1'b0;
                        found_sector_2    <= 1'b0;
                        physical_position <= 6'd0;
                        sector_count      <= 6'd0;
                        state             <= ST_COLLECTING;
                    end
                end

                //-------------------------------------------------------------
                ST_COLLECTING: begin
                    if (sector_valid) begin
                        // Record position of sectors 1 and 2
                        if (sector_id == 8'd1 && !found_sector_1) begin
                            position_of_1  <= physical_position;
                            found_sector_1 <= 1'b1;
                        end
                        if (sector_id == 8'd2 && !found_sector_2) begin
                            position_of_2  <= physical_position;
                            found_sector_2 <= 1'b1;
                        end

                        physical_position <= physical_position + 1'b1;
                        sector_count      <= sector_count + 1'b1;
                    end

                    if (track_complete) begin
                        state <= ST_CALCULATE;
                    end
                end

                //-------------------------------------------------------------
                ST_CALCULATE: begin
                    if (found_sector_1 && found_sector_2 && sector_count >= 2) begin
                        // Calculate interleave from the gap between sectors 1 and 2
                        // The physical distance from sector 1 to sector 2 tells us
                        // how many physical slots we skip between logical sectors.
                        //
                        // For interleave I, sector 2 appears at position:
                        //   pos_2 = (pos_1 + I) mod sectors_per_track
                        //
                        // Therefore: I = (pos_2 - pos_1) mod sectors_per_track

                        reg [5:0] delta;
                        if (position_of_2 >= position_of_1) begin
                            delta = position_of_2 - position_of_1;
                        end else begin
                            // Wrap around case
                            delta = (sectors_per_track[5:0] - position_of_1) + position_of_2;
                        end

                        // Clamp to valid interleave range (1-8)
                        if (delta == 6'd0) begin
                            detected_interleave <= 4'd1;  // Shouldn't happen
                            detection_error     <= 1'b1;
                        end else if (delta > 6'd8) begin
                            // Interleave > 8 is unusual, may indicate detection error
                            // or very high interleave (some XT systems used 6:1)
                            // We'll cap at 8 and flag possible error
                            detected_interleave <= 4'd8;
                            detection_error     <= 1'b1;
                        end else begin
                            detected_interleave <= delta[3:0];
                        end

                        detection_valid <= 1'b1;
                    end else begin
                        // Couldn't find both sectors - error
                        detected_interleave <= 4'd1;  // Default
                        detection_error     <= 1'b1;
                        detection_valid     <= 1'b1;
                    end

                    state <= ST_DONE;
                end

                //-------------------------------------------------------------
                ST_DONE: begin
                    // Wait for next track
                    if (track_start) begin
                        position_of_1     <= 6'd0;
                        position_of_2     <= 6'd0;
                        found_sector_1    <= 1'b0;
                        found_sector_2    <= 1'b0;
                        physical_position <= 6'd0;
                        sector_count      <= 6'd0;
                        state             <= ST_COLLECTING;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
