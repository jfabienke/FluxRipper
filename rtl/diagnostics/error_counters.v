//-----------------------------------------------------------------------------
// Lifetime Error Counters for FluxRipper
//
// Tracks cumulative error counts across all operations. These counters
// persist across captures and commands, providing insight into media
// degradation and drive health.
//
// Counters:
//   - CRC errors (data field)
//   - Address mark errors (ID field)
//   - Missing address mark
//   - Data overrun/underrun
//   - Seek errors
//   - Write faults
//
// Created: 2025-12-04 13:00
//-----------------------------------------------------------------------------

module error_counters (
    input  wire        clk,
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Error Input Strobes (active for one clock when error occurs)
    //-------------------------------------------------------------------------
    input  wire        err_crc_data,         // CRC error in data field
    input  wire        err_crc_addr,         // CRC error in address field
    input  wire        err_missing_am,       // Missing address mark
    input  wire        err_missing_dam,      // Missing data address mark
    input  wire        err_overrun,          // Data overrun
    input  wire        err_underrun,         // Data underrun
    input  wire        err_seek,             // Seek error/timeout
    input  wire        err_write_fault,      // Write fault from drive
    input  wire        err_pll_unlock,       // PLL lost lock during operation

    //-------------------------------------------------------------------------
    // Counter Clear Control
    //-------------------------------------------------------------------------
    input  wire        clear_all,            // Clear all counters
    input  wire [3:0]  clear_select,         // Clear specific counter (one-hot)

    //-------------------------------------------------------------------------
    // Counter Outputs (32-bit saturating counters)
    //-------------------------------------------------------------------------
    output reg  [31:0] cnt_crc_data,         // Total CRC data errors
    output reg  [31:0] cnt_crc_addr,         // Total CRC address errors
    output reg  [31:0] cnt_missing_am,       // Total missing AM errors
    output reg  [31:0] cnt_missing_dam,      // Total missing DAM errors
    output reg  [31:0] cnt_overrun,          // Total overrun errors
    output reg  [31:0] cnt_underrun,         // Total underrun errors
    output reg  [31:0] cnt_seek,             // Total seek errors
    output reg  [31:0] cnt_write_fault,      // Total write faults
    output reg  [31:0] cnt_pll_unlock,       // Total PLL unlock events

    //-------------------------------------------------------------------------
    // Operation Counting (for error rate)
    //-------------------------------------------------------------------------
    input  wire        operation_complete,   // Pulse when read/write completes

    //-------------------------------------------------------------------------
    // Summary Outputs
    //-------------------------------------------------------------------------
    output wire [31:0] total_errors,         // Sum of all errors
    output wire        any_error,            // At least one error occurred
    output reg  [7:0]  error_rate            // Errors per 1000 operations (0-255)
);

    //-------------------------------------------------------------------------
    // Operations counter (for error rate calculation)
    //-------------------------------------------------------------------------
    reg [31:0] operations_count;

    //-------------------------------------------------------------------------
    // Saturating increment macro
    //-------------------------------------------------------------------------
    // Increment counter if not at max value
    `define SAT_INC(cnt, strobe) \
        if (strobe && cnt != 32'hFFFFFFFF) \
            cnt <= cnt + 1

    //-------------------------------------------------------------------------
    // Counter Logic
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || clear_all) begin
            cnt_crc_data    <= 32'd0;
            cnt_crc_addr    <= 32'd0;
            cnt_missing_am  <= 32'd0;
            cnt_missing_dam <= 32'd0;
            cnt_overrun     <= 32'd0;
            cnt_underrun    <= 32'd0;
            cnt_seek        <= 32'd0;
            cnt_write_fault <= 32'd0;
            cnt_pll_unlock  <= 32'd0;
            operations_count <= 32'd0;
            error_rate      <= 8'd0;
        end else begin
            // Selective clear
            if (clear_select[0]) cnt_crc_data    <= 32'd0;
            if (clear_select[1]) cnt_crc_addr    <= 32'd0;
            if (clear_select[2]) cnt_missing_am  <= 32'd0;
            if (clear_select[3]) cnt_missing_dam <= 32'd0;

            // Count errors (saturating increment)
            `SAT_INC(cnt_crc_data, err_crc_data);
            `SAT_INC(cnt_crc_addr, err_crc_addr);
            `SAT_INC(cnt_missing_am, err_missing_am);
            `SAT_INC(cnt_missing_dam, err_missing_dam);
            `SAT_INC(cnt_overrun, err_overrun);
            `SAT_INC(cnt_underrun, err_underrun);
            `SAT_INC(cnt_seek, err_seek);
            `SAT_INC(cnt_write_fault, err_write_fault);
            `SAT_INC(cnt_pll_unlock, err_pll_unlock);

            // Count operations for error rate
            if (operation_complete && operations_count != 32'hFFFFFFFF) begin
                operations_count <= operations_count + 1;

                // Update error rate every 1000 operations
                if (operations_count[9:0] == 10'd999) begin
                    // Calculate errors per 1000 ops (saturate at 255)
                    if (total_errors > 32'd255000) begin
                        error_rate <= 8'd255;
                    end else begin
                        error_rate <= total_errors[17:10];  // Approximate /1000
                    end
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Summary Calculations
    //-------------------------------------------------------------------------
    assign total_errors = cnt_crc_data + cnt_crc_addr + cnt_missing_am +
                          cnt_missing_dam + cnt_overrun + cnt_underrun +
                          cnt_seek + cnt_write_fault + cnt_pll_unlock;

    assign any_error = (total_errors != 32'd0);

endmodule

//-----------------------------------------------------------------------------
// Per-Track Error Statistics
// Maintains error counts per track for weak track identification
//-----------------------------------------------------------------------------
module track_error_stats #(
    parameter MAX_TRACKS = 80
)(
    input  wire        clk,
    input  wire        reset,

    // Current track being accessed
    input  wire [7:0]  current_track,

    // Error strobes
    input  wire        err_crc,
    input  wire        err_am,

    // Clear
    input  wire        clear_all,

    // Query interface
    input  wire [7:0]  query_track,
    output wire [15:0] query_errors,     // Total errors for queried track
    output wire [7:0]  worst_track,      // Track with most errors
    output wire [15:0] worst_count       // Error count on worst track
);

    // Per-track error counts (8-bit saturating per track)
    reg [7:0] track_errors [0:MAX_TRACKS-1];

    // Worst track tracking
    reg [7:0]  worst_track_reg;
    reg [15:0] worst_count_reg;

    integer i;

    always @(posedge clk) begin
        if (reset || clear_all) begin
            for (i = 0; i < MAX_TRACKS; i = i + 1) begin
                track_errors[i] <= 8'd0;
            end
            worst_track_reg <= 8'd0;
            worst_count_reg <= 16'd0;
        end else begin
            // Increment error count for current track
            if ((err_crc || err_am) && current_track < MAX_TRACKS) begin
                if (track_errors[current_track] != 8'hFF) begin
                    track_errors[current_track] <= track_errors[current_track] + 1;

                    // Update worst track if this is now the worst
                    if (track_errors[current_track] + 1 > worst_count_reg[7:0]) begin
                        worst_track_reg <= current_track;
                        worst_count_reg <= {8'd0, track_errors[current_track] + 1};
                    end
                end
            end
        end
    end

    assign query_errors = {8'd0, track_errors[query_track]};
    assign worst_track = worst_track_reg;
    assign worst_count = worst_count_reg;

endmodule
