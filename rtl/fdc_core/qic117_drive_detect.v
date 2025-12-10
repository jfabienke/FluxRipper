//==============================================================================
// QIC-117 Drive Auto-Detection
//==============================================================================
// File: qic117_drive_detect.v
// Description: Automatic detection of QIC-117 tape drive presence and type.
//              Sequences through detection commands to identify:
//                - Drive presence (responds to PHANTOM_SELECT + REPORT_STATUS)
//                - Vendor ID (REPORT_VENDOR command)
//                - Model ID (REPORT_MODEL command)
//                - Drive configuration/capabilities
//
// Detection Sequence:
//   1. Send PHANTOM_SELECT (46 pulses)
//   2. Send REPORT_STATUS (4 pulses) - verify drive responds
//   3. Send REPORT_VENDOR (38 pulses) - get vendor ID
//   4. Send REPORT_MODEL (39 pulses) - get model ID
//   5. Send REPORT_DRIVE_CFG (41 pulses) - get capabilities
//   6. Decode results to known drive types
//
// Known Drive Types:
//   - Colorado Memory Systems (CMS): QIC-40/80, Jumbo, Trakker
//   - Conner/Archive: QIC-80, QIC-3010
//   - Iomega: Ditto, Ditto Max
//   - Mountain: Filesafe
//   - Wangtek: Various models
//
// Reference: QIC-117 Revision G
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module qic117_drive_detect #(
    parameter CLK_FREQ_HZ = 200_000_000   // 200 MHz clock
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Control
    //=========================================================================
    input  wire        enable,            // Enable detection (tape mode active)
    input  wire        start_detect,      // Pulse to start detection sequence
    input  wire        abort_detect,      // Abort detection in progress

    //=========================================================================
    // Command Interface (directly sends commands)
    //=========================================================================
    output reg  [5:0]  cmd_code,          // Command to send
    output reg         cmd_send,          // Pulse to send command
    input  wire        cmd_done,          // Command completed

    //=========================================================================
    // TRK0 Decoder Interface
    //=========================================================================
    output reg         trk0_capture_start,// Start TRK0 response capture
    output reg  [3:0]  trk0_expected_bytes,// Bytes to capture
    input  wire [63:0] trk0_response,     // Captured response data
    input  wire [3:0]  trk0_bytes_rcvd,   // Bytes actually received
    input  wire        trk0_complete,     // Capture complete
    input  wire        trk0_error,        // Capture error

    //=========================================================================
    // Detection Results
    //=========================================================================
    output reg         detect_complete,   // Detection sequence finished
    output reg         detect_error,      // Detection failed
    output reg         drive_present,     // Drive detected and responding
    output reg         cartridge_present, // Tape cartridge inserted
    output reg         write_protected,   // Write protect enabled

    // Drive identification
    output reg  [7:0]  vendor_id,         // Vendor code
    output reg  [7:0]  model_id,          // Model code
    output reg  [7:0]  rom_version,       // Firmware version
    output reg  [7:0]  drive_config,      // Configuration byte

    // Decoded drive type
    output reg  [3:0]  drive_type,        // Enumerated drive type
    output reg  [4:0]  max_tracks,        // Maximum tracks (20/28/40/50)
    output reg  [1:0]  supported_rates,   // Supported data rates bitmap

    //=========================================================================
    // Status
    //=========================================================================
    output reg         detecting,         // Detection in progress
    output reg  [3:0]  detect_phase       // Current phase (for debug)
);

    //=========================================================================
    // QIC-117 Command Codes
    //=========================================================================
    localparam [5:0] QIC_REPORT_STATUS    = 6'd4;
    localparam [5:0] QIC_REPORT_VENDOR    = 6'd38;
    localparam [5:0] QIC_REPORT_MODEL     = 6'd39;
    localparam [5:0] QIC_REPORT_ROM_VER   = 6'd40;
    localparam [5:0] QIC_REPORT_DRIVE_CFG = 6'd41;
    localparam [5:0] QIC_PHANTOM_SELECT   = 6'd46;

    //=========================================================================
    // Drive Type Enumeration
    //=========================================================================
    localparam [3:0] DRIVE_UNKNOWN        = 4'd0;
    localparam [3:0] DRIVE_QIC40          = 4'd1;   // 40MB, 20 tracks
    localparam [3:0] DRIVE_QIC80          = 4'd2;   // 80MB, 28 tracks
    localparam [3:0] DRIVE_QIC80_WIDE     = 4'd3;   // 80-120MB wide
    localparam [3:0] DRIVE_QIC3010        = 4'd4;   // 340MB, 40 tracks
    localparam [3:0] DRIVE_QIC3020        = 4'd5;   // 680MB, 40 tracks, 1Mbps
    localparam [3:0] DRIVE_TRAVAN_1       = 4'd6;   // TR-1 (400MB)
    localparam [3:0] DRIVE_TRAVAN_2       = 4'd7;   // TR-2 (800MB)
    localparam [3:0] DRIVE_TRAVAN_3       = 4'd8;   // TR-3 (1.6GB)
    localparam [3:0] DRIVE_DITTO          = 4'd9;   // Iomega Ditto
    localparam [3:0] DRIVE_DITTO_MAX      = 4'd10;  // Iomega Ditto Max

    //=========================================================================
    // Known Vendor IDs
    //=========================================================================
    localparam [7:0] VENDOR_CMS           = 8'h01;  // Colorado Memory Systems
    localparam [7:0] VENDOR_CONNER        = 8'h02;  // Conner/Archive/Seagate
    localparam [7:0] VENDOR_IOMEGA        = 8'h03;  // Iomega
    localparam [7:0] VENDOR_MOUNTAIN      = 8'h04;  // Mountain
    localparam [7:0] VENDOR_WANGTEK       = 8'h05;  // Wangtek
    localparam [7:0] VENDOR_EXABYTE       = 8'h06;  // Exabyte
    localparam [7:0] VENDOR_AIWA          = 8'h07;  // AIWA
    localparam [7:0] VENDOR_SONY          = 8'h08;  // Sony

    //=========================================================================
    // Data Rate Bitmap
    //=========================================================================
    localparam [1:0] RATE_250K            = 2'b01;  // 250 Kbps
    localparam [1:0] RATE_500K            = 2'b10;  // 500 Kbps
    localparam [1:0] RATE_1M              = 2'b11;  // 1 Mbps

    //=========================================================================
    // Detection State Machine
    //=========================================================================
    localparam [3:0] ST_IDLE              = 4'd0;
    localparam [3:0] ST_PHANTOM_SELECT    = 4'd1;
    localparam [3:0] ST_WAIT_SELECT       = 4'd2;
    localparam [3:0] ST_REPORT_STATUS     = 4'd3;
    localparam [3:0] ST_WAIT_STATUS       = 4'd4;
    localparam [3:0] ST_CAPTURE_STATUS    = 4'd5;
    localparam [3:0] ST_REPORT_VENDOR     = 4'd6;
    localparam [3:0] ST_WAIT_VENDOR       = 4'd7;
    localparam [3:0] ST_CAPTURE_VENDOR    = 4'd8;
    localparam [3:0] ST_REPORT_MODEL      = 4'd9;
    localparam [3:0] ST_WAIT_MODEL        = 4'd10;
    localparam [3:0] ST_CAPTURE_MODEL     = 4'd11;
    localparam [3:0] ST_REPORT_CONFIG     = 4'd12;
    localparam [3:0] ST_WAIT_CONFIG       = 4'd13;
    localparam [3:0] ST_CAPTURE_CONFIG    = 4'd14;
    localparam [3:0] ST_DECODE            = 4'd15;

    reg [3:0] state;
    reg [7:0] status_byte;                // Captured status

    //=========================================================================
    // Timeout Counter
    //=========================================================================
    // 500ms timeout for each phase
    localparam PHASE_TIMEOUT_CLKS = CLK_FREQ_HZ / 2;
    localparam TIMEOUT_WIDTH = $clog2(PHASE_TIMEOUT_CLKS + 1);

    reg [TIMEOUT_WIDTH-1:0] timeout_cnt;
    wire timeout_expired = (timeout_cnt >= PHASE_TIMEOUT_CLKS - 1);

    //=========================================================================
    // Main State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state              <= ST_IDLE;
            cmd_code           <= 6'd0;
            cmd_send           <= 1'b0;
            trk0_capture_start <= 1'b0;
            trk0_expected_bytes <= 4'd1;
            detect_complete    <= 1'b0;
            detect_error       <= 1'b0;
            drive_present      <= 1'b0;
            cartridge_present  <= 1'b0;
            write_protected    <= 1'b0;
            vendor_id          <= 8'd0;
            model_id           <= 8'd0;
            rom_version        <= 8'd0;
            drive_config       <= 8'd0;
            drive_type         <= DRIVE_UNKNOWN;
            max_tracks         <= 5'd0;
            supported_rates    <= 2'b00;
            detecting          <= 1'b0;
            detect_phase       <= 4'd0;
            timeout_cnt        <= 0;
            status_byte        <= 8'd0;
        end else if (!enable) begin
            state           <= ST_IDLE;
            detecting       <= 1'b0;
            detect_complete <= 1'b0;
            detect_error    <= 1'b0;
        end else begin
            // Default: clear single-cycle signals
            cmd_send           <= 1'b0;
            trk0_capture_start <= 1'b0;
            detect_complete    <= 1'b0;
            detect_error       <= 1'b0;

            // Timeout counter
            if (state != ST_IDLE && state != ST_DECODE) begin
                if (timeout_cnt < PHASE_TIMEOUT_CLKS - 1) begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                end
            end

            // Abort handling
            if (abort_detect && detecting) begin
                state           <= ST_IDLE;
                detecting       <= 1'b0;
                detect_error    <= 1'b1;
            end else begin
                case (state)
                    //=========================================================
                    ST_IDLE: begin
                        detecting    <= 1'b0;
                        detect_phase <= 4'd0;

                        if (start_detect) begin
                            // Clear previous results
                            drive_present     <= 1'b0;
                            cartridge_present <= 1'b0;
                            write_protected   <= 1'b0;
                            vendor_id         <= 8'd0;
                            model_id          <= 8'd0;
                            rom_version       <= 8'd0;
                            drive_config      <= 8'd0;
                            drive_type        <= DRIVE_UNKNOWN;
                            max_tracks        <= 5'd0;
                            supported_rates   <= 2'b00;
                            timeout_cnt       <= 0;
                            detecting         <= 1'b1;
                            state             <= ST_PHANTOM_SELECT;
                        end
                    end

                    //=========================================================
                    // Phase 1: Phantom Select
                    //=========================================================
                    ST_PHANTOM_SELECT: begin
                        detect_phase <= 4'd1;
                        cmd_code     <= QIC_PHANTOM_SELECT;
                        cmd_send     <= 1'b1;
                        timeout_cnt  <= 0;
                        state        <= ST_WAIT_SELECT;
                    end

                    ST_WAIT_SELECT: begin
                        if (cmd_done) begin
                            state <= ST_REPORT_STATUS;
                        end else if (timeout_expired) begin
                            // No response - no drive
                            drive_present   <= 1'b0;
                            detect_complete <= 1'b1;
                            state           <= ST_IDLE;
                        end
                    end

                    //=========================================================
                    // Phase 2: Report Status (verify presence)
                    //=========================================================
                    ST_REPORT_STATUS: begin
                        detect_phase <= 4'd2;
                        cmd_code     <= QIC_REPORT_STATUS;
                        cmd_send     <= 1'b1;
                        timeout_cnt  <= 0;
                        state        <= ST_WAIT_STATUS;
                    end

                    ST_WAIT_STATUS: begin
                        if (cmd_done) begin
                            // Start capturing TRK0 response (1 byte)
                            trk0_expected_bytes <= 4'd1;
                            trk0_capture_start  <= 1'b1;
                            state               <= ST_CAPTURE_STATUS;
                        end else if (timeout_expired) begin
                            drive_present   <= 1'b0;
                            detect_complete <= 1'b1;
                            state           <= ST_IDLE;
                        end
                    end

                    ST_CAPTURE_STATUS: begin
                        if (trk0_complete) begin
                            // Got status response - drive is present!
                            drive_present     <= 1'b1;
                            status_byte       <= trk0_response[7:0];
                            cartridge_present <= trk0_response[5];  // Bit 5
                            write_protected   <= trk0_response[4];  // Bit 4
                            state             <= ST_REPORT_VENDOR;
                        end else if (trk0_error || timeout_expired) begin
                            // No valid response
                            drive_present   <= 1'b0;
                            detect_complete <= 1'b1;
                            state           <= ST_IDLE;
                        end
                    end

                    //=========================================================
                    // Phase 3: Report Vendor ID
                    //=========================================================
                    ST_REPORT_VENDOR: begin
                        detect_phase <= 4'd3;
                        cmd_code     <= QIC_REPORT_VENDOR;
                        cmd_send     <= 1'b1;
                        timeout_cnt  <= 0;
                        state        <= ST_WAIT_VENDOR;
                    end

                    ST_WAIT_VENDOR: begin
                        if (cmd_done) begin
                            trk0_expected_bytes <= 4'd1;
                            trk0_capture_start  <= 1'b1;
                            state               <= ST_CAPTURE_VENDOR;
                        end else if (timeout_expired) begin
                            // Skip to next phase
                            state <= ST_REPORT_MODEL;
                        end
                    end

                    ST_CAPTURE_VENDOR: begin
                        if (trk0_complete) begin
                            vendor_id <= trk0_response[7:0];
                            state     <= ST_REPORT_MODEL;
                        end else if (trk0_error || timeout_expired) begin
                            // Continue without vendor ID
                            state <= ST_REPORT_MODEL;
                        end
                    end

                    //=========================================================
                    // Phase 4: Report Model ID
                    //=========================================================
                    ST_REPORT_MODEL: begin
                        detect_phase <= 4'd4;
                        cmd_code     <= QIC_REPORT_MODEL;
                        cmd_send     <= 1'b1;
                        timeout_cnt  <= 0;
                        state        <= ST_WAIT_MODEL;
                    end

                    ST_WAIT_MODEL: begin
                        if (cmd_done) begin
                            trk0_expected_bytes <= 4'd1;
                            trk0_capture_start  <= 1'b1;
                            state               <= ST_CAPTURE_MODEL;
                        end else if (timeout_expired) begin
                            state <= ST_REPORT_CONFIG;
                        end
                    end

                    ST_CAPTURE_MODEL: begin
                        if (trk0_complete) begin
                            model_id <= trk0_response[7:0];
                            state    <= ST_REPORT_CONFIG;
                        end else if (trk0_error || timeout_expired) begin
                            state <= ST_REPORT_CONFIG;
                        end
                    end

                    //=========================================================
                    // Phase 5: Report Drive Configuration
                    //=========================================================
                    ST_REPORT_CONFIG: begin
                        detect_phase <= 4'd5;
                        cmd_code     <= QIC_REPORT_DRIVE_CFG;
                        cmd_send     <= 1'b1;
                        timeout_cnt  <= 0;
                        state        <= ST_WAIT_CONFIG;
                    end

                    ST_WAIT_CONFIG: begin
                        if (cmd_done) begin
                            // Config may return multiple bytes
                            trk0_expected_bytes <= 4'd2;
                            trk0_capture_start  <= 1'b1;
                            state               <= ST_CAPTURE_CONFIG;
                        end else if (timeout_expired) begin
                            state <= ST_DECODE;
                        end
                    end

                    ST_CAPTURE_CONFIG: begin
                        if (trk0_complete) begin
                            drive_config <= trk0_response[7:0];
                            // Second byte may contain extended info
                            if (trk0_bytes_rcvd >= 2) begin
                                rom_version <= trk0_response[15:8];
                            end
                            state <= ST_DECODE;
                        end else if (trk0_error || timeout_expired) begin
                            state <= ST_DECODE;
                        end
                    end

                    //=========================================================
                    // Phase 6: Decode Results
                    //=========================================================
                    ST_DECODE: begin
                        detect_phase <= 4'd6;

                        // Decode drive type based on vendor/model/config
                        // This is heuristic based on known drive signatures

                        case (vendor_id)
                            VENDOR_CMS: begin
                                // Colorado Memory Systems
                                if (drive_config[3:0] <= 4'd2) begin
                                    drive_type      <= DRIVE_QIC40;
                                    max_tracks      <= 5'd20;
                                    supported_rates <= RATE_250K;
                                end else if (drive_config[3:0] <= 4'd4) begin
                                    drive_type      <= DRIVE_QIC80;
                                    max_tracks      <= 5'd28;
                                    supported_rates <= RATE_500K;
                                end else begin
                                    drive_type      <= DRIVE_QIC3010;
                                    max_tracks      <= 5'd40;
                                    supported_rates <= RATE_500K;
                                end
                            end

                            VENDOR_CONNER: begin
                                // Conner/Archive
                                if (model_id <= 8'h20) begin
                                    drive_type      <= DRIVE_QIC80;
                                    max_tracks      <= 5'd28;
                                    supported_rates <= RATE_500K;
                                end else begin
                                    drive_type      <= DRIVE_QIC3010;
                                    max_tracks      <= 5'd40;
                                    supported_rates <= RATE_500K;
                                end
                            end

                            VENDOR_IOMEGA: begin
                                // Iomega Ditto series
                                if (model_id <= 8'h10) begin
                                    drive_type      <= DRIVE_DITTO;
                                    max_tracks      <= 5'd28;
                                    supported_rates <= RATE_500K;
                                end else begin
                                    drive_type      <= DRIVE_DITTO_MAX;
                                    max_tracks      <= 5'd40;
                                    supported_rates <= RATE_1M;
                                end
                            end

                            default: begin
                                // Unknown vendor - guess based on config
                                if (drive_config[7]) begin
                                    // High bit set often means higher capacity
                                    drive_type      <= DRIVE_QIC3010;
                                    max_tracks      <= 5'd40;
                                    supported_rates <= RATE_500K;
                                end else if (drive_config[3:0] > 4'd4) begin
                                    drive_type      <= DRIVE_QIC80;
                                    max_tracks      <= 5'd28;
                                    supported_rates <= RATE_500K;
                                end else begin
                                    drive_type      <= DRIVE_QIC40;
                                    max_tracks      <= 5'd20;
                                    supported_rates <= RATE_250K;
                                end
                            end
                        endcase

                        // Override if config explicitly indicates 1Mbps
                        if (drive_config[6]) begin
                            supported_rates <= RATE_1M;
                            if (drive_type == DRIVE_QIC3010) begin
                                drive_type <= DRIVE_QIC3020;
                            end
                        end

                        detect_complete <= 1'b1;
                        detecting       <= 1'b0;
                        state           <= ST_IDLE;
                    end

                    //=========================================================
                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
