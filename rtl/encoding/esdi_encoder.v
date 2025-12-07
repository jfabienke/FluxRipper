//-----------------------------------------------------------------------------
// ESDI NRZ Encoder
//
// Encodes data for ESDI drives using NRZ (Non-Return-to-Zero) encoding.
// ESDI uses separate clock and data lines, unlike MFM/RLL which embed clock.
//
// ESDI Data Format:
//   - NRZ data stream on DATA lines
//   - Separate clock on CLOCK lines (provided by controller)
//   - Sector/Address Mark (SAMK) for sector identification
//   - Preamble: all zeros for PLL lock
//   - Sync: specific pattern for byte alignment
//
// ESDI Sector Format:
//   - Preamble (PLO sync field): ~12 bytes of 0x00
//   - Sync byte: 0x0A (or drive-specific)
//   - Address Mark: special pattern
//   - ID Field: cylinder, head, sector, flags
//   - ID CRC: 2 bytes
//   - Data Preamble: ~12 bytes of 0x00
//   - Data Sync: 0x0A
//   - Data Field: 512-1024 bytes
//   - Data CRC: 4 bytes (32-bit CRC)
//   - Pad/Gap
//
// Clock domain: 300 MHz
// Created: 2025-12-04 09:15
//-----------------------------------------------------------------------------

