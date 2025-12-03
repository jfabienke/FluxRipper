//-----------------------------------------------------------------------------
// GCR Encoder/Decoder - Commodore CBM Format
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Based on CAPSImg Codec/DiskEncoding.cpp gcr_cbm[] table
// CBM GCR: 4 bits -> 5 bits encoding
// Each byte becomes two 5-bit groups (10 bits total)
//
// Target: Xilinx Spartan UltraScale+ (UC+)
// Updated: 2025-12-03 12:05
//-----------------------------------------------------------------------------

module gcr_cbm_encoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [7:0]  data_in,        // Byte to encode
    input  wire        data_valid,     // Input data valid
    output reg  [9:0]  encoded_out,    // GCR encoded output (10 bits)
    output reg         encoded_valid,  // Output valid
    output reg         busy            // Encoder busy
);

    //-------------------------------------------------------------------------
    // CBM GCR Encoding Table (4-bit -> 5-bit)
    // From CAPSImg: gcr_cbm[] = {
    //   0x0a, 0x0b, 0x12, 0x13, 0x0e, 0x0f, 0x16, 0x17,
    //   0x09, 0x19, 0x1a, 0x1b, 0x0d, 0x1d, 0x1e, 0x15
    // }
    //-------------------------------------------------------------------------

    function [4:0] gcr_encode_nibble;
        input [3:0] nibble;
        begin
            case (nibble)
                4'h0: gcr_encode_nibble = 5'h0A;  // 01010
                4'h1: gcr_encode_nibble = 5'h0B;  // 01011
                4'h2: gcr_encode_nibble = 5'h12;  // 10010
                4'h3: gcr_encode_nibble = 5'h13;  // 10011
                4'h4: gcr_encode_nibble = 5'h0E;  // 01110
                4'h5: gcr_encode_nibble = 5'h0F;  // 01111
                4'h6: gcr_encode_nibble = 5'h16;  // 10110
                4'h7: gcr_encode_nibble = 5'h17;  // 10111
                4'h8: gcr_encode_nibble = 5'h09;  // 01001
                4'h9: gcr_encode_nibble = 5'h19;  // 11001
                4'hA: gcr_encode_nibble = 5'h1A;  // 11010
                4'hB: gcr_encode_nibble = 5'h1B;  // 11011
                4'hC: gcr_encode_nibble = 5'h0D;  // 01101
                4'hD: gcr_encode_nibble = 5'h1D;  // 11101
                4'hE: gcr_encode_nibble = 5'h1E;  // 11110
                4'hF: gcr_encode_nibble = 5'h15;  // 10101
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            encoded_out   <= 10'h000;
            encoded_valid <= 1'b0;
            busy          <= 1'b0;
        end
        else if (enable) begin
            encoded_valid <= 1'b0;

            if (data_valid && !busy) begin
                // Encode high nibble and low nibble
                // High nibble first, then low nibble
                encoded_out <= {gcr_encode_nibble(data_in[7:4]),
                                gcr_encode_nibble(data_in[3:0])};
                encoded_valid <= 1'b1;
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// CBM GCR Decoder
// Decodes 10-bit GCR data back to 8-bit byte
//-----------------------------------------------------------------------------

