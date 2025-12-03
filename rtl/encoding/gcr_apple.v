//-----------------------------------------------------------------------------
// GCR Encoder/Decoder - Apple II Format
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Based on CAPSImg Codec/DiskEncoding.cpp gcr_apple5[] and gcr_apple6[] tables
// Apple DOS 3.2 uses 5-bit GCR (5&3 encoding): 5 bits -> 8 bits
// Apple DOS 3.3/ProDOS uses 6-bit GCR (6&2 encoding): 6 bits -> 8 bits
//
// Target: Xilinx Spartan UltraScale+ (UC+)
// Updated: 2025-12-03 12:10
//-----------------------------------------------------------------------------

//=============================================================================
// Apple DOS 3.3 / ProDOS 6-bit GCR (6&2 encoding)
// This is the more common format
//=============================================================================

module gcr_apple6_encoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [5:0]  data_in,        // 6-bit data to encode
    input  wire        data_valid,     // Input data valid
    output reg  [7:0]  encoded_out,    // GCR encoded output (8 bits)
    output reg         encoded_valid,  // Output valid
    output reg         busy            // Encoder busy
);

    //-------------------------------------------------------------------------
    // Apple 6-bit GCR Encoding Table (6-bit -> 8-bit)
    // From CAPSImg: gcr_apple6[] = {
    //   0x96, 0x97, 0x9a, 0x9b, 0x9d, 0x9e, 0x9f, 0xa6,
    //   0xa7, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb2, 0xb3,
    //   0xb4, 0xb5, 0xb6, 0xb7, 0xb9, 0xba, 0xbb, 0xbc,
    //   0xbd, 0xbe, 0xbf, 0xcb, 0xcd, 0xce, 0xcf, 0xd3,
    //   0xd6, 0xd7, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde,
    //   0xdf, 0xe5, 0xe6, 0xe7, 0xe9, 0xea, 0xeb, 0xec,
    //   0xed, 0xee, 0xef, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6,
    //   0xf7, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
    // }
    //-------------------------------------------------------------------------

    function [7:0] gcr6_encode;
        input [5:0] data;
        begin
            case (data)
                6'h00: gcr6_encode = 8'h96;
                6'h01: gcr6_encode = 8'h97;
                6'h02: gcr6_encode = 8'h9A;
                6'h03: gcr6_encode = 8'h9B;
                6'h04: gcr6_encode = 8'h9D;
                6'h05: gcr6_encode = 8'h9E;
                6'h06: gcr6_encode = 8'h9F;
                6'h07: gcr6_encode = 8'hA6;
                6'h08: gcr6_encode = 8'hA7;
                6'h09: gcr6_encode = 8'hAB;
                6'h0A: gcr6_encode = 8'hAC;
                6'h0B: gcr6_encode = 8'hAD;
                6'h0C: gcr6_encode = 8'hAE;
                6'h0D: gcr6_encode = 8'hAF;
                6'h0E: gcr6_encode = 8'hB2;
                6'h0F: gcr6_encode = 8'hB3;
                6'h10: gcr6_encode = 8'hB4;
                6'h11: gcr6_encode = 8'hB5;
                6'h12: gcr6_encode = 8'hB6;
                6'h13: gcr6_encode = 8'hB7;
                6'h14: gcr6_encode = 8'hB9;
                6'h15: gcr6_encode = 8'hBA;
                6'h16: gcr6_encode = 8'hBB;
                6'h17: gcr6_encode = 8'hBC;
                6'h18: gcr6_encode = 8'hBD;
                6'h19: gcr6_encode = 8'hBE;
                6'h1A: gcr6_encode = 8'hBF;
                6'h1B: gcr6_encode = 8'hCB;
                6'h1C: gcr6_encode = 8'hCD;
                6'h1D: gcr6_encode = 8'hCE;
                6'h1E: gcr6_encode = 8'hCF;
                6'h1F: gcr6_encode = 8'hD3;
                6'h20: gcr6_encode = 8'hD6;
                6'h21: gcr6_encode = 8'hD7;
                6'h22: gcr6_encode = 8'hD9;
                6'h23: gcr6_encode = 8'hDA;
                6'h24: gcr6_encode = 8'hDB;
                6'h25: gcr6_encode = 8'hDC;
                6'h26: gcr6_encode = 8'hDD;
                6'h27: gcr6_encode = 8'hDE;
                6'h28: gcr6_encode = 8'hDF;
                6'h29: gcr6_encode = 8'hE5;
                6'h2A: gcr6_encode = 8'hE6;
                6'h2B: gcr6_encode = 8'hE7;
                6'h2C: gcr6_encode = 8'hE9;
                6'h2D: gcr6_encode = 8'hEA;
                6'h2E: gcr6_encode = 8'hEB;
                6'h2F: gcr6_encode = 8'hEC;
                6'h30: gcr6_encode = 8'hED;
                6'h31: gcr6_encode = 8'hEE;
                6'h32: gcr6_encode = 8'hEF;
                6'h33: gcr6_encode = 8'hF2;
                6'h34: gcr6_encode = 8'hF3;
                6'h35: gcr6_encode = 8'hF4;
                6'h36: gcr6_encode = 8'hF5;
                6'h37: gcr6_encode = 8'hF6;
                6'h38: gcr6_encode = 8'hF7;
                6'h39: gcr6_encode = 8'hF9;
                6'h3A: gcr6_encode = 8'hFA;
                6'h3B: gcr6_encode = 8'hFB;
                6'h3C: gcr6_encode = 8'hFC;
                6'h3D: gcr6_encode = 8'hFD;
                6'h3E: gcr6_encode = 8'hFE;
                6'h3F: gcr6_encode = 8'hFF;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            encoded_out   <= 8'h00;
            encoded_valid <= 1'b0;
            busy          <= 1'b0;
        end
        else if (enable) begin
            encoded_valid <= 1'b0;

            if (data_valid && !busy) begin
                encoded_out   <= gcr6_encode(data_in);
                encoded_valid <= 1'b1;
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Apple 6-bit GCR Decoder
// Decodes 8-bit GCR data back to 6-bit data
//-----------------------------------------------------------------------------

