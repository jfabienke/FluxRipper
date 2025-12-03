//-----------------------------------------------------------------------------
// Step Controller for FluxRipper
// Controls head positioning with double-step support
//
// Based on CAPSImg CapsFDCEmulator.cpp clockstep[] timing values
//
// Updated: 2025-12-02 16:45
//-----------------------------------------------------------------------------

module step_controller (
    input  wire        clk,
    input  wire        reset,

    // Configuration
    input  wire [31:0] clk_freq,        // System clock frequency
    input  wire [1:0]  step_rate_sel,   // Step rate selection (0-3)
    input  wire        double_step,     // Enable double-stepping for 40-track disks

    // Command interface
    input  wire        seek_start,      // Start seek operation
    input  wire [7:0]  target_track,    // Target track number
    input  wire        step_in,         // Step in (towards center)
    input  wire        step_out,        // Step out (towards track 0)
    input  wire        restore,         // Restore to track 0

    // Drive interface
    output reg         step_pulse,      // Step pulse output
    output reg         direction,       // Direction: 1=in, 0=out
    output reg         head_load,       // Head load signal

    // Status
    output reg  [7:0]  current_track,   // Current track position
    output reg  [7:0]  physical_track,  // Physical track (may differ with double-step)
    output reg         seek_complete,   // Seek operation complete
    output reg         at_track0,       // At track 0
    output reg         busy             // Step operation in progress
);

    //-------------------------------------------------------------------------
    // Step rate timing (from CAPSImg CapsFDCEmulator.cpp FdcSetTiming)
    //-------------------------------------------------------------------------
    // Standard 82077AA step rates in microseconds:
    // Rate 0: 6ms,  Rate 1: 12ms,  Rate 2: 2ms,  Rate 3: 3ms

    localparam STEP_6MS  = 32'd6000;
    localparam STEP_12MS = 32'd12000;
    localparam STEP_2MS  = 32'd2000;
    localparam STEP_3MS  = 32'd3000;
    localparam HEAD_SETTLE = 32'd15000;  // 15ms head settle time

    // Calculate timer counts based on clock frequency
    reg [31:0] step_delay;
    reg [31:0] settle_delay;

    always @(*) begin
        case (step_rate_sel)
            2'b00: step_delay = (clk_freq / 1000) * 6;      // 6ms
            2'b01: step_delay = (clk_freq / 1000) * 12;     // 12ms
            2'b10: step_delay = (clk_freq / 1000) * 2;      // 2ms
            2'b11: step_delay = (clk_freq / 1000) * 3;      // 3ms
        endcase
        settle_delay = (clk_freq / 1000) * 15;              // 15ms
    end

    //-------------------------------------------------------------------------
    // State machine
    //-------------------------------------------------------------------------
    localparam S_IDLE         = 4'd0;
    localparam S_CALC_STEPS   = 4'd1;
    localparam S_STEP_PULSE   = 4'd2;
    localparam S_STEP_WAIT    = 4'd3;
    localparam S_STEP2_PULSE  = 4'd4;  // For double-step
    localparam S_STEP2_WAIT   = 4'd5;
    localparam S_HEAD_SETTLE  = 4'd6;
    localparam S_COMPLETE     = 4'd7;
    localparam S_RESTORE      = 4'd8;

    reg [3:0]  state;
    reg [31:0] timer;
    reg [7:0]  steps_remaining;
    reg        step_direction;  // 1=in, 0=out

    // Pulse width (typically 1-10 microseconds)
    localparam PULSE_WIDTH = 32'd200;  // 200 clock cycles @ 200MHz = 1us

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            step_pulse <= 1'b0;
            direction <= 1'b0;
            head_load <= 1'b0;
            current_track <= 8'd0;
            physical_track <= 8'd0;
            seek_complete <= 1'b0;
            at_track0 <= 1'b1;
            busy <= 1'b0;
            timer <= 32'd0;
            steps_remaining <= 8'd0;
            step_direction <= 1'b0;
        end else begin
            // Default outputs
            seek_complete <= 1'b0;
            step_pulse <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;

                    if (restore) begin
                        // Restore to track 0
                        busy <= 1'b1;
                        direction <= 1'b0;  // Step out
                        head_load <= 1'b1;
                        steps_remaining <= current_track + 8'd10;  // Extra steps for safety
                        state <= S_RESTORE;
                    end else if (seek_start) begin
                        // Seek to target track
                        busy <= 1'b1;
                        head_load <= 1'b1;
                        state <= S_CALC_STEPS;
                    end else if (step_in && current_track < 8'd83) begin
                        // Single step in
                        busy <= 1'b1;
                        direction <= 1'b1;
                        head_load <= 1'b1;
                        steps_remaining <= double_step ? 8'd2 : 8'd1;
                        step_direction <= 1'b1;
                        state <= S_STEP_PULSE;
                    end else if (step_out && current_track > 8'd0) begin
                        // Single step out
                        busy <= 1'b1;
                        direction <= 1'b0;
                        head_load <= 1'b1;
                        steps_remaining <= double_step ? 8'd2 : 8'd1;
                        step_direction <= 1'b0;
                        state <= S_STEP_PULSE;
                    end
                end

                S_CALC_STEPS: begin
                    // Calculate steps needed
                    if (target_track > current_track) begin
                        step_direction <= 1'b1;  // Step in
                        direction <= 1'b1;
                        if (double_step) begin
                            steps_remaining <= (target_track - current_track) << 1;
                        end else begin
                            steps_remaining <= target_track - current_track;
                        end
                    end else if (target_track < current_track) begin
                        step_direction <= 1'b0;  // Step out
                        direction <= 1'b0;
                        if (double_step) begin
                            steps_remaining <= (current_track - target_track) << 1;
                        end else begin
                            steps_remaining <= current_track - target_track;
                        end
                    end else begin
                        // Already at target
                        state <= S_HEAD_SETTLE;
                        timer <= settle_delay;
                    end

                    if (steps_remaining > 8'd0) begin
                        state <= S_STEP_PULSE;
                    end
                end

                S_STEP_PULSE: begin
                    // Generate step pulse
                    step_pulse <= 1'b1;
                    timer <= PULSE_WIDTH;
                    state <= S_STEP_WAIT;
                end

                S_STEP_WAIT: begin
                    // Wait for step pulse duration, then step delay
                    if (timer > 32'd0) begin
                        timer <= timer - 1'b1;
                        if (timer == 32'd1) begin
                            step_pulse <= 1'b0;
                            timer <= step_delay;
                        end
                    end else begin
                        // Update track counter
                        if (double_step) begin
                            physical_track <= step_direction ?
                                              (physical_track + 8'd1) :
                                              (physical_track > 8'd0 ? physical_track - 8'd1 : 8'd0);
                            // Logical track updates every 2 physical steps
                            if (steps_remaining[0] == 1'b0) begin
                                current_track <= step_direction ?
                                                 (current_track + 8'd1) :
                                                 (current_track > 8'd0 ? current_track - 8'd1 : 8'd0);
                            end
                        end else begin
                            current_track <= step_direction ?
                                             (current_track + 8'd1) :
                                             (current_track > 8'd0 ? current_track - 8'd1 : 8'd0);
                            physical_track <= current_track;
                        end

                        steps_remaining <= steps_remaining - 8'd1;
                        at_track0 <= (current_track == 8'd0);

                        if (steps_remaining == 8'd1) begin
                            // Last step, go to settle
                            state <= S_HEAD_SETTLE;
                            timer <= settle_delay;
                        end else begin
                            // More steps needed
                            state <= S_STEP_PULSE;
                        end
                    end
                end

                S_HEAD_SETTLE: begin
                    // Wait for head settle time
                    if (timer > 32'd0) begin
                        timer <= timer - 1'b1;
                    end else begin
                        state <= S_COMPLETE;
                    end
                end

                S_COMPLETE: begin
                    seek_complete <= 1'b1;
                    state <= S_IDLE;
                end

                S_RESTORE: begin
                    // Step out until track 0 or step count exhausted
                    if (at_track0 || steps_remaining == 8'd0) begin
                        current_track <= 8'd0;
                        physical_track <= 8'd0;
                        at_track0 <= 1'b1;
                        state <= S_HEAD_SETTLE;
                        timer <= settle_delay;
                    end else begin
                        // Generate step pulse
                        step_pulse <= 1'b1;
                        timer <= PULSE_WIDTH;

                        // Wait and count
                        if (timer == 32'd0) begin
                            steps_remaining <= steps_remaining - 8'd1;
                            timer <= step_delay;
                        end else begin
                            timer <= timer - 1'b1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Track Width Analyzer
// Detects 40-track vs 80-track disk format
//-----------------------------------------------------------------------------
module track_width_analyzer (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [7:0]  id_cylinder,     // Cylinder from ID field
    input  wire        id_valid,        // ID field is valid
    input  wire [7:0]  physical_track,  // Physical head position
    output reg         double_step_recommended,
    output reg         analysis_complete,
    output reg  [7:0]  detected_tracks  // Detected track count (40 or 80)
);

    // Analysis state
    reg [3:0] sample_count;
    reg [7:0] max_cylinder_seen;
    reg       mismatch_detected;

    always @(posedge clk) begin
        if (reset || !enable) begin
            sample_count <= 4'd0;
            max_cylinder_seen <= 8'd0;
            mismatch_detected <= 1'b0;
            double_step_recommended <= 1'b0;
            analysis_complete <= 1'b0;
            detected_tracks <= 8'd80;
        end else if (id_valid) begin
            sample_count <= sample_count + 1'b1;

            // Track maximum cylinder seen
            if (id_cylinder > max_cylinder_seen) begin
                max_cylinder_seen <= id_cylinder;
            end

            // Check for mismatch between physical and logical tracks
            if (id_cylinder != physical_track) begin
                mismatch_detected <= 1'b1;
            end

            // After several samples, make decision
            if (sample_count >= 4'd8) begin
                analysis_complete <= 1'b1;

                if (max_cylinder_seen < 8'd45 || mismatch_detected) begin
                    // Likely 40-track disk
                    double_step_recommended <= 1'b1;
                    detected_tracks <= 8'd40;
                end else begin
                    // 80-track disk
                    double_step_recommended <= 1'b0;
                    detected_tracks <= 8'd80;
                end
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Motor Controller
// Handles motor on/off timing
//-----------------------------------------------------------------------------
module motor_controller (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] clk_freq,

    // Control inputs
    input  wire [3:0]  motor_on_cmd,    // Motor on command per drive
    input  wire        auto_off_enable, // Enable automatic motor off

    // Index pulse input
    input  wire        index_pulse,

    // Motor outputs
    output reg  [3:0]  motor_running,   // Motor actually running
    output reg  [3:0]  motor_at_speed,  // Motor up to speed

    // Status
    output reg  [7:0]  revolution_count // Revolution counter
);

    // Timing constants
    localparam SPINUP_REVS = 8'd8;       // Revolutions to reach speed
    localparam AUTO_OFF_REVS = 8'd20;    // Revolutions before auto-off

    reg [3:0]  spinup_count [0:3];
    reg [7:0]  idle_count [0:3];
    reg        index_prev;

    wire index_edge = index_pulse && !index_prev;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            motor_running <= 4'b0000;
            motor_at_speed <= 4'b0000;
            revolution_count <= 8'd0;
            index_prev <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                spinup_count[i] <= 4'd0;
                idle_count[i] <= 8'd0;
            end
        end else begin
            index_prev <= index_pulse;

            // Count revolutions
            if (index_edge) begin
                revolution_count <= revolution_count + 1'b1;
            end

            // Per-drive motor control
            for (i = 0; i < 4; i = i + 1) begin
                if (motor_on_cmd[i]) begin
                    motor_running[i] <= 1'b1;
                    idle_count[i] <= 8'd0;

                    // Spinup timing
                    if (index_edge && !motor_at_speed[i]) begin
                        if (spinup_count[i] < SPINUP_REVS) begin
                            spinup_count[i] <= spinup_count[i] + 1'b1;
                        end else begin
                            motor_at_speed[i] <= 1'b1;
                        end
                    end
                end else begin
                    // Motor commanded off
                    if (auto_off_enable) begin
                        // Count idle revolutions
                        if (index_edge) begin
                            if (idle_count[i] < AUTO_OFF_REVS) begin
                                idle_count[i] <= idle_count[i] + 1'b1;
                            end else begin
                                motor_running[i] <= 1'b0;
                                motor_at_speed[i] <= 1'b0;
                                spinup_count[i] <= 4'd0;
                            end
                        end
                    end else begin
                        // Immediate off
                        motor_running[i] <= 1'b0;
                        motor_at_speed[i] <= 1'b0;
                        spinup_count[i] <= 4'd0;
                    end
                end
            end
        end
    end

endmodule
