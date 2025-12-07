// SPDX-License-Identifier: MIT
//-----------------------------------------------------------------------------
// usb_hs_negotiator.v - USB 2.0 High-Speed Detection and Bus Reset Handler
//
// Part of FluxRipper - Open-source floppy disk preservation tool
// Copyright (c) 2025 John Fabienke
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Created: 2025-12-06 21:00:00
//
// Description:
//   Implements USB 2.0 High-Speed detection handshake per USB 2.0 spec 7.1.7.5.
//   Handles bus reset detection and chirp sequence for HS negotiation.
//
// USB 2.0 HS Detection Handshake (from spec):
//   1. Host asserts SE0 (bus reset) for >= 2.5µs
//   2. Device detects reset, asserts Chirp K for 1-7ms
//   3. Host responds with alternating K-J chirps (40-60µs each)
//   4. Device counts K-J pairs; >= 3 pairs = enter HS mode
//   5. If no valid chirps from host, remain in FS mode
//
// Line State Encoding (UTMI):
//   2'b00 = SE0 (both lines low)
//   2'b01 = J state (FS idle, or HS K chirp)
//   2'b10 = K state (HS J chirp in device mode)
//   2'b11 = SE1 (illegal)
//
//-----------------------------------------------------------------------------

module usb_hs_negotiator (
    input  wire        clk,             // 60 MHz ULPI clock
    input  wire        rst_n,           // Active-low reset

    // Configuration
    input  wire        enable,          // Enable HS negotiation
    input  wire        force_fs,        // Force Full-Speed only

    // UTMI Status
    input  wire [1:0]  line_state,      // Current USB line state
    input  wire        rx_active,       // PHY receiving data

    // UTMI Control (directly drive these during chirp)
    output reg  [1:0]  xcvr_select,     // 00=HS, 01=FS, 10=LS
    output reg         term_select,     // 0=HS term, 1=FS term
    output reg  [1:0]  op_mode,         // 00=normal, 01=non-driving, 10=disable bit stuff
    output reg         tx_valid,        // Transmit data valid
    output wire [7:0]  tx_data,         // Transmit data (0x00 for chirp)

    // Status outputs
    output reg         bus_reset,       // Bus reset detected
    output reg         hs_enabled,      // Operating in High-Speed mode
    output reg         chirp_complete,  // HS negotiation done
    output reg         suspended        // Bus suspend detected
);

    //=========================================================================
    // Timing Constants (60 MHz clock = 16.67ns period)
    //=========================================================================
    // USB 2.0 spec timing requirements:
    localparam TICKS_2P5_US   = 150;      // 2.5µs for reset detect (150 @ 60MHz)
    localparam TICKS_3_MS     = 180000;   // 3ms chirp K duration
    localparam TICKS_40_US    = 2400;     // 40µs minimum chirp duration
    localparam TICKS_60_US    = 3600;     // 60µs maximum chirp duration
    localparam TICKS_2_MS     = 120000;   // 2ms chirp timeout
    localparam TICKS_3_MS_MAX = 180000;   // 3ms suspend threshold
    localparam TICKS_100_US   = 6000;     // 100µs debounce

    // Counter widths
    localparam CNT_WIDTH = 18;  // Enough for 3ms @ 60MHz

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [3:0] ST_DISCONNECTED  = 4'd0;   // No VBUS / waiting
    localparam [3:0] ST_ATTACHED      = 4'd1;   // Attached, FS mode
    localparam [3:0] ST_WAIT_RESET    = 4'd2;   // Waiting for SE0 (reset)
    localparam [3:0] ST_RESET_DETECT  = 4'd3;   // SE0 seen, timing 2.5µs
    localparam [3:0] ST_SEND_CHIRP_K  = 4'd4;   // Sending device chirp K
    localparam [3:0] ST_WAIT_HOST_K   = 4'd5;   // Waiting for host chirp K
    localparam [3:0] ST_HOST_CHIRP_K  = 4'd6;   // In host chirp K
    localparam [3:0] ST_HOST_CHIRP_J  = 4'd7;   // In host chirp J
    localparam [3:0] ST_HS_MODE       = 4'd8;   // Operating in HS
    localparam [3:0] ST_FS_MODE       = 4'd9;   // Operating in FS
    localparam [3:0] ST_SUSPEND       = 4'd10;  // Suspended

    reg [3:0] state, next_state;

    //=========================================================================
    // Line State Definitions
    //=========================================================================
    localparam [1:0] SE0 = 2'b00;   // Single-ended zero
    localparam [1:0] J   = 2'b01;   // J state (D+ high in FS)
    localparam [1:0] K   = 2'b10;   // K state (D- high in FS)
    localparam [1:0] SE1 = 2'b11;   // Illegal state

    //=========================================================================
    // Internal Signals
    //=========================================================================
    reg [CNT_WIDTH-1:0] timer;
    reg [2:0]           kj_pair_count;  // Count of valid K-J pairs from host
    reg                 chirp_k_done;   // Device chirp K complete
    reg [1:0]           line_state_r;   // Registered line state
    reg [1:0]           line_state_rr;  // Double-registered for metastability

    // Chirp data is always 0x00
    assign tx_data = 8'h00;

    //=========================================================================
    // Line State Synchronization
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_state_r  <= J;  // Idle is J
            line_state_rr <= J;
        end else begin
            line_state_r  <= line_state;
            line_state_rr <= line_state_r;
        end
    end

    //=========================================================================
    // State Machine - Sequential
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_DISCONNECTED;
        end else begin
            state <= next_state;
        end
    end

    //=========================================================================
    // State Machine - Combinational
    //=========================================================================
    always @(*) begin
        next_state = state;

        case (state)
            ST_DISCONNECTED: begin
                // Wait for attachment (J state = FS idle)
                if (enable && line_state_rr == J)
                    next_state = ST_ATTACHED;
            end

            ST_ATTACHED: begin
                // Wait for bus reset (SE0)
                if (line_state_rr == SE0)
                    next_state = ST_RESET_DETECT;
                else if (!enable)
                    next_state = ST_DISCONNECTED;
            end

            ST_RESET_DETECT: begin
                // Time SE0 for 2.5µs minimum
                if (line_state_rr != SE0)
                    next_state = ST_ATTACHED;  // Glitch, go back
                else if (timer >= TICKS_2P5_US) begin
                    if (force_fs)
                        next_state = ST_FS_MODE;  // Skip HS negotiation
                    else
                        next_state = ST_SEND_CHIRP_K;
                end
            end

            ST_SEND_CHIRP_K: begin
                // Send chirp K for ~3ms
                if (timer >= TICKS_3_MS)
                    next_state = ST_WAIT_HOST_K;
                else if (line_state_rr != SE0 && !chirp_k_done)
                    next_state = ST_FS_MODE;  // Reset ended early, stay FS
            end

            ST_WAIT_HOST_K: begin
                // Wait for host to start chirping (K state)
                if (line_state_rr == K)
                    next_state = ST_HOST_CHIRP_K;
                else if (timer >= TICKS_2_MS)
                    next_state = ST_FS_MODE;  // Timeout, no HS host
            end

            ST_HOST_CHIRP_K: begin
                // In host K chirp, wait for transition to J
                if (line_state_rr == J) begin
                    next_state = ST_HOST_CHIRP_J;
                end else if (line_state_rr == SE0) begin
                    // Check if we have enough K-J pairs
                    if (kj_pair_count >= 3)
                        next_state = ST_HS_MODE;
                    else
                        next_state = ST_FS_MODE;
                end else if (timer >= TICKS_100_US) begin
                    next_state = ST_FS_MODE;  // Chirp too long
                end
            end

            ST_HOST_CHIRP_J: begin
                // In host J chirp, wait for transition to K or SE0
                if (line_state_rr == K)
                    next_state = ST_HOST_CHIRP_K;
                else if (line_state_rr == SE0) begin
                    if (kj_pair_count >= 3)
                        next_state = ST_HS_MODE;
                    else
                        next_state = ST_FS_MODE;
                end else if (timer >= TICKS_100_US) begin
                    next_state = ST_FS_MODE;  // Chirp too long
                end
            end

            ST_HS_MODE: begin
                // Operating in High-Speed
                if (line_state_rr == SE0 && timer >= TICKS_2P5_US)
                    next_state = ST_RESET_DETECT;  // New reset
                else if (!enable)
                    next_state = ST_DISCONNECTED;
            end

            ST_FS_MODE: begin
                // Operating in Full-Speed
                if (line_state_rr == SE0 && timer >= TICKS_2P5_US)
                    next_state = ST_RESET_DETECT;  // New reset
                else if (!enable)
                    next_state = ST_DISCONNECTED;
            end

            ST_SUSPEND: begin
                // Suspended state (idle > 3ms)
                if (line_state_rr != J)
                    next_state = hs_enabled ? ST_HS_MODE : ST_FS_MODE;
            end

            default: next_state = ST_DISCONNECTED;
        endcase
    end

    //=========================================================================
    // Timer and Counters
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer         <= 0;
            kj_pair_count <= 0;
            chirp_k_done  <= 0;
        end else begin
            // Timer management
            case (state)
                ST_RESET_DETECT,
                ST_SEND_CHIRP_K,
                ST_WAIT_HOST_K,
                ST_HOST_CHIRP_K,
                ST_HOST_CHIRP_J,
                ST_HS_MODE,
                ST_FS_MODE: begin
                    if (state != next_state)
                        timer <= 0;  // Reset on state change
                    else
                        timer <= timer + 1;
                end
                default: timer <= 0;
            endcase

            // K-J pair counter
            if (state == ST_SEND_CHIRP_K || state == ST_WAIT_HOST_K) begin
                kj_pair_count <= 0;
            end else if (state == ST_HOST_CHIRP_J && next_state == ST_HOST_CHIRP_K) begin
                // Completed one K-J pair
                kj_pair_count <= kj_pair_count + 1;
            end

            // Chirp K done flag
            if (state == ST_SEND_CHIRP_K && timer >= TICKS_3_MS)
                chirp_k_done <= 1;
            else if (state == ST_ATTACHED || state == ST_DISCONNECTED)
                chirp_k_done <= 0;
        end
    end

    //=========================================================================
    // Output Generation
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xcvr_select    <= 2'b01;  // FS
            term_select    <= 1'b1;   // FS termination
            op_mode        <= 2'b01;  // Non-driving
            tx_valid       <= 1'b0;
            bus_reset      <= 1'b0;
            hs_enabled     <= 1'b0;
            chirp_complete <= 1'b0;
            suspended      <= 1'b0;
        end else begin
            // Defaults
            tx_valid       <= 1'b0;
            bus_reset      <= 1'b0;

            case (state)
                ST_DISCONNECTED: begin
                    xcvr_select    <= 2'b01;  // FS
                    term_select    <= 1'b1;   // FS termination
                    op_mode        <= 2'b01;  // Non-driving
                    hs_enabled     <= 1'b0;
                    chirp_complete <= 1'b0;
                    suspended      <= 1'b0;
                end

                ST_ATTACHED: begin
                    xcvr_select    <= 2'b01;  // FS
                    term_select    <= 1'b1;   // FS termination
                    op_mode        <= 2'b00;  // Normal
                    hs_enabled     <= 1'b0;
                    chirp_complete <= 1'b0;
                end

                ST_RESET_DETECT: begin
                    bus_reset      <= 1'b1;
                    chirp_complete <= 1'b0;
                end

                ST_SEND_CHIRP_K: begin
                    // Configure for chirp: HS transceiver, no bit stuffing
                    xcvr_select <= 2'b00;     // HS transceiver
                    term_select <= 1'b0;      // HS termination
                    op_mode     <= 2'b10;     // Disable bit stuff/NRZI
                    tx_valid    <= 1'b1;      // Transmit chirp K
                    bus_reset   <= 1'b1;
                end

                ST_WAIT_HOST_K,
                ST_HOST_CHIRP_K,
                ST_HOST_CHIRP_J: begin
                    // Waiting for host chirps
                    xcvr_select <= 2'b00;     // HS transceiver
                    term_select <= 1'b0;      // HS termination
                    op_mode     <= 2'b00;     // Normal (receiving)
                    tx_valid    <= 1'b0;
                    bus_reset   <= 1'b1;
                end

                ST_HS_MODE: begin
                    xcvr_select    <= 2'b00;  // HS
                    term_select    <= 1'b0;   // HS termination
                    op_mode        <= 2'b00;  // Normal
                    hs_enabled     <= 1'b1;
                    chirp_complete <= 1'b1;
                    suspended      <= 1'b0;
                end

                ST_FS_MODE: begin
                    xcvr_select    <= 2'b01;  // FS
                    term_select    <= 1'b1;   // FS termination
                    op_mode        <= 2'b00;  // Normal
                    hs_enabled     <= 1'b0;
                    chirp_complete <= 1'b1;
                    suspended      <= 1'b0;
                end

                ST_SUSPEND: begin
                    op_mode   <= 2'b01;       // Non-driving
                    suspended <= 1'b1;
                end
            endcase
        end
    end

endmodule
