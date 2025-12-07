//-----------------------------------------------------------------------------
// INDEX Frequency Counter - Floppy vs HDD Discrimination
//
// Measures the period between INDEX pulses to distinguish:
//   - Floppy: 300-360 RPM → 166-200ms period → 5-6 Hz
//   - HDD: 3000-3600 RPM → 16.7-20ms period → 50-60 Hz
//
// Part of Phase 0: Pre-Personality Interface Detection
//
// Clock domain: 300 MHz (HDD domain)
// Created: 2025-12-04 12:45
//-----------------------------------------------------------------------------

module index_freq_counter (
    input  wire        clk,              // 300 MHz
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        count_start,      // Start measurement
    input  wire        count_abort,      // Abort measurement
    input  wire [26:0] timeout,          // Max clocks to wait (default ~500ms)
    output reg         count_done,       // Measurement complete
    output reg         count_busy,       // Measurement in progress

    //-------------------------------------------------------------------------
    // INDEX Pulse Input
    //-------------------------------------------------------------------------
    input  wire        index_pulse,      // Raw INDEX from drive

    //-------------------------------------------------------------------------
    // Results
    //-------------------------------------------------------------------------
    output reg  [26:0] measured_period,  // Clocks between INDEX pulses
    output reg  [1:0]  freq_class,       // 0=none, 1=slow(floppy), 2=fast(HDD)
    output reg  [7:0]  pulse_count,      // INDEX pulses seen
    output reg  [7:0]  confidence        // 0-255 confidence in classification
);

    //-------------------------------------------------------------------------
    // Timing Thresholds at 300 MHz
    //-------------------------------------------------------------------------
    // Floppy 300 RPM: 200ms/rev = 60,000,000 clocks
    // Floppy 360 RPM: 166.7ms/rev = 50,000,000 clocks
    // HDD 3000 RPM: 20ms/rev = 6,000,000 clocks
    // HDD 3600 RPM: 16.67ms/rev = 5,000,000 clocks
    //
    // Threshold: 30,000,000 clocks = 100ms
    //   < 30M = HDD (freq_class = 2)
    //   > 30M = Floppy (freq_class = 1)

    localparam [26:0] FLOPPY_HDD_THRESHOLD = 27'd30_000_000;  // 100ms @ 300 MHz

    // Valid ranges (with 20% tolerance)
    localparam [26:0] FLOPPY_MIN_PERIOD = 27'd39_750_000;   // ~133ms (450 RPM max)
    localparam [26:0] FLOPPY_MAX_PERIOD = 27'd75_000_000;  // 250ms (240 RPM min)
    localparam [26:0] HDD_MIN_PERIOD    = 27'd3_750_000;    // 12.5ms (4800 RPM max)
    localparam [26:0] HDD_MAX_PERIOD    = 27'd9_750_000;   // 32.5ms (1846 RPM min)

    // Default timeout (500ms = 150M clocks)
    localparam [26:0] DEFAULT_TIMEOUT = 27'd150_000_000;

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [2:0]
        STATE_IDLE        = 3'd0,
        STATE_WAIT_FIRST  = 3'd1,
        STATE_MEASURING   = 3'd2,
        STATE_CLASSIFY    = 3'd3,
        STATE_DONE        = 3'd4;

    reg [2:0] state;

    //-------------------------------------------------------------------------
    // Internal Registers
    //-------------------------------------------------------------------------
    reg [26:0] period_counter;
    reg [26:0] period_accumulator;
    reg [26:0] active_timeout;
    reg [2:0]  period_samples;           // Number of periods measured (0-7)
    reg        index_prev;
    reg        index_sync [0:2];         // 3-stage synchronizer

    wire index_edge;

    //-------------------------------------------------------------------------
    // INDEX Pulse Synchronization and Edge Detection
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            index_sync[0] <= 1'b0;
            index_sync[1] <= 1'b0;
            index_sync[2] <= 1'b0;
            index_prev <= 1'b0;
        end else begin
            index_sync[0] <= index_pulse;
            index_sync[1] <= index_sync[0];
            index_sync[2] <= index_sync[1];
            index_prev <= index_sync[2];
        end
    end

    // Rising edge detection
    assign index_edge = index_sync[2] && !index_prev;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            count_done <= 1'b0;
            count_busy <= 1'b0;
            measured_period <= 27'd0;
            freq_class <= 2'd0;
            pulse_count <= 8'd0;
            confidence <= 8'd0;
            period_counter <= 27'd0;
            period_accumulator <= 27'd0;
            period_samples <= 3'd0;
            active_timeout <= DEFAULT_TIMEOUT;
        end else begin
            count_done <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    count_busy <= 1'b0;
                    if (count_start) begin
                        count_busy <= 1'b1;
                        period_counter <= 27'd0;
                        period_accumulator <= 27'd0;
                        period_samples <= 3'd0;
                        pulse_count <= 8'd0;
                        freq_class <= 2'd0;
                        confidence <= 8'd0;
                        // Use provided timeout or default
                        active_timeout <= (timeout != 27'd0) ? timeout : DEFAULT_TIMEOUT;
                        state <= STATE_WAIT_FIRST;
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_FIRST: begin
                    // Wait for first INDEX pulse to start measurement
                    period_counter <= period_counter + 1;

                    if (count_abort) begin
                        state <= STATE_DONE;
                    end else if (index_edge) begin
                        pulse_count <= 8'd1;
                        period_counter <= 27'd0;
                        state <= STATE_MEASURING;
                    end else if (period_counter >= active_timeout) begin
                        // Timeout - no INDEX pulses
                        freq_class <= 2'd0;  // Unknown
                        confidence <= 8'd0;
                        state <= STATE_DONE;
                    end
                end

                //-------------------------------------------------------------
                STATE_MEASURING: begin
                    period_counter <= period_counter + 1;

                    if (count_abort) begin
                        state <= STATE_CLASSIFY;
                    end else if (index_edge) begin
                        // Got another INDEX pulse
                        pulse_count <= pulse_count + 1;

                        // Accumulate period (for averaging)
                        period_accumulator <= period_accumulator + period_counter;
                        period_samples <= period_samples + 1;

                        // Reset counter for next period
                        period_counter <= 27'd0;

                        // After 3 periods, we have enough data
                        if (period_samples >= 3'd2) begin
                            state <= STATE_CLASSIFY;
                        end
                    end else if (period_counter >= active_timeout) begin
                        // Timeout waiting for next INDEX
                        if (period_samples > 3'd0) begin
                            // We have at least one period, classify with what we have
                            state <= STATE_CLASSIFY;
                        end else begin
                            // No complete periods
                            freq_class <= 2'd0;
                            confidence <= 8'd0;
                            state <= STATE_DONE;
                        end
                    end
                end

                //-------------------------------------------------------------
                STATE_CLASSIFY: begin
                    // Calculate average period
                    if (period_samples > 3'd0) begin
                        case (period_samples)
                            3'd1: measured_period <= period_accumulator;
                            3'd2: measured_period <= period_accumulator >> 1;
                            3'd3: measured_period <= period_accumulator / 3;
                            3'd4: measured_period <= period_accumulator >> 2;
                            default: measured_period <= period_accumulator >> 2;
                        endcase
                    end

                    // Classify based on threshold
                    if (period_accumulator == 27'd0 || period_samples == 3'd0) begin
                        freq_class <= 2'd0;  // Unknown
                        confidence <= 8'd0;
                    end else begin
                        // Calculate average for classification
                        // Using period_accumulator / period_samples approximation
                        reg [26:0] avg_period;
                        case (period_samples)
                            3'd1: avg_period = period_accumulator;
                            3'd2: avg_period = period_accumulator >> 1;
                            3'd3: avg_period = period_accumulator / 3;
                            3'd4: avg_period = period_accumulator >> 2;
                            default: avg_period = period_accumulator >> 2;
                        endcase

                        if (avg_period < FLOPPY_HDD_THRESHOLD) begin
                            // HDD range
                            freq_class <= 2'd2;

                            // Calculate confidence based on how well it fits HDD range
                            if (avg_period >= HDD_MIN_PERIOD && avg_period <= HDD_MAX_PERIOD) begin
                                // Perfect HDD range
                                confidence <= 8'd255;
                            end else if (avg_period < HDD_MIN_PERIOD) begin
                                // Faster than typical HDD (could be valid, lower confidence)
                                confidence <= 8'd180;
                            end else begin
                                // Borderline
                                confidence <= 8'd128;
                            end
                        end else begin
                            // Floppy range
                            freq_class <= 2'd1;

                            // Calculate confidence based on how well it fits floppy range
                            if (avg_period >= FLOPPY_MIN_PERIOD && avg_period <= FLOPPY_MAX_PERIOD) begin
                                // Perfect floppy range
                                confidence <= 8'd255;
                            end else if (avg_period > FLOPPY_MAX_PERIOD) begin
                                // Slower than typical (could be bad motor)
                                confidence <= 8'd128;
                            end else begin
                                // Borderline
                                confidence <= 8'd160;
                            end
                        end

                        // Boost confidence with more samples
                        if (period_samples >= 3'd3) begin
                            // 3+ samples, high confidence in measurement
                            // confidence already set above
                        end else if (period_samples == 3'd2) begin
                            // 2 samples, reduce confidence slightly
                            confidence <= (confidence > 8'd32) ? confidence - 8'd32 : 8'd0;
                        end else begin
                            // 1 sample, lower confidence
                            confidence <= (confidence > 8'd64) ? confidence - 8'd64 : 8'd0;
                        end
                    end

                    state <= STATE_DONE;
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    count_done <= 1'b1;
                    count_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// INDEX Period to RPM Converter (Utility Module)
// Converts measured period to RPM * 10 (for 0.1 RPM resolution)
//-----------------------------------------------------------------------------
module index_period_to_rpm (
    input  wire [26:0] period_clocks,    // Period in 300 MHz clocks
    output reg  [15:0] rpm_x10           // RPM * 10 (e.g., 36000 = 3600.0 RPM)
);

    // RPM = 60 / (period_clocks / 300_000_000)
    // RPM = 60 * 300_000_000 / period_clocks
    // RPM * 10 = 600 * 300_000_000 / period_clocks
    //          = 180_000_000_000 / period_clocks
    //
    // This is a big division; in practice, use lookup table or approximation

    // Simplified approximation using shift operations
    // For typical HDD (3000-3600 RPM): period ~5M-6M clocks
    // For typical floppy (300-360 RPM): period ~50M-60M clocks

    localparam [47:0] RPM_NUMERATOR = 48'd180_000_000_000;

    always @(*) begin
        if (period_clocks == 27'd0 || period_clocks > 27'd90_000_000) begin
            // Invalid or too slow
            rpm_x10 = 16'd0;
        end else if (period_clocks < 27'd3_000_000) begin
            // Too fast (>6000 RPM)
            rpm_x10 = 16'hFFFF;
        end else begin
            // Approximate division using lookup/interpolation
            // For simulation, use actual division
            rpm_x10 = RPM_NUMERATOR / {21'd0, period_clocks};
        end
    end

endmodule