module gcr_apple6_decoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [7:0]  encoded_in,     // GCR encoded input (8 bits)
    input  wire        encoded_valid,  // Input valid
    output reg  [5:0]  data_out,       // Decoded 6-bit data
    output reg         data_valid,     // Output valid
    output reg         decode_error    // Invalid GCR pattern detected
);

    //-------------------------------------------------------------------------
    // Apple 6-bit GCR Decoding (8-bit -> 6-bit)
    // Inverse lookup with error detection
    //-------------------------------------------------------------------------

    function [6:0] gcr6_decode;  // [6] = error flag, [5:0] = decoded data
        input [7:0] encoded;
        begin
            case (encoded)
                8'h96: gcr6_decode = 7'b0_000000;
                8'h97: gcr6_decode = 7'b0_000001;
                8'h9A: gcr6_decode = 7'b0_000010;
                8'h9B: gcr6_decode = 7'b0_000011;
                8'h9D: gcr6_decode = 7'b0_000100;
                8'h9E: gcr6_decode = 7'b0_000101;
                8'h9F: gcr6_decode = 7'b0_000110;
                8'hA6: gcr6_decode = 7'b0_000111;
                8'hA7: gcr6_decode = 7'b0_001000;
                8'hAB: gcr6_decode = 7'b0_001001;
                8'hAC: gcr6_decode = 7'b0_001010;
                8'hAD: gcr6_decode = 7'b0_001011;
                8'hAE: gcr6_decode = 7'b0_001100;
                8'hAF: gcr6_decode = 7'b0_001101;
                8'hB2: gcr6_decode = 7'b0_001110;
                8'hB3: gcr6_decode = 7'b0_001111;
                8'hB4: gcr6_decode = 7'b0_010000;
                8'hB5: gcr6_decode = 7'b0_010001;
                8'hB6: gcr6_decode = 7'b0_010010;
                8'hB7: gcr6_decode = 7'b0_010011;
                8'hB9: gcr6_decode = 7'b0_010100;
                8'hBA: gcr6_decode = 7'b0_010101;
                8'hBB: gcr6_decode = 7'b0_010110;
                8'hBC: gcr6_decode = 7'b0_010111;
                8'hBD: gcr6_decode = 7'b0_011000;
                8'hBE: gcr6_decode = 7'b0_011001;
                8'hBF: gcr6_decode = 7'b0_011010;
                8'hCB: gcr6_decode = 7'b0_011011;
                8'hCD: gcr6_decode = 7'b0_011100;
                8'hCE: gcr6_decode = 7'b0_011101;
                8'hCF: gcr6_decode = 7'b0_011110;
                8'hD3: gcr6_decode = 7'b0_011111;
                8'hD6: gcr6_decode = 7'b0_100000;
                8'hD7: gcr6_decode = 7'b0_100001;
                8'hD9: gcr6_decode = 7'b0_100010;
                8'hDA: gcr6_decode = 7'b0_100011;
                8'hDB: gcr6_decode = 7'b0_100100;
                8'hDC: gcr6_decode = 7'b0_100101;
                8'hDD: gcr6_decode = 7'b0_100110;
                8'hDE: gcr6_decode = 7'b0_100111;
                8'hDF: gcr6_decode = 7'b0_101000;
                8'hE5: gcr6_decode = 7'b0_101001;
                8'hE6: gcr6_decode = 7'b0_101010;
                8'hE7: gcr6_decode = 7'b0_101011;
                8'hE9: gcr6_decode = 7'b0_101100;
                8'hEA: gcr6_decode = 7'b0_101101;
                8'hEB: gcr6_decode = 7'b0_101110;
                8'hEC: gcr6_decode = 7'b0_101111;
                8'hED: gcr6_decode = 7'b0_110000;
                8'hEE: gcr6_decode = 7'b0_110001;
                8'hEF: gcr6_decode = 7'b0_110010;
                8'hF2: gcr6_decode = 7'b0_110011;
                8'hF3: gcr6_decode = 7'b0_110100;
                8'hF4: gcr6_decode = 7'b0_110101;
                8'hF5: gcr6_decode = 7'b0_110110;
                8'hF6: gcr6_decode = 7'b0_110111;
                8'hF7: gcr6_decode = 7'b0_111000;
                8'hF9: gcr6_decode = 7'b0_111001;
                8'hFA: gcr6_decode = 7'b0_111010;
                8'hFB: gcr6_decode = 7'b0_111011;
                8'hFC: gcr6_decode = 7'b0_111100;
                8'hFD: gcr6_decode = 7'b0_111101;
                8'hFE: gcr6_decode = 7'b0_111110;
                8'hFF: gcr6_decode = 7'b0_111111;
                default: gcr6_decode = 7'b1_000000;  // Error
            endcase
        end
    endfunction

    wire [6:0] decoded = gcr6_decode(encoded_in);

    always @(posedge clk) begin
        if (reset) begin
            data_out     <= 6'h00;
            data_valid   <= 1'b0;
            decode_error <= 1'b0;
        end
        else if (enable && encoded_valid) begin
            data_out     <= decoded[5:0];
            data_valid   <= 1'b1;
            decode_error <= decoded[6];
        end
        else begin
            data_valid <= 1'b0;
        end
    end

