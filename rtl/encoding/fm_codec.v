//-----------------------------------------------------------------------------
// FM Encoder/Decoder Module
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Based on CAPSImg Codec/DiskEncoding.cpp InitFM()
// FM encoding: clock bit always 1, data bit follows source
//   Data 1 -> 11 (clock=1, data=1)
//   Data 0 -> 10 (clock=1, data=0)
//
// Target: Xilinx Spartan UltraScale+ (UC+)
// Updated: 2025-12-03 12:00
//-----------------------------------------------------------------------------

module fm_encoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [7:0]  data_in,        // Byte to encode
    input  wire        data_valid,     // Input data valid
    output reg  [15:0] encoded_out,    // FM encoded output (16 bits)
    output reg         encoded_valid,  // Output valid
    output reg         busy            // Encoder busy
);

    //-------------------------------------------------------------------------
    // FM Encoding Logic
    // Each input bit becomes 2 output bits: clock (always 1) + data
    // Input: 8 bits -> Output: 16 bits
    //-------------------------------------------------------------------------

    reg [7:0] data_reg;
    reg [3:0] bit_count;
    reg       processing;

    // Combinational FM encoding - direct implementation from CAPSImg
    // code |= (sval & bit) ? 3 : 2;  // 3=11 for data 1, 2=10 for data 0
    function [15:0] fm_encode_byte;
        input [7:0] data;
        integer i;
        reg [15:0] result;
        begin
            result = 16'h0000;
            for (i = 7; i >= 0; i = i - 1) begin
                result = result << 2;
                // Clock bit is always 1, data bit follows source
                if (data[i])
                    result = result | 2'b11;  // Data 1: clock=1, data=1
                else
                    result = result | 2'b10;  // Data 0: clock=1, data=0
            end
            fm_encode_byte = result;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            encoded_out   <= 16'h0000;
            encoded_valid <= 1'b0;
            busy          <= 1'b0;
            processing    <= 1'b0;
            data_reg      <= 8'h00;
            bit_count     <= 4'd0;
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
                // Complete encoding in one cycle (combinational)
                encoded_out   <= fm_encode_byte(data_reg);
                encoded_valid <= 1'b1;
                processing    <= 1'b0;
                busy          <= 1'b0;
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// FM Decoder
// Decodes 16-bit FM data back to 8-bit byte
// Extracts data bits (odd positions), ignores clock bits (even positions)
//-----------------------------------------------------------------------------

module fm_decoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [15:0] encoded_in,     // FM encoded input (16 bits)
    input  wire        encoded_valid,  // Input valid
    output reg  [7:0]  data_out,       // Decoded byte
    output reg         data_valid,     // Output valid
    output reg         decode_error    // Clock bit error detected
);

    //-------------------------------------------------------------------------
    // FM Decoding Logic
    // Extract data bits from positions 0, 2, 4, 6, 8, 10, 12, 14
    // Clock bits at positions 1, 3, 5, 7, 9, 11, 13, 15 should all be 1
    //-------------------------------------------------------------------------

    // Combinational FM decoding - from CAPSImg fmdecode table logic
    // Extract every other bit (data bits at odd positions in cell)
    function [7:0] fm_decode_word;
        input [15:0] encoded;
        reg [7:0] result;
        begin
            // Data bits are at positions 0, 2, 4, 6, 8, 10, 12, 14
            // (the second bit of each clock+data pair)
            result[7] = encoded[14];
            result[6] = encoded[12];
            result[5] = encoded[10];
            result[4] = encoded[8];
            result[3] = encoded[6];
            result[2] = encoded[4];
            result[1] = encoded[2];
            result[0] = encoded[0];
            fm_decode_word = result;
        end
    endfunction

    // Check if all clock bits are 1 (valid FM encoding)
    function clock_bits_valid;
        input [15:0] encoded;
        begin
            // Clock bits are at positions 1, 3, 5, 7, 9, 11, 13, 15
            clock_bits_valid = encoded[15] & encoded[13] & encoded[11] & encoded[9] &
                               encoded[7]  & encoded[5]  & encoded[3]  & encoded[1];
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            data_out     <= 8'h00;
            data_valid   <= 1'b0;
            decode_error <= 1'b0;
        end
        else if (enable && encoded_valid) begin
            data_out     <= fm_decode_word(encoded_in);
            data_valid   <= 1'b1;
            decode_error <= ~clock_bits_valid(encoded_in);
        end
        else begin
            data_valid <= 1'b0;
        end
    end

endmodule


//-----------------------------------------------------------------------------
// FM Serial Encoder
// Encodes data bit-by-bit for direct flux output
//-----------------------------------------------------------------------------

module fm_encoder_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_clk,        // Bit clock (2x data rate for FM)
    input  wire [7:0]  data_in,        // Byte to encode
    input  wire        data_valid,     // New byte available
    output reg         flux_out,       // Serial FM encoded output
    output reg         flux_valid,     // Output bit valid
    output reg         byte_complete,  // Byte fully transmitted
    output reg         ready           // Ready for new byte
);

    reg [7:0]  shift_reg;
    reg [3:0]  bit_counter;   // Counts 0-15 (8 data bits * 2 = 16 FM bits)
    reg        clock_phase;   // 0=clock bit, 1=data bit
    reg        active;

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
                    // Output clock bit (always 1 for FM)
                    flux_out    <= 1'b1;
                    flux_valid  <= 1'b1;
                    clock_phase <= 1'b1;
                end
                else begin
                    // Output data bit (MSB first)
                    flux_out    <= shift_reg[7];
                    flux_valid  <= 1'b1;
                    clock_phase <= 1'b0;
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
// FM Serial Decoder
// Decodes serial FM flux transitions to bytes
//-----------------------------------------------------------------------------

