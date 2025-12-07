//-----------------------------------------------------------------------------
// Signal Quality Scorer - Edge Quality and Rate Analysis
//
// Analyzes the quality of the data signal to help discriminate between:
//   - Good SE signal (MFM/RLL) vs bad SE (wrong mode)
//   - Good DIFF signal (ESDI) vs bad DIFF (wrong mode)
//
// Metrics:
//   - Edge count (should match expected rate)
//   - Runt pulse count (too narrow = noise)
//   - Long pulse count (too wide = missing edges)
//   - Pulse width variance (stable = good)
//   - Histogram peak clarity (single peak = good)
//
// Part of Phase 0: Pre-Personality Interface Detection
//
// Clock domain: 300 MHz (HDD domain)
// Created: 2025-12-04 12:55
//-----------------------------------------------------------------------------

module signal_quality_scorer (
    input  wire        clk,              // 300 MHz
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        enable,           // Enable measurement
    input  wire        clear,            // Clear accumulators
    input  wire [15:0] expected_rate,    // Expected pulse width (clocks), 0=auto

    //-------------------------------------------------------------------------
    // Data Input
    //-------------------------------------------------------------------------
    input  wire        data_in,          // Data stream from receiver

    //-------------------------------------------------------------------------
    // Results
    //-------------------------------------------------------------------------
    output reg  [7:0]  quality,          // 0-255 overall quality score
    output reg  [15:0] edge_count,       // Total edges detected
    output reg  [7:0]  runt_count,       // Pulses < min_width (saturating)
    output reg  [7:0]  long_count,       // Pulses > max_width (saturating)
    output reg  [15:0] avg_pulse_width,  // Average pulse width
    output reg  [15:0] min_pulse_width,  // Minimum pulse width seen
    output reg  [15:0] max_pulse_width,  // Maximum pulse width seen
    output reg  [2:0]  best_rate_bin     // Histogram bin with most hits
);

    //-------------------------------------------------------------------------
    // Pulse Width Thresholds at 300 MHz
    //-------------------------------------------------------------------------
    // Runt: < 23 clocks (77ns) - too short to be valid data
    // Valid ranges by rate:
    //   5 Mbps MFM:   60-300 clocks (200-1000ns)
    //   7.5 Mbps RLL: 38-375 clocks (127-1250ns, RLL has wider range)
    //   10 Mbps ESDI: 30-225 clocks (100-750ns)
    //   15 Mbps ESDI: 19-150 clocks (63-500ns)

    localparam [15:0] RUNT_THRESHOLD    = 16'd23;    // < 77ns
    localparam [15:0] LONG_THRESHOLD    = 16'd450;   // > 1.5µs

    //-------------------------------------------------------------------------
    // Histogram Bins (for rate detection)
    //-------------------------------------------------------------------------
    // Bin 0: 0-38 clocks (noise/invalid or 15 Mbps)
    // Bin 1: 38-60 clocks (15 Mbps range)
    // Bin 2: 60-90 clocks (10 Mbps range)
    // Bin 3: 90-135 clocks (7.5 Mbps range)
    // Bin 4: 135-188 clocks (5 Mbps range)
    // Bin 5: 188-300 clocks (extended MFM)
    // Bin 6: 300-450 clocks (sync gaps)
    // Bin 7: 450+ clocks (very long, gaps)

    reg [15:0] histogram [0:7];

    //-------------------------------------------------------------------------
    // Signal Synchronization
    //-------------------------------------------------------------------------
    reg [2:0] data_sync;
    reg       data_prev;
    wire      data_edge;

    always @(posedge clk) begin
        if (reset) begin
            data_sync <= 3'b000;
            data_prev <= 1'b0;
        end else begin
            data_sync <= {data_sync[1:0], data_in};
            data_prev <= data_sync[2];
        end
    end

    assign data_edge = (data_sync[2] != data_prev);

    //-------------------------------------------------------------------------
    // Pulse Width Measurement
    //-------------------------------------------------------------------------
    reg [15:0] pulse_counter;
    reg [31:0] pulse_sum;            // For average calculation
    reg [15:0] pulse_count_for_avg;

    // Histogram bin lookup
    function [2:0] get_bin;
        input [15:0] width;
        begin
            if (width < 16'd38)       get_bin = 3'd0;
            else if (width < 16'd60)  get_bin = 3'd1;
            else if (width < 16'd90)  get_bin = 3'd2;
            else if (width < 16'd135) get_bin = 3'd3;
            else if (width < 16'd188) get_bin = 3'd4;
            else if (width < 16'd300) get_bin = 3'd5;
            else if (width < 16'd450) get_bin = 3'd6;
            else                      get_bin = 3'd7;
        end
    endfunction

    //-------------------------------------------------------------------------
    // Main Measurement Logic
    //-------------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (reset || clear) begin
            pulse_counter <= 16'd0;
            pulse_sum <= 32'd0;
            pulse_count_for_avg <= 16'd0;
            edge_count <= 16'd0;
            runt_count <= 8'd0;
            long_count <= 8'd0;
            avg_pulse_width <= 16'd0;
            min_pulse_width <= 16'hFFFF;
            max_pulse_width <= 16'd0;
            quality <= 8'd0;
            best_rate_bin <= 3'd0;

            for (i = 0; i < 8; i = i + 1)
                histogram[i] <= 16'd0;
        end else if (enable) begin
            if (data_edge) begin
                // Edge detected
                if (edge_count < 16'hFFFF)
                    edge_count <= edge_count + 1;

                // Process pulse width (if not first edge)
                if (pulse_counter > 16'd0) begin
                    // Accumulate for average
                    pulse_sum <= pulse_sum + {16'd0, pulse_counter};
                    if (pulse_count_for_avg < 16'hFFFF)
                        pulse_count_for_avg <= pulse_count_for_avg + 1;

                    // Update min/max
                    if (pulse_counter < min_pulse_width)
                        min_pulse_width <= pulse_counter;
                    if (pulse_counter > max_pulse_width)
                        max_pulse_width <= pulse_counter;

                    // Check for runts
                    if (pulse_counter < RUNT_THRESHOLD) begin
                        if (runt_count < 8'hFF)
                            runt_count <= runt_count + 1;
                    end

                    // Check for long pulses
                    if (pulse_counter > LONG_THRESHOLD) begin
                        if (long_count < 8'hFF)
                            long_count <= long_count + 1;
                    end

                    // Update histogram
                    begin
                        reg [2:0] bin;
                        bin = get_bin(pulse_counter);
                        if (histogram[bin] < 16'hFFFF)
                            histogram[bin] <= histogram[bin] + 1;
                    end
                end

                // Reset counter for next pulse
                pulse_counter <= 16'd0;
            end else begin
                // Increment pulse width counter
                if (pulse_counter < 16'hFFFF)
                    pulse_counter <= pulse_counter + 1;
            end

            //-------------------------------------------------------------
            // Update statistics periodically
            //-------------------------------------------------------------
            if (edge_count >= 16'd128 && edge_count[6:0] == 7'd0) begin
                // Calculate average
                if (pulse_count_for_avg > 16'd0) begin
                    avg_pulse_width <= pulse_sum[31:16] / pulse_count_for_avg[15:0];
                end

                // Find best histogram bin
                begin
                    reg [2:0] best_bin;
                    reg [15:0] best_count;
                    best_bin = 3'd0;
                    best_count = histogram[0];

                    for (i = 1; i < 8; i = i + 1) begin
                        if (histogram[i] > best_count) begin
                            best_count = histogram[i];
                            best_bin = i[2:0];
                        end
                    end
                    best_rate_bin <= best_bin;
                end

                // Calculate quality score
                begin
                    reg [7:0] edge_score;
                    reg [7:0] runt_score;
                    reg [7:0] variance_score;
                    reg [7:0] histogram_score;

                    // Edge count score (more edges = better)
                    if (edge_count >= 16'd10000)
                        edge_score = 8'd255;
                    else if (edge_count >= 16'd5000)
                        edge_score = 8'd224;
                    else if (edge_count >= 16'd1000)
                        edge_score = 8'd192;
                    else if (edge_count >= 16'd500)
                        edge_score = 8'd160;
                    else if (edge_count >= 16'd100)
                        edge_score = 8'd128;
                    else
                        edge_score = 8'd64;

                    // Runt score (fewer runts = better)
                    if (runt_count == 8'd0)
                        runt_score = 8'd255;
                    else if (runt_count < 8'd5)
                        runt_score = 8'd224;
                    else if (runt_count < 8'd20)
                        runt_score = 8'd192;
                    else if (runt_count < 8'd50)
                        runt_score = 8'd128;
                    else
                        runt_score = 8'd64;

                    // Variance score (smaller range = better)
                    begin
                        reg [15:0] range;
                        range = max_pulse_width - min_pulse_width;

                        if (range < 16'd50)
                            variance_score = 8'd255;
                        else if (range < 16'd100)
                            variance_score = 8'd224;
                        else if (range < 16'd200)
                            variance_score = 8'd192;
                        else if (range < 16'd400)
                            variance_score = 8'd160;
                        else
                            variance_score = 8'd128;
                    end

                    // Histogram score (clear peak = better)
                    // Good signal has >50% of pulses in 2 adjacent bins
                    begin
                        reg [15:0] peak_count;
                        reg [15:0] total_count;

                        peak_count = histogram[best_rate_bin];
                        if (best_rate_bin > 3'd0)
                            peak_count = peak_count + histogram[best_rate_bin - 1];
                        if (best_rate_bin < 3'd7)
                            peak_count = peak_count + histogram[best_rate_bin + 1];

                        total_count = 16'd0;
                        for (i = 0; i < 8; i = i + 1)
                            total_count = total_count + histogram[i];

                        if (total_count > 16'd0) begin
                            if (peak_count > (total_count >> 1))  // >50%
                                histogram_score = 8'd255;
                            else if (peak_count > (total_count >> 2))  // >25%
                                histogram_score = 8'd192;
                            else
                                histogram_score = 8'd128;
                        end else begin
                            histogram_score = 8'd64;
                        end
                    end

                    // Combined quality score (weighted average)
                    // Edge: 20%, Runt: 30%, Variance: 25%, Histogram: 25%
                    quality <= (edge_score >> 2) +          // 25%
                               ({1'b0, runt_score} +
                                {2'b0, runt_score[7:1]}) >> 2 +  // ~37.5%
                               (variance_score >> 2) +      // 25%
                               (histogram_score >> 3);      // 12.5%
                end
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Rate Classifier - Maps histogram bin to data rate code
//-----------------------------------------------------------------------------
module rate_classifier (
    input  wire [2:0]  best_bin,         // From signal_quality_scorer
    input  wire [15:0] avg_pulse_width,  // Average pulse width

    output reg  [2:0]  rate_code,        // 0=unknown, 1=5M, 2=7.5M, 3=10M, 4=15M
    output reg  [7:0]  confidence        // 0-255 confidence in classification
);

    always @(*) begin
        case (best_bin)
            3'd0: begin
                // Very short pulses - possibly 15 Mbps or noise
                if (avg_pulse_width > 16'd25 && avg_pulse_width < 16'd60) begin
                    rate_code = 3'd4;    // 15 Mbps
                    confidence = 8'd200;
                end else begin
                    rate_code = 3'd0;    // Unknown/noise
                    confidence = 8'd64;
                end
            end

            3'd1: begin
                // 50-80 clocks - 15 Mbps or 10 Mbps
                if (avg_pulse_width < 16'd70) begin
                    rate_code = 3'd4;    // 15 Mbps
                    confidence = 8'd224;
                end else begin
                    rate_code = 3'd3;    // 10 Mbps
                    confidence = 8'd192;
                end
            end

            3'd2: begin
                // 80-120 clocks - 10 Mbps
                rate_code = 3'd3;
                confidence = 8'd255;
            end

            3'd3: begin
                // 120-180 clocks - 7.5 Mbps (RLL) or 10 Mbps
                if (avg_pulse_width < 16'd140) begin
                    rate_code = 3'd3;    // 10 Mbps
                    confidence = 8'd192;
                end else begin
                    rate_code = 3'd2;    // 7.5 Mbps
                    confidence = 8'd224;
                end
            end

            3'd4: begin
                // 180-250 clocks - 5 Mbps (MFM) or 7.5 Mbps
                if (avg_pulse_width < 16'd200) begin
                    rate_code = 3'd2;    // 7.5 Mbps
                    confidence = 8'd192;
                end else begin
                    rate_code = 3'd1;    // 5 Mbps
                    confidence = 8'd255;
                end
            end

            3'd5: begin
                // 250-400 clocks - Extended MFM/RLL
                rate_code = 3'd1;        // 5 Mbps (or RLL extended)
                confidence = 8'd200;
            end

            3'd6, 3'd7: begin
                // Very long pulses - sync gaps or bad signal
                rate_code = 3'd1;        // Default to 5 Mbps
                confidence = 8'd128;
            end

            default: begin
                rate_code = 3'd0;
                confidence = 8'd0;
            end
        endcase
    end

endmodule
