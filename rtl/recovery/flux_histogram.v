//-----------------------------------------------------------------------------
// Flux Histogram Builder for FluxStat Recovery
//
// Real-time histogram of flux transition intervals during capture.
// Used to identify data rate, analyze timing distribution, and detect
// weak/marginal bit cells.
//
// Features:
//   - 256-bin histogram (configurable bin width)
//   - Running statistics: min, max, mean, peak bin
//   - Overflow/underflow counting
//   - Snapshot capability for multi-pass comparison
//
// Created: 2025-12-04 18:00
//-----------------------------------------------------------------------------

module flux_histogram #(
    parameter BIN_COUNT     = 256,          // Number of histogram bins
    parameter BIN_WIDTH     = 16,           // Counter width per bin
    parameter INTERVAL_BITS = 16,           // Flux interval input width
    parameter BIN_SHIFT     = 2             // Right-shift for bin index (interval >> BIN_SHIFT)
)(
    input  wire                    clk,
    input  wire                    reset,

    //-------------------------------------------------------------------------
    // Flux Input Interface
    //-------------------------------------------------------------------------
    input  wire                    flux_valid,      // Pulse on each flux transition
    input  wire [INTERVAL_BITS-1:0] flux_interval,  // Time since last transition (clocks)

    //-------------------------------------------------------------------------
    // Control
    //-------------------------------------------------------------------------
    input  wire                    enable,          // Enable histogram collection
    input  wire                    clear,           // Clear all bins and stats
    input  wire                    snapshot,        // Capture current stats to snapshot regs

    //-------------------------------------------------------------------------
    // Histogram Read Interface
    //-------------------------------------------------------------------------
    input  wire [7:0]              read_bin,        // Bin index to read
    output wire [BIN_WIDTH-1:0]    read_data,       // Bin count at read_bin

    //-------------------------------------------------------------------------
    // Statistics Output
    //-------------------------------------------------------------------------
    output reg  [31:0]             total_count,     // Total flux transitions counted
    output reg  [INTERVAL_BITS-1:0] interval_min,   // Minimum interval seen
    output reg  [INTERVAL_BITS-1:0] interval_max,   // Maximum interval seen
    output reg  [7:0]              peak_bin,        // Bin with highest count
    output reg  [BIN_WIDTH-1:0]    peak_count,      // Count in peak bin
    output reg  [31:0]             overflow_count,  // Intervals above max bin
    output reg  [31:0]             underflow_count, // Intervals below min bin (if applicable)

    //-------------------------------------------------------------------------
    // Running Mean (EMA approximation)
    //-------------------------------------------------------------------------
    output reg  [INTERVAL_BITS-1:0] mean_interval,  // Exponential moving average

    //-------------------------------------------------------------------------
    // Snapshot Outputs (captured on snapshot pulse)
    //-------------------------------------------------------------------------
    output reg  [31:0]             snap_total,
    output reg  [7:0]              snap_peak_bin,
    output reg  [BIN_WIDTH-1:0]    snap_peak_count,
    output reg  [INTERVAL_BITS-1:0] snap_mean
);

    //-------------------------------------------------------------------------
    // Histogram Memory (dual-port: one for update, one for read)
    //-------------------------------------------------------------------------
    reg [BIN_WIDTH-1:0] histogram [0:BIN_COUNT-1];

    // Bin index calculation
    wire [7:0] bin_index;
    wire       bin_overflow;
    wire       bin_valid;

    // Calculate bin index from interval
    // Shift right by BIN_SHIFT to map interval range to bins
    wire [INTERVAL_BITS-1:0] shifted_interval = flux_interval >> BIN_SHIFT;

    assign bin_overflow = (shifted_interval >= BIN_COUNT);
    assign bin_index = bin_overflow ? (BIN_COUNT - 1) : shifted_interval[7:0];
    assign bin_valid = flux_valid && enable;

    //-------------------------------------------------------------------------
    // Histogram Update Logic
    //-------------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (reset || clear) begin
            // Clear all bins
            for (i = 0; i < BIN_COUNT; i = i + 1) begin
                histogram[i] <= {BIN_WIDTH{1'b0}};
            end

            // Clear statistics
            total_count     <= 32'd0;
            interval_min    <= {INTERVAL_BITS{1'b1}};  // Max value
            interval_max    <= {INTERVAL_BITS{1'b0}};
            peak_bin        <= 8'd0;
            peak_count      <= {BIN_WIDTH{1'b0}};
            overflow_count  <= 32'd0;
            underflow_count <= 32'd0;
            mean_interval   <= {INTERVAL_BITS{1'b0}};

        end else if (bin_valid) begin
            // Update total count
            total_count <= total_count + 1;

            // Update min/max
            if (flux_interval < interval_min) begin
                interval_min <= flux_interval;
            end
            if (flux_interval > interval_max) begin
                interval_max <= flux_interval;
            end

            // Update overflow counter
            if (bin_overflow) begin
                overflow_count <= overflow_count + 1;
            end

            // Increment histogram bin (saturating)
            if (histogram[bin_index] != {BIN_WIDTH{1'b1}}) begin
                histogram[bin_index] <= histogram[bin_index] + 1;

                // Update peak tracking
                if (histogram[bin_index] + 1 > peak_count) begin
                    peak_bin   <= bin_index;
                    peak_count <= histogram[bin_index] + 1;
                end
            end

            // Update running mean (EMA with alpha = 1/16)
            // new_mean = mean + (interval - mean) / 16
            //          = mean * 15/16 + interval / 16
            mean_interval <= mean_interval - (mean_interval >> 4) + (flux_interval >> 4);
        end
    end

    //-------------------------------------------------------------------------
    // Read Port
    //-------------------------------------------------------------------------
    assign read_data = histogram[read_bin];

    //-------------------------------------------------------------------------
    // Snapshot Logic
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            snap_total      <= 32'd0;
            snap_peak_bin   <= 8'd0;
            snap_peak_count <= {BIN_WIDTH{1'b0}};
            snap_mean       <= {INTERVAL_BITS{1'b0}};
        end else if (snapshot) begin
            snap_total      <= total_count;
            snap_peak_bin   <= peak_bin;
            snap_peak_count <= peak_count;
            snap_mean       <= mean_interval;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Dual-Histogram Module for Comparative Analysis
//
// Maintains two histograms for A/B comparison (e.g., current pass vs reference)
//-----------------------------------------------------------------------------
module flux_histogram_dual #(
    parameter BIN_COUNT     = 256,
    parameter BIN_WIDTH     = 16,
    parameter INTERVAL_BITS = 16,
    parameter BIN_SHIFT     = 2
)(
    input  wire                    clk,
    input  wire                    reset,

    // Flux input
    input  wire                    flux_valid,
    input  wire [INTERVAL_BITS-1:0] flux_interval,

    // Control
    input  wire                    enable,
    input  wire                    select,          // 0=histogram A, 1=histogram B
    input  wire                    clear_a,
    input  wire                    clear_b,
    input  wire                    swap,            // Swap A and B

    // Read interface (reads from both)
    input  wire [7:0]              read_bin,
    output wire [BIN_WIDTH-1:0]    read_data_a,
    output wire [BIN_WIDTH-1:0]    read_data_b,

    // Statistics from both
    output wire [31:0]             total_a,
    output wire [31:0]             total_b,
    output wire [7:0]              peak_bin_a,
    output wire [7:0]              peak_bin_b,
    output wire [INTERVAL_BITS-1:0] mean_a,
    output wire [INTERVAL_BITS-1:0] mean_b,

    // Comparison outputs
    output wire [31:0]             correlation,     // How similar are the histograms
    output wire                    rate_match       // Peak bins within tolerance
);

    // Internal select (may be swapped)
    reg select_internal;

    always @(posedge clk) begin
        if (reset) begin
            select_internal <= 1'b0;
        end else if (swap) begin
            select_internal <= ~select_internal;
        end else begin
            select_internal <= select;
        end
    end

    wire flux_valid_a = flux_valid & enable & ~select_internal;
    wire flux_valid_b = flux_valid & enable &  select_internal;

    // Histogram A
    flux_histogram #(
        .BIN_COUNT(BIN_COUNT),
        .BIN_WIDTH(BIN_WIDTH),
        .INTERVAL_BITS(INTERVAL_BITS),
        .BIN_SHIFT(BIN_SHIFT)
    ) hist_a (
        .clk(clk),
        .reset(reset),
        .flux_valid(flux_valid_a),
        .flux_interval(flux_interval),
        .enable(1'b1),
        .clear(clear_a),
        .snapshot(1'b0),
        .read_bin(read_bin),
        .read_data(read_data_a),
        .total_count(total_a),
        .interval_min(),
        .interval_max(),
        .peak_bin(peak_bin_a),
        .peak_count(),
        .overflow_count(),
        .underflow_count(),
        .mean_interval(mean_a),
        .snap_total(),
        .snap_peak_bin(),
        .snap_peak_count(),
        .snap_mean()
    );

    // Histogram B
    flux_histogram #(
        .BIN_COUNT(BIN_COUNT),
        .BIN_WIDTH(BIN_WIDTH),
        .INTERVAL_BITS(INTERVAL_BITS),
        .BIN_SHIFT(BIN_SHIFT)
    ) hist_b (
        .clk(clk),
        .reset(reset),
        .flux_valid(flux_valid_b),
        .flux_interval(flux_interval),
        .enable(1'b1),
        .clear(clear_b),
        .snapshot(1'b0),
        .read_bin(read_bin),
        .read_data(read_data_b),
        .total_count(total_b),
        .interval_min(),
        .interval_max(),
        .peak_bin(peak_bin_b),
        .peak_count(),
        .overflow_count(),
        .underflow_count(),
        .mean_interval(mean_b),
        .snap_total(),
        .snap_peak_bin(),
        .snap_peak_count(),
        .snap_mean()
    );

    // Peak bin comparison (within ±2 bins = rate match)
    wire [7:0] peak_diff = (peak_bin_a > peak_bin_b) ?
                           (peak_bin_a - peak_bin_b) :
                           (peak_bin_b - peak_bin_a);
    assign rate_match = (peak_diff <= 8'd2);

    // Simple correlation metric: sum of min(A[i], B[i]) / max(total_a, total_b)
    // This is computed in firmware due to complexity; output placeholder
    assign correlation = 32'd0;  // Computed in firmware

endmodule
