//-----------------------------------------------------------------------------
// Flux Interval Analyzer
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Measures flux transition intervals to auto-detect data rate.
// Uses running average and histogram-based classification.
//
// Data Rate Detection:
//   250 Kbps: 4.0 µs bit cell = 800 clocks @ 200 MHz (avg ~400 flux interval)
//   300 Kbps: 3.33 µs bit cell = 667 clocks @ 200 MHz (avg ~333 flux interval)
//   500 Kbps: 2.0 µs bit cell = 400 clocks @ 200 MHz (avg ~200 flux interval)
//   1 Mbps:   1.0 µs bit cell = 200 clocks @ 200 MHz (avg ~100 flux interval)
//
// Target: AMD Spartan UltraScale+ SCU35
// Created: 2025-12-04 01:15
//-----------------------------------------------------------------------------

module flux_analyzer (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Flux transition input
    input  wire        flux_transition,   // Pulse on each flux transition

    // Analysis outputs
    output reg  [15:0] avg_interval,      // Average flux interval (clocks)
    output reg  [15:0] min_interval,      // Minimum interval seen
    output reg  [15:0] max_interval,      // Maximum interval seen

    // Data rate detection
    output reg  [1:0]  detected_rate,     // 00=500K, 01=300K, 10=250K, 11=1M
    output reg         rate_valid,        // Detection complete
    output reg         rate_locked        // Rate stable for N samples
);

    //-------------------------------------------------------------------------
    // Timing Thresholds (at 200 MHz clock)
    //-------------------------------------------------------------------------
    // These are average flux intervals (between transitions)
    // MFM has 1.0T, 1.5T, 2.0T patterns, so average ~1.5T

    // Boundaries between data rates (using average interval)
    // Values chosen to be midpoints between expected averages
    localparam [15:0] THRESH_1M_500K   = 16'd150;   // 1M: ~100, 500K: ~200
    localparam [15:0] THRESH_500K_300K = 16'd265;   // 500K: ~200, 300K: ~333
    localparam [15:0] THRESH_300K_250K = 16'd365;   // 300K: ~333, 250K: ~400

    // Valid range for intervals (reject noise/invalid pulses)
    localparam [15:0] MIN_VALID_INTERVAL = 16'd50;    // ~4 MHz (way too fast)
    localparam [15:0] MAX_VALID_INTERVAL = 16'd1000;  // ~200 KHz (too slow)

    // Samples needed for valid detection
    localparam [7:0] SAMPLES_FOR_VALID  = 8'd64;
    localparam [7:0] SAMPLES_FOR_LOCKED = 8'd128;

    //-------------------------------------------------------------------------
    // Interval Measurement
    //-------------------------------------------------------------------------
    reg [15:0] interval_counter;
    reg [15:0] last_interval;
    reg        first_transition;

    //-------------------------------------------------------------------------
    // Running Average (exponential moving average)
    //-------------------------------------------------------------------------
    // Using alpha = 1/16 for smoothing: avg = avg + (new - avg) / 16
    reg [23:0] avg_accum;        // Higher precision accumulator
    reg [7:0]  sample_count;
    reg [1:0]  prev_rate;
    reg [7:0]  stable_count;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            interval_counter <= 16'd0;
            last_interval    <= 16'd0;
            first_transition <= 1'b1;
            avg_accum        <= 24'd0;
            avg_interval     <= 16'd0;
            min_interval     <= 16'hFFFF;
            max_interval     <= 16'd0;
            detected_rate    <= 2'b00;
            rate_valid       <= 1'b0;
            rate_locked      <= 1'b0;
            sample_count     <= 8'd0;
            prev_rate        <= 2'b00;
            stable_count     <= 8'd0;
        end
        else if (enable) begin
            // Increment interval counter
            if (interval_counter < 16'hFFFF)
                interval_counter <= interval_counter + 1'b1;

            if (flux_transition) begin
                if (first_transition) begin
                    // First transition, just start counting
                    first_transition <= 1'b0;
                    interval_counter <= 16'd0;
                end
                else begin
                    last_interval <= interval_counter;

                    // Only process valid intervals
                    if (interval_counter >= MIN_VALID_INTERVAL &&
                        interval_counter <= MAX_VALID_INTERVAL) begin

                        // Update min/max
                        if (interval_counter < min_interval)
                            min_interval <= interval_counter;
                        if (interval_counter > max_interval)
                            max_interval <= interval_counter;

                        // Update running average (EMA with alpha = 1/16)
                        // avg = avg + (new - avg) / 16
                        if (sample_count == 0) begin
                            // First sample, initialize average
                            avg_accum <= {interval_counter, 8'd0};
                            avg_interval <= interval_counter;
                        end
                        else begin
                            // Exponential moving average
                            avg_accum <= avg_accum +
                                         (({interval_counter, 8'd0} - avg_accum) >> 4);
                            avg_interval <= avg_accum[23:8];
                        end

                        // Increment sample count
                        if (sample_count < 8'hFF)
                            sample_count <= sample_count + 1'b1;

                        // Classify data rate based on average interval
                        if (sample_count >= 8'd16) begin
                            // Enough samples to start classifying
                            if (avg_interval < THRESH_1M_500K) begin
                                detected_rate <= 2'b11;  // 1 Mbps
                            end
                            else if (avg_interval < THRESH_500K_300K) begin
                                detected_rate <= 2'b00;  // 500 Kbps (HD 3.5")
                            end
                            else if (avg_interval < THRESH_300K_250K) begin
                                detected_rate <= 2'b01;  // 300 Kbps (HD 5.25")
                            end
                            else begin
                                detected_rate <= 2'b10;  // 250 Kbps (DD)
                            end
                        end

                        // Check if rate is valid
                        if (sample_count >= SAMPLES_FOR_VALID)
                            rate_valid <= 1'b1;

                        // Check if rate is locked (stable for many samples)
                        if (detected_rate == prev_rate) begin
                            if (stable_count < 8'hFF)
                                stable_count <= stable_count + 1'b1;
                            if (stable_count >= SAMPLES_FOR_LOCKED)
                                rate_locked <= 1'b1;
                        end
                        else begin
                            stable_count <= 8'd0;
                            rate_locked <= 1'b0;
                        end

                        prev_rate <= detected_rate;
                    end

                    interval_counter <= 16'd0;
                end
            end
        end
        else begin
            // Disabled - reset detection but keep last values
            first_transition <= 1'b1;
            interval_counter <= 16'd0;
            sample_count     <= 8'd0;
            stable_count     <= 8'd0;
            rate_valid       <= 1'b0;
            rate_locked      <= 1'b0;
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Data Rate Detector Wrapper
// Instantiates flux_analyzer and provides simplified interface for FDC core
//-----------------------------------------------------------------------------
module data_rate_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Flux input (from read data synchronizer)
    input  wire        flux_in,

    // Auto-detection control
    input  wire        auto_rate_enable,  // Enable auto data rate detection
    input  wire [1:0]  manual_rate,       // Manual rate setting

    // Outputs
    output wire [1:0]  effective_rate,    // Rate to use (auto or manual)
    output wire        rate_detected,     // Auto-detection complete
    output wire        rate_locked,       // Rate is stable
    output wire [15:0] debug_avg_interval // For debugging
);

    // Edge detection for flux_in
    reg [2:0] flux_sync;
    wire flux_edge;

    always @(posedge clk) begin
        if (reset)
            flux_sync <= 3'b000;
        else
            flux_sync <= {flux_sync[1:0], flux_in};
    end

    assign flux_edge = (flux_sync[2:1] == 2'b01);

    // Flux analyzer instance
    wire [1:0]  detected_rate;
    wire        rate_valid;
    wire        analyzer_locked;
    wire [15:0] avg_interval;

    flux_analyzer u_analyzer (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .flux_transition(flux_edge),
        .avg_interval(avg_interval),
        .min_interval(),
        .max_interval(),
        .detected_rate(detected_rate),
        .rate_valid(rate_valid),
        .rate_locked(analyzer_locked)
    );

    // Output assignments
    assign effective_rate    = (auto_rate_enable && rate_valid) ? detected_rate : manual_rate;
    assign rate_detected     = rate_valid;
    assign rate_locked       = analyzer_locked;
    assign debug_avg_interval = avg_interval;

endmodule
