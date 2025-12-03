//-----------------------------------------------------------------------------
// Tandy/CoCo FM Sync Detector
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Used by:
//   - TRS-80 Color Computer (CoCo)
//   - Dragon 32/64
//   - Some other 6809-based systems
//
// Tandy uses standard FM encoding but with slightly different address marks
// and sync patterns than IBM-style FM:
//
// Standard IBM FM Address Marks:
//   - ID AM: FE with missing clock
//   - Data AM: FB with missing clock
//   - Deleted Data AM: F8 with missing clock
//
// Tandy/CoCo differences:
//   - Uses same address mark bytes but different gap structure
//   - Sync field is typically 0x00 bytes followed by AM
//   - Some variants use 0xFF sync instead of 0x00
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-03 23:40
//-----------------------------------------------------------------------------

module tandy_sync_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_in,         // Bit from DPLL
    input  wire        bit_valid,      // Bit valid
    output reg         sync_detected,  // Sync pattern found
    output reg         id_am,          // ID address mark (FE)
    output reg         data_am,        // Data address mark (FB)
    output reg         deleted_am,     // Deleted data address mark (F8)
    output reg  [7:0]  data_byte,      // Assembled data byte
    output reg         byte_ready,     // Data byte ready
    output reg  [2:0]  sync_count      // Count of consecutive sync bytes
);

    //-------------------------------------------------------------------------
    // Tandy Address Mark Patterns
    //-------------------------------------------------------------------------
    localparam AM_ID      = 8'hFE;
    localparam AM_DATA    = 8'hFB;
    localparam AM_DELETED = 8'hF8;
    localparam SYNC_BYTE  = 8'h00;     // Standard gap byte
    localparam SYNC_FF    = 8'hFF;     // Alternate sync (some systems)

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    localparam ST_IDLE     = 2'b00;
    localparam ST_SYNC     = 2'b01;    // Receiving sync bytes
    localparam ST_AM       = 2'b10;    // Looking for address mark
    localparam ST_DATA     = 2'b11;    // Receiving data bytes

    reg [1:0]  state;
    reg [15:0] shift_reg;      // 16-bit shift register for FM cell pairs
    reg [3:0]  bit_count;
    reg        clock_phase;
    reg [7:0]  decoded_byte;
    reg [2:0]  gap_count;      // Count of gap (sync) bytes seen

    // Minimum sync bytes required before AM is valid
    localparam MIN_SYNC_BYTES = 3'd4;

    //-------------------------------------------------------------------------
    // Decode FM cell to data bit
    // FM encoding: clock+data pair, clock always 1
    //-------------------------------------------------------------------------
    wire [7:0] decoded_fm;
    assign decoded_fm = {shift_reg[13], shift_reg[11], shift_reg[9], shift_reg[7],
                         shift_reg[5],  shift_reg[3],  shift_reg[1], bit_in};

    always @(posedge clk) begin
        if (reset) begin
            state         <= ST_IDLE;
            shift_reg     <= 16'h0000;
            bit_count     <= 4'd0;
            clock_phase   <= 1'b0;
            sync_detected <= 1'b0;
            id_am         <= 1'b0;
            data_am       <= 1'b0;
            deleted_am    <= 1'b0;
            data_byte     <= 8'h00;
            byte_ready    <= 1'b0;
            sync_count    <= 3'd0;
            gap_count     <= 3'd0;
        end
        else if (enable && bit_valid) begin
            // Clear single-cycle outputs
            sync_detected <= 1'b0;
            id_am         <= 1'b0;
            data_am       <= 1'b0;
            deleted_am    <= 1'b0;
            byte_ready    <= 1'b0;

            // Shift in new bit
            shift_reg <= {shift_reg[14:0], bit_in};

            // Count bits for byte framing
            if (!clock_phase) begin
                // Clock bit position (should be 1 for valid FM)
                clock_phase <= 1'b1;
            end
            else begin
                // Data bit position
                clock_phase <= 1'b0;
                bit_count   <= bit_count + 1'b1;

                // Every 8 data bits = 16 total bits = 1 byte
                if (bit_count == 4'd7) begin
                    decoded_byte <= decoded_fm;
                    byte_ready   <= 1'b1;
                    bit_count    <= 4'd0;

                    case (state)
                        ST_IDLE: begin
                            // Look for sync bytes (0x00 or 0xFF)
                            if (decoded_fm == SYNC_BYTE || decoded_fm == SYNC_FF) begin
                                state     <= ST_SYNC;
                                gap_count <= 3'd1;
                            end
                        end

                        ST_SYNC: begin
                            // Count consecutive sync bytes
                            if (decoded_fm == SYNC_BYTE || decoded_fm == SYNC_FF) begin
                                if (gap_count < 3'd7)
                                    gap_count <= gap_count + 1'b1;
                            end
                            else begin
                                // Non-sync byte - check if it's an AM
                                if (gap_count >= MIN_SYNC_BYTES) begin
                                    sync_detected <= 1'b1;
                                    sync_count    <= gap_count;

                                    case (decoded_fm)
                                        AM_ID: begin
                                            id_am <= 1'b1;
                                            state <= ST_DATA;
                                        end
                                        AM_DATA: begin
                                            data_am <= 1'b1;
                                            state   <= ST_DATA;
                                        end
                                        AM_DELETED: begin
                                            deleted_am <= 1'b1;
                                            state      <= ST_DATA;
                                        end
                                        default: begin
                                            // Not an AM, back to idle
                                            state     <= ST_IDLE;
                                            gap_count <= 3'd0;
                                        end
                                    endcase
                                end
                                else begin
                                    // Not enough sync bytes
                                    state     <= ST_IDLE;
                                    gap_count <= 3'd0;
                                end
                            end
                        end

                        ST_DATA: begin
                            // Pass through data bytes
                            data_byte <= decoded_fm;
                            // Stay in data state until next sync
                            if (decoded_fm == SYNC_BYTE || decoded_fm == SYNC_FF) begin
                                state     <= ST_SYNC;
                                gap_count <= 3'd1;
                            end
                        end

                        default: begin
                            state <= ST_IDLE;
                        end
                    endcase
                end
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// Tandy/CoCo Track Format Reference
//-----------------------------------------------------------------------------
// CoCo disk format (RSDOS):
//   - 35 tracks, single-sided (160KB) or double-sided (320KB)
//   - 18 sectors per track, 256 bytes per sector
//   - FM encoding at 250 Kbps (single density)
//   - Some later systems used MFM (double density)
//
// Track layout:
//   - Gap 1: ~40 bytes of 0xFF
//   - For each sector:
//     - Sync: 6 bytes of 0x00
//     - ID AM: 0xFE
//     - Track, Side, Sector, Size (4 bytes)
//     - CRC (2 bytes)
//     - Gap 2: 11 bytes of 0xFF
//     - Sync: 6 bytes of 0x00
//     - Data AM: 0xFB (or 0xF8 for deleted)
//     - Data: 256 bytes
//     - CRC (2 bytes)
//     - Gap 3: ~27 bytes of 0xFF
//   - Gap 4: Fill to index
//-----------------------------------------------------------------------------
