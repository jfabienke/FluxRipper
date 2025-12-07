//-----------------------------------------------------------------------------
// raw_interface.v
// USB Vendor-Specific Raw Mode Interface
//
// Created: 2025-12-05 16:20
//
// Provides vendor-specific USB interface for:
//   - Raw flux capture with 32-bit timestamps
//   - Track-level access with metadata
//   - Signal quality and PLL diagnostics
//
// Command Protocol:
//   - Host sends 16-byte command packets (magic + cmd + params)
//   - Device responds with variable-length data packets
//   - Magic signature: 0x46525751 ("FRWQ" - FluxRipper Wireless Query)
//
// Command Set:
//   0x00  NOP                 - Status query
//   0x01  GET_INFO            - Device/version info
//   0x02  SELECT_DRIVE        - Select physical drive (0-3)
//   0x03  MOTOR_ON/OFF        - Motor control
//   0x05  SEEK                - Seek to track
//   0x10  CAPTURE_START       - Begin flux capture
//   0x11  CAPTURE_STOP        - End flux capture
//   0x13  READ_FLUX           - Stream flux data
//   0x20  READ_TRACK_RAW      - Read track with metadata
//   0x30  GET_PLL_STATUS      - PLL diagnostics
//   0x31  GET_SIGNAL_QUAL     - Signal quality metrics
//   0x40  GET_DRIVE_PROFILE   - Detected drive parameters
//-----------------------------------------------------------------------------

