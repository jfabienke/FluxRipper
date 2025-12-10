//-----------------------------------------------------------------------------
// isa_slot_detect.v
// ISA Slot Width Detection using C18 Pin Sensing
//
// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 FluxRipper Project
//
// Description:
//   Detects whether the card is inserted in an 8-bit (XT) or 16-bit (AT) slot
//   using the "C18 Method" - passive sensing of a ground pin.
//
//   PCB Requirements:
//   - Pin C18 (normally GND on AT slots) must NOT connect to ground plane
//   - C18 routed as discrete trace to FPGA I/O with 10k pull-up to 3.3V
//
//   Truth Table:
//   - 8-bit slot: C18 floats, pull-up makes it HIGH -> XT mode
//   - 16-bit slot: C18 grounded by slot contact -> AT mode
//
//   The detection is latched at power-up with debounce to avoid glitches
//   during insertion. Once latched, the mode is stable until reset.
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

module isa_slot_detect #(
    parameter DEBOUNCE_CYCLES = 1000,    // Debounce period (clk cycles)
    parameter SAMPLE_COUNT    = 8        // Number of consistent samples required
) (
    input  wire        clk,              // System clock
    input  wire        rst_n,            // Active-low reset

    // Physical sense input (directly from C18 pin via pull-up)
    input  wire        slot_sense_n,     // LOW = 16-bit, HIGH = 8-bit

    // Flash configuration override
    input  wire [1:0]  force_mode,       // 00=AUTO, 01=FORCE_8BIT, 10=FORCE_16BIT

    // Detection outputs (active after detection_valid)
    output reg         detection_valid,  // Detection complete, outputs stable
    output reg         is_8bit_slot,     // HIGH = 8-bit XT slot
    output reg         is_16bit_slot,    // HIGH = 16-bit AT slot

    // Bus width control outputs
    output wire        enable_high_byte, // Enable D8-D15 transceivers
    output wire        use_xt_mode       // Use XT register map / Option ROM
);

    //=========================================================================
    // Force Mode Encoding
    //=========================================================================
    localparam FORCE_AUTO    = 2'b00;
    localparam FORCE_8BIT    = 2'b01;
    localparam FORCE_16BIT   = 2'b10;
    // 2'b11 reserved

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam ST_WAIT_STABLE  = 2'd0;   // Wait for signal to stabilize
    localparam ST_SAMPLING     = 2'd1;   // Sample and count
    localparam ST_LATCHED      = 2'd2;   // Detection complete

    reg [1:0]  state;
    reg [15:0] debounce_cnt;
    reg [3:0]  sample_cnt;
    reg [3:0]  high_count;               // Count of HIGH samples
    reg [3:0]  low_count;                // Count of LOW samples

    // Synchronizer for async input
    reg [2:0]  sense_sync;
    wire       sense_stable;

    //=========================================================================
    // Input Synchronizer (2-stage + metastability filter)
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sense_sync <= 3'b111;        // Default to 8-bit (safe)
        end else begin
            sense_sync <= {sense_sync[1:0], slot_sense_n};
        end
    end

    // Glitch filter - require 3 consistent samples
    assign sense_stable = (sense_sync[2] == sense_sync[1]);

    //=========================================================================
    // Detection State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_WAIT_STABLE;
            debounce_cnt    <= 16'd0;
            sample_cnt      <= 4'd0;
            high_count      <= 4'd0;
            low_count       <= 4'd0;
            detection_valid <= 1'b0;
            is_8bit_slot    <= 1'b1;     // Default safe: 8-bit mode
            is_16bit_slot   <= 1'b0;
        end else begin
            case (state)
                //-------------------------------------------------------------
                // Wait for initial stabilization after power-up
                //-------------------------------------------------------------
                ST_WAIT_STABLE: begin
                    if (debounce_cnt >= DEBOUNCE_CYCLES) begin
                        debounce_cnt <= 16'd0;
                        sample_cnt   <= 4'd0;
                        high_count   <= 4'd0;
                        low_count    <= 4'd0;
                        state        <= ST_SAMPLING;
                    end else begin
                        debounce_cnt <= debounce_cnt + 1'b1;
                    end
                end

                //-------------------------------------------------------------
                // Sample the input multiple times
                //-------------------------------------------------------------
                ST_SAMPLING: begin
                    if (debounce_cnt >= (DEBOUNCE_CYCLES / SAMPLE_COUNT)) begin
                        debounce_cnt <= 16'd0;
                        sample_cnt   <= sample_cnt + 1'b1;

                        // Count this sample
                        if (sense_stable) begin
                            if (sense_sync[2])
                                high_count <= high_count + 1'b1;
                            else
                                low_count <= low_count + 1'b1;
                        end

                        // Check if we have enough samples
                        if (sample_cnt >= (SAMPLE_COUNT - 1)) begin
                            state <= ST_LATCHED;

                            // Determine result based on majority
                            if (high_count > low_count) begin
                                // HIGH = floating = 8-bit XT slot
                                is_8bit_slot  <= 1'b1;
                                is_16bit_slot <= 1'b0;
                            end else begin
                                // LOW = grounded = 16-bit AT slot
                                is_8bit_slot  <= 1'b0;
                                is_16bit_slot <= 1'b1;
                            end

                            detection_valid <= 1'b1;
                        end
                    end else begin
                        debounce_cnt <= debounce_cnt + 1'b1;
                    end
                end

                //-------------------------------------------------------------
                // Detection complete - stay latched until reset
                //-------------------------------------------------------------
                ST_LATCHED: begin
                    // Stay in this state - detection is permanent until reset
                    detection_valid <= 1'b1;
                end

                default: begin
                    state <= ST_WAIT_STABLE;
                end
            endcase
        end
    end

    //=========================================================================
    // Output Logic with Force Mode Override
    //=========================================================================

    // Apply force mode overrides to final outputs
    wire auto_enable_high = is_16bit_slot & detection_valid;
    wire auto_xt_mode     = is_8bit_slot | ~detection_valid;  // Default XT until detected

    assign enable_high_byte = (force_mode == FORCE_AUTO)   ? auto_enable_high :
                              (force_mode == FORCE_8BIT)   ? 1'b0 :
                              (force_mode == FORCE_16BIT)  ? 1'b1 :
                                                             auto_enable_high;

    assign use_xt_mode      = (force_mode == FORCE_AUTO)   ? auto_xt_mode :
                              (force_mode == FORCE_8BIT)   ? 1'b1 :
                              (force_mode == FORCE_16BIT)  ? 1'b0 :
                                                             auto_xt_mode;

endmodule