endmodule


//=============================================================================
// Apple DOS 3.2 5-bit GCR (5&3 encoding)
// Legacy format, less common
//=============================================================================

module gcr_apple5_encoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [4:0]  data_in,        // 5-bit data to encode
    input  wire        data_valid,     // Input data valid
    output reg  [7:0]  encoded_out,    // GCR encoded output (8 bits)
    output reg         encoded_valid,  // Output valid
    output reg         busy            // Encoder busy
);

    //-------------------------------------------------------------------------
    // Apple 5-bit GCR Encoding Table (5-bit -> 8-bit)
    // From CAPSImg: gcr_apple5[] = {
    //   0xab, 0xad, 0xae, 0xaf, 0xb5, 0xb6, 0xb7, 0xba,
    //   0xbb, 0xbd, 0xbe, 0xbf, 0xd6, 0xd7, 0xda, 0xdb,
    //   0xdd, 0xde, 0xdf, 0xea, 0xeb, 0xed, 0xee, 0xef,
    //   0xf5, 0xf6, 0xf7, 0xfa, 0xfb, 0xfd, 0xfe, 0xff
    // }
    //-------------------------------------------------------------------------

    function [7:0] gcr5_encode;
        input [4:0] data;
        begin
            case (data)
                5'h00: gcr5_encode = 8'hAB;
                5'h01: gcr5_encode = 8'hAD;
                5'h02: gcr5_encode = 8'hAE;
                5'h03: gcr5_encode = 8'hAF;
                5'h04: gcr5_encode = 8'hB5;
                5'h05: gcr5_encode = 8'hB6;
                5'h06: gcr5_encode = 8'hB7;
                5'h07: gcr5_encode = 8'hBA;
                5'h08: gcr5_encode = 8'hBB;
                5'h09: gcr5_encode = 8'hBD;
                5'h0A: gcr5_encode = 8'hBE;
                5'h0B: gcr5_encode = 8'hBF;
                5'h0C: gcr5_encode = 8'hD6;
                5'h0D: gcr5_encode = 8'hD7;
                5'h0E: gcr5_encode = 8'hDA;
                5'h0F: gcr5_encode = 8'hDB;
                5'h10: gcr5_encode = 8'hDD;
                5'h11: gcr5_encode = 8'hDE;
                5'h12: gcr5_encode = 8'hDF;
                5'h13: gcr5_encode = 8'hEA;
                5'h14: gcr5_encode = 8'hEB;
                5'h15: gcr5_encode = 8'hED;
                5'h16: gcr5_encode = 8'hEE;
                5'h17: gcr5_encode = 8'hEF;
                5'h18: gcr5_encode = 8'hF5;
                5'h19: gcr5_encode = 8'hF6;
                5'h1A: gcr5_encode = 8'hF7;
                5'h1B: gcr5_encode = 8'hFA;
                5'h1C: gcr5_encode = 8'hFB;
                5'h1D: gcr5_encode = 8'hFD;
                5'h1E: gcr5_encode = 8'hFE;
                5'h1F: gcr5_encode = 8'hFF;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            encoded_out   <= 8'h00;
            encoded_valid <= 1'b0;
            busy          <= 1'b0;
        end
        else if (enable) begin
            encoded_valid <= 1'b0;

            if (data_valid && !busy) begin
                encoded_out   <= gcr5_encode(data_in);
                encoded_valid <= 1'b1;
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Apple 5-bit GCR Decoder
//-----------------------------------------------------------------------------

