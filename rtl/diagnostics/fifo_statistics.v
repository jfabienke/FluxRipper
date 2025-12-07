//-----------------------------------------------------------------------------
// FIFO Statistics Module for FluxRipper
//
// Tracks FIFO utilization and performance metrics:
//   - Peak fill level (high water mark)
//   - Overflow count
//   - Underrun count
//   - Backpressure events (TREADY deassertions)
//   - Average fill level
//
// Created: 2025-12-04 13:00
//-----------------------------------------------------------------------------

module fifo_statistics #(
    parameter FIFO_DEPTH = 512,
    parameter ADDR_BITS  = 9
)(
    input  wire                clk,
    input  wire                reset,

    //-------------------------------------------------------------------------
    // FIFO Status Inputs
    //-------------------------------------------------------------------------
    input  wire [ADDR_BITS:0]  fifo_level,       // Current FIFO fill level
    input  wire                fifo_empty,
    input  wire                fifo_full,
    input  wire                fifo_write,       // Write strobe
    input  wire                fifo_read,        // Read strobe

    //-------------------------------------------------------------------------
    // AXI Stream Backpressure Detection
    //-------------------------------------------------------------------------
    input  wire                axis_tvalid,
    input  wire                axis_tready,

    //-------------------------------------------------------------------------
    // Capture Session Control
    //-------------------------------------------------------------------------
    input  wire                capture_active,   // Capture in progress
    input  wire                stats_clear,      // Clear statistics

    //-------------------------------------------------------------------------
    // Statistics Outputs
    //-------------------------------------------------------------------------
    // Fill level statistics
    output reg  [ADDR_BITS:0]  peak_level,       // Maximum fill level seen
    output reg  [ADDR_BITS:0]  min_level,        // Minimum fill level (during active)
    output reg  [31:0]         avg_level,        // Average level (scaled x256)

    // Event counters
    output reg  [31:0]         overflow_count,   // Write attempts when full
    output reg  [31:0]         underrun_count,   // Read attempts when empty
    output reg  [31:0]         backpressure_cnt, // TREADY=0 while TVALID=1
    output reg  [31:0]         total_writes,     // Total write operations
    output reg  [31:0]         total_reads,      // Total read operations

    // Timing
    output reg  [31:0]         time_at_peak,     // Clocks spent at peak level
    output reg  [31:0]         time_empty,       // Clocks spent empty
    output reg  [31:0]         time_full,        // Clocks spent full

    // Utilization
    output wire [7:0]          utilization_pct,  // Average utilization (0-100%)
    output wire                overflow_flag,    // Sticky overflow flag
    output wire                underrun_flag     // Sticky underrun flag
);

    //-------------------------------------------------------------------------
    // Internal State
    //-------------------------------------------------------------------------
    reg        overflow_sticky;
    reg        underrun_sticky;
    reg [31:0] level_accumulator;
    reg [31:0] sample_count;
    reg        prev_capture_active;

    //-------------------------------------------------------------------------
    // Peak/Min Level Tracking
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || stats_clear) begin
            peak_level <= {(ADDR_BITS+1){1'b0}};
            min_level <= {(ADDR_BITS+1){1'b1}};  // Start at max
        end else if (capture_active) begin
            if (fifo_level > peak_level)
                peak_level <= fifo_level;
            if (fifo_level < min_level)
                min_level <= fifo_level;
        end
    end

    //-------------------------------------------------------------------------
    // Event Counting
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || stats_clear) begin
            overflow_count   <= 32'd0;
            underrun_count   <= 32'd0;
            backpressure_cnt <= 32'd0;
            total_writes     <= 32'd0;
            total_reads      <= 32'd0;
            overflow_sticky  <= 1'b0;
            underrun_sticky  <= 1'b0;
        end else begin
            // Overflow detection: write attempt when full
            if (fifo_write && fifo_full) begin
                if (overflow_count != 32'hFFFFFFFF)
                    overflow_count <= overflow_count + 1;
                overflow_sticky <= 1'b1;
            end

            // Underrun detection: read attempt when empty
            if (fifo_read && fifo_empty) begin
                if (underrun_count != 32'hFFFFFFFF)
                    underrun_count <= underrun_count + 1;
                underrun_sticky <= 1'b1;
            end

            // Backpressure detection: TVALID high but TREADY low
            if (axis_tvalid && !axis_tready) begin
                if (backpressure_cnt != 32'hFFFFFFFF)
                    backpressure_cnt <= backpressure_cnt + 1;
            end

            // Total operations
            if (fifo_write && !fifo_full) begin
                if (total_writes != 32'hFFFFFFFF)
                    total_writes <= total_writes + 1;
            end
            if (fifo_read && !fifo_empty) begin
                if (total_reads != 32'hFFFFFFFF)
                    total_reads <= total_reads + 1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Time Tracking
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || stats_clear) begin
            time_at_peak <= 32'd0;
            time_empty   <= 32'd0;
            time_full    <= 32'd0;
        end else if (capture_active) begin
            // Time at peak
            if (fifo_level == peak_level && peak_level != 0) begin
                if (time_at_peak != 32'hFFFFFFFF)
                    time_at_peak <= time_at_peak + 1;
            end

            // Time empty
            if (fifo_empty) begin
                if (time_empty != 32'hFFFFFFFF)
                    time_empty <= time_empty + 1;
            end

            // Time full
            if (fifo_full) begin
                if (time_full != 32'hFFFFFFFF)
                    time_full <= time_full + 1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Average Level Calculation
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || stats_clear) begin
            level_accumulator <= 32'd0;
            sample_count      <= 32'd0;
            avg_level         <= 32'd0;
            prev_capture_active <= 1'b0;
        end else begin
            prev_capture_active <= capture_active;

            if (capture_active) begin
                // Accumulate level every 256 clocks to avoid overflow
                if (sample_count[7:0] == 8'hFF) begin
                    level_accumulator <= level_accumulator + {23'd0, fifo_level};
                end
                sample_count <= sample_count + 1;
            end

            // Calculate average when capture ends
            if (prev_capture_active && !capture_active && sample_count > 0) begin
                // avg_level = (accumulator * 256) / (sample_count / 256)
                // Simplified: already sampled every 256, so just scale
                avg_level <= {level_accumulator[23:0], 8'd0};
            end
        end
    end

    //-------------------------------------------------------------------------
    // Utilization Calculation
    // utilization_pct = (avg_level / FIFO_DEPTH) * 100
    //-------------------------------------------------------------------------
    wire [31:0] util_scaled;
    assign util_scaled = (avg_level * 100) >> (ADDR_BITS + 8);  // Divide by depth*256
    assign utilization_pct = (util_scaled > 100) ? 8'd100 : util_scaled[7:0];

    //-------------------------------------------------------------------------
    // Status Flags
    //-------------------------------------------------------------------------
    assign overflow_flag = overflow_sticky;
    assign underrun_flag = underrun_sticky;

endmodule

//-----------------------------------------------------------------------------
// Capture Timing Statistics
// Tracks timing metrics during flux capture
//-----------------------------------------------------------------------------
module capture_timing (
    input  wire        clk,
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Capture Status
    //-------------------------------------------------------------------------
    input  wire        capture_active,
    input  wire        flux_edge,          // Flux transition detected
    input  wire        index_pulse,        // Index pulse detected

    //-------------------------------------------------------------------------
    // Clear
    //-------------------------------------------------------------------------
    input  wire        stats_clear,

    //-------------------------------------------------------------------------
    // Timing Outputs (all in clock cycles)
    //-------------------------------------------------------------------------
    output reg  [31:0] capture_duration,   // Total capture time
    output reg  [31:0] time_to_first_flux, // Time from start to first flux
    output reg  [31:0] time_to_first_index,// Time from start to first index

    // Index timing
    output reg  [31:0] index_period_last,  // Last index-to-index period
    output reg  [31:0] index_period_min,   // Minimum index period
    output reg  [31:0] index_period_max,   // Maximum index period
    output reg  [31:0] index_period_avg,   // Average index period (EMA)

    // Flux timing
    output reg  [31:0] flux_interval_min,  // Minimum flux interval
    output reg  [31:0] flux_interval_max,  // Maximum flux interval
    output reg  [15:0] flux_count          // Total flux transitions
);

    //-------------------------------------------------------------------------
    // Internal State
    //-------------------------------------------------------------------------
    reg        prev_capture;
    reg        first_flux_seen;
    reg        first_index_seen;
    reg [31:0] capture_timer;
    reg [31:0] index_timer;
    reg [31:0] flux_timer;
    reg        prev_flux;
    reg        prev_index;

    //-------------------------------------------------------------------------
    // Edge Detection
    //-------------------------------------------------------------------------
    wire flux_edge_det = flux_edge && !prev_flux;
    wire index_edge_det = index_pulse && !prev_index;

    //-------------------------------------------------------------------------
    // Timing Logic
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || stats_clear) begin
            capture_duration    <= 32'd0;
            time_to_first_flux  <= 32'd0;
            time_to_first_index <= 32'd0;
            index_period_last   <= 32'd0;
            index_period_min    <= 32'hFFFFFFFF;
            index_period_max    <= 32'd0;
            index_period_avg    <= 32'd0;
            flux_interval_min   <= 32'hFFFFFFFF;
            flux_interval_max   <= 32'd0;
            flux_count          <= 16'd0;
            prev_capture        <= 1'b0;
            first_flux_seen     <= 1'b0;
            first_index_seen    <= 1'b0;
            capture_timer       <= 32'd0;
            index_timer         <= 32'd0;
            flux_timer          <= 32'd0;
            prev_flux           <= 1'b0;
            prev_index          <= 1'b0;
        end else begin
            prev_flux <= flux_edge;
            prev_index <= index_pulse;
            prev_capture <= capture_active;

            // Detect capture start
            if (capture_active && !prev_capture) begin
                first_flux_seen <= 1'b0;
                first_index_seen <= 1'b0;
                capture_timer <= 32'd0;
                index_timer <= 32'd0;
                flux_timer <= 32'd0;
                flux_count <= 16'd0;
            end

            if (capture_active) begin
                // Increment capture timer
                capture_timer <= capture_timer + 1;
                index_timer <= index_timer + 1;
                flux_timer <= flux_timer + 1;

                // First flux detection
                if (flux_edge_det && !first_flux_seen) begin
                    time_to_first_flux <= capture_timer;
                    first_flux_seen <= 1'b1;
                end

                // First index detection
                if (index_edge_det && !first_index_seen) begin
                    time_to_first_index <= capture_timer;
                    first_index_seen <= 1'b1;
                end

                // Flux interval tracking
                if (flux_edge_det) begin
                    flux_count <= flux_count + 1;

                    if (flux_timer < flux_interval_min)
                        flux_interval_min <= flux_timer;
                    if (flux_timer > flux_interval_max)
                        flux_interval_max <= flux_timer;

                    flux_timer <= 32'd0;
                end

                // Index period tracking
                if (index_edge_det && first_index_seen) begin
                    index_period_last <= index_timer;

                    if (index_timer < index_period_min)
                        index_period_min <= index_timer;
                    if (index_timer > index_period_max)
                        index_period_max <= index_timer;

                    // EMA for average (alpha = 1/8)
                    index_period_avg <= index_period_avg +
                                       ((index_timer - index_period_avg) >>> 3);

                    index_timer <= 32'd0;
                end
            end

            // Capture end - record duration
            if (prev_capture && !capture_active) begin
                capture_duration <= capture_timer;
            end
        end
    end

endmodule
