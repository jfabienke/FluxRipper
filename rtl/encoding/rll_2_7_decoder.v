//-----------------------------------------------------------------------------
// RLL(2,7) Decoder for ST-506 Hard Drives
//
// Decodes Run-Length Limited (2,7) encoded data back to original bytes
// Used for reading ST-506 RLL formatted hard drives
//
// Decoding process:
//   - 4 code bits → 2 data bits (primary patterns)
//   - 6 code bits → 3 data bits (extended patterns)
//   - Context-aware for edge cases
//
// Reference: IBM 3370 disk format
//
// Created: 2025-12-03 16:15
//-----------------------------------------------------------------------------

module rll_2_7_decoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Encoded input (from DPLL/data separator)
    input  wire        code_bit,         // Serial encoded bit input
    input  wire        code_valid,       // Input bit valid (from sample_point)

    // Decoded output
    output reg  [7:0]  data_out,         // Decoded data byte
    output reg         data_valid,       // Output byte valid
    output reg         sync_detected,    // Sync pattern found
    output reg         decode_error      // Decoding error (constraint violation)
);

    //-------------------------------------------------------------------------
    // RLL(2,7) Decoding Table
    //-------------------------------------------------------------------------
    // Primary 4-bit to 2-bit mappings:
    //   1000 → 00
    //   0100 → 01
    //   0010 → 10 (context A)
    //   1001 → 10 (context B) or 11
    //
    // Extended 6-bit to 3-bit mappings:
    //   000100 → 000
    //   100100 → 010
    //   001000 → 011
    //   100010 → 100 (context A)
    //   001001 → 100 (context B) or 110

    // Shift register for incoming code bits
    reg [11:0] code_shift;
    reg [3:0]  code_count;

    // Decoded data accumulator
    reg [7:0]  decode_buffer;
    reg [3:0]  decode_count;

    // State machine
    localparam [2:0]
        STATE_HUNT     = 3'd0,    // Looking for sync
        STATE_DECODE   = 3'd1,    // Normal decoding
        STATE_CHECK_6  = 3'd2,    // Check for 6-bit pattern
        STATE_OUTPUT   = 3'd3,
        STATE_ERROR    = 3'd4;

    reg [2:0] state;

    // Constraint tracking
    reg [2:0] zeros_count;        // Consecutive zeros seen
    reg       prev_was_one;

    // Decode results (declared at module level for Verilog compatibility)
    reg [2:0] result_4;
    reg [3:0] result_6;

    //-------------------------------------------------------------------------
    // 4-bit Pattern Lookup
    //-------------------------------------------------------------------------
    function [2:0] decode_4bit;
        input [3:0] pattern;
        // Returns {valid, data[1:0]}
        begin
            case (pattern)
                4'b1000: decode_4bit = 3'b100;  // Valid, 00
                4'b0100: decode_4bit = 3'b101;  // Valid, 01
                4'b0010: decode_4bit = 3'b110;  // Valid, 10
                4'b1001: decode_4bit = 3'b111;  // Valid, 11 (or 10 in context)
                default: decode_4bit = 3'b000;  // Invalid / need more bits
            endcase
        end
    endfunction

    //-------------------------------------------------------------------------
    // 6-bit Pattern Lookup
    //-------------------------------------------------------------------------
    function [3:0] decode_6bit;
        input [5:0] pattern;
        // Returns {valid, data[2:0]}
        begin
            case (pattern)
                6'b000100: decode_6bit = 4'b1000;  // Valid, 000
                6'b100100: decode_6bit = 4'b1010;  // Valid, 010
                6'b001000: decode_6bit = 4'b1011;  // Valid, 011
                6'b100010: decode_6bit = 4'b1100;  // Valid, 100
                6'b001001: decode_6bit = 4'b1110;  // Valid, 110
                6'b010010: decode_6bit = 4'b1101;  // Valid, 101
                6'b100001: decode_6bit = 4'b1111;  // Valid, 111
                default:   decode_6bit = 4'b0000;  // Invalid
            endcase
        end
    endfunction

    //-------------------------------------------------------------------------
    // Sync Pattern Detection
    //-------------------------------------------------------------------------
    // RLL sync pattern: sequence of specific encoded bytes
    // Typically looks for 0x00 bytes encoded as repeating 1000 pattern
    wire sync_match;
    assign sync_match = (code_shift[11:0] == 12'b1000_1000_1000);

    //-------------------------------------------------------------------------
    // Main Decoder Logic
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_HUNT;
            code_shift <= 12'd0;
            code_count <= 4'd0;
            decode_buffer <= 8'd0;
            decode_count <= 4'd0;
            data_out <= 8'd0;
            data_valid <= 1'b0;
            sync_detected <= 1'b0;
            decode_error <= 1'b0;
            zeros_count <= 3'd0;
            prev_was_one <= 1'b0;
        end else if (enable) begin
            data_valid <= 1'b0;
            sync_detected <= 1'b0;
            decode_error <= 1'b0;

            if (code_valid) begin
                // Shift in new code bit
                code_shift <= {code_shift[10:0], code_bit};
                code_count <= code_count + 1;

                // Track consecutive zeros for constraint checking
                if (code_bit) begin
                    // Check (2,7) constraint: minimum 2 zeros between 1s
                    if (prev_was_one || (zeros_count < 3'd2 && zeros_count > 0)) begin
                        // Constraint violation (less than 2 zeros between 1s)
                        // Note: zeros_count includes the current position
                        if (zeros_count > 0 && zeros_count < 3'd2) begin
                            decode_error <= 1'b1;
                        end
                    end
                    zeros_count <= 3'd0;
                    prev_was_one <= 1'b1;
                end else begin
                    zeros_count <= (zeros_count < 3'd7) ? zeros_count + 1 : 3'd7;
                    prev_was_one <= 1'b0;

                    // Check maximum constraint: no more than 7 zeros
                    if (zeros_count >= 3'd7) begin
                        decode_error <= 1'b1;
                    end
                end
            end

            case (state)
                //-------------------------------------------------------------
                STATE_HUNT: begin
                    // Hunt for sync pattern
                    if (sync_match && code_count >= 4'd12) begin
                        sync_detected <= 1'b1;
                        code_count <= 4'd0;
                        decode_count <= 4'd0;
                        state <= STATE_DECODE;
                    end
                end

                //-------------------------------------------------------------
                STATE_DECODE: begin
                    // Try to decode accumulated bits
                    if (code_count >= 4'd4) begin
                        // First try 4-bit decode
                        result_4 = decode_4bit(code_shift[3:0]);

                        if (result_4[2]) begin
                            // Valid 4-bit pattern
                            decode_buffer <= {decode_buffer[5:0], result_4[1:0]};
                            decode_count <= decode_count + 4'd2;
                            code_count <= code_count - 4'd4;

                            if (decode_count >= 4'd6) begin
                                state <= STATE_OUTPUT;
                            end
                        end else if (code_count >= 4'd6) begin
                            // Try 6-bit decode
                            state <= STATE_CHECK_6;
                        end
                        // else: need more bits, stay in decode
                    end
                end

                //-------------------------------------------------------------
                STATE_CHECK_6: begin
                    result_6 = decode_6bit(code_shift[5:0]);

                    if (result_6[3]) begin
                        // Valid 6-bit pattern
                        decode_buffer <= {decode_buffer[4:0], result_6[2:0]};
                        decode_count <= decode_count + 4'd3;
                        code_count <= code_count - 4'd6;

                        if (decode_count >= 4'd5) begin
                            state <= STATE_OUTPUT;
                        end else begin
                            state <= STATE_DECODE;
                        end
                    end else begin
                        // Neither 4-bit nor 6-bit valid - error or resync needed
                        decode_error <= 1'b1;
                        state <= STATE_HUNT;
                    end
                end

                //-------------------------------------------------------------
                STATE_OUTPUT: begin
                    // Output completed byte
                    if (decode_count >= 4'd8) begin
                        data_out <= decode_buffer;
                        data_valid <= 1'b1;
                        decode_buffer <= 8'd0;
                        decode_count <= decode_count - 4'd8;
                    end
                    state <= STATE_DECODE;
                end

                //-------------------------------------------------------------
                STATE_ERROR: begin
                    // Error recovery - hunt for next sync
                    decode_error <= 1'b1;
                    code_count <= 4'd0;
                    decode_count <= 4'd0;
                    state <= STATE_HUNT;
                end

                default: state <= STATE_HUNT;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// RLL(2,7) Address Mark Detector
// Detects sector address marks in RLL encoded data stream
//-----------------------------------------------------------------------------
module rll_2_7_am_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        code_bit,
    input  wire        code_valid,

    output reg         id_mark,          // ID address mark detected (sector header)
    output reg         data_mark,        // Data address mark detected
    output reg         deleted_mark      // Deleted data mark detected
);

    //-------------------------------------------------------------------------
    // RLL Address Mark Patterns
    //-------------------------------------------------------------------------
    // ST-506 RLL uses specific patterns that would be illegal in normal data
    // to mark sector boundaries. These patterns intentionally violate the
    // (2,7) constraint in a controlled way.
    //
    // Common patterns (drive/controller specific):
    //   ID Address Mark:      0x5224 encoded → specific bit pattern
    //   Data Address Mark:    0x4489 encoded
    //   Deleted Data Mark:    0x4481 encoded

    // 24-bit shift register for pattern detection
    reg [23:0] pattern_shift;

    // Address mark patterns (example - actual patterns vary by controller)
    localparam [23:0] AM_ID_PATTERN      = 24'h522452;
    localparam [23:0] AM_DATA_PATTERN    = 24'h448944;
    localparam [23:0] AM_DELETED_PATTERN = 24'h448144;

    always @(posedge clk) begin
        if (reset) begin
            pattern_shift <= 24'd0;
            id_mark <= 1'b0;
            data_mark <= 1'b0;
            deleted_mark <= 1'b0;
        end else if (enable && code_valid) begin
            // Shift in new bit
            pattern_shift <= {pattern_shift[22:0], code_bit};

            // Default outputs
            id_mark <= 1'b0;
            data_mark <= 1'b0;
            deleted_mark <= 1'b0;

            // Check for address marks
            if (pattern_shift == AM_ID_PATTERN) begin
                id_mark <= 1'b1;
            end else if (pattern_shift == AM_DATA_PATTERN) begin
                data_mark <= 1'b1;
            end else if (pattern_shift == AM_DELETED_PATTERN) begin
                deleted_mark <= 1'b1;
            end
        end
    end

endmodule
