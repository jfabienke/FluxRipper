//-----------------------------------------------------------------------------
// hfe_protocol.v
// HxC HFE Format Handler
//
// Created: 2025-12-05 08:25
// Updated: 2025-12-06 01:45 - Corrected with official HxC format constants
//
// HFE file format encoder for HxC-compatible flux data output.
//
// IMPORTANT NOTES:
//   - HFE file format is publicly documented (hxc2001.com)
//   - Format constants from official GPL source (github.com/jfdelnero/HxCFloppyEmulator)
//   - USB command codes are FluxRipper-specific (NOT official HxC protocol)
//   - Real HxC USB uses streaming protocol with 0x33/0xCC/0xDD markers
//   - This implementation outputs correct HFE format but uses custom commands
//
// HFE Format Specification:
//   https://hxc2001.com/floppy_drive_emulator/HFE-file-format.html
//
// Format constants from HxCFloppyEmulator (GPL):
//   https://github.com/jfdelnero/HxCFloppyEmulator
//   (C) Jean-François DEL NERO, licensed under GPL
//
// HFE Format Structure:
//   - 512-byte header at offset 0 (signature "HXCPICFE")
//   - Track LUT at offset 512 (4 bytes per track: offset + length)
//   - Track data: 256-byte blocks interleaved (side0, side1, side0, ...)
//   - Little-endian, LSB-first bit order
//
// MFM Encoding:
//   - Bit cell contains clock (T) and data (D) windows
//   - "1" data bit: transition in D window only (01)
//   - "0" data bit after "1": no transitions (00)
//   - "0" data bit after "0": transition in T window only (10)
//-----------------------------------------------------------------------------

