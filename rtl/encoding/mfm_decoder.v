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
// MFM Decoder with Sync Detection
// Detects A1 (0x4489) and C2 (0x5224) sync patterns
//-----------------------------------------------------------------------------
module mfm_decoder_sync (
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
