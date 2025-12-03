//-----------------------------------------------------------------------------
// M2FM (Modified Modified FM) Encoder/Decoder Module
// FluxRipper - FPGA-based Floppy Disk Controller
//
// M2FM encoding used by:
//   - DEC RX01/RX02 (PDP-11, VAX)
//   - Intel MDS (Microprocessor Development System)
//   - Cromemco
//   - Some early CP/M systems
//
// M2FM is similar to MFM but with inverted clock rules:
//   - Clock bit is 1 ONLY if both previous and current data bits are 0
//   - This is the inverse of MFM where clock=1 when prev_data=0 AND cur_data=0
//
// Sync mark: 0xF77A (vs MFM's 0x4489)
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-03 23:35
//-----------------------------------------------------------------------------

module m2fm_encoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [7:0]  data_in,        // Byte to encode
    input  wire        data_valid,     // Input data valid
    output reg  [15:0] encoded_out,    // M2FM encoded output (16 bits)
    output reg         encoded_valid,  // Output valid
    output reg         busy            // Encoder busy
);

    //-------------------------------------------------------------------------
    // M2FM Encoding Logic
    // Each input bit becomes 2 output bits: clock + data
    // Clock = 1 ONLY when prev_data=0 AND cur_data=0
    // (Inverse of MFM clock rule)
    //-------------------------------------------------------------------------

    reg [7:0] data_reg;
    reg       prev_bit;       // Previous data bit (for clock generation)
    reg       processing;

    // M2FM encoding function
    // Clock bit is 1 when both previous and current data bits are 0
    function [15:0] m2fm_encode_byte;
        input [7:0] data;
        input       prev_data;
        integer i;
        reg [15:0] result;
        reg        prev;
        reg        clock_bit;
        begin
            result = 16'h0000;
            prev = prev_data;
            for (i = 7; i >= 0; i = i - 1) begin
                result = result << 2;
                // M2FM: Clock=1 only if prev=0 AND current=0
                clock_bit = (~prev) & (~data[i]);
                result = result | {clock_bit, data[i]};
                prev = data[i];
            end
            m2fm_encode_byte = result;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            encoded_out   <= 16'h0000;
            encoded_valid <= 1'b0;
            busy          <= 1'b0;
            processing    <= 1'b0;
            data_reg      <= 8'h00;
            prev_bit      <= 1'b0;
        end
        else if (enable) begin
            encoded_valid <= 1'b0;

            if (data_valid && !processing) begin
                // Start encoding new byte
                data_reg   <= data_in;
                processing <= 1'b1;
                busy       <= 1'b1;
            end
            else if (processing) begin
                // Complete encoding in one cycle
                encoded_out   <= m2fm_encode_byte(data_reg, prev_bit);
                encoded_valid <= 1'b1;
                processing    <= 1'b0;
                busy          <= 1'b0;
                prev_bit      <= data_reg[0];  // Save LSB for next byte
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// M2FM Decoder
// Decodes 16-bit M2FM data back to 8-bit byte
// Extracts data bits, validates clock bits according to M2FM rules
//-----------------------------------------------------------------------------

