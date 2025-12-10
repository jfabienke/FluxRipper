//-----------------------------------------------------------------------------
// HDD PHY Probe - Physical Layer Detection
//
// Probes the ST-506 data interface to determine:
//   - Single-ended vs differential signaling
//   - Signal quality metrics (edge count, noise floor)
//   - Termination status
//
// Used as first stage of HDD discovery pipeline
//
// Created: 2025-12-03 22:00
//-----------------------------------------------------------------------------

module hdd_phy_probe (
    input  wire        clk,              // 300 MHz HDD clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        probe_start,      // Start probe sequence
    output reg         probe_done,       // Probe complete
    output reg         probe_busy,       // Probe in progress

    //-------------------------------------------------------------------------
    // PHY Inputs (from ST-506 interface)
    //-------------------------------------------------------------------------
    input  wire        read_data_se,     // Single-ended read data
    input  wire        read_data_p,      // Differential positive
    input  wire        read_data_n,      // Differential negative
    input  wire        index_pulse,      // Index pulse for timing reference

    //-------------------------------------------------------------------------
    // Probe Results
    //-------------------------------------------------------------------------
    output reg         phy_is_differential, // 1 = differential, 0 = single-ended
    output reg  [15:0] edge_count,          // Edges detected in sample window
    output reg  [7:0]  noise_score,         // 0 = clean, 255 = very noisy
    output reg  [7:0]  signal_quality,      // Overall quality 0-255
    output reg         signal_present,      // Signal detected at all
    output reg         termination_ok       // Termination appears correct
);

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    // Sample window: 1 revolution (~16.67ms @ 3600 RPM = 5M clocks @ 300 MHz)
    // Use shorter window for quicker probe
    localparam [23:0] SAMPLE_WINDOW       = 24'd1_500_000;  // 5ms @ 300 MHz
    localparam [15:0] MIN_EDGES_THRESHOLD = 16'd1000; // Minimum edges to confirm signal
    localparam [15:0] MAX_NOISE_EDGES = 16'd50000;    // Above this = noisy

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [2:0]
        STATE_IDLE       = 3'd0,
        STATE_WAIT_INDEX = 3'd1,
        STATE_SAMPLE_SE  = 3'd2,
        STATE_SAMPLE_DIFF= 3'd3,
        STATE_ANALYZE    = 3'd4,
        STATE_DONE       = 3'd5;

    reg [2:0] state;

    //-------------------------------------------------------------------------
    // Sampling Registers
    //-------------------------------------------------------------------------
    reg [23:0] sample_counter;

    // Single-ended sampling
    reg        se_prev;
    reg [15:0] se_edge_count;
    reg [15:0] se_pulse_width_sum;
    reg [7:0]  se_pulse_count;

    // Differential sampling
    reg        diff_prev;
    wire       diff_data;
    reg [15:0] diff_edge_count;
    reg [15:0] diff_pulse_width_sum;
    reg [7:0]  diff_pulse_count;

    // Differential signal reconstruction
    assign diff_data = read_data_p ^ read_data_n;

    // Pulse width measurement
    reg [15:0] pulse_width_counter;
    reg [15:0] min_pulse_width;
    reg [15:0] max_pulse_width;

    // Noise detection (rapid transitions)
    reg [7:0]  rapid_transition_count;
    reg [3:0]  transition_spacing;

    //-------------------------------------------------------------------------
    // Edge Detection
    //-------------------------------------------------------------------------
    wire se_edge;
    wire diff_edge;

    assign se_edge = se_prev ^ read_data_se;
    assign diff_edge = diff_prev ^ diff_data;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            probe_done <= 1'b0;
            probe_busy <= 1'b0;
            phy_is_differential <= 1'b0;
            edge_count <= 16'd0;
            noise_score <= 8'd0;
            signal_quality <= 8'd0;
            signal_present <= 1'b0;
            termination_ok <= 1'b0;
            sample_counter <= 24'd0;
            se_prev <= 1'b0;
            diff_prev <= 1'b0;
            se_edge_count <= 16'd0;
            diff_edge_count <= 16'd0;
            pulse_width_counter <= 16'd0;
            min_pulse_width <= 16'hFFFF;
            max_pulse_width <= 16'd0;
            rapid_transition_count <= 8'd0;
            transition_spacing <= 4'd0;
        end else begin
            probe_done <= 1'b0;

            // Track previous values for edge detection
            se_prev <= read_data_se;
            diff_prev <= diff_data;

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    probe_busy <= 1'b0;
                    if (probe_start) begin
                        probe_busy <= 1'b1;
                        sample_counter <= 24'd0;
                        se_edge_count <= 16'd0;
                        diff_edge_count <= 16'd0;
                        min_pulse_width <= 16'hFFFF;
                        max_pulse_width <= 16'd0;
                        rapid_transition_count <= 8'd0;
                        state <= STATE_WAIT_INDEX;
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_INDEX: begin
                    // Wait for index pulse to start synchronized sampling
                    if (index_pulse) begin
                        sample_counter <= 24'd0;
                        pulse_width_counter <= 16'd0;
                        state <= STATE_SAMPLE_SE;
                    end else if (sample_counter > SAMPLE_WINDOW) begin
                        // No index pulse - sample anyway
                        sample_counter <= 24'd0;
                        pulse_width_counter <= 16'd0;
                        state <= STATE_SAMPLE_SE;
                    end else begin
                        sample_counter <= sample_counter + 1;
                    end
                end

                //-------------------------------------------------------------
                STATE_SAMPLE_SE: begin
                    // Sample single-ended signal
                    sample_counter <= sample_counter + 1;
                    pulse_width_counter <= pulse_width_counter + 1;

                    if (se_edge) begin
                        se_edge_count <= se_edge_count + 1;

                        // Track pulse widths
                        if (pulse_width_counter < min_pulse_width)
                            min_pulse_width <= pulse_width_counter;
                        if (pulse_width_counter > max_pulse_width)
                            max_pulse_width <= pulse_width_counter;

                        // Detect rapid transitions (noise)
                        if (pulse_width_counter < 16'd10) begin
                            rapid_transition_count <= rapid_transition_count + 1;
                        end

                        pulse_width_counter <= 16'd0;
                    end

                    if (sample_counter >= SAMPLE_WINDOW) begin
                        sample_counter <= 24'd0;
                        pulse_width_counter <= 16'd0;
                        state <= STATE_SAMPLE_DIFF;
                    end
                end

                //-------------------------------------------------------------
                STATE_SAMPLE_DIFF: begin
                    // Sample differential signal
                    sample_counter <= sample_counter + 1;

                    if (diff_edge) begin
                        diff_edge_count <= diff_edge_count + 1;
                    end

                    if (sample_counter >= SAMPLE_WINDOW) begin
                        state <= STATE_ANALYZE;
                    end
                end

                //-------------------------------------------------------------
                STATE_ANALYZE: begin
                    // Determine PHY type and signal quality

                    // Signal present if enough edges detected
                    if (se_edge_count > MIN_EDGES_THRESHOLD ||
                        diff_edge_count > MIN_EDGES_THRESHOLD) begin
                        signal_present <= 1'b1;
                    end else begin
                        signal_present <= 1'b0;
                    end

                    // Differential detection:
                    // If differential has significantly more edges than SE,
                    // or if SE has none but diff has some, it's differential
                    if (diff_edge_count > se_edge_count + 16'd500) begin
                        phy_is_differential <= 1'b1;
                        edge_count <= diff_edge_count;
                    end else begin
                        phy_is_differential <= 1'b0;
                        edge_count <= se_edge_count;
                    end

                    // Noise score: based on rapid transitions and edge variance
                    if (rapid_transition_count > 8'd200) begin
                        noise_score <= 8'd255;
                    end else begin
                        noise_score <= rapid_transition_count;
                    end

                    // Signal quality: inverse of noise, scaled
                    if (signal_present) begin
                        if (noise_score < 8'd20) begin
                            signal_quality <= 8'd255;  // Excellent
                        end else if (noise_score < 8'd50) begin
                            signal_quality <= 8'd200;  // Good
                        end else if (noise_score < 8'd100) begin
                            signal_quality <= 8'd128;  // Fair
                        end else begin
                            signal_quality <= 8'd64;   // Poor
                        end
                    end else begin
                        signal_quality <= 8'd0;
                    end

                    // Termination check: pulse width variance
                    // Good termination = consistent pulse widths
                    if (max_pulse_width > 16'd0 && min_pulse_width < 16'hFFFF) begin
                        if ((max_pulse_width - min_pulse_width) < (min_pulse_width >> 1)) begin
                            termination_ok <= 1'b1;  // Variance < 50% of min
                        end else begin
                            termination_ok <= 1'b0;
                        end
                    end else begin
                        termination_ok <= 1'b0;
                    end

                    state <= STATE_DONE;
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    probe_done <= 1'b1;
                    probe_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// PHY Mode Controller
// Configures the physical interface based on probe results
//-----------------------------------------------------------------------------
module hdd_phy_mode_ctrl (
    input  wire        clk,
    input  wire        reset,

    // From PHY probe
    input  wire        phy_is_differential,
    input  wire        signal_present,

    // Configuration
    input  wire        force_se_mode,         // Force single-ended
    input  wire        force_diff_mode,       // Force differential
    input  wire        auto_detect,           // Use probe result

    // PHY control outputs
    output reg         use_differential,      // 1 = use diff, 0 = use SE
    output reg         enable_termination,    // Enable 100Ω termination
    output reg  [1:0]  phy_mode               // 00=off, 01=SE, 10=diff, 11=both
);

    always @(posedge clk) begin
        if (reset) begin
            use_differential <= 1'b0;
            enable_termination <= 1'b0;
            phy_mode <= 2'b00;
        end else begin
            if (force_se_mode) begin
                use_differential <= 1'b0;
                enable_termination <= 1'b0;
                phy_mode <= 2'b01;
            end else if (force_diff_mode) begin
                use_differential <= 1'b1;
                enable_termination <= 1'b1;
                phy_mode <= 2'b10;
            end else if (auto_detect && signal_present) begin
                use_differential <= phy_is_differential;
                enable_termination <= phy_is_differential;
                phy_mode <= phy_is_differential ? 2'b10 : 2'b01;
            end else begin
                // Default: try single-ended first
                use_differential <= 1'b0;
                enable_termination <= 1'b0;
                phy_mode <= 2'b01;
            end
        end
    end

endmodule
