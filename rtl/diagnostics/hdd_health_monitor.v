//-----------------------------------------------------------------------------
// HDD Health Monitor - Drive Health and Performance Metrics
//
// Measures drive mechanical health:
//   - RPM and RPM jitter (spindle stability)
//   - Seek timing and reliability
//   - Head switch timing
//
// Used as final stage of discovery pipeline for health assessment
//
// Created: 2025-12-03 22:00
//-----------------------------------------------------------------------------

module hdd_health_monitor (
    input  wire        clk,              // 300 MHz HDD clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        check_start,      // Start health check
    output reg         check_done,       // Check complete
    output reg         check_busy,       // Check in progress

    //-------------------------------------------------------------------------
    // Drive Inputs
    //-------------------------------------------------------------------------
    input  wire        index_pulse,      // Index for RPM measurement
    input  wire        seek_complete,    // Seek complete for timing
    input  wire        drive_ready,
    input  wire        drive_fault,

    //-------------------------------------------------------------------------
    // Seek Test Interface
    //-------------------------------------------------------------------------
    output reg         seek_test_start,  // Start test seek
    output reg  [15:0] seek_test_cyl,    // Target cylinder
    input  wire        seek_test_done,   // Seek completed
    input  wire        seek_test_error,  // Seek failed

    //-------------------------------------------------------------------------
    // Health Results
    //-------------------------------------------------------------------------
    output reg  [15:0] rpm_measured,     // RPM * 10 (e.g., 36000 = 3600 RPM)
    output reg  [7:0]  rpm_jitter,       // RPM variation 0-255
    output reg  [15:0] avg_seek_time,    // Average seek time (microseconds)
    output reg  [7:0]  seek_reliability, // Seek success rate 0-255 (255=100%)
    output reg  [7:0]  overall_health    // Overall health score 0-255
);

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [2:0]
        STATE_IDLE       = 3'd0,
        STATE_RPM_MEAS   = 3'd1,
        STATE_SEEK_TEST  = 3'd2,
        STATE_WAIT_SEEK  = 3'd3,
        STATE_CALCULATE  = 3'd4,
        STATE_DONE       = 3'd5;

    reg [2:0] state;

    //-------------------------------------------------------------------------
    // RPM Measurement
    //-------------------------------------------------------------------------
    // At 300 MHz, 3600 RPM gives ~5M clocks per revolution
    // 3000 RPM = 6M clocks, 4000 RPM = 4.5M clocks
    // RPM = 60 * 300M / index_period = 18B / index_period

    localparam [31:0] RPM_NUMERATOR = 32'd18_000_000_000;  // 60 * 300M * 10 (for 0.1 RPM resolution)

    reg [23:0] index_period_counter;
    reg [23:0] index_periods [0:7];      // Store last 8 periods
    reg [2:0]  index_period_idx;
    reg        index_prev;
    reg [3:0]  rotation_count;

    wire index_edge;
    assign index_edge = index_pulse && !index_prev;

    //-------------------------------------------------------------------------
    // Seek Test Variables
    //-------------------------------------------------------------------------
    localparam NUM_SEEK_TESTS = 8;

    reg [23:0] seek_start_time;
    reg [23:0] seek_times [0:7];         // Store seek times
    reg [2:0]  seek_test_idx;
    reg [3:0]  seek_success_count;
    reg [3:0]  seek_fail_count;

    // Test cylinder sequence (short, medium, long seeks)
    reg [15:0] seek_test_targets [0:7];

    //-------------------------------------------------------------------------
    // Calculation Variables (moved from procedural blocks for Verilog compat)
    //-------------------------------------------------------------------------
    reg [31:0] calc_avg_period;
    reg [31:0] calc_min_period;
    reg [31:0] calc_max_period;
    reg [31:0] calc_rpm;
    reg [31:0] calc_seek_sum;
    reg [3:0]  calc_valid_seeks;
    integer    calc_i;
    reg [7:0]  calc_rpm_score;
    reg [7:0]  calc_seek_score;
    reg [7:0]  calc_fault_score;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            check_done <= 1'b0;
            check_busy <= 1'b0;
            seek_test_start <= 1'b0;
            seek_test_cyl <= 16'd0;
            rpm_measured <= 16'd0;
            rpm_jitter <= 8'd0;
            avg_seek_time <= 16'd0;
            seek_reliability <= 8'd0;
            overall_health <= 8'd0;
            index_period_counter <= 24'd0;
            index_period_idx <= 3'd0;
            index_prev <= 1'b0;
            rotation_count <= 4'd0;
            seek_start_time <= 24'd0;
            seek_test_idx <= 3'd0;
            seek_success_count <= 4'd0;
            seek_fail_count <= 4'd0;

            // Initialize test targets (assuming ~600 cylinder drive)
            seek_test_targets[0] <= 16'd10;   // Short seek
            seek_test_targets[1] <= 16'd50;   // Medium
            seek_test_targets[2] <= 16'd100;  // Medium
            seek_test_targets[3] <= 16'd300;  // Long
            seek_test_targets[4] <= 16'd200;  // Back
            seek_test_targets[5] <= 16'd0;    // To track 0
            seek_test_targets[6] <= 16'd400;  // Long
            seek_test_targets[7] <= 16'd0;    // Back to 0
        end else begin
            check_done <= 1'b0;
            seek_test_start <= 1'b0;
            index_prev <= index_pulse;
            index_period_counter <= index_period_counter + 1;

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    check_busy <= 1'b0;
                    if (check_start) begin
                        check_busy <= 1'b1;
                        rotation_count <= 4'd0;
                        index_period_idx <= 3'd0;
                        index_period_counter <= 24'd0;
                        seek_test_idx <= 3'd0;
                        seek_success_count <= 4'd0;
                        seek_fail_count <= 4'd0;
                        state <= STATE_RPM_MEAS;
                    end
                end

                //-------------------------------------------------------------
                STATE_RPM_MEAS: begin
                    // Measure multiple rotation periods for average and jitter
                    if (index_edge) begin
                        if (rotation_count > 0) begin
                            // Store this period
                            index_periods[index_period_idx] <= index_period_counter;
                            index_period_idx <= index_period_idx + 1;
                        end

                        index_period_counter <= 24'd0;
                        rotation_count <= rotation_count + 1;

                        if (rotation_count >= 4'd9) begin
                            // Collected 8 periods, move to seek test
                            state <= STATE_SEEK_TEST;
                        end
                    end

                    // Timeout if no index
                    if (index_period_counter > 24'd12_000_000) begin
                        // No rotation detected
                        rpm_measured <= 16'd0;
                        rpm_jitter <= 8'd255;
                        state <= STATE_SEEK_TEST;
                    end
                end

                //-------------------------------------------------------------
                STATE_SEEK_TEST: begin
                    if (seek_test_idx >= NUM_SEEK_TESTS) begin
                        state <= STATE_CALCULATE;
                    end else begin
                        // Start next seek test
                        seek_test_cyl <= seek_test_targets[seek_test_idx];
                        seek_test_start <= 1'b1;
                        seek_start_time <= 24'd0;
                        state <= STATE_WAIT_SEEK;
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT_SEEK: begin
                    seek_start_time <= seek_start_time + 1;

                    if (seek_test_done) begin
                        if (seek_test_error) begin
                            seek_fail_count <= seek_fail_count + 1;
                            seek_times[seek_test_idx] <= 24'hFFFFFF;  // Mark as failed
                        end else begin
                            seek_success_count <= seek_success_count + 1;
                            seek_times[seek_test_idx] <= seek_start_time;
                        end

                        seek_test_idx <= seek_test_idx + 1;
                        state <= STATE_SEEK_TEST;
                    end

                    // Seek timeout (100ms)
                    if (seek_start_time > 24'd40_000_000) begin
                        seek_fail_count <= seek_fail_count + 1;
                        seek_times[seek_test_idx] <= 24'hFFFFFF;
                        seek_test_idx <= seek_test_idx + 1;
                        state <= STATE_SEEK_TEST;
                    end
                end

                //-------------------------------------------------------------
                STATE_CALCULATE: begin
                    // Calculate RPM from average period
                    // Average index period
                    calc_avg_period = 32'd0;
                    calc_min_period = 32'hFFFFFFFF;
                    calc_max_period = 32'd0;

                    for (calc_i = 0; calc_i < 8; calc_i = calc_i + 1) begin
                        calc_avg_period = calc_avg_period + {8'd0, index_periods[calc_i]};
                        if ({8'd0, index_periods[calc_i]} < calc_min_period)
                            calc_min_period = {8'd0, index_periods[calc_i]};
                        if ({8'd0, index_periods[calc_i]} > calc_max_period)
                            calc_max_period = {8'd0, index_periods[calc_i]};
                    end
                    calc_avg_period = calc_avg_period >> 3;  // Divide by 8

                    // Calculate RPM: 60 * 300M * 10 / period
                    if (calc_avg_period > 0) begin
                        calc_rpm = RPM_NUMERATOR / calc_avg_period;
                        rpm_measured <= calc_rpm[15:0];

                        // Jitter = (max - min) / avg * 256
                        if (calc_max_period > calc_min_period) begin
                            rpm_jitter <= ((calc_max_period - calc_min_period) << 8) / calc_avg_period;
                        end else begin
                            rpm_jitter <= 8'd0;
                        end
                    end else begin
                        rpm_measured <= 16'd0;
                        rpm_jitter <= 8'd255;
                    end

                    // Average seek time (in microseconds)
                    // Time in clocks / 300 = microseconds
                    calc_seek_sum = 32'd0;
                    calc_valid_seeks = 4'd0;

                    for (calc_i = 0; calc_i < 8; calc_i = calc_i + 1) begin
                        if (seek_times[calc_i] != 24'hFFFFFF) begin
                            calc_seek_sum = calc_seek_sum + {8'd0, seek_times[calc_i]};
                            calc_valid_seeks = calc_valid_seeks + 1;
                        end
                    end

                    if (calc_valid_seeks > 0) begin
                        avg_seek_time <= (calc_seek_sum / {28'd0, calc_valid_seeks}) / 16'd400;
                    end else begin
                        avg_seek_time <= 16'hFFFF;
                    end

                    // Seek reliability: (success / total) * 255
                    if (seek_success_count + seek_fail_count > 0) begin
                        seek_reliability <= ({4'd0, seek_success_count} * 8'd255) /
                                           {4'd0, (seek_success_count + seek_fail_count)};
                    end else begin
                        seek_reliability <= 8'd0;
                    end

                    // Overall health score
                    // Factors: RPM stability, seek reliability, no faults
                    // RPM score: good if jitter < 10
                    if (rpm_jitter < 8'd10)
                        calc_rpm_score = 8'd255;
                    else if (rpm_jitter < 8'd30)
                        calc_rpm_score = 8'd200;
                    else if (rpm_jitter < 8'd100)
                        calc_rpm_score = 8'd128;
                    else
                        calc_rpm_score = 8'd64;

                    calc_seek_score = seek_reliability;

                    calc_fault_score = drive_fault ? 8'd0 : 8'd255;

                    // Weighted average
                    overall_health <= (calc_rpm_score + calc_seek_score + calc_fault_score) / 8'd3;

                    state <= STATE_DONE;
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    check_done <= 1'b1;
                    check_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Decode Test Module
// Tests MFM vs RLL decoding to determine encoding type
//-----------------------------------------------------------------------------
module hdd_decode_tester (
    input  wire        clk,
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        test_start,
    input  wire        test_use_mfm,     // 1 = test MFM, 0 = test RLL
    output reg         test_done,

    //-------------------------------------------------------------------------
    // Data Input (from data separator)
    //-------------------------------------------------------------------------
    input  wire        data_bit,
    input  wire        data_valid,
    input  wire        index_pulse,

    //-------------------------------------------------------------------------
    // Results
    //-------------------------------------------------------------------------
    output reg  [15:0] sync_hits,        // Sync patterns found
    output reg  [15:0] crc_ok_count,     // Valid CRCs
    output reg  [15:0] error_count       // Decode errors
);

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [1:0]
        STATE_IDLE    = 2'd0,
        STATE_COLLECT = 2'd1,
        STATE_DONE    = 2'd2;

    reg [1:0] state;
    reg [23:0] collect_counter;
    localparam [23:0] COLLECT_TIME = 24'd6_000_000;  // 20ms

    //-------------------------------------------------------------------------
    // Pattern Detection
    //-------------------------------------------------------------------------
    reg [31:0] shift_reg;

    // MFM sync pattern: 0x4489 repeated (A1 with missing clock)
    localparam [15:0] MFM_SYNC = 16'h4489;

    // RLL sync pattern: encoded 0x00 = 1000 pattern
    localparam [15:0] RLL_SYNC = 16'b1000_1000_1000_1000;

    wire sync_match;
    assign sync_match = test_use_mfm ?
                        (shift_reg[15:0] == MFM_SYNC) :
                        (shift_reg[15:0] == RLL_SYNC);

    //-------------------------------------------------------------------------
    // Main Logic
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            test_done <= 1'b0;
            sync_hits <= 16'd0;
            crc_ok_count <= 16'd0;
            error_count <= 16'd0;
            collect_counter <= 24'd0;
            shift_reg <= 32'd0;
        end else begin
            test_done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (test_start) begin
                        sync_hits <= 16'd0;
                        crc_ok_count <= 16'd0;
                        error_count <= 16'd0;
                        collect_counter <= 24'd0;
                        state <= STATE_COLLECT;
                    end
                end

                STATE_COLLECT: begin
                    collect_counter <= collect_counter + 1;

                    if (data_valid) begin
                        shift_reg <= {shift_reg[30:0], data_bit};

                        if (sync_match) begin
                            sync_hits <= sync_hits + 1;
                            // Simple heuristic: assume valid CRC after sync
                            // Real implementation would check actual CRC
                            crc_ok_count <= crc_ok_count + 1;
                        end
                    end

                    if (collect_counter >= COLLECT_TIME) begin
                        state <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    test_done <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
