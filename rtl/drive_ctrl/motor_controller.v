//-----------------------------------------------------------------------------
// Motor Controller
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Based on CAPSImg CapsFDCEmulator.cpp motor handling
// Implements motor spinup/spindown timing and auto-off functionality
//
// Target: Xilinx Spartan UltraScale+ (UC+)
// Updated: 2025-12-03 12:30
//-----------------------------------------------------------------------------

module motor_controller (
    input  wire        clk,
    input  wire        reset,

    // Clock frequency for timing
    input  wire [31:0] clk_freq,        // Clock frequency in Hz (200_000_000)

    // Motor control commands (from DOR register)
    input  wire [3:0]  motor_on_cmd,    // Motor enable for drives 0-3

    // Auto-off configuration
    input  wire        auto_off_enable, // Enable motor auto-off
    input  wire [3:0]  idle_revs,       // Revolutions before auto-off (0=disabled)

    // Index pulse for spinup detection and auto-off timing
    input  wire        index_pulse,

    // Activity indication (from command FSM)
    input  wire [3:0]  drive_active,    // Which drives have active commands

    // Motor status outputs
    output reg  [3:0]  motor_running,   // Motor physically running
    output reg  [3:0]  motor_at_speed,  // Motor at operating speed
    output reg  [7:0]  revolution_count // Revolutions since motor start
);

    //-------------------------------------------------------------------------
    // Timing Constants (at 200 MHz)
    //-------------------------------------------------------------------------
    // Motor spinup time: typically 300-500ms
    // We use 500ms = 100,000,000 clocks at 200 MHz
    localparam [31:0] SPINUP_TIME = 32'd100_000_000;

    // Motor spindown time: typically 1-2 seconds after command
    // We give it 2 seconds = 400,000,000 clocks
    localparam [31:0] SPINDOWN_TIME = 32'd400_000_000;

    // Number of index pulses to confirm motor at speed
    localparam [3:0] SPINUP_REVS = 4'd3;

    //-------------------------------------------------------------------------
    // Per-drive state
    //-------------------------------------------------------------------------
    reg [31:0] spinup_timer  [0:3];
    reg [31:0] spindown_timer[0:3];
    reg [3:0]  index_count   [0:3];
    reg [3:0]  idle_count    [0:3];
    reg [3:0]  motor_cmd_prev;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            motor_running    <= 4'b0000;
            motor_at_speed   <= 4'b0000;
            revolution_count <= 8'd0;
            motor_cmd_prev   <= 4'b0000;

            for (i = 0; i < 4; i = i + 1) begin
                spinup_timer[i]   <= 32'd0;
                spindown_timer[i] <= 32'd0;
                index_count[i]    <= 4'd0;
                idle_count[i]     <= 4'd0;
            end
        end
        else begin
            motor_cmd_prev <= motor_on_cmd;

            for (i = 0; i < 4; i = i + 1) begin
                // Motor ON command rising edge
                if (motor_on_cmd[i] && !motor_cmd_prev[i]) begin
                    // Start motor spinup
                    motor_running[i]  <= 1'b1;
                    motor_at_speed[i] <= 1'b0;
                    spinup_timer[i]   <= SPINUP_TIME;
                    spindown_timer[i] <= 32'd0;
                    index_count[i]    <= 4'd0;
                    idle_count[i]     <= 4'd0;
                end
                // Motor ON command falling edge
                else if (!motor_on_cmd[i] && motor_cmd_prev[i]) begin
                    // Start motor spindown
                    if (motor_running[i]) begin
                        spindown_timer[i] <= SPINDOWN_TIME;
                    end
                end

                // Handle spinup
                if (motor_running[i] && !motor_at_speed[i]) begin
                    if (index_pulse) begin
                        // Count index pulses during spinup
                        index_count[i] <= index_count[i] + 1'b1;

                        // Motor at speed when we've seen enough indexes
                        if (index_count[i] >= SPINUP_REVS) begin
                            motor_at_speed[i] <= 1'b1;
                        end
                    end

                    // Timeout-based spinup (backup)
                    if (spinup_timer[i] > 0) begin
                        spinup_timer[i] <= spinup_timer[i] - 1'b1;
                    end
                    else begin
                        // Assume motor at speed after timeout
                        motor_at_speed[i] <= 1'b1;
                    end
                end

                // Handle spindown
                if (spindown_timer[i] > 0) begin
                    spindown_timer[i] <= spindown_timer[i] - 1'b1;

                    if (spindown_timer[i] == 32'd1) begin
                        // Motor has stopped
                        motor_running[i]  <= 1'b0;
                        motor_at_speed[i] <= 1'b0;
                    end
                end

                // Handle auto-off
                if (auto_off_enable && motor_running[i] && motor_at_speed[i] && !motor_on_cmd[i]) begin
                    if (index_pulse) begin
                        if (!drive_active[i]) begin
                            // No activity, count idle revolutions
                            idle_count[i] <= idle_count[i] + 1'b1;

                            if (idle_revs != 4'd0 && idle_count[i] >= idle_revs) begin
                                // Auto-off triggered
                                spindown_timer[i] <= SPINDOWN_TIME;
                            end
                        end
                        else begin
                            // Activity detected, reset idle counter
                            idle_count[i] <= 4'd0;
                        end
                    end
                end
            end

            // Count revolutions for drive 0 (primary)
            if (motor_running[0] && motor_at_speed[0] && index_pulse) begin
                if (revolution_count < 8'hFF)
                    revolution_count <= revolution_count + 1'b1;
            end
            else if (!motor_running[0]) begin
                revolution_count <= 8'd0;
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Motor Speed Detector
// Detects actual motor speed from index pulses
//-----------------------------------------------------------------------------

module motor_speed_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Clock frequency
    input  wire [31:0] clk_freq,

    // Index pulse
    input  wire        index_pulse,

    // Outputs
    output reg  [15:0] rpm,             // Measured RPM
    output reg  [31:0] period_clocks,   // Period in clock cycles
    output reg         speed_valid,     // Speed measurement valid
    output reg         speed_error      // Speed out of range
);

    //-------------------------------------------------------------------------
    // Speed calculation
    //-------------------------------------------------------------------------
    reg [31:0] cycle_counter;
    reg [31:0] last_period;
    reg        first_index;

    // Valid RPM range: 250-400 RPM
    // At 200 MHz: 300 RPM = 40M clocks, 360 RPM = 33.3M clocks
    localparam [31:0] MIN_PERIOD = 32'd30_000_000;   // ~400 RPM
    localparam [31:0] MAX_PERIOD = 32'd48_000_000;   // ~250 RPM

    always @(posedge clk) begin
        if (reset) begin
            rpm           <= 16'd0;
            period_clocks <= 32'd0;
            speed_valid   <= 1'b0;
            speed_error   <= 1'b0;
            cycle_counter <= 32'd0;
            last_period   <= 32'd0;
            first_index   <= 1'b1;
        end
        else if (enable) begin
            // Increment cycle counter
            if (cycle_counter < 32'hFFFF_FFFF)
                cycle_counter <= cycle_counter + 1'b1;

            if (index_pulse) begin
                if (first_index) begin
                    // First index, just start counting
                    first_index   <= 1'b0;
                    cycle_counter <= 32'd0;
                end
                else begin
                    // Calculate speed
                    period_clocks <= cycle_counter;
                    last_period   <= cycle_counter;

                    // Check if in valid range
                    if (cycle_counter >= MIN_PERIOD && cycle_counter <= MAX_PERIOD) begin
                        speed_valid <= 1'b1;
                        speed_error <= 1'b0;

                        // Calculate RPM (simplified)
                        // RPM = 60 * clk_freq / period_clocks
                        // At 200 MHz: 60 * 200M / period = 12G / period
                        // Use approximate calculation
                        if (cycle_counter < 32'd35_000_000)
                            rpm <= 16'd360;
                        else if (cycle_counter < 32'd42_000_000)
                            rpm <= 16'd300;
                        else
                            rpm <= 16'd250;
                    end
                    else begin
                        speed_valid <= 1'b0;
                        speed_error <= 1'b1;
                    end

                    cycle_counter <= 32'd0;
                end
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Drive Ready Detector
// Combines motor status with drive ready signal
//-----------------------------------------------------------------------------

module drive_ready_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Motor status
    input  wire        motor_running,
    input  wire        motor_at_speed,

    // Drive signals
    input  wire        drive_ready_in,  // Physical ready signal from drive
    input  wire        disk_change,     // Disk change signal

    // Outputs
    output reg         ready,           // Drive is ready for operations
    output reg         disk_present,    // Disk is present in drive
    output reg         disk_changed     // Disk has been changed (sticky)
);

    reg disk_change_prev;

    always @(posedge clk) begin
        if (reset) begin
            ready          <= 1'b0;
            disk_present   <= 1'b0;
            disk_changed   <= 1'b0;
            disk_change_prev <= 1'b0;
        end
        else if (enable) begin
            disk_change_prev <= disk_change;

            // Detect disk change (typically active low, edge triggered)
            if (disk_change && !disk_change_prev) begin
                disk_changed <= 1'b1;
            end

            // Disk present when motor at speed and no disk change
            disk_present <= motor_at_speed && !disk_change;

            // Ready when motor at speed and drive reports ready
            ready <= motor_at_speed && drive_ready_in && !disk_change;
        end
    end

    // Clear disk changed flag (would be done by reading DIR register)
    // This is handled in fdc_registers module

endmodule


//-----------------------------------------------------------------------------
// Write Protect Detector
// Debounces and synchronizes write protect signal
//-----------------------------------------------------------------------------

module write_protect_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Write protect signal from drive (active low typically)
    input  wire        wp_raw,

    // Outputs
    output reg         write_protected, // Debounced write protect status
    output reg         wp_changed       // Write protect status changed
);

    //-------------------------------------------------------------------------
    // Debounce filter (10ms at 200 MHz = 2M clocks)
    //-------------------------------------------------------------------------
    localparam [20:0] DEBOUNCE_COUNT = 21'd2_000_000;

    reg [20:0] debounce_counter;
    reg [2:0]  wp_sync;
    reg        wp_stable;

    always @(posedge clk) begin
        if (reset) begin
            write_protected  <= 1'b0;
            wp_changed       <= 1'b0;
            debounce_counter <= 21'd0;
            wp_sync          <= 3'b000;
            wp_stable        <= 1'b0;
        end
        else if (enable) begin
            wp_changed <= 1'b0;

            // Synchronize input
            wp_sync <= {wp_sync[1:0], wp_raw};

            // Debounce
            if (wp_sync[2] != wp_stable) begin
                if (debounce_counter < DEBOUNCE_COUNT) begin
                    debounce_counter <= debounce_counter + 1'b1;
                end
                else begin
                    wp_stable        <= wp_sync[2];
                    write_protected  <= wp_sync[2];
                    wp_changed       <= 1'b1;
                    debounce_counter <= 21'd0;
                end
            end
            else begin
                debounce_counter <= 21'd0;
            end
        end
    end

endmodule
