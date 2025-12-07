//-----------------------------------------------------------------------------
// native_protocol.v
// Native FluxRipper USB Protocol Handler
//
// Created: 2025-12-05 18:35
//
// The native FluxRipper protocol is designed to fully utilize the hardware's
// capabilities without compromise for backwards compatibility.
//
// Features:
//   - Full 300 MHz (3.33ns) timestamp resolution
//   - 32-bit flux words with embedded metadata flags
//   - Per-revolution track headers with timing and diagnostics
//   - Signal quality metrics inline with flux data
//   - Efficient binary protocol with zero conversion overhead
//   - Streaming and block modes
//   - Full diagnostic access
//
// Flux Word Format (32-bit):
//   [31]    INDEX   - Index pulse marker
//   [30]    WEAK    - Weak/uncertain bit flag
//   [29]    SPLICE  - Track splice point marker
//   [28]    OVF     - Timer overflow (>335ms gap)
//   [27:0]  TIME    - Timestamp (28-bit, 2.5ns resolution = 671ms max)
//
// Command Format (16 bytes):
//   [3:0]   Signature (0x46524658 "FRFX")
//   [7:4]   Command code + flags
//   [15:8]  Parameters
//
// Response Format (variable):
//   [3:0]   Signature (0x46524658 "FRFX")
//   [7:4]   Status + command echo
//   [n:8]   Response data
//-----------------------------------------------------------------------------