module gcr_apple5_decoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [7:0]  encoded_in,     // GCR encoded input (8 bits)
    input  wire        encoded_valid,  // Input valid
    output reg  [4:0]  data_out,       // Decoded 5-bit data
    output reg         data_valid,     // Output valid
    output reg         decode_error    // Invalid GCR pattern detected
);

    function [5:0] gcr5_decode;  // [5] = error flag, [4:0] = decoded data
        input [7:0] encoded;
        begin
            case (encoded)
                8'hAB: gcr5_decode = 6'b0_00000;
                8'hAD: gcr5_decode = 6'b0_00001;
                8'hAE: gcr5_decode = 6'b0_00010;
                8'hAF: gcr5_decode = 6'b0_00011;
                8'hB5: gcr5_decode = 6'b0_00100;
                8'hB6: gcr5_decode = 6'b0_00101;
                8'hB7: gcr5_decode = 6'b0_00110;
                8'hBA: gcr5_decode = 6'b0_00111;
                8'hBB: gcr5_decode = 6'b0_01000;
                8'hBD: gcr5_decode = 6'b0_01001;
                8'hBE: gcr5_decode = 6'b0_01010;
                8'hBF: gcr5_decode = 6'b0_01011;
                8'hD6: gcr5_decode = 6'b0_01100;
                8'hD7: gcr5_decode = 6'b0_01101;
                8'hDA: gcr5_decode = 6'b0_01110;
                8'hDB: gcr5_decode = 6'b0_01111;
                8'hDD: gcr5_decode = 6'b0_10000;
                8'hDE: gcr5_decode = 6'b0_10001;
                8'hDF: gcr5_decode = 6'b0_10010;
                8'hEA: gcr5_decode = 6'b0_10011;
                8'hEB: gcr5_decode = 6'b0_10100;
                8'hED: gcr5_decode = 6'b0_10101;
                8'hEE: gcr5_decode = 6'b0_10110;
                8'hEF: gcr5_decode = 6'b0_10111;
                8'hF5: gcr5_decode = 6'b0_11000;
                8'hF6: gcr5_decode = 6'b0_11001;
                8'hF7: gcr5_decode = 6'b0_11010;
                8'hFA: gcr5_decode = 6'b0_11011;
                8'hFB: gcr5_decode = 6'b0_11100;
                8'hFD: gcr5_decode = 6'b0_11101;
                8'hFE: gcr5_decode = 6'b0_11110;
                8'hFF: gcr5_decode = 6'b0_11111;
                default: gcr5_decode = 6'b1_00000;  // Error
            endcase
        end
    endfunction

    wire [5:0] decoded = gcr5_decode(encoded_in);

    always @(posedge clk) begin
        if (reset) begin
            data_out     <= 5'h00;
            data_valid   <= 1'b0;
            decode_error <= 1'b0;
        end
        else if (enable && encoded_valid) begin
            data_out     <= decoded[4:0];
            data_valid   <= 1'b1;
            decode_error <= decoded[5];
        end
        else begin
            data_valid <= 1'b0;
        end
    end

