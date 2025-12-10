//==============================================================================
// QIC-117 STEP Pulse Counter
//==============================================================================
// File: qic117_step_counter.v
// Description: Counts STEP pulses from FDC to decode QIC-117 commands.
//              In tape mode, STEP pulses don't move the head; instead,
//              the count of pulses within a timeout window becomes a command.
//
// Protocol:
//   - Each rising edge on step_in increments the pulse counter
//   - After TIMEOUT_MS with no STEP, the count is latched as a command
//   - Counter resets for the next command sequence
//   - Valid commands are 1-48 pulses
//
// Timing:
//   - Minimum inter-pulse gap: ~2.5ms (set by FDC SPECIFY register)
//   - Command timeout: 100ms after last pulse
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module qic117_step_counter #(
    parameter CLK_FREQ_HZ   = 200_000_000,  // 200 MHz FDC clock
    parameter TIMEOUT_MS    = 100,          // Command timeout in ms
    parameter DEBOUNCE_US   = 10            // STEP debounce in µs
)(
    input  wire        clk,
    input  wire        reset_n,

    // Mode control
    input  wire        tape_mode_en,       // 1 = tape mode active

    // STEP input from FDC
    input  wire        step_in,            // Raw STEP signal

    // Command output
    output reg  [5:0]  pulse_count,        // Current pulse count (0-63)
    output reg         command_valid,      // Pulse when command ready
    output reg  [5:0]  latched_command,    // Latched command code

    // Status
    output reg         counting,           // Currently counting pulses
    output wire        timeout_pending     // Timeout timer running
);

    //=========================================================================
    // Timing Constants
    //=========================================================================

    localparam TIMEOUT_CLKS  = (CLK_FREQ_HZ / 1000) * TIMEOUT_MS;   // 100ms timeout
    localparam DEBOUNCE_CLKS = (CLK_FREQ_HZ / 1_000_000) * DEBOUNCE_US;  // Debounce

    // Counter widths
    localparam TIMEOUT_WIDTH  = $clog2(TIMEOUT_CLKS + 1);
    localparam DEBOUNCE_WIDTH = $clog2(DEBOUNCE_CLKS + 1);

    //=========================================================================
    // STEP Edge Detection with Debounce
    //=========================================================================

    reg  [2:0] step_sync;          // Synchronizer chain
    reg        step_debounced;     // Debounced STEP
    reg        step_prev;          // Previous STEP for edge detect
    wire       step_rising;        // Rising edge detected

    reg  [DEBOUNCE_WIDTH-1:0] debounce_cnt;
    reg                       debounce_active;

    // 3-stage synchronizer for async STEP input
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            step_sync <= 3'b000;
        end else begin
            step_sync <= {step_sync[1:0], step_in};
        end
    end

    // Debounce filter
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            step_debounced  <= 1'b0;
            debounce_cnt    <= 0;
            debounce_active <= 1'b0;
        end else begin
            if (step_sync[2] != step_debounced) begin
                // Input changed, start debounce timer
                if (!debounce_active) begin
                    debounce_active <= 1'b1;
                    debounce_cnt    <= 0;
                end else if (debounce_cnt >= DEBOUNCE_CLKS - 1) begin
                    // Debounce complete, accept new value
                    step_debounced  <= step_sync[2];
                    debounce_active <= 1'b0;
                end else begin
                    debounce_cnt <= debounce_cnt + 1'b1;
                end
            end else begin
                // Input stable, reset debounce
                debounce_active <= 1'b0;
                debounce_cnt    <= 0;
            end
        end
    end

    // Edge detection
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            step_prev <= 1'b0;
        end else begin
            step_prev <= step_debounced;
        end
    end

    assign step_rising = step_debounced && !step_prev;

    //=========================================================================
    // Timeout Counter
    //=========================================================================

    reg [TIMEOUT_WIDTH-1:0] timeout_cnt;
    reg                     timeout_running;
    wire                    timeout_expired;

    assign timeout_expired = (timeout_cnt >= TIMEOUT_CLKS - 1);
    assign timeout_pending = timeout_running && !timeout_expired;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            timeout_cnt     <= 0;
            timeout_running <= 1'b0;
        end else if (!tape_mode_en) begin
            // Not in tape mode - reset timeout
            timeout_cnt     <= 0;
            timeout_running <= 1'b0;
        end else if (step_rising && tape_mode_en) begin
            // STEP pulse received - restart timeout
            timeout_cnt     <= 0;
            timeout_running <= 1'b1;
        end else if (timeout_running && !timeout_expired) begin
            // Timeout counting
            timeout_cnt <= timeout_cnt + 1'b1;
        end else if (timeout_expired) begin
            // Timeout occurred - handled by FSM
            timeout_running <= 1'b0;
        end
    end

    //=========================================================================
    // Pulse Counter State Machine
    //=========================================================================

    localparam [1:0] ST_IDLE    = 2'd0;  // Waiting for first pulse
    localparam [1:0] ST_COUNTING = 2'd1; // Counting pulses
    localparam [1:0] ST_LATCH   = 2'd2;  // Latching command
    localparam [1:0] ST_DONE    = 2'd3;  // Command output

    reg [1:0] state;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= ST_IDLE;
            pulse_count     <= 6'd0;
            latched_command <= 6'd0;
            command_valid   <= 1'b0;
            counting        <= 1'b0;
        end else if (!tape_mode_en) begin
            // Not in tape mode - reset everything
            state           <= ST_IDLE;
            pulse_count     <= 6'd0;
            command_valid   <= 1'b0;
            counting        <= 1'b0;
        end else begin
            // Default: clear single-cycle signals
            command_valid <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    counting    <= 1'b0;
                    pulse_count <= 6'd0;

                    if (step_rising) begin
                        // First STEP pulse - start counting
                        pulse_count <= 6'd1;
                        counting    <= 1'b1;
                        state       <= ST_COUNTING;
                    end
                end

                //-------------------------------------------------------------
                ST_COUNTING: begin
                    counting <= 1'b1;

                    if (step_rising) begin
                        // Another STEP pulse
                        if (pulse_count < 6'd63) begin
                            pulse_count <= pulse_count + 1'b1;
                        end
                        // Timeout counter restarted by separate logic
                    end else if (timeout_expired) begin
                        // Timeout - latch the command
                        state <= ST_LATCH;
                    end
                end

                //-------------------------------------------------------------
                ST_LATCH: begin
                    // Latch the pulse count as command
                    latched_command <= pulse_count;
                    command_valid   <= 1'b1;
                    counting        <= 1'b0;
                    state           <= ST_DONE;
                end

                //-------------------------------------------------------------
                ST_DONE: begin
                    // Wait one cycle, then return to idle
                    pulse_count <= 6'd0;
                    state       <= ST_IDLE;
                end

                //-------------------------------------------------------------
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
