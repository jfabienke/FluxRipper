//-----------------------------------------------------------------------------
// Agat Sync Detector (Soviet Apple II Clone)
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Used by:
//   - Agat-7 (Soviet Apple II clone)
//   - Agat-9 (Enhanced version)
//
// Agat uses Apple-style GCR encoding but with different sync patterns:
//
// Apple II standard:
//   - Self-sync: D5 AA 96 (Address), D5 AA AD (Data)
//   - Uses 5&3 or 6&2 GCR encoding
//
// Agat differences:
//   - Agat-7: Uses different prologue bytes for some disk formats
//   - Agat-9: Can emulate Apple II or use native format
//   - Self-sync bytes may differ: Some use 0x95 instead of 0x96
//   - Native Agat format uses different address mark structure
//
// This detector handles both Apple-compatible and native Agat formats.
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-03 23:45
//-----------------------------------------------------------------------------

module agat_sync_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_in,         // Bit from DPLL
    input  wire        bit_valid,      // Bit valid
    input  wire        agat_native,    // 1=Native Agat, 0=Apple-compatible
    output reg         sync_detected,  // Sync pattern found
    output reg         addr_mark,      // Address field marker
    output reg         data_mark,      // Data field marker
    output reg  [7:0]  data_byte,      // Assembled data byte
    output reg         byte_ready,     // Data byte ready
    output reg  [1:0]  format_type     // 0=Apple, 1=Agat-7, 2=Agat-9
);

    //-------------------------------------------------------------------------
    // Sync Pattern Definitions
    //-------------------------------------------------------------------------

    // Apple II standard patterns (also used by some Agat disks)
    localparam APPLE_SYNC_D5   = 8'hD5;
    localparam APPLE_SYNC_AA   = 8'hAA;
    localparam APPLE_ADDR_96   = 8'h96;     // Address prologue end
    localparam APPLE_DATA_AD   = 8'hAD;     // Data prologue end

    // Agat-7 native format patterns
    localparam AGAT7_SYNC_D5   = 8'hD5;
    localparam AGAT7_SYNC_AA   = 8'hAA;
    localparam AGAT7_ADDR_95   = 8'h95;     // Some Agat disks use 0x95
    localparam AGAT7_DATA_AB   = 8'hAB;     // Alternate data marker

    // Agat-9 extended patterns
    localparam AGAT9_SYNC_A5   = 8'hA5;     // Alternate sync start
    localparam AGAT9_SYNC_5A   = 8'h5A;     // Alternate sync byte

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam ST_IDLE      = 3'b000;
    localparam ST_SYNC1     = 3'b001;       // Seen first sync byte (D5 or A5)
    localparam ST_SYNC2     = 3'b010;       // Seen second sync byte (AA or 5A)
    localparam ST_PROLOGUE  = 3'b011;       // Waiting for prologue end byte
    localparam ST_DATA      = 3'b100;       // Receiving field data

    reg [2:0]  state;
    reg [7:0]  shift_reg;          // 8-bit shift register for byte assembly
    reg [2:0]  bit_count;          // Count bits (0-7)
    reg [7:0]  prev_byte;          // Previous byte for pattern matching
    reg [7:0]  prev_prev_byte;     // Two bytes back
    reg        sync_type;          // 0=Apple style, 1=Agat-9 style

    //-------------------------------------------------------------------------
    // Byte Assembly and Pattern Detection
    //-------------------------------------------------------------------------

    always @(posedge clk) begin
        if (reset) begin
            state          <= ST_IDLE;
            shift_reg      <= 8'h00;
            bit_count      <= 3'd0;
            sync_detected  <= 1'b0;
            addr_mark      <= 1'b0;
            data_mark      <= 1'b0;
            data_byte      <= 8'h00;
            byte_ready     <= 1'b0;
            format_type    <= 2'b00;
            prev_byte      <= 8'h00;
            prev_prev_byte <= 8'h00;
            sync_type      <= 1'b0;
        end
        else if (enable && bit_valid) begin
            // Clear single-cycle outputs
            sync_detected <= 1'b0;
            addr_mark     <= 1'b0;
            data_mark     <= 1'b0;
            byte_ready    <= 1'b0;

            // Shift in new bit (MSB first, GCR convention)
            shift_reg <= {shift_reg[6:0], bit_in};
            bit_count <= bit_count + 1'b1;

            // Every 8 bits, we have a complete byte
            if (bit_count == 3'd7) begin
                // Update byte history
                prev_prev_byte <= prev_byte;
                prev_byte      <= shift_reg;

                // Output byte
                data_byte  <= {shift_reg[6:0], bit_in};
                byte_ready <= 1'b1;

                case (state)
                    ST_IDLE: begin
                        // Look for sync start byte
                        if ({shift_reg[6:0], bit_in} == APPLE_SYNC_D5 ||
                            {shift_reg[6:0], bit_in} == AGAT7_SYNC_D5) begin
                            state     <= ST_SYNC1;
                            sync_type <= 1'b0;      // Apple/Agat-7 style
                        end
                        else if (agat_native &&
                                 {shift_reg[6:0], bit_in} == AGAT9_SYNC_A5) begin
                            state     <= ST_SYNC1;
                            sync_type <= 1'b1;      // Agat-9 style
                        end
                    end

                    ST_SYNC1: begin
                        // Look for second sync byte
                        if (!sync_type) begin
                            // Apple/Agat-7: Expect AA
                            if ({shift_reg[6:0], bit_in} == APPLE_SYNC_AA) begin
                                state <= ST_SYNC2;
                            end
                            else begin
                                state <= ST_IDLE;   // Not a valid sync
                            end
                        end
                        else begin
                            // Agat-9: Expect 5A
                            if ({shift_reg[6:0], bit_in} == AGAT9_SYNC_5A) begin
                                state <= ST_SYNC2;
                            end
                            else begin
                                state <= ST_IDLE;
                            end
                        end
                    end

                    ST_SYNC2: begin
                        // Check prologue end byte to determine field type
                        sync_detected <= 1'b1;

                        case ({shift_reg[6:0], bit_in})
                            // Apple II / Agat compatible address marks
                            APPLE_ADDR_96: begin
                                addr_mark   <= 1'b1;
                                format_type <= 2'b00;   // Apple compatible
                                state       <= ST_DATA;
                            end

                            // Agat-7 alternate address mark
                            AGAT7_ADDR_95: begin
                                addr_mark   <= 1'b1;
                                format_type <= 2'b01;   // Agat-7 native
                                state       <= ST_DATA;
                            end

                            // Apple II / Agat compatible data marks
                            APPLE_DATA_AD: begin
                                data_mark   <= 1'b1;
                                format_type <= 2'b00;   // Apple compatible
                                state       <= ST_DATA;
                            end

                            // Agat-7 alternate data mark
                            AGAT7_DATA_AB: begin
                                data_mark   <= 1'b1;
                                format_type <= 2'b01;   // Agat-7 native
                                state       <= ST_DATA;
                            end

                            default: begin
                                // Unknown prologue byte - check for Agat-9
                                if (agat_native) begin
                                    // Agat-9 may use other patterns
                                    format_type <= 2'b10;   // Agat-9
                                    state       <= ST_DATA;
                                end
                                else begin
                                    state <= ST_IDLE;
                                end
                            end
                        endcase
                    end

                    ST_DATA: begin
                        // Pass through data bytes
                        // Return to idle if we see a new sync pattern
                        if ({shift_reg[6:0], bit_in} == APPLE_SYNC_D5 ||
                            {shift_reg[6:0], bit_in} == AGAT7_SYNC_D5) begin
                            state     <= ST_SYNC1;
                            sync_type <= 1'b0;
                        end
                        else if (agat_native &&
                                 {shift_reg[6:0], bit_in} == AGAT9_SYNC_A5) begin
                            state     <= ST_SYNC1;
                            sync_type <= 1'b1;
                        end
                        // Stay in data state otherwise
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Agat Format Reference
//-----------------------------------------------------------------------------
// Agat-7 disk format:
//   - 35 tracks (like Apple II)
//   - 16 sectors per track (256 bytes each) OR
//   - 13 sectors per track (in DOS 3.2 compatible mode)
//   - GCR 6&2 or 5&3 encoding
//   - Can read Apple II disks with appropriate software
//
// Agat-9 disk format:
//   - 80 tracks on 5.25" HD drives
//   - 840 KB capacity
//   - Modified GCR with different sync patterns
//   - Native format not Apple-compatible
//
// Sync pattern variations found in the wild:
//   - D5 AA 96 - Standard Apple II address
//   - D5 AA AD - Standard Apple II data
//   - D5 AA 95 - Agat variant address
//   - D5 AA AB - Agat variant data
//   - A5 5A xx - Agat-9 native format
//
// Note: Some Agat disks used copy protection schemes similar to Apple II,
// including non-standard sync bytes and timing-based protection.
//-----------------------------------------------------------------------------