module esdi_encoder (
    input  wire        clk,              // 300 MHz system clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    input  wire        enable,           // Encoder enable
    input  wire [1:0]  data_rate,        // 0=10Mbps, 1=15Mbps, 2=20Mbps, 3=24Mbps
    input  wire [9:0]  sector_size,      // Sector size in bytes (typically 512)
    input  wire [3:0]  preamble_len,     // Preamble length in bytes

    //-------------------------------------------------------------------------
    // Data Input Interface (from sector buffer)
    //-------------------------------------------------------------------------
    input  wire [7:0]  data_in,          // Parallel data input
    input  wire        data_valid,       // Data byte valid
    output reg         data_request,     // Request next byte

    //-------------------------------------------------------------------------
    // Field Information (from format controller)
    //-------------------------------------------------------------------------
    input  wire        write_id,         // Writing ID field
    input  wire        write_data,       // Writing data field
    input  wire [15:0] cylinder,         // Cylinder number for ID
    input  wire [3:0]  head,             // Head number for ID
    input  wire [7:0]  sector,           // Sector number for ID
    input  wire [7:0]  flags,            // ID field flags

    //-------------------------------------------------------------------------
    // Serial Output Interface (to PHY)
    //-------------------------------------------------------------------------
    output reg         nrz_data,         // NRZ data output
    output reg         nrz_clock,        // Bit clock output
    output reg         samk_out,         // Sector/Address Mark output
    output reg         write_active,     // Write in progress

    //-------------------------------------------------------------------------
    // Status
    //-------------------------------------------------------------------------
    output reg         encoder_busy,     // Encoding in progress
    output reg  [2:0]  current_field,    // Current field being written
    output reg  [10:0] byte_count        // Bytes written in current field
);

    //-------------------------------------------------------------------------
    // Field Identifiers
    //-------------------------------------------------------------------------
    localparam [2:0]
        FIELD_IDLE      = 3'd0,
        FIELD_PREAMBLE  = 3'd1,
        FIELD_SYNC      = 3'd2,
        FIELD_ID        = 3'd3,
        FIELD_ID_CRC    = 3'd4,
        FIELD_DATA      = 3'd5,
        FIELD_DATA_CRC  = 3'd6,
        FIELD_GAP       = 3'd7;

    //-------------------------------------------------------------------------
    // Bit Rate Divider
    //-------------------------------------------------------------------------
    // Generate bit clock from 300 MHz system clock
    reg [5:0] bit_divider;
    reg [5:0] bit_period;
    reg       bit_tick;

    // Period values for different rates at 300 MHz
    // 10 Mbps: 300/10 = 30 clocks per bit
    // 15 Mbps: 300/15 = 20 clocks per bit
    // 20 Mbps: 300/20 = 15 clocks per bit
    // 24 Mbps: 300/24 = 12.5 clocks per bit

    always @(*) begin
        case (data_rate)
            2.d0: bit_period = 6.d30;    // 10 Mbps
            2.d1: bit_period = 6.d20;    // 15 Mbps
            2.d2: bit_period = 6.d15;    // 20 Mbps
            2.d3: bit_period = 6.d13;    // 24 Mbps
        endcase
    end

    always @(posedge clk) begin
        if (reset || !enable) begin
            bit_divider <= 6'd0;
            bit_tick <= 1'b0;
            nrz_clock <= 1'b0;
        end else begin
            if (bit_divider >= bit_period - 1) begin
                bit_divider <= 6'd0;
                bit_tick <= 1'b1;
                nrz_clock <= ~nrz_clock;  // Toggle clock each bit period
            end else begin
                bit_divider <= bit_divider + 1;
                bit_tick <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Shift Register for Parallel-to-Serial Conversion
    //-------------------------------------------------------------------------
    reg [7:0]  shift_reg;
    reg [2:0]  bit_count;
    reg        byte_done;
    reg        load_byte;

    always @(posedge clk) begin
        if (reset) begin
            shift_reg <= 8'd0;
            bit_count <= 3'd0;
            byte_done <= 1'b0;
            nrz_data <= 1'b0;
        end else if (enable && bit_tick) begin
            if (load_byte) begin
                shift_reg <= data_in;
                bit_count <= 3'd7;
                byte_done <= 1'b0;
                nrz_data <= data_in[7];  // MSB first
            end else if (bit_count > 3'd0) begin
                shift_reg <= {shift_reg[6:0], 1'b0};
                bit_count <= bit_count - 1;
                nrz_data <= shift_reg[6];  // Next bit
                byte_done <= (bit_count == 3'd1);
            end else begin
                byte_done <= 1'b0;
            end
        end else begin
            byte_done <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // CRC-32 Generator (ESDI uses 32-bit CRC for data)
    //-------------------------------------------------------------------------
    reg [31:0] crc32;
    reg        crc_enable;
    reg        crc_init;
    wire [31:0] crc32_next;

    // CRC-32 polynomial: 0x04C11DB7 (IEEE 802.3)
    // x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0]  data;
        reg [31:0]   crc;
        integer      i;
        begin
            crc = crc_in;
            for (i = 7; i >= 0; i = i - 1) begin
                if ((crc[31] ^ data[i]) == 1'b1)
                    crc = {crc[30:0], 1'b0} ^ 32'h04C11DB7;
                else
                    crc = {crc[30:0], 1'b0};
            end
            crc32_byte = crc;
        end
    endfunction

    always @(posedge clk) begin
        if (reset || crc_init) begin
            crc32 <= 32'hFFFFFFFF;  // Initialize to all 1s
        end else if (crc_enable && byte_done) begin
            crc32 <= crc32_byte(crc32, shift_reg);
        end
    end

    //-------------------------------------------------------------------------
    // CRC-16 Generator (ESDI uses 16-bit CRC for ID field)
    //-------------------------------------------------------------------------
    reg [15:0] crc16;
    reg        crc16_enable;
    reg        crc16_init;

    // CRC-16-CCITT polynomial: 0x1021

    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0]  data;
        reg [15:0]   crc;
        integer      i;
        begin
            crc = crc_in;
            for (i = 7; i >= 0; i = i - 1) begin
                if ((crc[15] ^ data[i]) == 1'b1)
                    crc = {crc[14:0], 1'b0} ^ 16'h1021;
                else
                    crc = {crc[14:0], 1'b0};
            end
            crc16_byte = crc;
        end
    endfunction

    always @(posedge clk) begin
        if (reset || crc16_init) begin
            crc16 <= 16'hFFFF;
        end else if (crc16_enable && byte_done) begin
            crc16 <= crc16_byte(crc16, shift_reg);
        end
    end

    //-------------------------------------------------------------------------
    // Encoder State Machine
    //-------------------------------------------------------------------------
    reg [2:0]  state;
    reg [10:0] field_byte_count;
    reg [3:0]  id_byte_index;
    reg [7:0]  gen_byte;        // Generated byte (preamble, sync, etc.)
    reg        use_gen_byte;    // Use generated byte instead of data_in

    // ID field bytes
    wire [7:0] id_bytes [0:7];
    assign id_bytes[0] = cylinder[15:8];   // Cylinder high
    assign id_bytes[1] = cylinder[7:0];    // Cylinder low
    assign id_bytes[2] = {4'h0, head};     // Head
    assign id_bytes[3] = sector;           // Sector
    assign id_bytes[4] = flags;            // Flags
    assign id_bytes[5] = 8'h00;            // Reserved
    assign id_bytes[6] = crc16[15:8];      // CRC high
    assign id_bytes[7] = crc16[7:0];       // CRC low

    // CRC bytes for data field
    wire [7:0] crc32_bytes [0:3];
    assign crc32_bytes[0] = ~crc32[31:24];  // Inverted CRC
    assign crc32_bytes[1] = ~crc32[23:16];
    assign crc32_bytes[2] = ~crc32[15:8];
    assign crc32_bytes[3] = ~crc32[7:0];

    always @(posedge clk) begin
        if (reset) begin
            state <= FIELD_IDLE;
            current_field <= FIELD_IDLE;
            encoder_busy <= 1'b0;
            write_active <= 1'b0;
            data_request <= 1'b0;
            samk_out <= 1'b0;
            field_byte_count <= 11'd0;
            byte_count <= 11'd0;
            id_byte_index <= 4'd0;
            gen_byte <= 8'd0;
            use_gen_byte <= 1'b0;
            load_byte <= 1'b0;
            crc_init <= 1'b0;
            crc_enable <= 1'b0;
            crc16_init <= 1'b0;
            crc16_enable <= 1'b0;
        end else if (enable) begin
            // Default assignments
            load_byte <= 1'b0;
            crc_init <= 1'b0;
            crc16_init <= 1'b0;
            samk_out <= 1'b0;

            case (state)
                FIELD_IDLE: begin
                    encoder_busy <= 1'b0;
                    write_active <= 1'b0;
                    current_field <= FIELD_IDLE;

                    if (write_id || write_data) begin
                        state <= FIELD_PREAMBLE;
                        current_field <= FIELD_PREAMBLE;
                        encoder_busy <= 1'b1;
                        write_active <= 1'b1;
                        field_byte_count <= {7'd0, preamble_len};
                        byte_count <= 11'd0;
                        gen_byte <= 8'h00;  // Preamble is all zeros
                        use_gen_byte <= 1'b1;
                        crc_init <= 1'b1;
                        crc16_init <= 1'b1;
                    end
                end

                FIELD_PREAMBLE: begin
                    if (byte_done) begin
                        byte_count <= byte_count + 1;

                        if (field_byte_count <= 11'd1) begin
                            // Move to sync
                            state <= FIELD_SYNC;
                            current_field <= FIELD_SYNC;
                            gen_byte <= 8'h0A;  // ESDI sync byte
                            field_byte_count <= 11'd1;
                        end else begin
                            field_byte_count <= field_byte_count - 1;
                            load_byte <= 1'b1;
                        end
                    end else if (field_byte_count > 11'd0 && bit_count == 3'd0) begin
                        load_byte <= 1'b1;
                    end
                end

                FIELD_SYNC: begin
                    samk_out <= 1'b1;  // Assert SAMK during sync

                    if (byte_done) begin
                        byte_count <= byte_count + 1;
                        samk_out <= 1'b0;

                        if (write_id) begin
                            state <= FIELD_ID;
                            current_field <= FIELD_ID;
                            id_byte_index <= 4'd0;
                            crc16_enable <= 1'b1;
                        end else begin
                            state <= FIELD_DATA;
                            current_field <= FIELD_DATA;
                            field_byte_count <= {1'b0, sector_size};
                            data_request <= 1'b1;
                            use_gen_byte <= 1'b0;
                            crc_enable <= 1'b1;
                        end
                    end else if (bit_count == 3'd0) begin
                        load_byte <= 1'b1;
                    end
                end

                FIELD_ID: begin
                    crc16_enable <= (id_byte_index < 4'd6);  // CRC first 6 bytes

                    if (byte_done) begin
                        byte_count <= byte_count + 1;
                        id_byte_index <= id_byte_index + 1;

                        if (id_byte_index >= 4'd7) begin
                            // ID complete (6 data + 2 CRC)
                            state <= FIELD_GAP;
                            current_field <= FIELD_GAP;
                            field_byte_count <= 11'd4;  // Short gap
                            gen_byte <= 8'h00;
                            crc16_enable <= 1'b0;
                        end
                    end else if (bit_count == 3'd0) begin
                        gen_byte <= id_bytes[id_byte_index];
                        load_byte <= 1'b1;
                    end
                end

                FIELD_DATA: begin
                    if (byte_done) begin
                        byte_count <= byte_count + 1;
                        field_byte_count <= field_byte_count - 1;

                        if (field_byte_count <= 11'd1) begin
                            // Data complete, write CRC
                            state <= FIELD_DATA_CRC;
                            current_field <= FIELD_DATA_CRC;
                            field_byte_count <= 11'd4;
                            id_byte_index <= 4'd0;  // Reuse for CRC byte index
                            use_gen_byte <= 1'b1;
                            crc_enable <= 1'b0;
                            data_request <= 1'b0;
                        end else begin
                            data_request <= 1'b1;
                        end
                    end else if (bit_count == 3'd0 && data_valid) begin
                        load_byte <= 1'b1;
                        data_request <= 1'b0;
                    end
                end

                FIELD_DATA_CRC: begin
                    if (byte_done) begin
                        byte_count <= byte_count + 1;
                        id_byte_index <= id_byte_index + 1;

                        if (id_byte_index >= 4'd3) begin
                            // CRC complete
                            state <= FIELD_GAP;
                            current_field <= FIELD_GAP;
                            field_byte_count <= 11'd8;  // Post-data gap
                            gen_byte <= 8'h00;
                        end
                    end else if (bit_count == 3'd0) begin
                        gen_byte <= crc32_bytes[id_byte_index];
                        load_byte <= 1'b1;
                    end
                end

                FIELD_GAP: begin
                    if (byte_done) begin
                        byte_count <= byte_count + 1;
                        field_byte_count <= field_byte_count - 1;

                        if (field_byte_count <= 11'd1) begin
                            state <= FIELD_IDLE;
                            write_active <= 1'b0;
                        end
                    end else if (bit_count == 3'd0) begin
                        load_byte <= 1'b1;
                    end
                end

                default: state <= FIELD_IDLE;
            endcase
        end else begin
            // Encoder disabled
            state <= FIELD_IDLE;
            encoder_busy <= 1'b0;
            write_active <= 1'b0;
        end
    end

endmodule
