//-----------------------------------------------------------------------------
// Drive Profile Detector
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Aggregates all auto-detection signals to infer drive characteristics:
//   - Form factor (3.5", 5.25", 8")
//   - Density capability (DD, HD, ED)
//   - Track density (40T, 80T, 77T)
//   - Encoding detected
//   - Drive quality metrics
//
// Detection Strategy:
//   1. RPM measurement (300=3.5"/5.25"DD, 360=8"/5.25"HD)
//   2. HEAD_LOAD response (8" drives require it)
//   3. Data rate success (test 250K/300K/500K/1M)
//   4. Track density from sector ID fields
//   5. Encoding from sync pattern detection
//
// Output: 32-bit DRIVE_PROFILE word for software
//
// Target: AMD Spartan UltraScale+ SCU35
// Created: 2025-12-04 02:00
//-----------------------------------------------------------------------------

module drive_profile_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,               // Enable detection

    //-------------------------------------------------------------------------
    // Detection Inputs
    //-------------------------------------------------------------------------
    // RPM detection (from index_handler_dual)
    input  wire        rpm_valid,            // RPM measurement valid
    input  wire        rpm_300,              // Detected 300 RPM
    input  wire        rpm_360,              // Detected 360 RPM

    // Track density (from track_width_analyzer)
    input  wire        track_density_valid,  // Track analysis complete
    input  wire        detected_40_track,    // 40-track disk detected

    // Data rate detection (from flux_analyzer)
    input  wire        data_rate_valid,      // Data rate detection complete
    input  wire [1:0]  detected_data_rate,   // 00=250K, 01=300K, 10=500K, 11=1M
    input  wire        data_rate_locked,     // Data rate stable

    // Encoding detection (from encoding_detector)
    input  wire        encoding_valid,       // Encoding detected
    input  wire [2:0]  detected_encoding,    // Encoding type
    input  wire        encoding_locked,      // Encoding stable

    // PLL quality (from digital_pll)
    input  wire [7:0]  lock_quality,         // 0-255 quality metric
    input  wire        pll_locked,           // PLL in lock

    // Drive status signals
    input  wire        drive_ready,          // Drive ready signal
    input  wire        disk_present,         // Disk in drive (index pulses present)
    input  wire        write_protect,        // Write protect tab
    input  wire        head_load_active,     // HEAD_LOAD signal is being used

    // Hard-sector detection (from flux stream)
    input  wire        sector_pulse_detected, // /SECTOR pulses seen
    input  wire [3:0]  sector_count,          // Number of sector holes per rev

    // Current track position (for 77-track detection)
    input  wire [7:0]  current_track,

    //-------------------------------------------------------------------------
    // Density Probing Interface
    //-------------------------------------------------------------------------
    // For active probing of data rate capability
    output reg         probe_request,        // Request to test next data rate
    output reg  [1:0]  probe_data_rate,      // Data rate to test
    input  wire        probe_complete,       // Probe test finished
    input  wire        probe_success,        // Probe read succeeded

    //-------------------------------------------------------------------------
    // Profile Outputs
    //-------------------------------------------------------------------------
    output reg  [31:0] drive_profile,        // Packed profile word
    output reg         profile_valid,        // Profile detection complete
    output reg         profile_locked,       // Profile stable (high confidence)

    // Individual decoded fields for convenience
    output reg  [1:0]  form_factor,          // 00=unknown, 01=3.5", 10=5.25", 11=8"
    output reg  [1:0]  density_cap,          // 00=DD, 01=HD, 10=ED, 11=unknown
    output reg  [1:0]  track_density,        // 00=40T, 01=80T, 10=77T, 11=unknown
    output reg  [7:0]  quality_score,        // 0-255 composite quality
    output reg         is_hard_sectored,     // Hard-sectored media
    output reg         is_variable_speed,    // Mac GCR variable-speed zones
    output reg         needs_head_load       // 8" drive indicator
);

    //-------------------------------------------------------------------------
    // Form Factor Constants
    //-------------------------------------------------------------------------
    localparam FF_UNKNOWN = 2'b00;
    localparam FF_3_5     = 2'b01;
    localparam FF_5_25    = 2'b10;
    localparam FF_8       = 2'b11;

    // Density Capability
    localparam DENS_DD    = 2'b00;
    localparam DENS_HD    = 2'b01;
    localparam DENS_ED    = 2'b10;
    localparam DENS_UNK   = 2'b11;

    // Track Density
    localparam TRACKS_40  = 2'b00;
    localparam TRACKS_80  = 2'b01;
    localparam TRACKS_77  = 2'b10;
    localparam TRACKS_UNK = 2'b11;

    // Encoding values (match encoding_mux.v)
    localparam ENC_MFM       = 3'b000;
    localparam ENC_FM        = 3'b001;
    localparam ENC_GCR_CBM   = 3'b010;
    localparam ENC_GCR_AP6   = 3'b011;
    localparam ENC_GCR_AP5   = 3'b100;
    localparam ENC_M2FM      = 3'b101;
    localparam ENC_TANDY     = 3'b110;
    localparam ENC_AGAT      = 3'b111;  // Soviet Apple clones (Agat-7/9)

    //-------------------------------------------------------------------------
    // Detection State Machine
    //-------------------------------------------------------------------------
    localparam S_IDLE           = 4'd0;
    localparam S_WAIT_DISK      = 4'd1;
    localparam S_WAIT_RPM       = 4'd2;
    localparam S_PROBE_250K     = 4'd3;
    localparam S_PROBE_300K     = 4'd4;
    localparam S_PROBE_500K     = 4'd5;
    localparam S_PROBE_1M       = 4'd6;
    localparam S_ANALYZE        = 4'd7;
    localparam S_LOCKED         = 4'd8;

    reg [3:0]  state;
    reg [3:0]  next_state;
    reg [23:0] timeout_counter;
    reg [3:0]  probe_attempts;

    // Density probe results
    reg        can_250k;
    reg        can_300k;
    reg        can_500k;
    reg        can_1m;

    // Confidence tracking
    reg [3:0]  consecutive_matches;
    localparam LOCK_THRESHOLD = 4'd3;

    //-------------------------------------------------------------------------
    // Timeout for waiting states (2 seconds @ 200MHz)
    //-------------------------------------------------------------------------
    localparam [23:0] WAIT_TIMEOUT = 24'd200_000; // 1ms timeout for quick checks

    //-------------------------------------------------------------------------
    // Form Factor Inference Logic
    //-------------------------------------------------------------------------
    // Combinational logic to infer form factor from available signals
    reg [1:0]  inferred_form_factor;
    reg [7:0]  ff_confidence;  // 0-100 confidence level

    always @(*) begin
        inferred_form_factor = FF_UNKNOWN;
        ff_confidence = 8'd0;

        if (rpm_valid) begin
            if (rpm_360) begin
                // 360 RPM: Could be 8" or 5.25" HD
                if (head_load_active) begin
                    // 8" drives require HEAD_LOAD
                    inferred_form_factor = FF_8;
                    ff_confidence = 8'd95;
                end else begin
                    // 5.25" HD (no HEAD_LOAD needed)
                    inferred_form_factor = FF_5_25;
                    ff_confidence = 8'd90;
                end
            end else if (rpm_300) begin
                // 300 RPM: 3.5" or 5.25" DD
                if (can_500k || can_1m) begin
                    // HD/ED capability suggests 3.5"
                    inferred_form_factor = FF_3_5;
                    ff_confidence = 8'd85;
                end else if (encoding_valid && (detected_encoding == ENC_GCR_AP6 ||
                                                detected_encoding == ENC_GCR_AP5 ||
                                                detected_encoding == ENC_AGAT)) begin
                    // Apple/Agat GCR encoding suggests 5.25" (Apple II / Soviet clones)
                    inferred_form_factor = FF_5_25;
                    ff_confidence = 8'd80;
                end else if (encoding_valid && detected_encoding == ENC_GCR_CBM) begin
                    // Commodore GCR suggests 5.25" (C64/1541)
                    inferred_form_factor = FF_5_25;
                    ff_confidence = 8'd80;
                end else if (track_density_valid && detected_40_track) begin
                    // 40-track at 300 RPM is overwhelmingly 5.25" DD
                    // (3.5" drives are always 80-track)
                    inferred_form_factor = FF_5_25;
                    ff_confidence = 8'd88;
                end else if (track_density_valid && !detected_40_track) begin
                    // 80-track at 300 RPM without HD capability is likely 3.5" DD
                    inferred_form_factor = FF_3_5;
                    ff_confidence = 8'd82;
                end else begin
                    // Default to 3.5" for 300 RPM (most common modern drive)
                    inferred_form_factor = FF_3_5;
                    ff_confidence = 8'd70;
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Density Capability Inference
    //-------------------------------------------------------------------------
    reg [1:0]  inferred_density;

    always @(*) begin
        inferred_density = DENS_UNK;

        if (can_1m) begin
            inferred_density = DENS_ED;  // 2.88MB ED
        end else if (can_500k) begin
            inferred_density = DENS_HD;  // HD capable
        end else if (can_250k || can_300k) begin
            inferred_density = DENS_DD;  // DD only
        end
    end

    //-------------------------------------------------------------------------
    // Track Density Inference
    //-------------------------------------------------------------------------
    reg [1:0]  inferred_track_density;

    always @(*) begin
        inferred_track_density = TRACKS_UNK;

        if (track_density_valid) begin
            if (detected_40_track) begin
                inferred_track_density = TRACKS_40;
            end else begin
                // Check for 77-track (8" standard)
                if (inferred_form_factor == FF_8 || current_track > 8'd79) begin
                    inferred_track_density = TRACKS_77;
                end else begin
                    inferred_track_density = TRACKS_80;
                end
            end
        end else if (inferred_form_factor == FF_8) begin
            // Default 8" drives to 77 tracks
            inferred_track_density = TRACKS_77;
        end
    end

    //-------------------------------------------------------------------------
    // Quality Score Calculation
    //-------------------------------------------------------------------------
    // Composite score from multiple metrics
    reg [7:0]  computed_quality;

    always @(*) begin
        // Start with PLL lock quality
        computed_quality = lock_quality;

        // Reduce quality for various issues
        if (!pll_locked) begin
            computed_quality = (computed_quality > 8'd50) ? computed_quality - 8'd50 : 8'd0;
        end
        if (!data_rate_locked) begin
            computed_quality = (computed_quality > 8'd20) ? computed_quality - 8'd20 : 8'd0;
        end
        if (!encoding_locked) begin
            computed_quality = (computed_quality > 8'd10) ? computed_quality - 8'd10 : 8'd0;
        end
    end

    //-------------------------------------------------------------------------
    // Variable Speed Detection (Mac GCR)
    //-------------------------------------------------------------------------
    // Mac GCR is detected when Apple GCR encoding is found AND RPM is 300
    wire detected_variable_speed = encoding_valid &&
                                   (detected_encoding == ENC_GCR_AP6) &&
                                   rpm_300;

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            timeout_counter <= 24'd0;
            probe_attempts <= 4'd0;
            profile_valid <= 1'b0;
            profile_locked <= 1'b0;
            consecutive_matches <= 4'd0;

            can_250k <= 1'b0;
            can_300k <= 1'b0;
            can_500k <= 1'b0;
            can_1m <= 1'b0;

            probe_request <= 1'b0;
            probe_data_rate <= 2'b00;

            form_factor <= FF_UNKNOWN;
            density_cap <= DENS_UNK;
            track_density <= TRACKS_UNK;
            quality_score <= 8'd0;
            is_hard_sectored <= 1'b0;
            is_variable_speed <= 1'b0;
            needs_head_load <= 1'b0;
            drive_profile <= 32'd0;
        end else if (enable) begin
            // Clear one-shot signals
            probe_request <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (drive_ready && disk_present) begin
                        state <= S_WAIT_RPM;
                        timeout_counter <= 24'd0;
                        can_250k <= 1'b0;
                        can_300k <= 1'b0;
                        can_500k <= 1'b0;
                        can_1m <= 1'b0;
                    end
                end

                S_WAIT_RPM: begin
                    timeout_counter <= timeout_counter + 1'b1;

                    if (rpm_valid) begin
                        // RPM detected, start density probing
                        state <= S_PROBE_500K;
                        probe_request <= 1'b1;
                        probe_data_rate <= 2'b10;  // 500K
                        timeout_counter <= 24'd0;
                    end else if (timeout_counter >= 24'd400_000) begin
                        // 2ms timeout - proceed without RPM (use detected_data_rate)
                        state <= S_PROBE_500K;
                        probe_request <= 1'b1;
                        probe_data_rate <= 2'b10;
                        timeout_counter <= 24'd0;
                    end
                end

                S_PROBE_500K: begin
                    timeout_counter <= timeout_counter + 1'b1;

                    if (probe_complete) begin
                        can_500k <= probe_success;
                        if (probe_success) begin
                            // Try 1M next
                            state <= S_PROBE_1M;
                            probe_request <= 1'b1;
                            probe_data_rate <= 2'b11;
                        end else begin
                            // Try 250K/300K
                            state <= S_PROBE_250K;
                            probe_request <= 1'b1;
                            probe_data_rate <= 2'b00;
                        end
                        timeout_counter <= 24'd0;
                    end else if (timeout_counter >= 24'd2_000_000) begin
                        // 10ms timeout
                        can_500k <= 1'b0;
                        state <= S_PROBE_250K;
                        probe_request <= 1'b1;
                        probe_data_rate <= 2'b00;
                        timeout_counter <= 24'd0;
                    end
                end

                S_PROBE_1M: begin
                    timeout_counter <= timeout_counter + 1'b1;

                    if (probe_complete) begin
                        can_1m <= probe_success;
                        state <= S_ANALYZE;
                        timeout_counter <= 24'd0;
                    end else if (timeout_counter >= 24'd2_000_000) begin
                        can_1m <= 1'b0;
                        state <= S_ANALYZE;
                        timeout_counter <= 24'd0;
                    end
                end

                S_PROBE_250K: begin
                    timeout_counter <= timeout_counter + 1'b1;

                    if (probe_complete) begin
                        can_250k <= probe_success;
                        state <= S_PROBE_300K;
                        probe_request <= 1'b1;
                        probe_data_rate <= 2'b01;
                        timeout_counter <= 24'd0;
                    end else if (timeout_counter >= 24'd2_000_000) begin
                        can_250k <= 1'b0;
                        state <= S_PROBE_300K;
                        probe_request <= 1'b1;
                        probe_data_rate <= 2'b01;
                        timeout_counter <= 24'd0;
                    end
                end

                S_PROBE_300K: begin
                    timeout_counter <= timeout_counter + 1'b1;

                    if (probe_complete) begin
                        can_300k <= probe_success;
                        // If neither worked and 500K didn't work, try 500K again
                        if (!can_250k && !probe_success && !can_500k) begin
                            state <= S_PROBE_500K;
                            probe_request <= 1'b1;
                            probe_data_rate <= 2'b10;
                            probe_attempts <= probe_attempts + 1'b1;
                        end else begin
                            state <= S_ANALYZE;
                        end
                        timeout_counter <= 24'd0;
                    end else if (timeout_counter >= 24'd2_000_000) begin
                        can_300k <= 1'b0;
                        state <= S_ANALYZE;
                        timeout_counter <= 24'd0;
                    end
                end

                S_ANALYZE: begin
                    // Update all inferred fields
                    form_factor <= inferred_form_factor;
                    density_cap <= inferred_density;
                    track_density <= inferred_track_density;
                    quality_score <= computed_quality;
                    is_hard_sectored <= sector_pulse_detected;
                    is_variable_speed <= detected_variable_speed;
                    needs_head_load <= (inferred_form_factor == FF_8);

                    // Pack profile word
                    // Bit 15 = PROFILE_VALID: explicit valid flag for software
                    // Bit 14 = PROFILE_LOCKED: high-confidence detection complete
                    // Bit 13:12 = Reserved
                    drive_profile <= {
                        computed_quality,                    // [31:24] Quality score (0-255)
                        rpm_360 ? 8'd36 : 8'd30,            // [23:16] RPM / 10
                        1'b1,                                // [15] PROFILE_VALID
                        1'b0,                                // [14] PROFILE_LOCKED (set in S_LOCKED)
                        2'd0,                                // [13:12] Reserved
                        (inferred_form_factor == FF_8),      // [11] HEAD_LOAD required
                        detected_variable_speed,             // [10] Variable-speed zones
                        sector_pulse_detected,               // [9] Hard-sectored media
                        detected_encoding,                   // [8:6] Encoding detected
                        inferred_track_density,              // [5:4] Track density
                        inferred_density,                    // [3:2] Density capability
                        inferred_form_factor                 // [1:0] Form factor
                    };

                    profile_valid <= 1'b1;

                    // Check for lock stability
                    if (ff_confidence >= 8'd80 && encoding_locked && data_rate_locked) begin
                        consecutive_matches <= consecutive_matches + 1'b1;
                        if (consecutive_matches >= LOCK_THRESHOLD) begin
                            profile_locked <= 1'b1;
                            state <= S_LOCKED;
                        end
                    end else begin
                        consecutive_matches <= 4'd0;
                    end
                end

                S_LOCKED: begin
                    // Stay locked, but keep updating quality score
                    quality_score <= computed_quality;

                    drive_profile[31:24] <= computed_quality;
                    drive_profile[14] <= 1'b1;  // PROFILE_LOCKED bit

                    // Check for disk change or loss of lock
                    if (!disk_present || !drive_ready) begin
                        state <= S_IDLE;
                        profile_valid <= 1'b0;
                        profile_locked <= 1'b0;
                        drive_profile[15:14] <= 2'b00;  // Clear VALID and LOCKED
                        consecutive_matches <= 4'd0;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end else begin
            // Not enabled - clear state
            profile_valid <= 1'b0;
            profile_locked <= 1'b0;
            state <= S_IDLE;
        end
    end

endmodule
