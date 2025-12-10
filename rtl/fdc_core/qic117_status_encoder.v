//==============================================================================
// QIC-117 Status Encoder
//==============================================================================
// File: qic117_status_encoder.v
// Description: Encodes QIC-117 drive status as time-encoded pulses on TRK0.
//              The QIC-117 protocol uses pulse width modulation to communicate
//              status bits from drive to host.
//
// Status Bit Encoding:
//   - Bit = 0: TRK0 held low for ~500µs, then high for gap
//   - Bit = 1: TRK0 held low for ~1500µs, then high for gap
//   - Gap between bits: ~1000µs
//
// Status Word (8 bits, MSB first):
//   Bit 7: Drive Ready
//   Bit 6: Error
//   Bit 5: Cartridge Present
//   Bit 4: Write Protected
//   Bit 3: New Cartridge
//   Bit 2: At BOT (Beginning of Tape)
//   Bit 1: At EOT (End of Tape)
//   Bit 0: Reserved
//
// Reference: QIC-117 Revision G, Section 5.3
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module qic117_status_encoder #(
    parameter CLK_FREQ_HZ = 200_000_000   // 200 MHz clock
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Control Interface
    //=========================================================================
    input  wire        enable,            // Enable encoder (tape mode active)
    input  wire        send_status,       // Pulse to start sending full status
    input  wire        send_next_bit,     // Pulse to send next bit only

    //=========================================================================
    // Status Inputs
    //=========================================================================
    input  wire        stat_ready,        // Drive ready
    input  wire        stat_error,        // Error condition
    input  wire        stat_cartridge,    // Cartridge present
    input  wire        stat_write_prot,   // Write protected
    input  wire        stat_new_cart,     // New cartridge detected
    input  wire        stat_at_bot,       // At beginning of tape
    input  wire        stat_at_eot,       // At end of tape

    //=========================================================================
    // Output
    //=========================================================================
    output reg         trk0_out,          // TRK0 output (directly to drive interface)
    output reg         busy,              // Currently sending status

    //=========================================================================
    // Debug
    //=========================================================================
    output wire [3:0]  current_bit,       // Bit currently being sent (0-7)
    output wire [7:0]  status_word        // Current status word
);

    //=========================================================================
    // Timing Constants
    //=========================================================================
    // QIC-117 specifies timing tolerances, these are nominal values

    localparam BIT0_LOW_US   = 500;       // Low time for bit=0 (µs)
    localparam BIT1_LOW_US   = 1500;      // Low time for bit=1 (µs)
    localparam GAP_US        = 1000;      // Gap between bits (µs)
    localparam SETUP_US      = 100;       // Setup time before first bit (µs)

    // Convert to clock cycles
    localparam BIT0_LOW_CLKS  = (CLK_FREQ_HZ / 1_000_000) * BIT0_LOW_US;
    localparam BIT1_LOW_CLKS  = (CLK_FREQ_HZ / 1_000_000) * BIT1_LOW_US;
    localparam GAP_CLKS       = (CLK_FREQ_HZ / 1_000_000) * GAP_US;
    localparam SETUP_CLKS     = (CLK_FREQ_HZ / 1_000_000) * SETUP_US;

    // Timer width
    localparam TIMER_WIDTH = $clog2(BIT1_LOW_CLKS + 1);

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [2:0] ST_IDLE     = 3'd0;  // Idle, TRK0 high
    localparam [2:0] ST_SETUP    = 3'd1;  // Setup time before transmission
    localparam [2:0] ST_BIT_LOW  = 3'd2;  // TRK0 low for bit duration
    localparam [2:0] ST_BIT_GAP  = 3'd3;  // TRK0 high for gap
    localparam [2:0] ST_DONE     = 3'd4;  // Transmission complete

    reg [2:0] state;

    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [7:0]  shift_reg;                 // Status bits to send (MSB first)
    reg [3:0]  bit_count;                 // Bits remaining to send
    reg [3:0]  bit_index;                 // Current bit index (for debug)
    reg        send_all;                  // Sending full status vs single bit

    reg [TIMER_WIDTH-1:0] timer;          // Timing counter

    //=========================================================================
    // Status Word Construction
    //=========================================================================
    assign status_word = {
        stat_ready,       // Bit 7
        stat_error,       // Bit 6
        stat_cartridge,   // Bit 5
        stat_write_prot,  // Bit 4
        stat_new_cart,    // Bit 3
        stat_at_bot,      // Bit 2
        stat_at_eot,      // Bit 1
        1'b0              // Bit 0 (reserved)
    };

    assign current_bit = bit_index;

    //=========================================================================
    // State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= ST_IDLE;
            shift_reg <= 8'd0;
            bit_count <= 4'd0;
            bit_index <= 4'd0;
            send_all  <= 1'b0;
            timer     <= {TIMER_WIDTH{1'b0}};
            trk0_out  <= 1'b1;            // TRK0 idle high
            busy      <= 1'b0;
        end else if (!enable) begin
            // Disabled - reset to idle
            state    <= ST_IDLE;
            trk0_out <= 1'b1;
            busy     <= 1'b0;
        end else begin
            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    trk0_out <= 1'b1;     // TRK0 idle high
                    busy     <= 1'b0;

                    if (send_status) begin
                        // Start sending full 8-bit status
                        shift_reg <= status_word;
                        bit_count <= 4'd8;
                        bit_index <= 4'd0;
                        send_all  <= 1'b1;
                        timer     <= SETUP_CLKS;
                        state     <= ST_SETUP;
                        busy      <= 1'b1;
                    end else if (send_next_bit && bit_count > 0) begin
                        // Continue sending from where we left off
                        timer    <= SETUP_CLKS;
                        state    <= ST_SETUP;
                        busy     <= 1'b1;
                    end
                end

                //-------------------------------------------------------------
                ST_SETUP: begin
                    // Brief setup time, TRK0 still high
                    trk0_out <= 1'b1;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        // Start first/next bit - go low
                        trk0_out <= 1'b0;
                        // Set timer based on current bit value (MSB)
                        timer <= shift_reg[7] ? BIT1_LOW_CLKS : BIT0_LOW_CLKS;
                        state <= ST_BIT_LOW;
                    end
                end

                //-------------------------------------------------------------
                ST_BIT_LOW: begin
                    // TRK0 held low for bit duration
                    trk0_out <= 1'b0;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        // Low period complete, start gap
                        trk0_out <= 1'b1;
                        timer    <= GAP_CLKS;
                        state    <= ST_BIT_GAP;
                    end
                end

                //-------------------------------------------------------------
                ST_BIT_GAP: begin
                    // TRK0 high for inter-bit gap
                    trk0_out <= 1'b1;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        // Gap complete, shift to next bit
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bit_count <= bit_count - 1'b1;
                        bit_index <= bit_index + 1'b1;

                        if (bit_count > 1) begin
                            if (send_all) begin
                                // More bits to send, continue immediately
                                trk0_out <= 1'b0;
                                timer <= shift_reg[6] ? BIT1_LOW_CLKS : BIT0_LOW_CLKS;
                                state <= ST_BIT_LOW;
                            end else begin
                                // Single bit mode - wait for next request
                                state <= ST_DONE;
                            end
                        end else begin
                            // All bits sent
                            state <= ST_DONE;
                        end
                    end
                end

                //-------------------------------------------------------------
                ST_DONE: begin
                    trk0_out <= 1'b1;
                    busy     <= 1'b0;
                    state    <= ST_IDLE;
                end

                //-------------------------------------------------------------
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
