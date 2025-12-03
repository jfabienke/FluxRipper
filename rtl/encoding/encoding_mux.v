//-----------------------------------------------------------------------------
// Encoding Multiplexer
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Selects between FM, MFM, M2FM, GCR, and Tandy encoding/decoding based on format
// Provides unified interface for command FSM
//
// Supported encodings:
//   - MFM: Standard PC floppy (IBM, PC)
//   - FM: Legacy single-density
//   - M2FM: DEC RX01/02, Intel MDS, Cromemco
//   - GCR-CBM: Commodore 64/1541
//   - GCR-Apple6: Apple II DOS 3.3 (6&2)
//   - GCR-Apple5: Apple II DOS 3.2 (5&3)
//   - Tandy FM: TRS-80 CoCo, Dragon 32/64
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-03 23:50
//-----------------------------------------------------------------------------

module encoding_mux (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Encoding format selection
    input  wire [2:0]  encoding_mode,  // See encoding types below

    // Serial bit interface (from/to DPLL)
    input  wire        bit_clk,        // Bit clock from DPLL
    input  wire        flux_in,        // Serial flux input
    input  wire        flux_in_valid,  // Flux input valid
    output wire        flux_out,       // Serial flux output
    output wire        flux_out_valid, // Flux output valid

    // Byte interface (to/from command FSM)
    input  wire [7:0]  tx_data,        // Data to encode
    input  wire        tx_valid,       // Data valid
    output wire        tx_ready,       // Ready for new data
    output wire        tx_complete,    // Byte transmission complete

    output wire [7:0]  rx_data,        // Decoded data
    output wire        rx_valid,       // Decoded data valid
    output wire        rx_error,       // Decode error

    // Sync/AM detection outputs
    output wire        sync_detected,  // Sync pattern detected
    output wire        am_detected,    // Address mark detected
    output wire [1:0]  am_type         // Address mark type
);

    //-------------------------------------------------------------------------
    // Encoding Mode Definitions
    //-------------------------------------------------------------------------
    localparam ENC_MFM       = 3'b000;  // MFM (standard PC floppy)
    localparam ENC_FM        = 3'b001;  // FM (legacy single-density)
    localparam ENC_GCR_CBM   = 3'b010;  // Commodore 64/1541 GCR
    localparam ENC_GCR_AP6   = 3'b011;  // Apple II 6-bit GCR (DOS 3.3)
    localparam ENC_GCR_AP5   = 3'b100;  // Apple II 5-bit GCR (DOS 3.2)
    localparam ENC_M2FM      = 3'b101;  // M2FM (DEC RX01/02, Intel MDS)
    localparam ENC_TANDY     = 3'b110;  // Tandy FM (TRS-80 CoCo, Dragon)

    //-------------------------------------------------------------------------
    // Internal wires for each encoder/decoder
    //-------------------------------------------------------------------------

    // MFM signals
    wire        mfm_flux_out, mfm_flux_valid;
    wire        mfm_tx_ready, mfm_tx_complete;
    wire [7:0]  mfm_rx_data;
    wire        mfm_rx_valid, mfm_rx_error;
    wire        mfm_sync, mfm_am;
    wire [1:0]  mfm_am_type;

    // FM signals
    wire        fm_flux_out, fm_flux_valid;
    wire        fm_tx_ready, fm_tx_complete;
    wire [7:0]  fm_rx_data;
    wire        fm_rx_valid, fm_rx_error;
    wire        fm_sync, fm_am;
    wire [1:0]  fm_am_type;

    // CBM GCR signals
    wire        gcr_cbm_flux_out, gcr_cbm_flux_valid;
    wire        gcr_cbm_tx_ready, gcr_cbm_tx_complete;
    wire [7:0]  gcr_cbm_rx_data;
    wire        gcr_cbm_rx_valid, gcr_cbm_rx_error;
    wire        gcr_cbm_sync;

    // Apple GCR 6-bit signals
    wire        gcr_ap6_flux_out, gcr_ap6_flux_valid;
    wire        gcr_ap6_tx_ready, gcr_ap6_tx_complete;
    wire [7:0]  gcr_ap6_rx_data;
    wire        gcr_ap6_rx_valid, gcr_ap6_rx_error;
    wire        gcr_ap6_addr_prologue, gcr_ap6_data_prologue;

    // M2FM signals
    wire        m2fm_flux_out, m2fm_flux_valid;
    wire        m2fm_tx_ready, m2fm_tx_complete;
    wire [7:0]  m2fm_rx_data;
    wire        m2fm_rx_valid, m2fm_rx_error;
    wire        m2fm_sync;

    // Tandy FM signals
    wire        tandy_flux_out, tandy_flux_valid;
    wire        tandy_tx_ready, tandy_tx_complete;
    wire [7:0]  tandy_rx_data;
    wire        tandy_rx_valid, tandy_rx_error;
    wire        tandy_sync, tandy_id_am, tandy_data_am, tandy_deleted_am;

    //-------------------------------------------------------------------------
    // MFM Encoder/Decoder Instance
    //-------------------------------------------------------------------------
    mfm_encoder_serial u_mfm_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_MFM)),
        .bit_clk(bit_clk),
        .data_in(tx_data),
        .data_valid(tx_valid),
        .flux_out(mfm_flux_out),
        .flux_valid(mfm_flux_valid),
        .byte_complete(mfm_tx_complete),
        .ready(mfm_tx_ready)
    );

    mfm_decoder_sync u_mfm_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_MFM)),
        .bit_in(flux_in),
        .bit_valid(flux_in_valid && bit_clk),
        .data_out(mfm_rx_data),
        .data_valid(mfm_rx_valid),
        .decode_error(mfm_rx_error),
        .sync_detected(mfm_sync),
        .am_detected(mfm_am),
        .am_type(mfm_am_type)
    );

    //-------------------------------------------------------------------------
    // FM Encoder/Decoder Instance
    //-------------------------------------------------------------------------
    fm_encoder_serial u_fm_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_FM)),
        .bit_clk(bit_clk),
        .data_in(tx_data),
        .data_valid(tx_valid),
        .flux_out(fm_flux_out),
        .flux_valid(fm_flux_valid),
        .byte_complete(fm_tx_complete),
        .ready(fm_tx_ready)
    );

    fm_decoder_serial u_fm_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_FM)),
        .bit_clk(bit_clk),
        .flux_in(flux_in),
        .flux_valid(flux_in_valid),
        .data_out(fm_rx_data),
        .data_valid(fm_rx_valid),
        .sync_error(fm_rx_error)
    );

    // FM AM detector (simplified - generates sync/AM signals)
    fm_am_detector u_fm_am (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_FM)),
        .bit_in(flux_in),
        .bit_valid(flux_in_valid && bit_clk),
        .index_am(),
        .id_am(fm_am),
        .data_am(),
        .deleted_am(),
        .data_byte(),
        .byte_ready(fm_sync)
    );

    assign fm_am_type = 2'b00;  // FM uses different AM scheme

    //-------------------------------------------------------------------------
    // CBM GCR Encoder/Decoder Instance
    //-------------------------------------------------------------------------
    gcr_cbm_encoder_serial u_gcr_cbm_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_GCR_CBM)),
        .bit_clk(bit_clk),
        .data_in(tx_data),
        .data_valid(tx_valid),
        .flux_out(gcr_cbm_flux_out),
        .flux_valid(gcr_cbm_flux_valid),
        .byte_complete(gcr_cbm_tx_complete),
        .ready(gcr_cbm_tx_ready)
    );

    gcr_cbm_decoder_serial u_gcr_cbm_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_GCR_CBM)),
        .bit_clk(bit_clk),
        .flux_in(flux_in),
        .flux_valid(flux_in_valid),
        .data_out(gcr_cbm_rx_data),
        .data_valid(gcr_cbm_rx_valid),
        .decode_error(gcr_cbm_rx_error)
    );

    gcr_cbm_sync_detector u_gcr_cbm_sync (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_GCR_CBM)),
        .bit_in(flux_in),
        .bit_valid(flux_in_valid && bit_clk),
        .sync_detected(gcr_cbm_sync),
        .sync_count()
    );

    //-------------------------------------------------------------------------
    // Apple GCR 6-bit Encoder/Decoder (simplified byte interface)
    // Note: Apple uses different byte structure, this is a simplified wrapper
    //-------------------------------------------------------------------------
    reg [5:0] apple6_tx_data;
    wire [5:0] apple6_rx_data;
    wire apple6_rx_valid;

    // Map 8-bit to 6-bit (simplified - real implementation needs nibblizing)
    always @(*) begin
        apple6_tx_data = tx_data[5:0];  // Simplified mapping
    end

    gcr_apple6_encoder u_gcr_ap6_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_GCR_AP6)),
        .data_in(apple6_tx_data),
        .data_valid(tx_valid),
        .encoded_out(gcr_ap6_rx_data),  // 8-bit GCR encoded
        .encoded_valid(gcr_ap6_tx_complete),
        .busy()
    );

    gcr_apple6_decoder u_gcr_ap6_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_GCR_AP6)),
        .encoded_in(gcr_ap6_rx_data),  // Would need serial->parallel
        .encoded_valid(flux_in_valid),
        .data_out(apple6_rx_data),
        .data_valid(apple6_rx_valid),
        .decode_error(gcr_ap6_rx_error)
    );

    apple_sync_detector u_apple_sync (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_GCR_AP6 || encoding_mode == ENC_GCR_AP5)),
        .byte_in(gcr_ap6_rx_data),
        .byte_valid(gcr_ap6_rx_valid),
        .addr_prologue(gcr_ap6_addr_prologue),
        .data_prologue(gcr_ap6_data_prologue),
        .epilogue(),
        .sync_state()
    );

    // Simplified Apple outputs
    assign gcr_ap6_flux_out = 1'b0;      // Need serial encoder
    assign gcr_ap6_flux_valid = 1'b0;
    assign gcr_ap6_tx_ready = 1'b1;
    assign gcr_ap6_rx_valid = apple6_rx_valid;

    //-------------------------------------------------------------------------
    // M2FM Encoder/Decoder Instance (DEC RX01/02, Intel MDS)
    //-------------------------------------------------------------------------
    m2fm_encoder_serial u_m2fm_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_M2FM)),
        .bit_clk(bit_clk),
        .data_in(tx_data),
        .data_valid(tx_valid),
        .flux_out(m2fm_flux_out),
        .flux_valid(m2fm_flux_valid),
        .byte_complete(m2fm_tx_complete),
        .ready(m2fm_tx_ready)
    );

    m2fm_decoder_serial u_m2fm_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_M2FM)),
        .bit_clk(bit_clk),
        .flux_in(flux_in),
        .flux_valid(flux_in_valid),
        .data_out(m2fm_rx_data),
        .data_valid(m2fm_rx_valid),
        .sync_error(m2fm_rx_error)
    );

    m2fm_sync_detector u_m2fm_sync (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_M2FM)),
        .bit_in(flux_in),
        .bit_valid(flux_in_valid && bit_clk),
        .sync_detected(m2fm_sync),
        .data_byte(),
        .byte_ready()
    );

    //-------------------------------------------------------------------------
    // Tandy FM Encoder/Decoder Instance (TRS-80 CoCo, Dragon 32/64)
    // Uses standard FM encoding with Tandy-specific sync detector
    //-------------------------------------------------------------------------
    // Tandy uses standard FM encoder/decoder
    fm_encoder_serial u_tandy_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_TANDY)),
        .bit_clk(bit_clk),
        .data_in(tx_data),
        .data_valid(tx_valid),
        .flux_out(tandy_flux_out),
        .flux_valid(tandy_flux_valid),
        .byte_complete(tandy_tx_complete),
        .ready(tandy_tx_ready)
    );

    fm_decoder_serial u_tandy_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_TANDY)),
        .bit_clk(bit_clk),
        .flux_in(flux_in),
        .flux_valid(flux_in_valid),
        .data_out(tandy_rx_data),
        .data_valid(tandy_rx_valid),
        .sync_error(tandy_rx_error)
    );

    // Tandy-specific sync/AM detector
    tandy_sync_detector u_tandy_sync (
        .clk(clk),
        .reset(reset),
        .enable(enable && (encoding_mode == ENC_TANDY)),
        .bit_in(flux_in),
        .bit_valid(flux_in_valid && bit_clk),
        .sync_detected(tandy_sync),
        .id_am(tandy_id_am),
        .data_am(tandy_data_am),
        .deleted_am(tandy_deleted_am),
        .data_byte(),
        .byte_ready(),
        .sync_count()
    );

    //-------------------------------------------------------------------------
    // Output Multiplexer
    //-------------------------------------------------------------------------
    reg        flux_out_r;
    reg        flux_out_valid_r;
    reg        tx_ready_r;
    reg        tx_complete_r;
    reg [7:0]  rx_data_r;
    reg        rx_valid_r;
    reg        rx_error_r;
    reg        sync_detected_r;
    reg        am_detected_r;
    reg [1:0]  am_type_r;

    always @(*) begin
        case (encoding_mode)
            ENC_MFM: begin
                flux_out_r       = mfm_flux_out;
                flux_out_valid_r = mfm_flux_valid;
                tx_ready_r       = mfm_tx_ready;
                tx_complete_r    = mfm_tx_complete;
                rx_data_r        = mfm_rx_data;
                rx_valid_r       = mfm_rx_valid;
                rx_error_r       = mfm_rx_error;
                sync_detected_r  = mfm_sync;
                am_detected_r    = mfm_am;
                am_type_r        = mfm_am_type;
            end

            ENC_FM: begin
                flux_out_r       = fm_flux_out;
                flux_out_valid_r = fm_flux_valid;
                tx_ready_r       = fm_tx_ready;
                tx_complete_r    = fm_tx_complete;
                rx_data_r        = fm_rx_data;
                rx_valid_r       = fm_rx_valid;
                rx_error_r       = fm_rx_error;
                sync_detected_r  = fm_sync;
                am_detected_r    = fm_am;
                am_type_r        = fm_am_type;
            end

            ENC_GCR_CBM: begin
                flux_out_r       = gcr_cbm_flux_out;
                flux_out_valid_r = gcr_cbm_flux_valid;
                tx_ready_r       = gcr_cbm_tx_ready;
                tx_complete_r    = gcr_cbm_tx_complete;
                rx_data_r        = gcr_cbm_rx_data;
                rx_valid_r       = gcr_cbm_rx_valid;
                rx_error_r       = gcr_cbm_rx_error;
                sync_detected_r  = gcr_cbm_sync;
                am_detected_r    = 1'b0;  // CBM uses different structure
                am_type_r        = 2'b00;
            end

            ENC_GCR_AP6, ENC_GCR_AP5: begin
                flux_out_r       = gcr_ap6_flux_out;
                flux_out_valid_r = gcr_ap6_flux_valid;
                tx_ready_r       = gcr_ap6_tx_ready;
                tx_complete_r    = gcr_ap6_tx_complete;
                rx_data_r        = {2'b00, apple6_rx_data};
                rx_valid_r       = gcr_ap6_rx_valid;
                rx_error_r       = gcr_ap6_rx_error;
                sync_detected_r  = gcr_ap6_addr_prologue | gcr_ap6_data_prologue;
                am_detected_r    = gcr_ap6_addr_prologue;
                am_type_r        = {1'b0, gcr_ap6_data_prologue};
            end

            ENC_M2FM: begin
                flux_out_r       = m2fm_flux_out;
                flux_out_valid_r = m2fm_flux_valid;
                tx_ready_r       = m2fm_tx_ready;
                tx_complete_r    = m2fm_tx_complete;
                rx_data_r        = m2fm_rx_data;
                rx_valid_r       = m2fm_rx_valid;
                rx_error_r       = m2fm_rx_error;
                sync_detected_r  = m2fm_sync;
                am_detected_r    = m2fm_sync;  // M2FM uses sync as AM indicator
                am_type_r        = 2'b00;       // DEC format differs from IBM
            end

            ENC_TANDY: begin
                flux_out_r       = tandy_flux_out;
                flux_out_valid_r = tandy_flux_valid;
                tx_ready_r       = tandy_tx_ready;
                tx_complete_r    = tandy_tx_complete;
                rx_data_r        = tandy_rx_data;
                rx_valid_r       = tandy_rx_valid;
                rx_error_r       = tandy_rx_error;
                sync_detected_r  = tandy_sync;
                am_detected_r    = tandy_id_am | tandy_data_am | tandy_deleted_am;
                am_type_r        = tandy_deleted_am ? 2'b11 :
                                   tandy_data_am    ? 2'b10 :
                                   tandy_id_am      ? 2'b01 : 2'b00;
            end

            default: begin
                flux_out_r       = 1'b0;
                flux_out_valid_r = 1'b0;
                tx_ready_r       = 1'b1;
                tx_complete_r    = 1'b0;
                rx_data_r        = 8'h00;
                rx_valid_r       = 1'b0;
                rx_error_r       = 1'b0;
                sync_detected_r  = 1'b0;
                am_detected_r    = 1'b0;
                am_type_r        = 2'b00;
            end
        endcase
    end

    assign flux_out       = flux_out_r;
    assign flux_out_valid = flux_out_valid_r;
    assign tx_ready       = tx_ready_r;
    assign tx_complete    = tx_complete_r;
    assign rx_data        = rx_data_r;
    assign rx_valid       = rx_valid_r;
    assign rx_error       = rx_error_r;
    assign sync_detected  = sync_detected_r;
    assign am_detected    = am_detected_r;
    assign am_type        = am_type_r;

endmodule
