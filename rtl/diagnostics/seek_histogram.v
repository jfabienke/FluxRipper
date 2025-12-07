//-----------------------------------------------------------------------------
// Seek Distance Histogram for FluxRipper HDD Interface
//
// Tracks seek operations by distance to characterize drive mechanics
// and identify potential issues:
//   - Short seeks (0-10 cylinders)
//   - Medium seeks (11-50 cylinders)
//   - Long seeks (51-200 cylinders)
//   - Full seeks (201+ cylinders)
//
// Also tracks seek timing for each distance bucket.
//
// Created: 2025-12-04 13:15
//-----------------------------------------------------------------------------

module seek_histogram (
    input  wire        clk,
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Seek Event Inputs
    //-------------------------------------------------------------------------
    input  wire        seek_start,          // Seek operation started
    input  wire        seek_complete,       // Seek operation completed
    input  wire        seek_error,          // Seek failed
    input  wire [15:0] seek_distance,       // Cylinders moved (absolute)

    //-------------------------------------------------------------------------
    // Control
    //-------------------------------------------------------------------------
    input  wire        stats_clear,

    //-------------------------------------------------------------------------
    // Distance Histogram (8 buckets)
    //-------------------------------------------------------------------------
    output reg  [15:0] seeks_0_1,           // 0-1 cylinders (track-to-track)
    output reg  [15:0] seeks_2_10,          // 2-10 cylinders (short)
    output reg  [15:0] seeks_11_25,         // 11-25 cylinders
    output reg  [15:0] seeks_26_50,         // 26-50 cylinders
    output reg  [15:0] seeks_51_100,        // 51-100 cylinders
    output reg  [15:0] seeks_101_200,       // 101-200 cylinders
    output reg  [15:0] seeks_201_500,       // 201-500 cylinders
    output reg  [15:0] seeks_501_plus,      // 501+ cylinders (full stroke)

    //-------------------------------------------------------------------------
    // Timing Statistics per Bucket (average seek time in microseconds)
    //-------------------------------------------------------------------------
    output reg  [15:0] time_0_1,            // Avg time for 0-1 cyl seeks
    output reg  [15:0] time_2_10,
    output reg  [15:0] time_11_25,
    output reg  [15:0] time_26_50,
    output reg  [15:0] time_51_100,
    output reg  [15:0] time_101_200,
    output reg  [15:0] time_201_500,
    output reg  [15:0] time_501_plus,

    //-------------------------------------------------------------------------
    // Summary Statistics
    //-------------------------------------------------------------------------
    output reg  [31:0] total_seeks,         // Total seek operations
    output reg  [31:0] total_errors,        // Total seek errors
    output reg  [31:0] total_seek_time,     // Cumulative seek time (clocks)
    output reg  [15:0] avg_seek_time,       // Average seek time (microseconds)
    output reg  [15:0] min_seek_time,       // Minimum seek time
    output reg  [15:0] max_seek_time,       // Maximum seek time

    // Per-bucket error counts
    output reg  [7:0]  errors_short,        // Errors on seeks < 25 cyl
    output reg  [7:0]  errors_medium,       // Errors on seeks 25-100 cyl
    output reg  [7:0]  errors_long          // Errors on seeks > 100 cyl
);

    //-------------------------------------------------------------------------
    // Clock frequency for time conversion (300 MHz HDD domain)
    //-------------------------------------------------------------------------
    localparam CLK_MHZ = 300;

    //-------------------------------------------------------------------------
    // Internal State
    //-------------------------------------------------------------------------
    reg        seek_in_progress;
    reg [31:0] seek_timer;
    reg [15:0] current_distance;
    reg [2:0]  current_bucket;

    // Running averages for each bucket (scaled by 16 for precision)
    reg [31:0] time_accum [0:7];
    reg [15:0] time_count [0:7];

    //-------------------------------------------------------------------------
    // Bucket Selection
    //-------------------------------------------------------------------------
    function [2:0] get_bucket;
        input [15:0] distance;
        begin
            if (distance <= 16'd1)
                get_bucket = 3'd0;
            else if (distance <= 16'd10)
                get_bucket = 3'd1;
            else if (distance <= 16'd25)
                get_bucket = 3'd2;
            else if (distance <= 16'd50)
                get_bucket = 3'd3;
            else if (distance <= 16'd100)
                get_bucket = 3'd4;
            else if (distance <= 16'd200)
                get_bucket = 3'd5;
            else if (distance <= 16'd500)
                get_bucket = 3'd6;
            else
                get_bucket = 3'd7;
        end
    endfunction

    //-------------------------------------------------------------------------
    // Convert clocks to microseconds
    // For 300 MHz: 1 µs = 300 clocks
    //-------------------------------------------------------------------------
    function [15:0] clocks_to_us;
        input [31:0] clocks;
        begin
            clocks_to_us = clocks / CLK_MHZ;
        end
    endfunction

    //-------------------------------------------------------------------------
    // Seek Tracking
    //-------------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (reset || stats_clear) begin
            seek_in_progress <= 1'b0;
            seek_timer <= 32'd0;
            current_distance <= 16'd0;
            current_bucket <= 3'd0;

            // Clear counters
            seeks_0_1 <= 16'd0;
            seeks_2_10 <= 16'd0;
            seeks_11_25 <= 16'd0;
            seeks_26_50 <= 16'd0;
            seeks_51_100 <= 16'd0;
            seeks_101_200 <= 16'd0;
            seeks_201_500 <= 16'd0;
            seeks_501_plus <= 16'd0;

            time_0_1 <= 16'd0;
            time_2_10 <= 16'd0;
            time_11_25 <= 16'd0;
            time_26_50 <= 16'd0;
            time_51_100 <= 16'd0;
            time_101_200 <= 16'd0;
            time_201_500 <= 16'd0;
            time_501_plus <= 16'd0;

            total_seeks <= 32'd0;
            total_errors <= 32'd0;
            total_seek_time <= 32'd0;
            avg_seek_time <= 16'd0;
            min_seek_time <= 16'hFFFF;
            max_seek_time <= 16'd0;

            errors_short <= 8'd0;
            errors_medium <= 8'd0;
            errors_long <= 8'd0;

            for (i = 0; i < 8; i = i + 1) begin
                time_accum[i] <= 32'd0;
                time_count[i] <= 16'd0;
            end
        end else begin
            // Seek start
            if (seek_start && !seek_in_progress) begin
                seek_in_progress <= 1'b1;
                seek_timer <= 32'd0;
                current_distance <= seek_distance;
                current_bucket <= get_bucket(seek_distance);
            end

            // Timer while seeking
            if (seek_in_progress) begin
                seek_timer <= seek_timer + 1;
            end

            // Seek complete
            if (seek_complete && seek_in_progress) begin
                seek_in_progress <= 1'b0;

                // Record total seeks
                if (total_seeks != 32'hFFFFFFFF)
                    total_seeks <= total_seeks + 1;

                // Accumulate total time
                total_seek_time <= total_seek_time + seek_timer;

                // Convert to microseconds
                wire [15:0] seek_us = clocks_to_us(seek_timer);

                // Update min/max
                if (seek_us < min_seek_time)
                    min_seek_time <= seek_us;
                if (seek_us > max_seek_time)
                    max_seek_time <= seek_us;

                // Update bucket count
                case (current_bucket)
                    3'd0: if (seeks_0_1 != 16'hFFFF) seeks_0_1 <= seeks_0_1 + 1;
                    3'd1: if (seeks_2_10 != 16'hFFFF) seeks_2_10 <= seeks_2_10 + 1;
                    3'd2: if (seeks_11_25 != 16'hFFFF) seeks_11_25 <= seeks_11_25 + 1;
                    3'd3: if (seeks_26_50 != 16'hFFFF) seeks_26_50 <= seeks_26_50 + 1;
                    3'd4: if (seeks_51_100 != 16'hFFFF) seeks_51_100 <= seeks_51_100 + 1;
                    3'd5: if (seeks_101_200 != 16'hFFFF) seeks_101_200 <= seeks_101_200 + 1;
                    3'd6: if (seeks_201_500 != 16'hFFFF) seeks_201_500 <= seeks_201_500 + 1;
                    3'd7: if (seeks_501_plus != 16'hFFFF) seeks_501_plus <= seeks_501_plus + 1;
                endcase

                // Update bucket timing (running average)
                if (time_count[current_bucket] != 16'hFFFF) begin
                    time_accum[current_bucket] <= time_accum[current_bucket] + seek_timer;
                    time_count[current_bucket] <= time_count[current_bucket] + 1;
                end

                // Update average seek time
                if (total_seeks > 0) begin
                    avg_seek_time <= clocks_to_us(total_seek_time / total_seeks);
                end
            end

            // Seek error
            if (seek_error && seek_in_progress) begin
                seek_in_progress <= 1'b0;

                if (total_errors != 32'hFFFFFFFF)
                    total_errors <= total_errors + 1;

                // Categorize error by distance
                if (current_distance <= 25) begin
                    if (errors_short != 8'hFF)
                        errors_short <= errors_short + 1;
                end else if (current_distance <= 100) begin
                    if (errors_medium != 8'hFF)
                        errors_medium <= errors_medium + 1;
                end else begin
                    if (errors_long != 8'hFF)
                        errors_long <= errors_long + 1;
                end
            end

            // Calculate bucket average times
            if (time_count[0] > 0) time_0_1 <= clocks_to_us(time_accum[0] / time_count[0]);
            if (time_count[1] > 0) time_2_10 <= clocks_to_us(time_accum[1] / time_count[1]);
            if (time_count[2] > 0) time_11_25 <= clocks_to_us(time_accum[2] / time_count[2]);
            if (time_count[3] > 0) time_26_50 <= clocks_to_us(time_accum[3] / time_count[3]);
            if (time_count[4] > 0) time_51_100 <= clocks_to_us(time_accum[4] / time_count[4]);
            if (time_count[5] > 0) time_101_200 <= clocks_to_us(time_accum[5] / time_count[5]);
            if (time_count[6] > 0) time_201_500 <= clocks_to_us(time_accum[6] / time_count[6]);
            if (time_count[7] > 0) time_501_plus <= clocks_to_us(time_accum[7] / time_count[7]);
        end
    end

endmodule
