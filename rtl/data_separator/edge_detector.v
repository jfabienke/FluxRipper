//-----------------------------------------------------------------------------
// Edge Detector Module for FluxRipper Data Separator
// Detects flux transitions from analog front-end
//
// Updated: 2025-12-02 16:35
//-----------------------------------------------------------------------------

module edge_detector (
    input  wire        clk,             // System clock (200 MHz recommended)
    input  wire        reset,
    input  wire        flux_in,         // Raw flux input from comparator
    input  wire        enable,          // Enable edge detection
    output reg         edge_detected,   // Pulse on edge detection
    output reg         edge_polarity,   // 0=falling, 1=rising
    output reg  [31:0] edge_timestamp,  // Timestamp of last edge
    output reg  [15:0] edge_interval    // Interval since last edge
);

    // Synchronizer for metastability
    reg [2:0] flux_sync;

    // Edge detection
    wire rising_edge;
    wire falling_edge;

    // Timestamp counter
    reg [31:0] timestamp_cnt;
    reg [31:0] last_edge_time;

    // Synchronize input (3-stage for better metastability handling)
    always @(posedge clk) begin
        if (reset) begin
            flux_sync <= 3'b000;
        end else begin
            flux_sync <= {flux_sync[1:0], flux_in};
        end
    end

    // Detect edges on synchronized signal
    assign rising_edge  = (flux_sync[2:1] == 2'b01);
    assign falling_edge = (flux_sync[2:1] == 2'b10);

    // Timestamp counter (free-running)
    always @(posedge clk) begin
        if (reset) begin
            timestamp_cnt <= 32'd0;
        end else begin
            timestamp_cnt <= timestamp_cnt + 1'b1;
        end
    end

    // Edge detection and interval measurement
    always @(posedge clk) begin
        if (reset) begin
            edge_detected <= 1'b0;
            edge_polarity <= 1'b0;
            edge_timestamp <= 32'd0;
            edge_interval <= 16'd0;
            last_edge_time <= 32'd0;
        end else if (enable) begin
            edge_detected <= 1'b0;

            if (rising_edge || falling_edge) begin
                edge_detected <= 1'b1;
                edge_polarity <= rising_edge;
                edge_timestamp <= timestamp_cnt;

                // Calculate interval (saturate at 16 bits)
                if ((timestamp_cnt - last_edge_time) > 32'h0000FFFF) begin
                    edge_interval <= 16'hFFFF;
                end else begin
                    edge_interval <= timestamp_cnt - last_edge_time;
                end

                last_edge_time <= timestamp_cnt;
            end
        end else begin
            edge_detected <= 1'b0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Glitch Filter for noisy flux signals
// Requires edge to be stable for N clocks before reporting
//-----------------------------------------------------------------------------
module edge_detector_filtered (
    input  wire        clk,
    input  wire        reset,
    input  wire        flux_in,
    input  wire        enable,
    input  wire [3:0]  filter_depth,    // Number of stable clocks required (1-15)
    output reg         edge_detected,
    output reg         edge_polarity,
    output reg  [31:0] edge_timestamp,
    output reg  [15:0] edge_interval
);

    reg [2:0]  flux_sync;
    reg [3:0]  stable_cnt;
    reg        flux_stable;
    reg        flux_prev;
    reg [31:0] timestamp_cnt;
    reg [31:0] last_edge_time;

    // Synchronize input
    always @(posedge clk) begin
        if (reset) begin
            flux_sync <= 3'b000;
        end else begin
            flux_sync <= {flux_sync[1:0], flux_in};
        end
    end

    // Glitch filter - require stable signal
    always @(posedge clk) begin
        if (reset) begin
            stable_cnt <= 4'd0;
            flux_stable <= 1'b0;
        end else begin
            if (flux_sync[2] == flux_sync[1]) begin
                if (stable_cnt < filter_depth) begin
                    stable_cnt <= stable_cnt + 1'b1;
                end else begin
                    flux_stable <= flux_sync[2];
                end
            end else begin
                stable_cnt <= 4'd0;
            end
        end
    end

    // Timestamp counter
    always @(posedge clk) begin
        if (reset) begin
            timestamp_cnt <= 32'd0;
        end else begin
            timestamp_cnt <= timestamp_cnt + 1'b1;
        end
    end

    // Edge detection on filtered signal
    always @(posedge clk) begin
        if (reset) begin
            edge_detected <= 1'b0;
            edge_polarity <= 1'b0;
            edge_timestamp <= 32'd0;
            edge_interval <= 16'd0;
            last_edge_time <= 32'd0;
            flux_prev <= 1'b0;
        end else if (enable) begin
            edge_detected <= 1'b0;
            flux_prev <= flux_stable;

            if (flux_stable != flux_prev) begin
                edge_detected <= 1'b1;
                edge_polarity <= flux_stable;  // 1 if now high (rising)
                edge_timestamp <= timestamp_cnt;

                if ((timestamp_cnt - last_edge_time) > 32'h0000FFFF) begin
                    edge_interval <= 16'hFFFF;
                end else begin
                    edge_interval <= timestamp_cnt - last_edge_time;
                end

                last_edge_time <= timestamp_cnt;
            end
        end else begin
            edge_detected <= 1'b0;
        end
    end

endmodule