module gcr_cbm_decoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [9:0]  encoded_in,     // GCR encoded input (10 bits)
    input  wire        encoded_valid,  // Input valid
    output reg  [7:0]  data_out,       // Decoded byte
    output reg         data_valid,     // Output valid
    output reg         decode_error    // Invalid GCR pattern detected
);

    //-------------------------------------------------------------------------
    // CBM GCR Decoding (5-bit -> 4-bit)
    // Inverse of encoding table, with error detection
    //-------------------------------------------------------------------------

    function [4:0] gcr_decode_quintet;  // [4] = error flag, [3:0] = decoded nibble
        input [4:0] quintet;
        begin
            case (quintet)
                5'h0A: gcr_decode_quintet = 5'b00000;  // 0
                5'h0B: gcr_decode_quintet = 5'b00001;  // 1
                5'h12: gcr_decode_quintet = 5'b00010;  // 2
                5'h13: gcr_decode_quintet = 5'b00011;  // 3
                5'h0E: gcr_decode_quintet = 5'b00100;  // 4
                5'h0F: gcr_decode_quintet = 5'b00101;  // 5
                5'h16: gcr_decode_quintet = 5'b00110;  // 6
                5'h17: gcr_decode_quintet = 5'b00111;  // 7
                5'h09: gcr_decode_quintet = 5'b01000;  // 8
                5'h19: gcr_decode_quintet = 5'b01001;  // 9
                5'h1A: gcr_decode_quintet = 5'b01010;  // A
                5'h1B: gcr_decode_quintet = 5'b01011;  // B
                5'h0D: gcr_decode_quintet = 5'b01100;  // C
                5'h1D: gcr_decode_quintet = 5'b01101;  // D
                5'h1E: gcr_decode_quintet = 5'b01110;  // E
                5'h15: gcr_decode_quintet = 5'b01111;  // F
                default: gcr_decode_quintet = 5'b10000; // Error
            endcase
        end
    endfunction

    wire [4:0] high_decoded = gcr_decode_quintet(encoded_in[9:5]);
    wire [4:0] low_decoded  = gcr_decode_quintet(encoded_in[4:0]);

    always @(posedge clk) begin
        if (reset) begin
            data_out     <= 8'h00;
            data_valid   <= 1'b0;
            decode_error <= 1'b0;
        end
        else if (enable && encoded_valid) begin
            data_out     <= {high_decoded[3:0], low_decoded[3:0]};
            data_valid   <= 1'b1;
            decode_error <= high_decoded[4] | low_decoded[4];
        end
        else begin
            data_valid <= 1'b0;
        end
    end

endmodule


//-----------------------------------------------------------------------------
// CBM GCR Serial Encoder
// Encodes data bit-by-bit for direct flux output
// Handles the 4-byte to 5-byte (40-bit) group encoding
//-----------------------------------------------------------------------------

