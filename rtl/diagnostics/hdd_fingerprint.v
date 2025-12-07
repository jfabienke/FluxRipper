//-----------------------------------------------------------------------------
// HDD Fingerprint Generator - Drive Identification via Physics + Format
//
// Produces a unique fingerprint for each physical drive by combining:
//   - Mechanical envelope (cylinder range, actuator behavior)
//   - Format structure (SPT zoning, interleave, skew)
//   - Timing signatures (jitter profile, seek curve)
//   - Defect pattern (persistent error locations)
//
// The fingerprint enables:
//   - Drive recognition across sessions
//   - Confidence scoring for geometry discovery
//   - Detection of format vs native geometry mismatch
//
// Created: 2025-12-04 17:45
//-----------------------------------------------------------------------------

module hdd_fingerprint (
    input  wire        clk,              // 300 MHz HDD clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        fp_start,         // Start fingerprint collection
    input  wire        fp_abort,         // Abort fingerprint
    input  wire [1:0]  fp_mode,          // 0=quick, 1=standard, 2=thorough
    output reg         fp_done,          // Fingerprint complete
    output reg         fp_busy,          // Fingerprint in progress
    output reg  [3:0]  fp_stage,         // Current stage

    //-------------------------------------------------------------------------
    // Seek Controller Interface
    //-------------------------------------------------------------------------
    output reg         seek_start,
    output reg  [15:0] seek_cylinder,
    input  wire        seek_done,
    input  wire        seek_error,
    input  wire        track00,
    input  wire [15:0] current_cylinder,

    //-------------------------------------------------------------------------
    // Head Select Interface
    //-------------------------------------------------------------------------
    output reg  [3:0]  head_select,
    input  wire        head_selected,

    //-------------------------------------------------------------------------
    // Data Path Interface
    //-------------------------------------------------------------------------
    input  wire        flux_edge,        // Raw flux transitions
    input  wire        flux_valid,
    input  wire        sector_header_valid,
    input  wire [15:0] sector_cylinder,
    input  wire [3:0]  sector_head,
    input  wire [7:0]  sector_number,
    input  wire        sector_crc_ok,
    input  wire        sector_crc_error,
    input  wire        index_pulse,

    //-------------------------------------------------------------------------
    // Drive Status
    //-------------------------------------------------------------------------
    input  wire        drive_ready,
    input  wire        seek_complete_in,

    //-------------------------------------------------------------------------
    // Fingerprint Results (256-bit fingerprint vector)
    //-------------------------------------------------------------------------
    output reg [255:0] fingerprint,
    output reg  [7:0]  fp_confidence,    // Overall confidence 0-255
    output reg         fp_valid,

    // Detailed components (for debug/display)
    output reg  [15:0] mech_max_cyl,     // Mechanical cylinder limit
    output reg  [15:0] format_max_cyl,   // Formatted cylinder limit
    output reg  [3:0]  valid_heads,      // Number of readable heads
    output reg  [7:0]  spt_inner,        // SPT at inner zone
    output reg  [7:0]  spt_mid,          // SPT at mid zone
    output reg  [7:0]  spt_outer,        // SPT at outer zone
    output reg         is_zoned,         // 1 if zones detected
    output reg  [15:0] rpm_x10,          // RPM * 10
    output reg  [7:0]  rpm_jitter,       // RPM jitter 0-255
    output reg  [7:0]  jitter_inner,     // Bit jitter at inner cyl
    output reg  [7:0]  jitter_outer,     // Bit jitter at outer cyl
    output reg  [7:0]  seek_curve_type,  // 0=linear, 1=voice-coil, 2=stepper
    output reg  [15:0] defect_hash       // Hash of defect locations
);

    //-------------------------------------------------------------------------
    // Fingerprint Stages
    //-------------------------------------------------------------------------
    localparam [3:0]
        STAGE_IDLE          = 4'd0,
        STAGE_INIT          = 4'd1,
        STAGE_MECH_ENVELOPE = 4'd2,   // Find mechanical cylinder limit
        STAGE_HEAD_PROBE    = 4'd3,   // Count valid heads
        STAGE_ZONE_SCAN     = 4'd4,   // SPT at multiple radii
        STAGE_RPM_MEASURE   = 4'd5,   // RPM and jitter
        STAGE_SEEK_CURVE    = 4'd6,   // Seek time vs distance
        STAGE_JITTER_INNER  = 4'd7,   // Jitter at inner cylinder
        STAGE_JITTER_OUTER  = 4'd8,   // Jitter at outer cylinder
        STAGE_DEFECT_SCAN   = 4'd9,   // Optional: defect locations
        STAGE_COMPUTE       = 4'd10,  // Compute final fingerprint
        STAGE_COMPLETE      = 4'd11,
        STAGE_ERROR         = 4'd15;

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [2:0]
        STATE_IDLE          = 3'd0,
        STATE_SEEK          = 3'd1,
        STATE_WAIT_SEEK     = 3'd2,
        STATE_SELECT_HEAD   = 3'd3,
        STATE_MEASURE       = 3'd4,
        STATE_PROCESS       = 3'd5,
        STATE_NEXT          = 3'd6;

    reg [2:0] state;

    //-------------------------------------------------------------------------
    // Timing Constants
    //-------------------------------------------------------------------------
    localparam [23:0] ROTATION_TIMEOUT = 24'd6_000_000;   // 20ms @ 300 MHz
    localparam [23:0] SEEK_TIMEOUT     = 24'd30_000_000;  // 100ms
    localparam [23:0] JITTER_WINDOW    = 24'd6_000_000;   // 20ms sample

    //-------------------------------------------------------------------------
    // Counters and Timers
    //-------------------------------------------------------------------------
    reg [23:0] timeout_counter;
    reg [23:0] measure_counter;
    reg [7:0]  rotation_count;
    reg        index_prev;
    wire       index_edge;
    assign index_edge = index_pulse && !index_prev;

    //-------------------------------------------------------------------------
    // Mechanical Envelope Variables
    //-------------------------------------------------------------------------
    reg [15:0] mech_cyl_low;          // Known reachable
    reg [15:0] mech_cyl_high;         // Known unreachable or untested
    reg [15:0] mech_cyl_test;         // Current test cylinder

    //-------------------------------------------------------------------------
    // Head Probe Variables
    //-------------------------------------------------------------------------
    reg [3:0]  head_probe_idx;
    reg [15:0] head_valid_mask;
    reg [7:0]  head_sector_count;

    //-------------------------------------------------------------------------
    // Zone Scan Variables
    //-------------------------------------------------------------------------
    localparam NUM_ZONE_SAMPLES = 3;  // Inner, mid, outer
    reg [1:0]  zone_idx;
    reg [15:0] zone_cylinders [0:2];  // Cylinders to sample
    reg [7:0]  zone_spt [0:2];        // SPT at each zone
    reg [7:0]  sector_seen_count;
    reg [7:0]  max_sector_num;

    //-------------------------------------------------------------------------
    // RPM Measurement Variables
    //-------------------------------------------------------------------------
    reg [23:0] index_period;
    reg [23:0] index_periods [0:3];   // Store 4 periods
    reg [1:0]  index_period_idx;
    reg [23:0] index_period_min;
    reg [23:0] index_period_max;

    //-------------------------------------------------------------------------
    // Seek Curve Variables
    //-------------------------------------------------------------------------
    localparam NUM_SEEK_SAMPLES = 6;
    reg [2:0]  seek_sample_idx;
    reg [15:0] seek_distances [0:5];  // Step distances to test
    reg [23:0] seek_times [0:5];      // Measured times
    reg [23:0] seek_start_time;

    //-------------------------------------------------------------------------
    // Jitter Measurement Variables
    //-------------------------------------------------------------------------
    reg [15:0] pulse_width_counter;
    reg [31:0] pulse_width_sum;
    reg [31:0] pulse_width_sq_sum;    // For variance
    reg [15:0] pulse_sample_count;
    reg [15:0] jitter_result;

    //-------------------------------------------------------------------------
    // Defect Scan Variables
    //-------------------------------------------------------------------------
    reg [7:0]  defect_count;
    reg [15:0] defect_cyl [0:15];     // Store up to 16 defect locations
    reg [3:0]  defect_head [0:15];
    reg [7:0]  defect_sector [0:15];
    reg [3:0]  defect_idx;

    //-------------------------------------------------------------------------
    // Fingerprint Computation
    //-------------------------------------------------------------------------
    reg [31:0] hash_accum;

    //-------------------------------------------------------------------------
    // Initialization
    //-------------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            fp_stage <= STAGE_IDLE;
            fp_done <= 1'b0;
            fp_busy <= 1'b0;
            seek_start <= 1'b0;
            seek_cylinder <= 16'd0;
            head_select <= 4'd0;
            fingerprint <= 256'd0;
            fp_confidence <= 8'd0;
            fp_valid <= 1'b0;

            mech_max_cyl <= 16'd0;
            format_max_cyl <= 16'd0;
            valid_heads <= 4'd0;
            spt_inner <= 8'd0;
            spt_mid <= 8'd0;
            spt_outer <= 8'd0;
            is_zoned <= 1'b0;
            rpm_x10 <= 16'd0;
            rpm_jitter <= 8'd0;
            jitter_inner <= 8'd0;
            jitter_outer <= 8'd0;
            seek_curve_type <= 8'd0;
            defect_hash <= 16'd0;

            timeout_counter <= 24'd0;
            measure_counter <= 24'd0;
            rotation_count <= 8'd0;
            index_prev <= 1'b0;

            mech_cyl_low <= 16'd0;
            mech_cyl_high <= 16'd4096;
            mech_cyl_test <= 16'd0;

            head_probe_idx <= 4'd0;
            head_valid_mask <= 16'd0;
            head_sector_count <= 8'd0;

            zone_idx <= 2'd0;
            for (i = 0; i < 3; i = i + 1) begin
                zone_cylinders[i] <= 16'd0;
                zone_spt[i] <= 8'd0;
            end
            sector_seen_count <= 8'd0;
            max_sector_num <= 8'd0;

            index_period <= 24'd0;
            index_period_idx <= 2'd0;
            index_period_min <= 24'hFFFFFF;
            index_period_max <= 24'd0;

            seek_sample_idx <= 3'd0;
            for (i = 0; i < 6; i = i + 1) begin
                seek_distances[i] <= 16'd0;
                seek_times[i] <= 24'd0;
            end
            seek_start_time <= 24'd0;

            pulse_width_counter <= 16'd0;
            pulse_width_sum <= 32'd0;
            pulse_width_sq_sum <= 32'd0;
            pulse_sample_count <= 16'd0;
            jitter_result <= 16'd0;

            defect_count <= 8'd0;
            defect_idx <= 4'd0;
            hash_accum <= 32'd0;

        end else begin
            // Defaults
            fp_done <= 1'b0;
            seek_start <= 1'b0;
            index_prev <= index_pulse;

            // Timeout counter
            if (state != STATE_IDLE)
                timeout_counter <= timeout_counter + 1;

            // Pulse width measurement
            if (fp_stage == STAGE_JITTER_INNER || fp_stage == STAGE_JITTER_OUTER) begin
                pulse_width_counter <= pulse_width_counter + 1;
            end

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    fp_busy <= 1'b0;
                    if (fp_start && drive_ready) begin
                        fp_busy <= 1'b1;
                        fp_stage <= STAGE_INIT;
                        fp_valid <= 1'b0;
                        state <= STATE_SEEK;

                        // Initialize seek distances for curve profiling
                        seek_distances[0] <= 16'd10;    // Short
                        seek_distances[1] <= 16'd50;    // Medium-short
                        seek_distances[2] <= 16'd100;   // Medium
                        seek_distances[3] <= 16'd200;   // Medium-long
                        seek_distances[4] <= 16'd400;   // Long
                        seek_distances[5] <= 16'd0;     // Return to 0

                        // Initialize with seek to track 0
                        seek_cylinder <= 16'd0;
                        seek_start <= 1'b1;
                    end
                end

                //-------------------------------------------------------------
                STATE_SEEK: begin
                    seek_start <= 1'b0;
                    timeout_counter <= 24'd0;
                    state <= STATE_WAIT_SEEK;
                end

                //-------------------------------------------------------------
                STATE_WAIT_SEEK: begin
                    if (seek_done) begin
                        if (seek_error) begin
                            case (fp_stage)
                                STAGE_MECH_ENVELOPE: begin
                                    // This cylinder unreachable
                                    mech_cyl_high <= mech_cyl_test;
                                    state <= STATE_NEXT;
                                end
                                default: begin
                                    fp_stage <= STAGE_ERROR;
                                    state <= STATE_PROCESS;
                                end
                            endcase
                        end else begin
                            state <= STATE_SELECT_HEAD;
                        end
                    end else if (timeout_counter > SEEK_TIMEOUT) begin
                        // Seek timeout
                        case (fp_stage)
                            STAGE_MECH_ENVELOPE: begin
                                mech_cyl_high <= mech_cyl_test;
                                state <= STATE_NEXT;
                            end
                            default: begin
                                fp_stage <= STAGE_ERROR;
                                state <= STATE_PROCESS;
                            end
                        endcase
                    end
                end

                //-------------------------------------------------------------
                STATE_SELECT_HEAD: begin
                    case (fp_stage)
                        STAGE_INIT: begin
                            fp_stage <= STAGE_MECH_ENVELOPE;
                            mech_cyl_low <= 16'd0;
                            mech_cyl_high <= 16'd4096;
                            head_select <= 4'd0;
                        end
                        STAGE_HEAD_PROBE: begin
                            head_select <= head_probe_idx;
                            head_sector_count <= 8'd0;
                        end
                        default: begin
                            head_select <= 4'd0;
                        end
                    endcase

                    timeout_counter <= 24'd0;
                    rotation_count <= 8'd0;
                    measure_counter <= 24'd0;
                    state <= STATE_MEASURE;

                    // Reset measurement variables per stage
                    case (fp_stage)
                        STAGE_ZONE_SCAN: begin
                            sector_seen_count <= 8'd0;
                            max_sector_num <= 8'd0;
                        end
                        STAGE_RPM_MEASURE: begin
                            index_period <= 24'd0;
                            index_period_idx <= 2'd0;
                            index_period_min <= 24'hFFFFFF;
                            index_period_max <= 24'd0;
                        end
                        STAGE_JITTER_INNER, STAGE_JITTER_OUTER: begin
                            pulse_width_counter <= 16'd0;
                            pulse_width_sum <= 32'd0;
                            pulse_width_sq_sum <= 32'd0;
                            pulse_sample_count <= 16'd0;
                        end
                        STAGE_SEEK_CURVE: begin
                            seek_start_time <= 24'd0;
                        end
                    endcase
                end

                //-------------------------------------------------------------
                STATE_MEASURE: begin
                    measure_counter <= measure_counter + 1;

                    // Count rotations
                    if (index_edge) begin
                        rotation_count <= rotation_count + 1;

                        // RPM measurement
                        if (fp_stage == STAGE_RPM_MEASURE && rotation_count > 0) begin
                            index_periods[index_period_idx] <= measure_counter;
                            index_period_idx <= index_period_idx + 1;

                            if (measure_counter < index_period_min)
                                index_period_min <= measure_counter;
                            if (measure_counter > index_period_max)
                                index_period_max <= measure_counter;

                            measure_counter <= 24'd0;
                        end
                    end

                    // Sector header processing
                    if (sector_header_valid && sector_crc_ok) begin
                        case (fp_stage)
                            STAGE_MECH_ENVELOPE: begin
                                // Valid sector = cylinder reachable
                                if (sector_cylinder == mech_cyl_test) begin
                                    mech_cyl_low <= mech_cyl_test;
                                end
                            end
                            STAGE_HEAD_PROBE: begin
                                if (sector_head == head_probe_idx) begin
                                    head_sector_count <= head_sector_count + 1;
                                end
                            end
                            STAGE_ZONE_SCAN: begin
                                sector_seen_count <= sector_seen_count + 1;
                                if (sector_number > max_sector_num)
                                    max_sector_num <= sector_number;
                            end
                        endcase
                    end

                    // CRC error = potential defect
                    if (sector_header_valid && sector_crc_error) begin
                        if (fp_stage == STAGE_DEFECT_SCAN && defect_idx < 4'd15) begin
                            defect_cyl[defect_idx] <= sector_cylinder;
                            defect_head[defect_idx] <= sector_head;
                            defect_sector[defect_idx] <= sector_number;
                            defect_idx <= defect_idx + 1;
                            defect_count <= defect_count + 1;
                        end
                    end

                    // Jitter measurement
                    if ((fp_stage == STAGE_JITTER_INNER || fp_stage == STAGE_JITTER_OUTER) &&
                        flux_valid && flux_edge) begin
                        if (pulse_width_counter > 16'd10 && pulse_sample_count < 16'hFFFF) begin
                            pulse_width_sum <= pulse_width_sum + {16'd0, pulse_width_counter};
                            // Simplified variance: track sum of squares
                            pulse_width_sq_sum <= pulse_width_sq_sum +
                                                  ({16'd0, pulse_width_counter} * {16'd0, pulse_width_counter});
                            pulse_sample_count <= pulse_sample_count + 1;
                        end
                        pulse_width_counter <= 16'd0;
                    end

                    // Seek curve timing
                    if (fp_stage == STAGE_SEEK_CURVE) begin
                        seek_start_time <= seek_start_time + 1;
                        if (seek_complete_in) begin
                            seek_times[seek_sample_idx] <= seek_start_time;
                            state <= STATE_PROCESS;
                        end
                    end

                    // Completion conditions
                    case (fp_stage)
                        STAGE_MECH_ENVELOPE: begin
                            if (rotation_count >= 8'd2 || measure_counter > ROTATION_TIMEOUT)
                                state <= STATE_PROCESS;
                        end
                        STAGE_HEAD_PROBE: begin
                            if (rotation_count >= 8'd2 || measure_counter > ROTATION_TIMEOUT)
                                state <= STATE_PROCESS;
                        end
                        STAGE_ZONE_SCAN: begin
                            if (rotation_count >= 8'd2 || measure_counter > ROTATION_TIMEOUT)
                                state <= STATE_PROCESS;
                        end
                        STAGE_RPM_MEASURE: begin
                            if (rotation_count >= 8'd5 || measure_counter > ROTATION_TIMEOUT * 3)
                                state <= STATE_PROCESS;
                        end
                        STAGE_JITTER_INNER, STAGE_JITTER_OUTER: begin
                            if (measure_counter >= JITTER_WINDOW ||
                                pulse_sample_count >= 16'd8000)
                                state <= STATE_PROCESS;
                        end
                    endcase

                    // Abort check
                    if (fp_abort) begin
                        fp_stage <= STAGE_IDLE;
                        state <= STATE_IDLE;
                        fp_busy <= 1'b0;
                    end
                end

                //-------------------------------------------------------------
                STATE_PROCESS: begin
                    case (fp_stage)
                        STAGE_MECH_ENVELOPE: begin
                            // Check if we found readable sectors
                            if (sector_seen_count > 0 || head_sector_count > 0) begin
                                mech_cyl_low <= mech_cyl_test;
                            end else begin
                                mech_cyl_high <= mech_cyl_test;
                            end
                            state <= STATE_NEXT;
                        end

                        STAGE_HEAD_PROBE: begin
                            if (head_sector_count > 0) begin
                                head_valid_mask[head_probe_idx] <= 1'b1;
                            end

                            if (head_probe_idx < 4'd15) begin
                                head_probe_idx <= head_probe_idx + 1;
                                state <= STATE_SELECT_HEAD;
                            end else begin
                                // Count valid heads
                                valid_heads <= count_heads(head_valid_mask);
                                fp_stage <= STAGE_ZONE_SCAN;
                                zone_idx <= 2'd0;
                                // Set zone cylinders based on mechanical range
                                zone_cylinders[0] <= 16'd0;                          // Outer
                                zone_cylinders[1] <= mech_cyl_low >> 1;              // Mid
                                zone_cylinders[2] <= mech_cyl_low - (mech_cyl_low >> 3); // Inner
                                seek_cylinder <= 16'd0;
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end
                        end

                        STAGE_ZONE_SCAN: begin
                            // Store SPT for this zone
                            zone_spt[zone_idx] <= max_sector_num + 1;

                            if (zone_idx < 2'd2) begin
                                zone_idx <= zone_idx + 1;
                                seek_cylinder <= zone_cylinders[zone_idx + 1];
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end else begin
                                // Analyze zones
                                spt_outer <= zone_spt[0];
                                spt_mid <= zone_spt[1];
                                spt_inner <= zone_spt[2];
                                is_zoned <= (zone_spt[0] != zone_spt[1]) ||
                                           (zone_spt[1] != zone_spt[2]);

                                // Proceed to RPM measurement
                                fp_stage <= STAGE_RPM_MEASURE;
                                seek_cylinder <= mech_cyl_low >> 1;  // Mid cylinder
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end
                        end

                        STAGE_RPM_MEASURE: begin
                            // Calculate RPM from average period
                            // RPM = 60 * 300M / period
                            reg [31:0] avg_period;
                            avg_period = (index_periods[0] + index_periods[1] +
                                         index_periods[2] + index_periods[3]) >> 2;

                            if (avg_period > 0) begin
                                // RPM * 10 = 18,000,000,000 / avg_period
                                rpm_x10 <= 32'd18_000_000_000 / avg_period;

                                // Jitter = (max - min) * 256 / avg
                                if (index_period_max > index_period_min) begin
                                    rpm_jitter <= ((index_period_max - index_period_min) << 8) / avg_period;
                                end else begin
                                    rpm_jitter <= 8'd0;
                                end
                            end

                            // Proceed to seek curve
                            fp_stage <= STAGE_SEEK_CURVE;
                            seek_sample_idx <= 3'd0;
                            seek_cylinder <= seek_distances[0];
                            seek_start <= 1'b1;
                            state <= STATE_SEEK;
                        end

                        STAGE_SEEK_CURVE: begin
                            if (seek_sample_idx < 3'd5) begin
                                seek_sample_idx <= seek_sample_idx + 1;
                                seek_cylinder <= seek_distances[seek_sample_idx + 1];
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end else begin
                                // Analyze seek curve shape
                                // Voice coil: time ~ sqrt(distance)
                                // Stepper: time ~ distance
                                analyze_seek_curve();

                                // Proceed to jitter measurement
                                fp_stage <= STAGE_JITTER_OUTER;
                                seek_cylinder <= 16'd0;
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end
                        end

                        STAGE_JITTER_OUTER: begin
                            // Calculate jitter from variance
                            if (pulse_sample_count > 0) begin
                                reg [31:0] mean;
                                reg [31:0] variance;
                                mean = pulse_width_sum / {16'd0, pulse_sample_count};
                                variance = (pulse_width_sq_sum / {16'd0, pulse_sample_count}) -
                                          (mean * mean);
                                jitter_outer <= variance[15:8];  // Scaled
                            end

                            // Proceed to inner jitter
                            fp_stage <= STAGE_JITTER_INNER;
                            seek_cylinder <= mech_cyl_low - 16'd10;  // Near inner
                            seek_start <= 1'b1;
                            state <= STATE_SEEK;
                        end

                        STAGE_JITTER_INNER: begin
                            // Calculate jitter
                            if (pulse_sample_count > 0) begin
                                reg [31:0] mean;
                                reg [31:0] variance;
                                mean = pulse_width_sum / {16'd0, pulse_sample_count};
                                variance = (pulse_width_sq_sum / {16'd0, pulse_sample_count}) -
                                          (mean * mean);
                                jitter_inner <= variance[15:8];
                            end

                            // Skip defect scan in quick mode
                            if (fp_mode == 2'd0) begin
                                fp_stage <= STAGE_COMPUTE;
                                state <= STATE_PROCESS;
                            end else begin
                                fp_stage <= STAGE_DEFECT_SCAN;
                                defect_count <= 8'd0;
                                defect_idx <= 4'd0;
                                // Would scan multiple cylinders - simplified here
                                fp_stage <= STAGE_COMPUTE;
                                state <= STATE_PROCESS;
                            end
                        end

                        STAGE_COMPUTE: begin
                            // Compute final fingerprint hash
                            compute_fingerprint();
                            fp_stage <= STAGE_COMPLETE;
                            state <= STATE_PROCESS;
                        end

                        STAGE_COMPLETE: begin
                            fp_done <= 1'b1;
                            fp_valid <= 1'b1;
                            fp_busy <= 1'b0;
                            fp_stage <= STAGE_IDLE;
                            state <= STATE_IDLE;
                        end

                        STAGE_ERROR: begin
                            fp_done <= 1'b1;
                            fp_valid <= 1'b0;
                            fp_confidence <= 8'd0;
                            fp_busy <= 1'b0;
                            fp_stage <= STAGE_IDLE;
                            state <= STATE_IDLE;
                        end

                        default: state <= STATE_IDLE;
                    endcase
                end

                //-------------------------------------------------------------
                STATE_NEXT: begin
                    case (fp_stage)
                        STAGE_MECH_ENVELOPE: begin
                            // Binary search for mechanical limit
                            if (mech_cyl_high - mech_cyl_low <= 16'd1) begin
                                // Converged
                                mech_max_cyl <= mech_cyl_low;
                                format_max_cyl <= mech_cyl_low;  // Will be refined

                                // Move to head probe
                                fp_stage <= STAGE_HEAD_PROBE;
                                head_probe_idx <= 4'd0;
                                head_valid_mask <= 16'd0;
                                seek_cylinder <= 16'd0;
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end else begin
                                // Continue binary search
                                mech_cyl_test <= (mech_cyl_low + mech_cyl_high) >> 1;
                                seek_cylinder <= (mech_cyl_low + mech_cyl_high) >> 1;
                                seek_start <= 1'b1;
                                state <= STATE_SEEK;
                            end
                        end

                        default: state <= STATE_IDLE;
                    endcase
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Count Valid Heads
    //-------------------------------------------------------------------------
    function [3:0] count_heads;
        input [15:0] mask;
        integer j;
        reg [3:0] cnt;
        begin
            cnt = 4'd0;
            for (j = 0; j < 16; j = j + 1) begin
                if (mask[j]) cnt = cnt + 1;
            end
            count_heads = cnt;
        end
    endfunction

    //-------------------------------------------------------------------------
    // Analyze Seek Curve Shape
    //-------------------------------------------------------------------------
    task analyze_seek_curve;
        reg [31:0] linear_error;
        reg [31:0] sqrt_error;
        integer k;
        begin
            // Compare seek times to linear vs sqrt model
            // Simplified: check if time scales with distance or sqrt(distance)

            // For now, classify based on short vs long seek ratio
            if (seek_times[0] > 0 && seek_times[4] > 0) begin
                // Stepper: time ~ distance, ratio should be ~40x
                // Voice coil: time ~ sqrt(distance), ratio should be ~6x
                if ((seek_times[4] / seek_times[0]) > 24'd20) begin
                    seek_curve_type <= 8'd2;  // Stepper
                end else begin
                    seek_curve_type <= 8'd1;  // Voice coil
                end
            end else begin
                seek_curve_type <= 8'd0;  // Unknown
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Compute Fingerprint
    //-------------------------------------------------------------------------
    task compute_fingerprint;
        begin
            // Build 256-bit fingerprint from collected data
            // Structure:
            // [255:240] = RPM * 10 (16 bits)
            // [239:232] = RPM jitter (8 bits)
            // [231:216] = Mechanical max cylinder (16 bits)
            // [215:212] = Valid heads (4 bits)
            // [211:204] = SPT outer (8 bits)
            // [203:196] = SPT mid (8 bits)
            // [195:188] = SPT inner (8 bits)
            // [187:180] = Jitter outer (8 bits)
            // [179:172] = Jitter inner (8 bits)
            // [171:164] = Seek curve type (8 bits)
            // [163:148] = Seek time short (16 bits)
            // [147:132] = Seek time long (16 bits)
            // [131:116] = Defect hash (16 bits)
            // [115:112] = Zone flag + reserved (4 bits)
            // [111:0]   = Reserved / future use

            fingerprint[255:240] <= rpm_x10;
            fingerprint[239:232] <= rpm_jitter;
            fingerprint[231:216] <= mech_max_cyl;
            fingerprint[215:212] <= valid_heads;
            fingerprint[211:204] <= spt_outer;
            fingerprint[203:196] <= spt_mid;
            fingerprint[195:188] <= spt_inner;
            fingerprint[187:180] <= jitter_outer;
            fingerprint[179:172] <= jitter_inner;
            fingerprint[171:164] <= seek_curve_type;
            fingerprint[163:148] <= seek_times[0][15:0];  // Short seek
            fingerprint[147:132] <= seek_times[4][15:0];  // Long seek
            fingerprint[131:116] <= compute_defect_hash();
            fingerprint[115:112] <= {3'd0, is_zoned};
            fingerprint[111:0]   <= 112'd0;

            // Compute confidence based on data quality
            // High confidence if: RPM stable, zones detected, good jitter
            begin
                reg [7:0] conf;
                conf = 8'd128;  // Base confidence

                if (rpm_jitter < 8'd10) conf = conf + 8'd32;
                else if (rpm_jitter > 8'd50) conf = conf - 8'd32;

                if (valid_heads > 4'd0 && valid_heads <= 4'd8) conf = conf + 8'd16;

                if (spt_outer > 8'd0) conf = conf + 8'd16;

                if (mech_max_cyl > 16'd100) conf = conf + 8'd32;

                if (seek_curve_type != 8'd0) conf = conf + 8'd16;

                fp_confidence <= conf;
            end

            defect_hash <= compute_defect_hash();
        end
    endtask

    //-------------------------------------------------------------------------
    // Compute Defect Location Hash
    //-------------------------------------------------------------------------
    function [15:0] compute_defect_hash;
        reg [31:0] hash;
        integer m;
        begin
            hash = 32'h5A5A5A5A;  // Seed
            for (m = 0; m < 16; m = m + 1) begin
                if (m < defect_count) begin
                    // Simple XOR hash
                    hash = hash ^ {defect_cyl[m], defect_head[m], defect_sector[m], 4'd0};
                    hash = {hash[30:0], hash[31]} ^ hash;  // Rotate and mix
                end
            end
            compute_defect_hash = hash[15:0];
        end
    endfunction

endmodule
