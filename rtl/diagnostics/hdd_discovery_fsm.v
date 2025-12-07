//-----------------------------------------------------------------------------
// HDD Discovery FSM - Master Orchestrator
//
// Coordinates the complete HDD discovery pipeline:
//   A1: PHY Probe      - Single-ended vs differential
//   A2: Rate Detection - Find data rate (5/7.5/10/15 Mbps)
//   A3: Decode Test    - Try MFM, try RLL, compare results
//   A4: Classification - Determine drive type (MFM/RLL/ESDI)
//   A5: ESDI Config    - Query ESDI drive for geometry (if ESDI detected)
//   B1: Control Check  - Verify READY, INDEX, TRACK00, SEEK_COMPLETE
//   B2: Head Scan      - Count valid heads
//   B3: SPT Scan       - Sectors per track
//   B4: Cylinder Scan  - Find max cylinder
//   B5: Interleave     - Measure sector ordering
//   B6: Skew           - Track-to-track timing offset
//   B7: Health         - RPM jitter, seek timing
//
// Created: 2025-12-03 22:00
// Updated: 2025-12-04 17:55 - Added ESDI configuration query stage
//-----------------------------------------------------------------------------

module hdd_discovery_fsm (
    input  wire        clk,              // 300 MHz HDD clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface (from CPU/AXI)
    //-------------------------------------------------------------------------
    input  wire        discover_start,   // Start discovery
    input  wire        discover_abort,   // Abort discovery
    output reg         discover_done,    // Discovery complete
    output reg         discover_busy,    // Discovery in progress
    output reg  [3:0]  discover_stage,   // Current stage (for status)
    output reg  [7:0]  discover_progress,// Progress 0-255

    //-------------------------------------------------------------------------
    // PHY Probe Interface
    //-------------------------------------------------------------------------
    output reg         phy_probe_start,
    input  wire        phy_probe_done,
    input  wire        phy_probe_busy,
    input  wire        phy_is_differential,
    input  wire [15:0] phy_edge_count,
    input  wire [7:0]  phy_signal_quality,
    input  wire        phy_signal_present,

    //-------------------------------------------------------------------------
    // Rate Detector Interface
    //-------------------------------------------------------------------------
    output reg         rate_detect_start,
    input  wire        rate_detect_done,
    input  wire        rate_detect_busy,
    input  wire [2:0]  detected_rate,
    input  wire [7:0]  rate_confidence,
    input  wire        rate_valid,

    //-------------------------------------------------------------------------
    // Geometry Scanner Interface
    //-------------------------------------------------------------------------
    output reg         geometry_scan_start,
    input  wire        geometry_scan_done,
    input  wire        geometry_scan_busy,
    input  wire [3:0]  geometry_stage,
    input  wire [3:0]  num_heads,
    input  wire [15:0] num_cylinders,
    input  wire [7:0]  sectors_per_track,
    input  wire [7:0]  interleave,
    input  wire [7:0]  track_skew,
    input  wire        geometry_valid,

    //-------------------------------------------------------------------------
    // Decode Test Interface (MFM vs RLL)
    //-------------------------------------------------------------------------
    output reg         decode_test_start,
    output reg         decode_use_mfm,    // 1 = test MFM, 0 = test RLL
    input  wire        decode_test_done,
    input  wire [15:0] decode_sync_hits,  // Sync patterns found
    input  wire [15:0] decode_crc_ok,     // Valid CRCs
    input  wire [15:0] decode_errors,     // Decode errors

    //-------------------------------------------------------------------------
    // Health Monitor Interface
    //-------------------------------------------------------------------------
    output reg         health_check_start,
    input  wire        health_check_done,
    input  wire [15:0] rpm_measured,      // RPM * 10 (e.g., 36000 = 3600 RPM)
    input  wire [7:0]  rpm_jitter,        // RPM variation 0-255
    input  wire [15:0] avg_seek_time,     // Average seek time (us)
    input  wire [7:0]  seek_reliability,  // Seek success rate 0-255

    //-------------------------------------------------------------------------
    // ESDI Command Interface (for GET_DEV_CONFIG)
    //-------------------------------------------------------------------------
    output reg         esdi_cmd_start,    // Start ESDI command
    output reg  [7:0]  esdi_cmd_opcode,   // Command opcode
    input  wire        esdi_cmd_done,     // Command complete
    input  wire        esdi_cmd_error,    // Command failed
    input  wire        esdi_config_valid, // Configuration data valid
    input  wire [15:0] esdi_cfg_cylinders,// ESDI-reported cylinders
    input  wire [7:0]  esdi_cfg_heads,    // ESDI-reported heads
    input  wire [7:0]  esdi_cfg_spt,      // ESDI-reported sectors per track

    //-------------------------------------------------------------------------
    // Drive Status Inputs
    //-------------------------------------------------------------------------
    input  wire        drive_ready,
    input  wire        drive_fault,
    input  wire        index_pulse,
    input  wire        track00,
    input  wire        seek_complete,

    //-------------------------------------------------------------------------
    // Discovery Results (Output)
    //-------------------------------------------------------------------------
    output reg  [2:0]  result_encoding,   // 0=unknown, 1=MFM, 2=RLL, 3=ESDI
    output reg         result_differential,
    output reg  [2:0]  result_rate,
    output reg  [3:0]  result_heads,
    output reg  [15:0] result_cylinders,
    output reg  [7:0]  result_spt,
    output reg  [7:0]  result_interleave,
    output reg  [7:0]  result_skew,
    output reg  [7:0]  result_quality,    // Overall quality score
    output reg         result_valid,
    output wire        result_esdi_config_used, // 1 if geometry from ESDI GET_DEV_CONFIG

    // Packed profile register (for direct register read)
    output wire [63:0] result_profile
);

    // ESDI config used flag - wire to internal reg
    assign result_esdi_config_used = esdi_config_success;

    //-------------------------------------------------------------------------
    // Discovery Stages
    //-------------------------------------------------------------------------
    localparam [3:0]
        STAGE_IDLE       = 4'd0,
        STAGE_PHY_PROBE  = 4'd1,   // A1
        STAGE_RATE_DET   = 4'd2,   // A2
        STAGE_DECODE_MFM = 4'd3,   // A3a
        STAGE_DECODE_RLL = 4'd4,   // A3b
        STAGE_CLASSIFY   = 4'd5,   // A4
        STAGE_ESDI_CFG   = 4'd6,   // A5 - ESDI GET_DEV_CONFIG query
        STAGE_CTRL_CHECK = 4'd7,   // B1
        STAGE_GEOMETRY   = 4'd8,   // B2-B6
        STAGE_HEALTH     = 4'd9,   // B7
        STAGE_COMPLETE   = 4'd10,
        STAGE_ERROR      = 4'd11;

    // ESDI command opcode
    localparam [7:0] CMD_GET_DEV_CONFIG = 8'h09;

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam [2:0]
        STATE_IDLE      = 3'd0,
        STATE_START     = 3'd1,
        STATE_WAIT      = 3'd2,
        STATE_PROCESS   = 3'd3,
        STATE_NEXT      = 3'd4,
        STATE_DONE      = 3'd5;

    reg [2:0] state;

    //-------------------------------------------------------------------------
    // Stage Tracking
    //-------------------------------------------------------------------------
    reg [3:0] current_stage;
    reg [23:0] timeout_counter;
    localparam [23:0] STAGE_TIMEOUT = 24.d30_000_000;  // 100ms @ 300 MHz

    //-------------------------------------------------------------------------
    // Decode Test Results Storage
    //-------------------------------------------------------------------------
    reg [15:0] mfm_sync_hits;
    reg [15:0] mfm_crc_ok;
    reg [15:0] mfm_errors;
    reg [15:0] rll_sync_hits;
    reg [15:0] rll_crc_ok;
    reg [15:0] rll_errors;

    //-------------------------------------------------------------------------
    // Control Check Results
    //-------------------------------------------------------------------------
    reg        ctrl_ready_ok;
    reg        ctrl_index_ok;
    reg        ctrl_track00_ok;
    reg        ctrl_seek_ok;
    reg [7:0]  index_count;
    reg        index_prev;

    //-------------------------------------------------------------------------
    // ESDI Configuration Results
    //-------------------------------------------------------------------------
    reg        esdi_config_queried;     // Did we attempt ESDI config query?
    reg        esdi_config_success;     // Did ESDI config query succeed?
    reg [15:0] esdi_geometry_cylinders; // Cylinders from ESDI
    reg [7:0]  esdi_geometry_heads;     // Heads from ESDI
    reg [7:0]  esdi_geometry_spt;       // SPT from ESDI

    //-------------------------------------------------------------------------
    // Profile Encoder
    //-------------------------------------------------------------------------
    hdd_geometry_profile u_profile (
        .num_heads(result_heads),
        .num_cylinders(result_cylinders),
        .sectors_per_track(result_spt),
        .detected_rate(result_rate),
        .is_differential(result_differential),
        .interleave(result_interleave),
        .profile(result_profile)
    );

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            current_stage <= STAGE_IDLE;
            discover_done <= 1'b0;
            discover_busy <= 1'b0;
            discover_stage <= 4'd0;
            discover_progress <= 8'd0;
            phy_probe_start <= 1'b0;
            rate_detect_start <= 1'b0;
            geometry_scan_start <= 1'b0;
            decode_test_start <= 1'b0;
            decode_use_mfm <= 1'b0;
            health_check_start <= 1'b0;
            esdi_cmd_start <= 1'b0;
            esdi_cmd_opcode <= 8'd0;
            result_encoding <= 3'd0;
            result_differential <= 1'b0;
            result_rate <= 3'd0;
            result_heads <= 4'd0;
            result_cylinders <= 16'd0;
            result_spt <= 8'd0;
            result_interleave <= 8'd1;
            result_skew <= 8'd0;
            result_quality <= 8'd0;
            result_valid <= 1'b0;
            timeout_counter <= 24'd0;
            mfm_sync_hits <= 16'd0;
            mfm_crc_ok <= 16'd0;
            mfm_errors <= 16'd0;
            rll_sync_hits <= 16'd0;
            rll_crc_ok <= 16'd0;
            rll_errors <= 16'd0;
            ctrl_ready_ok <= 1'b0;
            ctrl_index_ok <= 1'b0;
            ctrl_track00_ok <= 1'b0;
            ctrl_seek_ok <= 1'b0;
            index_count <= 8'd0;
            index_prev <= 1'b0;
            esdi_config_queried <= 1'b0;
            esdi_config_success <= 1'b0;
            esdi_geometry_cylinders <= 16'd0;
            esdi_geometry_heads <= 8'd0;
            esdi_geometry_spt <= 8'd0;
        end else begin
            // Default pulse outputs
            discover_done <= 1'b0;
            phy_probe_start <= 1'b0;
            rate_detect_start <= 1'b0;
            geometry_scan_start <= 1'b0;
            decode_test_start <= 1'b0;
            health_check_start <= 1'b0;
            esdi_cmd_start <= 1'b0;

            // Update stage output
            discover_stage <= current_stage;

            // Timeout counter
            if (state != STATE_IDLE) begin
                timeout_counter <= timeout_counter + 1;
            end

            // Index counter for control check
            index_prev <= index_pulse;
            if (index_pulse && !index_prev && current_stage == STAGE_CTRL_CHECK) begin
                index_count <= index_count + 1;
            end

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    discover_busy <= 1'b0;
                    if (discover_start) begin
                        discover_busy <= 1'b1;
                        result_valid <= 1'b0;
                        current_stage <= STAGE_PHY_PROBE;
                        discover_progress <= 8'd0;
                        state <= STATE_START;
                    end
                end

                //-------------------------------------------------------------
                STATE_START: begin
                    timeout_counter <= 24'd0;

                    case (current_stage)
                        STAGE_PHY_PROBE: begin
                            phy_probe_start <= 1'b1;
                            discover_progress <= 8'd10;
                        end

                        STAGE_RATE_DET: begin
                            rate_detect_start <= 1'b1;
                            discover_progress <= 8'd30;
                        end

                        STAGE_DECODE_MFM: begin
                            decode_use_mfm <= 1'b1;
                            decode_test_start <= 1'b1;
                            discover_progress <= 8'd50;
                        end

                        STAGE_DECODE_RLL: begin
                            decode_use_mfm <= 1'b0;
                            decode_test_start <= 1'b1;
                            discover_progress <= 8'd60;
                        end

                        STAGE_CLASSIFY: begin
                            // No external module - process immediately
                            discover_progress <= 8'd70;
                            state <= STATE_PROCESS;
                        end

                        STAGE_ESDI_CFG: begin
                            // Query ESDI drive for configuration
                            // Only executed if ESDI was detected in classification
                            esdi_cmd_opcode <= CMD_GET_DEV_CONFIG;
                            esdi_cmd_start <= 1'b1;
                            esdi_config_queried <= 1'b1;
                            discover_progress <= 8'd72;
                        end

                        STAGE_CTRL_CHECK: begin
                            // Check control signals
                            index_count <= 8'd0;
                            ctrl_ready_ok <= drive_ready;
                            ctrl_track00_ok <= track00;
                            ctrl_seek_ok <= seek_complete;
                            discover_progress <= 8'd75;
                        end

                        STAGE_GEOMETRY: begin
                            geometry_scan_start <= 1'b1;
                            discover_progress <= 8'd80;
                        end

                        STAGE_HEALTH: begin
                            health_check_start <= 1'b1;
                            discover_progress <= 8'd95;
                        end

                        STAGE_COMPLETE: begin
                            discover_progress <= 8'd255;
                            state <= STATE_DONE;
                        end

                        STAGE_ERROR: begin
                            state <= STATE_DONE;
                        end

                        default: state <= STATE_DONE;
                    endcase

                    if (current_stage != STAGE_CLASSIFY &&
                        current_stage != STAGE_COMPLETE &&
                        current_stage != STAGE_ERROR) begin
                        state <= STATE_WAIT;
                    end
                end

                //-------------------------------------------------------------
                STATE_WAIT: begin
                    // Check for abort
                    if (discover_abort) begin
                        current_stage <= STAGE_ERROR;
                        state <= STATE_DONE;
                    end
                    // Check for timeout
                    else if (timeout_counter > STAGE_TIMEOUT) begin
                        // Timeout - move to next stage with partial results
                        state <= STATE_PROCESS;
                    end
                    // Check for completion
                    else begin
                        case (current_stage)
                            STAGE_PHY_PROBE: begin
                                if (phy_probe_done) state <= STATE_PROCESS;
                            end

                            STAGE_RATE_DET: begin
                                if (rate_detect_done) state <= STATE_PROCESS;
                            end

                            STAGE_DECODE_MFM, STAGE_DECODE_RLL: begin
                                if (decode_test_done) state <= STATE_PROCESS;
                            end

                            STAGE_ESDI_CFG: begin
                                if (esdi_cmd_done) state <= STATE_PROCESS;
                            end

                            STAGE_CTRL_CHECK: begin
                                // Wait for a few index pulses
                                if (index_count >= 8'd3) begin
                                    ctrl_index_ok <= 1'b1;
                                    state <= STATE_PROCESS;
                                end else if (timeout_counter > 24'd12_000_000) begin
                                    // 30ms = should see ~2 indices at 3600 RPM
                                    ctrl_index_ok <= (index_count > 0);
                                    state <= STATE_PROCESS;
                                end
                            end

                            STAGE_GEOMETRY: begin
                                if (geometry_scan_done) state <= STATE_PROCESS;
                            end

                            STAGE_HEALTH: begin
                                if (health_check_done) state <= STATE_PROCESS;
                            end

                            default: state <= STATE_PROCESS;
                        endcase
                    end
                end

                //-------------------------------------------------------------
                STATE_PROCESS: begin
                    case (current_stage)
                        STAGE_PHY_PROBE: begin
                            result_differential <= phy_is_differential;
                            if (!phy_signal_present) begin
                                // No signal - error
                                current_stage <= STAGE_ERROR;
                            end else begin
                                current_stage <= STAGE_RATE_DET;
                            end
                        end

                        STAGE_RATE_DET: begin
                            result_rate <= detected_rate;
                            if (rate_valid) begin
                                current_stage <= STAGE_DECODE_MFM;
                            end else begin
                                // Couldn't determine rate - try default
                                result_rate <= 3'd1;  // Default 5 Mbps
                                current_stage <= STAGE_DECODE_MFM;
                            end
                        end

                        STAGE_DECODE_MFM: begin
                            mfm_sync_hits <= decode_sync_hits;
                            mfm_crc_ok <= decode_crc_ok;
                            mfm_errors <= decode_errors;
                            current_stage <= STAGE_DECODE_RLL;
                        end

                        STAGE_DECODE_RLL: begin
                            rll_sync_hits <= decode_sync_hits;
                            rll_crc_ok <= decode_crc_ok;
                            rll_errors <= decode_errors;
                            current_stage <= STAGE_CLASSIFY;
                        end

                        STAGE_CLASSIFY: begin
                            // Classify based on decode test results
                            if (result_rate >= 3'd3 || result_differential) begin
                                // 10+ Mbps or differential = ESDI
                                result_encoding <= 3'd3;
                                // For ESDI, try to get configuration from drive
                                current_stage <= STAGE_ESDI_CFG;
                            end else if (rll_crc_ok > mfm_crc_ok &&
                                         rll_errors < mfm_errors) begin
                                // RLL decoded better
                                result_encoding <= 3'd2;
                                current_stage <= STAGE_CTRL_CHECK;
                            end else if (mfm_crc_ok > 0) begin
                                // MFM worked
                                result_encoding <= 3'd1;
                                current_stage <= STAGE_CTRL_CHECK;
                            end else begin
                                // Unknown
                                result_encoding <= 3'd0;
                                current_stage <= STAGE_CTRL_CHECK;
                            end
                        end

                        STAGE_ESDI_CFG: begin
                            // Process ESDI GET_DEV_CONFIG response
                            if (esdi_config_valid && !esdi_cmd_error) begin
                                // ESDI configuration query succeeded!
                                esdi_config_success <= 1'b1;
                                esdi_geometry_cylinders <= esdi_cfg_cylinders;
                                esdi_geometry_heads <= esdi_cfg_heads;
                                esdi_geometry_spt <= esdi_cfg_spt;
                            end else begin
                                // ESDI config query failed - will fall back to probing
                                esdi_config_success <= 1'b0;
                            end
                            current_stage <= STAGE_CTRL_CHECK;
                        end

                        STAGE_CTRL_CHECK: begin
                            // Store control check results in quality score
                            if (ctrl_ready_ok && ctrl_index_ok) begin
                                current_stage <= STAGE_GEOMETRY;
                            end else begin
                                // Drive not responding properly
                                result_quality <= 8'd64;  // Partial quality
                                current_stage <= STAGE_GEOMETRY;
                            end
                        end

                        STAGE_GEOMETRY: begin
                            // Prefer ESDI-reported geometry if available
                            if (esdi_config_success && esdi_geometry_cylinders != 16'd0) begin
                                // Use ESDI-reported geometry (authoritative for ESDI drives)
                                result_cylinders <= esdi_geometry_cylinders;
                                result_heads <= esdi_geometry_heads[3:0];  // Truncate to 4 bits
                                result_spt <= esdi_geometry_spt;
                                // Still use probed interleave/skew if available
                                if (geometry_valid) begin
                                    result_interleave <= interleave;
                                    result_skew <= track_skew;
                                end else begin
                                    result_interleave <= 8'd1;  // ESDI typically 1:1
                                    result_skew <= 8'd0;
                                end
                                current_stage <= STAGE_HEALTH;
                            end else if (geometry_valid) begin
                                // Use probed geometry (MFM/RLL or ESDI fallback)
                                result_heads <= num_heads;
                                result_cylinders <= num_cylinders;
                                result_spt <= sectors_per_track;
                                result_interleave <= interleave;
                                result_skew <= track_skew;
                                current_stage <= STAGE_HEALTH;
                            end else begin
                                // Geometry scan failed - use defaults
                                result_heads <= 4'd2;
                                result_cylinders <= 16'd615;  // ST-225 default
                                result_spt <= 8'd17;
                                result_interleave <= 8'd1;
                                result_skew <= 8'd0;
                                current_stage <= STAGE_HEALTH;
                            end
                        end

                        STAGE_HEALTH: begin
                            // Calculate overall quality score
                            result_quality <= calc_quality(
                                phy_signal_quality,
                                rate_confidence,
                                seek_reliability,
                                rpm_jitter
                            );
                            result_valid <= 1'b1;
                            current_stage <= STAGE_COMPLETE;
                        end

                        default: current_stage <= STAGE_COMPLETE;
                    endcase

                    state <= STATE_NEXT;
                end

                //-------------------------------------------------------------
                STATE_NEXT: begin
                    state <= STATE_START;
                end

                //-------------------------------------------------------------
                STATE_DONE: begin
                    discover_done <= 1'b1;
                    discover_busy <= 1'b0;
                    state <= STATE_IDLE;
                    current_stage <= STAGE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Quality Score Calculation
    //-------------------------------------------------------------------------
    function [7:0] calc_quality;
        input [7:0] signal_q;
        input [7:0] rate_conf;
        input [7:0] seek_rel;
        input [7:0] jitter;
        reg [9:0] sum;
        begin
            // Weight: signal=30%, rate=20%, seek=30%, jitter=20%
            sum = ({2'd0, signal_q} * 10'd77) +     // ~30%
                  ({2'd0, rate_conf} * 10'd51) +    // ~20%
                  ({2'd0, seek_rel} * 10'd77) +     // ~30%
                  ({2'd0, (8'd255 - jitter)} * 10'd51); // ~20%, inverted
            calc_quality = sum[9:2];  // Divide by ~4 to get 0-255
        end
    endfunction

endmodule

//-----------------------------------------------------------------------------
// HDD Discovery Registers
// CPU-accessible registers for discovery control and results
//-----------------------------------------------------------------------------
module hdd_discovery_registers (
    input  wire        clk,
    input  wire        reset,

    // Register interface
    input  wire [7:0]  addr,
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [31:0] wr_data,
    output reg  [31:0] rd_data,

    // Discovery FSM interface
    output reg         discover_start,
    output reg         discover_abort,
    input  wire        discover_done,
    input  wire        discover_busy,
    input  wire [3:0]  discover_stage,
    input  wire [7:0]  discover_progress,

    // Results from FSM
    input  wire [2:0]  result_encoding,
    input  wire        result_differential,
    input  wire [2:0]  result_rate,
    input  wire [3:0]  result_heads,
    input  wire [15:0] result_cylinders,
    input  wire [7:0]  result_spt,
    input  wire [7:0]  result_interleave,
    input  wire [7:0]  result_skew,
    input  wire [7:0]  result_quality,
    input  wire        result_valid,
    input  wire        result_esdi_config_used,
    input  wire [63:0] result_profile
);

    // Register addresses (offset from HDD base 0x80)
    localparam [7:0]
        REG_DISCOVER_CTRL   = 8'h00,  // 0x80: Control/status
        REG_DISCOVER_STATUS = 8'h04,  // 0x84: Stage/progress
        REG_PHY_RESULT      = 8'h08,  // 0x88: PHY probe result
        REG_RATE_RESULT     = 8'h0C,  // 0x8C: Rate detection result
        REG_ENCODE_RESULT   = 8'h10,  // 0x90: Encoding classification + ESDI config flag
        REG_GEOMETRY_A      = 8'h14,  // 0x94: Heads/cylinders
        REG_GEOMETRY_B      = 8'h18,  // 0x98: SPT/interleave/skew
        REG_QUALITY         = 8'h1C,  // 0x9C: Quality score
        REG_PROFILE_LO      = 8'h20,  // 0xA0: Profile low 32 bits
        REG_PROFILE_HI      = 8'h24;  // 0xA4: Profile high 32 bits

    always @(posedge clk) begin
        if (reset) begin
            discover_start <= 1'b0;
            discover_abort <= 1'b0;
            rd_data <= 32'd0;
        end else begin
            // Pulse outputs
            discover_start <= 1'b0;
            discover_abort <= 1'b0;

            // Write handling
            if (wr_en) begin
                case (addr)
                    REG_DISCOVER_CTRL: begin
                        if (wr_data[0]) discover_start <= 1'b1;
                        if (wr_data[1]) discover_abort <= 1'b1;
                    end
                    // Other registers are read-only
                endcase
            end

            // Read handling
            if (rd_en) begin
                case (addr)
                    REG_DISCOVER_CTRL: begin
                        rd_data <= {29'd0, result_valid, discover_done, discover_busy};
                    end

                    REG_DISCOVER_STATUS: begin
                        rd_data <= {16'd0, discover_progress, 4'd0, discover_stage};
                    end

                    REG_PHY_RESULT: begin
                        rd_data <= {23'd0, result_differential, 8'd0};
                    end

                    REG_RATE_RESULT: begin
                        rd_data <= {24'd0, 5'd0, result_rate};
                    end

                    REG_ENCODE_RESULT: begin
                        // Bit 7 = ESDI config used (geometry from GET_DEV_CONFIG)
                        // Bits 2:0 = Encoding type
                        rd_data <= {24'd0, result_esdi_config_used, 4'd0, result_encoding};
                    end

                    REG_GEOMETRY_A: begin
                        rd_data <= {result_cylinders, 12'd0, result_heads};
                    end

                    REG_GEOMETRY_B: begin
                        rd_data <= {8'd0, result_skew, result_interleave, result_spt};
                    end

                    REG_QUALITY: begin
                        rd_data <= {24'd0, result_quality};
                    end

                    REG_PROFILE_LO: begin
                        rd_data <= result_profile[31:0];
                    end

                    REG_PROFILE_HI: begin
                        rd_data <= result_profile[63:32];
                    end

                    default: rd_data <= 32'd0;
                endcase
            end
        end
    end

endmodule
