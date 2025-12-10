//-----------------------------------------------------------------------------
// MFM Decoder Module for FluxRipper
// Ported from CAPSImg Codec/DiskEncoding.cpp InitMFM()
//
// MFM decoding extracts data bits from clock+data pairs:
// - 01 decodes to data bit 1
// - 00 decodes to data bit 0 (previous bit was 1)
// - 10 decodes to data bit 0 (previous bit was 0)
// - 11 is an encoding error
//
// Updated: 2025-12-02 16:30
//-----------------------------------------------------------------------------

module mfm_decoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,          // Process when high
    input  wire [15:0] encoded_in,      // MFM encoded input (16 bits = 8 data bits)
    output reg  [7:0]  data_out,        // Decoded byte
    output reg         error,           // Encoding error detected
    output reg         done             // Decoding complete
);

    // State machine
    localparam IDLE = 2'b00;
    localparam DECODE = 2'b01;
    localparam CHECK = 2'b10;

    reg [1:0] state;
    reg [2:0] bit_cnt;
    reg [15:0] enc_reg;
    reg [7:0] dec_reg;
    reg error_flag;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            data_out <= 8'h00;
            error <= 1'b0;
            done <= 1'b0;
            bit_cnt <= 3'd0;
            enc_reg <= 16'h0000;
            dec_reg <= 8'h00;
            error_flag <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    if (enable) begin
                        enc_reg <= encoded_in;
                        bit_cnt <= 3'd0;
                        dec_reg <= 8'h00;
                        error_flag <= 1'b0;
                        state <= DECODE;
                    end
                end

                DECODE: begin
                    // Extract data bit from clock+data pair
                    // Data bit is at odd position (clock at even)
                    dec_reg <= {dec_reg[6:0], enc_reg[14]};

                    // Check for encoding error (11 pattern)
                    if (enc_reg[15:14] == 2'b11) begin
                        error_flag <= 1'b1;
                    end

                    enc_reg <= {enc_reg[13:0], 2'b00};

                    if (bit_cnt == 3'd7) begin
                        state <= CHECK;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                CHECK: begin
                    data_out <= dec_reg;
                    error <= error_flag;
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// MFM Decoder with Lookup Table (combinational)
// For high-speed decoding without state machine
//-----------------------------------------------------------------------------
module mfm_decoder_lut (
    input  wire [15:0] encoded_in,      // MFM encoded input
    output wire [7:0]  data_out,        // Decoded byte
    output wire        error            // Encoding error (any 11 pattern)
);

    // Extract data bits (at odd positions: 14, 12, 10, 8, 6, 4, 2, 0)
    assign data_out[7] = encoded_in[14];
    assign data_out[6] = encoded_in[12];
    assign data_out[5] = encoded_in[10];
    assign data_out[4] = encoded_in[8];
    assign data_out[3] = encoded_in[6];
    assign data_out[2] = encoded_in[4];
    assign data_out[1] = encoded_in[2];
    assign data_out[0] = encoded_in[0];

    // Check for 11 patterns (encoding errors)
    wire err0 = (encoded_in[15:14] == 2'b11);
    wire err1 = (encoded_in[13:12] == 2'b11);
    wire err2 = (encoded_in[11:10] == 2'b11);
    wire err3 = (encoded_in[9:8]   == 2'b11);
    wire err4 = (encoded_in[7:6]   == 2'b11);
    wire err5 = (encoded_in[5:4]   == 2'b11);
    wire err6 = (encoded_in[3:2]   == 2'b11);
    wire err7 = (encoded_in[1:0]   == 2'b11);

    assign error = err0 | err1 | err2 | err3 | err4 | err5 | err6 | err7;

endmodule

//-----------------------------------------------------------------------------
// MFM Decoder with Sync Detection (Parallel Interface)
// Detects A1 (0x4489) and C2 (0x5224) sync patterns
// Note: For serial interface, use mfm_decoder_sync below
//-----------------------------------------------------------------------------
module mfm_decoder_sync_parallel (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [15:0] encoded_in,
    output reg  [7:0]  data_out,
    output reg         a1_detected,     // A1 sync mark detected
    output reg         c2_detected,     // C2 sync mark detected
    output reg         error,
    output reg         done
);

    // Sync patterns from CAPSImg CapsFDCEmulator.cpp
    localparam [15:0] SYNC_A1 = 16'h4489;  // A1 with missing clock
    localparam [15:0] SYNC_C2 = 16'h5224;  // C2 with missing clock

    wire [7:0] decoded_data;
    wire decode_error;

    // Instantiate combinational decoder
    mfm_decoder_lut decoder (
        .encoded_in(encoded_in),
        .data_out(decoded_data),
        .error(decode_error)
    );

    always @(posedge clk) begin
        if (reset) begin
            data_out <= 8'h00;
            a1_detected <= 1'b0;
            c2_detected <= 1'b0;
            error <= 1'b0;
            done <= 1'b0;
        end else if (enable) begin
            data_out <= decoded_data;
            a1_detected <= (encoded_in == SYNC_A1);
            c2_detected <= (encoded_in == SYNC_C2);
            // A1 and C2 have intentional "errors" - don't flag them
            error <= decode_error && (encoded_in != SYNC_A1) && (encoded_in != SYNC_C2);
            done <= 1'b1;
        end else begin
            done <= 1'b0;
            a1_detected <= 1'b0;
            c2_detected <= 1'b0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Bit-serial MFM Decoder
// Decodes MFM bit stream one bit at a time from data separator
//-----------------------------------------------------------------------------
module mfm_decoder_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        bit_clk,         // Bit clock from DPLL
    input  wire        bit_in,          // Serial bit input
    input  wire        sync_reset,      // Reset bit counter on sync
    output reg  [7:0]  data_out,        // Decoded byte
    output reg         byte_ready,      // Byte complete
    output reg  [15:0] shift_reg        // Raw MFM shift register for sync detection
);

    reg [3:0] bit_cnt;
    reg       bit_clk_prev;
    wire      bit_clk_edge;

    assign bit_clk_edge = bit_clk && !bit_clk_prev;

    always @(posedge clk) begin
        if (reset) begin
            shift_reg <= 16'h0000;
            data_out <= 8'h00;
            byte_ready <= 1'b0;
            bit_cnt <= 4'd0;
            bit_clk_prev <= 1'b0;
        end else begin
            bit_clk_prev <= bit_clk;
            byte_ready <= 1'b0;

            if (sync_reset) begin
                bit_cnt <= 4'd0;
            end else if (bit_clk_edge) begin
                // Shift in new bit
                shift_reg <= {shift_reg[14:0], bit_in};
                bit_cnt <= bit_cnt + 1'b1;

                // After 16 bits, extract byte (data bits at odd positions)
                if (bit_cnt == 4'd15) begin
                    data_out <= {shift_reg[14], shift_reg[12], shift_reg[10], shift_reg[8],
                                 shift_reg[6],  shift_reg[4],  shift_reg[2],  bit_in};
                    byte_ready <= 1'b1;
                    bit_cnt <= 4'd0;
                end
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// MFM Serial Decoder with Sync/AM Detection for encoding_mux.v
// Combines serial decoding with MFM sync pattern detection
//
// Interface matches encoding_mux.v expectations for mfm_decoder_sync
//
// MFM Sync patterns (with missing clock):
//   - A1 sync mark: 0x4489 (detects IDAM/DAM)
//   - C2 sync mark: 0x5224 (index mark)
//
// AM Types:
//   - 00: No AM
//   - 01: IDAM (ID Address Mark)
//   - 10: DAM (Data Address Mark)
//   - 11: DDAM (Deleted Data Address Mark)
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------
module mfm_decoder_sync (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_in,          // Serial bit input
    input  wire        bit_valid,       // Bit valid strobe
    output reg  [7:0]  data_out,        // Decoded byte
    output reg         data_valid,      // Byte complete
    output reg         decode_error,    // Decode error (invalid MFM pattern)
    output reg         sync_detected,   // A1/C2 sync pattern detected
    output reg         am_detected,     // Address mark byte detected
    output reg  [1:0]  am_type          // Address mark type
);

    //-------------------------------------------------------------------------
    // MFM Sync Patterns
    //-------------------------------------------------------------------------
    localparam [15:0] SYNC_A1 = 16'h4489;  // A1 with missing clock
    localparam [15:0] SYNC_C2 = 16'h5224;  // C2 with missing clock

    // Address Mark bytes (appear after 3x A1 sync)
    localparam [7:0] AM_IDAM  = 8'hFE;     // ID Address Mark
    localparam [7:0] AM_DAM   = 8'hFB;     // Data Address Mark
    localparam [7:0] AM_DDAM  = 8'hF8;     // Deleted Data Address Mark

    //-------------------------------------------------------------------------
    // Internal State
    //-------------------------------------------------------------------------
    reg [15:0] shift_reg;
    reg [3:0]  bit_cnt;
    reg [1:0]  sync_count;     // Count consecutive A1 syncs (need 3 for AM)
    reg        in_sync;        // Currently synchronized
    reg        await_am;       // Waiting for AM byte after 3x A1

    //-------------------------------------------------------------------------
    // Serial Decoding with Sync Detection
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            shift_reg     <= 16'h0000;
            bit_cnt       <= 4'd0;
            data_out      <= 8'h00;
            data_valid    <= 1'b0;
            decode_error  <= 1'b0;
            sync_detected <= 1'b0;
            am_detected   <= 1'b0;
            am_type       <= 2'b00;
            sync_count    <= 2'd0;
            in_sync       <= 1'b0;
            await_am      <= 1'b0;
        end
        else if (enable && bit_valid) begin
            // Default: clear single-cycle outputs
            data_valid    <= 1'b0;
            sync_detected <= 1'b0;
            am_detected   <= 1'b0;
            decode_error  <= 1'b0;

            // Shift in new bit
            shift_reg <= {shift_reg[14:0], bit_in};
            bit_cnt   <= bit_cnt + 1'b1;

            // Check for sync pattern continuously (can appear any time)
            if (shift_reg[14:0] == SYNC_A1[15:1] && bit_in == SYNC_A1[0]) begin
                // A1 sync detected
                sync_detected <= 1'b1;
                in_sync <= 1'b1;
                bit_cnt <= 4'd0;  // Reset byte alignment

                if (sync_count < 2'd3)
                    sync_count <= sync_count + 1'b1;

                // After 3x A1, next byte is address mark
                if (sync_count == 2'd2) begin
                    await_am <= 1'b1;
                end
            end
            else if (shift_reg[14:0] == SYNC_C2[15:1] && bit_in == SYNC_C2[0]) begin
                // C2 sync detected (index mark)
                sync_detected <= 1'b1;
                in_sync <= 1'b1;
                bit_cnt <= 4'd0;
                sync_count <= 2'd0;  // C2 doesn't chain to AM
            end
            else if (bit_cnt == 4'd15) begin
                // Extract byte from shift register (data bits at odd positions)
                // MFM encoding: bit15=C7, bit14=D7, bit13=C6, bit12=D6, ...
                // Data bits are at positions 14,12,10,8,6,4,2,0
                data_out <= {shift_reg[14], shift_reg[12], shift_reg[10], shift_reg[8],
                             shift_reg[6],  shift_reg[4],  shift_reg[2],  bit_in};
                data_valid <= 1'b1;
                bit_cnt <= 4'd0;

                // Check for address mark if we just got 3x A1
                if (await_am) begin
                    await_am <= 1'b0;
                    am_detected <= 1'b1;

                    // Decode AM type
                    case ({shift_reg[14], shift_reg[12], shift_reg[10], shift_reg[8],
                           shift_reg[6],  shift_reg[4],  shift_reg[2],  bit_in})
                        AM_IDAM:  am_type <= 2'b01;  // ID Address Mark
                        AM_DAM:   am_type <= 2'b10;  // Data Address Mark
                        AM_DDAM:  am_type <= 2'b11;  // Deleted Data Address Mark
                        default:  am_type <= 2'b00;  // Unknown
                    endcase
                end

                // Reset sync count if not seeing sync pattern
                sync_count <= 2'd0;

                // Check for MFM encoding violation
                // Valid MFM: no two consecutive 1s in encoded stream
                // Check pairs: bits 15-14, 13-12, etc.
                if ((shift_reg[15] && shift_reg[14]) ||
                    (shift_reg[13] && shift_reg[12]) ||
                    (shift_reg[11] && shift_reg[10]) ||
                    (shift_reg[9]  && shift_reg[8])  ||
                    (shift_reg[7]  && shift_reg[6])  ||
                    (shift_reg[5]  && shift_reg[4])  ||
                    (shift_reg[3]  && shift_reg[2])  ||
                    (shift_reg[1]  && bit_in)) begin
                    decode_error <= 1'b1;
                end
            end
        end
        else if (!enable) begin
            // Reset state when disabled
            sync_count <= 2'd0;
            in_sync    <= 1'b0;
            await_am   <= 1'b0;
        end
    end

endmodule
