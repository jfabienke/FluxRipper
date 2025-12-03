//-----------------------------------------------------------------------------
// Flux Capture Diagnostic Module
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Based on CAPSImg DiskTrackInfo.timebuf structure
// Captures raw flux transitions with timestamps for analysis
// Supports KryoFlux-style flux dumps
//
// Target: Xilinx Spartan UltraScale+ (UC+)
// Updated: 2025-12-03 12:25
//-----------------------------------------------------------------------------

module flux_capture (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Clock frequency for timestamp scaling
    input  wire [31:0] clk_freq,        // Clock frequency in Hz

    // Flux input
    input  wire        flux_raw,        // Raw flux pulse from drive
    input  wire        index_pulse,     // Index pulse for track sync

    // Capture control
    input  wire        capture_start,   // Start capturing
    input  wire        capture_stop,    // Stop capturing
    input  wire        capture_arm,     // Arm for index-triggered capture
    input  wire [1:0]  capture_mode,    // 00=continuous, 01=one track, 10=one rev

    // Memory interface (for BRAM or external SRAM)
    output reg  [15:0] mem_addr,        // Memory address
    output reg  [31:0] mem_data,        // Memory data (timestamp)
    output reg         mem_write,       // Memory write enable
    input  wire        mem_ready,       // Memory ready

    // Status outputs
    output reg         capturing,       // Capture in progress
    output reg         capture_done,    // Capture complete
    output reg  [15:0] flux_count,      // Number of flux transitions captured
    output reg  [31:0] capture_time,    // Total capture time (clocks)
    output reg         overflow,        // Memory overflow
    output reg  [7:0]  avg_interval     // Average flux interval (for diagnostics)
);

    //-------------------------------------------------------------------------
    // Capture modes
    //-------------------------------------------------------------------------
    localparam MODE_CONTINUOUS = 2'b00;
    localparam MODE_ONE_TRACK  = 2'b01;
    localparam MODE_ONE_REV    = 2'b10;

    //-------------------------------------------------------------------------
    // Memory limits
    //-------------------------------------------------------------------------
    localparam [15:0] MEM_SIZE = 16'hFFFF;  // 64K entries max

    //-------------------------------------------------------------------------
    // Flux edge detection
    //-------------------------------------------------------------------------
    reg [2:0] flux_sync;
    wire flux_edge;

    always @(posedge clk) begin
        if (reset)
            flux_sync <= 3'b000;
        else
            flux_sync <= {flux_sync[1:0], flux_raw};
    end

    // Detect rising edge (flux transition)
    assign flux_edge = (flux_sync[2:1] == 2'b01);

    //-------------------------------------------------------------------------
    // Timestamp counter
    //-------------------------------------------------------------------------
    reg [31:0] timestamp;
    reg [31:0] last_flux_time;
    reg [31:0] interval;

    //-------------------------------------------------------------------------
    // Average interval calculator (for signal quality)
    //-------------------------------------------------------------------------
    reg [39:0] interval_sum;
    reg [15:0] interval_count;

    //-------------------------------------------------------------------------
    // State machine
    //-------------------------------------------------------------------------
    localparam S_IDLE     = 3'd0;
    localparam S_ARMED    = 3'd1;
    localparam S_CAPTURE  = 3'd2;
    localparam S_WRITE    = 3'd3;
    localparam S_DONE     = 3'd4;

    reg [2:0] state;
    reg       index_seen;
    reg       second_index;

    always @(posedge clk) begin
        if (reset) begin
            state          <= S_IDLE;
            capturing      <= 1'b0;
            capture_done   <= 1'b0;
            flux_count     <= 16'd0;
            capture_time   <= 32'd0;
            overflow       <= 1'b0;
            avg_interval   <= 8'd0;
            mem_addr       <= 16'd0;
            mem_data       <= 32'd0;
            mem_write      <= 1'b0;
            timestamp      <= 32'd0;
            last_flux_time <= 32'd0;
            interval       <= 32'd0;
            interval_sum   <= 40'd0;
            interval_count <= 16'd0;
            index_seen     <= 1'b0;
            second_index   <= 1'b0;
        end
        else if (enable) begin
            mem_write    <= 1'b0;
            capture_done <= 1'b0;

            // Increment timestamp when capturing
            if (state == S_CAPTURE || state == S_WRITE) begin
                timestamp    <= timestamp + 1'b1;
                capture_time <= capture_time + 1'b1;
            end

            case (state)
                S_IDLE: begin
                    if (capture_start) begin
                        // Direct start
                        state          <= S_CAPTURE;
                        capturing      <= 1'b1;
                        mem_addr       <= 16'd0;
                        flux_count     <= 16'd0;
                        timestamp      <= 32'd0;
                        capture_time   <= 32'd0;
                        last_flux_time <= 32'd0;
                        interval_sum   <= 40'd0;
                        interval_count <= 16'd0;
                        overflow       <= 1'b0;
                        index_seen     <= 1'b0;
                        second_index   <= 1'b0;
                    end
                    else if (capture_arm) begin
                        // Wait for index pulse
                        state          <= S_ARMED;
                        capturing      <= 1'b0;
                        mem_addr       <= 16'd0;
                        flux_count     <= 16'd0;
                        overflow       <= 1'b0;
                    end
                end

                S_ARMED: begin
                    if (index_pulse) begin
                        // Index seen, start capturing
                        state          <= S_CAPTURE;
                        capturing      <= 1'b1;
                        timestamp      <= 32'd0;
                        capture_time   <= 32'd0;
                        last_flux_time <= 32'd0;
                        interval_sum   <= 40'd0;
                        interval_count <= 16'd0;
                        index_seen     <= 1'b1;
                    end
                    else if (capture_stop) begin
                        state <= S_IDLE;
                    end
                end

                S_CAPTURE: begin
                    if (capture_stop) begin
                        state        <= S_DONE;
                        capturing    <= 1'b0;
                        capture_done <= 1'b1;
                    end
                    else if (flux_edge) begin
                        // Calculate interval since last flux
                        interval <= timestamp - last_flux_time;
                        last_flux_time <= timestamp;

                        // Prepare to write
                        state    <= S_WRITE;
                        mem_data <= timestamp - last_flux_time;  // Store interval
                    end
                    else if (index_pulse) begin
                        // Check for end conditions based on mode
                        if (index_seen) begin
                            second_index <= 1'b1;
                            if (capture_mode == MODE_ONE_REV ||
                                (capture_mode == MODE_ONE_TRACK && second_index)) begin
                                state        <= S_DONE;
                                capturing    <= 1'b0;
                                capture_done <= 1'b1;
                            end
                        end
                        else begin
                            index_seen <= 1'b1;
                        end

                        // Also record index as special marker (MSB set)
                        state    <= S_WRITE;
                        mem_data <= {1'b1, 31'd0};  // Index marker
                    end
                end

                S_WRITE: begin
                    if (mem_ready) begin
                        mem_write <= 1'b1;

                        // Update statistics
                        if (!mem_data[31]) begin  // Not an index marker
                            interval_sum   <= interval_sum + interval;
                            interval_count <= interval_count + 1'b1;
                        end

                        // Increment address
                        if (mem_addr < MEM_SIZE) begin
                            mem_addr   <= mem_addr + 1'b1;
                            flux_count <= flux_count + 1'b1;
                            state      <= S_CAPTURE;
                        end
                        else begin
                            // Memory overflow
                            overflow     <= 1'b1;
                            state        <= S_DONE;
                            capturing    <= 1'b0;
                            capture_done <= 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    // Calculate average interval
                    if (interval_count > 0) begin
                        avg_interval <= interval_sum[23:16];  // Scaled average
                    end

                    if (capture_start || capture_arm) begin
                        state <= S_IDLE;  // Allow restart
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Track Width Analyzer
// Analyzes track data to detect track width (40 vs 80 track drives)
//-----------------------------------------------------------------------------

module track_width_analyzer (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Track data
    input  wire        index_pulse,
    input  wire        flux_valid,
    input  wire [31:0] flux_interval,   // From flux_capture or DPLL

    // Step controller interface
    input  wire [7:0]  current_track,
    input  wire        step_complete,

    // Analysis outputs
    output reg         analysis_done,
    output reg         is_40_track,     // 1=40 track, 0=80 track
    output reg  [7:0]  max_track,       // Maximum track detected
    output reg  [15:0] signal_strength, // Signal strength indicator
    output reg         weak_signal      // Signal too weak
);

    //-------------------------------------------------------------------------
    // Signal strength thresholds
    //-------------------------------------------------------------------------
    localparam [15:0] SIGNAL_THRESHOLD = 16'd100;

    //-------------------------------------------------------------------------
    // Analysis state
    //-------------------------------------------------------------------------
    reg [31:0] flux_sum;
    reg [15:0] flux_count;
    reg [7:0]  test_track;
    reg        measuring;

    // Average flux interval indicates track type:
    // 40-track drives have wider tracks = stronger/more consistent signal
    // 80-track drives reading 40-track disk shows weaker signal on odd tracks

    always @(posedge clk) begin
        if (reset) begin
            analysis_done   <= 1'b0;
            is_40_track     <= 1'b0;
            max_track       <= 8'd79;
            signal_strength <= 16'd0;
            weak_signal     <= 1'b0;
            flux_sum        <= 32'd0;
            flux_count      <= 16'd0;
            test_track      <= 8'd0;
            measuring       <= 1'b0;
        end
        else if (enable) begin
            // Start measurement on new track
            if (step_complete) begin
                test_track <= current_track;
                flux_sum   <= 32'd0;
                flux_count <= 16'd0;
                measuring  <= 1'b1;
            end

            // Accumulate flux data
            if (measuring && flux_valid) begin
                flux_sum   <= flux_sum + flux_interval;
                flux_count <= flux_count + 1'b1;
            end

            // Complete measurement on index
            if (measuring && index_pulse) begin
                measuring <= 1'b0;

                // Calculate signal strength
                if (flux_count > 16'd0) begin
                    signal_strength <= flux_count;  // More transitions = stronger signal

                    // Check for weak signal (may indicate wrong track width)
                    if (flux_count < SIGNAL_THRESHOLD) begin
                        weak_signal <= 1'b1;

                        // If odd track is weak, probably 40-track disk
                        if (test_track[0])
                            is_40_track <= 1'b1;
                    end
                    else begin
                        weak_signal <= 1'b0;
                    end
                end

                // Update max track if we got good data
                if (flux_count > SIGNAL_THRESHOLD && test_track > max_track) begin
                    max_track <= test_track;
                end

                analysis_done <= 1'b1;
            end
            else begin
                analysis_done <= 1'b0;
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Signal Quality Monitor
// Monitors flux signal quality for diagnostics
//-----------------------------------------------------------------------------

module signal_quality_monitor (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // DPLL inputs
    input  wire        pll_locked,
    input  wire [7:0]  lock_quality,
    input  wire [1:0]  margin_zone,
    input  wire [15:0] phase_error,

    // Flux capture inputs
    input  wire        flux_valid,
    input  wire [31:0] flux_interval,

    // Index timing
    input  wire        index_pulse,
    input  wire [31:0] revolution_time,

    // Quality outputs
    output reg  [7:0]  overall_quality,  // 0=bad, 255=excellent
    output reg  [7:0]  stability,        // Signal stability
    output reg  [7:0]  consistency,      // Interval consistency
    output reg         degraded,         // Signal degraded warning
    output reg         critical          // Signal critically bad
);

    //-------------------------------------------------------------------------
    // Quality calculation
    //-------------------------------------------------------------------------
    reg [31:0] interval_variance;
    reg [31:0] last_interval;
    reg [31:0] variance_sum;
    reg [15:0] sample_count;

    // Running average of quality metrics
    reg [15:0] lock_sum;
    reg [15:0] margin_sum;
    reg [7:0]  measurement_count;

    always @(posedge clk) begin
        if (reset) begin
            overall_quality   <= 8'd128;
            stability         <= 8'd128;
            consistency       <= 8'd128;
            degraded          <= 1'b0;
            critical          <= 1'b0;
            interval_variance <= 32'd0;
            last_interval     <= 32'd0;
            variance_sum      <= 32'd0;
            sample_count      <= 16'd0;
            lock_sum          <= 16'd0;
            margin_sum        <= 16'd0;
            measurement_count <= 8'd0;
        end
        else if (enable) begin
            // Accumulate quality metrics
            if (pll_locked && flux_valid) begin
                // Track lock quality
                lock_sum <= lock_sum + {8'd0, lock_quality};

                // Track margin zone (0=center=good, 2=edge=bad)
                margin_sum <= margin_sum + {14'd0, margin_zone};

                // Track interval variance
                if (last_interval > 0) begin
                    if (flux_interval > last_interval)
                        variance_sum <= variance_sum + (flux_interval - last_interval);
                    else
                        variance_sum <= variance_sum + (last_interval - flux_interval);
                end
                last_interval <= flux_interval;

                sample_count      <= sample_count + 1'b1;
                measurement_count <= measurement_count + 1'b1;
            end

            // Calculate overall quality on index pulse
            if (index_pulse && measurement_count > 8'd0) begin
                // Stability based on PLL lock quality
                stability <= lock_sum[15:8];

                // Consistency based on interval variance
                if (variance_sum > 32'h00FF_FFFF)
                    consistency <= 8'd0;
                else
                    consistency <= 8'd255 - variance_sum[23:16];

                // Overall quality
                overall_quality <= (stability >> 1) + (consistency >> 1);

                // Warning thresholds
                degraded <= (overall_quality < 8'd100);
                critical <= (overall_quality < 8'd50);

                // Reset accumulators
                lock_sum          <= 16'd0;
                margin_sum        <= 16'd0;
                variance_sum      <= 32'd0;
                measurement_count <= 8'd0;
            end
        end
    end

endmodule
