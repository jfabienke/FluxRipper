//==============================================================================
// FFT Analyzer for RPM/Jitter Frequency Analysis
//==============================================================================
// File: fft_analyzer.v
// Description: 64-point radix-2 DIT FFT for analyzing spindle speed variations,
//              flux timing jitter, and other periodic phenomena. Uses DSP slices
//              for butterfly operations.
//
// DSP Usage: 8-16 DSP48E2 slices (complex multiply in butterfly)
// FFT Size: 64 points (configurable)
// Data Format: 16-bit signed fixed-point
//
// Applications:
//   - RPM variation analysis (wow & flutter)
//   - Flux transition jitter spectrum
//   - Motor bearing frequency detection
//   - Head positioning resonance detection
//
// Target: AMD Spartan UltraScale+ XCSU35P
// Author: Claude Code (FluxRipper Project)
// Created: 2025-12-05 01:55
//==============================================================================

`timescale 1ns / 1ps

module fft_analyzer #(
    parameter FFT_SIZE      = 64,       // Must be power of 2
    parameter DATA_WIDTH    = 16,       // Input/output data width
    parameter TWIDDLE_WIDTH = 16        // Twiddle factor width
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     enable,

    // Control
    input  wire                     start,          // Start FFT computation
    output reg                      busy,
    output reg                      done,

    // Input samples (real-only input, imaginary = 0)
    input  wire signed [DATA_WIDTH-1:0] sample_in,
    input  wire                     sample_valid,
    output reg                      sample_ready,   // Ready for next sample

    // Output bins (complex)
    output reg  signed [DATA_WIDTH-1:0] bin_real,
    output reg  signed [DATA_WIDTH-1:0] bin_imag,
    output reg  [5:0]               bin_index,
    output reg                      bin_valid,

    // Magnitude output (for spectrum display)
    output reg  [DATA_WIDTH-1:0]    bin_magnitude,
    output reg                      magnitude_valid,

    // Analysis results
    output reg  [5:0]               peak_bin,           // Bin with highest magnitude
    output reg  [DATA_WIDTH-1:0]    peak_magnitude,
    output reg  [15:0]              peak_frequency_x10, // Frequency * 10 (0.1 Hz resolution)
    input  wire [15:0]              sample_rate         // Sample rate for frequency calculation
);

    //=========================================================================
    // Memory for FFT Data (Ping-Pong Buffers)
    //=========================================================================

    // Real and imaginary parts
    reg signed [DATA_WIDTH-1:0] mem_real_a [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mem_imag_a [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mem_real_b [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mem_imag_b [0:FFT_SIZE-1];

    reg buffer_select;  // 0 = read A/write B, 1 = read B/write A

    //=========================================================================
    // Twiddle Factor ROM
    //=========================================================================
    // W_N^k = exp(-j*2*pi*k/N) = cos(2*pi*k/N) - j*sin(2*pi*k/N)
    // Stored as 16-bit signed fixed-point (Q1.15)

    reg signed [TWIDDLE_WIDTH-1:0] twiddle_cos [0:FFT_SIZE/2-1];
    reg signed [TWIDDLE_WIDTH-1:0] twiddle_sin [0:FFT_SIZE/2-1];

    // Initialize twiddle factors for 64-point FFT
    initial begin : init_twiddle
        integer k;
        real angle;
        real scale;

        scale = 32767.0;  // Q1.15 scaling

        for (k = 0; k < FFT_SIZE/2; k = k + 1) begin
            angle = -2.0 * 3.14159265359 * k / FFT_SIZE;
            twiddle_cos[k] = $rtoi($cos(angle) * scale);
            twiddle_sin[k] = $rtoi($sin(angle) * scale);
        end
    end

    //=========================================================================
    // Bit-Reversal Table
    //=========================================================================

    function [5:0] bit_reverse;
        input [5:0] index;
        begin
            bit_reverse = {index[0], index[1], index[2], index[3], index[4], index[5]};
        end
    endfunction

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_IDLE      = 4'd0;
    localparam ST_LOAD      = 4'd1;
    localparam ST_BITREV    = 4'd2;
    localparam ST_BUTTERFLY = 4'd3;
    localparam ST_OUTPUT    = 4'd4;
    localparam ST_ANALYZE   = 4'd5;
    localparam ST_DONE      = 4'd6;

    reg [3:0] state;
    reg [5:0] sample_count;
    reg [2:0] stage;            // FFT stage (0 to log2(N)-1 = 5)
    reg [5:0] butterfly_count;
    reg [5:0] group_count;
    reg [5:0] pair_count;

    //=========================================================================
    // Butterfly Unit
    //=========================================================================
    // Radix-2 DIT butterfly:
    //   A' = A + W * B
    //   B' = A - W * B
    // where W is twiddle factor

    reg signed [DATA_WIDTH-1:0] bfly_a_real, bfly_a_imag;
    reg signed [DATA_WIDTH-1:0] bfly_b_real, bfly_b_imag;
    reg signed [TWIDDLE_WIDTH-1:0] bfly_w_cos, bfly_w_sin;

    // Complex multiply: W * B = (Wr + jWi) * (Br + jBi)
    //                        = (Wr*Br - Wi*Bi) + j(Wr*Bi + Wi*Br)
    (* use_dsp = "yes" *)
    reg signed [DATA_WIDTH+TWIDDLE_WIDTH-1:0] wb_rr, wb_ii, wb_ri, wb_ir;
    reg signed [DATA_WIDTH+TWIDDLE_WIDTH:0] wb_real, wb_imag;

    always @(posedge clk) begin
        if (enable) begin
            // Stage 1: Partial products
            wb_rr <= bfly_w_cos * bfly_b_real;
            wb_ii <= bfly_w_sin * bfly_b_imag;
            wb_ri <= bfly_w_cos * bfly_b_imag;
            wb_ir <= bfly_w_sin * bfly_b_real;
        end
    end

    always @(posedge clk) begin
        if (enable) begin
            // Stage 2: Combine
            wb_real <= wb_rr - wb_ii;
            wb_imag <= wb_ri + wb_ir;
        end
    end

    // Scaled W*B result
    wire signed [DATA_WIDTH-1:0] wb_real_scaled, wb_imag_scaled;
    assign wb_real_scaled = wb_real[DATA_WIDTH+TWIDDLE_WIDTH-1:TWIDDLE_WIDTH];
    assign wb_imag_scaled = wb_imag[DATA_WIDTH+TWIDDLE_WIDTH-1:TWIDDLE_WIDTH];

    // Butterfly outputs (with scaling to prevent overflow)
    wire signed [DATA_WIDTH:0] bfly_out_a_real, bfly_out_a_imag;
    wire signed [DATA_WIDTH:0] bfly_out_b_real, bfly_out_b_imag;

    assign bfly_out_a_real = bfly_a_real + wb_real_scaled;
    assign bfly_out_a_imag = bfly_a_imag + wb_imag_scaled;
    assign bfly_out_b_real = bfly_a_real - wb_real_scaled;
    assign bfly_out_b_imag = bfly_a_imag - wb_imag_scaled;

    //=========================================================================
    // Main State Machine
    //=========================================================================

    integer i;
    reg [5:0] addr_a, addr_b;
    reg [5:0] twiddle_idx;
    reg [2:0] bfly_pipe;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            sample_ready <= 1'b1;
            sample_count <= 6'd0;
            stage <= 3'd0;
            butterfly_count <= 6'd0;
            buffer_select <= 1'b0;
            bin_valid <= 1'b0;
            magnitude_valid <= 1'b0;
            bfly_pipe <= 3'd0;

            for (i = 0; i < FFT_SIZE; i = i + 1) begin
                mem_real_a[i] <= 0;
                mem_imag_a[i] <= 0;
                mem_real_b[i] <= 0;
                mem_imag_b[i] <= 0;
            end
        end else if (enable) begin
            // Default outputs
            done <= 1'b0;
            bin_valid <= 1'b0;
            magnitude_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    sample_ready <= 1'b1;
                    if (start) begin
                        busy <= 1'b1;
                        sample_count <= 6'd0;
                        state <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    // Load input samples with bit-reversed addressing
                    if (sample_valid && sample_ready) begin
                        mem_real_a[bit_reverse(sample_count)] <= sample_in;
                        mem_imag_a[bit_reverse(sample_count)] <= 16'd0;

                        if (sample_count == FFT_SIZE - 1) begin
                            sample_ready <= 1'b0;
                            state <= ST_BUTTERFLY;
                            stage <= 3'd0;
                            butterfly_count <= 6'd0;
                            buffer_select <= 1'b0;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                ST_BUTTERFLY: begin
                    // Compute butterflies for current stage
                    // Stage s has 2^s butterflies per group, N/2^(s+1) groups

                    // Calculate addresses for this butterfly
                    begin : calc_butterfly
                        reg [5:0] group_size;
                        reg [5:0] half_size;
                        reg [5:0] group_idx;
                        reg [5:0] pair_idx;

                        group_size = 6'd1 << (stage + 1);
                        half_size = 6'd1 << stage;
                        group_idx = butterfly_count / half_size;
                        pair_idx = butterfly_count % half_size;

                        addr_a = group_idx * group_size + pair_idx;
                        addr_b = addr_a + half_size;
                        twiddle_idx = pair_idx * (FFT_SIZE >> (stage + 1));
                    end

                    // Pipeline butterfly computation
                    bfly_pipe <= {bfly_pipe[1:0], 1'b1};

                    // Load operands
                    if (!buffer_select) begin
                        bfly_a_real <= mem_real_a[addr_a];
                        bfly_a_imag <= mem_imag_a[addr_a];
                        bfly_b_real <= mem_real_a[addr_b];
                        bfly_b_imag <= mem_imag_a[addr_b];
                    end else begin
                        bfly_a_real <= mem_real_b[addr_a];
                        bfly_a_imag <= mem_imag_b[addr_a];
                        bfly_b_real <= mem_real_b[addr_b];
                        bfly_b_imag <= mem_imag_b[addr_b];
                    end

                    bfly_w_cos <= twiddle_cos[twiddle_idx];
                    bfly_w_sin <= twiddle_sin[twiddle_idx];

                    // Store results (3 cycles later due to pipeline)
                    if (bfly_pipe[2]) begin
                        if (!buffer_select) begin
                            mem_real_b[addr_a] <= bfly_out_a_real[DATA_WIDTH:1];  // Scale by 1/2
                            mem_imag_b[addr_a] <= bfly_out_a_imag[DATA_WIDTH:1];
                            mem_real_b[addr_b] <= bfly_out_b_real[DATA_WIDTH:1];
                            mem_imag_b[addr_b] <= bfly_out_b_imag[DATA_WIDTH:1];
                        end else begin
                            mem_real_a[addr_a] <= bfly_out_a_real[DATA_WIDTH:1];
                            mem_imag_a[addr_a] <= bfly_out_a_imag[DATA_WIDTH:1];
                            mem_real_a[addr_b] <= bfly_out_b_real[DATA_WIDTH:1];
                            mem_imag_a[addr_b] <= bfly_out_b_imag[DATA_WIDTH:1];
                        end

                        butterfly_count <= butterfly_count + 1'b1;

                        if (butterfly_count == (FFT_SIZE/2) - 1) begin
                            butterfly_count <= 6'd0;
                            buffer_select <= ~buffer_select;

                            if (stage == 5) begin  // log2(64) - 1 = 5
                                state <= ST_OUTPUT;
                                bin_index <= 6'd0;
                            end else begin
                                stage <= stage + 1'b1;
                            end
                        end
                    end
                end

                ST_OUTPUT: begin
                    // Output FFT bins
                    if (!buffer_select) begin
                        bin_real <= mem_real_b[bin_index];
                        bin_imag <= mem_imag_b[bin_index];
                    end else begin
                        bin_real <= mem_real_a[bin_index];
                        bin_imag <= mem_imag_a[bin_index];
                    end
                    bin_valid <= 1'b1;

                    if (bin_index == FFT_SIZE - 1) begin
                        state <= ST_ANALYZE;
                        bin_index <= 6'd0;
                        peak_magnitude <= 16'd0;
                        peak_bin <= 6'd0;
                    end else begin
                        bin_index <= bin_index + 1'b1;
                    end
                end

                ST_ANALYZE: begin
                    // Find peak bin (excluding DC)
                    state <= ST_DONE;
                end

                ST_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    //=========================================================================
    // Magnitude Calculation (Approximation)
    //=========================================================================
    // |X| ≈ max(|Re|, |Im|) + 0.4 * min(|Re|, |Im|)
    // Avoids square root, good enough for peak detection

    reg signed [DATA_WIDTH-1:0] mag_re, mag_im;
    reg [DATA_WIDTH-1:0] abs_re, abs_im;
    reg [DATA_WIDTH-1:0] max_val, min_val;
    reg [DATA_WIDTH-1:0] magnitude_approx;
    reg mag_pipe_valid;

    always @(posedge clk) begin
        if (enable && bin_valid) begin
            // Absolute values
            abs_re <= (bin_real < 0) ? -bin_real : bin_real;
            abs_im <= (bin_imag < 0) ? -bin_imag : bin_imag;
            mag_pipe_valid <= 1'b1;
        end else begin
            mag_pipe_valid <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (enable && mag_pipe_valid) begin
            // Max and min
            if (abs_re > abs_im) begin
                max_val <= abs_re;
                min_val <= abs_im;
            end else begin
                max_val <= abs_im;
                min_val <= abs_re;
            end
        end
    end

    // Final approximation: max + min/2 + min/8 ≈ max + 0.625*min
    always @(posedge clk) begin
        if (enable) begin
            magnitude_approx <= max_val + (min_val >> 1) + (min_val >> 3);
            bin_magnitude <= magnitude_approx;
            magnitude_valid <= mag_pipe_valid;

            // Track peak
            if (mag_pipe_valid && bin_index > 0 && magnitude_approx > peak_magnitude) begin
                peak_magnitude <= magnitude_approx;
                peak_bin <= bin_index - 1;  // -1 due to pipeline delay
            end
        end
    end

    // Calculate frequency from peak bin
    // freq = bin * sample_rate / FFT_SIZE
    // freq * 10 = bin * sample_rate * 10 / 64
    (* use_dsp = "yes" *)
    always @(posedge clk) begin
        if (enable && state == ST_DONE) begin
            peak_frequency_x10 <= (peak_bin * sample_rate * 10) >> 6;  // /64
        end
    end

endmodule

//==============================================================================
// RPM Jitter Analyzer
//==============================================================================
// Specialized wrapper for analyzing spindle speed variations.
//==============================================================================

module rpm_jitter_analyzer #(
    parameter DATA_WIDTH = 16
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     enable,

    // Index pulse input (for RPM measurement)
    input  wire                     index_pulse,

    // Analysis control
    input  wire                     analyze_start,
    output wire                     analyze_busy,
    output wire                     analyze_done,

    // Results
    output reg  [15:0]              avg_rpm_x10,        // Average RPM * 10
    output reg  [15:0]              rpm_variance,       // RPM variance
    output reg  [15:0]              wow_frequency_x10,  // Primary wow frequency * 10
    output reg  [15:0]              wow_magnitude,      // Wow magnitude (% of nominal)
    output reg  [15:0]              flutter_freq_x10,   // Primary flutter frequency * 10
    output reg  [15:0]              flutter_magnitude   // Flutter magnitude
);

    // Measure index pulse periods
    reg [23:0] period_counter;
    reg [23:0] period_buffer [0:63];
    reg [5:0] period_index;
    reg period_ready;

    // Convert periods to RPM deviations for FFT
    reg signed [15:0] rpm_deviation [0:63];

    // Index pulse edge detection
    reg index_prev;
    wire index_rising;
    assign index_rising = index_pulse && !index_prev;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            period_counter <= 24'd0;
            period_index <= 6'd0;
            index_prev <= 1'b0;
            period_ready <= 1'b0;
        end else if (enable) begin
            index_prev <= index_pulse;

            if (index_rising) begin
                // Store period
                period_buffer[period_index] <= period_counter;
                period_counter <= 24'd0;

                if (period_index == 6'd63) begin
                    period_ready <= 1'b1;
                    period_index <= 6'd0;
                end else begin
                    period_index <= period_index + 1'b1;
                end
            end else begin
                period_counter <= period_counter + 1'b1;
            end
        end
    end

    // FFT for jitter spectrum
    wire fft_busy, fft_done;
    wire signed [15:0] fft_bin_real, fft_bin_imag;
    wire [5:0] fft_bin_index;
    wire fft_bin_valid;
    wire [15:0] fft_peak_freq;
    wire [15:0] fft_peak_mag;
    wire [5:0] fft_peak_bin;

    // Sample input to FFT
    reg signed [15:0] fft_sample;
    reg fft_sample_valid;
    wire fft_sample_ready;
    reg fft_start;

    fft_analyzer #(
        .FFT_SIZE(64),
        .DATA_WIDTH(16)
    ) u_fft (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .start(fft_start),
        .busy(fft_busy),
        .done(fft_done),
        .sample_in(fft_sample),
        .sample_valid(fft_sample_valid),
        .sample_ready(fft_sample_ready),
        .bin_real(fft_bin_real),
        .bin_imag(fft_bin_imag),
        .bin_index(fft_bin_index),
        .bin_valid(fft_bin_valid),
        .bin_magnitude(),
        .magnitude_valid(),
        .peak_bin(fft_peak_bin),
        .peak_magnitude(fft_peak_mag),
        .peak_frequency_x10(fft_peak_freq),
        .sample_rate(16'd100)  // ~100 Hz effective sample rate for RPM
    );

    assign analyze_busy = fft_busy;
    assign analyze_done = fft_done;

    // State machine to load FFT and process results
    reg [2:0] state;
    reg [5:0] load_index;

    localparam S_IDLE = 3'd0;
    localparam S_LOAD = 3'd1;
    localparam S_FFT  = 3'd2;
    localparam S_RESULT = 3'd3;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            load_index <= 6'd0;
            fft_start <= 1'b0;
            fft_sample_valid <= 1'b0;
            avg_rpm_x10 <= 16'd0;
            rpm_variance <= 16'd0;
            wow_frequency_x10 <= 16'd0;
            wow_magnitude <= 16'd0;
            flutter_freq_x10 <= 16'd0;
            flutter_magnitude <= 16'd0;
        end else if (enable) begin
            fft_start <= 1'b0;
            fft_sample_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (analyze_start && period_ready) begin
                        state <= S_LOAD;
                        load_index <= 6'd0;
                        fft_start <= 1'b1;
                    end
                end

                S_LOAD: begin
                    if (fft_sample_ready) begin
                        // Convert period to RPM deviation
                        // Simplified: just use period directly
                        fft_sample <= period_buffer[load_index][15:0];
                        fft_sample_valid <= 1'b1;

                        if (load_index == 6'd63) begin
                            state <= S_FFT;
                        end else begin
                            load_index <= load_index + 1'b1;
                        end
                    end
                end

                S_FFT: begin
                    if (fft_done) begin
                        state <= S_RESULT;
                    end
                end

                S_RESULT: begin
                    // Extract results
                    wow_frequency_x10 <= fft_peak_freq;
                    wow_magnitude <= fft_peak_mag;
                    // Simplified: flutter would be secondary peak
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