endmodule


//=============================================================================
// Apple Sync/Prologue Detector
// Detects Apple II disk structure markers
//=============================================================================

module apple_sync_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [7:0]  byte_in,        // Decoded byte
    input  wire        byte_valid,     // Byte valid
    output reg         addr_prologue,  // Address prologue detected (D5 AA 96)
    output reg         data_prologue,  // Data prologue detected (D5 AA AD)
    output reg         epilogue,       // Epilogue detected (DE AA EB)
    output reg  [2:0]  sync_state      // Current sync state
);

    // Apple II disk field markers
    localparam MARK_D5 = 8'hD5;
    localparam MARK_AA = 8'hAA;
    localparam MARK_96 = 8'h96;  // Address field
    localparam MARK_AD = 8'hAD;  // Data field
    localparam MARK_DE = 8'hDE;
    localparam MARK_EB = 8'hEB;

    // State machine
    localparam S_IDLE      = 3'd0;
    localparam S_D5_SEEN   = 3'd1;
    localparam S_AA_SEEN   = 3'd2;
    localparam S_DE_SEEN   = 3'd3;
    localparam S_DE_AA     = 3'd4;

    reg [7:0] prev_byte;
    reg [7:0] prev_prev_byte;

    always @(posedge clk) begin
        if (reset) begin
            sync_state    <= S_IDLE;
            addr_prologue <= 1'b0;
            data_prologue <= 1'b0;
            epilogue      <= 1'b0;
            prev_byte     <= 8'h00;
            prev_prev_byte <= 8'h00;
        end
        else if (enable) begin
            addr_prologue <= 1'b0;
            data_prologue <= 1'b0;
            epilogue      <= 1'b0;

            if (byte_valid) begin
                prev_prev_byte <= prev_byte;
                prev_byte      <= byte_in;

                case (sync_state)
                    S_IDLE: begin
                        if (byte_in == MARK_D5)
                            sync_state <= S_D5_SEEN;
                        else if (byte_in == MARK_DE)
                            sync_state <= S_DE_SEEN;
                    end

                    S_D5_SEEN: begin
                        if (byte_in == MARK_AA)
                            sync_state <= S_AA_SEEN;
                        else if (byte_in == MARK_D5)
                            sync_state <= S_D5_SEEN;
                        else
                            sync_state <= S_IDLE;
                    end

                    S_AA_SEEN: begin
                        if (byte_in == MARK_96) begin
                            addr_prologue <= 1'b1;
                            sync_state    <= S_IDLE;
                        end
                        else if (byte_in == MARK_AD) begin
                            data_prologue <= 1'b1;
                            sync_state    <= S_IDLE;
                        end
                        else if (byte_in == MARK_D5)
                            sync_state <= S_D5_SEEN;
                        else
                            sync_state <= S_IDLE;
                    end

                    S_DE_SEEN: begin
                        if (byte_in == MARK_AA)
                            sync_state <= S_DE_AA;
                        else if (byte_in == MARK_D5)
                            sync_state <= S_D5_SEEN;
                        else
                            sync_state <= S_IDLE;
                    end

                    S_DE_AA: begin
                        if (byte_in == MARK_EB) begin
                            epilogue   <= 1'b1;
                            sync_state <= S_IDLE;
                        end
                        else if (byte_in == MARK_D5)
                            sync_state <= S_D5_SEEN;
                        else
                            sync_state <= S_IDLE;
                    end

                    default: sync_state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
