//-----------------------------------------------------------------------------
// Data Path Sniffer - SE/Differential Mode Signal Capture
//
// Captures and analyzes the 20-pin data cable signals in both modes:
//   - Single-Ended (SE): Uses one receiver, measures from data_se_rx
//   - Differential (DIFF): Uses diff receiver, measures from data_diff_rx
//                          Also captures raw A/B for correlation
//
// For each mode, computes:
//   - Signal quality score
//   - Edge density and rate
//   - Pulse width histogram
//   - A/B correlation (DIFF mode only)
//
// Part of Phase 0: Pre-Personality Interface Detection
//
// Clock domain: 300 MHz (HDD domain)
// Created: 2025-12-04 13:00
//-----------------------------------------------------------------------------

module data_path_sniffer (
    input  wire        clk,              // 300 MHz
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        sniff_start,      // Start capture
    input  wire        sniff_abort,      // Abort capture
    input  wire        sniff_mode,       // 0=SE, 1=DIFF
    input  wire [23:0] sniff_duration,   // Capture duration (clocks), 0=default
    output reg         sniff_done,       // Capture complete
    output reg         sniff_busy,       // Capture in progress

    //-------------------------------------------------------------------------
    // Data Inputs
    //-------------------------------------------------------------------------
    input  wire        data_se_rx,       // Single-ended receiver output
    input  wire        data_diff_rx,     // Differential receiver output
    input  wire        wire_a_raw,       // Raw wire A (for correlation)
    input  wire        wire_b_raw,       // Raw wire B (for correlation)
    input  wire        index_pulse,      // INDEX for rotation sync (optional)

    //-------------------------------------------------------------------------
    // Front-End Control (directly from here to PHY)
    //-------------------------------------------------------------------------
    output reg         term_enable,      // Enable 100Ω termination
    output reg         rx_mode_sel,      // 0=SE, 1=DIFF receiver select

    //-------------------------------------------------------------------------
    // Results
    //-------------------------------------------------------------------------
    output reg  [7:0]  quality_score,    // Overall signal quality 0-255
    output reg  [15:0] edge_count,       // Total edges detected
    output reg  [7:0]  runt_count,       // Runt pulses (too narrow)
    output reg  [15:0] avg_pulse_width,  // Average pulse width (clocks)
    output reg  [2:0]  best_rate_bin,    // Histogram bin with peak
    output reg  [7:0]  ab_correlation,   // A/B correlation (DIFF mode only)
    output reg         is_differential   // Detected as differential
);

    //-------------------------------------------------------------------------
    // Default Capture Duration
    //-------------------------------------------------------------------------
    // 200ms @ 300 MHz = 80,000,000 clocks
    // This gives ~12 rotations @ 3600 RPM
    localparam [23:0] DEFAULT_DURATION = 24'd80_000_000;

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [2:0]
        STATE_IDLE       = 3'd0,
        STATE_SETUP      = 3'd1,
        STATE_SETTLE     = 3'd2,
        STATE_CAPTURE    = 3'd3,
        STATE_FINALIZE   = 3'd4,
        STATE_DONE       = 3'd5;

    reg [2:0] state;

    //-------------------------------------------------------------------------
    // Capture Control
    //-------------------------------------------------------------------------
    reg [23:0] capture_counter;
    reg [23:0] active_duration;
    reg [15:0] settle_counter;
    reg        capture_mode;             // Latched sniff_mode

    localparam [15:0] SETTLE_TIME = 16.d3000;  // 10µs settling time

    //-------------------------------------------------------------------------
    // Sub-Module Interfaces
    //-------------------------------------------------------------------------

    // Signal quality scorer
    wire       sqe_enable;
    wire       sqe_clear;
    wire       sqe_data;
    wire [7:0] sqe_quality;
    wire [15:0] sqe_edge_count;
    wire [7:0] sqe_runt_count;
    wire [15:0] sqe_avg_width;
    wire [2:0] sqe_best_bin;

    // Correlation calculator
    wire       corr_enable;
    wire       corr_clear;
    wire [7:0] corr_correlation;
    wire       corr_is_diff;
    wire [15:0] corr_edge_count;
    wire [15:0] corr_match_count;

    //-------------------------------------------------------------------------
    // Data Source Multiplexing
    //-------------------------------------------------------------------------
    // Select data source based on mode
    assign sqe_data = capture_mode ? data_diff_rx : data_se_rx;

    // Control signals
    assign sqe_enable = (state == STATE_CAPTURE);
    assign sqe_clear = (state == STATE_SETUP);
    assign corr_enable = (state == STATE_CAPTURE) && capture_mode;  // Only in DIFF mode
    assign corr_clear = (state == STATE_SETUP);

    //-------------------------------------------------------------------------
    // Signal Quality Scorer Instance
    //-------------------------------------------------------------------------
    signal_quality_scorer u_scorer (
        .clk(clk),
        .reset(reset),
        .enable(sqe_enable),
        .clear(sqe_clear),
        .expected_rate(16'd0),           // Auto-detect rate
        .data_in(sqe_data),
        .quality(sqe_quality),
        .edge_count(sqe_edge_count),
        .runt_count(sqe_runt_count),
        .long_count(),                   // Not used
        .avg_pulse_width(sqe_avg_width),
        .min_pulse_width(),              // Not used
        .max_pulse_width(),              // Not used
        .best_rate_bin(sqe_best_bin)
    );

    //-------------------------------------------------------------------------
    // Correlation Calculator Instance
    //-------------------------------------------------------------------------
    correlation_calc u_correlation (
        .clk(clk),
        .reset(reset),
        .enable(corr_enable),
        .clear(corr_clear),
        .wire_a(wire_a_raw),
        .wire_b(wire_b_raw),
        .correlation(corr_correlation),
        .is_differential(corr_is_diff),
        .edge_count_a(corr_edge_count),
        .match_count(corr_match_count),
        .quality()                       // Not used (we have sqe_quality)
    );

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            sniff_done <= 1'b0;
            sniff_busy <= 1'b0;
            term_enable <= 1'b0;
            rx_mode_sel <= 1'b0;
            quality_score <= 8'd0;
            edge_count <= 16'd0;
            runt_count <= 8'd0;
            avg_pulse_width <= 16'd0;
            best_rate_bin <= 3'd0;
            ab_correlation <= 8'd0;
            is_differential <= 1'b0;
            capture_counter <= 24'd0;
            settle_counter <= 16'd0;
            capture_mode <= 1'b0;
            active_duration <= DEFAULT_DURATION;
        end else begin
            sniff_done <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    sniff_busy <= 1'b0;

                    if (sniff_start) begin
                        sniff_busy <= 1'b1;
                        capture_mode <= sniff_mode;
                        active_duration <= (sniff_duration != 24'd0) ?
                                           sniff_duration : DEFAULT_DURATION;
                        state <= STATE_SETUP;
                    end
                end

                //-------------------------------------------------------------
                STATE_SETUP: begin
                    // Configure front-end for the capture mode
                    if (capture_mode) begin
                        // Differential mode
                        term_enable <= 1'b1;     // Enable 100Ω termination
                        rx_mode_sel <= 1'b1;     // Select differential receiver
                    end else begin
                        // Single-ended mode
                        term_enable <= 1'b0;     // No termination (high-Z probe)
                        rx_mode_sel <= 1'b0;     // Select SE receiver
                    end

                    capture_counter <= 24'd0;
                    settle_counter <= 16'd0;
                    state <= STATE_SETTLE;
                end

                //-------------------------------------------------------------
                STATE_SETTLE: begin
                    // Wait for front-end to settle after mode change
                    settle_counter <= settle_counter + 1;

                    if (sniff_abort) begin
                        state <= STATE_DONE;
                    end else if (settle_counter >= SETTLE_TIME) begin
                        capture_counter <= 24'd0;
                        state <= STATE_CAPTURE;
                    end
                end

                //-------------------------------------------------------------
                STATE_CAPTURE: begin
                    capture_counter <= capture_counter + 1;

                    if (sniff_abort) begin
                        state <= STATE_FINALIZE;
                    end else if (capture_counter >= active_duration) begin
                        state <= STATE_FINALIZE;
                    end
                end

                //-------------------------------------------------------------
                STATE_FINALIZE: begin
                    // Capture results from sub-modules
                    quality_score <= sqe_quality;
                    edge_count <= sqe_edge_count;
                    runt_count <= sqe_runt_count;
                    avg_pulse_width <= sqe_avg_width;
                    best_rate_bin <= sqe_best_bin;

                    if (capture_mode) begin
                        // DIFF mode - include correlation data
                        ab_correlation <= corr_correlation;
                        is_differential <= corr_is_diff;
                    end else begin
                        // SE mode - no correlation data
                        ab_correlation <= 8'd0;
                        is_differential <= 1'b0;
                    end

                    state <= STATE_DONE;
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    sniff_done <= 1'b1;
                    sniff_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Dual-Mode Sniffer - Captures both SE and DIFF modes sequentially
//-----------------------------------------------------------------------------
module dual_mode_sniffer (
    input  wire        clk,
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control
    //-------------------------------------------------------------------------
    input  wire        capture_start,    // Start dual capture
    input  wire        capture_abort,    // Abort capture
    output reg         capture_done,     // Both captures complete
    output reg         capture_busy,

    //-------------------------------------------------------------------------
    // Data Inputs
    //-------------------------------------------------------------------------
    input  wire        data_se_rx,
    input  wire        data_diff_rx,
    input  wire        wire_a_raw,
    input  wire        wire_b_raw,
    input  wire        index_pulse,

    //-------------------------------------------------------------------------
    // Front-End Control
    //-------------------------------------------------------------------------
    output wire        term_enable,
    output wire        rx_mode_sel,

    //-------------------------------------------------------------------------
    // SE Mode Results
    //-------------------------------------------------------------------------
    output reg  [7:0]  se_quality,
    output reg  [15:0] se_edge_count,
    output reg  [15:0] se_avg_width,
    output reg  [2:0]  se_rate_bin,

    //-------------------------------------------------------------------------
    // DIFF Mode Results
    //-------------------------------------------------------------------------
    output reg  [7:0]  diff_quality,
    output reg  [15:0] diff_edge_count,
    output reg  [15:0] diff_avg_width,
    output reg  [2:0]  diff_rate_bin,
    output reg  [7:0]  diff_correlation,
    output reg         diff_is_differential,

    //-------------------------------------------------------------------------
    // Combined Decision
    //-------------------------------------------------------------------------
    output reg         se_is_better,     // SE mode gave better signal
    output reg         diff_is_better    // DIFF mode gave better signal
);

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [2:0]
        STATE_IDLE     = 3'd0,
        STATE_SE_START = 3'd1,
        STATE_SE_WAIT  = 3'd2,
        STATE_DIFF_START = 3'd3,
        STATE_DIFF_WAIT = 3'd4,
        STATE_COMPARE  = 3'd5,
        STATE_DONE     = 3'd6;

    reg [2:0] state;

    //-------------------------------------------------------------------------
    // Sniffer Control
    //-------------------------------------------------------------------------
    reg        sniff_start;
    reg        sniff_mode;
    wire       sniff_done;
    wire       sniff_busy;
    wire [7:0] sniff_quality;
    wire [15:0] sniff_edge_count;
    wire [7:0] sniff_runt;
    wire [15:0] sniff_avg_width;
    wire [2:0] sniff_rate_bin;
    wire [7:0] sniff_correlation;
    wire       sniff_is_diff;

    //-------------------------------------------------------------------------
    // Data Path Sniffer Instance
    //-------------------------------------------------------------------------
    data_path_sniffer u_sniffer (
        .clk(clk),
        .reset(reset),
        .sniff_start(sniff_start),
        .sniff_abort(capture_abort),
        .sniff_mode(sniff_mode),
        .sniff_duration(24'd0),          // Use default
        .sniff_done(sniff_done),
        .sniff_busy(sniff_busy),
        .data_se_rx(data_se_rx),
        .data_diff_rx(data_diff_rx),
        .wire_a_raw(wire_a_raw),
        .wire_b_raw(wire_b_raw),
        .index_pulse(index_pulse),
        .term_enable(term_enable),
        .rx_mode_sel(rx_mode_sel),
        .quality_score(sniff_quality),
        .edge_count(sniff_edge_count),
        .runt_count(sniff_runt),
        .avg_pulse_width(sniff_avg_width),
        .best_rate_bin(sniff_rate_bin),
        .ab_correlation(sniff_correlation),
        .is_differential(sniff_is_diff)
    );

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            capture_done <= 1'b0;
            capture_busy <= 1'b0;
            sniff_start <= 1'b0;
            sniff_mode <= 1'b0;
            se_quality <= 8'd0;
            se_edge_count <= 16'd0;
            se_avg_width <= 16'd0;
            se_rate_bin <= 3'd0;
            diff_quality <= 8'd0;
            diff_edge_count <= 16'd0;
            diff_avg_width <= 16'd0;
            diff_rate_bin <= 3'd0;
            diff_correlation <= 8'd0;
            diff_is_differential <= 1'b0;
            se_is_better <= 1'b0;
            diff_is_better <= 1'b0;
        end else begin
            capture_done <= 1'b0;
            sniff_start <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    capture_busy <= 1'b0;
                    if (capture_start) begin
                        capture_busy <= 1'b1;
                        state <= STATE_SE_START;
                    end
                end

                STATE_SE_START: begin
                    sniff_mode <= 1'b0;      // SE mode
                    sniff_start <= 1'b1;
                    state <= STATE_SE_WAIT;
                end

                STATE_SE_WAIT: begin
                    if (capture_abort) begin
                        state <= STATE_DONE;
                    end else if (sniff_done) begin
                        // Capture SE results
                        se_quality <= sniff_quality;
                        se_edge_count <= sniff_edge_count;
                        se_avg_width <= sniff_avg_width;
                        se_rate_bin <= sniff_rate_bin;
                        state <= STATE_DIFF_START;
                    end
                end

                STATE_DIFF_START: begin
                    sniff_mode <= 1'b1;      // DIFF mode
                    sniff_start <= 1'b1;
                    state <= STATE_DIFF_WAIT;
                end

                STATE_DIFF_WAIT: begin
                    if (capture_abort) begin
                        state <= STATE_COMPARE;
                    end else if (sniff_done) begin
                        // Capture DIFF results
                        diff_quality <= sniff_quality;
                        diff_edge_count <= sniff_edge_count;
                        diff_avg_width <= sniff_avg_width;
                        diff_rate_bin <= sniff_rate_bin;
                        diff_correlation <= sniff_correlation;
                        diff_is_differential <= sniff_is_diff;
                        state <= STATE_COMPARE;
                    end
                end

                STATE_COMPARE: begin
                    // Determine which mode is better
                    // DIFF is better if:
                    //   1. High correlation (actual differential signal)
                    //   2. Better quality in DIFF mode
                    // SE is better if:
                    //   1. Low/no correlation (single-ended signal)
                    //   2. Better quality in SE mode

                    if (diff_is_differential && diff_quality > se_quality) begin
                        se_is_better <= 1'b0;
                        diff_is_better <= 1'b1;
                    end else if (!diff_is_differential && se_quality >= diff_quality) begin
                        se_is_better <= 1'b1;
                        diff_is_better <= 1'b0;
                    end else if (diff_quality > se_quality + 8'd32) begin
                        // DIFF significantly better
                        se_is_better <= 1'b0;
                        diff_is_better <= 1'b1;
                    end else begin
                        // SE is default
                        se_is_better <= 1'b1;
                        diff_is_better <= 1'b0;
                    end

                    state <= STATE_DONE;
                end

                STATE_DONE: begin
                    capture_done <= 1'b1;
                    capture_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