module gcr_cbm_encoder_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_clk,        // Bit clock
    input  wire [7:0]  data_in,        // Byte to encode
    input  wire        data_valid,     // New byte available
    output reg         flux_out,       // Serial GCR encoded output
    output reg         flux_valid,     // Output bit valid
    output reg         byte_complete,  // Byte fully transmitted
    output reg         ready           // Ready for new byte
);

    reg [9:0]  shift_reg;
    reg [3:0]  bit_counter;   // Counts 0-9 (10 GCR bits per byte)
    reg        active;

    // GCR encode table lookup
    function [4:0] gcr_encode;
        input [3:0] nibble;
        begin
            case (nibble)
                4'h0: gcr_encode = 5'h0A;
                4'h1: gcr_encode = 5'h0B;
                4'h2: gcr_encode = 5'h12;
                4'h3: gcr_encode = 5'h13;
                4'h4: gcr_encode = 5'h0E;
                4'h5: gcr_encode = 5'h0F;
                4'h6: gcr_encode = 5'h16;
                4'h7: gcr_encode = 5'h17;
                4'h8: gcr_encode = 5'h09;
                4'h9: gcr_encode = 5'h19;
                4'hA: gcr_encode = 5'h1A;
                4'hB: gcr_encode = 5'h1B;
                4'hC: gcr_encode = 5'h0D;
                4'hD: gcr_encode = 5'h1D;
                4'hE: gcr_encode = 5'h1E;
                4'hF: gcr_encode = 5'h15;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            shift_reg     <= 10'h000;
            bit_counter   <= 4'd0;
            active        <= 1'b0;
            flux_out      <= 1'b0;
            flux_valid    <= 1'b0;
            byte_complete <= 1'b0;
            ready         <= 1'b1;
        end
        else if (enable) begin
            flux_valid    <= 1'b0;
            byte_complete <= 1'b0;

            if (data_valid && ready) begin
                // Load new byte, encode to GCR
                shift_reg   <= {gcr_encode(data_in[7:4]), gcr_encode(data_in[3:0])};
                bit_counter <= 4'd0;
                active      <= 1'b1;
                ready       <= 1'b0;
            end
            else if (active && bit_clk) begin
                // Output MSB first
                flux_out    <= shift_reg[9];
                flux_valid  <= 1'b1;
                shift_reg   <= {shift_reg[8:0], 1'b0};
                bit_counter <= bit_counter + 1'b1;

                if (bit_counter == 4'd9) begin
                    // All 10 bits transmitted
                    active        <= 1'b0;
                    byte_complete <= 1'b1;
                    ready         <= 1'b1;
                end
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// CBM GCR Serial Decoder
// Decodes serial GCR flux transitions to bytes
//-----------------------------------------------------------------------------

module gcr_cbm_decoder_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_clk,        // Bit clock from DPLL
    input  wire        flux_in,        // Serial GCR encoded input
    input  wire        flux_valid,     // Input bit valid
    output reg  [7:0]  data_out,       // Decoded byte
    output reg         data_valid,     // Byte complete
    output reg         decode_error    // Invalid GCR pattern
);

    reg [9:0]  shift_reg;
    reg [3:0]  bit_counter;   // Counts 0-9

    // GCR decode table lookup with error detection
    function [4:0] gcr_decode;  // [4] = error, [3:0] = data
        input [4:0] quintet;
        begin
            case (quintet)
                5'h0A: gcr_decode = 5'b00000;
                5'h0B: gcr_decode = 5'b00001;
                5'h12: gcr_decode = 5'b00010;
                5'h13: gcr_decode = 5'b00011;
                5'h0E: gcr_decode = 5'b00100;
                5'h0F: gcr_decode = 5'b00101;
                5'h16: gcr_decode = 5'b00110;
                5'h17: gcr_decode = 5'b00111;
                5'h09: gcr_decode = 5'b01000;
                5'h19: gcr_decode = 5'b01001;
                5'h1A: gcr_decode = 5'b01010;
                5'h1B: gcr_decode = 5'b01011;
                5'h0D: gcr_decode = 5'b01100;
                5'h1D: gcr_decode = 5'b01101;
                5'h1E: gcr_decode = 5'b01110;
                5'h15: gcr_decode = 5'b01111;
                default: gcr_decode = 5'b10000;
            endcase
        end
    endfunction

    wire [4:0] high_nibble = gcr_decode(shift_reg[9:5]);
    wire [4:0] low_nibble  = gcr_decode({shift_reg[4:1], flux_in});

    always @(posedge clk) begin
        if (reset) begin
            shift_reg    <= 10'h000;
            bit_counter  <= 4'd0;
            data_out     <= 8'h00;
            data_valid   <= 1'b0;
            decode_error <= 1'b0;
        end
        else if (enable) begin
            data_valid <= 1'b0;

            if (flux_valid && bit_clk) begin
                shift_reg   <= {shift_reg[8:0], flux_in};
                bit_counter <= bit_counter + 1'b1;

                if (bit_counter == 4'd9) begin
                    // 10 bits received, decode
                    data_out     <= {high_nibble[3:0], low_nibble[3:0]};
                    data_valid   <= 1'b1;
                    decode_error <= high_nibble[4] | low_nibble[4];
                    bit_counter  <= 4'd0;
                end
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// CBM Sync Mark Detector
// Detects CBM-specific sync marks (5x 0xFF = 10 consecutive 1s pattern)
//-----------------------------------------------------------------------------

module gcr_cbm_sync_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_in,         // Bit from DPLL
    input  wire        bit_valid,      // Bit valid
    output reg         sync_detected,  // Sync pattern detected
    output reg  [5:0]  sync_count      // Number of sync bytes detected
);

    // CBM uses sync marks: multiple 0xFF bytes which encode as
    // 10101 10101 (5 ones encoded as GCR creates this pattern)
    // Need to detect 10+ consecutive 1 bits

    reg [9:0]  shift_reg;
    reg [3:0]  one_count;     // Count of consecutive 1s

    always @(posedge clk) begin
        if (reset) begin
            shift_reg     <= 10'h000;
            one_count     <= 4'd0;
            sync_detected <= 1'b0;
            sync_count    <= 6'd0;
        end
        else if (enable && bit_valid) begin
            shift_reg <= {shift_reg[8:0], bit_in};

            if (bit_in) begin
                if (one_count < 4'd15)
                    one_count <= one_count + 1'b1;

                // Sync detected when we have 10+ consecutive 1s
                if (one_count >= 4'd9) begin
                    sync_detected <= 1'b1;
                    if (one_count == 4'd9 && sync_count < 6'd63)
                        sync_count <= sync_count + 1'b1;
                end
            end
            else begin
                one_count     <= 4'd0;
                sync_detected <= 1'b0;
            end
        end
    end

endmodule
