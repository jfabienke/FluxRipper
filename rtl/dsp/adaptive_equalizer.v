//==============================================================================
// Adaptive Equalizer for Flux Signal Recovery
//==============================================================================
// File: adaptive_equalizer.v
// Description: LMS (Least Mean Squares) adaptive equalizer for compensating
//              cable losses, head frequency response, and media degradation.
//              Automatically adapts filter coefficients to minimize error.
//
// DSP Usage: 8-16 DSP48E2 slices
// Algorithm: LMS with leaky integrator for coefficient stability
//
// Application:
//   - Compensate for lossy cables on vintage drives
//   - Equalize head frequency response variations
//   - Improve recovery from degraded media
//   - Pre-processing for PRML decoder
//
// Target: AMD Spartan UltraScale+ XCSU35P
// Author: Claude Code (FluxRipper Project)
// Created: 2025-12-05 01:40
//==============================================================================

`timescale 1ns / 1ps

module adaptive_equalizer #(
    parameter DATA_WIDTH    = 12,       // Input/output sample width
    parameter COEF_WIDTH    = 16,       // Coefficient width
    parameter NUM_TAPS      = 11,       // Number of equalizer taps (odd for symmetry)
    parameter MU_WIDTH      = 8,        // Step size width (mu = 2^-MU_SHIFT)
    parameter MU_SHIFT      = 12        // Step size: mu = 1/4096
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     enable,

    // Input sample stream
    input  wire signed [DATA_WIDTH-1:0] data_in,
    input  wire                     data_valid,

    // Output equalized stream
    output reg  signed [DATA_WIDTH-1:0] data_out,
    output reg                      data_out_valid,

    // Training/reference signal (for adaptation)
    input  wire signed [DATA_WIDTH-1:0] reference_in,   // Ideal signal (slicer output)
    input  wire                     reference_valid,
    input  wire                     training_mode,      // 1=adapt coefficients

    // Coefficient access (for diagnostics/preload)
    input  wire                     coef_read,
    input  wire                     coef_write,
    input  wire [3:0]               coef_addr,
    input  wire signed [COEF_WIDTH-1:0] coef_wdata,
    output reg  signed [COEF_WIDTH-1:0] coef_rdata,

    // Configuration
    input  wire [MU_WIDTH-1:0]      step_size,          // Adaptation step size
    input  wire [7:0]               leakage,            // Coefficient leakage (0-255)
    input  wire                     freeze_coefs,       // Stop adaptation

    // Status
    output reg  signed [DATA_WIDTH-1:0] current_error,  // Last error value
    output reg  [15:0]              error_power,        // Running error power (MSE estimate)
    output reg                      converged           // Coefficients have converged
);

    //=========================================================================
    // Coefficient Storage
    //=========================================================================

    reg signed [COEF_WIDTH-1:0] coef [0:NUM_TAPS-1];

    // Initialize to identity filter (center tap = 1.0)
    integer i;
    initial begin
        for (i = 0; i < NUM_TAPS; i = i + 1) begin
            if (i == NUM_TAPS/2) begin
                coef[i] = {1'b0, 1'b1, {(COEF_WIDTH-2){1'b0}}};  // 0.5 in Q1.15
            end else begin
                coef[i] = {COEF_WIDTH{1'b0}};
            end
        end
    end

    //=========================================================================
    // Data Delay Line
    //=========================================================================

    reg signed [DATA_WIDTH-1:0] delay_line [0:NUM_TAPS-1];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                delay_line[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (enable && data_valid) begin
            delay_line[0] <= data_in;
            for (i = 1; i < NUM_TAPS; i = i + 1) begin
                delay_line[i] <= delay_line[i-1];
            end
        end
    end

    //=========================================================================
    // FIR Filter (Equalization)
    //=========================================================================

    // Multiply-accumulate for filter output
    (* use_dsp = "yes" *)
    reg signed [DATA_WIDTH+COEF_WIDTH-1:0] products [0:NUM_TAPS-1];
    reg signed [DATA_WIDTH+COEF_WIDTH+3:0] filter_sum;
    reg valid_p1, valid_p2;

    always @(posedge clk) begin
        if (enable && data_valid) begin
            // Compute products
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                products[i] <= delay_line[i] * coef[i];
            end
        end
    end

    // Adder tree for accumulation
    reg signed [DATA_WIDTH+COEF_WIDTH:0] sum_s1 [0:5];
    reg signed [DATA_WIDTH+COEF_WIDTH+1:0] sum_s2 [0:2];
    reg signed [DATA_WIDTH+COEF_WIDTH+2:0] sum_s3 [0:1];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 6; i = i + 1) sum_s1[i] <= 0;
            for (i = 0; i < 3; i = i + 1) sum_s2[i] <= 0;
            sum_s3[0] <= 0;
            sum_s3[1] <= 0;
            filter_sum <= 0;
            valid_p1 <= 1'b0;
            valid_p2 <= 1'b0;
        end else if (enable) begin
            // Stage 1: pairs
            sum_s1[0] <= products[0] + products[1];
            sum_s1[1] <= products[2] + products[3];
            sum_s1[2] <= products[4] + products[5];
            sum_s1[3] <= products[6] + products[7];
            sum_s1[4] <= products[8] + products[9];
            sum_s1[5] <= products[10];  // Odd tap
            valid_p1 <= data_valid;

            // Stage 2
            sum_s2[0] <= sum_s1[0] + sum_s1[1];
            sum_s2[1] <= sum_s1[2] + sum_s1[3];
            sum_s2[2] <= sum_s1[4] + sum_s1[5];

            // Stage 3
            sum_s3[0] <= sum_s2[0] + sum_s2[1];
            sum_s3[1] <= sum_s2[2];
            valid_p2 <= valid_p1;

            // Final sum
            filter_sum <= sum_s3[0] + sum_s3[1];
        end
    end

    // Scale and output
    wire signed [DATA_WIDTH-1:0] equalized;
    assign equalized = filter_sum[DATA_WIDTH+COEF_WIDTH-2:COEF_WIDTH-1];  // Q1.15 scaling

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            data_out <= {DATA_WIDTH{1'b0}};
            data_out_valid <= 1'b0;
        end else if (enable) begin
            data_out <= equalized;
            data_out_valid <= valid_p2;
        end
    end

    //=========================================================================
    // Error Computation
    //=========================================================================

    reg signed [DATA_WIDTH-1:0] error;
    reg signed [DATA_WIDTH-1:0] delayed_reference;
    reg reference_valid_d;

    // Delay reference to align with filter output
    localparam REF_DELAY = 3;  // Match filter pipeline delay
    reg signed [DATA_WIDTH-1:0] ref_delay [0:REF_DELAY-1];
    reg [REF_DELAY-1:0] ref_valid_delay;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < REF_DELAY; i = i + 1) begin
                ref_delay[i] <= {DATA_WIDTH{1'b0}};
            end
            ref_valid_delay <= {REF_DELAY{1'b0}};
            delayed_reference <= {DATA_WIDTH{1'b0}};
            reference_valid_d <= 1'b0;
        end else if (enable) begin
            ref_delay[0] <= reference_in;
            for (i = 1; i < REF_DELAY; i = i + 1) begin
                ref_delay[i] <= ref_delay[i-1];
            end
            ref_valid_delay <= {ref_valid_delay[REF_DELAY-2:0], reference_valid};
            delayed_reference <= ref_delay[REF_DELAY-1];
            reference_valid_d <= ref_valid_delay[REF_DELAY-1];
        end
    end

    // Error = reference - output
    always @(posedge clk) begin
        if (enable && valid_p2 && reference_valid_d) begin
            error <= delayed_reference - equalized;
            current_error <= delayed_reference - equalized;
        end
    end

    //=========================================================================
    // LMS Coefficient Update
    //=========================================================================
    // coef[i] <= coef[i] + mu * error * x[i] - leakage * coef[i]
    // Using fixed-point: mu = step_size / 2^MU_SHIFT

    (* use_dsp = "yes" *)
    reg signed [DATA_WIDTH+DATA_WIDTH-1:0] error_x [0:NUM_TAPS-1];
    reg signed [DATA_WIDTH+DATA_WIDTH+MU_WIDTH-1:0] mu_error_x [0:NUM_TAPS-1];
    reg signed [COEF_WIDTH+7:0] leak_term [0:NUM_TAPS-1];

    reg update_valid;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                error_x[i] <= 0;
                mu_error_x[i] <= 0;
                leak_term[i] <= 0;
            end
            update_valid <= 1'b0;
        end else if (enable && training_mode && !freeze_coefs && valid_p2 && reference_valid_d) begin
            // Stage 1: error * x[i]
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                error_x[i] <= error * delay_line[i];
            end
            update_valid <= 1'b1;
        end else begin
            update_valid <= 1'b0;
        end
    end

    // Coefficient update with leakage
    always @(posedge clk) begin
        if (enable && update_valid) begin
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                // mu * error * x (scaled by 2^MU_SHIFT)
                mu_error_x[i] <= (error_x[i] * $signed({1'b0, step_size})) >>> MU_SHIFT;

                // Leakage term: coef * leakage / 256
                leak_term[i] <= (coef[i] * $signed({1'b0, leakage})) >>> 8;
            end
        end
    end

    // Final coefficient update
    reg update_valid_d;
    always @(posedge clk) begin
        update_valid_d <= update_valid;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Reset to identity filter
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                if (i == NUM_TAPS/2) begin
                    coef[i] <= {1'b0, 1'b1, {(COEF_WIDTH-2){1'b0}}};
                end else begin
                    coef[i] <= {COEF_WIDTH{1'b0}};
                end
            end
        end else if (enable && update_valid_d && training_mode && !freeze_coefs) begin
            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                coef[i] <= coef[i] + mu_error_x[i][COEF_WIDTH-1:0] - leak_term[i][COEF_WIDTH-1:0];
            end
        end else if (coef_write && coef_addr < NUM_TAPS) begin
            coef[coef_addr] <= coef_wdata;
        end
    end

    //=========================================================================
    // Coefficient Read
    //=========================================================================

    always @(posedge clk) begin
        if (coef_read && coef_addr < NUM_TAPS) begin
            coef_rdata <= coef[coef_addr];
        end
    end

    //=========================================================================
    // Error Power Estimation (MSE)
    //=========================================================================

    (* use_dsp = "yes" *)
    reg signed [2*DATA_WIDTH-1:0] error_squared;
    reg [2*DATA_WIDTH+3:0] error_accum;
    reg [7:0] sample_count;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            error_squared <= 0;
            error_accum <= 0;
            sample_count <= 0;
            error_power <= 0;
        end else if (enable && valid_p2 && reference_valid_d) begin
            error_squared <= error * error;

            // Accumulate over 256 samples, then update estimate
            if (sample_count == 8'hFF) begin
                error_power <= error_accum[2*DATA_WIDTH+3:2*DATA_WIDTH-12];  // Scale
                error_accum <= {{4{error_squared[2*DATA_WIDTH-1]}}, error_squared};
                sample_count <= 8'd0;
            end else begin
                error_accum <= error_accum + {{4{error_squared[2*DATA_WIDTH-1]}}, error_squared};
                sample_count <= sample_count + 1'b1;
            end
        end
    end

    //=========================================================================
    // Convergence Detection
    //=========================================================================

    reg [15:0] prev_error_power;
    reg [7:0] stable_count;

    localparam CONVERGE_THRESHOLD = 16'd100;   // Error power threshold
    localparam STABLE_SAMPLES = 8'd32;         // Samples below threshold

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            converged <= 1'b0;
            prev_error_power <= 16'hFFFF;
            stable_count <= 8'd0;
        end else if (enable && sample_count == 8'd0) begin
            prev_error_power <= error_power;

            // Check if error power is stable and below threshold
            if (error_power < CONVERGE_THRESHOLD &&
                (error_power >= prev_error_power - 16'd10) &&
                (error_power <= prev_error_power + 16'd10)) begin
                if (stable_count < STABLE_SAMPLES) begin
                    stable_count <= stable_count + 1'b1;
                end else begin
                    converged <= 1'b1;
                end
            end else begin
                stable_count <= 8'd0;
                converged <= 1'b0;
            end
        end
    end

endmodule

//==============================================================================
// Decision Feedback Equalizer (DFE)
//==============================================================================
// Combines feedforward equalizer with feedback from decisions.
// Better for channels with severe ISI (inter-symbol interference).
//==============================================================================

module decision_feedback_equalizer #(
    parameter DATA_WIDTH    = 12,
    parameter COEF_WIDTH    = 16,
    parameter FF_TAPS       = 7,        // Feedforward taps
    parameter FB_TAPS       = 4         // Feedback taps
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     enable,

    input  wire signed [DATA_WIDTH-1:0] data_in,
    input  wire                     data_valid,

    output reg  signed [DATA_WIDTH-1:0] data_out,
    output reg                      data_out_valid,
    output reg                      decision_out,       // Hard decision (0 or 1)

    input  wire                     training_mode,
    input  wire signed [DATA_WIDTH-1:0] training_ref,
    input  wire [7:0]               step_size
);

    // Feedforward section
    reg signed [DATA_WIDTH-1:0] ff_delay [0:FF_TAPS-1];
    reg signed [COEF_WIDTH-1:0] ff_coef [0:FF_TAPS-1];

    // Feedback section (uses decisions)
    reg decision_delay [0:FB_TAPS-1];
    reg signed [COEF_WIDTH-1:0] fb_coef [0:FB_TAPS-1];

    // Accumulator
    (* use_dsp = "yes" *)
    reg signed [DATA_WIDTH+COEF_WIDTH+3:0] ff_sum;
    reg signed [COEF_WIDTH+3:0] fb_sum;
    reg signed [DATA_WIDTH+COEF_WIDTH+4:0] total_sum;

    integer i;

    // Initialize coefficients
    initial begin
        for (i = 0; i < FF_TAPS; i = i + 1) begin
            ff_coef[i] = (i == FF_TAPS/2) ? 16'h4000 : 16'h0000;
        end
        for (i = 0; i < FB_TAPS; i = i + 1) begin
            fb_coef[i] = 16'h0000;
        end
    end

    // Feedforward delay line
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < FF_TAPS; i = i + 1) begin
                ff_delay[i] <= 0;
            end
        end else if (enable && data_valid) begin
            ff_delay[0] <= data_in;
            for (i = 1; i < FF_TAPS; i = i + 1) begin
                ff_delay[i] <= ff_delay[i-1];
            end
        end
    end

    // Feedforward FIR
    always @(posedge clk) begin
        if (enable && data_valid) begin
            ff_sum <= 0;
            for (i = 0; i < FF_TAPS; i = i + 1) begin
                ff_sum <= ff_sum + ff_delay[i] * ff_coef[i];
            end
        end
    end

    // Feedback from decisions
    always @(posedge clk) begin
        if (enable && data_valid) begin
            fb_sum <= 0;
            for (i = 0; i < FB_TAPS; i = i + 1) begin
                // Decision is +1 or -1 (mapped from 0/1)
                fb_sum <= fb_sum + (decision_delay[i] ? fb_coef[i] : -fb_coef[i]);
            end
        end
    end

    // Combined output
    always @(posedge clk) begin
        if (enable && data_valid) begin
            total_sum <= ff_sum - fb_sum;
        end
    end

    // Slicer (hard decision)
    wire signed [DATA_WIDTH-1:0] equalized_sample;
    assign equalized_sample = total_sum[DATA_WIDTH+COEF_WIDTH-1:COEF_WIDTH];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            data_out <= 0;
            data_out_valid <= 1'b0;
            decision_out <= 1'b0;
            for (i = 0; i < FB_TAPS; i = i + 1) begin
                decision_delay[i] <= 1'b0;
            end
        end else if (enable && data_valid) begin
            data_out <= equalized_sample;
            data_out_valid <= 1'b1;

            // Hard decision (threshold at 0)
            decision_out <= (equalized_sample >= 0) ? 1'b1 : 1'b0;

            // Update feedback delay line
            decision_delay[0] <= (equalized_sample >= 0) ? 1'b1 : 1'b0;
            for (i = 1; i < FB_TAPS; i = i + 1) begin
                decision_delay[i] <= decision_delay[i-1];
            end
        end else begin
            data_out_valid <= 1'b0;
        end
    end

endmodule
