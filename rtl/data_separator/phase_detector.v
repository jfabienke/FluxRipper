//-----------------------------------------------------------------------------
// Phase Detector for FluxRipper DPLL
// Compares flux edge timing to expected bit clock timing
//
// Updated: 2025-12-02 16:35
//-----------------------------------------------------------------------------

module phase_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        edge_detected,   // Flux edge pulse from edge detector
    input  wire [31:0] nco_phase,       // Current NCO phase
    output reg  [15:0] phase_error,     // Signed phase error
    output reg         error_valid,     // Phase error is valid
    output reg  [1:0]  margin_zone      // 00=early, 01=on-time, 10=late, 11=way off
);

    // Phase error is the difference between expected and actual edge time
    // Ideal edge should occur when NCO phase = 0 (bit boundary)
    //
    // Phase interpretation (32-bit accumulator):
    //   0x00000000 - 0x3FFFFFFF: Early (0° to 90°)
    //   0x40000000 - 0x7FFFFFFF: Early-normal (90° to 180°)
    //   0x80000000 - 0xBFFFFFFF: Late-normal (180° to 270°)
    //   0xC0000000 - 0xFFFFFFFF: Late (270° to 360°)

    // Window definitions for margin zones
    localparam [31:0] EARLY_LIMIT     = 32'h20000000;  // 45° early
    localparam [31:0] LATE_LIMIT      = 32'hE0000000;  // 45° late (315°)
    localparam [31:0] WAY_OFF_EARLY   = 32'h40000000;  // 90° early
    localparam [31:0] WAY_OFF_LATE    = 32'hC0000000;  // 90° late (270°)

    reg [31:0] captured_phase;

    always @(posedge clk) begin
        if (reset) begin
            phase_error <= 16'd0;
            error_valid <= 1'b0;
            margin_zone <= 2'b01;  // On-time by default
            captured_phase <= 32'd0;
        end else begin
            error_valid <= 1'b0;

            if (edge_detected) begin
                captured_phase <= nco_phase;
                error_valid <= 1'b1;

                // Calculate signed phase error (16-bit resolution)
                // Take upper 16 bits of phase for error calculation
                if (nco_phase[31]) begin
                    // Phase > 180°: edge is late, error is positive
                    phase_error <= nco_phase[31:16];
                end else begin
                    // Phase < 180°: edge is early, error is negative
                    phase_error <= nco_phase[31:16];
                end

                // Determine margin zone
                if (nco_phase < EARLY_LIMIT || nco_phase >= LATE_LIMIT) begin
                    // Within ±45° of bit boundary
                    margin_zone <= 2'b01;  // On-time
                end else if (nco_phase < WAY_OFF_EARLY) begin
                    margin_zone <= 2'b00;  // Early
                end else if (nco_phase >= WAY_OFF_LATE) begin
                    margin_zone <= 2'b10;  // Late
                end else begin
                    margin_zone <= 2'b11;  // Way off (mid-bit area)
                end
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Bang-Bang Phase Detector (simplified)
// Outputs early/late decision instead of proportional error
//-----------------------------------------------------------------------------
module phase_detector_bangbang (
    input  wire        clk,
    input  wire        reset,
    input  wire        edge_detected,
    input  wire [31:0] nco_phase,
    output reg         early,           // Edge arrived early
    output reg         late,            // Edge arrived late
    output reg         error_valid
);

    always @(posedge clk) begin
        if (reset) begin
            early <= 1'b0;
            late <= 1'b0;
            error_valid <= 1'b0;
        end else begin
            error_valid <= 1'b0;
            early <= 1'b0;
            late <= 1'b0;

            if (edge_detected) begin
                error_valid <= 1'b1;

                // Simple early/late decision based on phase quadrant
                if (nco_phase[31:30] == 2'b00 || nco_phase[31:30] == 2'b01) begin
                    // 0° to 180°: edge is early
                    early <= 1'b1;
                end else begin
                    // 180° to 360°: edge is late
                    late <= 1'b1;
                end
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Phase Detector with Missing Pulse Detection
// Handles cases where flux transitions are missing
//-----------------------------------------------------------------------------
module phase_detector_robust (
    input  wire        clk,
    input  wire        reset,
    input  wire        edge_detected,
    input  wire [31:0] nco_phase,
    input  wire        bit_clk,         // Bit clock from NCO
    output reg  [15:0] phase_error,
    output reg         error_valid,
    output reg  [1:0]  margin_zone,
    output reg         missing_pulse,   // No edge in last bit cell
    output reg  [3:0]  consecutive_missing // Count of consecutive missing pulses
);

    reg bit_clk_prev;
    wire bit_boundary;
    reg edge_seen_this_bit;

    assign bit_boundary = bit_clk && !bit_clk_prev;

    always @(posedge clk) begin
        if (reset) begin
            phase_error <= 16'd0;
            error_valid <= 1'b0;
            margin_zone <= 2'b01;
            missing_pulse <= 1'b0;
            consecutive_missing <= 4'd0;
            bit_clk_prev <= 1'b0;
            edge_seen_this_bit <= 1'b0;
        end else begin
            bit_clk_prev <= bit_clk;
            error_valid <= 1'b0;
            missing_pulse <= 1'b0;

            // Check for bit boundary
            if (bit_boundary) begin
                if (!edge_seen_this_bit) begin
                    missing_pulse <= 1'b1;
                    if (consecutive_missing < 4'd15) begin
                        consecutive_missing <= consecutive_missing + 1'b1;
                    end
                end else begin
                    consecutive_missing <= 4'd0;
                end
                edge_seen_this_bit <= 1'b0;
            end

            // Process edge
            if (edge_detected) begin
                edge_seen_this_bit <= 1'b1;
                error_valid <= 1'b1;

                // Phase error calculation
                phase_error <= nco_phase[31:16];

                // Margin zone
                if (nco_phase < 32'h20000000 || nco_phase >= 32'hE0000000) begin
                    margin_zone <= 2'b01;  // On-time
                end else if (nco_phase < 32'h40000000) begin
                    margin_zone <= 2'b00;  // Early
                end else if (nco_phase >= 32'hC0000000) begin
                    margin_zone <= 2'b10;  // Late
                end else begin
                    margin_zone <= 2'b11;  // Way off
                end
            end
        end
    end

endmodule