module raw_interface #(
    parameter RAW_SIGNATURE    = 32'h46525751,  // "FRWQ"
    parameter MAX_DRIVES       = 4,
    parameter FLUX_TIMESTAMP_BITS = 27,
    parameter FIFO_DEPTH       = 4096           // Flux data FIFO depth
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // USB Interface (from composite mux)
    //=========================================================================

    input  wire [31:0] usb_rx_data,
    input  wire        usb_rx_valid,
    output wire        usb_rx_ready,

    output reg  [31:0] usb_tx_data,
    output reg         usb_tx_valid,
    input  wire        usb_tx_ready,

    //=========================================================================
    // FluxRipper HAL Interface - FDD
    //=========================================================================

    output reg  [1:0]  fdd_select,
    output reg         fdd_motor_on,
    output reg  [7:0]  fdd_track,
    output reg         fdd_seek_cmd,
    input  wire        fdd_seek_done,
    input  wire        fdd_disk_present,
    input  wire        fdd_write_prot,
    input  wire        fdd_index,
    input  wire        fdd_track0,

    //=========================================================================
    // FluxRipper HAL Interface - HDD
    //=========================================================================

    output reg  [1:0]  hdd_select,
    input  wire        hdd_ready,
    input  wire [31:0] hdd_capacity,

    //=========================================================================
    // Flux Capture Interface
    //=========================================================================

    // Capture control
    output reg         capture_enable,
    output reg         capture_arm,
    input  wire        capture_active,
    input  wire        capture_overflow,

    // Flux data input (from flux_sampler)
    input  wire [31:0] flux_data,         // [31]=INDEX, [30]=overflow, [29]=weak, [26:0]=timestamp
    input  wire        flux_valid,
    output wire        flux_ready,

    //=========================================================================
    // PLL Diagnostics Interface
    //=========================================================================

    input  wire [15:0] pll_frequency,     // Current PLL frequency
    input  wire        pll_locked,
    input  wire [7:0]  pll_lock_count,
    input  wire [7:0]  pll_error_count,

    //=========================================================================
    // Signal Quality Interface
    //=========================================================================

    input  wire [15:0] signal_amplitude,
    input  wire [15:0] signal_noise,
    input  wire [7:0]  bit_error_rate,
    input  wire [15:0] jitter_ns,

    //=========================================================================
    // Status
    //=========================================================================

    output reg  [7:0]  raw_state,
    output reg  [7:0]  last_command,
    output reg         command_error
);

    //=========================================================================
    // Command Definitions
    //=========================================================================

    localparam CMD_NOP              = 8'h00;
    localparam CMD_GET_INFO         = 8'h01;
    localparam CMD_SELECT_DRIVE     = 8'h02;
    localparam CMD_MOTOR_CTRL       = 8'h03;
    localparam CMD_SEEK             = 8'h05;
    localparam CMD_CAPTURE_START    = 8'h10;
    localparam CMD_CAPTURE_STOP     = 8'h11;
    localparam CMD_READ_FLUX        = 8'h13;
    localparam CMD_READ_TRACK_RAW   = 8'h20;
    localparam CMD_GET_PLL_STATUS   = 8'h30;
    localparam CMD_GET_SIGNAL_QUAL  = 8'h31;
    localparam CMD_GET_DRIVE_PROFILE= 8'h40;

    //=========================================================================
    // Response Codes
    //=========================================================================

    localparam RSP_OK               = 8'h00;
    localparam RSP_ERR_INVALID_CMD  = 8'h01;
    localparam RSP_ERR_INVALID_PARAM= 8'h02;
    localparam RSP_ERR_NO_DRIVE     = 8'h03;
    localparam RSP_ERR_NOT_READY    = 8'h04;
    localparam RSP_ERR_OVERFLOW     = 8'h05;

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_IDLE          = 4'd0;
    localparam ST_RX_CMD_1      = 4'd1;
    localparam ST_RX_CMD_2      = 4'd2;
    localparam ST_RX_CMD_3      = 4'd3;
    localparam ST_VALIDATE      = 4'd4;
    localparam ST_EXECUTE       = 4'd5;
    localparam ST_TX_RESPONSE   = 4'd6;
    localparam ST_TX_DATA       = 4'd7;
    localparam ST_STREAM_FLUX   = 4'd8;
    localparam ST_WAIT_SEEK     = 4'd9;
    localparam ST_ERROR         = 4'd10;

    reg [3:0] state;

    //=========================================================================
    // Command Packet Buffer (16 bytes = 4 words)
    //=========================================================================

    reg [31:0] cmd_word0;   // Magic signature
    reg [31:0] cmd_word1;   // [31:24]=cmd, [23:16]=param1, [15:0]=param2
    reg [31:0] cmd_word2;   // Extended parameters
    reg [31:0] cmd_word3;   // Extended parameters

    wire [7:0]  cmd_opcode = cmd_word1[31:24];
    wire [7:0]  cmd_param1 = cmd_word1[23:16];
    wire [15:0] cmd_param2 = cmd_word1[15:0];
    wire [31:0] cmd_param3 = cmd_word2;
    wire [31:0] cmd_param4 = cmd_word3;

    //=========================================================================
    // Response Buffer
    //=========================================================================

    reg [31:0] rsp_buffer [0:15];   // Up to 64 bytes response
    reg [4:0]  rsp_len;             // Response length in words
    reg [4:0]  rsp_idx;             // Current response index

    //=========================================================================
    // Flux Data FIFO
    //=========================================================================

    reg [31:0] flux_fifo [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH):0] flux_wr_ptr;
    reg [$clog2(FIFO_DEPTH):0] flux_rd_ptr;

    wire [$clog2(FIFO_DEPTH):0] flux_count = flux_wr_ptr - flux_rd_ptr;
    wire flux_fifo_empty = (flux_wr_ptr == flux_rd_ptr);
    wire flux_fifo_full  = (flux_count == FIFO_DEPTH);

    assign flux_ready = !flux_fifo_full && capture_enable;

    //=========================================================================
    // Selected Drive State
    //=========================================================================

    reg [1:0]  selected_drive;      // Currently selected drive (0-3)
    reg        selected_is_fdd;     // Selected drive is FDD

    //=========================================================================
    // Device Info Constants
    //=========================================================================

    localparam [15:0] FW_VERSION = 16'h0100;  // v1.0
    localparam [15:0] HW_VERSION = 16'h0100;  // v1.0
    localparam [31:0] DEVICE_ID  = 32'h464C5558; // "FLUX"

    //=========================================================================
    // USB RX Ready
    //=========================================================================

    assign usb_rx_ready = (state == ST_IDLE) ||
                          (state == ST_RX_CMD_1) ||
                          (state == ST_RX_CMD_2) ||
                          (state == ST_RX_CMD_3);

    //=========================================================================
    // Flux FIFO Write Logic
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flux_wr_ptr <= 0;
        end else if (flux_valid && flux_ready) begin
            flux_fifo[flux_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= flux_data;
            flux_wr_ptr <= flux_wr_ptr + 1'b1;
        end
    end

    //=========================================================================
    // Main State Machine
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            raw_state <= 8'h0;
            last_command <= 8'h0;
            command_error <= 1'b0;

            cmd_word0 <= 32'h0;
            cmd_word1 <= 32'h0;
            cmd_word2 <= 32'h0;
            cmd_word3 <= 32'h0;

            rsp_len <= 5'h0;
            rsp_idx <= 5'h0;

            usb_tx_data <= 32'h0;
            usb_tx_valid <= 1'b0;

            flux_rd_ptr <= 0;

            selected_drive <= 2'b00;
            selected_is_fdd <= 1'b1;

            fdd_select <= 2'b00;
            fdd_motor_on <= 1'b0;
            fdd_track <= 8'h0;
            fdd_seek_cmd <= 1'b0;
            hdd_select <= 2'b00;

            capture_enable <= 1'b0;
            capture_arm <= 1'b0;
        end else begin
            raw_state <= {4'h0, state};
            fdd_seek_cmd <= 1'b0;
            usb_tx_valid <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                // IDLE - Wait for command
                //-------------------------------------------------------------
                ST_IDLE: begin
                    command_error <= 1'b0;
                    if (usb_rx_valid) begin
                        cmd_word0 <= usb_rx_data;
                        state <= ST_RX_CMD_1;
                    end
                end

                //-------------------------------------------------------------
                // Receive command words
                //-------------------------------------------------------------
                ST_RX_CMD_1: begin
                    if (usb_rx_valid) begin
                        cmd_word1 <= usb_rx_data;
                        state <= ST_RX_CMD_2;
                    end
                end

                ST_RX_CMD_2: begin
                    if (usb_rx_valid) begin
                        cmd_word2 <= usb_rx_data;
                        state <= ST_RX_CMD_3;
                    end
                end

                ST_RX_CMD_3: begin
                    if (usb_rx_valid) begin
                        cmd_word3 <= usb_rx_data;
                        state <= ST_VALIDATE;
                    end
                end

                //-------------------------------------------------------------
                // Validate command
                //-------------------------------------------------------------
                ST_VALIDATE: begin
                    last_command <= cmd_opcode;

                    if (cmd_word0 != RAW_SIGNATURE) begin
                        // Invalid signature
                        rsp_buffer[0] <= {RAW_SIGNATURE[7:0], RAW_SIGNATURE[15:8],
                                         RAW_SIGNATURE[23:16], RAW_SIGNATURE[31:24]};
                        rsp_buffer[1] <= {RSP_ERR_INVALID_CMD, cmd_opcode, 16'h0};
                        rsp_len <= 5'd2;
                        command_error <= 1'b1;
                        state <= ST_TX_RESPONSE;
                    end else begin
                        state <= ST_EXECUTE;
                    end
                end

                //-------------------------------------------------------------
                // Execute command
                //-------------------------------------------------------------
                ST_EXECUTE: begin
                    case (cmd_opcode)
                        //-----------------------------------------------------
                        // NOP - Return status
                        //-----------------------------------------------------
                        CMD_NOP: begin
                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_OK, CMD_NOP, 16'h0};
                            rsp_len <= 5'd2;
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // GET_INFO - Device information
                        //-----------------------------------------------------
                        CMD_GET_INFO: begin
                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_OK, CMD_GET_INFO, 16'd24}; // 24 bytes data
                            rsp_buffer[2] <= DEVICE_ID;
                            rsp_buffer[3] <= {FW_VERSION, HW_VERSION};
                            rsp_buffer[4] <= {4'd4, 4'd2, 4'd2, 4'h0,       // max_luns, max_fdd, max_hdd
                                             8'h0, 8'h0};
                            rsp_buffer[5] <= {16'h0,
                                             fdd_disk_present, fdd_write_prot, hdd_ready, 5'h0,
                                             capture_active, capture_overflow, pll_locked, 5'h0};
                            rsp_buffer[6] <= {selected_drive, selected_is_fdd, 5'h0, fdd_track,
                                             8'h0, 8'h0};
                            rsp_buffer[7] <= hdd_capacity;
                            rsp_len <= 5'd8;
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // SELECT_DRIVE - Select physical drive
                        //-----------------------------------------------------
                        CMD_SELECT_DRIVE: begin
                            if (cmd_param1 >= MAX_DRIVES) begin
                                rsp_buffer[0] <= RAW_SIGNATURE;
                                rsp_buffer[1] <= {RSP_ERR_INVALID_PARAM, CMD_SELECT_DRIVE, 16'h0};
                                rsp_len <= 5'd2;
                                command_error <= 1'b1;
                            end else begin
                                selected_drive <= cmd_param1[1:0];
                                selected_is_fdd <= (cmd_param1 < 2);

                                if (cmd_param1 < 2) begin
                                    fdd_select <= cmd_param1[0];
                                end else begin
                                    hdd_select <= cmd_param1[0];
                                end

                                rsp_buffer[0] <= RAW_SIGNATURE;
                                rsp_buffer[1] <= {RSP_OK, CMD_SELECT_DRIVE, 8'h0, cmd_param1};
                                rsp_len <= 5'd2;
                            end
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // MOTOR_CTRL - Motor on/off
                        //-----------------------------------------------------
                        CMD_MOTOR_CTRL: begin
                            if (selected_is_fdd) begin
                                fdd_motor_on <= cmd_param1[0];
                            end
                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_OK, CMD_MOTOR_CTRL, 8'h0, 7'h0, cmd_param1[0]};
                            rsp_len <= 5'd2;
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // SEEK - Seek to track
                        //-----------------------------------------------------
                        CMD_SEEK: begin
                            if (!selected_is_fdd) begin
                                rsp_buffer[0] <= RAW_SIGNATURE;
                                rsp_buffer[1] <= {RSP_ERR_INVALID_CMD, CMD_SEEK, 16'h0};
                                rsp_len <= 5'd2;
                                command_error <= 1'b1;
                                state <= ST_TX_RESPONSE;
                            end else begin
                                fdd_track <= cmd_param1;
                                fdd_seek_cmd <= 1'b1;
                                state <= ST_WAIT_SEEK;
                            end
                        end

                        //-----------------------------------------------------
                        // CAPTURE_START - Begin flux capture
                        //-----------------------------------------------------
                        CMD_CAPTURE_START: begin
                            flux_wr_ptr <= 0;
                            flux_rd_ptr <= 0;
                            capture_arm <= 1'b1;
                            capture_enable <= 1'b1;

                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_OK, CMD_CAPTURE_START, 16'h0};
                            rsp_len <= 5'd2;
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // CAPTURE_STOP - End flux capture
                        //-----------------------------------------------------
                        CMD_CAPTURE_STOP: begin
                            capture_enable <= 1'b0;
                            capture_arm <= 1'b0;

                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_OK, CMD_CAPTURE_STOP, flux_count[15:0]};
                            rsp_len <= 5'd2;
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // READ_FLUX - Stream flux data
                        //-----------------------------------------------------
                        CMD_READ_FLUX: begin
                            if (flux_fifo_empty) begin
                                rsp_buffer[0] <= RAW_SIGNATURE;
                                rsp_buffer[1] <= {RSP_OK, CMD_READ_FLUX, 16'h0};
                                rsp_len <= 5'd2;
                                state <= ST_TX_RESPONSE;
                            end else begin
                                // Send header then stream data
                                rsp_buffer[0] <= RAW_SIGNATURE;
                                rsp_buffer[1] <= {RSP_OK, CMD_READ_FLUX, flux_count[15:0]};
                                rsp_len <= 5'd2;
                                rsp_idx <= 5'd0;
                                state <= ST_TX_RESPONSE;
                            end
                        end

                        //-----------------------------------------------------
                        // GET_PLL_STATUS - PLL diagnostics
                        //-----------------------------------------------------
                        CMD_GET_PLL_STATUS: begin
                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_OK, CMD_GET_PLL_STATUS, 16'd8};
                            rsp_buffer[2] <= {pll_frequency, 7'h0, pll_locked, pll_lock_count};
                            rsp_buffer[3] <= {16'h0, 8'h0, pll_error_count};
                            rsp_len <= 5'd4;
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // GET_SIGNAL_QUAL - Signal quality metrics
                        //-----------------------------------------------------
                        CMD_GET_SIGNAL_QUAL: begin
                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_OK, CMD_GET_SIGNAL_QUAL, 16'd12};
                            rsp_buffer[2] <= {signal_amplitude, signal_noise};
                            rsp_buffer[3] <= {8'h0, bit_error_rate, jitter_ns};
                            rsp_buffer[4] <= {capture_overflow, 31'h0};
                            rsp_len <= 5'd5;
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // GET_DRIVE_PROFILE - Drive parameters
                        //-----------------------------------------------------
                        CMD_GET_DRIVE_PROFILE: begin
                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_OK, CMD_GET_DRIVE_PROFILE, 16'd16};
                            rsp_buffer[2] <= {selected_drive, selected_is_fdd, 5'h0,
                                             fdd_disk_present, fdd_write_prot, fdd_track0, 5'h0,
                                             fdd_track, 8'h0};
                            rsp_buffer[3] <= selected_is_fdd ? 32'd2880 : hdd_capacity;
                            rsp_buffer[4] <= 32'd512;  // Block size
                            rsp_buffer[5] <= {selected_is_fdd ? 8'd80 : 8'd0,   // Tracks
                                             selected_is_fdd ? 8'd2 : 8'd0,    // Heads
                                             selected_is_fdd ? 8'd18 : 8'd0,   // Sectors/track
                                             8'h0};
                            rsp_len <= 5'd6;
                            state <= ST_TX_RESPONSE;
                        end

                        //-----------------------------------------------------
                        // Unknown command
                        //-----------------------------------------------------
                        default: begin
                            rsp_buffer[0] <= RAW_SIGNATURE;
                            rsp_buffer[1] <= {RSP_ERR_INVALID_CMD, cmd_opcode, 16'h0};
                            rsp_len <= 5'd2;
                            command_error <= 1'b1;
                            state <= ST_TX_RESPONSE;
                        end
                    endcase
                end

                //-------------------------------------------------------------
                // Wait for seek completion
                //-------------------------------------------------------------
                ST_WAIT_SEEK: begin
                    if (fdd_seek_done) begin
                        rsp_buffer[0] <= RAW_SIGNATURE;
                        rsp_buffer[1] <= {RSP_OK, CMD_SEEK, 8'h0, fdd_track};
                        rsp_len <= 5'd2;
                        state <= ST_TX_RESPONSE;
                    end
                end

                //-------------------------------------------------------------
                // Transmit response
                //-------------------------------------------------------------
                ST_TX_RESPONSE: begin
                    if (usb_tx_ready || !usb_tx_valid) begin
                        if (rsp_idx < rsp_len) begin
                            usb_tx_data <= rsp_buffer[rsp_idx];
                            usb_tx_valid <= 1'b1;
                            rsp_idx <= rsp_idx + 1'b1;
                        end else begin
                            // Check if we need to stream flux data
                            if (last_command == CMD_READ_FLUX && !flux_fifo_empty) begin
                                state <= ST_STREAM_FLUX;
                            end else begin
                                state <= ST_IDLE;
                            end
                        end
                    end
                end

                //-------------------------------------------------------------
                // Stream flux data
                //-------------------------------------------------------------
                ST_STREAM_FLUX: begin
                    if (usb_tx_ready || !usb_tx_valid) begin
                        if (!flux_fifo_empty) begin
                            usb_tx_data <= flux_fifo[flux_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                            usb_tx_valid <= 1'b1;
                            flux_rd_ptr <= flux_rd_ptr + 1'b1;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // Error state
                //-------------------------------------------------------------
                ST_ERROR: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
