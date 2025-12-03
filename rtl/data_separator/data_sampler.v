//-----------------------------------------------------------------------------
// Data Sampler for FluxRipper DPLL
// Samples flux data at optimal point in bit cell
//
// Updated: 2025-12-02 16:40
//-----------------------------------------------------------------------------

module data_sampler (
    input  wire        clk,
    input  wire        reset,
    input  wire        sample_point,    // Sample strobe from NCO
    input  wire        flux_in,         // Flux data to sample
    input  wire [31:0] nco_phase,       // For window detection
    output reg         bit_value,       // Sampled bit value
    output reg         bit_ready,       // New bit available
    output reg         in_window        // Currently in sample window
);

    // Sample window is around the mid-point of the bit cell
    // NCO phase 0x80000000 is the ideal sample point (180°)
    localparam [31:0] WINDOW_START = 32'h60000000;  // 135°
    localparam [31:0] WINDOW_END   = 32'hA0000000;  // 225°

    // Flux history for voting
    reg [3:0] flux_history;
    reg       sample_pending;

    // Window detection
    always @(posedge clk) begin
        if (reset) begin
            in_window <= 1'b0;
        end else begin
            in_window <= (nco_phase >= WINDOW_START) && (nco_phase < WINDOW_END);
        end
    end

    // Sample at mid-bit point
    always @(posedge clk) begin
        if (reset) begin
            bit_value <= 1'b0;
            bit_ready <= 1'b0;
            flux_history <= 4'b0000;
            sample_pending <= 1'b0;
        end else begin
            bit_ready <= 1'b0;

            // Track flux transitions in sample window
            if (in_window) begin
                flux_history <= {flux_history[2:0], flux_in};
                sample_pending <= 1'b1;
            end

            // Output sampled bit at sample point
            if (sample_point && sample_pending) begin
                // Use majority voting on flux history
                case (flux_history)
                    4'b0000, 4'b0001, 4'b0010, 4'b0100, 4'b1000: bit_value <= 1'b0;
                    4'b0011, 4'b0101, 4'b0110, 4'b1001, 4'b1010, 4'b1100: bit_value <= flux_in;
                    default: bit_value <= 1'b1;
                endcase
                bit_ready <= 1'b1;
                sample_pending <= 1'b0;
                flux_history <= 4'b0000;
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// MFM-aware Data Sampler
// Applies MFM decoding rules to detect '0' vs '1' data bits
//-----------------------------------------------------------------------------
module data_sampler_mfm (
    input  wire        clk,
    input  wire        reset,
    input  wire        edge_detected,   // Flux transition detected
    input  wire [31:0] nco_phase,       // Current phase
    input  wire        bit_clk,         // Bit clock from NCO
    output reg         data_bit,        // Decoded data bit
    output reg         clock_bit,       // Clock bit (for diagnostics)
    output reg         bit_ready        // New bit pair available
);

    // MFM encoding produces 2 flux cells per data bit:
    // - Cell 1 contains clock bit
    // - Cell 2 contains data bit
    //
    // Transition in cell 2 = data '1'
    // No transition in cell 2 = data '0'
    // Transition in cell 1 = clock '1' (only if prev data was '0')

    reg        bit_clk_prev;
    reg        edge_in_cell;
    reg        cell_select;      // 0 = clock cell, 1 = data cell
    reg [31:0] phase_at_edge;

    wire bit_boundary = bit_clk && !bit_clk_prev;

    always @(posedge clk) begin
        if (reset) begin
            data_bit <= 1'b0;
            clock_bit <= 1'b0;
            bit_ready <= 1'b0;
            bit_clk_prev <= 1'b0;
            edge_in_cell <= 1'b0;
            cell_select <= 1'b0;
            phase_at_edge <= 32'd0;
        end else begin
            bit_clk_prev <= bit_clk;
            bit_ready <= 1'b0;

            // Track edges in current cell
            if (edge_detected) begin
                edge_in_cell <= 1'b1;
                phase_at_edge <= nco_phase;
            end

            // Process at bit boundary
            if (bit_boundary) begin
                if (cell_select == 1'b0) begin
                    // Clock cell
                    clock_bit <= edge_in_cell;
                end else begin
                    // Data cell
                    data_bit <= edge_in_cell;
                    bit_ready <= 1'b1;
                end

                cell_select <= ~cell_select;
                edge_in_cell <= 1'b0;
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Lock Detector
// Determines when DPLL has achieved stable lock
//-----------------------------------------------------------------------------
module lock_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] phase_error,     // Current phase error
    input  wire        error_valid,     // Phase error is valid
    input  wire [1:0]  margin_zone,     // Phase margin indicator
    input  wire [15:0] lock_threshold,  // Max error for "locked" status
    output reg         pll_locked,      // PLL is locked
    output reg  [7:0]  lock_quality,    // Lock quality metric (0-255)
    output reg  [15:0] avg_phase_error  // Running average of phase error
);

    // Lock state machine
    localparam UNLOCKED = 2'b00;
    localparam ACQUIRING = 2'b01;
    localparam LOCKED = 2'b10;
    localparam HOLDING = 2'b11;

    reg [1:0] lock_state;
    reg [7:0] good_sample_cnt;
    reg [7:0] bad_sample_cnt;
    reg [23:0] error_accumulator;
    reg [7:0]  sample_cnt;

    // Thresholds
    localparam LOCK_SAMPLES = 8'd32;      // Samples to confirm lock
    localparam UNLOCK_SAMPLES = 8'd8;     // Bad samples to lose lock

    // Absolute value of phase error
    wire [15:0] abs_error = phase_error[15] ? (~phase_error + 1'b1) : phase_error;

    always @(posedge clk) begin
        if (reset) begin
            lock_state <= UNLOCKED;
            pll_locked <= 1'b0;
            lock_quality <= 8'd0;
            avg_phase_error <= 16'd0;
            good_sample_cnt <= 8'd0;
            bad_sample_cnt <= 8'd0;
            error_accumulator <= 24'd0;
            sample_cnt <= 8'd0;
        end else if (error_valid) begin
            // Update running average
            if (sample_cnt < 8'd255) begin
                sample_cnt <= sample_cnt + 1'b1;
                error_accumulator <= error_accumulator + {8'd0, abs_error};
            end else begin
                // Shift out old samples
                error_accumulator <= error_accumulator - {8'd0, avg_phase_error} + {8'd0, abs_error};
            end
            avg_phase_error <= error_accumulator[23:8];

            // Check if error is within threshold
            if (abs_error < lock_threshold && margin_zone == 2'b01) begin
                bad_sample_cnt <= 8'd0;
                if (good_sample_cnt < 8'hFF) begin
                    good_sample_cnt <= good_sample_cnt + 1'b1;
                end
            end else begin
                good_sample_cnt <= 8'd0;
                if (bad_sample_cnt < 8'hFF) begin
                    bad_sample_cnt <= bad_sample_cnt + 1'b1;
                end
            end

            // State machine
            case (lock_state)
                UNLOCKED: begin
                    pll_locked <= 1'b0;
                    if (good_sample_cnt >= 8'd4) begin
                        lock_state <= ACQUIRING;
                    end
                end

                ACQUIRING: begin
                    pll_locked <= 1'b0;
                    if (good_sample_cnt >= LOCK_SAMPLES) begin
                        lock_state <= LOCKED;
                    end else if (bad_sample_cnt >= 8'd4) begin
                        lock_state <= UNLOCKED;
                    end
                end

                LOCKED: begin
                    pll_locked <= 1'b1;
                    if (bad_sample_cnt >= UNLOCK_SAMPLES) begin
                        lock_state <= HOLDING;
                    end
                end

                HOLDING: begin
                    pll_locked <= 1'b1;  // Still report locked
                    if (good_sample_cnt >= 8'd8) begin
                        lock_state <= LOCKED;
                    end else if (bad_sample_cnt >= UNLOCK_SAMPLES * 2) begin
                        lock_state <= UNLOCKED;
                    end
                end
            endcase

            // Calculate lock quality
            if (pll_locked) begin
                // Quality based on average error magnitude
                if (avg_phase_error < 16'h0100) begin
                    lock_quality <= 8'hFF;  // Excellent
                end else if (avg_phase_error < 16'h0400) begin
                    lock_quality <= 8'hC0;  // Good
                end else if (avg_phase_error < 16'h1000) begin
                    lock_quality <= 8'h80;  // Fair
                end else begin
                    lock_quality <= 8'h40;  // Marginal
                end
            end else begin
                lock_quality <= 8'd0;
            end
        end
    end

endmodule
