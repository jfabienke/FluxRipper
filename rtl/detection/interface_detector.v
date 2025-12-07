//-----------------------------------------------------------------------------
// Interface Detector - Master FSM for Pre-Personality Detection
//
// Orchestrates the complete interface detection sequence:
//   Phase A: Floppy vs HDD (INDEX frequency, cable presence)
//   Phase B: ST-506 vs ESDI (SE vs Differential data path)
//   Phase B4: MFM vs RLL (decode scoring)
//
// Uses evidence-based scoring for robust detection across vendor variants.
//
// Part of Phase 0: Pre-Personality Interface Detection
//
// Clock domain: 300 MHz (HDD domain)
// Created: 2025-12-04 13:05
//-----------------------------------------------------------------------------

module interface_detector (
    input  wire        clk,              // 300 MHz
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Control Interface
    //-------------------------------------------------------------------------
    input  wire        detect_start,     // Start detection sequence
    input  wire        detect_abort,     // Abort detection
    input  wire [2:0]  force_personality,// 0=auto, 1=floppy, 2=MFM, 3=RLL, 4=ESDI
    input  wire        personality_locked,// Skip auto-detect, use forced value
    output reg         detect_busy,      // Detection in progress
    output reg         detect_done,      // Detection complete

    //-------------------------------------------------------------------------
    // INDEX Pulse Input
    //-------------------------------------------------------------------------
    input  wire        index_pulse,      // Raw INDEX from drive

    //-------------------------------------------------------------------------
    // Data Path Inputs
    //-------------------------------------------------------------------------
    input  wire        data_se_rx,       // Single-ended receiver output
    input  wire        data_diff_rx,     // Differential receiver output
    input  wire        wire_a_raw,       // Raw wire A (for correlation)
    input  wire        wire_b_raw,       // Raw wire B (for correlation)

    //-------------------------------------------------------------------------
    // MFM/RLL Decode Test Interface
    //-------------------------------------------------------------------------
    output reg         decode_test_start,
    output reg         decode_test_mfm,  // 1=try MFM, 0=try RLL
    input  wire        decode_test_done,
    input  wire [15:0] decode_sync_hits,
    input  wire [15:0] decode_crc_ok,

    //-------------------------------------------------------------------------
    // Front-End Control
    //-------------------------------------------------------------------------
    output wire        term_enable,      // 100Ω termination control
    output wire        rx_mode_sel,      // 0=SE, 1=DIFF receiver select

    //-------------------------------------------------------------------------
    // Results
    //-------------------------------------------------------------------------
    output reg  [2:0]  detected_type,    // 0=unknown, 1=floppy, 2=MFM, 3=RLL, 4=ESDI
    output reg  [3:0]  confidence,       // 0-15 confidence level
    output reg  [1:0]  phy_mode,         // 0=none, 1=SE, 2=DIFF
    output reg  [2:0]  detected_rate,    // Rate code for NCO
    output reg         was_forced,       // Result was forced, not detected

    //-------------------------------------------------------------------------
    // Debug/Status Outputs
    //-------------------------------------------------------------------------
    output reg  [3:0]  current_phase,    // Current detection phase
    output reg  [7:0]  score_floppy,     // Evidence score for floppy
    output reg  [7:0]  score_hdd,        // Evidence score for HDD
    output reg  [7:0]  score_st506,      // Evidence score for ST-506 (MFM/RLL)
    output reg  [7:0]  score_esdi,       // Evidence score for ESDI
    output reg  [7:0]  score_mfm,        // Evidence score for MFM encoding
    output reg  [7:0]  score_rll         // Evidence score for RLL encoding
);

    //-------------------------------------------------------------------------
    // Interface Type Codes
    //-------------------------------------------------------------------------
    localparam [2:0]
        TYPE_UNKNOWN = 3'd0,
        TYPE_FLOPPY  = 3'd1,
        TYPE_MFM     = 3'd2,
        TYPE_RLL     = 3'd3,
        TYPE_ESDI    = 3'd4;

    //-------------------------------------------------------------------------
    // Detection Phases
    //-------------------------------------------------------------------------
    localparam [3:0]
        PHASE_IDLE          = 4'd0,
        PHASE_INIT          = 4'd1,
        PHASE_A1_INDEX      = 4'd2,     // Measure INDEX frequency
        PHASE_A1_WAIT       = 4'd3,
        PHASE_A_DECIDE      = 4'd4,     // Floppy vs HDD decision
        PHASE_B_START       = 4'd5,     // Start data path sniffing
        PHASE_B_WAIT        = 4'd6,
        PHASE_B_DECIDE      = 4'd7,     // ST-506 vs ESDI decision
        PHASE_B4_MFM        = 4'd8,     // Try MFM decode
        PHASE_B4_MFM_WAIT   = 4'd9,
        PHASE_B4_RLL        = 4'd10,    // Try RLL decode
        PHASE_B4_RLL_WAIT   = 4'd11,
        PHASE_B4_DECIDE     = 4'd12,    // MFM vs RLL decision
        PHASE_FINAL         = 4'd13,
        PHASE_DONE          = 4'd14;

    reg [3:0] state;

    //-------------------------------------------------------------------------
    // Evidence Score Thresholds
    //-------------------------------------------------------------------------
    localparam [7:0] FLOPPY_CONFIRM_THRESHOLD = 8'd8;
    localparam [7:0] HDD_CONFIRM_THRESHOLD    = 8'd8;
    localparam [7:0] ESDI_CONFIRM_THRESHOLD   = 8'd6;
    localparam [7:0] ST506_CONFIRM_THRESHOLD  = 8'd4;

    //-------------------------------------------------------------------------
    // Sub-Module Interfaces
    //-------------------------------------------------------------------------

    // INDEX Frequency Counter
    reg        index_count_start;
    wire       index_count_done;
    wire       index_count_busy;
    wire [26:0] index_period;
    wire [1:0] index_freq_class;
    wire [7:0] index_pulse_count;
    wire [7:0] index_confidence;

    // Dual-Mode Sniffer
    reg        sniff_start;
    wire       sniff_done;
    wire       sniff_busy;
    wire [7:0] se_quality;
    wire [15:0] se_edge_count;
    wire [15:0] se_avg_width;
    wire [2:0] se_rate_bin;
    wire [7:0] diff_quality;
    wire [15:0] diff_edge_count;
    wire [15:0] diff_avg_width;
    wire [2:0] diff_rate_bin;
    wire [7:0] diff_correlation;
    wire       diff_is_differential;
    wire       se_is_better;
    wire       diff_is_better;

    //-------------------------------------------------------------------------
    // INDEX Frequency Counter Instance
    //-------------------------------------------------------------------------
    index_freq_counter u_index_counter (
        .clk(clk),
        .reset(reset),
        .count_start(index_count_start),
        .count_abort(detect_abort),
        .timeout(27'd0),                 // Use default 500ms
        .count_done(index_count_done),
        .count_busy(index_count_busy),
        .index_pulse(index_pulse),
        .measured_period(index_period),
        .freq_class(index_freq_class),
        .pulse_count(index_pulse_count),
        .confidence(index_confidence)
    );

    //-------------------------------------------------------------------------
    // Dual-Mode Sniffer Instance
    //-------------------------------------------------------------------------
    dual_mode_sniffer u_sniffer (
        .clk(clk),
        .reset(reset),
        .capture_start(sniff_start),
        .capture_abort(detect_abort),
        .capture_done(sniff_done),
        .capture_busy(sniff_busy),
        .data_se_rx(data_se_rx),
        .data_diff_rx(data_diff_rx),
        .wire_a_raw(wire_a_raw),
        .wire_b_raw(wire_b_raw),
        .index_pulse(index_pulse),
        .term_enable(term_enable),
        .rx_mode_sel(rx_mode_sel),
        .se_quality(se_quality),
        .se_edge_count(se_edge_count),
        .se_avg_width(se_avg_width),
        .se_rate_bin(se_rate_bin),
        .diff_quality(diff_quality),
        .diff_edge_count(diff_edge_count),
        .diff_avg_width(diff_avg_width),
        .diff_rate_bin(diff_rate_bin),
        .diff_correlation(diff_correlation),
        .diff_is_differential(diff_is_differential),
        .se_is_better(se_is_better),
        .diff_is_better(diff_is_better)
    );

    //-------------------------------------------------------------------------
    // Decode Test Score Storage
    //-------------------------------------------------------------------------
    reg [15:0] mfm_sync_hits;
    reg [15:0] mfm_crc_ok;
    reg [15:0] rll_sync_hits;
    reg [15:0] rll_crc_ok;

    //-------------------------------------------------------------------------
    // Main State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= PHASE_IDLE;
            detect_busy <= 1'b0;
            detect_done <= 1'b0;
            detected_type <= TYPE_UNKNOWN;
            confidence <= 4'd0;
            phy_mode <= 2'd0;
            detected_rate <= 3'd0;
            was_forced <= 1'b0;
            current_phase <= PHASE_IDLE;
            score_floppy <= 8'd0;
            score_hdd <= 8'd0;
            score_st506 <= 8'd0;
            score_esdi <= 8'd0;
            score_mfm <= 8'd0;
            score_rll <= 8'd0;
            index_count_start <= 1'b0;
            sniff_start <= 1'b0;
            decode_test_start <= 1'b0;
            decode_test_mfm <= 1'b0;
            mfm_sync_hits <= 16'd0;
            mfm_crc_ok <= 16'd0;
            rll_sync_hits <= 16'd0;
            rll_crc_ok <= 16'd0;
        end else begin
            detect_done <= 1'b0;
            index_count_start <= 1'b0;
            sniff_start <= 1'b0;
            decode_test_start <= 1'b0;
            current_phase <= state;

            case (state)
                //-------------------------------------------------------------
                PHASE_IDLE: begin
                    detect_busy <= 1'b0;

                    if (detect_start) begin
                        detect_busy <= 1'b1;

                        // Check for forced personality
                        if (personality_locked && force_personality != 3'd0) begin
                            detected_type <= force_personality;
                            was_forced <= 1'b1;
                            confidence <= 4'd15;

                            // Set phy_mode and rate based on forced type
                            case (force_personality)
                                TYPE_FLOPPY: begin
                                    phy_mode <= 2'd0;
                                    detected_rate <= 3'd0;
                                end
                                TYPE_MFM: begin
                                    phy_mode <= 2'd1;  // SE
                                    detected_rate <= 3'd1;  // 5 Mbps
                                end
                                TYPE_RLL: begin
                                    phy_mode <= 2'd1;  // SE
                                    detected_rate <= 3'd2;  // 7.5 Mbps
                                end
                                TYPE_ESDI: begin
                                    phy_mode <= 2'd2;  // DIFF
                                    detected_rate <= 3'd3;  // 10 Mbps
                                end
                                default: begin
                                    phy_mode <= 2'd0;
                                    detected_rate <= 3'd0;
                                end
                            endcase

                            state <= PHASE_DONE;
                        end else begin
                            // Auto-detect mode
                            was_forced <= 1'b0;
                            state <= PHASE_INIT;
                        end
                    end
                end

                //-------------------------------------------------------------
                PHASE_INIT: begin
                    // Clear scores
                    score_floppy <= 8'd0;
                    score_hdd <= 8'd0;
                    score_st506 <= 8'd0;
                    score_esdi <= 8'd0;
                    score_mfm <= 8'd0;
                    score_rll <= 8'd0;
                    detected_type <= TYPE_UNKNOWN;
                    confidence <= 4'd0;

                    state <= PHASE_A1_INDEX;
                end

                //-------------------------------------------------------------
                // PHASE A: Floppy vs HDD Detection
                //-------------------------------------------------------------
                PHASE_A1_INDEX: begin
                    // Start INDEX frequency measurement
                    index_count_start <= 1'b1;
                    state <= PHASE_A1_WAIT;
                end

                PHASE_A1_WAIT: begin
                    if (detect_abort) begin
                        state <= PHASE_FINAL;
                    end else if (index_count_done) begin
                        // Process INDEX frequency results
                        case (index_freq_class)
                            2'd0: begin
                                // No INDEX detected - inconclusive
                                // Could be floppy with motor off or HDD
                                // Continue to Phase B
                            end
                            2'd1: begin
                                // Slow INDEX (5-6 Hz) = Floppy
                                score_floppy <= score_floppy + 8'd5;
                            end
                            2'd2: begin
                                // Fast INDEX (50-60 Hz) = HDD
                                score_hdd <= score_hdd + 8'd5;
                            end
                        endcase

                        state <= PHASE_A_DECIDE;
                    end
                end

                PHASE_A_DECIDE: begin
                    // Decision: Floppy vs HDD
                    if (score_floppy >= FLOPPY_CONFIRM_THRESHOLD) begin
                        // Floppy confirmed with high confidence
                        detected_type <= TYPE_FLOPPY;
                        phy_mode <= 2'd0;
                        detected_rate <= 3'd0;

                        // Calculate confidence (0-15)
                        if (score_floppy >= 8'd10)
                            confidence <= 4'd15;
                        else if (score_floppy >= 8'd8)
                            confidence <= 4'd12;
                        else
                            confidence <= 4'd10;

                        state <= PHASE_FINAL;
                    end else if (score_hdd >= HDD_CONFIRM_THRESHOLD) begin
                        // HDD confirmed, continue to Phase B
                        state <= PHASE_B_START;
                    end else begin
                        // Inconclusive - assume HDD and continue
                        // (more likely scenario for this device)
                        score_hdd <= score_hdd + 8'd2;  // Small bias toward HDD
                        state <= PHASE_B_START;
                    end
                end

                //-------------------------------------------------------------
                // PHASE B: ST-506 vs ESDI Detection
                //-------------------------------------------------------------
                PHASE_B_START: begin
                    // Start dual-mode data path sniffing
                    sniff_start <= 1'b1;
                    state <= PHASE_B_WAIT;
                end

                PHASE_B_WAIT: begin
                    if (detect_abort) begin
                        state <= PHASE_FINAL;
                    end else if (sniff_done) begin
                        // Process sniffing results

                        // Score SE mode results
                        if (se_quality >= 8'd200) begin
                            score_st506 <= score_st506 + 8'd3;
                        end else if (se_quality >= 8'd150) begin
                            score_st506 <= score_st506 + 8'd2;
                        end else if (se_quality >= 8'd100) begin
                            score_st506 <= score_st506 + 8'd1;
                        end

                        // Score DIFF mode results
                        if (diff_is_differential) begin
                            score_esdi <= score_esdi + 8'd4;
                        end
                        if (diff_correlation >= 8'd200) begin
                            score_esdi <= score_esdi + 8'd3;
                        end
                        if (diff_quality > se_quality + 8'd32) begin
                            // DIFF significantly better
                            score_esdi <= score_esdi + 8'd2;
                        end

                        // Score based on rate
                        // 10-15 Mbps = more likely ESDI
                        // 5-7.5 Mbps = more likely ST-506
                        if (diff_rate_bin <= 3'd2) begin
                            // High rate (10-15 Mbps range)
                            score_esdi <= score_esdi + 8'd2;
                        end else if (se_rate_bin >= 3'd4) begin
                            // Low rate (5-7.5 Mbps range)
                            score_st506 <= score_st506 + 8'd2;
                        end

                        state <= PHASE_B_DECIDE;
                    end
                end

                PHASE_B_DECIDE: begin
                    if (score_esdi >= ESDI_CONFIRM_THRESHOLD) begin
                        // ESDI confirmed
                        detected_type <= TYPE_ESDI;
                        phy_mode <= 2'd2;  // Differential

                        // Set rate based on histogram
                        case (diff_rate_bin)
                            3'd0, 3'd1: detected_rate <= 3'd4;  // 15 Mbps
                            3'd2: detected_rate <= 3'd3;         // 10 Mbps
                            default: detected_rate <= 3'd3;      // Default 10 Mbps
                        endcase

                        confidence <= (score_esdi >= 8'd10) ? 4'd15 :
                                     (score_esdi >= 8'd8) ? 4'd12 : 4'd10;

                        state <= PHASE_FINAL;
                    end else if (score_st506 >= ST506_CONFIRM_THRESHOLD) begin
                        // ST-506 confirmed, need to determine MFM vs RLL
                        phy_mode <= 2'd1;  // Single-ended
                        state <= PHASE_B4_MFM;
                    end else begin
                        // Inconclusive - assume ST-506 (MFM is most common)
                        phy_mode <= 2'd1;
                        state <= PHASE_B4_MFM;
                    end
                end

                //-------------------------------------------------------------
                // PHASE B4: MFM vs RLL Detection
                //-------------------------------------------------------------
                PHASE_B4_MFM: begin
                    // Try MFM decode
                    decode_test_mfm <= 1'b1;
                    decode_test_start <= 1'b1;
                    state <= PHASE_B4_MFM_WAIT;
                end

                PHASE_B4_MFM_WAIT: begin
                    if (detect_abort) begin
                        state <= PHASE_FINAL;
                    end else if (decode_test_done) begin
                        // Store MFM results
                        mfm_sync_hits <= decode_sync_hits;
                        mfm_crc_ok <= decode_crc_ok;

                        // Score MFM
                        score_mfm <= {decode_sync_hits[7:0]} +
                                     ({decode_crc_ok[6:0], 1'b0});  // sync + 2*crc

                        state <= PHASE_B4_RLL;
                    end
                end

                PHASE_B4_RLL: begin
                    // Try RLL decode
                    decode_test_mfm <= 1'b0;
                    decode_test_start <= 1'b1;
                    state <= PHASE_B4_RLL_WAIT;
                end

                PHASE_B4_RLL_WAIT: begin
                    if (detect_abort) begin
                        state <= PHASE_FINAL;
                    end else if (decode_test_done) begin
                        // Store RLL results
                        rll_sync_hits <= decode_sync_hits;
                        rll_crc_ok <= decode_crc_ok;

                        // Score RLL
                        score_rll <= {decode_sync_hits[7:0]} +
                                    ({decode_crc_ok[6:0], 1'b0});

                        state <= PHASE_B4_DECIDE;
                    end
                end

                PHASE_B4_DECIDE: begin
                    // Compare MFM vs RLL scores
                    if (score_mfm > score_rll) begin
                        detected_type <= TYPE_MFM;
                        detected_rate <= 3'd1;  // 5 Mbps
                        confidence <= (score_mfm > score_rll + 8'd32) ? 4'd15 :
                                     (score_mfm > score_rll + 8'd16) ? 4'd12 : 4'd10;
                    end else if (score_rll > score_mfm) begin
                        detected_type <= TYPE_RLL;
                        detected_rate <= 3'd2;  // 7.5 Mbps
                        confidence <= (score_rll > score_mfm + 8'd32) ? 4'd15 :
                                     (score_rll > score_mfm + 8'd16) ? 4'd12 : 4'd10;
                    end else begin
                        // Tie - use rate as tiebreaker
                        if (se_rate_bin <= 3'd3) begin
                            // Faster rate suggests RLL
                            detected_type <= TYPE_RLL;
                            detected_rate <= 3'd2;
                        end else begin
                            // Slower rate, default to MFM
                            detected_type <= TYPE_MFM;
                            detected_rate <= 3'd1;
                        end
                        confidence <= 4'd8;  // Lower confidence on tie
                    end

                    state <= PHASE_FINAL;
                end

                //-------------------------------------------------------------
                PHASE_FINAL: begin
                    // Ensure we have a valid result
                    if (detected_type == TYPE_UNKNOWN) begin
                        // Default to MFM if still unknown
                        detected_type <= TYPE_MFM;
                        phy_mode <= 2'd1;
                        detected_rate <= 3'd1;
                        confidence <= 4'd4;  // Low confidence
                    end

                    state <= PHASE_DONE;
                end

                //-------------------------------------------------------------
                PHASE_DONE: begin
                    detect_done <= 1'b1;
                    detect_busy <= 1'b0;
                    state <= PHASE_IDLE;
                end

                default: state <= PHASE_IDLE;
            endcase
        end
    end

endmodule