module m2fm_decoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [15:0] encoded_in,     // M2FM encoded input (16 bits)
    input  wire        encoded_valid,  // Input valid
    input  wire        prev_data_bit,  // Previous data bit for clock validation
    output reg  [7:0]  data_out,       // Decoded byte
    output reg         data_valid,     // Output valid
    output reg         decode_error    // Clock pattern error detected
);

    //-------------------------------------------------------------------------
    // M2FM Decoding Logic
    // Extract data bits from even positions (0, 2, 4, 6, 8, 10, 12, 14)
    // Clock bits at odd positions should follow M2FM rule
    //-------------------------------------------------------------------------

    // Extract data bits (same as MFM - data at even positions in cell)
    function [7:0] m2fm_decode_word;
        input [15:0] encoded;
        reg [7:0] result;
        begin
            // Data bits are at positions 0, 2, 4, 6, 8, 10, 12, 14
            result[7] = encoded[14];
            result[6] = encoded[12];
            result[5] = encoded[10];
            result[4] = encoded[8];
            result[3] = encoded[6];
            result[2] = encoded[4];
            result[1] = encoded[2];
            result[0] = encoded[0];
            m2fm_decode_word = result;
        end
    endfunction

    // Validate M2FM clock pattern
    // Clock=1 only when prev_data=0 AND cur_data=0
    function clock_pattern_valid;
        input [15:0] encoded;
        input        prev;
        reg [7:0] data;
        reg       valid;
        reg       expected_clk;
        reg       actual_clk;
        reg       p;
        integer   i;
        begin
            data = {encoded[14], encoded[12], encoded[10], encoded[8],
                    encoded[6],  encoded[4],  encoded[2],  encoded[0]};
            valid = 1'b1;
            p = prev;
            for (i = 7; i >= 0; i = i - 1) begin
                expected_clk = (~p) & (~data[i]);
                actual_clk = encoded[i*2 + 1];  // Clock at odd positions
                if (expected_clk != actual_clk)
                    valid = 1'b0;
                p = data[i];
            end
            clock_pattern_valid = valid;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            data_out     <= 8'h00;
            data_valid   <= 1'b0;
            decode_error <= 1'b0;
        end
        else if (enable && encoded_valid) begin
            data_out     <= m2fm_decode_word(encoded_in);
            data_valid   <= 1'b1;
            decode_error <= ~clock_pattern_valid(encoded_in, prev_data_bit);
        end
        else begin
            data_valid <= 1'b0;
        end
    end

endmodule


//-----------------------------------------------------------------------------
// M2FM Serial Encoder
// Encodes data bit-by-bit for direct flux output
//-----------------------------------------------------------------------------