module hfe_protocol #(
    parameter MAX_TRACKS     = 166,    // Max tracks (83 cylinders * 2 sides)
    parameter TRACK_BUF_SIZE = 32768,  // Track buffer size (bytes)
    parameter SAMPLE_CLK_MHZ = 300     // FluxRipper sample clock
)(
    input  wire        clk,
    input  wire        rst_n,

    // USB endpoint interface
    input  wire [31:0] cmd_rx_data,
    input  wire        cmd_rx_valid,
    output reg         cmd_rx_ready,

    output reg  [31:0] resp_tx_data,
    output reg         resp_tx_valid,
    input  wire        resp_tx_ready,

    // Flux data interface (read path)
    input  wire [31:0] flux_in_data,      // [31]=INDEX, [26:0]=timestamp delta
    input  wire        flux_in_valid,
    output reg         flux_in_ready,

    output reg  [7:0]  hfe_out_data,
    output reg         hfe_out_valid,
    input  wire        hfe_out_ready,

    // Flux data interface (write path)
    input  wire [7:0]  hfe_in_data,       // MFM cell data from host
    input  wire        hfe_in_valid,
    output reg         hfe_in_ready,

    output reg  [31:0] flux_out_data,     // Flux timing for write
    output reg         flux_out_valid,
    input  wire        flux_out_ready,

    // Drive interface
    output reg  [7:0]  drv_cylinder,
    output reg         drv_head,
    output reg         drv_motor_on,
    output reg         drv_select,
    output reg         drv_write_gate,    // Write gate for write operations

    input  wire        drv_ready,
    input  wire        drv_index,
    input  wire        drv_write_protect,

    // Configuration
    input  wire [7:0]  cfg_tracks,       // Number of tracks
    input  wire [7:0]  cfg_sides,        // 1 or 2
    input  wire [15:0] cfg_bitrate,      // kbit/s (250, 300, 500)
    input  wire [15:0] cfg_rpm,          // 300 or 360
    input  wire [7:0]  cfg_encoding,     // Track encoding type

    // Status
    output reg  [7:0]  hfe_state,
    output reg  [15:0] current_track,
    output reg         read_active,
    output reg         write_active
);

    //=========================================================================
    // FluxRipper Command Codes (NOT official HxC protocol)
    //=========================================================================
    // NOTE: These are FluxRipper-specific command codes for FIFO-based USB.
    // Real HxC USB protocol uses streaming with 0x33/0xCC/0xDD markers.
    // These commands allow HFE file output but are not HxC-compatible.

    localparam HFE_CMD_GET_INFO      = 8'h00;
    localparam HFE_CMD_READ_TRACK    = 8'h01;
    localparam HFE_CMD_WRITE_TRACK   = 8'h02;
    localparam HFE_CMD_GET_STATUS    = 8'h03;
    localparam HFE_CMD_SET_TRACK     = 8'h04;
    localparam HFE_CMD_SET_SIDE      = 8'h05;
    localparam HFE_CMD_MOTOR_ON      = 8'h06;
    localparam HFE_CMD_MOTOR_OFF     = 8'h07;
    localparam HFE_CMD_SELECT        = 8'h08;
    localparam HFE_CMD_DESELECT      = 8'h09;

    //=========================================================================
    // HFE Track Encoding Types (from official HxCFloppyEmulator GPL source)
    //=========================================================================
    // Source: github.com/jfdelnero/HxCFloppyEmulator/blob/master/libhxcfe/
    //         sources/libhxcfe/floppy_loader/hfe_loader/hfe_format.h

    localparam ENC_ISOIBM_MFM        = 8'h00;  // IBM PC MFM
    localparam ENC_AMIGA_MFM         = 8'h01;  // Amiga MFM
    localparam ENC_ISOIBM_FM         = 8'h02;  // IBM PC FM
    localparam ENC_EMU_FM            = 8'h03;  // Emu FM
    localparam ENC_TYCOM_FM          = 8'h04;  // Tycom FM
    localparam ENC_MEMBRAIN_MFM      = 8'h05;  // Membrain MFM
    localparam ENC_APPLEII_GCR1      = 8'h06;  // Apple II GCR (5.25")
    localparam ENC_APPLEII_GCR2      = 8'h07;  // Apple II GCR (5.25" 2)
    localparam ENC_APPLEII_HDDD_GCR1 = 8'h08;  // Apple II HDDD GCR
    localparam ENC_APPLEII_HDDD_GCR2 = 8'h09;  // Apple II HDDD GCR 2
    localparam ENC_ARBURGDAT         = 8'h0A;  // Arburg Data
    localparam ENC_ARBURGSYS         = 8'h0B;  // Arburg System
    localparam ENC_AED6200P_MFM      = 8'h0C;  // AED 6200P MFM
    localparam ENC_NORTHSTAR_HS_MFM  = 8'h0D;  // NorthStar HS MFM
    localparam ENC_HEATHKIT_HS_FM    = 8'h0E;  // Heathkit HS FM
    localparam ENC_DEC_RX02_M2FM     = 8'h0F;  // DEC RX02 M2FM
    localparam ENC_APPLEMAC_GCR      = 8'h10;  // Apple Mac GCR
    localparam ENC_QD_MO5_MFM        = 8'h11;  // QD MO5 MFM
    localparam ENC_C64_GCR           = 8'h12;  // Commodore 64 GCR
    localparam ENC_VICTOR9K_GCR      = 8'h13;  // Victor 9000 GCR
    localparam ENC_MICRALN_HS_FM     = 8'h14;  // Micral N HS FM
    localparam ENC_SMC_MFM           = 8'h15;  // SMC MFM
    localparam ENC_UNKNOWN           = 8'hFF;  // Unknown encoding

    //=========================================================================
    // HFE Header Structure (PICFILEFORMATHEADER)
    //=========================================================================

    // Header is 512 bytes at offset 0
    reg [7:0]  hfe_signature [0:7];      // "HXCPICFE"
    reg [7:0]  hfe_revision;             // Format revision (0)
    reg [7:0]  hfe_num_tracks;
    reg [7:0]  hfe_num_sides;
    reg [7:0]  hfe_track_encoding;
    reg [15:0] hfe_bitrate;              // kbit/s
    reg [15:0] hfe_rpm;
    reg [7:0]  hfe_interface_mode;
    reg [15:0] hfe_track_list_offset;    // Offset to track LUT

    //=========================================================================
    // Track LUT
    //=========================================================================

    // Each entry is 4 bytes: [offset (16-bit), length (16-bit)]
    reg [15:0] track_offset [0:MAX_TRACKS-1];
    reg [15:0] track_length [0:MAX_TRACKS-1];

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_IDLE           = 4'd0;
    localparam ST_CMD_DECODE     = 4'd1;
    localparam ST_SEND_HEADER    = 4'd2;
    localparam ST_SEND_TRACK_LUT = 4'd3;
    localparam ST_READ_TRACK     = 4'd4;
    localparam ST_STREAM_TRACK   = 4'd5;
    localparam ST_SEND_RESPONSE  = 4'd6;
    localparam ST_ERROR          = 4'd7;
    localparam ST_WRITE_TRACK    = 4'd8;
    localparam ST_WRITE_WAIT_IDX = 4'd9;
    localparam ST_WRITE_STREAM   = 4'd10;
    localparam ST_WRITE_DONE     = 4'd11;

    reg [3:0]  state;
    reg [7:0]  cmd_code;
    reg [15:0] byte_count;
    reg [15:0] target_bytes;

    //=========================================================================
    // HFE Initialization
    //=========================================================================

    integer i;

    initial begin
        // Signature "HXCPICFE"
        hfe_signature[0] = "H";
        hfe_signature[1] = "X";
        hfe_signature[2] = "C";
        hfe_signature[3] = "P";
        hfe_signature[4] = "I";
        hfe_signature[5] = "C";
        hfe_signature[6] = "F";
        hfe_signature[7] = "E";

        hfe_revision          = 8'h00;
        hfe_num_tracks        = 8'd80;   // Default 80 tracks
        hfe_num_sides         = 8'd2;    // Default 2 sides
        hfe_track_encoding    = ENC_ISOIBM_MFM;
        hfe_bitrate           = 16'd250; // 250 kbit/s
        hfe_rpm               = 16'd300; // 300 RPM
        hfe_interface_mode    = 8'h00;   // Generic
        hfe_track_list_offset = 16'h0200; // Track LUT at 512

        // Initialize track LUT with placeholder values
        for (i = 0; i < MAX_TRACKS; i = i + 1) begin
            track_offset[i] = 16'h0400 + (i * 16'h0800);  // 2KB per track
            track_length[i] = 16'h0800;  // 2KB
        end
    end

    //=========================================================================
    // Flux to MFM Cell Conversion
    //=========================================================================

    // MFM bit cell timing (in 300 MHz clocks):
    //   250 kbit/s: 1200 clocks per bit cell (4µs)
    //   300 kbit/s: 1000 clocks per bit cell (3.33µs)
    //   500 kbit/s:  600 clocks per bit cell (2µs)
    //
    // Each bit cell has a clock window (T) and data window (D)
    // Flux transition in T window = clock bit set
    // Flux transition in D window = data bit set

    reg [15:0] bit_cell_period;      // Clocks per bit cell
    reg [15:0] half_cell_period;     // Clocks per half cell (T or D window)
    reg [15:0] cell_tolerance;       // Timing tolerance window

    // Calculate bit cell period from bitrate
    // bit_cell_period = (SAMPLE_CLK_MHZ * 1000) / cfg_bitrate
    // Simplified: use lookup for common rates
    always @(*) begin
        case (cfg_bitrate)
            16'd250: begin
                bit_cell_period  = 16'd1200;  // 300MHz / 250kHz = 1200
                half_cell_period = 16'd600;
                cell_tolerance   = 16'd200;
            end
            16'd300: begin
                bit_cell_period  = 16'd1000;  // 300MHz / 300kHz = 1000
                half_cell_period = 16'd500;
                cell_tolerance   = 16'd166;
            end
            16'd500: begin
                bit_cell_period  = 16'd600;   // 300MHz / 500kHz = 600
                half_cell_period = 16'd300;
                cell_tolerance   = 16'd100;
            end
            default: begin
                bit_cell_period  = 16'd1000;  // Default to 300 kbit/s
                half_cell_period = 16'd500;
                cell_tolerance   = 16'd166;
            end
        endcase
    end

    // MFM decoder state
    reg [15:0] flux_accumulator;     // Accumulated flux timing
    reg [7:0]  mfm_shift_reg;        // Shift register for MFM bits
    reg [2:0]  mfm_bit_count;        // Bits accumulated (0-7)
    reg        prev_data_bit;        // Previous data bit for MFM encoding

    // Dual-side interleaving buffers (256 bytes each)
    reg [7:0]  side0_buffer [0:255];
    reg [7:0]  side1_buffer [0:255];
    reg [7:0]  side0_wr_ptr;
    reg [7:0]  side1_wr_ptr;
    reg [7:0]  interleave_rd_ptr;
    reg        current_side;         // 0=side0, 1=side1
    reg        output_side;          // Which side to output next
    reg [8:0]  block_count;          // 256-byte blocks written

    // Track data accumulator for LUT calculation
    reg [15:0] track_byte_count;     // Bytes in current track
    reg [7:0]  tracks_captured;      // Number of tracks with valid data

    //=========================================================================
    // MFM to Flux Conversion (for write path)
    //=========================================================================

    // Convert MFM bit cells back to flux transitions
    reg [7:0]  write_shift_reg;      // MFM bits to write
    reg [2:0]  write_bit_count;      // Bits remaining
    reg [15:0] write_flux_timer;     // Timing accumulator
    reg        write_prev_bit;       // Previous MFM bit (for transition detection)

    //=========================================================================
    // State Machine
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            cmd_rx_ready   <= 1'b0;
            resp_tx_valid  <= 1'b0;
            resp_tx_data   <= 32'h0;
            flux_in_ready  <= 1'b0;
            hfe_out_valid  <= 1'b0;
            hfe_out_data   <= 8'h0;
            hfe_in_ready   <= 1'b0;
            flux_out_valid <= 1'b0;
            flux_out_data  <= 32'h0;

            drv_cylinder   <= 8'h0;
            drv_head       <= 1'b0;
            drv_motor_on   <= 1'b0;
            drv_select     <= 1'b0;
            drv_write_gate <= 1'b0;

            hfe_state      <= 8'h0;
            current_track  <= 16'h0;
            read_active    <= 1'b0;
            write_active   <= 1'b0;
            byte_count     <= 16'h0;
            cmd_code       <= 8'h0;

            // MFM decoder state
            flux_accumulator   <= 16'h0;
            mfm_shift_reg      <= 8'h0;
            mfm_bit_count      <= 3'h0;
            prev_data_bit      <= 1'b0;

            // Interleaving state
            side0_wr_ptr       <= 8'h0;
            side1_wr_ptr       <= 8'h0;
            interleave_rd_ptr  <= 8'h0;
            current_side       <= 1'b0;
            output_side        <= 1'b0;
            block_count        <= 9'h0;
            track_byte_count   <= 16'h0;
            tracks_captured    <= 8'h0;

            // Write path state
            write_shift_reg    <= 8'h0;
            write_bit_count    <= 3'h0;
            write_flux_timer   <= 16'h0;
            write_prev_bit     <= 1'b0;
        end else begin
            // Defaults
            cmd_rx_ready  <= 1'b0;
            resp_tx_valid <= 1'b0;
            hfe_out_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    hfe_state <= 8'h00;
                    if (cmd_rx_valid) begin
                        cmd_rx_ready <= 1'b1;
                        cmd_code     <= cmd_rx_data[7:0];
                        state        <= ST_CMD_DECODE;
                    end
                end

                ST_CMD_DECODE: begin
                    hfe_state <= 8'h01;

                    case (cmd_code)
                        HFE_CMD_GET_INFO: begin
                            // Update header from configuration
                            hfe_num_tracks     <= cfg_tracks;
                            hfe_num_sides      <= cfg_sides;
                            hfe_bitrate        <= cfg_bitrate;
                            hfe_rpm            <= cfg_rpm;
                            hfe_track_encoding <= cfg_encoding;

                            byte_count   <= 16'h0;
                            target_bytes <= 16'd512;  // Header is 512 bytes
                            state        <= ST_SEND_HEADER;
                        end

                        HFE_CMD_READ_TRACK: begin
                            current_track <= {cmd_rx_data[15:8], cmd_rx_data[23:16]};
                            drv_cylinder  <= cmd_rx_data[15:8];
                            drv_head      <= cmd_rx_data[16];
                            read_active   <= 1'b1;
                            flux_in_ready <= 1'b1;
                            byte_count    <= 16'h0;
                            state         <= ST_READ_TRACK;
                        end

                        HFE_CMD_SET_TRACK: begin
                            drv_cylinder <= cmd_rx_data[15:8];
                            state        <= ST_SEND_RESPONSE;
                        end

                        HFE_CMD_SET_SIDE: begin
                            drv_head <= cmd_rx_data[8];
                            state    <= ST_SEND_RESPONSE;
                        end

                        HFE_CMD_MOTOR_ON: begin
                            drv_motor_on <= 1'b1;
                            state        <= ST_SEND_RESPONSE;
                        end

                        HFE_CMD_MOTOR_OFF: begin
                            drv_motor_on <= 1'b0;
                            state        <= ST_SEND_RESPONSE;
                        end

                        HFE_CMD_SELECT: begin
                            drv_select <= 1'b1;
                            state      <= ST_SEND_RESPONSE;
                        end

                        HFE_CMD_DESELECT: begin
                            drv_select <= 1'b0;
                            state      <= ST_SEND_RESPONSE;
                        end

                        HFE_CMD_GET_STATUS: begin
                            resp_tx_data <= {16'h0, current_track[7:0], hfe_state};
                            state        <= ST_SEND_RESPONSE;
                        end

                        HFE_CMD_WRITE_TRACK: begin
                            // Check write protect
                            if (drv_write_protect) begin
                                resp_tx_data <= {24'h000000, 8'h02};  // Write protected
                                state        <= ST_SEND_RESPONSE;
                            end else begin
                                current_track    <= {cmd_rx_data[15:8], cmd_rx_data[23:16]};
                                drv_cylinder     <= cmd_rx_data[15:8];
                                drv_head         <= cmd_rx_data[16];
                                write_active     <= 1'b1;
                                byte_count       <= 16'h0;
                                write_shift_reg  <= 8'h0;
                                write_bit_count  <= 3'h0;
                                write_flux_timer <= 16'h0;
                                write_prev_bit   <= 1'b0;
                                state            <= ST_WRITE_TRACK;
                            end
                        end

                        default: begin
                            state <= ST_ERROR;
                        end
                    endcase
                end

                ST_SEND_HEADER: begin
                    hfe_state <= 8'h02;

                    if (resp_tx_ready) begin
                        // Send header bytes (4 at a time)
                        case (byte_count[8:2])  // Word index
                            0: resp_tx_data <= {hfe_signature[3], hfe_signature[2],
                                               hfe_signature[1], hfe_signature[0]};
                            1: resp_tx_data <= {hfe_signature[7], hfe_signature[6],
                                               hfe_signature[5], hfe_signature[4]};
                            2: resp_tx_data <= {hfe_track_encoding, hfe_num_sides,
                                               hfe_num_tracks, hfe_revision};
                            3: resp_tx_data <= {hfe_rpm, hfe_bitrate};
                            4: resp_tx_data <= {hfe_track_list_offset, 8'h00, hfe_interface_mode};
                            default: resp_tx_data <= 32'h00000000;  // Padding
                        endcase

                        resp_tx_valid <= 1'b1;
                        byte_count    <= byte_count + 16'd4;

                        if (byte_count + 16'd4 >= target_bytes)
                            state <= ST_SEND_TRACK_LUT;
                    end
                end

                ST_SEND_TRACK_LUT: begin
                    hfe_state <= 8'h03;

                    if (resp_tx_ready) begin
                        // Send track LUT entries (4 bytes per track)
                        resp_tx_data <= {track_length[byte_count[9:2]],
                                        track_offset[byte_count[9:2]]};
                        resp_tx_valid <= 1'b1;
                        byte_count    <= byte_count + 16'd4;

                        if (byte_count[9:2] >= hfe_num_tracks - 1)
                            state <= ST_IDLE;
                    end
                end

                ST_READ_TRACK: begin
                    hfe_state <= 8'h04;

                    // Wait for index pulse to start
                    if (drv_index) begin
                        byte_count        <= 16'h0;
                        current_side      <= 1'b0;
                        flux_accumulator  <= 16'h0;
                        mfm_shift_reg     <= 8'h0;
                        mfm_bit_count     <= 3'h0;
                        prev_data_bit     <= 1'b0;
                        side0_wr_ptr      <= 8'h0;
                        side1_wr_ptr      <= 8'h0;
                        interleave_rd_ptr <= 8'h0;
                        output_side       <= 1'b0;
                        block_count       <= 9'h0;
                        track_byte_count  <= 16'h0;
                        state             <= ST_STREAM_TRACK;
                    end
                end

                ST_STREAM_TRACK: begin
                    hfe_state     <= 8'h05;
                    flux_in_ready <= 1'b1;

                    //----------------------------------------------------------
                    // Flux to MFM Conversion
                    //----------------------------------------------------------
                    // HFE format stores MFM bit cells as bytes
                    // Each flux transition timing maps to cell boundaries
                    //
                    // Algorithm:
                    // 1. Accumulate flux timing
                    // 2. For each bit cell period, determine if transition
                    //    occurred in clock (T) or data (D) window
                    // 3. MFM decoding: T=clock, D=data
                    //    - Transition in D window = data "1"
                    //    - Transition in T window only = data "0" (after "0")
                    //    - No transition = data "0" (after "1")
                    //----------------------------------------------------------

                    if (flux_in_valid) begin
                        // Extract flux delta (27-bit timestamp in 300MHz clocks)
                        flux_accumulator <= flux_accumulator + flux_in_data[15:0];

                        // Process accumulated time into MFM bit cells
                        if (flux_accumulator >= bit_cell_period) begin
                            // Determine how many bit cells this transition spans
                            // and where within the cell the transition occurred

                            // Check if transition is in data window (second half)
                            if (flux_accumulator >= half_cell_period - cell_tolerance &&
                                flux_accumulator < bit_cell_period - cell_tolerance) begin
                                // Transition in data window = data "1"
                                mfm_shift_reg <= {mfm_shift_reg[6:0], 1'b1};
                                prev_data_bit <= 1'b1;
                            end else begin
                                // Transition in clock window or gap = data "0"
                                mfm_shift_reg <= {mfm_shift_reg[6:0], 1'b0};
                                prev_data_bit <= 1'b0;
                            end

                            mfm_bit_count    <= mfm_bit_count + 1'b1;
                            flux_accumulator <= flux_accumulator - bit_cell_period;

                            // When we have 8 bits, write to appropriate side buffer
                            if (mfm_bit_count == 3'd7) begin
                                if (current_side == 1'b0) begin
                                    side0_buffer[side0_wr_ptr] <= {mfm_shift_reg[6:0],
                                        (flux_accumulator >= half_cell_period - cell_tolerance &&
                                         flux_accumulator < bit_cell_period - cell_tolerance) ? 1'b1 : 1'b0};
                                    side0_wr_ptr <= side0_wr_ptr + 1'b1;
                                end else begin
                                    side1_buffer[side1_wr_ptr] <= {mfm_shift_reg[6:0],
                                        (flux_accumulator >= half_cell_period - cell_tolerance &&
                                         flux_accumulator < bit_cell_period - cell_tolerance) ? 1'b1 : 1'b0};
                                    side1_wr_ptr <= side1_wr_ptr + 1'b1;
                                end
                                track_byte_count <= track_byte_count + 1'b1;
                            end
                        end
                    end

                    //----------------------------------------------------------
                    // Dual-Side Interleaved Output
                    //----------------------------------------------------------
                    // HFE format: 256-byte blocks interleaved [side0][side1][side0]...
                    // Output when we have a full block from each side
                    //----------------------------------------------------------

                    if (hfe_out_ready) begin
                        // Check if we have data to output
                        if (output_side == 1'b0 && side0_wr_ptr > interleave_rd_ptr) begin
                            // Output from side 0 buffer
                            hfe_out_data  <= side0_buffer[interleave_rd_ptr];
                            hfe_out_valid <= 1'b1;

                            if (interleave_rd_ptr == 8'hFF) begin
                                // Finished 256-byte block, switch to side 1
                                output_side       <= 1'b1;
                                interleave_rd_ptr <= 8'h0;
                                block_count       <= block_count + 1'b1;
                            end else begin
                                interleave_rd_ptr <= interleave_rd_ptr + 1'b1;
                            end
                        end else if (output_side == 1'b1 && side1_wr_ptr > interleave_rd_ptr) begin
                            // Output from side 1 buffer
                            hfe_out_data  <= side1_buffer[interleave_rd_ptr];
                            hfe_out_valid <= 1'b1;

                            if (interleave_rd_ptr == 8'hFF) begin
                                // Finished 256-byte block, switch to side 0
                                output_side       <= 1'b0;
                                interleave_rd_ptr <= 8'h0;
                                block_count       <= block_count + 1'b1;
                                // Reset write pointers for next block pair
                                side0_wr_ptr      <= 8'h0;
                                side1_wr_ptr      <= 8'h0;
                            end else begin
                                interleave_rd_ptr <= interleave_rd_ptr + 1'b1;
                            end
                        end
                    end

                    //----------------------------------------------------------
                    // Track Completion
                    //----------------------------------------------------------
                    // End track on second index pulse
                    //----------------------------------------------------------

                    if (drv_index && track_byte_count > 16'd512) begin
                        // Update track LUT with actual captured length
                        track_length[current_track[7:0]] <= track_byte_count;
                        tracks_captured <= tracks_captured + 1'b1;

                        read_active   <= 1'b0;
                        flux_in_ready <= 1'b0;
                        state         <= ST_SEND_RESPONSE;
                    end
                end

                ST_SEND_RESPONSE: begin
                    hfe_state <= 8'h06;

                    if (resp_tx_ready) begin
                        resp_tx_data  <= {24'h000000, 8'h00};  // ACK OK
                        resp_tx_valid <= 1'b1;
                        state         <= ST_IDLE;
                    end
                end

                ST_ERROR: begin
                    hfe_state <= 8'hFF;

                    if (resp_tx_ready) begin
                        resp_tx_data  <= {24'h000000, 8'hFF};  // Error
                        resp_tx_valid <= 1'b1;
                        state         <= ST_IDLE;
                    end
                end

                //=============================================================
                // Write Track States
                //=============================================================

                ST_WRITE_TRACK: begin
                    hfe_state     <= 8'h08;
                    hfe_in_ready  <= 1'b0;

                    // Initialize for write operation
                    side0_wr_ptr      <= 8'h0;
                    side1_wr_ptr      <= 8'h0;
                    interleave_rd_ptr <= 8'h0;
                    current_side      <= 1'b0;
                    block_count       <= 9'h0;
                    track_byte_count  <= 16'h0;

                    // Wait for motor ready and drive selection
                    if (drv_ready && drv_motor_on && drv_select) begin
                        state <= ST_WRITE_WAIT_IDX;
                    end
                end

                ST_WRITE_WAIT_IDX: begin
                    hfe_state    <= 8'h09;
                    hfe_in_ready <= 1'b1;

                    //----------------------------------------------------------
                    // Pre-buffer HFE data while waiting for index
                    //----------------------------------------------------------
                    // Fill side buffers with de-interleaved data from host
                    // HFE format: alternating 256-byte blocks [s0][s1][s0]...
                    //----------------------------------------------------------

                    if (hfe_in_valid) begin
                        if (current_side == 1'b0) begin
                            side0_buffer[side0_wr_ptr] <= hfe_in_data;
                            side0_wr_ptr <= side0_wr_ptr + 1'b1;
                            if (side0_wr_ptr == 8'hFF) begin
                                current_side <= 1'b1;
                                block_count  <= block_count + 1'b1;
                            end
                        end else begin
                            side1_buffer[side1_wr_ptr] <= hfe_in_data;
                            side1_wr_ptr <= side1_wr_ptr + 1'b1;
                            if (side1_wr_ptr == 8'hFF) begin
                                current_side <= 1'b0;
                                block_count  <= block_count + 1'b1;
                            end
                        end
                        byte_count <= byte_count + 1'b1;
                    end

                    // Start writing on index pulse when we have data
                    if (drv_index && byte_count >= 16'd256) begin
                        interleave_rd_ptr <= 8'h0;
                        output_side       <= 1'b0;  // Start with side 0
                        drv_write_gate    <= 1'b1;
                        state             <= ST_WRITE_STREAM;
                    end
                end

                ST_WRITE_STREAM: begin
                    hfe_state    <= 8'h0A;
                    hfe_in_ready <= 1'b1;

                    //----------------------------------------------------------
                    // MFM to Flux Conversion
                    //----------------------------------------------------------
                    // Convert MFM bit cells to flux transition timings
                    // Each '1' bit = transition, '0' bit = no transition
                    // Timing based on bit cell period
                    //----------------------------------------------------------

                    // Continue buffering incoming HFE data
                    if (hfe_in_valid) begin
                        if (current_side == 1'b0) begin
                            side0_buffer[side0_wr_ptr] <= hfe_in_data;
                            if (side0_wr_ptr != 8'hFF) side0_wr_ptr <= side0_wr_ptr + 1'b1;
                        end else begin
                            side1_buffer[side1_wr_ptr] <= hfe_in_data;
                            if (side1_wr_ptr != 8'hFF) side1_wr_ptr <= side1_wr_ptr + 1'b1;
                        end
                    end

                    // Process MFM bytes to flux
                    if (write_bit_count == 3'd0) begin
                        // Load next byte from appropriate side buffer
                        if (drv_head == 1'b0) begin
                            write_shift_reg <= side0_buffer[interleave_rd_ptr];
                        end else begin
                            write_shift_reg <= side1_buffer[interleave_rd_ptr];
                        end
                        write_bit_count <= 3'd7;
                        interleave_rd_ptr <= interleave_rd_ptr + 1'b1;

                        // Track byte count for LUT update
                        track_byte_count <= track_byte_count + 1'b1;

                        // Handle 256-byte block boundary
                        if (interleave_rd_ptr == 8'hFF) begin
                            // Switch side buffers for next block
                            if (output_side == 1'b0 && cfg_sides == 8'd2) begin
                                output_side <= 1'b1;
                            end else begin
                                output_side  <= 1'b0;
                            end
                        end
                    end else begin
                        // Generate flux timing for current bit
                        write_flux_timer <= write_flux_timer + 1'b1;

                        if (write_flux_timer >= bit_cell_period) begin
                            write_flux_timer <= 16'h0;

                            // Check if this bit is a '1' (transition)
                            if (write_shift_reg[7]) begin
                                // Output flux transition timing
                                flux_out_data  <= {5'h0, write_flux_timer + half_cell_period};
                                flux_out_valid <= 1'b1;
                            end

                            // Shift to next bit
                            write_shift_reg <= {write_shift_reg[6:0], 1'b0};
                            write_bit_count <= write_bit_count - 1'b1;
                            write_prev_bit  <= write_shift_reg[7];
                        end
                    end

                    // Check for flux output handshake
                    if (flux_out_valid && flux_out_ready) begin
                        flux_out_valid <= 1'b0;
                    end

                    // End write on index pulse (full revolution)
                    if (drv_index && track_byte_count > 16'd512) begin
                        drv_write_gate <= 1'b0;
                        state          <= ST_WRITE_DONE;
                    end
                end

                ST_WRITE_DONE: begin
                    hfe_state      <= 8'h0B;
                    hfe_in_ready   <= 1'b0;
                    flux_out_valid <= 1'b0;
                    write_active   <= 1'b0;

                    // Update track LUT with written length
                    track_length[current_track[7:0]] <= track_byte_count;

                    // Send success response
                    resp_tx_data <= {16'h0, track_byte_count[15:8], 8'h00};  // OK + bytes written
                    state        <= ST_SEND_RESPONSE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
