//-----------------------------------------------------------------------------
// ESDI NRZ Decoder
//
// Decodes ESDI NRZ data stream using the drive-provided reference clock.
// ESDI drives provide separate clock and data lines, simplifying clock recovery.
//
// Features:
//   - NRZ data decoding using reference clock
//   - Sync byte detection and byte alignment
//   - Sector/Address Mark (SAMK) detection
//   - CRC-16 verification for ID field
//   - CRC-32 verification for data field
//   - Automatic field recognition
//
// Clock domain: 300 MHz
// Created: 2025-12-04 09:15
//-----------------------------------------------------------------------------

module esdi_decoder (
    input  wire        clk,              // 300 MHz system clock
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    input  wire        enable,           // Decoder enable
    input  wire [1:0]  data_rate,        // 0=10Mbps, 1=15Mbps, 2=20Mbps, 3=24Mbps
    input  wire [9:0]  sector_size,      // Expected sector size in bytes

    //-------------------------------------------------------------------------
    // Serial Input Interface (from PHY)
    //-------------------------------------------------------------------------
    input  wire        nrz_data,         // NRZ data input
    input  wire        nrz_clock,        // Reference clock from drive
    input  wire        samk_in,          // Sector/Address Mark input
    input  wire        index_in,         // Index pulse input

    //-------------------------------------------------------------------------
    // Parallel Data Output Interface (to sector buffer)
    //-------------------------------------------------------------------------
    output reg  [7:0]  data_out,         // Parallel data output
    output reg         data_valid,       // Data byte valid
    output reg         data_start,       // Start of data field
    output reg         data_end,         // End of data field

    //-------------------------------------------------------------------------
    // ID Field Output
    //-------------------------------------------------------------------------
    output reg  [15:0] id_cylinder,      // Decoded cylinder number
    output reg  [3:0]  id_head,          // Decoded head number
    output reg  [7:0]  id_sector,        // Decoded sector number
    output reg  [7:0]  id_flags,         // Decoded flags
    output reg         id_valid,         // ID field valid (CRC OK)
    output reg         id_crc_error,     // ID CRC error

    //-------------------------------------------------------------------------
    // Status
    //-------------------------------------------------------------------------
    output reg         decoder_active,   // Decoding in progress
    output reg  [2:0]  current_field,    // Current field being decoded
    output reg         sync_found,       // Sync byte detected
    output reg         data_crc_ok,      // Data CRC verified OK
    output reg         data_crc_error,   // Data CRC error
    output reg  [10:0] byte_count        // Bytes decoded in current field
);

    //-------------------------------------------------------------------------
    // Field Identifiers
    //-------------------------------------------------------------------------
    localparam [2:0]
        FIELD_IDLE      = 3'd0,
        FIELD_HUNTING   = 3'd1,    // Looking for sync
        FIELD_SYNC      = 3'd2,
        FIELD_ID        = 3'd3,
        FIELD_ID_CRC    = 3'd4,
        FIELD_DATA      = 3'd5,
        FIELD_DATA_CRC  = 3'd6;

    //-------------------------------------------------------------------------
    // Clock Edge Detection
    //-------------------------------------------------------------------------
    reg [2:0] nrz_clock_sync;
    reg       nrz_clock_prev;
    wire      clock_rising;
    wire      clock_falling;

    always @(posedge clk) begin
        if (reset) begin
            nrz_clock_sync <= 3'b000;
            nrz_clock_prev <= 1'b0;
        end else begin
            nrz_clock_sync <= {nrz_clock_sync[1:0], nrz_clock};
            nrz_clock_prev <= nrz_clock_sync[2];
        end
    end

    assign clock_rising = nrz_clock_sync[2] & ~nrz_clock_prev;
    assign clock_falling = ~nrz_clock_sync[2] & nrz_clock_prev;

    //-------------------------------------------------------------------------
    // Data Synchronization
    //-------------------------------------------------------------------------
    reg [2:0] nrz_data_sync;

    always @(posedge clk) begin
        if (reset) begin
            nrz_data_sync <= 3'b000;
        end else begin
            nrz_data_sync <= {nrz_data_sync[1:0], nrz_data};
        end
    end

    //-------------------------------------------------------------------------
    // SAMK Edge Detection
    //-------------------------------------------------------------------------
    reg [2:0] samk_sync;
    reg       samk_prev;
    wire      samk_rising;

    always @(posedge clk) begin
        if (reset) begin
            samk_sync <= 3'b000;
            samk_prev <= 1'b0;
        end else begin
            samk_sync <= {samk_sync[1:0], samk_in};
            samk_prev <= samk_sync[2];
        end
    end

    assign samk_rising = samk_sync[2] & ~samk_prev;

    //-------------------------------------------------------------------------
    // Bit-to-Byte Shift Register
    //-------------------------------------------------------------------------
    reg [7:0]  shift_reg;
    reg [2:0]  bit_count;
    reg        byte_ready;

    always @(posedge clk) begin
        if (reset) begin
            shift_reg <= 8'd0;
            bit_count <= 3'd0;
            byte_ready <= 1'b0;
        end else if (enable && clock_rising) begin
            // Sample data on clock rising edge
            shift_reg <= {shift_reg[6:0], nrz_data_sync[2]};
            bit_count <= bit_count + 1;

            if (bit_count == 3'd7) begin
                byte_ready <= 1'b1;
            end else begin
                byte_ready <= 1'b0;
            end
        end else begin
            byte_ready <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // Sync Byte Detection
    //-------------------------------------------------------------------------
    // ESDI sync byte is typically 0x0A
    localparam [7:0] SYNC_BYTE = 8'h0A;

    reg sync_detected;

    always @(posedge clk) begin
        if (reset) begin
            sync_detected <= 1'b0;
        end else if (byte_ready) begin
            sync_detected <= (shift_reg == SYNC_BYTE);
        end else begin
            sync_detected <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // CRC-16 Calculator (for ID field)
    //-------------------------------------------------------------------------
    reg [15:0] crc16;
    reg        crc16_enable;
    reg        crc16_init;

    function [15:0] crc16_update;
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
            crc16_update = crc;
        end
    endfunction

    always @(posedge clk) begin
        if (reset || crc16_init) begin
            crc16 <= 16'hFFFF;
        end else if (crc16_enable && byte_ready) begin
            crc16 <= crc16_update(crc16, shift_reg);
        end
    end

    //-------------------------------------------------------------------------
    // CRC-32 Calculator (for data field)
    //-------------------------------------------------------------------------
    reg [31:0] crc32;
    reg        crc32_enable;
    reg        crc32_init;

    function [31:0] crc32_update;
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
            crc32_update = crc;
        end
    endfunction

    always @(posedge clk) begin
        if (reset || crc32_init) begin
            crc32 <= 32'hFFFFFFFF;
        end else if (crc32_enable && byte_ready) begin
            crc32 <= crc32_update(crc32, shift_reg);
        end
    end

    //-------------------------------------------------------------------------
    // ID Field Capture
    //-------------------------------------------------------------------------
    reg [7:0] id_buffer [0:5];   // 6 bytes of ID data
    reg [2:0] id_byte_index;

    //-------------------------------------------------------------------------
    // Decoder State Machine
    //-------------------------------------------------------------------------
    reg [2:0]  state;
    reg [10:0] field_byte_count;
    reg        expecting_data;    // After ID, expect data field

    always @(posedge clk) begin
        if (reset) begin
            state <= FIELD_IDLE;
            current_field <= FIELD_IDLE;
            decoder_active <= 1'b0;
            sync_found <= 1'b0;
            data_out <= 8'd0;
            data_valid <= 1'b0;
            data_start <= 1'b0;
            data_end <= 1'b0;
            id_cylinder <= 16'd0;
            id_head <= 4'd0;
            id_sector <= 8'd0;
            id_flags <= 8'd0;
            id_valid <= 1'b0;
            id_crc_error <= 1'b0;
            data_crc_ok <= 1'b0;
            data_crc_error <= 1'b0;
            byte_count <= 11'd0;
            field_byte_count <= 11'd0;
            id_byte_index <= 3'd0;
            expecting_data <= 1'b0;
            crc16_init <= 1'b0;
            crc16_enable <= 1'b0;
            crc32_init <= 1'b0;
            crc32_enable <= 1'b0;
        end else if (enable) begin
            // Default pulse signals
            data_valid <= 1'b0;
            data_start <= 1'b0;
            data_end <= 1'b0;
            id_valid <= 1'b0;
            id_crc_error <= 1'b0;
            data_crc_ok <= 1'b0;
            data_crc_error <= 1'b0;
            crc16_init <= 1'b0;
            crc32_init <= 1'b0;

            case (state)
                FIELD_IDLE: begin
                    decoder_active <= 1'b0;
                    sync_found <= 1'b0;

                    // Start hunting on SAMK or index
                    if (samk_rising || index_in) begin
                        state <= FIELD_HUNTING;
                        current_field <= FIELD_HUNTING;
                        decoder_active <= 1'b1;
                        crc16_init <= 1'b1;
                        crc32_init <= 1'b1;
                        byte_count <= 11'd0;
                    end
                end

                FIELD_HUNTING: begin
                    // Look for sync byte
                    if (sync_detected) begin
                        state <= FIELD_SYNC;
                        current_field <= FIELD_SYNC;
                        sync_found <= 1'b1;
                    end else if (byte_ready) begin
                        byte_count <= byte_count + 1;

                        // Timeout if no sync after many bytes
                        if (byte_count > 11'd50) begin
                            state <= FIELD_IDLE;
                        end
                    end
                end

                FIELD_SYNC: begin
                    // After sync, determine if this is ID or data based on context
                    if (byte_ready) begin
                        byte_count <= byte_count + 1;

                        if (!expecting_data) begin
                            // First field after SAMK is ID
                            state <= FIELD_ID;
                            current_field <= FIELD_ID;
                            id_byte_index <= 3'd0;
                            field_byte_count <= 11'd6;
                            crc16_enable <= 1'b1;
                        end else begin
                            // After ID, this is data
                            state <= FIELD_DATA;
                            current_field <= FIELD_DATA;
                            field_byte_count <= {1'b0, sector_size};
                            crc32_enable <= 1'b1;
                            data_start <= 1'b1;
                        end
                    end
                end

                FIELD_ID: begin
                    if (byte_ready) begin
                        byte_count <= byte_count + 1;

                        // Capture ID bytes
                        id_buffer[id_byte_index] <= shift_reg;
                        id_byte_index <= id_byte_index + 1;
                        field_byte_count <= field_byte_count - 1;

                        if (field_byte_count <= 11'd1) begin
                            // ID data complete, now read CRC
                            state <= FIELD_ID_CRC;
                            current_field <= FIELD_ID_CRC;
                            field_byte_count <= 11'd2;
                            crc16_enable <= 1'b0;
                        end
                    end
                end

                FIELD_ID_CRC: begin
                    if (byte_ready) begin
                        byte_count <= byte_count + 1;
                        field_byte_count <= field_byte_count - 1;

                        // Include CRC bytes in calculation for residue check
                        crc16 <= crc16_update(crc16, shift_reg);

                        if (field_byte_count <= 11'd1) begin
                            // Check CRC residue (should be 0 for good CRC)
                            // Actually check against expected residue
                            if (crc16 == 16'h0000 || crc16 == 16'h1D0F) begin
                                // Valid ID
                                id_cylinder <= {id_buffer[0], id_buffer[1]};
                                id_head <= id_buffer[2][3:0];
                                id_sector <= id_buffer[3];
                                id_flags <= id_buffer[4];
                                id_valid <= 1'b1;
                                expecting_data <= 1'b1;
                            end else begin
                                id_crc_error <= 1'b1;
                                expecting_data <= 1'b0;
                            end

                            // Go back to hunting for data sync
                            state <= FIELD_HUNTING;
                            current_field <= FIELD_HUNTING;
                            sync_found <= 1'b0;
                            crc32_init <= 1'b1;
                        end
                    end
                end

                FIELD_DATA: begin
                    if (byte_ready) begin
                        byte_count <= byte_count + 1;
                        field_byte_count <= field_byte_count - 1;

                        data_out <= shift_reg;
                        data_valid <= 1'b1;

                        if (field_byte_count <= 11'd1) begin
                            // Data complete, now read CRC
                            state <= FIELD_DATA_CRC;
                            current_field <= FIELD_DATA_CRC;
                            field_byte_count <= 11'd4;
                            crc32_enable <= 1'b0;
                            data_end <= 1'b1;
                        end
                    end
                end

                FIELD_DATA_CRC: begin
                    if (byte_ready) begin
                        byte_count <= byte_count + 1;
                        field_byte_count <= field_byte_count - 1;

                        // Include CRC bytes
                        crc32 <= crc32_update(crc32, shift_reg);

                        if (field_byte_count <= 11'd1) begin
                            // Check CRC-32 residue
                            // After including the CRC, residue should be constant
                            if (crc32 == 32'hDEBB20E3 || crc32 == 32'h00000000) begin
                                data_crc_ok <= 1'b1;
                            end else begin
                                data_crc_error <= 1'b1;
                            end

                            // Done with this sector
                            state <= FIELD_IDLE;
                            current_field <= FIELD_IDLE;
                            expecting_data <= 1'b0;
                        end
                    end
                end

                default: state <= FIELD_IDLE;
            endcase

            // Abort on index (new revolution)
            if (index_in && state != FIELD_IDLE) begin
                state <= FIELD_IDLE;
                expecting_data <= 1'b0;
            end

        end else begin
            // Decoder disabled
            state <= FIELD_IDLE;
            decoder_active <= 1'b0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// ESDI Sector Buffer Interface
// Manages buffering between decoder and memory
//-----------------------------------------------------------------------------
module esdi_sector_buffer (
    input  wire        clk,
    input  wire        reset,

    //-------------------------------------------------------------------------
    // Decoder Interface
    //-------------------------------------------------------------------------
    input  wire [7:0]  dec_data,
    input  wire        dec_valid,
    input  wire        dec_start,
    input  wire        dec_end,

    //-------------------------------------------------------------------------
    // Memory Interface
    //-------------------------------------------------------------------------
    output reg  [9:0]  mem_addr,
    output reg  [7:0]  mem_data,
    output reg         mem_write,

    //-------------------------------------------------------------------------
    // Status
    //-------------------------------------------------------------------------
    output reg         buffer_active,
    output reg         buffer_complete,
    output reg  [9:0]  bytes_captured
);

    always @(posedge clk) begin
        if (reset) begin
            mem_addr <= 10'd0;
            mem_data <= 8'd0;
            mem_write <= 1'b0;
            buffer_active <= 1'b0;
            buffer_complete <= 1'b0;
            bytes_captured <= 10'd0;
        end else begin
            mem_write <= 1'b0;
            buffer_complete <= 1'b0;

            if (dec_start) begin
                buffer_active <= 1'b1;
                mem_addr <= 10'd0;
                bytes_captured <= 10'd0;
            end else if (buffer_active && dec_valid) begin
                mem_data <= dec_data;
                mem_write <= 1'b1;
                mem_addr <= mem_addr + 1;
                bytes_captured <= bytes_captured + 1;
            end

            if (dec_end) begin
                buffer_active <= 1'b0;
                buffer_complete <= 1'b1;
            end
        end
    end

endmodule
