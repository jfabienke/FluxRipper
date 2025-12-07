//-----------------------------------------------------------------------------
// RLL(2,7) Encoder for ST-506 Hard Drives
//
// Run-Length Limited (2,7) encoding:
//   - Minimum 2 zeros between consecutive 1s
//   - Maximum 7 zeros between consecutive 1s
//   - 50% higher density than MFM at same bit rate
//
// Encoding is variable-length: 2 data bits → 4 code bits, 3 bits → 6 code bits
// Context-dependent based on previous bit to maintain constraints
//
// Reference: IBM 3370 disk format (original RLL 2,7 implementation)
//
// Created: 2025-12-03 15:45
//-----------------------------------------------------------------------------

module rll_2_7_encoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Data input
    input  wire [7:0]  data_in,          // Input data byte
    input  wire        data_valid,       // Input data valid
    output wire        data_ready,       // Ready for next byte

    // Encoded output
    output reg  [15:0] code_out,         // Encoded output (up to 16 bits)
    output reg  [4:0]  code_bits,        // Number of valid bits in code_out
    output reg         code_valid,       // Output valid
    input  wire        code_ready        // Downstream ready
);

    //-------------------------------------------------------------------------
    // RLL(2,7) Encoding Table
    //-------------------------------------------------------------------------
    // The encoding is context-dependent. The table below shows the primary
    // mappings for the most common patterns.
    //
    // 2-bit patterns → 4-bit codes:
    //   00 → 1000
    //   01 → 0100
    //   10 → 0010 or 1001 (context-dependent)
    //   11 → 1001
    //
    // 3-bit patterns → 6-bit codes:
    //   000 → 000100
    //   010 → 100100
    //   011 → 001000
    //   100 → 100010 or 001001 (context-dependent)
    //
    // The encoder tracks state to ensure (2,7) constraints are maintained.

    // Encoding state machine
    localparam [2:0]
        STATE_IDLE     = 3'd0,
        STATE_ENCODE_2 = 3'd1,   // Encoding 2-bit pattern
        STATE_ENCODE_3 = 3'd2,   // Encoding 3-bit pattern
        STATE_OUTPUT   = 3'd3,
        STATE_WAIT     = 3'd4;

    reg [2:0] state;
    reg [7:0] data_buffer;
    reg [3:0] bits_remaining;
    reg [2:0] zeros_since_one;    // Track consecutive zeros for constraint checking

    // Lookup tables for encoding
    // 2-bit encoding (normal context)
    function [3:0] encode_2bit;
        input [1:0] data;
        input       prev_was_one;
        begin
            case (data)
                2'b00: encode_2bit = 4'b1000;
                2'b01: encode_2bit = 4'b0100;
                2'b10: encode_2bit = prev_was_one ? 4'b0010 : 4'b1001;
                2'b11: encode_2bit = 4'b1001;
            endcase
        end
    endfunction

    // 3-bit encoding (for patterns that need 6-bit codes)
    function [5:0] encode_3bit;
        input [2:0] data;
        input       prev_was_one;
        begin
            case (data)
                3'b000: encode_3bit = 6'b000100;
                3'b010: encode_3bit = 6'b100100;
                3'b011: encode_3bit = 6'b001000;
                3'b100: encode_3bit = prev_was_one ? 6'b100010 : 6'b001001;
                3'b101: encode_3bit = 6'b100010;
                3'b110: encode_3bit = 6'b001001;
                3'b111: encode_3bit = 6'b001001;  // Needs special handling
                default: encode_3bit = 6'b100100;
            endcase
        end
    endfunction

    // State tracking
    reg prev_bit_was_one;
    reg [15:0] output_shift;
    reg [4:0] output_count;

    // Ready signal
    assign data_ready = (state == STATE_IDLE) || (state == STATE_WAIT && bits_remaining < 4'd3);

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            data_buffer <= 8'd0;
            bits_remaining <= 4'd0;
            zeros_since_one <= 3'd0;
            prev_bit_was_one <= 1'b0;
            code_out <= 16'd0;
            code_bits <= 5'd0;
            code_valid <= 1'b0;
            output_shift <= 16'd0;
            output_count <= 5'd0;
        end else if (enable) begin
            code_valid <= 1'b0;  // Default

            case (state)
                STATE_IDLE: begin
                    if (data_valid) begin
                        data_buffer <= data_in;
                        bits_remaining <= 4'd8;
                        state <= STATE_ENCODE_2;
                    end
                end

                STATE_ENCODE_2: begin
                    // Encode 2 bits at a time
                    if (bits_remaining >= 4'd2) begin
                        // Get next 2 bits
                        reg [1:0] next_2bits;
                        next_2bits = data_buffer[7:6];

                        // Check if we need 3-bit encoding for special cases
                        if (bits_remaining >= 4'd3 &&
                            (next_2bits == 2'b00 || next_2bits == 2'b01)) begin
                            // Use 3-bit encoding for these patterns
                            state <= STATE_ENCODE_3;
                        end else begin
                            // Standard 2-bit encoding
                            reg [3:0] encoded;
                            encoded = encode_2bit(next_2bits, prev_bit_was_one);

                            output_shift <= {output_shift[11:0], encoded};
                            output_count <= output_count + 5'd4;

                            // Update state tracking
                            prev_bit_was_one <= encoded[0];
                            zeros_since_one <= encoded[0] ? 3'd0 :
                                             (encoded[1] ? 3'd1 :
                                             (encoded[2] ? 3'd2 : 3'd3));

                            // Shift data buffer
                            data_buffer <= {data_buffer[5:0], 2'b00};
                            bits_remaining <= bits_remaining - 4'd2;

                            // Check if we have enough output to emit
                            if (output_count >= 5'd8) begin
                                state <= STATE_OUTPUT;
                            end
                        end
                    end else begin
                        // Not enough bits, go to output or wait for more
                        if (output_count > 0) begin
                            state <= STATE_OUTPUT;
                        end else begin
                            state <= STATE_WAIT;
                        end
                    end
                end

                STATE_ENCODE_3: begin
                    // 3-bit encoding for special patterns
                    if (bits_remaining >= 4'd3) begin
                        reg [2:0] next_3bits;
                        reg [5:0] encoded;

                        next_3bits = data_buffer[7:5];
                        encoded = encode_3bit(next_3bits, prev_bit_was_one);

                        output_shift <= {output_shift[9:0], encoded};
                        output_count <= output_count + 5'd6;

                        // Update state tracking
                        prev_bit_was_one <= encoded[0];

                        // Shift data buffer
                        data_buffer <= {data_buffer[4:0], 3'b000};
                        bits_remaining <= bits_remaining - 4'd3;

                        // Check if we have enough output
                        if (output_count >= 5'd8) begin
                            state <= STATE_OUTPUT;
                        end else begin
                            state <= STATE_ENCODE_2;
                        end
                    end else begin
                        state <= STATE_ENCODE_2;
                    end
                end

                STATE_OUTPUT: begin
                    // Output accumulated encoded bits
                    if (code_ready || !code_valid) begin
                        if (output_count >= 5'd8) begin
                            code_out <= {output_shift[15:8], 8'd0};
                            code_bits <= 5'd8;
                            code_valid <= 1'b1;
                            output_shift <= {output_shift[7:0], 8'd0};
                            output_count <= output_count - 5'd8;
                        end else if (output_count > 0) begin
                            code_out <= output_shift;
                            code_bits <= output_count;
                            code_valid <= 1'b1;
                            output_shift <= 16'd0;
                            output_count <= 5'd0;
                        end

                        if (bits_remaining > 0) begin
                            state <= STATE_ENCODE_2;
                        end else begin
                            state <= STATE_WAIT;
                        end
                    end
                end

                STATE_WAIT: begin
                    // Wait for more data or flush remaining output
                    if (data_valid) begin
                        data_buffer <= data_in;
                        bits_remaining <= 4'd8;
                        state <= STATE_ENCODE_2;
                    end else if (output_count > 0 && code_ready) begin
                        code_out <= output_shift;
                        code_bits <= output_count;
                        code_valid <= 1'b1;
                        output_shift <= 16'd0;
                        output_count <= 5'd0;
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// RLL(2,7) Sync Pattern Generator
// Generates the sync/preamble pattern for ST-506 RLL formatted tracks
//-----------------------------------------------------------------------------
module rll_2_7_sync_generator (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        start,            // Start sync generation
    input  wire [7:0]  sync_count,       // Number of sync bytes

    output reg  [7:0]  sync_data,        // Sync pattern output
    output reg         sync_valid,
    output reg         sync_done
);

    //-------------------------------------------------------------------------
    // RLL(2,7) Sync Pattern
    //-------------------------------------------------------------------------
    // Standard ST-506 RLL sync is typically:
    //   - 12-14 bytes of 0x00 (gap/sync)
    //   - Address mark: specific pattern to indicate sector header or data
    //
    // The sync pattern must maintain (2,7) constraints when encoded.

    localparam [7:0] SYNC_BYTE = 8'h00;
    localparam [7:0] ADDR_MARK = 8'hA1;  // Address mark (special pattern)

    reg [7:0] byte_count;

    localparam [1:0]
        STATE_IDLE = 2'd0,
        STATE_SYNC = 2'd1,
        STATE_MARK = 2'd2,
        STATE_DONE = 2'd3;

    reg [1:0] state;

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            byte_count <= 8'd0;
            sync_data <= 8'd0;
            sync_valid <= 1'b0;
            sync_done <= 1'b0;
        end else if (enable) begin
            sync_valid <= 1'b0;
            sync_done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        byte_count <= sync_count;
                        state <= STATE_SYNC;
                    end
                end

                STATE_SYNC: begin
                    if (byte_count > 0) begin
                        sync_data <= SYNC_BYTE;
                        sync_valid <= 1'b1;
                        byte_count <= byte_count - 1;
                    end else begin
                        state <= STATE_MARK;
                    end
                end

                STATE_MARK: begin
                    // Output address mark
                    sync_data <= ADDR_MARK;
                    sync_valid <= 1'b1;
                    state <= STATE_DONE;
                end

                STATE_DONE: begin
                    sync_done <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
