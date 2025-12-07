//-----------------------------------------------------------------------------
// HDD Seek Controller for FluxRipper ST-506 Interface
//
// Implements SEEK_COMPLETE-based seek control for MFM/RLL/ESDI drives
// Unlike floppy drives (which poll TRACK0), HDDs signal seek completion
// via the SEEK_COMPLETE line.
//
// Features:
//   - Buffered step mode (queue multiple steps)
//   - Variable step rate (3ms to 20ms per step)
//   - Track recalibration (restore to track 0)
//   - Seek timeout detection
//   - Position tracking
//
// Created: 2025-12-03 16:00
//-----------------------------------------------------------------------------

module hdd_seek_controller (
    input  wire        clk,              // System clock (300 MHz HDD domain)
    input  wire        reset_n,

    //-------------------------------------------------------------------------
    // Command Interface
    //-------------------------------------------------------------------------
    input  wire        seek_start,       // Start seek operation
    input  wire [15:0] target_cylinder,  // Target cylinder (0-65535)
    input  wire        recalibrate,      // Restore to track 0
    output reg         seek_busy,        // Seek in progress
    output reg         seek_done,        // Seek complete (pulse)
    output reg         seek_error,       // Seek failed (timeout/fault)

    //-------------------------------------------------------------------------
    // Position Tracking
    //-------------------------------------------------------------------------
    output reg  [15:0] current_cylinder, // Current head position
    output reg         at_track00,       // At cylinder 0

    //-------------------------------------------------------------------------
    // Timing Configuration
    //-------------------------------------------------------------------------
    input  wire [15:0] step_pulse_width, // Step pulse width (clocks)
    input  wire [23:0] step_rate,        // Time between steps (clocks)
    input  wire [23:0] settle_time,      // Head settle time after seek (clocks)
    input  wire [23:0] seek_timeout,     // Maximum seek time (clocks)

    //-------------------------------------------------------------------------
    // ST-506 Interface (directly to st506_interface module)
    //-------------------------------------------------------------------------
    output reg         step_request,     // Request step pulse
    output reg         step_direction,   // 1 = in (higher cyl), 0 = out (lower cyl)
    input  wire        step_done_in,     // Step pulse complete

    // Status from drive
    input  wire        seek_complete,    // Drive signals seek complete
    input  wire        track00,          // At track 0
    input  wire        drive_fault,      // Drive fault detected
    input  wire        drive_ready       // Drive ready
);

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [3:0]
        STATE_IDLE       = 4'd0,
        STATE_WAIT_READY = 4'd1,
        STATE_CALC_STEPS = 4'd2,
        STATE_STEP_OUT   = 4'd3,    // Step toward track 0
        STATE_STEP_IN    = 4'd4,    // Step toward center
        STATE_WAIT_STEP  = 4'd5,    // Wait for step pulse complete
        STATE_WAIT_RATE  = 4'd6,    // Inter-step delay
        STATE_WAIT_SEEK  = 4'd7,    // Wait for SEEK_COMPLETE
        STATE_SETTLE     = 4'd8,    // Head settle time
        STATE_DONE       = 4'd9,
        STATE_ERROR      = 4'd10,
        STATE_RECAL      = 4'd11;   // Recalibrate (seek to track 0)

    reg [3:0] state;
    reg [3:0] next_state;

    // Counters
    reg [15:0] steps_remaining;
    reg [23:0] timer;
    reg [23:0] timeout_counter;

    // Direction tracking
    reg seeking_inward;

    //-------------------------------------------------------------------------
    // Seek Calculation
    //-------------------------------------------------------------------------
    wire [15:0] distance;
    wire direction;

    // Calculate absolute distance to target
    assign distance = (target_cylinder > current_cylinder) ?
                      (target_cylinder - current_cylinder) :
                      (current_cylinder - target_cylinder);

    // Direction: 1 = in (toward higher cylinder), 0 = out (toward track 0)
    assign direction = (target_cylinder > current_cylinder);

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_IDLE;
            seek_busy <= 1'b0;
            seek_done <= 1'b0;
            seek_error <= 1'b0;
            current_cylinder <= 16'd0;
            at_track00 <= 1'b1;
            step_request <= 1'b0;
            step_direction <= 1'b0;
            steps_remaining <= 16'd0;
            timer <= 24'd0;
            timeout_counter <= 24'd0;
            seeking_inward <= 1'b0;
        end else begin
            // Default outputs
            seek_done <= 1'b0;
            step_request <= 1'b0;

            // Track track00 from drive
            at_track00 <= track00;

            // Timeout counter (runs during active seek)
            if (seek_busy && state != STATE_IDLE) begin
                if (timeout_counter < seek_timeout) begin
                    timeout_counter <= timeout_counter + 1;
                end
            end

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    seek_busy <= 1'b0;
                    seek_error <= 1'b0;
                    timeout_counter <= 24'd0;

                    if (recalibrate) begin
                        // Recalibrate: seek outward until track 0
                        seek_busy <= 1'b1;
                        steps_remaining <= 16'd1024;  // Max tracks to try
                        seeking_inward <= 1'b0;
                        state <= STATE_WAIT_READY;
                        next_state <= STATE_RECAL;
                    end else if (seek_start) begin
                        // Normal seek
                        seek_busy <= 1'b1;
                        if (target_cylinder == current_cylinder) begin
                            // Already at target
                            state <= STATE_DONE;
                        end else begin
                            state <= STATE_WAIT_READY;
                            next_state <= STATE_CALC_STEPS;
                        end
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_READY: begin
                    // Wait for drive ready
                    if (!drive_ready) begin
                        // Drive not ready - wait
                        if (timeout_counter >= seek_timeout) begin
                            state <= STATE_ERROR;
                        end
                    end else if (drive_fault) begin
                        state <= STATE_ERROR;
                    end else begin
                        state <= next_state;
                    end
                end

                //-------------------------------------------------------------
                STATE_CALC_STEPS: begin
                    // Calculate number of steps and direction
                    steps_remaining <= distance;
                    seeking_inward <= direction;
                    step_direction <= direction;

                    if (direction) begin
                        state <= STATE_STEP_IN;
                    end else begin
                        state <= STATE_STEP_OUT;
                    end
                end

                //-------------------------------------------------------------
                STATE_RECAL: begin
                    // Recalibrate: step out until track 0
                    if (track00) begin
                        // Found track 0
                        current_cylinder <= 16'd0;
                        timer <= settle_time;
                        state <= STATE_SETTLE;
                    end else if (steps_remaining == 0) begin
                        // Max steps reached without finding track 0
                        state <= STATE_ERROR;
                    end else begin
                        // Issue step outward
                        step_direction <= 1'b0;  // Out
                        step_request <= 1'b1;
                        state <= STATE_WAIT_STEP;
                        next_state <= STATE_RECAL;
                    end
                end

                //-------------------------------------------------------------
                STATE_STEP_OUT: begin
                    if (steps_remaining == 0) begin
                        // All steps complete, wait for SEEK_COMPLETE
                        state <= STATE_WAIT_SEEK;
                    end else if (track00 && !seeking_inward) begin
                        // Hit track 0 while stepping out - stop
                        current_cylinder <= 16'd0;
                        state <= STATE_WAIT_SEEK;
                    end else begin
                        // Issue step
                        step_direction <= 1'b0;  // Out
                        step_request <= 1'b1;
                        state <= STATE_WAIT_STEP;
                        next_state <= STATE_STEP_OUT;
                    end
                end

                //-------------------------------------------------------------
                STATE_STEP_IN: begin
                    if (steps_remaining == 0) begin
                        // All steps complete, wait for SEEK_COMPLETE
                        state <= STATE_WAIT_SEEK;
                    end else begin
                        // Issue step
                        step_direction <= 1'b1;  // In
                        step_request <= 1'b1;
                        state <= STATE_WAIT_STEP;
                        next_state <= STATE_STEP_IN;
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_STEP: begin
                    // Wait for step pulse to complete
                    if (step_done_in) begin
                        // Update position
                        if (step_direction) begin
                            current_cylinder <= current_cylinder + 1;
                        end else if (current_cylinder > 0) begin
                            current_cylinder <= current_cylinder - 1;
                        end

                        steps_remaining <= steps_remaining - 1;
                        timer <= step_rate;
                        state <= STATE_WAIT_RATE;
                    end else if (timeout_counter >= seek_timeout) begin
                        state <= STATE_ERROR;
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_RATE: begin
                    // Inter-step delay (step rate)
                    if (timer == 0) begin
                        state <= next_state;
                    end else begin
                        timer <= timer - 1;
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_SEEK: begin
                    // Wait for SEEK_COMPLETE from drive
                    if (seek_complete) begin
                        timer <= settle_time;
                        state <= STATE_SETTLE;
                    end else if (drive_fault) begin
                        state <= STATE_ERROR;
                    end else if (timeout_counter >= seek_timeout) begin
                        state <= STATE_ERROR;
                    end
                end

                //-------------------------------------------------------------
                STATE_SETTLE: begin
                    // Head settle time
                    if (timer == 0) begin
                        state <= STATE_DONE;
                    end else begin
                        timer <= timer - 1;
                    end
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    seek_done <= 1'b1;
                    seek_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                //-------------------------------------------------------------
                STATE_ERROR: begin
                    seek_error <= 1'b1;
                    seek_busy <= 1'b0;
                    seek_done <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// HDD Seek Timing Parameters