module native_protocol #(
    parameter SAMPLE_RATE_MHZ = 300,
    parameter TIMESTAMP_BITS  = 28,
    parameter BUFFER_DEPTH    = 8192
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // USB Endpoint Interface
    //=========================================================================

    input  wire [31:0] cmd_rx_data,
    input  wire        cmd_rx_valid,
    output reg         cmd_rx_ready,

    output reg  [31:0] resp_tx_data,
    output reg         resp_tx_valid,
    input  wire        resp_tx_ready,

    //=========================================================================
    // Flux Data Interface (from flux_sampler)
    //=========================================================================

    input  wire [31:0] flux_in_data,      // Native 32-bit format
    input  wire        flux_in_valid,
    output reg         flux_in_ready,

    //=========================================================================
    // Signal Quality Interface
    //=========================================================================

    input  wire [15:0] signal_amplitude,
    input  wire [15:0] signal_noise,
    input  wire [15:0] pll_frequency,
    input  wire        pll_locked,
    input  wire [15:0] jitter_ns,

    //=========================================================================
    // Drive Control Interface
    //=========================================================================

    output reg         drv_motor_on,
    output reg  [7:0]  drv_cylinder,
    output reg         drv_head,
    output reg         drv_step_dir,
    output reg         drv_step_pulse,
    output reg         drv_select,
    output reg         drv_write_gate,
    output reg  [7:0]  drv_write_precomp,

    input  wire        drv_ready,
    input  wire        drv_track00,
    input  wire        drv_write_protect,
    input  wire        drv_index,

    //=========================================================================
    // Capture Control
    //=========================================================================

    output reg         capture_enable,
    output reg         capture_arm,
    output reg  [7:0]  capture_revolutions,
    input  wire        capture_active,
    input  wire        capture_complete,
    input  wire [15:0] capture_rev_count,

    //=========================================================================
    // Status
    //=========================================================================

    output reg  [7:0]  native_state,
    output reg  [31:0] sample_count,
    output reg  [31:0] transfer_count,
    output reg         streaming_active
);

    //=========================================================================
    // Protocol Constants
    //=========================================================================

    localparam SIGNATURE = 32'h46524658;  // "FRFX" - FluxRipper FluX

    //=========================================================================
    // Command Codes
    //=========================================================================

    localparam CMD_NOP              = 8'h00;
    localparam CMD_GET_INFO         = 8'h01;
    localparam CMD_GET_VERSION      = 8'h02;
    localparam CMD_RESET            = 8'h03;

    // Drive Control (0x10-0x1F)
    localparam CMD_SELECT_DRIVE     = 8'h10;
    localparam CMD_MOTOR_ON         = 8'h11;
    localparam CMD_MOTOR_OFF        = 8'h12;
    localparam CMD_SEEK             = 8'h13;
    localparam CMD_RECALIBRATE      = 8'h14;
    localparam CMD_SET_HEAD         = 8'h15;
    localparam CMD_GET_STATUS       = 8'h16;

    // Capture Control (0x20-0x2F)
    localparam CMD_CAPTURE_START    = 8'h20;
    localparam CMD_CAPTURE_STOP     = 8'h21;
    localparam CMD_CAPTURE_ARM      = 8'h22;
    localparam CMD_SET_REVOLUTIONS  = 8'h23;
    localparam CMD_GET_CAPTURE_STATUS = 8'h24;

    // Data Transfer (0x30-0x3F)
    localparam CMD_READ_FLUX        = 8'h30;
    localparam CMD_WRITE_FLUX       = 8'h31;
    localparam CMD_READ_TRACK       = 8'h32;
    localparam CMD_WRITE_TRACK      = 8'h33;
    localparam CMD_STREAM_START     = 8'h34;
    localparam CMD_STREAM_STOP      = 8'h35;

    // Diagnostics (0x40-0x4F)
    localparam CMD_GET_SIGNAL       = 8'h40;
    localparam CMD_GET_PLL_STATUS   = 8'h41;
    localparam CMD_GET_TIMING       = 8'h42;
    localparam CMD_GET_HISTOGRAM    = 8'h43;

    // Configuration (0x50-0x5F)
    localparam CMD_SET_SAMPLE_RATE  = 8'h50;
    localparam CMD_SET_WRITE_PRECOMP= 8'h51;
    localparam CMD_SET_DENSITY      = 8'h52;

    //=========================================================================
    // Response Codes
    //=========================================================================

    localparam RSP_OK               = 8'h00;
    localparam RSP_ERR_UNKNOWN_CMD  = 8'h01;
    localparam RSP_ERR_INVALID_PARAM= 8'h02;
    localparam RSP_ERR_NOT_READY    = 8'h03;
    localparam RSP_ERR_TIMEOUT      = 8'h04;
    localparam RSP_ERR_WRITE_PROT   = 8'h05;
    localparam RSP_ERR_NO_DISK      = 8'h06;
    localparam RSP_DATA_FOLLOWS     = 8'h80;
    localparam RSP_STREAM_START     = 8'h81;
    localparam RSP_STREAM_END       = 8'h82;

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_IDLE              = 4'd0;
    localparam ST_CMD_WORD1         = 4'd1;
    localparam ST_CMD_WORD2         = 4'd2;
    localparam ST_CMD_WORD3         = 4'd3;
    localparam ST_EXECUTE           = 4'd4;
    localparam ST_RESPONSE          = 4'd5;
    localparam ST_RESPONSE_DATA     = 4'd6;
    localparam ST_STREAMING         = 4'd7;
    localparam ST_STREAM_HEADER     = 4'd8;
    localparam ST_STREAM_DATA       = 4'd9;
    localparam ST_SEEK              = 4'd10;
    localparam ST_RECALIBRATE       = 4'd11;

    reg [3:0] state;

    //=========================================================================
    // Command Buffer
    //=========================================================================

    reg [31:0] cmd_word0;
    reg [31:0] cmd_word1;
    reg [31:0] cmd_word2;
    reg [31:0] cmd_word3;

    wire [7:0]  cmd_code   = cmd_word1[7:0];
    wire [7:0]  cmd_flags  = cmd_word1[15:8];
    wire [15:0] cmd_param1 = cmd_word1[31:16];
    wire [31:0] cmd_param2 = cmd_word2;
    wire [31:0] cmd_param3 = cmd_word3;

    //=========================================================================
    // Response Buffer
    //=========================================================================

    reg [31:0] rsp_buffer [0:15];
    reg [3:0]  rsp_length;
    reg [3:0]  rsp_index;
    reg [7:0]  rsp_code;

    //=========================================================================
    // Stream State
    //=========================================================================

    reg [31:0] stream_sample_count;
    reg [15:0] stream_rev_count;
    reg        stream_index_pending;
    reg        prev_index;

    //=========================================================================
    // Track Header (sent at start of each revolution)
    //=========================================================================

    // Track header format (8 words = 32 bytes):
    //   [0] Signature (0x54524B48 "TRKH")
    //   [1] Track number, head, revolution
    //   [2] Sample count in this revolution
    //   [3] Index position (sample offset)
    //   [4] Signal amplitude, noise
    //   [5] PLL frequency, lock status
    //   [6] Jitter, reserved
    //   [7] CRC32 of header

    localparam TRACK_HEADER_SIG = 32'h54524B48;  // "TRKH"

    reg [31:0] track_header [0:7];
    reg [2:0]  header_index;
    reg        header_pending;

    //=========================================================================
    // Device Info
    //=========================================================================

    localparam [31:0] DEVICE_ID      = 32'h46525052;  // "FRPR" FluxRipper
    localparam [15:0] HW_VERSION     = 16'h0100;
    localparam [15:0] FW_VERSION     = 16'h0100;
    localparam [31:0] CAPABILITIES   = 32'h0000FFFF;
    localparam [31:0] MAX_SAMPLE_RATE= 32'd300000000;

    //=========================================================================
    // Main State Machine
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            native_state <= 8'h0;

            cmd_rx_ready <= 1'b1;
            resp_tx_data <= 32'h0;
            resp_tx_valid <= 1'b0;
            flux_in_ready <= 1'b0;

            drv_motor_on <= 1'b0;
            drv_cylinder <= 8'h0;
            drv_head <= 1'b0;
            drv_step_dir <= 1'b0;
            drv_step_pulse <= 1'b0;
            drv_select <= 1'b0;
            drv_write_gate <= 1'b0;
            drv_write_precomp <= 8'h0;

            capture_enable <= 1'b0;
            capture_arm <= 1'b0;
            capture_revolutions <= 8'd3;

            sample_count <= 32'h0;
            transfer_count <= 32'h0;
            streaming_active <= 1'b0;

            cmd_word0 <= 32'h0;
            cmd_word1 <= 32'h0;
            cmd_word2 <= 32'h0;
            cmd_word3 <= 32'h0;

            rsp_length <= 4'h0;
            rsp_index <= 4'h0;
            rsp_code <= 8'h0;

            stream_sample_count <= 32'h0;
            stream_rev_count <= 16'h0;
            stream_index_pending <= 1'b0;
            prev_index <= 1'b0;
            header_index <= 3'h0;
            header_pending <= 1'b0;
        end else begin
            native_state <= {4'h0, state};
            drv_step_pulse <= 1'b0;
            resp_tx_valid <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                // IDLE - Wait for command
                //-------------------------------------------------------------
                ST_IDLE: begin
                    cmd_rx_ready <= 1'b1;
                    if (cmd_rx_valid) begin
                        cmd_word0 <= cmd_rx_data;
                        cmd_rx_ready <= 1'b0;
                        state <= ST_CMD_WORD1;
                    end
                end

                //-------------------------------------------------------------
                // Receive command words
                //-------------------------------------------------------------
                ST_CMD_WORD1: begin
                    cmd_rx_ready <= 1'b1;
                    if (cmd_rx_valid) begin
                        cmd_word1 <= cmd_rx_data;
                        state <= ST_CMD_WORD2;
                    end
                end

                ST_CMD_WORD2: begin
                    if (cmd_rx_valid) begin
                        cmd_word2 <= cmd_rx_data;
                        state <= ST_CMD_WORD3;
                    end
                end

                ST_CMD_WORD3: begin
                    if (cmd_rx_valid) begin
                        cmd_word3 <= cmd_rx_data;
                        cmd_rx_ready <= 1'b0;
                        state <= ST_EXECUTE;
                    end
                end

                //-------------------------------------------------------------
                // EXECUTE - Process command
                //-------------------------------------------------------------
                ST_EXECUTE: begin
                    // Validate signature
                    if (cmd_word0 != SIGNATURE) begin
                        rsp_code <= RSP_ERR_UNKNOWN_CMD;
                        rsp_buffer[0] <= SIGNATURE;
                        rsp_buffer[1] <= {16'h0, RSP_ERR_UNKNOWN_CMD, cmd_code};
                        rsp_length <= 4'd2;
                        rsp_index <= 4'd0;
                        state <= ST_RESPONSE;
                    end else begin
                        case (cmd_code)
                            //--------------------------------------------------
                            // System Commands
                            //--------------------------------------------------
                            CMD_NOP: begin
                                rsp_code <= RSP_OK;
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_OK, CMD_NOP};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end

                            CMD_GET_INFO: begin
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'd24, RSP_DATA_FOLLOWS, CMD_GET_INFO};
                                rsp_buffer[2] <= DEVICE_ID;
                                rsp_buffer[3] <= {HW_VERSION, FW_VERSION};
                                rsp_buffer[4] <= CAPABILITIES;
                                rsp_buffer[5] <= MAX_SAMPLE_RATE;
                                rsp_buffer[6] <= {capture_revolutions, streaming_active, capture_active, drv_ready,
                                                 5'h0, drv_head, drv_cylinder, 8'h0};
                                rsp_buffer[7] <= sample_count;
                                rsp_length <= 4'd8;
                                state <= ST_RESPONSE;
                            end

                            CMD_RESET: begin
                                drv_motor_on <= 1'b0;
                                drv_select <= 1'b0;
                                capture_enable <= 1'b0;
                                streaming_active <= 1'b0;
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_OK, CMD_RESET};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end

                            //--------------------------------------------------
                            // Drive Control
                            //--------------------------------------------------
                            CMD_SELECT_DRIVE: begin
                                drv_select <= cmd_param1[0];
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_OK, CMD_SELECT_DRIVE};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end

                            CMD_MOTOR_ON: begin
                                drv_motor_on <= 1'b1;
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_OK, CMD_MOTOR_ON};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end

                            CMD_MOTOR_OFF: begin
                                drv_motor_on <= 1'b0;
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_OK, CMD_MOTOR_OFF};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end

                            CMD_SEEK: begin
                                drv_cylinder <= cmd_param1[7:0];
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_OK, CMD_SEEK};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end

                            CMD_SET_HEAD: begin
                                drv_head <= cmd_param1[0];
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_OK, CMD_SET_HEAD};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end

                            CMD_GET_STATUS: begin
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'd12, RSP_DATA_FOLLOWS, CMD_GET_STATUS};
                                rsp_buffer[2] <= {drv_write_protect, drv_track00, drv_ready, drv_index,
                                                 4'h0, drv_head, drv_cylinder, capture_revolutions, 8'h0};
                                rsp_buffer[3] <= sample_count;
                                rsp_buffer[4] <= transfer_count;
                                rsp_length <= 4'd5;
                                state <= ST_RESPONSE;
                            end

                            //--------------------------------------------------
                            // Capture Control
                            //--------------------------------------------------
                            CMD_SET_REVOLUTIONS: begin
                                capture_revolutions <= cmd_param1[7:0];
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_OK, CMD_SET_REVOLUTIONS};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end

                            //--------------------------------------------------
                            // Streaming
                            //--------------------------------------------------
                            CMD_STREAM_START: begin
                                streaming_active <= 1'b1;
                                capture_enable <= 1'b1;
                                stream_sample_count <= 32'h0;
                                stream_rev_count <= 16'h0;
                                header_pending <= 1'b1;

                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_STREAM_START, CMD_STREAM_START};
                                rsp_length <= 4'd2;
                                rsp_index <= 4'd0;
                                state <= ST_RESPONSE;
                            end

                            CMD_STREAM_STOP: begin
                                streaming_active <= 1'b0;
                                capture_enable <= 1'b0;

                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'd8, RSP_STREAM_END, CMD_STREAM_STOP};
                                rsp_buffer[2] <= stream_sample_count;
                                rsp_buffer[3] <= {stream_rev_count, 16'h0};
                                rsp_length <= 4'd4;
                                state <= ST_RESPONSE;
                            end

                            //--------------------------------------------------
                            // Diagnostics
                            //--------------------------------------------------
                            CMD_GET_SIGNAL: begin
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'd12, RSP_DATA_FOLLOWS, CMD_GET_SIGNAL};
                                rsp_buffer[2] <= {signal_amplitude, signal_noise};
                                rsp_buffer[3] <= {pll_frequency, 7'h0, pll_locked, 8'h0};
                                rsp_buffer[4] <= {jitter_ns, 16'h0};
                                rsp_length <= 4'd5;
                                state <= ST_RESPONSE;
                            end

                            //--------------------------------------------------
                            // Unknown Command
                            //--------------------------------------------------
                            default: begin
                                rsp_buffer[0] <= SIGNATURE;
                                rsp_buffer[1] <= {16'h0, RSP_ERR_UNKNOWN_CMD, cmd_code};
                                rsp_length <= 4'd2;
                                state <= ST_RESPONSE;
                            end
                        endcase
                        rsp_index <= 4'd0;
                    end
                end

                //-------------------------------------------------------------
                // RESPONSE - Send response header/data
                //-------------------------------------------------------------
                ST_RESPONSE: begin
                    if (resp_tx_ready || !resp_tx_valid) begin
                        if (rsp_index < rsp_length) begin
                            resp_tx_data <= rsp_buffer[rsp_index];
                            resp_tx_valid <= 1'b1;
                            rsp_index <= rsp_index + 1'b1;
                        end else begin
                            if (streaming_active)
                                state <= ST_STREAMING;
                            else
                                state <= ST_IDLE;
                        end
                    end
                end

                //-------------------------------------------------------------
                // STREAMING - Stream flux data
                //-------------------------------------------------------------
                ST_STREAMING: begin
                    flux_in_ready <= 1'b1;

                    // Check for index pulse (new revolution)
                    if (drv_index && !prev_index) begin
                        stream_rev_count <= stream_rev_count + 1'b1;
                        header_pending <= 1'b1;
                    end
                    prev_index <= drv_index;

                    // Send track header if pending
                    if (header_pending && (resp_tx_ready || !resp_tx_valid)) begin
                        header_index <= 3'h0;
                        track_header[0] <= TRACK_HEADER_SIG;
                        track_header[1] <= {stream_rev_count, drv_head, 7'h0, drv_cylinder};
                        track_header[2] <= stream_sample_count;
                        track_header[3] <= 32'h0;  // Index position (filled later)
                        track_header[4] <= {signal_amplitude, signal_noise};
                        track_header[5] <= {pll_frequency, 7'h0, pll_locked, 8'h0};
                        track_header[6] <= {jitter_ns, 16'h0};
                        track_header[7] <= 32'h0;  // CRC placeholder
                        state <= ST_STREAM_HEADER;
                    end
                    // Send flux data
                    else if (flux_in_valid && (resp_tx_ready || !resp_tx_valid)) begin
                        resp_tx_data <= flux_in_data;
                        resp_tx_valid <= 1'b1;
                        stream_sample_count <= stream_sample_count + 1'b1;
                        sample_count <= sample_count + 1'b1;
                        transfer_count <= transfer_count + 1'b1;
                    end

                    // Check for stop command
                    if (cmd_rx_valid && cmd_rx_data == SIGNATURE) begin
                        flux_in_ready <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                // STREAM_HEADER - Send track header
                //-------------------------------------------------------------
                ST_STREAM_HEADER: begin
                    if (resp_tx_ready || !resp_tx_valid) begin
                        if (header_index < 8) begin
                            resp_tx_data <= track_header[header_index];
                            resp_tx_valid <= 1'b1;
                            header_index <= header_index + 1'b1;
                            transfer_count <= transfer_count + 1'b1;
                        end else begin
                            header_pending <= 1'b0;
                            state <= ST_STREAMING;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
