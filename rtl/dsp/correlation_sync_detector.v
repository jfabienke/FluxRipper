//==============================================================================
// Correlation-Based Sync Pattern Detector
//==============================================================================
// File: correlation_sync_detector.v
// Description: Sliding correlator for detecting sync patterns in flux data.
//              Uses DSP slices for efficient correlation computation.
//              Supports multiple sync patterns (MFM, RLL, ESDI).
//
// DSP Usage: 4-8 DSP48E2 slices
// Latency: Pattern length + 2 cycles
//
// Algorithm:
//   correlation[n] = sum(data[n-k] * pattern[k]) for k=0..pattern_len-1
//   Detection when correlation > threshold
//
// Target: AMD Spartan UltraScale+ XCSU35P
// Author: Claude Code (FluxRipper Project)
// Created: 2025-12-05 01:35
//==============================================================================

`timescale 1ns / 1ps

module correlation_sync_detector #(
    parameter DATA_WIDTH     = 8,        // Input data width
    parameter PATTERN_LEN    = 32,       // Max pattern length
    parameter CORR_WIDTH     = 24,       // Correlation accumulator width
    parameter NUM_PATTERNS   = 4         // Number of patterns to detect simultaneously
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     enable,

    // Input data stream (typically from flux quantizer)
    input  wire [DATA_WIDTH-1:0]    data_in,
    input  wire                     data_valid,

    // Pattern configuration
    input  wire [1:0]               pattern_select, // Which pattern set to use
    input  wire                     pattern_load,   // Load custom pattern
    input  wire [4:0]               pattern_addr,   // Pattern bit address
    input  wire                     pattern_bit,    // Pattern bit value

    // Detection outputs
    output reg                      sync_detected,      // Sync pattern found
    output reg  [1:0]               sync_pattern_id,    // Which pattern matched
    output reg  [CORR_WIDTH-1:0]    sync_correlation,   // Correlation value at detection
    output reg  [7:0]               sync_quality,       // Detection quality (0-255)

    // Threshold configuration
    input  wire [CORR_WIDTH-1:0]    detect_threshold,   // Detection threshold
    input  wire [7:0]               min_quality         // Minimum quality for valid detection
);

    //=========================================================================
    // Sync Pattern ROM - Predefined Patterns
    //=========================================================================

    // MFM sync pattern: 0x4489 (A1 with missing clock)
    // Binary: 0100 0100 1000 1001
    // As flux transitions (differential): alternating pattern
    reg [PATTERN_LEN-1:0] pattern_mfm;
    initial pattern_mfm = 32'b01000100_10001001_01000100_10001001;

    // RLL(2,7) sync pattern
    reg [PATTERN_LEN-1:0] pattern_rll;
    initial pattern_rll = 32'b00100010_00100010_01000100_01000100;

    // ESDI NRZ sync pattern
    reg [PATTERN_LEN-1:0] pattern_esdi;
    initial pattern_esdi = 32'b11111111_00000000_11111111_00000000;

    // Custom pattern (loadable)
    reg [PATTERN_LEN-1:0] pattern_custom;

    //=========================================================================
    // Pattern Loading
    //=========================================================================

    always @(posedge clk) begin
        if (pattern_load && pattern_addr < PATTERN_LEN) begin
            pattern_custom[pattern_addr] <= pattern_bit;
        end
    end

    //=========================================================================
    // Active Pattern Selection
    //=========================================================================

    reg [PATTERN_LEN-1:0] active_pattern;

    always @(*) begin
        case (pattern_select)
            2'b00: active_pattern = pattern_mfm;
            2'b01: active_pattern = pattern_rll;
            2'b10: active_pattern = pattern_esdi;
            2'b11: active_pattern = pattern_custom;
        endcase
    end

    // Convert pattern to signed coefficients (+1 for 1, -1 for 0)
    wire signed [1:0] pattern_coef [0:PATTERN_LEN-1];
    genvar g;
    generate
        for (g = 0; g < PATTERN_LEN; g = g + 1) begin : gen_coef
            assign pattern_coef[g] = active_pattern[g] ? 2'sb01 : 2'sb11;
        end
    endgenerate

    //=========================================================================
    // Data Shift Register
    //=========================================================================

    reg [DATA_WIDTH-1:0] data_shift [0:PATTERN_LEN-1];

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < PATTERN_LEN; i = i + 1) begin
                data_shift[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (enable && data_valid) begin
            data_shift[0] <= data_in;
            for (i = 1; i < PATTERN_LEN; i = i + 1) begin
                data_shift[i] <= data_shift[i-1];
            end
        end
    end

    //=========================================================================
    // Correlation Computation (DSP-Optimized)
    //=========================================================================
    // Split into 8 groups of 4 taps each, using DSP pre-adders

    // Stage 1: Partial correlations (8 groups x 4 taps)
    (* use_dsp = "yes" *)
    reg signed [DATA_WIDTH+3:0] partial_corr [0:7];

    always @(posedge clk) begin
        if (enable && data_valid) begin
            // Group 0: taps 0-3
            partial_corr[0] <= ($signed(data_shift[0])  * pattern_coef[0]) +
                               ($signed(data_shift[1])  * pattern_coef[1]) +
                               ($signed(data_shift[2])  * pattern_coef[2]) +
                               ($signed(data_shift[3])  * pattern_coef[3]);

            // Group 1: taps 4-7
            partial_corr[1] <= ($signed(data_shift[4])  * pattern_coef[4]) +
                               ($signed(data_shift[5])  * pattern_coef[5]) +
                               ($signed(data_shift[6])  * pattern_coef[6]) +
                               ($signed(data_shift[7])  * pattern_coef[7]);

            // Group 2: taps 8-11
            partial_corr[2] <= ($signed(data_shift[8])  * pattern_coef[8]) +
                               ($signed(data_shift[9])  * pattern_coef[9]) +
                               ($signed(data_shift[10]) * pattern_coef[10]) +
                               ($signed(data_shift[11]) * pattern_coef[11]);

            // Group 3: taps 12-15
            partial_corr[3] <= ($signed(data_shift[12]) * pattern_coef[12]) +
                               ($signed(data_shift[13]) * pattern_coef[13]) +
                               ($signed(data_shift[14]) * pattern_coef[14]) +
                               ($signed(data_shift[15]) * pattern_coef[15]);

            // Group 4: taps 16-19
            partial_corr[4] <= ($signed(data_shift[16]) * pattern_coef[16]) +
                               ($signed(data_shift[17]) * pattern_coef[17]) +
                               ($signed(data_shift[18]) * pattern_coef[18]) +
                               ($signed(data_shift[19]) * pattern_coef[19]);

            // Group 5: taps 20-23
            partial_corr[5] <= ($signed(data_shift[20]) * pattern_coef[20]) +
                               ($signed(data_shift[21]) * pattern_coef[21]) +
                               ($signed(data_shift[22]) * pattern_coef[22]) +
                               ($signed(data_shift[23]) * pattern_coef[23]);

            // Group 6: taps 24-27
            partial_corr[6] <= ($signed(data_shift[24]) * pattern_coef[24]) +
                               ($signed(data_shift[25]) * pattern_coef[25]) +
                               ($signed(data_shift[26]) * pattern_coef[26]) +
                               ($signed(data_shift[27]) * pattern_coef[27]);

            // Group 7: taps 28-31
            partial_corr[7] <= ($signed(data_shift[28]) * pattern_coef[28]) +
                               ($signed(data_shift[29]) * pattern_coef[29]) +
                               ($signed(data_shift[30]) * pattern_coef[30]) +
                               ($signed(data_shift[31]) * pattern_coef[31]);
        end
    end

    //=========================================================================
    // Adder Tree for Final Correlation
    //=========================================================================

    // Stage 2: 8 -> 4
    reg signed [DATA_WIDTH+4:0] sum_s2 [0:3];
    reg valid_s1, valid_s2, valid_s3;

    // Stage 3: 4 -> 2
    reg signed [DATA_WIDTH+5:0] sum_s3 [0:1];

    // Stage 4: 2 -> 1
    reg signed [DATA_WIDTH+6:0] correlation_raw;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 4; i = i + 1) sum_s2[i] <= 0;
            sum_s3[0] <= 0;
            sum_s3[1] <= 0;
            correlation_raw <= 0;
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_s3 <= 1'b0;
        end else if (enable) begin
            // Stage 2
            sum_s2[0] <= partial_corr[0] + partial_corr[1];
            sum_s2[1] <= partial_corr[2] + partial_corr[3];
            sum_s2[2] <= partial_corr[4] + partial_corr[5];
            sum_s2[3] <= partial_corr[6] + partial_corr[7];
            valid_s1 <= data_valid;

            // Stage 3
            sum_s3[0] <= sum_s2[0] + sum_s2[1];
            sum_s3[1] <= sum_s2[2] + sum_s2[3];
            valid_s2 <= valid_s1;

            // Stage 4
            correlation_raw <= sum_s3[0] + sum_s3[1];
            valid_s3 <= valid_s2;
        end
    end

    //=========================================================================
    // Peak Detection and Quality Assessment
    //=========================================================================

    // Absolute value of correlation
    wire [DATA_WIDTH+5:0] correlation_abs;
    assign correlation_abs = (correlation_raw < 0) ? -correlation_raw : correlation_raw;

    // Extended to CORR_WIDTH
    wire [CORR_WIDTH-1:0] correlation_ext;
    assign correlation_ext = {{(CORR_WIDTH-DATA_WIDTH-7){1'b0}}, correlation_abs};

    // Peak detection with holdoff
    reg [7:0] peak_holdoff;
    reg [CORR_WIDTH-1:0] peak_value;
    reg [CORR_WIDTH-1:0] prev_correlation;
    reg prev_valid;

    localparam HOLDOFF_COUNT = 8'd16;  // Minimum samples between detections

    // Quality calculation: correlation / max_possible * 255
    // Max possible = PATTERN_LEN * max_data_value
    wire [CORR_WIDTH+7:0] quality_calc;
    assign quality_calc = (correlation_ext << 8) / (PATTERN_LEN * ((1 << DATA_WIDTH) - 1));

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sync_detected <= 1'b0;
            sync_pattern_id <= 2'b00;
            sync_correlation <= {CORR_WIDTH{1'b0}};
            sync_quality <= 8'd0;
            peak_holdoff <= 8'd0;
            peak_value <= {CORR_WIDTH{1'b0}};
            prev_correlation <= {CORR_WIDTH{1'b0}};
            prev_valid <= 1'b0;
        end else if (enable) begin
            prev_correlation <= correlation_ext;
            prev_valid <= valid_s3;

            // Default: no detection
            sync_detected <= 1'b0;

            // Holdoff counter
            if (peak_holdoff > 0) begin
                peak_holdoff <= peak_holdoff - 1'b1;
            end

            // Peak detection: correlation exceeds threshold AND is local maximum
            if (valid_s3 && prev_valid && peak_holdoff == 0) begin
                if (correlation_ext >= detect_threshold &&
                    correlation_ext >= prev_correlation &&
                    quality_calc[7:0] >= min_quality) begin

                    // Check if this is a peak (next sample would be needed for full check)
                    // Simplified: detect when crossing threshold upward
                    if (prev_correlation < detect_threshold) begin
                        sync_detected <= 1'b1;
                        sync_pattern_id <= pattern_select;
                        sync_correlation <= correlation_ext;
                        sync_quality <= quality_calc[7:0];
                        peak_holdoff <= HOLDOFF_COUNT;
                    end
                end
            end
        end
    end

endmodule

//==============================================================================
// Multi-Pattern Parallel Correlator
//==============================================================================
// Detects multiple sync patterns simultaneously using shared data path.
// Useful for auto-detection of encoding format.
//==============================================================================

module multi_pattern_correlator #(
    parameter DATA_WIDTH  = 8,
    parameter CORR_WIDTH  = 24
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     enable,

    input  wire [DATA_WIDTH-1:0]    data_in,
    input  wire                     data_valid,

    // Detection outputs (one per pattern)
    output wire                     mfm_detected,
    output wire [CORR_WIDTH-1:0]    mfm_correlation,
    output wire                     rll_detected,
    output wire [CORR_WIDTH-1:0]    rll_correlation,
    output wire                     esdi_detected,
    output wire [CORR_WIDTH-1:0]    esdi_correlation,

    // Best match output
    output reg  [1:0]               best_pattern,    // 0=MFM, 1=RLL, 2=ESDI
    output reg                      any_detected,

    // Threshold
    input  wire [CORR_WIDTH-1:0]    detect_threshold
);

    wire [7:0] quality_mfm, quality_rll, quality_esdi;
    wire [1:0] id_mfm, id_rll, id_esdi;

    // MFM correlator
    correlation_sync_detector #(
        .DATA_WIDTH(DATA_WIDTH),
        .CORR_WIDTH(CORR_WIDTH)
    ) u_corr_mfm (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .data_in(data_in),
        .data_valid(data_valid),
        .pattern_select(2'b00),
        .pattern_load(1'b0),
        .pattern_addr(5'd0),
        .pattern_bit(1'b0),
        .sync_detected(mfm_detected),
        .sync_pattern_id(id_mfm),
        .sync_correlation(mfm_correlation),
        .sync_quality(quality_mfm),
        .detect_threshold(detect_threshold),
        .min_quality(8'd64)
    );

    // RLL correlator
    correlation_sync_detector #(
        .DATA_WIDTH(DATA_WIDTH),
        .CORR_WIDTH(CORR_WIDTH)
    ) u_corr_rll (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .data_in(data_in),
        .data_valid(data_valid),
        .pattern_select(2'b01),
        .pattern_load(1'b0),
        .pattern_addr(5'd0),
        .pattern_bit(1'b0),
        .sync_detected(rll_detected),
        .sync_pattern_id(id_rll),
        .sync_correlation(rll_correlation),
        .sync_quality(quality_rll),
        .detect_threshold(detect_threshold),
        .min_quality(8'd64)
    );

    // ESDI correlator
    correlation_sync_detector #(
        .DATA_WIDTH(DATA_WIDTH),
        .CORR_WIDTH(CORR_WIDTH)
    ) u_corr_esdi (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .data_in(data_in),
        .data_valid(data_valid),
        .pattern_select(2'b10),
        .pattern_load(1'b0),
        .pattern_addr(5'd0),
        .pattern_bit(1'b0),
        .sync_detected(esdi_detected),
        .sync_pattern_id(id_esdi),
        .sync_correlation(esdi_correlation),
        .sync_quality(quality_esdi),
        .detect_threshold(detect_threshold),
        .min_quality(8'd64)
    );

    // Best match selection
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            best_pattern <= 2'b00;
            any_detected <= 1'b0;
        end else begin
            any_detected <= mfm_detected | rll_detected | esdi_detected;

            if (mfm_detected && mfm_correlation >= rll_correlation &&
                mfm_correlation >= esdi_correlation) begin
                best_pattern <= 2'b00;
            end else if (rll_detected && rll_correlation >= esdi_correlation) begin
                best_pattern <= 2'b01;
            end else if (esdi_detected) begin
                best_pattern <= 2'b10;
            end
        end
    end

endmodule