// Default values for common ST-506 drives
//-----------------------------------------------------------------------------
//
// Drive Type        Step Rate    Settle Time    Notes
// ----------------  ----------   -----------    -----
// ST-225 (MFM)      8 ms         15 ms          Seagate 20MB
// ST-251 (MFM)      5 ms         15 ms          Seagate 40MB
// Miniscribe 3425   3 ms         15 ms          RLL 20MB
// CDC Wren (ESDI)   1.5 ms       10 ms          Fast ESDI
//
// Step pulse width: Typically 8-10 µs (2400-3000 cycles @ 300 MHz)
// @ 300 MHz clock:
//   1 ms  = 400,000 cycles
//   3 ms  = 1,200,000 cycles
//   8 ms  = 3,200,000 cycles
//   15 ms = 6,000,000 cycles

`define HDD_STEP_PULSE_WIDTH  16'd3000    // 10 µs @ 300 MHz
`define HDD_STEP_RATE_FAST    24'd600000  // 1.5 ms (ESDI)
`define HDD_STEP_RATE_MED     24'd1200000 // 3 ms (RLL)
`define HDD_STEP_RATE_SLOW    24'd3200000 // 8 ms (MFM)
`define HDD_SETTLE_TIME       24'd6000000 // 15 ms
`define HDD_SEEK_TIMEOUT      24'd200000000 // 500 ms max seek
