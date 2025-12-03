//-----------------------------------------------------------------------------
// Encoding Auto-Detector
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Runs all sync pattern detectors in parallel and auto-selects encoding
// based on which detector fires first (or most consistently).
//
// Detection Priority (most distinctive patterns first):
//   1. GCR-Apple (D5 AA 96/AD) - Very distinctive 3-byte sequence
//   2. GCR-CBM (10-byte sync of 0xFF) - Long sync run
//   3. M2FM (F77A pattern) - Unique to DEC/Intel
//   4. Tandy FM (specific AM sequence) - Different from standard FM
//   5. MFM (A1 A1 A1 with missing clock) - Most common
//   6. FM (fallback) - Simple clock pattern
//
// Lock Logic: After 3 consecutive matches of the same encoding, lock the
// detection to prevent spurious mode changes.
//
// Target: AMD Spartan UltraScale+ SCU35
// Created: 2025-12-04 01:30
//-----------------------------------------------------------------------------

module encoding_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Bit input (from DPLL or flux edge detector)
    input  wire        bit_in,
    input  wire        bit_valid,

    // Sync detection inputs from all encoding decoders
    input  wire        mfm_sync,          // MFM A1 sync (3x A1 with clock violations)
    input  wire        fm_sync,           // FM clock pattern detected
    input  wire        m2fm_sync,         // M2FM F77A pattern
    input  wire        gcr_cbm_sync,      // CBM 10-byte sync
    input  wire        gcr_apple_sync,    // Apple D5 AA xx prologue
    input  wire        tandy_sync,        // Tandy AM sequence

    // Detection outputs
    output reg  [2:0]  detected_encoding, // Detected encoding mode (same as ENC_* values)
    output reg         encoding_valid,    // Detection has occurred
    output reg         encoding_locked,   // Encoding is locked (stable)

    // Debug outputs
    output reg  [7:0]  match_count,       // How many times current encoding matched
    output reg  [5:0]  sync_history       // Which syncs have ever been seen
);

    //-------------------------------------------------------------------------
    // Encoding Mode Values (must match encoding_mux.v)
    //-------------------------------------------------------------------------
    localparam ENC_MFM       = 3'b000;  // MFM (standard PC floppy)
    localparam ENC_FM        = 3'b001;  // FM (legacy single-density)
    localparam ENC_GCR_CBM   = 3'b010;  // Commodore 64/1541 GCR
    localparam ENC_GCR_AP6   = 3'b011;  // Apple II 6-bit GCR (DOS 3.3)
    localparam ENC_GCR_AP5   = 3'b100;  // Apple II 5-bit GCR (DOS 3.2)
    localparam ENC_M2FM      = 3'b101;  // M2FM (DEC RX01/02, Intel MDS)
    localparam ENC_TANDY     = 3'b110;  // Tandy FM (TRS-80 CoCo, Dragon)

    // Lock thresholds
    localparam [3:0] LOCK_THRESHOLD = 4'd3;    // Consecutive matches to lock
    localparam [7:0] UNLOCK_THRESHOLD = 8'd10; // Mismatches to unlock

    //-------------------------------------------------------------------------
    // Detection State
    //-------------------------------------------------------------------------
    reg [2:0]  current_detection;   // Current detected encoding
    reg [3:0]  consecutive_matches; // Consecutive matches of same encoding
    reg [7:0]  mismatch_count;      // Mismatches since lock

    // Edge detection for sync pulses (ensure we catch each sync once)
    reg mfm_sync_prev, fm_sync_prev, m2fm_sync_prev;
    reg gcr_cbm_sync_prev, gcr_apple_sync_prev, tandy_sync_prev;

    wire mfm_sync_edge       = mfm_sync && !mfm_sync_prev;
    wire fm_sync_edge        = fm_sync && !fm_sync_prev;
    wire m2fm_sync_edge      = m2fm_sync && !m2fm_sync_prev;
    wire gcr_cbm_sync_edge   = gcr_cbm_sync && !gcr_cbm_sync_prev;
    wire gcr_apple_sync_edge = gcr_apple_sync && !gcr_apple_sync_prev;
    wire tandy_sync_edge     = tandy_sync && !tandy_sync_prev;

    // Any sync detected this cycle
    wire any_sync = mfm_sync_edge || fm_sync_edge || m2fm_sync_edge ||
                    gcr_cbm_sync_edge || gcr_apple_sync_edge || tandy_sync_edge;

    //-------------------------------------------------------------------------
    // Priority Encoder for Sync Detection
    //-------------------------------------------------------------------------
    // Select encoding based on which sync fired, with priority for distinctive patterns
    reg [2:0] priority_encoding;

    always @(*) begin
        // Default to no change
        priority_encoding = current_detection;

        // Priority order: Apple GCR > CBM GCR > M2FM > Tandy > MFM > FM
        // (Most distinctive patterns have highest priority)
        if (gcr_apple_sync_edge) begin
            priority_encoding = ENC_GCR_AP6;
        end
        else if (gcr_cbm_sync_edge) begin
            priority_encoding = ENC_GCR_CBM;
        end
        else if (m2fm_sync_edge) begin
            priority_encoding = ENC_M2FM;
        end
        else if (tandy_sync_edge) begin
            priority_encoding = ENC_TANDY;
        end
        else if (mfm_sync_edge) begin
            priority_encoding = ENC_MFM;
        end
        else if (fm_sync_edge) begin
            priority_encoding = ENC_FM;
        end
    end

    //-------------------------------------------------------------------------
    // Main Detection State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            detected_encoding   <= ENC_MFM;  // Default to MFM
            encoding_valid      <= 1'b0;
            encoding_locked     <= 1'b0;
            current_detection   <= ENC_MFM;
            consecutive_matches <= 4'd0;
            mismatch_count      <= 8'd0;
            match_count         <= 8'd0;
            sync_history        <= 6'b000000;

            mfm_sync_prev       <= 1'b0;
            fm_sync_prev        <= 1'b0;
            m2fm_sync_prev      <= 1'b0;
            gcr_cbm_sync_prev   <= 1'b0;
            gcr_apple_sync_prev <= 1'b0;
            tandy_sync_prev     <= 1'b0;
        end
        else if (enable) begin
            // Update sync edge detection
            mfm_sync_prev       <= mfm_sync;
            fm_sync_prev        <= fm_sync;
            m2fm_sync_prev      <= m2fm_sync;
            gcr_cbm_sync_prev   <= gcr_cbm_sync;
            gcr_apple_sync_prev <= gcr_apple_sync;
            tandy_sync_prev     <= tandy_sync;

            // Track which syncs we've ever seen (for debugging)
            if (mfm_sync_edge)       sync_history[0] <= 1'b1;
            if (fm_sync_edge)        sync_history[1] <= 1'b1;
            if (gcr_cbm_sync_edge)   sync_history[2] <= 1'b1;
            if (gcr_apple_sync_edge) sync_history[3] <= 1'b1;
            if (m2fm_sync_edge)      sync_history[4] <= 1'b1;
            if (tandy_sync_edge)     sync_history[5] <= 1'b1;

            if (any_sync) begin
                // A sync was detected
                if (priority_encoding == current_detection) begin
                    // Same encoding as before - increment match count
                    if (consecutive_matches < 4'd15)
                        consecutive_matches <= consecutive_matches + 1'b1;
                    if (match_count < 8'hFF)
                        match_count <= match_count + 1'b1;
                    mismatch_count <= 8'd0;

                    // Check if we should lock
                    if (consecutive_matches >= LOCK_THRESHOLD) begin
                        encoding_locked <= 1'b1;
                    end
                end
                else begin
                    // Different encoding detected
                    if (encoding_locked) begin
                        // We're locked - count mismatches
                        if (mismatch_count < 8'hFF)
                            mismatch_count <= mismatch_count + 1'b1;

                        // Too many mismatches - unlock and switch
                        if (mismatch_count >= UNLOCK_THRESHOLD) begin
                            encoding_locked     <= 1'b0;
                            current_detection   <= priority_encoding;
                            consecutive_matches <= 4'd1;
                            match_count         <= 8'd1;
                            mismatch_count      <= 8'd0;
                        end
                    end
                    else begin
                        // Not locked - switch to new encoding
                        current_detection   <= priority_encoding;
                        consecutive_matches <= 4'd1;
                        match_count         <= 8'd1;
                        mismatch_count      <= 8'd0;
                    end
                end

                // Mark as valid after first detection
                encoding_valid <= 1'b1;
            end

            // Always output the current detection
            detected_encoding <= current_detection;
        end
        else begin
            // Disabled - clear validity but keep last detection
            encoding_valid <= 1'b0;
            encoding_locked <= 1'b0;
            consecutive_matches <= 4'd0;
            mismatch_count <= 8'd0;
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Encoding Auto-Select Wrapper
// Combines detector with manual override capability
//-----------------------------------------------------------------------------
module encoding_auto_select (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Control
    input  wire        auto_encoding_enable, // Enable auto-detection
    input  wire [2:0]  manual_encoding,      // Manual encoding selection

    // Bit input (for sync detectors)
    input  wire        bit_in,
    input  wire        bit_valid,

    // Sync inputs from encoding mux (directly connected)
    input  wire        mfm_sync,
    input  wire        fm_sync,
    input  wire        m2fm_sync,
    input  wire        gcr_cbm_sync,
    input  wire        gcr_apple_sync,
    input  wire        tandy_sync,

    // Outputs
    output wire [2:0]  effective_encoding,   // Encoding to use
    output wire        encoding_detected,    // Auto-detection has occurred
    output wire        encoding_locked       // Encoding is locked
);

    // Detector instance
    wire [2:0]  auto_encoding;
    wire        auto_valid;
    wire        auto_locked;

    encoding_detector u_detector (
        .clk(clk),
        .reset(reset),
        .enable(enable && auto_encoding_enable),
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        .mfm_sync(mfm_sync),
        .fm_sync(fm_sync),
        .m2fm_sync(m2fm_sync),
        .gcr_cbm_sync(gcr_cbm_sync),
        .gcr_apple_sync(gcr_apple_sync),
        .tandy_sync(tandy_sync),
        .detected_encoding(auto_encoding),
        .encoding_valid(auto_valid),
        .encoding_locked(auto_locked),
        .match_count(),
        .sync_history()
    );

    // Output selection
    assign effective_encoding = (auto_encoding_enable && auto_valid) ? auto_encoding : manual_encoding;
    assign encoding_detected  = auto_valid;
    assign encoding_locked    = auto_locked;

endmodule
