//-----------------------------------------------------------------------------
// A/B Wire Correlation Calculator - Differential vs Single-Ended Discrimination
//
// Determines if the 20-pin data cable is carrying differential signals (ESDI)
// or single-ended signals (ST-506 MFM/RLL).
//
// Algorithm:
//   - Sample both wires (A and B) of the data pair
//   - For differential: A and B have strong NEGATIVE correlation
//     (when A rises, B falls; when A falls, B rises)
//   - For single-ended: No correlation (one wire swings, other is ground/static)
//
// Part of Phase 0: Pre-Personality Interface Detection
//
// Clock domain: 300 MHz (HDD domain)
// Created: 2025-12-04 12:50
//-----------------------------------------------------------------------------

module correlation_calc (
    input  wire        clk,              // 300 MHz
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        enable,           // Enable correlation measurement
    input  wire        clear,            // Clear accumulators

    //-------------------------------------------------------------------------
    // Data Wire Inputs (raw from FPGA pins)
    //-------------------------------------------------------------------------
    input  wire        wire_a,           // Raw wire A (READ_DATA+)
    input  wire        wire_b,           // Raw wire B (READ_DATA-)

    //-------------------------------------------------------------------------
    // Results
    //-------------------------------------------------------------------------
    output reg  [7:0]  correlation,      // 0=uncorrelated, 255=perfect negative
    output reg         is_differential,  // 1 if correlation > threshold
    output reg  [15:0] edge_count_a,     // Total edges detected on A
    output reg  [15:0] match_count,      // Edges with opposite polarity on B
    output reg  [7:0]  quality           // Signal quality 0-255
);

    //-------------------------------------------------------------------------
    // Correlation Thresholds
    //-------------------------------------------------------------------------
    // For differential signals: expect >78% correlation (200/255)
    // For single-ended: expect <20% correlation (50/255)

    localparam [7:0] DIFF_THRESHOLD     = 8'd200;  // >78% = differential
    localparam [7:0] SE_THRESHOLD       = 8'd50;   // <20% = single-ended
    localparam [3:0] EDGE_WINDOW        = 4'd8;    // 27ns @ 300 MHz

    //-------------------------------------------------------------------------
    // Signal Synchronizers
    //-------------------------------------------------------------------------
    reg [2:0] wire_a_sync;
    reg [2:0] wire_b_sync;
    reg       wire_a_prev;
    reg       wire_b_prev;

    wire a_rising;
    wire a_falling;
    wire b_rising;
    wire b_falling;

    always @(posedge clk) begin
        if (reset) begin
            wire_a_sync <= 3'b000;
            wire_b_sync <= 3'b000;
            wire_a_prev <= 1'b0;
            wire_b_prev <= 1'b0;
        end else begin
            // 3-stage synchronizers
            wire_a_sync <= {wire_a_sync[1:0], wire_a};
            wire_b_sync <= {wire_b_sync[1:0], wire_b};

            // Edge detection registers
            wire_a_prev <= wire_a_sync[2];
            wire_b_prev <= wire_b_sync[2];
        end
    end

    // Edge detection
    assign a_rising  = wire_a_sync[2] && !wire_a_prev;
    assign a_falling = !wire_a_sync[2] && wire_a_prev;
    assign b_rising  = wire_b_sync[2] && !wire_b_prev;
    assign b_falling = !wire_b_sync[2] && wire_b_prev;

    //-------------------------------------------------------------------------
    // Edge Timing Capture
    //-------------------------------------------------------------------------
    // Track recent edges on A and check for opposite edges on B within window

    reg [3:0]  a_edge_timer;       // Countdown from EDGE_WINDOW after A edge
    reg        a_edge_type;        // 1=rising, 0=falling
    reg        a_edge_pending;     // Waiting for B response

    reg [3:0]  b_edge_timer;       // Countdown from EDGE_WINDOW after B edge
    reg        b_edge_type;        // 1=rising, 0=falling
    reg        b_edge_pending;     // Waiting for A response

    //-------------------------------------------------------------------------
    // Accumulators
    //-------------------------------------------------------------------------
    reg [15:0] edges_on_a;         // Total A edges
    reg [15:0] edges_on_b;         // Total B edges
    reg [15:0] matched_edges;      // A edges with opposite B edge in window
    reg [15:0] runt_count;         // Very short pulses (noise indicator)

    // Pulse width measurement for quality
    reg [7:0]  a_pulse_width;
    reg [7:0]  a_pulse_min;
    reg [7:0]  a_pulse_max;

    // Correlation calculation temporary
    reg [23:0] scaled_match;

    //-------------------------------------------------------------------------
    // Main Correlation Logic
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || clear) begin
            a_edge_timer <= 4'd0;
            a_edge_type <= 1'b0;
            a_edge_pending <= 1'b0;
            b_edge_timer <= 4'd0;
            b_edge_type <= 1'b0;
            b_edge_pending <= 1'b0;
            edges_on_a <= 16'd0;
            edges_on_b <= 16'd0;
            matched_edges <= 16'd0;
            runt_count <= 16'd0;
            a_pulse_width <= 8'd0;
            a_pulse_min <= 8'hFF;
            a_pulse_max <= 8'd0;
            correlation <= 8'd0;
            is_differential <= 1'b0;
            edge_count_a <= 16'd0;
            match_count <= 16'd0;
            quality <= 8'd0;
        end else if (enable) begin
            //-------------------------------------------------------------
            // A edge detection and B response checking
            //-------------------------------------------------------------
            if (a_rising || a_falling) begin
                // New edge on A
                if (edges_on_a < 16'hFFFF)
                    edges_on_a <= edges_on_a + 1;

                // Update pulse width tracking
                if (a_pulse_width > 8'd0) begin
                    if (a_pulse_width < a_pulse_min)
                        a_pulse_min <= a_pulse_width;
                    if (a_pulse_width > a_pulse_max)
                        a_pulse_max <= a_pulse_width;

                    // Check for runts (very short pulses)
                    if (a_pulse_width < 8'd5)
                        runt_count <= runt_count + 1;
                end
                a_pulse_width <= 8'd0;

                // Start looking for opposite edge on B
                a_edge_pending <= 1'b1;
                a_edge_type <= a_rising;  // 1=rising, expecting B falling
                a_edge_timer <= EDGE_WINDOW;

                // Check if we were already waiting for A and B matched
                // (handles case where B edge came first)
                if (b_edge_pending && b_edge_timer > 4'd0) begin
                    // B was waiting for A, check if polarities are opposite
                    if ((a_rising && !b_edge_type) ||    // A rising, B was falling
                        (a_falling && b_edge_type)) begin // A falling, B was rising
                        if (matched_edges < 16'hFFFF)
                            matched_edges <= matched_edges + 1;
                    end
                    b_edge_pending <= 1'b0;
                end
            end else begin
                // Measure pulse width
                if (a_pulse_width < 8'hFF)
                    a_pulse_width <= a_pulse_width + 1;
            end

            // A edge timeout
            if (a_edge_pending) begin
                if (a_edge_timer > 4'd0) begin
                    a_edge_timer <= a_edge_timer - 1;

                    // Check for matching B edge within window
                    if ((a_edge_type && b_falling) ||    // A rising, want B falling
                        (!a_edge_type && b_rising)) begin // A falling, want B rising
                        if (matched_edges < 16'hFFFF)
                            matched_edges <= matched_edges + 1;
                        a_edge_pending <= 1'b0;
                    end
                end else begin
                    // Window expired, no match
                    a_edge_pending <= 1'b0;
                end
            end

            //-------------------------------------------------------------
            // B edge detection and A response checking
            //-------------------------------------------------------------
            if (b_rising || b_falling) begin
                if (edges_on_b < 16'hFFFF)
                    edges_on_b <= edges_on_b + 1;

                // Start looking for opposite edge on A (if not already matched)
                if (!a_edge_pending || a_edge_timer == 4'd0) begin
                    b_edge_pending <= 1'b1;
                    b_edge_type <= b_rising;
                    b_edge_timer <= EDGE_WINDOW;
                end
            end

            // B edge timeout
            if (b_edge_pending && !a_rising && !a_falling) begin
                if (b_edge_timer > 4'd0) begin
                    b_edge_timer <= b_edge_timer - 1;
                end else begin
                    b_edge_pending <= 1'b0;
                end
            end

            //-------------------------------------------------------------
            // Calculate correlation
            //-------------------------------------------------------------
            // correlation = (matched_edges * 255) / edges_on_a
            // To avoid division, update periodically

            if (edges_on_a >= 16'd64 && edges_on_a[5:0] == 6'd0) begin
                // Update every 64 edges
                if (edges_on_a > 16'd0) begin
                    // Approximation: (matched * 256) / edges ≈ matched << 8 / edges
                    scaled_match = {matched_edges, 8'd0};
                    correlation <= scaled_match[23:16];

                    // Determine if differential
                    is_differential <= (correlation >= DIFF_THRESHOLD);

                    // Calculate quality based on edge count and runt ratio
                    if (edges_on_a >= 16'd1000) begin
                        if (runt_count < edges_on_a >> 4) begin  // <6.25% runts
                            quality <= 8'd255;
                        end else if (runt_count < edges_on_a >> 3) begin  // <12.5% runts
                            quality <= 8'd192;
                        end else if (runt_count < edges_on_a >> 2) begin  // <25% runts
                            quality <= 8'd128;
                        end else begin
                            quality <= 8'd64;
                        end
                    end else if (edges_on_a >= 16'd100) begin
                        quality <= 8'd192;
                    end else begin
                        quality <= 8'd128;
                    end
                end
            end

            // Update output registers
            edge_count_a <= edges_on_a;
            match_count <= matched_edges;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Differential Signal Detector (Simplified Version)
// Quick check for differential signaling based on B wire activity
//-----------------------------------------------------------------------------
module diff_signal_quick_check (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    input  wire        wire_a,
    input  wire        wire_b,

    output reg         b_is_active,      // B wire has transitions (not static)
    output reg  [15:0] b_edge_count,     // Edges on B
    output reg         likely_differential
);

    reg [2:0] b_sync;
    reg       b_prev;
    wire      b_edge;

    always @(posedge clk) begin
        if (reset) begin
            b_sync <= 3'b000;
            b_prev <= 1'b0;
        end else begin
            b_sync <= {b_sync[1:0], wire_b};
            b_prev <= b_sync[2];
        end
    end

    assign b_edge = (b_sync[2] != b_prev);

    always @(posedge clk) begin
        if (reset) begin
            b_is_active <= 1'b0;
            b_edge_count <= 16'd0;
            likely_differential <= 1'b0;
        end else if (enable) begin
            if (b_edge) begin
                if (b_edge_count < 16'hFFFF)
                    b_edge_count <= b_edge_count + 1;
            end

            // If B has significant activity, likely differential
            // Single-ended: B would be static (ground reference)
            b_is_active <= (b_edge_count > 16'd100);
            likely_differential <= (b_edge_count > 16'd500);
        end
    end

endmodule