module fm_decoder_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_clk,        // Bit clock from DPLL
    input  wire        flux_in,        // Serial FM encoded input
    input  wire        flux_valid,     // Input bit valid
    output reg  [7:0]  data_out,       // Decoded byte
    output reg         data_valid,     // Byte complete
    output reg         sync_error      // Clock bit was not 1
);

    reg [7:0]  shift_reg;
    reg [3:0]  bit_counter;   // Counts 0-15 (8 data bits * 2 = 16 FM bits)
    reg        clock_phase;   // 0=expect clock, 1=expect data
    reg        active;

    always @(posedge clk) begin
        if (reset) begin
            shift_reg   <= 8'h00;
            bit_counter <= 4'd0;
            clock_phase <= 1'b0;
            active      <= 1'b1;  // Always receiving
            data_out    <= 8'h00;
            data_valid  <= 1'b0;
            sync_error  <= 1'b0;
        end
        else if (enable) begin
            data_valid <= 1'b0;

            if (flux_valid && bit_clk) begin
                if (!clock_phase) begin
                    // Expecting clock bit (should be 1)
                    if (!flux_in) begin
                        sync_error <= 1'b1;  // Clock bit missing
                    end
                    clock_phase <= 1'b1;
                end
                else begin
                    // Capture data bit
                    shift_reg   <= {shift_reg[6:0], flux_in};
                    clock_phase <= 1'b0;
                    bit_counter <= bit_counter + 1'b1;
                    sync_error  <= 1'b0;

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
// FM Address Mark Detector
// Detects FM-specific sync marks
// FM uses different address marks than MFM:
//   - Index AM: FC (with missing clock at bit 0)
//   - ID AM: FE (with missing clock at bit 0)
//   - Data AM: FB (with missing clock at bit 0)
//   - Deleted Data AM: F8 (with missing clock at bit 0)
//-----------------------------------------------------------------------------

module fm_am_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_in,         // Bit from DPLL
    input  wire        bit_valid,      // Bit valid
    output reg         index_am,       // Index address mark detected
    output reg         id_am,          // ID address mark detected
    output reg         data_am,        // Data address mark detected
    output reg         deleted_am,     // Deleted data address mark detected
    output reg  [7:0]  data_byte,      // Assembled data byte
    output reg         byte_ready      // Data byte ready
);

    // FM address marks with missing clocks
    // Standard FM: clock always 1, so encoded FC = 1111_1111_1111_1100
    // With missing clock at bit 0: FFFE (special pattern)
    // These are the raw 16-bit patterns after decoding considers clock anomalies

    // Simplified: detect after byte assembly when we see specific patterns
    // following the gap bytes (typically 0x00)

    localparam AM_INDEX   = 8'hFC;
    localparam AM_ID      = 8'hFE;
    localparam AM_DATA    = 8'hFB;
    localparam AM_DELETED = 8'hF8;

    reg [15:0] shift_reg;
    reg [4:0]  bit_count;
    reg        clock_phase;

    always @(posedge clk) begin
        if (reset) begin
            shift_reg  <= 16'h0000;
            bit_count  <= 5'd0;
            clock_phase <= 1'b0;
            index_am   <= 1'b0;
            id_am      <= 1'b0;
            data_am    <= 1'b0;
            deleted_am <= 1'b0;
            data_byte  <= 8'h00;
            byte_ready <= 1'b0;
        end
        else if (enable && bit_valid) begin
            // Clear previous detections
            index_am   <= 1'b0;
            id_am      <= 1'b0;
            data_am    <= 1'b0;
            deleted_am <= 1'b0;
            byte_ready <= 1'b0;

            // Shift in new bit
            shift_reg <= {shift_reg[14:0], bit_in};

            if (!clock_phase) begin
                // Clock bit position
                clock_phase <= 1'b1;
            end
            else begin
                // Data bit position
                clock_phase <= 1'b0;
                bit_count   <= bit_count + 1'b1;

                if (bit_count == 5'd7) begin
                    // Extract decoded byte (data bits only)
                    data_byte <= {shift_reg[13], shift_reg[11], shift_reg[9], shift_reg[7],
                                  shift_reg[5],  shift_reg[3],  shift_reg[1], bit_in};
                    byte_ready <= 1'b1;
                    bit_count  <= 5'd0;

                    // Check for address marks
                    // The extracted byte pattern indicates the AM type
                    case ({shift_reg[13], shift_reg[11], shift_reg[9], shift_reg[7],
                           shift_reg[5],  shift_reg[3],  shift_reg[1], bit_in})
                        AM_INDEX:   index_am   <= 1'b1;
                        AM_ID:      id_am      <= 1'b1;
                        AM_DATA:    data_am    <= 1'b1;
                        AM_DELETED: deleted_am <= 1'b1;
                    endcase
                end
            end
        end
    end

endmodule
