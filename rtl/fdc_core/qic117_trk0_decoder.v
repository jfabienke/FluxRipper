//==============================================================================
// QIC-117 TRK0 Response Decoder
//==============================================================================
// File: qic117_trk0_decoder.v
// Description: Decodes time-encoded status bits from tape drive TRK0 signal.
//              QIC-117 drives encode status as pulse widths:
//                - Bit 0: TRK0 low for ~500µs
//                - Bit 1: TRK0 low for ~1500µs
//                - Gap between bits: ~1000µs
//
// The decoder measures TRK0 low pulse widths and assembles bytes.
// Used for capturing REPORT_STATUS responses and multi-byte queries
// like REPORT_VENDOR, REPORT_MODEL, etc.
//
// Reference: QIC-117 Revision G, Section 5.3
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module qic117_trk0_decoder #(
    parameter CLK_FREQ_HZ = 200_000_000   // 200 MHz clock
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Control
    //=========================================================================
    input  wire        enable,            // Enable decoder
    input  wire        start_capture,     // Start capturing response
    input  wire [3:0]  expected_bytes,    // Number of bytes to capture (1-8)

    //=========================================================================
    // TRK0 Input
    //=========================================================================
    input  wire        trk0_in,           // TRK0 signal from drive

    //=========================================================================
    // Decoded Output
    //=========================================================================
    output reg  [63:0] response_data,     // Up to 8 bytes of response
    output reg  [3:0]  bytes_received,    // Number of bytes captured
    output reg         capture_complete,  // All expected bytes received
    output reg         capture_error,     // Timing error detected
    output reg         capture_active,    // Currently capturing

    //=========================================================================
    // Debug
    //=========================================================================
    output reg  [2:0]  bit_count,         // Bits in current byte
    output reg  [19:0] pulse_width        // Last measured pulse width (clocks)
);

    //=========================================================================
    // Timing Constants
    //=========================================================================
    // QIC-117 timing tolerances (nominal ±20%)

    // Bit 0: 500µs low pulse
    localparam BIT0_MIN_US = 350;         // 500 - 30%
    localparam BIT0_MAX_US = 750;         // 500 + 50%

    // Bit 1: 1500µs low pulse
    localparam BIT1_MIN_US = 1050;        // 1500 - 30%
    localparam BIT1_MAX_US = 2000;        // 1500 + 33%

    // Gap: 1000µs high between bits
    localparam GAP_MIN_US  = 500;         // Minimum gap to detect end of bit
    localparam GAP_MAX_US  = 2000;        // Maximum before timeout

    // Timeout: No activity for 5ms means response complete/error
    localparam TIMEOUT_US  = 5000;

    // Convert to clock cycles
    localparam CLKS_PER_US = CLK_FREQ_HZ / 1_000_000;

    localparam BIT0_MIN_CLKS = BIT0_MIN_US * CLKS_PER_US;
    localparam BIT0_MAX_CLKS = BIT0_MAX_US * CLKS_PER_US;
    localparam BIT1_MIN_CLKS = BIT1_MIN_US * CLKS_PER_US;
    localparam BIT1_MAX_CLKS = BIT1_MAX_US * CLKS_PER_US;
    localparam GAP_MIN_CLKS  = GAP_MIN_US * CLKS_PER_US;
    localparam TIMEOUT_CLKS  = TIMEOUT_US * CLKS_PER_US;

    // Counter width
    localparam COUNTER_WIDTH = $clog2(TIMEOUT_CLKS + 1);

    //=========================================================================
    // TRK0 Edge Detection
    //=========================================================================
    reg [2:0] trk0_sync;                  // Synchronizer chain
    reg       trk0_prev;
    wire      trk0_falling;
    wire      trk0_rising;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            trk0_sync <= 3'b111;          // TRK0 idle high
            trk0_prev <= 1'b1;
        end else begin
            trk0_sync <= {trk0_sync[1:0], trk0_in};
            trk0_prev <= trk0_sync[2];
        end
    end

    assign trk0_falling = trk0_prev && !trk0_sync[2];
    assign trk0_rising  = !trk0_prev && trk0_sync[2];

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [2:0] ST_IDLE        = 3'd0;  // Waiting to start
    localparam [2:0] ST_WAIT_LOW    = 3'd1;  // Waiting for TRK0 to go low
    localparam [2:0] ST_MEASURE_LOW = 3'd2;  // Measuring low pulse width
    localparam [2:0] ST_WAIT_HIGH   = 3'd3;  // Waiting for gap (high)
    localparam [2:0] ST_DONE        = 3'd4;  // Capture complete
    localparam [2:0] ST_ERROR       = 3'd5;  // Error state

    reg [2:0] state;

    //=========================================================================
    // Counters and Registers
    //=========================================================================
    reg [COUNTER_WIDTH-1:0] timer;        // Pulse/gap/timeout timer
    reg [7:0]  shift_reg;                 // Current byte being assembled
    reg [3:0]  target_bytes;              // How many bytes to capture

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= ST_IDLE;
            response_data    <= 64'd0;
            bytes_received   <= 4'd0;
            capture_complete <= 1'b0;
            capture_error    <= 1'b0;
            capture_active   <= 1'b0;
            bit_count        <= 3'd0;
            pulse_width      <= 20'd0;
            timer            <= 0;
            shift_reg        <= 8'd0;
            target_bytes     <= 4'd1;
        end else if (!enable) begin
            state            <= ST_IDLE;
            capture_active   <= 1'b0;
            capture_complete <= 1'b0;
            capture_error    <= 1'b0;
        end else begin
            // Default: clear single-cycle flags
            capture_complete <= 1'b0;
            capture_error    <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    capture_active <= 1'b0;

                    if (start_capture) begin
                        // Initialize for new capture
                        response_data  <= 64'd0;
                        bytes_received <= 4'd0;
                        bit_count      <= 3'd0;
                        shift_reg      <= 8'd0;
                        target_bytes   <= (expected_bytes == 0) ? 4'd1 : expected_bytes;
                        timer          <= 0;
                        capture_active <= 1'b1;
                        state          <= ST_WAIT_LOW;
                    end
                end

                //-------------------------------------------------------------
                ST_WAIT_LOW: begin
                    // Wait for TRK0 to go low (start of bit)
                    timer <= timer + 1'b1;

                    if (trk0_falling) begin
                        // Start measuring low pulse
                        timer <= 0;
                        state <= ST_MEASURE_LOW;
                    end else if (timer >= TIMEOUT_CLKS) begin
                        // Timeout - no more bits coming
                        if (bytes_received >= target_bytes) begin
                            // Got all expected bytes
                            capture_complete <= 1'b1;
                            state <= ST_DONE;
                        end else if (bytes_received > 0 && bit_count == 0) begin
                            // Got some complete bytes, acceptable
                            capture_complete <= 1'b1;
                            state <= ST_DONE;
                        end else begin
                            // Incomplete response
                            capture_error <= 1'b1;
                            state <= ST_ERROR;
                        end
                    end
                end

                //-------------------------------------------------------------
                ST_MEASURE_LOW: begin
                    // Measure how long TRK0 stays low
                    timer <= timer + 1'b1;

                    if (trk0_rising) begin
                        // End of low pulse - decode bit value
                        pulse_width <= timer[19:0];

                        if (timer >= BIT0_MIN_CLKS && timer <= BIT0_MAX_CLKS) begin
                            // Bit = 0
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            bit_count <= bit_count + 1'b1;
                            timer     <= 0;
                            state     <= ST_WAIT_HIGH;
                        end else if (timer >= BIT1_MIN_CLKS && timer <= BIT1_MAX_CLKS) begin
                            // Bit = 1
                            shift_reg <= {shift_reg[6:0], 1'b1};
                            bit_count <= bit_count + 1'b1;
                            timer     <= 0;
                            state     <= ST_WAIT_HIGH;
                        end else begin
                            // Invalid pulse width
                            capture_error <= 1'b1;
                            state <= ST_ERROR;
                        end
                    end else if (timer >= BIT1_MAX_CLKS + GAP_MIN_CLKS) begin
                        // Stuck low too long - error
                        capture_error <= 1'b1;
                        state <= ST_ERROR;
                    end
                end

                //-------------------------------------------------------------
                ST_WAIT_HIGH: begin
                    // In gap between bits, check if byte complete
                    timer <= timer + 1'b1;

                    if (bit_count >= 3'd8) begin
                        // Byte complete - store it
                        case (bytes_received)
                            4'd0: response_data[7:0]   <= shift_reg;
                            4'd1: response_data[15:8]  <= shift_reg;
                            4'd2: response_data[23:16] <= shift_reg;
                            4'd3: response_data[31:24] <= shift_reg;
                            4'd4: response_data[39:32] <= shift_reg;
                            4'd5: response_data[47:40] <= shift_reg;
                            4'd6: response_data[55:48] <= shift_reg;
                            4'd7: response_data[63:56] <= shift_reg;
                        endcase

                        bytes_received <= bytes_received + 1'b1;
                        bit_count      <= 3'd0;
                        shift_reg      <= 8'd0;

                        // Check if done
                        if (bytes_received + 1'b1 >= target_bytes) begin
                            capture_complete <= 1'b1;
                            state <= ST_DONE;
                        end else begin
                            // Wait for next bit
                            timer <= 0;
                            state <= ST_WAIT_LOW;
                        end
                    end else if (trk0_falling) begin
                        // Next bit starting
                        timer <= 0;
                        state <= ST_MEASURE_LOW;
                    end else if (timer >= TIMEOUT_CLKS) begin
                        // Timeout in middle of byte - partial data
                        if (bytes_received > 0) begin
                            // Some data captured
                            capture_complete <= 1'b1;
                            state <= ST_DONE;
                        end else begin
                            capture_error <= 1'b1;
                            state <= ST_ERROR;
                        end
                    end
                end

                //-------------------------------------------------------------
                ST_DONE: begin
                    capture_active <= 1'b0;
                    // Stay here until new capture started
                    if (start_capture) begin
                        state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                ST_ERROR: begin
                    capture_active <= 1'b0;
                    // Stay here until new capture started
                    if (start_capture) begin
                        state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
