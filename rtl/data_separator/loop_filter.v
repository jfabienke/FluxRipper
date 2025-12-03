//-----------------------------------------------------------------------------
// Loop Filter for FluxRipper DPLL
// PI (Proportional-Integral) controller for PLL stability
//
// Supports automatic bandwidth switching and rate change strobe for
// Macintosh variable-speed zone transitions.
//
// Updated: 2025-12-03 22:55
//-----------------------------------------------------------------------------

module loop_filter (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [15:0] phase_error,     // Signed phase error input
    input  wire        error_valid,     // Phase error is valid
    input  wire [7:0]  kp,              // Proportional gain (fixed point 0.8)
    input  wire [7:0]  ki,              // Integral gain (fixed point 0.8)
    output reg  [15:0] phase_adj,       // Phase adjustment output
    output reg         phase_adj_valid  // Output is valid
);

    // Integrator with saturation
    reg signed [23:0] integrator;

    // Intermediate calculations
    wire signed [15:0] error_signed;
    wire signed [23:0] p_term;
    wire signed [23:0] i_term;
    wire signed [23:0] sum;
    wire signed [23:0] new_integrator;

    // Saturation limits
    localparam signed [23:0] INT_MAX = 24'sh3FFFFF;
    localparam signed [23:0] INT_MIN = 24'sh400000;

    assign error_signed = phase_error;

    // Proportional term: Kp * error
    assign p_term = (error_signed * $signed({1'b0, kp})) >>> 8;

    // Integral term: Ki * error (accumulated)
    assign i_term = (error_signed * $signed({1'b0, ki})) >>> 8;

    // New integrator value with saturation
    assign new_integrator = integrator + i_term;

    // Sum of P and I terms
    assign sum = p_term + integrator;

    always @(posedge clk) begin
        if (reset) begin
            integrator <= 24'd0;
            phase_adj <= 16'd0;
            phase_adj_valid <= 1'b0;
        end else if (enable && error_valid) begin
            // Update integrator with saturation
            if (new_integrator > INT_MAX) begin
                integrator <= INT_MAX;
            end else if (new_integrator < INT_MIN) begin
                integrator <= INT_MIN;
            end else begin
                integrator <= new_integrator;
            end

            // Output phase adjustment (saturate to 16 bits)
            if (sum > 24'sh007FFF) begin
                phase_adj <= 16'h7FFF;
            end else if (sum < 24'shFF8000) begin
                phase_adj <= 16'h8000;
            end else begin
                phase_adj <= sum[15:0];
            end

            phase_adj_valid <= 1'b1;
        end else begin
            phase_adj_valid <= 1'b0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Loop Filter with configurable bandwidth
// Presets for different acquisition/tracking modes
//-----------------------------------------------------------------------------
module loop_filter_adaptive (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [15:0] phase_error,
    input  wire        error_valid,
    input  wire [1:0]  bandwidth,       // 00=narrow, 01=medium, 10=wide, 11=acquisition
    output reg  [15:0] phase_adj,
    output reg         phase_adj_valid
);

    // Gain presets (Kp, Ki as 8-bit fixed point)
    // Narrow: low bandwidth, stable tracking
    // Wide: high bandwidth, fast acquisition
    reg [7:0] kp, ki;

    always @(*) begin
        case (bandwidth)
            2'b00: begin kp = 8'h08; ki = 8'h01; end  // Narrow: Kp=0.03, Ki=0.004
            2'b01: begin kp = 8'h10; ki = 8'h02; end  // Medium: Kp=0.06, Ki=0.008
            2'b10: begin kp = 8'h20; ki = 8'h04; end  // Wide: Kp=0.12, Ki=0.015
            2'b11: begin kp = 8'h40; ki = 8'h08; end  // Acquisition: Kp=0.25, Ki=0.03
        endcase
    end

    // Instantiate base loop filter
    loop_filter lf (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .phase_error(phase_error),
        .error_valid(error_valid),
        .kp(kp),
        .ki(ki),
        .phase_adj(phase_adj),
        .phase_adj_valid(phase_adj_valid)
    );

endmodule

//-----------------------------------------------------------------------------
// Loop Filter with automatic bandwidth switching
// Widens bandwidth for acquisition, narrows for tracking
// Supports rate_change strobe for Macintosh zone transitions
//-----------------------------------------------------------------------------
module loop_filter_auto (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [15:0] phase_error,
    input  wire        error_valid,
    input  wire        pll_locked,      // PLL is locked
    input  wire [1:0]  margin_zone,     // Phase margin indicator
    input  wire        rate_change,     // Pulse when data rate changes (Mac zone transition)
    output wire [15:0] phase_adj,
    output wire        phase_adj_valid,
    output reg  [1:0]  current_bandwidth
);

    // State machine for bandwidth control
    reg [7:0] good_margin_cnt;
    reg [7:0] bad_margin_cnt;

    // Rate change holdoff counter
    // Forces acquisition mode for N samples after rate change
    reg [4:0] rate_change_holdoff;
    localparam RATE_CHANGE_HOLDOFF = 5'd20;  // Hold acquisition mode for 20 samples

    localparam GOOD_THRESHOLD = 8'd64;   // Samples before narrowing
    localparam BAD_THRESHOLD = 8'd8;     // Samples before widening

    // Effective bandwidth (forced to acquisition during holdoff)
    wire [1:0] effective_bandwidth;
    assign effective_bandwidth = (rate_change_holdoff > 0) ? 2'b11 : current_bandwidth;

    always @(posedge clk) begin
        if (reset) begin
            current_bandwidth <= 2'b11;  // Start in acquisition mode
            good_margin_cnt <= 8'd0;
            bad_margin_cnt <= 8'd0;
            rate_change_holdoff <= 5'd0;
        end else begin
            //-------------------------------------------------------------
            // Rate change detection (Mac zone transition)
            // Force acquisition mode immediately
            //-------------------------------------------------------------
            if (rate_change) begin
                rate_change_holdoff <= RATE_CHANGE_HOLDOFF;
                good_margin_cnt <= 8'd0;
                bad_margin_cnt <= 8'd0;
            end else if (rate_change_holdoff > 0 && enable && error_valid) begin
                rate_change_holdoff <= rate_change_holdoff - 1'b1;
            end

            //-------------------------------------------------------------
            // Normal adaptive bandwidth control
            //-------------------------------------------------------------
            if (enable && error_valid && rate_change_holdoff == 0) begin
                // Count good/bad phase margins
                if (margin_zone == 2'b01) begin  // On-time
                    bad_margin_cnt <= 8'd0;
                    if (good_margin_cnt < 8'hFF) begin
                        good_margin_cnt <= good_margin_cnt + 1'b1;
                    end
                end else begin
                    good_margin_cnt <= 8'd0;
                    if (bad_margin_cnt < 8'hFF) begin
                        bad_margin_cnt <= bad_margin_cnt + 1'b1;
                    end
                end

                // Adjust bandwidth based on performance
                if (bad_margin_cnt >= BAD_THRESHOLD && current_bandwidth < 2'b11) begin
                    current_bandwidth <= current_bandwidth + 1'b1;  // Widen
                    bad_margin_cnt <= 8'd0;
                end else if (good_margin_cnt >= GOOD_THRESHOLD && current_bandwidth > 2'b00) begin
                    current_bandwidth <= current_bandwidth - 1'b1;  // Narrow
                    good_margin_cnt <= 8'd0;
                end
            end
        end
    end

    loop_filter_adaptive lf_adaptive (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .phase_error(phase_error),
        .error_valid(error_valid),
        .bandwidth(effective_bandwidth),
        .phase_adj(phase_adj),
        .phase_adj_valid(phase_adj_valid)
    );

endmodule
