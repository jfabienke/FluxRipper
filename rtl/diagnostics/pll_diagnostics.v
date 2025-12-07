//-----------------------------------------------------------------------------
// PLL/DPLL Diagnostics Module for FluxRipper
//
// Exposes internal DPLL state for diagnostics and tuning:
//   - Phase error (instantaneous and averaged)
//   - Frequency offset from nominal (PPM)
//   - NCO frequency word
//   - Loop filter state
//   - Lock statistics
//
// Created: 2025-12-04 13:00
//-----------------------------------------------------------------------------

module pll_diagnostics (
    input  wire        clk,
    input  wire        reset,

    //-------------------------------------------------------------------------
    // PLL Status Inputs (from digital_pll)
    //-------------------------------------------------------------------------
    input  wire        pll_locked,
    input  wire [7:0]  lock_quality,        // 0-255 quality score
    input  wire [15:0] phase_error,         // Instantaneous phase error (signed)
    input  wire [31:0] phase_accum,         // NCO phase accumulator
    input  wire [1:0]  bandwidth,           // Current loop bandwidth setting
    input  wire        data_ready,          // Data bit ready strobe

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    input  wire [1:0]  data_rate,           // Expected data rate
    input  wire [31:0] nominal_freq_word,   // Nominal NCO frequency word

    //-------------------------------------------------------------------------
    // Snapshot Control
    //-------------------------------------------------------------------------
    input  wire        snapshot_trigger,    // Capture current state
    input  wire        stats_clear,         // Clear statistics

    //-------------------------------------------------------------------------
    // Diagnostic Outputs
    //-------------------------------------------------------------------------
    // Instantaneous values
    output reg  [15:0] phase_error_snap,    // Snapshotted phase error
    output reg  [31:0] freq_word_snap,      // Snapshotted frequency word

    // Averaged/filtered values
    output reg  [15:0] phase_error_avg,     // Averaged phase error (EMA)
    output reg  [15:0] phase_error_peak,    // Peak phase error seen
    output reg  [31:0] freq_offset_ppm,     // Frequency offset in PPM (signed)

    // Statistics
    output reg  [31:0] lock_time_clocks,    // Time to achieve lock
    output reg  [31:0] total_lock_time,     // Total time in locked state
    output reg  [31:0] unlock_count,        // Number of unlock events
    output reg  [15:0] lock_quality_min,    // Minimum lock quality seen
    output reg  [15:0] lock_quality_max,    // Maximum lock quality seen
    output reg  [15:0] lock_quality_avg,    // Average lock quality

    // Histogram of phase errors (8 bins from -max to +max)
    output wire [15:0] phase_hist_0,        // Very early
    output wire [15:0] phase_hist_1,        // Early
    output wire [15:0] phase_hist_2,        // Slightly early
    output wire [15:0] phase_hist_3,        // On time (-)
    output wire [15:0] phase_hist_4,        // On time (+)
    output wire [15:0] phase_hist_5,        // Slightly late
    output wire [15:0] phase_hist_6,        // Late
    output wire [15:0] phase_hist_7         // Very late
);

    //-------------------------------------------------------------------------
    // Internal State
    //-------------------------------------------------------------------------
    reg [31:0] prev_phase_accum;
    reg [31:0] freq_word_estimate;
    reg        prev_locked;
    reg [31:0] lock_timer;
    reg [31:0] quality_accumulator;
    reg [15:0] quality_sample_count;

    // Phase error histogram
    reg [15:0] hist_bins [0:7];

    //-------------------------------------------------------------------------
    // Frequency Word Estimation
    // Difference between consecutive phase accumulator values = frequency word
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            prev_phase_accum <= 32'd0;
            freq_word_estimate <= 32'd0;
        end else if (data_ready) begin
            prev_phase_accum <= phase_accum;
            freq_word_estimate <= phase_accum - prev_phase_accum;
        end
    end

    //-------------------------------------------------------------------------
    // Frequency Offset Calculation (PPM)
    // PPM = ((actual - nominal) / nominal) * 1,000,000
    // Simplified: PPM ≈ ((actual - nominal) * 1000000) >> 32
    //-------------------------------------------------------------------------
    wire signed [31:0] freq_diff;
    assign freq_diff = freq_word_estimate - nominal_freq_word;

    // Approximate PPM calculation (avoiding division)
    // For 200 MHz clock, freq_word for 500K = 0x00A3D70A
    // 1 PPM = freq_word / 1,000,000 ≈ 0.01 (very small)
    // Instead: scale diff by (1M / freq_word) ≈ 93 for 500K
    wire signed [47:0] ppm_calc;
    assign ppm_calc = freq_diff * 32'd93;  // Approximate scaling

    //-------------------------------------------------------------------------
    // Phase Error Averaging (EMA with alpha = 1/16)
    //-------------------------------------------------------------------------
    reg signed [15:0] phase_error_signed;
    wire signed [15:0] ema_delta;

    always @(*) begin
        phase_error_signed = phase_error;
    end

    assign ema_delta = (phase_error_signed - phase_error_avg) >>> 4;

    always @(posedge clk) begin
        if (reset || stats_clear) begin
            phase_error_avg <= 16'd0;
            phase_error_peak <= 16'd0;
        end else if (data_ready) begin
            // Update EMA
            phase_error_avg <= phase_error_avg + ema_delta;

            // Update peak (absolute value)
            if (phase_error_signed < 0) begin
                if (-phase_error_signed > phase_error_peak)
                    phase_error_peak <= -phase_error_signed;
            end else begin
                if (phase_error_signed > phase_error_peak)
                    phase_error_peak <= phase_error_signed;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Lock Statistics
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || stats_clear) begin
            prev_locked <= 1'b0;
            lock_timer <= 32'd0;
            lock_time_clocks <= 32'd0;
            total_lock_time <= 32'd0;
            unlock_count <= 32'd0;
            lock_quality_min <= 16'hFFFF;
            lock_quality_max <= 16'd0;
            quality_accumulator <= 32'd0;
            quality_sample_count <= 16'd0;
            lock_quality_avg <= 16'd0;
        end else begin
            prev_locked <= pll_locked;

            // Lock timer (time since last unlock)
            if (!pll_locked) begin
                lock_timer <= lock_timer + 1;
            end

            // Detect lock transition
            if (pll_locked && !prev_locked) begin
                // Just locked - record lock time
                lock_time_clocks <= lock_timer;
                lock_timer <= 32'd0;
            end

            // Detect unlock transition
            if (!pll_locked && prev_locked) begin
                unlock_count <= unlock_count + 1;
            end

            // Accumulate locked time
            if (pll_locked) begin
                total_lock_time <= total_lock_time + 1;

                // Track quality statistics
                if ({8'd0, lock_quality} < lock_quality_min)
                    lock_quality_min <= {8'd0, lock_quality};
                if ({8'd0, lock_quality} > lock_quality_max)
                    lock_quality_max <= {8'd0, lock_quality};

                // Running average
                if (quality_sample_count < 16'hFFFF) begin
                    quality_accumulator <= quality_accumulator + {24'd0, lock_quality};
                    quality_sample_count <= quality_sample_count + 1;
                    lock_quality_avg <= quality_accumulator[23:8];  // Divide by 256 approx
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Snapshot Capture
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            phase_error_snap <= 16'd0;
            freq_word_snap <= 32'd0;
            freq_offset_ppm <= 32'd0;
        end else if (snapshot_trigger) begin
            phase_error_snap <= phase_error;
            freq_word_snap <= freq_word_estimate;
            freq_offset_ppm <= ppm_calc[47:16];  // Scale down
        end
    end

    //-------------------------------------------------------------------------
    // Phase Error Histogram
    // 8 bins: [-inf,-3σ], [-3σ,-2σ], [-2σ,-σ], [-σ,0], [0,σ], [σ,2σ], [2σ,3σ], [3σ,inf]
    // Using fixed thresholds based on typical phase error range
    //-------------------------------------------------------------------------
    localparam signed [15:0] THRESH_3 = 16'sd3000;
    localparam signed [15:0] THRESH_2 = 16'sd2000;
    localparam signed [15:0] THRESH_1 = 16'sd1000;

    wire [2:0] hist_bin;

    assign hist_bin = (phase_error_signed < -THRESH_3) ? 3'd0 :
                      (phase_error_signed < -THRESH_2) ? 3'd1 :
                      (phase_error_signed < -THRESH_1) ? 3'd2 :
                      (phase_error_signed < 0)         ? 3'd3 :
                      (phase_error_signed < THRESH_1)  ? 3'd4 :
                      (phase_error_signed < THRESH_2)  ? 3'd5 :
                      (phase_error_signed < THRESH_3)  ? 3'd6 : 3'd7;

    integer i;
    always @(posedge clk) begin
        if (reset || stats_clear) begin
            for (i = 0; i < 8; i = i + 1) begin
                hist_bins[i] <= 16'd0;
            end
        end else if (data_ready && pll_locked) begin
            // Saturating increment
            if (hist_bins[hist_bin] != 16'hFFFF) begin
                hist_bins[hist_bin] <= hist_bins[hist_bin] + 1;
            end
        end
    end

    assign phase_hist_0 = hist_bins[0];
    assign phase_hist_1 = hist_bins[1];
    assign phase_hist_2 = hist_bins[2];
    assign phase_hist_3 = hist_bins[3];
    assign phase_hist_4 = hist_bins[4];
    assign phase_hist_5 = hist_bins[5];
    assign phase_hist_6 = hist_bins[6];
    assign phase_hist_7 = hist_bins[7];

endmodule
