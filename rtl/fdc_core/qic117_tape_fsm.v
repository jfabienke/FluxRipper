//==============================================================================
// QIC-117 Tape Position State Machine
//==============================================================================
// File: qic117_tape_fsm.v
// Description: Manages tape position tracking and motion control for QIC-117
//              tape drives. Handles seek, skip, and streaming operations.
//
// Position Model:
//   - Segment: 0 to MAX_SEGMENTS (typically 4095 for QIC-80)
//   - Track: 0 to MAX_TRACKS (varies by tape format)
//   - QIC tapes use serpentine recording (odd tracks are reverse)
//
// Timing Model:
//   - Seek to BOT/EOT: ~30 seconds max
//   - Skip segment: ~100ms per segment
//   - Track change: ~1 second
//
// Reference: QIC-117 Revision G
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module qic117_tape_fsm #(
    parameter CLK_FREQ_HZ   = 200_000_000,  // 200 MHz clock
    parameter MAX_SEGMENTS  = 4095,          // Max segment number
    parameter MAX_TRACKS    = 27             // Max track number (QIC-80)
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Control Interface
    //=========================================================================
    input  wire        enable,             // FSM enabled (tape mode)

    // Command inputs
    input  wire [5:0]  command,            // QIC-117 command code
    input  wire        command_valid,      // Pulse when command ready
    output reg         command_done,       // Pulse when command complete
    output reg         command_error,      // Command failed

    //=========================================================================
    // Position Outputs
    //=========================================================================
    output reg [15:0]  segment,            // Current segment (0-4095)
    output reg [4:0]   track,              // Current track (0-27)
    output reg         direction,          // 0=forward, 1=reverse
    output reg         at_bot,             // At beginning of tape
    output reg         at_eot,             // At end of tape
    output reg         at_file_mark,       // At file mark position

    //=========================================================================
    // Motion Control
    //=========================================================================
    output reg         motor_on,           // Motor running
    output reg         tape_moving,        // Tape in motion
    output reg [1:0]   motion_mode,        // 0=stop, 1=seek, 2=skip, 3=stream

    //=========================================================================
    // External Inputs
    //=========================================================================
    input  wire        index_pulse,        // INDEX from drive (segment marker)
    input  wire        file_mark_detect,   // File mark detected in data stream

    //=========================================================================
    // Status
    //=========================================================================
    output reg [3:0]   fsm_state,          // Current state (debug)
    output reg [31:0]  operation_timer     // Time remaining in operation
);

    //=========================================================================
    // QIC-117 Command Codes (all position/motion related)
    //=========================================================================
    localparam [5:0] CMD_RESET           = 6'd1;
    localparam [5:0] CMD_PAUSE           = 6'd6;   // Pause motion
    localparam [5:0] CMD_SEEK_BOT        = 6'd8;   // Seek to BOT
    localparam [5:0] CMD_SEEK_EOT        = 6'd9;   // Seek to EOT
    localparam [5:0] CMD_SKIP_REV_SEG    = 6'd10;  // Skip 1 segment reverse
    localparam [5:0] CMD_SKIP_REV_FILE   = 6'd11;  // Skip to previous file mark
    localparam [5:0] CMD_SKIP_FWD_SEG    = 6'd12;  // Skip 1 segment forward
    localparam [5:0] CMD_SKIP_FWD_FILE   = 6'd13;  // Skip to next file mark
    localparam [5:0] CMD_SKIP_REV_EXT    = 6'd14;  // Skip N segments reverse
    localparam [5:0] CMD_SKIP_FWD_EXT    = 6'd15;  // Skip N segments forward
    localparam [5:0] CMD_READ_DATA       = 6'd16;  // Start reading data
    localparam [5:0] CMD_WRITE_DATA      = 6'd17;  // Start writing data
    localparam [5:0] CMD_SEEK_TRACK      = 6'd18;  // Seek to track N
    localparam [5:0] CMD_SEEK_SEGMENT    = 6'd19;  // Seek to segment N
    localparam [5:0] CMD_LOGICAL_FWD     = 6'd21;  // Logical forward
    localparam [5:0] CMD_LOGICAL_REV     = 6'd22;  // Logical reverse
    localparam [5:0] CMD_STOP            = 6'd23;  // Stop tape
    localparam [5:0] CMD_RETENSION       = 6'd24;  // Retension tape
    localparam [5:0] CMD_FORMAT          = 6'd25;  // Format tape (low-level)
    localparam [5:0] CMD_VERIFY_FWD      = 6'd26;  // Verify forward
    localparam [5:0] CMD_VERIFY_REV      = 6'd27;  // Verify reverse
    localparam [5:0] CMD_PHYSICAL_FWD    = 6'd30;  // Physical forward
    localparam [5:0] CMD_PHYSICAL_REV    = 6'd31;  // Physical reverse
    localparam [5:0] CMD_EJECT           = 6'd37;  // Eject cartridge

    //=========================================================================
    // Timing Constants
    //=========================================================================
    // All times in clock cycles

    localparam SEEK_BOT_TIME   = CLK_FREQ_HZ * 30;      // 30 seconds max
    localparam SEEK_EOT_TIME   = CLK_FREQ_HZ * 30;      // 30 seconds max
    localparam SKIP_SEG_TIME   = CLK_FREQ_HZ / 10;      // 100ms per segment
    localparam TRACK_CHANGE    = CLK_FREQ_HZ;           // 1 second
    localparam MOTOR_SPINUP    = CLK_FREQ_HZ / 2;       // 500ms motor spinup
    localparam STOP_TIME       = CLK_FREQ_HZ / 4;       // 250ms to stop
    localparam RETENSION_TIME  = CLK_FREQ_HZ * 120;     // 2 minutes for full retension
    localparam EJECT_TIME      = CLK_FREQ_HZ * 2;       // 2 seconds for eject

    // Timer width (needs to hold 120 seconds at 200MHz for retension)
    localparam TIMER_WIDTH = 35;  // ceil(log2(120 * 200M))

    //=========================================================================
    // State Machine States
    //=========================================================================
    localparam [3:0] ST_IDLE          = 4'd0;
    localparam [3:0] ST_MOTOR_SPINUP  = 4'd1;
    localparam [3:0] ST_SEEK_BOT      = 4'd2;
    localparam [3:0] ST_SEEK_EOT      = 4'd3;
    localparam [3:0] ST_SKIP_FWD      = 4'd4;
    localparam [3:0] ST_SKIP_REV      = 4'd5;
    localparam [3:0] ST_SKIP_FILE_FWD = 4'd6;
    localparam [3:0] ST_SKIP_FILE_REV = 4'd7;
    localparam [3:0] ST_STREAMING_FWD = 4'd8;
    localparam [3:0] ST_STREAMING_REV = 4'd9;
    localparam [3:0] ST_STOPPING      = 4'd10;
    localparam [3:0] ST_TRACK_CHANGE  = 4'd11;
    localparam [3:0] ST_ERROR         = 4'd12;
    localparam [3:0] ST_RETENSION_FWD = 4'd13;  // Retension forward pass
    localparam [3:0] ST_RETENSION_REV = 4'd14;  // Retension reverse pass
    localparam [3:0] ST_EJECTING      = 4'd15;  // Ejecting cartridge

    reg [3:0] state;
    reg [3:0] next_state_after_spinup;

    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [TIMER_WIDTH-1:0] timer;
    reg [15:0] target_segment;            // Target for skip operations
    reg        seeking_file;              // Looking for file mark

    // Edge detection for index pulse
    reg index_pulse_prev;
    wire index_rising = index_pulse && !index_pulse_prev;

    //=========================================================================
    // Index Pulse Edge Detection
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            index_pulse_prev <= 1'b0;
        end else begin
            index_pulse_prev <= index_pulse;
        end
    end

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state                <= ST_IDLE;
            next_state_after_spinup <= ST_IDLE;
            segment              <= 16'd0;
            track                <= 5'd0;
            direction            <= 1'b0;
            at_bot               <= 1'b1;
            at_eot               <= 1'b0;
            at_file_mark         <= 1'b0;
            motor_on             <= 1'b0;
            tape_moving          <= 1'b0;
            motion_mode          <= 2'd0;
            command_done         <= 1'b0;
            command_error        <= 1'b0;
            timer                <= {TIMER_WIDTH{1'b0}};
            target_segment       <= 16'd0;
            seeking_file         <= 1'b0;
            fsm_state            <= 4'd0;
            operation_timer      <= 32'd0;
        end else if (!enable) begin
            // Disabled - stop everything
            state       <= ST_IDLE;
            motor_on    <= 1'b0;
            tape_moving <= 1'b0;
            motion_mode <= 2'd0;
        end else begin
            // Default: clear single-cycle signals
            command_done  <= 1'b0;
            command_error <= 1'b0;

            // Update debug outputs
            fsm_state       <= state;
            operation_timer <= timer[31:0];

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    motor_on    <= 1'b0;
                    tape_moving <= 1'b0;
                    motion_mode <= 2'd0;

                    if (command_valid) begin
                        case (command)
                            CMD_RESET: begin
                                // Clear error state, stay at current position
                                command_done <= 1'b1;
                            end

                            CMD_SEEK_BOT: begin
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_SEEK_BOT;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_SEEK_EOT: begin
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_SEEK_EOT;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_SKIP_FWD_SEG: begin
                                if (!at_eot) begin
                                    motor_on       <= 1'b1;
                                    timer          <= MOTOR_SPINUP;
                                    target_segment <= segment + 1'b1;
                                    next_state_after_spinup <= ST_SKIP_FWD;
                                    state          <= ST_MOTOR_SPINUP;
                                end else begin
                                    command_error <= 1'b1;
                                end
                            end

                            CMD_SKIP_REV_SEG: begin
                                if (!at_bot) begin
                                    motor_on       <= 1'b1;
                                    timer          <= MOTOR_SPINUP;
                                    target_segment <= segment - 1'b1;
                                    next_state_after_spinup <= ST_SKIP_REV;
                                    state          <= ST_MOTOR_SPINUP;
                                end else begin
                                    command_error <= 1'b1;
                                end
                            end

                            CMD_SKIP_FWD_FILE: begin
                                motor_on     <= 1'b1;
                                timer        <= MOTOR_SPINUP;
                                seeking_file <= 1'b1;
                                next_state_after_spinup <= ST_SKIP_FILE_FWD;
                                state        <= ST_MOTOR_SPINUP;
                            end

                            CMD_SKIP_REV_FILE: begin
                                motor_on     <= 1'b1;
                                timer        <= MOTOR_SPINUP;
                                seeking_file <= 1'b1;
                                next_state_after_spinup <= ST_SKIP_FILE_REV;
                                state        <= ST_MOTOR_SPINUP;
                            end

                            CMD_LOGICAL_FWD, CMD_PHYSICAL_FWD: begin
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_STREAMING_FWD;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_LOGICAL_REV, CMD_PHYSICAL_REV: begin
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_STREAMING_REV;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_READ_DATA: begin
                                // Read data - same as logical forward but read mode
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_STREAMING_FWD;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_WRITE_DATA: begin
                                // Write data - same as logical forward but write mode
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_STREAMING_FWD;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_VERIFY_FWD: begin
                                // Verify forward - read and verify, same as streaming
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_STREAMING_FWD;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_VERIFY_REV: begin
                                // Verify reverse
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_STREAMING_REV;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_RETENSION: begin
                                // Retension - forward to EOT, then back to BOT
                                motor_on <= 1'b1;
                                timer    <= MOTOR_SPINUP;
                                next_state_after_spinup <= ST_RETENSION_FWD;
                                state    <= ST_MOTOR_SPINUP;
                            end

                            CMD_EJECT: begin
                                // Eject - rewind to BOT first, then eject
                                if (!at_bot) begin
                                    motor_on <= 1'b1;
                                    timer    <= MOTOR_SPINUP;
                                    next_state_after_spinup <= ST_SEEK_BOT;
                                    state    <= ST_MOTOR_SPINUP;
                                    // Note: after ST_SEEK_BOT, we'll need to eject
                                    // For now, just rewind - eject handled separately
                                end else begin
                                    motor_on <= 1'b1;
                                    timer    <= EJECT_TIME;
                                    state    <= ST_EJECTING;
                                end
                            end

                            CMD_STOP: begin
                                // Stop - already idle, just acknowledge
                                command_done <= 1'b1;
                            end

                            default: begin
                                // Unknown command - ignore
                                command_done <= 1'b1;
                            end
                        endcase
                    end
                end

                //-------------------------------------------------------------
                ST_MOTOR_SPINUP: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b0;
                    motion_mode <= 2'd0;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        state <= next_state_after_spinup;
                    end
                end

                //-------------------------------------------------------------
                ST_SEEK_BOT: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b1;  // Reverse
                    motion_mode <= 2'd1;  // Seek mode
                    at_eot      <= 1'b0;

                    // Simulate rewinding - decrement segment on index pulses
                    if (index_rising && segment > 0) begin
                        segment <= segment - 1'b1;
                    end

                    // Check if at BOT
                    if (segment == 0) begin
                        at_bot       <= 1'b1;
                        track        <= 5'd0;
                        timer        <= STOP_TIME;
                        state        <= ST_STOPPING;
                    end

                    // Handle pause/stop commands during operation
                    if (command_valid && (command == CMD_PAUSE || command == CMD_STOP)) begin
                        timer <= STOP_TIME;
                        state <= ST_STOPPING;
                    end
                end

                //-------------------------------------------------------------
                ST_SEEK_EOT: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b0;  // Forward
                    motion_mode <= 2'd1;  // Seek mode
                    at_bot      <= 1'b0;

                    // Simulate fast-forward - increment segment on index pulses
                    if (index_rising && segment < MAX_SEGMENTS) begin
                        segment <= segment + 1'b1;
                    end

                    // Check if at EOT
                    if (segment >= MAX_SEGMENTS) begin
                        at_eot <= 1'b1;
                        timer  <= STOP_TIME;
                        state  <= ST_STOPPING;
                    end

                    // Handle pause/stop commands
                    if (command_valid && (command == CMD_PAUSE || command == CMD_STOP)) begin
                        timer <= STOP_TIME;
                        state <= ST_STOPPING;
                    end
                end

                //-------------------------------------------------------------
                ST_SKIP_FWD: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b0;  // Forward
                    motion_mode <= 2'd2;  // Skip mode
                    at_bot      <= 1'b0;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        // Skip time elapsed - update position
                        segment <= target_segment;
                        if (target_segment >= MAX_SEGMENTS) begin
                            at_eot <= 1'b1;
                        end
                        timer <= STOP_TIME;
                        state <= ST_STOPPING;
                    end
                end

                //-------------------------------------------------------------
                ST_SKIP_REV: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b1;  // Reverse
                    motion_mode <= 2'd2;  // Skip mode
                    at_eot      <= 1'b0;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        // Skip time elapsed - update position
                        segment <= target_segment;
                        if (target_segment == 0) begin
                            at_bot <= 1'b1;
                        end
                        timer <= STOP_TIME;
                        state <= ST_STOPPING;
                    end
                end

                //-------------------------------------------------------------
                ST_SKIP_FILE_FWD: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b0;
                    motion_mode <= 2'd2;
                    at_bot      <= 1'b0;

                    // Increment segment on index
                    if (index_rising && segment < MAX_SEGMENTS) begin
                        segment <= segment + 1'b1;
                    end

                    // Check for file mark
                    if (file_mark_detect) begin
                        at_file_mark <= 1'b1;
                        seeking_file <= 1'b0;
                        timer        <= STOP_TIME;
                        state        <= ST_STOPPING;
                    end else if (segment >= MAX_SEGMENTS) begin
                        // Reached EOT without finding file mark
                        at_eot        <= 1'b1;
                        seeking_file  <= 1'b0;
                        command_error <= 1'b1;
                        timer         <= STOP_TIME;
                        state         <= ST_STOPPING;
                    end

                    // Handle pause/stop
                    if (command_valid && (command == CMD_PAUSE || command == CMD_STOP)) begin
                        seeking_file <= 1'b0;
                        timer        <= STOP_TIME;
                        state        <= ST_STOPPING;
                    end
                end

                //-------------------------------------------------------------
                ST_SKIP_FILE_REV: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b1;
                    motion_mode <= 2'd2;
                    at_eot      <= 1'b0;

                    // Decrement segment on index
                    if (index_rising && segment > 0) begin
                        segment <= segment - 1'b1;
                    end

                    // Check for file mark
                    if (file_mark_detect) begin
                        at_file_mark <= 1'b1;
                        seeking_file <= 1'b0;
                        timer        <= STOP_TIME;
                        state        <= ST_STOPPING;
                    end else if (segment == 0) begin
                        // Reached BOT without finding file mark
                        at_bot        <= 1'b1;
                        seeking_file  <= 1'b0;
                        command_error <= 1'b1;
                        timer         <= STOP_TIME;
                        state         <= ST_STOPPING;
                    end

                    // Handle pause/stop
                    if (command_valid && (command == CMD_PAUSE || command == CMD_STOP)) begin
                        seeking_file <= 1'b0;
                        timer        <= STOP_TIME;
                        state        <= ST_STOPPING;
                    end
                end

                //-------------------------------------------------------------
                ST_STREAMING_FWD: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b0;
                    motion_mode <= 2'd3;  // Stream mode
                    at_bot      <= 1'b0;
                    at_file_mark <= 1'b0;

                    // Track position via index pulses
                    if (index_rising && segment < MAX_SEGMENTS) begin
                        segment <= segment + 1'b1;
                    end

                    // Check for EOT
                    if (segment >= MAX_SEGMENTS) begin
                        at_eot <= 1'b1;
                        // Need to change track (serpentine)
                        if (track < MAX_TRACKS) begin
                            timer <= TRACK_CHANGE;
                            state <= ST_TRACK_CHANGE;
                        end else begin
                            timer <= STOP_TIME;
                            state <= ST_STOPPING;
                        end
                    end

                    // Handle commands during streaming
                    if (command_valid) begin
                        case (command)
                            CMD_PAUSE, CMD_STOP: begin
                                timer <= STOP_TIME;
                                state <= ST_STOPPING;
                            end
                            CMD_LOGICAL_REV, CMD_PHYSICAL_REV: begin
                                // Reverse direction
                                state <= ST_STREAMING_REV;
                            end
                            default: ;
                        endcase
                    end
                end

                //-------------------------------------------------------------
                ST_STREAMING_REV: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b1;
                    motion_mode <= 2'd3;
                    at_eot      <= 1'b0;
                    at_file_mark <= 1'b0;

                    // Track position via index pulses
                    if (index_rising && segment > 0) begin
                        segment <= segment - 1'b1;
                    end

                    // Check for BOT
                    if (segment == 0) begin
                        at_bot <= 1'b1;
                        // Need to change track (serpentine)
                        if (track > 0) begin
                            timer <= TRACK_CHANGE;
                            state <= ST_TRACK_CHANGE;
                        end else begin
                            timer <= STOP_TIME;
                            state <= ST_STOPPING;
                        end
                    end

                    // Handle commands during streaming
                    if (command_valid) begin
                        case (command)
                            CMD_PAUSE, CMD_STOP: begin
                                timer <= STOP_TIME;
                                state <= ST_STOPPING;
                            end
                            CMD_LOGICAL_FWD, CMD_PHYSICAL_FWD: begin
                                state <= ST_STREAMING_FWD;
                            end
                            default: ;
                        endcase
                    end
                end

                //-------------------------------------------------------------
                ST_TRACK_CHANGE: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b0;  // Paused during track change
                    motion_mode <= 2'd1;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        // Complete track change
                        if (direction == 1'b0) begin
                            // Was going forward, now go reverse on next track
                            track     <= track + 1'b1;
                            direction <= 1'b1;
                            at_eot    <= 1'b0;
                            state     <= ST_STREAMING_REV;
                        end else begin
                            // Was going reverse, now go forward on prev track
                            track     <= track - 1'b1;
                            direction <= 1'b0;
                            at_bot    <= 1'b0;
                            state     <= ST_STREAMING_FWD;
                        end
                    end
                end

                //-------------------------------------------------------------
                ST_STOPPING: begin
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b0;
                    motion_mode <= 2'd0;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        motor_on     <= 1'b0;
                        command_done <= 1'b1;
                        state        <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                ST_ERROR: begin
                    motor_on      <= 1'b0;
                    tape_moving   <= 1'b0;
                    motion_mode   <= 2'd0;
                    command_error <= 1'b1;

                    // Wait for reset command
                    if (command_valid && command == CMD_RESET) begin
                        state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                ST_RETENSION_FWD: begin
                    // Retension forward pass - fast forward to EOT
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b0;  // Forward
                    motion_mode <= 2'd1;  // Seek mode (fast)
                    at_bot      <= 1'b0;

                    // Simulate fast-forward
                    if (index_rising && segment < MAX_SEGMENTS) begin
                        segment <= segment + 1'b1;
                    end

                    // Check if at EOT
                    if (segment >= MAX_SEGMENTS) begin
                        at_eot    <= 1'b1;
                        direction <= 1'b1;  // Switch to reverse
                        state     <= ST_RETENSION_REV;
                    end

                    // Handle abort
                    if (command_valid && (command == CMD_PAUSE || command == CMD_STOP)) begin
                        timer <= STOP_TIME;
                        state <= ST_STOPPING;
                    end
                end

                //-------------------------------------------------------------
                ST_RETENSION_REV: begin
                    // Retension reverse pass - rewind to BOT
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b1;
                    direction   <= 1'b1;  // Reverse
                    motion_mode <= 2'd1;  // Seek mode (fast)
                    at_eot      <= 1'b0;

                    // Simulate rewind
                    if (index_rising && segment > 0) begin
                        segment <= segment - 1'b1;
                    end

                    // Check if at BOT - retension complete
                    if (segment == 0) begin
                        at_bot       <= 1'b1;
                        track        <= 5'd0;
                        timer        <= STOP_TIME;
                        state        <= ST_STOPPING;
                    end

                    // Handle abort
                    if (command_valid && (command == CMD_PAUSE || command == CMD_STOP)) begin
                        timer <= STOP_TIME;
                        state <= ST_STOPPING;
                    end
                end

                //-------------------------------------------------------------
                ST_EJECTING: begin
                    // Ejecting cartridge
                    motor_on    <= 1'b1;
                    tape_moving <= 1'b0;
                    motion_mode <= 2'd0;

                    if (timer > 0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        // Eject complete
                        motor_on     <= 1'b0;
                        command_done <= 1'b1;
                        // Note: Real hardware would need cartridge detection
                        // to verify eject completed
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
