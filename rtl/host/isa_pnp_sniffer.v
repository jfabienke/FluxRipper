//-----------------------------------------------------------------------------
// isa_pnp_sniffer.v
// ISA Plug-and-Play Initiation Key Detector ("Sniffer")
//
// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 FluxRipper Project
//
// Description:
//   Monitors ISA bus for the PnP Initiation Key sequence on port 0x279.
//   This implements the "Sleep-until-Key" strategy for universal compatibility:
//
//   - Card starts in LEGACY ACTIVE mode (responds to default I/O addresses)
//   - Sniffer monitors writes to 0x279 for the 32-byte LFSR initiation key
//   - Upon detecting valid key, card transitions to PnP Configuration mode
//   - If key is never received (non-PnP system), card stays in legacy mode
//
//   PnP Initiation Key (per ISA PnP Spec 1.0a):
//   - 32-byte LFSR sequence starting with 0x6A
//   - LFSR polynomial: x^8 + x^4 + x^3 + x^2 + 1
//   - Sequence: 0x6A, 0xB5, 0xDA, 0xED, 0xF6, 0xFB, 0x7D, 0xBE...
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

module isa_pnp_sniffer (
    input  wire        clk,              // System clock
    input  wire        rst_n,            // Active-low reset

    // ISA Bus Interface (directly from bus)
    input  wire [9:0]  isa_addr,         // I/O address (from SA[9:0])
    input  wire [7:0]  isa_data,         // Data bus (directly from SD[7:0])
    input  wire        isa_iow_n,        // I/O Write strobe (directly active-low)
    input  wire        isa_aen,          // Address Enable (HIGH during DMA)

    // Configuration
    input  wire        sniffer_enable,   // Enable sniffer (disabled in 8-bit mode)
    input  wire        force_legacy,     // Force legacy mode (ignore key)

    // Status outputs
    output reg         pnp_key_detected, // Valid initiation key received
    output reg         pnp_mode_active,  // Card is in PnP configuration mode
    output reg  [4:0]  key_match_count,  // Number of matched bytes (for debug)

    // Control outputs
    output wire        legacy_mode,      // Card should respond to legacy addresses
    output wire        config_mode       // Card is in PnP config mode
);

    //=========================================================================
    // PnP Protocol Constants
    //=========================================================================
    localparam PNP_ADDRESS_PORT = 10'h279;  // Write address port
    localparam KEY_LENGTH       = 32;       // 32-byte initiation key
    localparam LFSR_SEED        = 8'h6A;    // Starting value

    //=========================================================================
    // LFSR Key Generator
    //=========================================================================
    // Generates expected key byte for comparison
    // Polynomial: x^8 + x^4 + x^3 + x^2 + 1 (taps at bits 7,3,2,1)

    reg [7:0]  lfsr_value;
    wire [7:0] lfsr_next;

    // LFSR feedback - MSB is XOR of taps
    wire lfsr_feedback = lfsr_value[7] ^ lfsr_value[3] ^ lfsr_value[2] ^ lfsr_value[1];
    assign lfsr_next = {lfsr_value[6:0], lfsr_feedback};

    //=========================================================================
    // Pre-computed Key Table (for verification)
    //=========================================================================
    // First 8 bytes of the initiation key for quick reference:
    // 0x6A, 0xB5, 0xDA, 0xED, 0xF6, 0xFB, 0x7D, 0xBE,
    // 0x5F, 0x2F, 0x97, 0xCB, 0xE5, 0xF2, 0x79, 0x3C,
    // 0x9E, 0x4F, 0x27, 0x93, 0xC9, 0xE4, 0x72, 0x39,
    // 0x1C, 0x0E, 0x07, 0x83, 0xC1, 0xE0, 0x70, 0x38

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam ST_LEGACY_ACTIVE = 2'd0;  // Normal operation, monitoring for key
    localparam ST_KEY_MATCHING  = 2'd1;  // Receiving key sequence
    localparam ST_PNP_CONFIG    = 2'd2;  // PnP mode active

    reg [1:0]  state;
    reg [4:0]  byte_count;               // Bytes matched (0-31)

    // Edge detection for IOW#
    reg        iow_n_prev;
    wire       iow_falling = iow_n_prev & ~isa_iow_n;

    //=========================================================================
    // Address Decode
    //=========================================================================
    wire addr_is_279 = (isa_addr == PNP_ADDRESS_PORT);
    wire valid_write = addr_is_279 & iow_falling & ~isa_aen;

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_LEGACY_ACTIVE;
            byte_count      <= 5'd0;
            lfsr_value      <= LFSR_SEED;
            pnp_key_detected <= 1'b0;
            pnp_mode_active <= 1'b0;
            key_match_count <= 5'd0;
            iow_n_prev      <= 1'b1;
        end else begin
            iow_n_prev <= isa_iow_n;

            // Force legacy mode override
            if (force_legacy) begin
                state           <= ST_LEGACY_ACTIVE;
                pnp_mode_active <= 1'b0;
                byte_count      <= 5'd0;
                lfsr_value      <= LFSR_SEED;
            end else if (sniffer_enable) begin
                case (state)
                    //=========================================================
                    // Legacy Active: Monitor for first key byte
                    //=========================================================
                    ST_LEGACY_ACTIVE: begin
                        pnp_mode_active <= 1'b0;

                        if (valid_write) begin
                            if (isa_data == LFSR_SEED) begin
                                // First byte matches! Start key sequence
                                state       <= ST_KEY_MATCHING;
                                byte_count  <= 5'd1;
                                lfsr_value  <= lfsr_next;  // Advance to next expected
                                key_match_count <= 5'd1;
                            end
                            // Else: random write to 0x279, ignore
                        end
                    end

                    //=========================================================
                    // Key Matching: Compare subsequent bytes
                    //=========================================================
                    ST_KEY_MATCHING: begin
                        if (valid_write) begin
                            if (isa_data == lfsr_value) begin
                                // Byte matches!
                                byte_count      <= byte_count + 1'b1;
                                lfsr_value      <= lfsr_next;
                                key_match_count <= byte_count + 1'b1;

                                // Check if complete
                                if (byte_count >= (KEY_LENGTH - 1)) begin
                                    // Full 32-byte key received!
                                    state            <= ST_PNP_CONFIG;
                                    pnp_key_detected <= 1'b1;
                                    pnp_mode_active  <= 1'b1;
                                end
                            end else begin
                                // Mismatch - check if it's a new key start
                                if (isa_data == LFSR_SEED) begin
                                    // New key sequence starting
                                    byte_count      <= 5'd1;
                                    lfsr_value      <= lfsr_next;
                                    key_match_count <= 5'd1;
                                end else begin
                                    // Bad byte - reset to legacy monitoring
                                    state           <= ST_LEGACY_ACTIVE;
                                    byte_count      <= 5'd0;
                                    lfsr_value      <= LFSR_SEED;
                                    key_match_count <= 5'd0;
                                end
                            end
                        end
                    end

                    //=========================================================
                    // PnP Config Mode: Key detected, PnP controller takes over
                    //=========================================================
                    ST_PNP_CONFIG: begin
                        pnp_mode_active <= 1'b1;

                        // Monitor for RSTDEV command (Config Control register)
                        // This would return us to Wait-for-Key state
                        // (Handled by isa_pnp_controller.v)
                    end

                    default: begin
                        state <= ST_LEGACY_ACTIVE;
                    end
                endcase
            end else begin
                // Sniffer disabled (8-bit mode) - stay in legacy
                state           <= ST_LEGACY_ACTIVE;
                pnp_mode_active <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Output Logic
    //=========================================================================

    // Legacy mode: respond to default I/O addresses
    // Active when: sniffer disabled, OR in legacy state, OR force_legacy
    assign legacy_mode = ~sniffer_enable | (state == ST_LEGACY_ACTIVE) | force_legacy;

    // Config mode: PnP controller handles configuration
    assign config_mode = pnp_mode_active & ~force_legacy;

    //=========================================================================
    // Return to Legacy (RSTDEV) Interface
    //=========================================================================
    // The PnP controller can signal a return to Wait-for-Key state
    // This is exposed as an input that can reset the sniffer

    // (Would be connected from isa_pnp_controller's rstdev signal)

endmodule
