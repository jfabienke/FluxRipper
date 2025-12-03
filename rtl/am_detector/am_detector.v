//-----------------------------------------------------------------------------
// Address Mark Detector for FluxRipper
// Detects A1 (0x4489) and C2 (0x5224) sync patterns
//
// Based on CAPSImg CapsFDCEmulator.cpp FdcShiftBit() lines 2160-2223
//
// Updated: 2025-12-02 16:40
//-----------------------------------------------------------------------------

module am_detector (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_in,          // Serial bit input from DPLL
    input  wire        bit_valid,       // Bit is valid
    output reg         a1_detected,     // A1 sync mark detected
    output reg         c2_detected,     // C2 sync mark detected
    output reg  [1:0]  sync_count,      // Count of consecutive sync marks (0-3)
    output reg         sync_acquired,   // 3 consecutive A1 marks found
    output reg  [15:0] shift_reg,       // Current shift register value
    output reg  [4:0]  bit_count        // Bits since last sync
);

    // Sync mark patterns (MFM encoded with missing clock)
    // From CAPSImg CapsFDCEmulator.cpp
    localparam [15:0] MARK_A1 = 16'h4489;  // A1 with missing clock at bit 5
    localparam [15:0] MARK_C2 = 16'h5224;  // C2 mark (index address mark)

    // State machine
    localparam HUNT     = 2'b00;  // Hunting for sync
    localparam SYNC1    = 2'b01;  // Found 1 A1
    localparam SYNC2    = 2'b10;  // Found 2 A1s
    localparam SYNCED   = 2'b11;  // Found 3 A1s, sync acquired

    reg [1:0] state;
    reg [4:0] mark_distance;  // Distance since last sync mark

    always @(posedge clk) begin
        if (reset) begin
            shift_reg <= 16'h0000;
            a1_detected <= 1'b0;
            c2_detected <= 1'b0;
            sync_count <= 2'd0;
            sync_acquired <= 1'b0;
            bit_count <= 5'd0;
            state <= HUNT;
            mark_distance <= 5'd0;
        end else if (enable && bit_valid) begin
            // Default: clear detection flags
            a1_detected <= 1'b0;
            c2_detected <= 1'b0;

            // Shift in new bit
            shift_reg <= {shift_reg[14:0], bit_in};
            bit_count <= bit_count + 1'b1;
            mark_distance <= mark_distance + 1'b1;

            // Check for sync patterns
            if ({shift_reg[14:0], bit_in} == MARK_A1) begin
                a1_detected <= 1'b1;
                mark_distance <= 5'd0;

                case (state)
                    HUNT: begin
                        sync_count <= 2'd1;
                        state <= SYNC1;
                    end

                    SYNC1: begin
                        // Second A1 must be exactly 16 bits after first
                        if (mark_distance == 5'd15) begin
                            sync_count <= 2'd2;
                            state <= SYNC2;
                        end else begin
                            // Not consecutive, restart
                            sync_count <= 2'd1;
                            state <= SYNC1;
                        end
                    end

                    SYNC2: begin
                        if (mark_distance == 5'd15) begin
                            sync_count <= 2'd3;
                            sync_acquired <= 1'b1;
                            bit_count <= 5'd0;
                            state <= SYNCED;
                        end else begin
                            sync_count <= 2'd1;
                            state <= SYNC1;
                        end
                    end

                    SYNCED: begin
                        // Already synced, this is unexpected
                        // Could be data that looks like A1
                    end
                endcase

            end else if ({shift_reg[14:0], bit_in} == MARK_C2) begin
                c2_detected <= 1'b1;
                // C2 is index address mark, doesn't require triple sync
            end else begin
                // No sync mark - check for timeout
                if (mark_distance >= 5'd31) begin
                    // Too long without sync, reset
                    if (state != SYNCED) begin
                        state <= HUNT;
                        sync_count <= 2'd0;
                    end
                end
            end
        end else if (!enable) begin
            // Reset sync state when disabled
            state <= HUNT;
            sync_count <= 2'd0;
            sync_acquired <= 1'b0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Sync FSM - Controls data field parsing after sync acquisition
//-----------------------------------------------------------------------------
module sync_fsm (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        sync_acquired,   // From AM detector
    input  wire        a1_detected,
    input  wire        c2_detected,
    input  wire [7:0]  byte_in,         // Decoded byte from MFM decoder
    input  wire        byte_valid,
    output reg  [2:0]  field_type,      // Current field type
    output reg  [15:0] byte_count,      // Bytes in current field
    output reg         crc_reset,       // Reset CRC at start of field
    output reg         data_enable,     // Enable data capture
    output reg         header_complete, // Header field complete
    output reg         data_complete    // Data field complete
);

    // Field types
    localparam FT_IDLE     = 3'd0;
    localparam FT_ID_FIELD = 3'd1;  // Track/Head/Sector/Size + CRC
    localparam FT_DATA     = 3'd2;  // Sector data + CRC
    localparam FT_DELETED  = 3'd3;  // Deleted data
    localparam FT_ERROR    = 3'd4;  // CRC error or timeout

    // Address marks
    localparam AM_ID     = 8'hFE;  // ID Address Mark
    localparam AM_DATA   = 8'hFB;  // Data Address Mark
    localparam AM_DELETE = 8'hF8;  // Deleted Data Address Mark

    // State machine
    localparam S_HUNT    = 3'd0;
    localparam S_SYNC    = 3'd1;
    localparam S_AM      = 3'd2;
    localparam S_ID      = 3'd3;
    localparam S_GAP     = 3'd4;
    localparam S_DATA    = 3'd5;
    localparam S_CRC     = 3'd6;

    reg [2:0] state;
    reg [15:0] data_length;
    reg [7:0] sector_size;

    always @(posedge clk) begin
        if (reset) begin
            state <= S_HUNT;
            field_type <= FT_IDLE;
            byte_count <= 16'd0;
            crc_reset <= 1'b0;
            data_enable <= 1'b0;
            header_complete <= 1'b0;
            data_complete <= 1'b0;
            data_length <= 16'd0;
            sector_size <= 8'd0;
        end else if (enable) begin
            // Default outputs
            crc_reset <= 1'b0;
            header_complete <= 1'b0;
            data_complete <= 1'b0;

            case (state)
                S_HUNT: begin
                    field_type <= FT_IDLE;
                    data_enable <= 1'b0;
                    if (sync_acquired) begin
                        state <= S_AM;
                        crc_reset <= 1'b1;
                        byte_count <= 16'd0;
                    end
                end

                S_AM: begin
                    // Wait for address mark byte
                    if (byte_valid) begin
                        case (byte_in)
                            AM_ID: begin
                                field_type <= FT_ID_FIELD;
                                state <= S_ID;
                                data_enable <= 1'b1;
                                byte_count <= 16'd1;
                            end
                            AM_DATA: begin
                                field_type <= FT_DATA;
                                state <= S_DATA;
                                data_enable <= 1'b1;
                                byte_count <= 16'd1;
                                // Use sector size from previous ID field
                                data_length <= (16'd128 << sector_size);
                            end
                            AM_DELETE: begin
                                field_type <= FT_DELETED;
                                state <= S_DATA;
                                data_enable <= 1'b1;
                                byte_count <= 16'd1;
                                data_length <= (16'd128 << sector_size);
                            end
                            default: begin
                                // Unknown AM, return to hunt
                                state <= S_HUNT;
                            end
                        endcase
                    end
                end

                S_ID: begin
                    // ID field: C H R N CRC1 CRC2 (6 bytes)
                    if (byte_valid) begin
                        byte_count <= byte_count + 1'b1;

                        // Capture sector size (N field, byte 4)
                        if (byte_count == 16'd4) begin
                            sector_size <= byte_in[2:0];  // 0=128, 1=256, 2=512, 3=1024
                        end

                        // After CRC bytes
                        if (byte_count >= 16'd6) begin
                            header_complete <= 1'b1;
                            data_enable <= 1'b0;
                            state <= S_GAP;
                        end
                    end
                end

                S_GAP: begin
                    // Wait for next sync
                    field_type <= FT_IDLE;
                    if (sync_acquired) begin
                        state <= S_AM;
                        crc_reset <= 1'b1;
                        byte_count <= 16'd0;
                    end
                end

                S_DATA: begin
                    // Data field
                    if (byte_valid) begin
                        byte_count <= byte_count + 1'b1;

                        // After data + CRC
                        if (byte_count >= data_length + 16'd2) begin
                            data_complete <= 1'b1;
                            data_enable <= 1'b0;
                            state <= S_HUNT;
                        end
                    end
                end

                default: state <= S_HUNT;
            endcase

            // Handle new sync during any state
            if (sync_acquired && state != S_HUNT && state != S_AM) begin
                state <= S_AM;
                crc_reset <= 1'b1;
                byte_count <= 16'd0;
            end
        end else begin
            // Disabled
            state <= S_HUNT;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Combined AM Detector and Shift Register
//-----------------------------------------------------------------------------
module am_detector_with_shifter (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_in,
    input  wire        bit_valid,

    // AM detection outputs
    output wire        a1_detected,
    output wire        c2_detected,
    output wire [1:0]  sync_count,
    output wire        sync_acquired,

    // Byte assembly outputs
    output reg  [7:0]  data_byte,
    output reg         byte_ready,

    // Raw shift register (for diagnostics)
    output wire [15:0] raw_shift
);

    wire [4:0] bit_count;

    am_detector u_am_detector (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        .a1_detected(a1_detected),
        .c2_detected(c2_detected),
        .sync_count(sync_count),
        .sync_acquired(sync_acquired),
        .shift_reg(raw_shift),
        .bit_count(bit_count)
    );

    // Byte assembly from MFM stream
    // Extract data bits (every other bit starting from position 1)
    reg [3:0] mfm_bit_cnt;

    always @(posedge clk) begin
        if (reset || !enable) begin
            data_byte <= 8'h00;
            byte_ready <= 1'b0;
            mfm_bit_cnt <= 4'd0;
        end else if (bit_valid) begin
            byte_ready <= 1'b0;

            // Reset counter on sync
            if (sync_acquired && sync_count == 2'd3) begin
                mfm_bit_cnt <= 4'd0;
            end else begin
                mfm_bit_cnt <= mfm_bit_cnt + 1'b1;

                // Every 16 MFM bits = 1 byte
                // Data bits are at odd positions
                if (mfm_bit_cnt[0] == 1'b1) begin
                    data_byte <= {data_byte[6:0], bit_in};
                end

                if (mfm_bit_cnt == 4'd15) begin
                    byte_ready <= 1'b1;
                    mfm_bit_cnt <= 4'd0;
                end
            end
        end
    end

endmodule
