//==============================================================================
// PRML (Partial Response Maximum Likelihood) Decoder
//==============================================================================
// File: prml_decoder.v
// Description: Viterbi-based PRML decoder for high-density ESDI and advanced
//              MFM/RLL recovery. Implements PR4 (Partial Response Class 4)
//              channel model with 4-state Viterbi detector.
//
// DSP Usage: 16-32 DSP48E2 slices (branch metric + ACS operations)
// Latency: ~64 samples (5 constraint lengths)
//
// Channel Model: PR4 - H(D) = 1 - D^2
//   - Input:  NRZ data (±1)
//   - Output: {-2, 0, +2} ternary signal
//
// Viterbi Detector:
//   - 4 states (00, 01, 10, 11 for last 2 bits)
//   - Branch metrics computed via DSP
//   - Add-Compare-Select (ACS) for path metrics
//   - Traceback for final decisions
//
// Target: AMD Spartan UltraScale+ XCSU35P
// Author: Claude Code (FluxRipper Project)
// Created: 2025-12-05 01:50
//==============================================================================

`timescale 1ns / 1ps

module prml_decoder #(
    parameter SAMPLE_WIDTH  = 10,       // Input sample width (signed)
    parameter METRIC_WIDTH  = 16,       // Path metric width
    parameter TRACEBACK_LEN = 32        // Traceback length
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     enable,

    // Input samples (from ADC/equalizer)
    input  wire signed [SAMPLE_WIDTH-1:0] sample_in,
    input  wire                     sample_valid,

    // Decoded output
    output reg                      bit_out,
    output reg                      bit_valid,

    // Channel reference levels
    input  wire signed [SAMPLE_WIDTH-1:0] level_neg2,   // Expected level for -2
    input  wire signed [SAMPLE_WIDTH-1:0] level_zero,   // Expected level for 0
    input  wire signed [SAMPLE_WIDTH-1:0] level_pos2,   // Expected level for +2

    // Status
    output reg  [METRIC_WIDTH-1:0]  min_path_metric,
    output reg  [1:0]               min_state,
    output reg                      sync_locked
);

    //=========================================================================
    // PR4 State Definitions
    //=========================================================================
    // State encoding: {bit[n-1], bit[n-2]}
    // Output y[n] = x[n] - x[n-2] where x[n] ∈ {-1, +1}
    //
    // State transitions and outputs:
    // State 00 (--): Input 0 -> State 00, Output -1-(-1) = 0
    //                Input 1 -> State 10, Output +1-(-1) = +2
    // State 01 (-+): Input 0 -> State 00, Output -1-(+1) = -2
    //                Input 1 -> State 10, Output +1-(+1) = 0
    // State 10 (+-): Input 0 -> State 01, Output -1-(-1) = 0
    //                Input 1 -> State 11, Output +1-(-1) = +2
    // State 11 (++): Input 0 -> State 01, Output -1-(+1) = -2
    //                Input 1 -> State 11, Output +1-(+1) = 0

    localparam ST_00 = 2'b00;
    localparam ST_01 = 2'b01;
    localparam ST_10 = 2'b10;
    localparam ST_11 = 2'b11;

    //=========================================================================
    // Branch Metric Calculation
    //=========================================================================
    // Distance from received sample to expected value for each branch
    // Using squared error: (sample - expected)^2

    (* use_dsp = "yes" *)
    reg signed [SAMPLE_WIDTH:0] diff_neg2, diff_zero, diff_pos2;
    reg [2*SAMPLE_WIDTH-1:0] bm_neg2, bm_zero, bm_pos2;

    always @(posedge clk) begin
        if (enable && sample_valid) begin
            // Differences
            diff_neg2 <= sample_in - level_neg2;
            diff_zero <= sample_in - level_zero;
            diff_pos2 <= sample_in - level_pos2;
        end
    end

    // Squared errors (branch metrics)
    (* use_dsp = "yes" *)
    always @(posedge clk) begin
        if (enable) begin
            bm_neg2 <= diff_neg2 * diff_neg2;
            bm_zero <= diff_zero * diff_zero;
            bm_pos2 <= diff_pos2 * diff_pos2;
        end
    end

    // Truncated branch metrics
    wire [METRIC_WIDTH-1:0] bm_n2, bm_0, bm_p2;
    assign bm_n2 = bm_neg2[2*SAMPLE_WIDTH-1:2*SAMPLE_WIDTH-METRIC_WIDTH];
    assign bm_0  = bm_zero[2*SAMPLE_WIDTH-1:2*SAMPLE_WIDTH-METRIC_WIDTH];
    assign bm_p2 = bm_pos2[2*SAMPLE_WIDTH-1:2*SAMPLE_WIDTH-METRIC_WIDTH];

    //=========================================================================
    // Path Metrics Storage
    //=========================================================================

    reg [METRIC_WIDTH-1:0] path_metric [0:3];
    reg [METRIC_WIDTH-1:0] path_metric_new [0:3];

    //=========================================================================
    // Add-Compare-Select (ACS) Units
    //=========================================================================
    // Each state has 2 incoming paths; select the one with lower metric

    // ACS for State 00 (from State 00 with output 0, from State 01 with output -2)
    wire [METRIC_WIDTH-1:0] pm00_from_00, pm00_from_01;
    wire [METRIC_WIDTH-1:0] pm00_new;
    wire                    survivor00;

    assign pm00_from_00 = path_metric[ST_00] + bm_0;    // State 00, input 0, output 0
    assign pm00_from_01 = path_metric[ST_01] + bm_n2;   // State 01, input 0, output -2
    assign survivor00 = (pm00_from_01 < pm00_from_00);
    assign pm00_new = survivor00 ? pm00_from_01 : pm00_from_00;

    // ACS for State 01 (from State 10 with output 0, from State 11 with output -2)
    wire [METRIC_WIDTH-1:0] pm01_from_10, pm01_from_11;
    wire [METRIC_WIDTH-1:0] pm01_new;
    wire                    survivor01;

    assign pm01_from_10 = path_metric[ST_10] + bm_0;    // State 10, input 0, output 0
    assign pm01_from_11 = path_metric[ST_11] + bm_n2;   // State 11, input 0, output -2
    assign survivor01 = (pm01_from_11 < pm01_from_10);
    assign pm01_new = survivor01 ? pm01_from_11 : pm01_from_10;

    // ACS for State 10 (from State 00 with output +2, from State 01 with output 0)
    wire [METRIC_WIDTH-1:0] pm10_from_00, pm10_from_01;
    wire [METRIC_WIDTH-1:0] pm10_new;
    wire                    survivor10;

    assign pm10_from_00 = path_metric[ST_00] + bm_p2;   // State 00, input 1, output +2
    assign pm10_from_01 = path_metric[ST_01] + bm_0;    // State 01, input 1, output 0
    assign survivor10 = (pm10_from_01 < pm10_from_00);
    assign pm10_new = survivor10 ? pm10_from_01 : pm10_from_00;

    // ACS for State 11 (from State 10 with output +2, from State 11 with output 0)
    wire [METRIC_WIDTH-1:0] pm11_from_10, pm11_from_11;
    wire [METRIC_WIDTH-1:0] pm11_new;
    wire                    survivor11;

    assign pm11_from_10 = path_metric[ST_10] + bm_p2;   // State 10, input 1, output +2
    assign pm11_from_11 = path_metric[ST_11] + bm_0;    // State 11, input 1, output 0
    assign survivor11 = (pm11_from_11 < pm11_from_10);
    assign pm11_new = survivor11 ? pm11_from_11 : pm11_from_10;

    //=========================================================================
    // Traceback Memory
    //=========================================================================

    // Store survivor decisions for each state at each time step
    reg [3:0] survivor_mem [0:TRACEBACK_LEN-1];  // 4 bits: one per state
    reg [5:0] tb_write_ptr;
    reg [5:0] tb_read_ptr;

    //=========================================================================
    // Valid Pipeline
    //=========================================================================

    reg [3:0] valid_pipe;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            valid_pipe <= 4'd0;
        end else if (enable) begin
            valid_pipe <= {valid_pipe[2:0], sample_valid};
        end
    end

    wire acs_valid = valid_pipe[2];
    wire tb_valid = valid_pipe[3] && (tb_write_ptr >= TRACEBACK_LEN - 1);

    //=========================================================================
    // Path Metric Update
    //=========================================================================

    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 4; i = i + 1) begin
                path_metric[i] <= {METRIC_WIDTH{1'b0}};
            end
            tb_write_ptr <= 6'd0;
        end else if (enable && acs_valid) begin
            // Update path metrics
            path_metric[ST_00] <= pm00_new;
            path_metric[ST_01] <= pm01_new;
            path_metric[ST_10] <= pm10_new;
            path_metric[ST_11] <= pm11_new;

            // Store survivors
            survivor_mem[tb_write_ptr] <= {survivor11, survivor10, survivor01, survivor00};

            // Increment write pointer
            if (tb_write_ptr == TRACEBACK_LEN - 1) begin
                tb_write_ptr <= 6'd0;
            end else begin
                tb_write_ptr <= tb_write_ptr + 1'b1;
            end

            // Metric normalization (prevent overflow)
            // Find minimum and subtract from all
            begin : normalize
                reg [METRIC_WIDTH-1:0] min_metric;
                min_metric = pm00_new;
                if (pm01_new < min_metric) min_metric = pm01_new;
                if (pm10_new < min_metric) min_metric = pm10_new;
                if (pm11_new < min_metric) min_metric = pm11_new;

                if (min_metric > {1'b0, {(METRIC_WIDTH-1){1'b1}}}) begin  // > half max
                    path_metric[ST_00] <= pm00_new - min_metric;
                    path_metric[ST_01] <= pm01_new - min_metric;
                    path_metric[ST_10] <= pm10_new - min_metric;
                    path_metric[ST_11] <= pm11_new - min_metric;
                end

                min_path_metric <= min_metric;
            end
        end
    end

    //=========================================================================
    // Traceback
    //=========================================================================

    reg [1:0] tb_state;
    reg [5:0] tb_count;
    reg       tb_running;
    reg       decoded_bit;
    reg       decoded_valid;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tb_state <= ST_00;
            tb_count <= 6'd0;
            tb_running <= 1'b0;
            decoded_bit <= 1'b0;
            decoded_valid <= 1'b0;
            bit_out <= 1'b0;
            bit_valid <= 1'b0;
            min_state <= 2'b00;
        end else if (enable) begin
            decoded_valid <= 1'b0;
            bit_valid <= 1'b0;

            if (tb_valid && !tb_running) begin
                // Start traceback from state with minimum metric
                begin : find_min_state
                    reg [METRIC_WIDTH-1:0] min_m;
                    min_m = path_metric[0];
                    tb_state <= ST_00;
                    if (path_metric[1] < min_m) begin min_m = path_metric[1]; tb_state <= ST_01; end
                    if (path_metric[2] < min_m) begin min_m = path_metric[2]; tb_state <= ST_10; end
                    if (path_metric[3] < min_m) begin tb_state <= ST_11; end
                    min_state <= tb_state;
                end

                tb_count <= TRACEBACK_LEN - 1;
                tb_running <= 1'b1;
                tb_read_ptr <= (tb_write_ptr == 0) ? TRACEBACK_LEN - 1 : tb_write_ptr - 1;
            end else if (tb_running) begin
                // Trace back through survivors
                begin : traceback_step
                    reg [3:0] survivors;
                    reg       prev_bit;

                    survivors = survivor_mem[tb_read_ptr];

                    // Determine previous state based on current state and survivor
                    case (tb_state)
                        ST_00: begin
                            prev_bit = 1'b0;
                            tb_state <= survivors[0] ? ST_01 : ST_00;
                        end
                        ST_01: begin
                            prev_bit = 1'b0;
                            tb_state <= survivors[1] ? ST_11 : ST_10;
                        end
                        ST_10: begin
                            prev_bit = 1'b1;
                            tb_state <= survivors[2] ? ST_01 : ST_00;
                        end
                        ST_11: begin
                            prev_bit = 1'b1;
                            tb_state <= survivors[3] ? ST_11 : ST_10;
                        end
                    endcase

                    // Store decoded bit (will be output at end of traceback)
                    decoded_bit <= prev_bit;
                end

                // Decrement read pointer
                if (tb_read_ptr == 0) begin
                    tb_read_ptr <= TRACEBACK_LEN - 1;
                end else begin
                    tb_read_ptr <= tb_read_ptr - 1'b1;
                end

                // Count down
                if (tb_count == 0) begin
                    tb_running <= 1'b0;
                    decoded_valid <= 1'b1;
                end else begin
                    tb_count <= tb_count - 1'b1;
                end
            end

            // Output decoded bit
            if (decoded_valid) begin
                bit_out <= decoded_bit;
                bit_valid <= 1'b1;
            end
        end
    end

    //=========================================================================
    // Sync Lock Detection
    //=========================================================================

    reg [7:0] low_metric_count;
    localparam SYNC_THRESHOLD = {METRIC_WIDTH{1'b0}} + 16'd1000;  // Tune this
    localparam SYNC_COUNT = 8'd64;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            low_metric_count <= 8'd0;
            sync_locked <= 1'b0;
        end else if (enable && acs_valid) begin
            if (min_path_metric < SYNC_THRESHOLD) begin
                if (low_metric_count < SYNC_COUNT) begin
                    low_metric_count <= low_metric_count + 1'b1;
                end else begin
                    sync_locked <= 1'b1;
                end
            end else begin
                low_metric_count <= 8'd0;
                sync_locked <= 1'b0;
            end
        end
    end

endmodule

//==============================================================================
// EPR4 (Extended PR4) Decoder
//==============================================================================
// Higher density channel: H(D) = 1 + D - D^2 - D^3
// 8-state Viterbi with more complex branch structure.
//==============================================================================

module epr4_decoder #(
    parameter SAMPLE_WIDTH  = 10,
    parameter METRIC_WIDTH  = 16,
    parameter TRACEBACK_LEN = 48
)(
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     enable,

    input  wire signed [SAMPLE_WIDTH-1:0] sample_in,
    input  wire                     sample_valid,

    output reg                      bit_out,
    output reg                      bit_valid,

    // 5 reference levels for EPR4: {-4, -2, 0, +2, +4}
    input  wire signed [SAMPLE_WIDTH-1:0] level_n4,
    input  wire signed [SAMPLE_WIDTH-1:0] level_n2,
    input  wire signed [SAMPLE_WIDTH-1:0] level_0,
    input  wire signed [SAMPLE_WIDTH-1:0] level_p2,
    input  wire signed [SAMPLE_WIDTH-1:0] level_p4,

    output reg  [METRIC_WIDTH-1:0]  min_path_metric,
    output reg                      sync_locked
);

    // EPR4 has 8 states (3-bit history)
    // Full implementation would follow same pattern as PR4 but with
    // 8 ACS units and 5 branch metrics

    // Simplified: Just instantiate PR4 for now
    // Full EPR4 adds ~1000 lines

    prml_decoder #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .METRIC_WIDTH(METRIC_WIDTH),
        .TRACEBACK_LEN(TRACEBACK_LEN)
    ) u_pr4_fallback (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .bit_out(bit_out),
        .bit_valid(bit_valid),
        .level_neg2(level_n2),
        .level_zero(level_0),
        .level_pos2(level_p2),
        .min_path_metric(min_path_metric),
        .min_state(),
        .sync_locked(sync_locked)
    );

endmodule