module m2fm_encoder_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_clk,        // Bit clock (2x data rate)
    input  wire [7:0]  data_in,        // Byte to encode
    input  wire        data_valid,     // New byte available
    output reg         flux_out,       // Serial M2FM encoded output
    output reg         flux_valid,     // Output bit valid
    output reg         byte_complete,  // Byte fully transmitted
    output reg         ready           // Ready for new byte
);

    reg [7:0]  shift_reg;
    reg [3:0]  bit_counter;   // Counts 0-15 (8 data bits * 2 = 16 M2FM bits)
    reg        clock_phase;   // 0=clock bit, 1=data bit
    reg        active;
    reg        prev_data;     // Previous data bit for clock calculation

    always @(posedge clk) begin
        if (reset) begin
            shift_reg     <= 8'h00;
            bit_counter   <= 4'd0;
            clock_phase   <= 1'b0;
            active        <= 1'b0;
            flux_out      <= 1'b0;
            flux_valid    <= 1'b0;
            byte_complete <= 1'b0;
            ready         <= 1'b1;
            prev_data     <= 1'b0;
        end
        else if (enable) begin
            flux_valid    <= 1'b0;
            byte_complete <= 1'b0;

            if (data_valid && ready) begin
                // Load new byte
                shift_reg   <= data_in;
                bit_counter <= 4'd0;
                clock_phase <= 1'b0;
                active      <= 1'b1;
                ready       <= 1'b0;
            end
            else if (active && bit_clk) begin
                if (!clock_phase) begin
                    // Output clock bit
                    // M2FM: clock=1 only if prev_data=0 AND cur_data=0
                    flux_out    <= (~prev_data) & (~shift_reg[7]);
                    flux_valid  <= 1'b1;
                    clock_phase <= 1'b1;
                end
                else begin
                    // Output data bit (MSB first)
                    flux_out    <= shift_reg[7];
                    flux_valid  <= 1'b1;
                    clock_phase <= 1'b0;
                    prev_data   <= shift_reg[7];
                    shift_reg   <= {shift_reg[6:0], 1'b0};
                    bit_counter <= bit_counter + 1'b1;

                    if (bit_counter == 4'd7) begin
                        // Last data bit transmitted
                        active        <= 1'b0;
                        byte_complete <= 1'b1;
                        ready         <= 1'b1;
                    end
                end
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// M2FM Serial Decoder
// Decodes serial M2FM flux transitions to bytes
//-----------------------------------------------------------------------------

module m2fm_decoder_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_clk,        // Bit clock from DPLL
    input  wire        flux_in,        // Serial M2FM encoded input
    input  wire        flux_valid,     // Input bit valid
    output reg  [7:0]  data_out,       // Decoded byte
    output reg         data_valid,     // Byte complete
    output reg         sync_error      // Clock pattern error
);

    reg [7:0]  shift_reg;
    reg [3:0]  bit_counter;
    reg        clock_phase;
    reg        prev_data;
    reg        expected_clock;

    always @(posedge clk) begin
        if (reset) begin
            shift_reg   <= 8'h00;
            bit_counter <= 4'd0;
            clock_phase <= 1'b0;
            prev_data   <= 1'b0;
            data_out    <= 8'h00;
            data_valid  <= 1'b0;
            sync_error  <= 1'b0;
        end
        else if (enable) begin
            data_valid <= 1'b0;

            if (flux_valid && bit_clk) begin
                if (!clock_phase) begin
                    // Expecting clock bit
                    // M2FM: clock should be 1 only if prev=0 AND next=0
                    // We can't know next yet, so just record for post-check
                    expected_clock <= flux_in;
                    clock_phase    <= 1'b1;
                end
                else begin
                    // Capture data bit
                    // Now validate previous clock: should be (~prev_data) & (~flux_in)
                    if (expected_clock != ((~prev_data) & (~flux_in))) begin
                        sync_error <= 1'b1;
                    end else begin
                        sync_error <= 1'b0;
                    end

                    shift_reg   <= {shift_reg[6:0], flux_in};
                    prev_data   <= flux_in;
                    clock_phase <= 1'b0;
                    bit_counter <= bit_counter + 1'b1;

                    if (bit_counter == 4'd7) begin
                        // Byte complete
                        data_out    <= {shift_reg[6:0], flux_in};
                        data_valid  <= 1'b1;
                        bit_counter <= 4'd0;
                    end
                end
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// M2FM Sync/Address Mark Detector
// Detects M2FM-specific sync mark: 0xF77A
//
// DEC RX01/02 format:
//   - Sync mark: F77A (raw encoded pattern)
//   - Address marks different from IBM
//-----------------------------------------------------------------------------

module m2fm_sync_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_in,         // Bit from DPLL
    input  wire        bit_valid,      // Bit valid
    output reg         sync_detected,  // F77A sync pattern found
    output reg  [7:0]  data_byte,      // Assembled data byte
    output reg         byte_ready      // Data byte ready
);

    // M2FM sync mark pattern (16-bit encoded)
    // F77A is the raw bit pattern that indicates sync
    localparam [15:0] SYNC_PATTERN = 16'hF77A;

    reg [15:0] shift_reg;
    reg [3:0]  bit_count;

    always @(posedge clk) begin
        if (reset) begin
            shift_reg     <= 16'h0000;
            bit_count     <= 4'd0;
            sync_detected <= 1'b0;
            data_byte     <= 8'h00;
            byte_ready    <= 1'b0;
        end
        else if (enable && bit_valid) begin
            sync_detected <= 1'b0;
            byte_ready    <= 1'b0;

            // Shift in new bit
            shift_reg <= {shift_reg[14:0], bit_in};
            bit_count <= bit_count + 1'b1;

            // Check for sync pattern
            if (shift_reg == SYNC_PATTERN) begin
                sync_detected <= 1'b1;
                bit_count     <= 4'd0;  // Reset for data bytes
            end

            // Output byte every 16 bits (after sync)
            if (bit_count == 4'd15) begin
                // Extract data bits (even positions)
                data_byte <= {shift_reg[13], shift_reg[11], shift_reg[9], shift_reg[7],
                              shift_reg[5],  shift_reg[3],  shift_reg[1], bit_in};
                byte_ready <= 1'b1;
                bit_count  <= 4'd0;
            end
        end
    end

endmodule
