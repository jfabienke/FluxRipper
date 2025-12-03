//-----------------------------------------------------------------------------
// Index Pulse Handler
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Based on CAPSImg CapsFDCEmulator.cpp FdcIndex()
// Handles index pulse detection, revolution counting, and timing
//
// Target: Xilinx Spartan UltraScale+ (UC+)
// Updated: 2025-12-03 12:20
//-----------------------------------------------------------------------------

module index_handler (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Clock frequency for timing calculations
    input  wire [31:0] clk_freq,        // Clock frequency in Hz (e.g., 200_000_000)

    // Index pulse input (directly from drive)
    input  wire        index_raw,       // Raw index pulse from drive
    input  wire        motor_running,   // Motor is running

    // Configuration
    input  wire        rpm_360,         // 1=360 RPM (HD), 0=300 RPM (DD)

    // Outputs
    output reg         index_pulse,     // Synchronized index pulse (1 clock)
    output reg         index_level,     // Current index level
    output reg  [31:0] revolution_time, // Time between index pulses (clocks)
    output reg  [15:0] revolution_count,// Number of revolutions since reset
    output reg         disk_rotating,   // Disk is rotating at proper speed
    output reg         first_index,     // First index since motor start
    output reg  [7:0]  rpm_measured,    // Measured RPM (scaled)
    output reg         rpm_error        // RPM out of tolerance
);

    //-------------------------------------------------------------------------
    // Constants
    //-------------------------------------------------------------------------
    // Expected revolution times at 200 MHz clock:
    // 300 RPM = 200ms/rev = 40,000,000 clocks
    // 360 RPM = 166.67ms/rev = 33,333,333 clocks
    localparam [31:0] REV_TIME_300RPM = 32'd40_000_000;  // 200ms at 200MHz
    localparam [31:0] REV_TIME_360RPM = 32'd33_333_333;  // 166.67ms at 200MHz

    // Tolerance: ±5%
    localparam [31:0] REV_TIME_300_MIN = 32'd38_000_000;
    localparam [31:0] REV_TIME_300_MAX = 32'd42_000_000;
    localparam [31:0] REV_TIME_360_MIN = 32'd31_666_666;
    localparam [31:0] REV_TIME_360_MAX = 32'd35_000_000;

    // Timeout: no index for 500ms = disk stopped
    localparam [31:0] INDEX_TIMEOUT = 32'd100_000_000;  // 500ms at 200MHz

    //-------------------------------------------------------------------------
    // Index pulse synchronizer and edge detector
    //-------------------------------------------------------------------------
    reg [2:0] index_sync;
    wire index_rising;
    wire index_falling;

    always @(posedge clk) begin
        if (reset)
            index_sync <= 3'b000;
        else
            index_sync <= {index_sync[1:0], index_raw};
    end

    assign index_rising  = (index_sync[2:1] == 2'b01);
    assign index_falling = (index_sync[2:1] == 2'b10);

    //-------------------------------------------------------------------------
    // Revolution timing and counting
    //-------------------------------------------------------------------------
    reg [31:0] time_counter;
    reg [31:0] last_rev_time;
    reg        motor_was_running;
    reg        awaiting_first;

    // Expected revolution time based on RPM setting
    wire [31:0] expected_rev_time = rpm_360 ? REV_TIME_360RPM : REV_TIME_300RPM;
    wire [31:0] min_rev_time = rpm_360 ? REV_TIME_360_MIN : REV_TIME_300_MIN;
    wire [31:0] max_rev_time = rpm_360 ? REV_TIME_360_MAX : REV_TIME_300_MAX;

    always @(posedge clk) begin
        if (reset) begin
            index_pulse      <= 1'b0;
            index_level      <= 1'b0;
            revolution_time  <= 32'd0;
            revolution_count <= 16'd0;
            disk_rotating    <= 1'b0;
            first_index      <= 1'b0;
            rpm_measured     <= 8'd0;
            rpm_error        <= 1'b0;
            time_counter     <= 32'd0;
            last_rev_time    <= 32'd0;
            motor_was_running <= 1'b0;
            awaiting_first   <= 1'b1;
        end
        else if (enable) begin
            // Clear single-cycle pulse
            index_pulse <= 1'b0;
            first_index <= 1'b0;

            // Track motor state transitions
            motor_was_running <= motor_running;

            // Motor just started - reset for first index
            if (motor_running && !motor_was_running) begin
                awaiting_first   <= 1'b1;
                time_counter     <= 32'd0;
                revolution_count <= 16'd0;
                disk_rotating    <= 1'b0;
            end

            // Motor stopped
            if (!motor_running) begin
                disk_rotating <= 1'b0;
                rpm_error     <= 1'b0;
            end

            // Update index level
            if (index_rising)
                index_level <= 1'b1;
            else if (index_falling)
                index_level <= 1'b0;

            // Index pulse detected
            if (index_rising && motor_running) begin
                index_pulse <= 1'b1;

                if (awaiting_first) begin
                    // First index after motor start
                    first_index    <= 1'b1;
                    awaiting_first <= 1'b0;
                    time_counter   <= 32'd0;
                end
                else begin
                    // Measure revolution time
                    revolution_time <= time_counter;
                    last_rev_time   <= time_counter;

                    // Check if revolution time is within tolerance
                    if (time_counter >= min_rev_time && time_counter <= max_rev_time) begin
                        disk_rotating <= 1'b1;
                        rpm_error     <= 1'b0;

                        // Calculate approximate RPM (scaled by 1x)
                        // RPM = 60 / (time_counter / clk_freq)
                        // RPM = 60 * clk_freq / time_counter
                        // Simplified: use lookup or approximation
                        if (time_counter > 32'd35_000_000)
                            rpm_measured <= 8'd300;  // ~300 RPM
                        else
                            rpm_measured <= 8'd360;  // ~360 RPM
                    end
                    else begin
                        rpm_error <= 1'b1;
                    end

                    time_counter <= 32'd0;
                end

                // Increment revolution counter
                if (revolution_count < 16'hFFFF)
                    revolution_count <= revolution_count + 1'b1;
            end
            else if (motor_running) begin
                // Increment time counter
                if (time_counter < INDEX_TIMEOUT)
                    time_counter <= time_counter + 1'b1;
                else begin
                    // Timeout - disk not rotating
                    disk_rotating <= 1'b0;
                end
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Index Sector Timer
// Measures time from index pulse, used for sector positioning
//-----------------------------------------------------------------------------

module index_sector_timer (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Index pulse
    input  wire        index_pulse,     // From index_handler

    // Configuration
    input  wire [1:0]  data_rate,       // 00=500K, 01=300K, 10=250K, 11=1M
    input  wire        rpm_360,         // 1=360 RPM, 0=300 RPM

    // Timer outputs
    output reg  [31:0] track_position,  // Current position in track (bit times)
    output reg  [15:0] sector_time,     // Time within current sector
    output reg  [5:0]  expected_sector, // Expected sector number at this position
    output reg         track_wrapped    // Track position wrapped (full revolution)
);

    //-------------------------------------------------------------------------
    // Track length in bit times for various formats
    // Assumes 200 MHz clock, values are approximate
    //-------------------------------------------------------------------------

    // Bits per track at various rates:
    // 500K @ 300 RPM = 100K bits/track
    // 300K @ 300 RPM = 60K bits/track
    // 250K @ 300 RPM = 50K bits/track
    // 500K @ 360 RPM = 83.3K bits/track

    reg [31:0] bits_per_track;
    reg [31:0] clocks_per_bit;

    always @(*) begin
        case (data_rate)
            2'b00: begin  // 500 Kbps
                clocks_per_bit = 32'd400;   // 200MHz / 500KHz = 400
                bits_per_track = rpm_360 ? 32'd83333 : 32'd100000;
            end
            2'b01: begin  // 300 Kbps
                clocks_per_bit = 32'd667;   // 200MHz / 300KHz = 667
                bits_per_track = 32'd60000;
            end
            2'b10: begin  // 250 Kbps
                clocks_per_bit = 32'd800;   // 200MHz / 250KHz = 800
                bits_per_track = 32'd50000;
            end
            2'b11: begin  // 1 Mbps
                clocks_per_bit = 32'd200;   // 200MHz / 1MHz = 200
                bits_per_track = rpm_360 ? 32'd166666 : 32'd200000;
            end
        endcase
    end

    // Clock counter between bit times
    reg [31:0] clock_counter;

    always @(posedge clk) begin
        if (reset) begin
            track_position  <= 32'd0;
            sector_time     <= 16'd0;
            expected_sector <= 6'd0;
            track_wrapped   <= 1'b0;
            clock_counter   <= 32'd0;
        end
        else if (enable) begin
            track_wrapped <= 1'b0;

            if (index_pulse) begin
                // Reset on index
                track_position  <= 32'd0;
                sector_time     <= 16'd0;
                expected_sector <= 6'd0;
                clock_counter   <= 32'd0;
                track_wrapped   <= 1'b1;
            end
            else begin
                // Increment clock counter
                clock_counter <= clock_counter + 1'b1;

                // Check if we've passed one bit time
                if (clock_counter >= clocks_per_bit) begin
                    clock_counter  <= 32'd0;
                    track_position <= track_position + 1'b1;
                    sector_time    <= sector_time + 1'b1;

                    // Check for track wrap (shouldn't happen without index)
                    if (track_position >= bits_per_track) begin
                        track_position <= 32'd0;
                        track_wrapped  <= 1'b1;
                    end

                    // Estimate sector number (18 sectors/track @ 512 bytes/sector)
                    // Each sector is approximately bits_per_track/18 bits
                    // Simplified calculation
                    if (track_position > 32'd0) begin
                        expected_sector <= track_position[19:14];  // Rough approximation
                    end
                end
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Revolution Counter with Auto-Off Support
// Counts revolutions and supports motor auto-off after idle period
//-----------------------------------------------------------------------------

module revolution_counter (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Index pulse
    input  wire        index_pulse,

    // Activity indication
    input  wire        read_active,     // Data read in progress
    input  wire        write_active,    // Data write in progress
    input  wire        seek_active,     // Seek in progress

    // Configuration
    input  wire [3:0]  idle_revs,       // Revolutions before auto-off (0=disabled)

    // Outputs
    output reg  [15:0] total_revs,      // Total revolution count
    output reg  [3:0]  idle_count,      // Revolutions since last activity
    output reg         auto_off_req     // Request motor auto-off
);

    reg activity_seen;

    always @(posedge clk) begin
        if (reset) begin
            total_revs   <= 16'd0;
            idle_count   <= 4'd0;
            auto_off_req <= 1'b0;
            activity_seen <= 1'b0;
        end
        else if (enable) begin
            auto_off_req <= 1'b0;

            // Track any activity
            if (read_active || write_active || seek_active)
                activity_seen <= 1'b1;

            // On index pulse
            if (index_pulse) begin
                // Increment total count
                if (total_revs < 16'hFFFF)
                    total_revs <= total_revs + 1'b1;

                // Check for activity since last index
                if (activity_seen) begin
                    idle_count    <= 4'd0;
                    activity_seen <= 1'b0;
                end
                else begin
                    // No activity, increment idle counter
                    if (idle_count < 4'd15)
                        idle_count <= idle_count + 1'b1;

                    // Check for auto-off threshold
                    if (idle_revs != 4'd0 && idle_count >= idle_revs) begin
                        auto_off_req <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
