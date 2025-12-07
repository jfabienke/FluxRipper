// SPDX-License-Identifier: BSD-3-Clause
//
// usb_control_ep.v - USB Control Endpoint (EP0) Handler
//
// Part of FluxRipper - Open-source KryoFlux-compatible floppy disk reader
// Copyright (c) 2025 John Fabienke
//
// Implements USB 2.0 control endpoint processing:
// - SETUP packet parsing and validation
// - Standard USB device requests (GET_DESCRIPTOR, SET_ADDRESS, etc.)
// - KryoFlux vendor-specific requests (bmRequestType=0xC3, bRequest=0x05-0x0D, 0x80-0x81)
// - MSC class requests (GET_MAX_LUN, Bulk-Only Mass Storage Reset)
// - CDC ACM class requests (SET_LINE_CODING, GET_LINE_CODING, SET_CONTROL_LINE_STATE)
// - Three-phase control transfer: SETUP -> DATA (optional) -> STATUS
// - Descriptor fetching from external ROM
// - Address latching after STATUS phase
//
// Personality-aware interface routing:
// - Personalities 0,1 (GW, HxC): CDC on interfaces 1,2
// - Personality 2 (KryoFlux): CDC on interfaces 1,2
// - Personality 3 (FluxRipper): MSC on IF0, Vendor on IF1, CDC on interfaces 2,3
//
// Last Modified: 2025-12-07 10:15:00
//
// SETUP Packet Format (8 bytes, little-endian):
//   [0]: bmRequestType [7]=dir(0=OUT,1=IN), [6:5]=type(0=std,1=class,2=vendor), [4:0]=recipient
//   [1]: bRequest
//   [2:3]: wValue
//   [4:5]: wIndex
//   [6:7]: wLength
//
// Standard Requests:
//   0x00 GET_STATUS, 0x01 CLEAR_FEATURE, 0x03 SET_FEATURE
//   0x05 SET_ADDRESS, 0x06 GET_DESCRIPTOR, 0x08 GET_CONFIGURATION, 0x09 SET_CONFIGURATION
//
// KryoFlux Vendor Requests (bmRequestType=0xC3):
//   0x05 RESET, 0x06 DEVICE, 0x07 MOTOR, 0x08 DENSITY, 0x09 SIDE
//   0x0A TRACK, 0x0B STREAM, 0x0C MIN_TRACK, 0x0D MAX_TRACK
//   0x80 STATUS, 0x81 INFO

module usb_control_ep (
    input         clk,
    input         rst_n,

    // From device core - SETUP and DATA phases
    input         setup_valid,
    input  [63:0] setup_packet,    // 8 bytes packed [63:56]=byte0, [55:48]=byte1, etc.
    input         out_valid,       // OUT data phase
    input  [7:0]  out_data,
    input         out_last,
    output reg [7:0] in_data,      // IN data phase
    output reg    in_valid,
    output reg    in_last,
    input         in_ready,

    // Handshake control
    output reg    send_ack,        // ACK this phase
    output reg    send_stall,      // STALL unsupported request
    input         phase_done,      // Host ACK received, advance state

    // Address/Configuration management
    output reg [6:0] new_address,
    output reg    address_valid,   // Latch address after STATUS
    output reg [7:0] new_config,
    output reg    config_valid,
    input  [6:0]  current_address,
    input  [7:0]  current_config,

    // Descriptor ROM interface
    output reg [7:0] desc_type,
    output reg [7:0] desc_index,
    output reg [15:0] desc_length,
    output reg    desc_request,
    input  [7:0]  desc_data,
    input         desc_valid,
    input         desc_last,

    // KryoFlux vendor request interface
    input  [2:0]  personality,     // Current USB personality (0=DiskTool, 1=Stream, etc.)
    output reg    kf_cmd_valid,
    output reg [7:0] kf_cmd_request,
    output reg [15:0] kf_cmd_value,
    output reg [15:0] kf_cmd_index,
    output reg [15:0] kf_cmd_length,
    input  [7:0]  kf_response_data,
    input         kf_response_valid,
    input         kf_response_last,
    output        kf_out_data_valid,
    output [7:0]  kf_out_data,

    // CDC ACM class request interface
    output reg    cdc_setup_valid,
    output reg [7:0]  cdc_request,
    output reg [15:0] cdc_value,
    output reg [15:0] cdc_index,
    output reg [15:0] cdc_length,
    input  [7:0]  cdc_response_data,
    input         cdc_response_valid,
    input         cdc_response_last,
    input         cdc_request_handled,
    output        cdc_out_data_valid,
    output [7:0]  cdc_out_data
);

    // USB Request Type field decoding
    localparam USB_DIR_OUT     = 1'b0;
    localparam USB_DIR_IN      = 1'b1;
    localparam USB_TYPE_STD    = 2'b00;
    localparam USB_TYPE_CLASS  = 2'b01;
    localparam USB_TYPE_VENDOR = 2'b10;

    // CDC ACM Class Requests
    localparam CDC_REQ_SET_LINE_CODING        = 8'h20;
    localparam CDC_REQ_GET_LINE_CODING        = 8'h21;
    localparam CDC_REQ_SET_CONTROL_LINE_STATE = 8'h22;

    // MSC (Mass Storage Class) Requests - Bulk-Only Transport
    localparam MSC_REQ_GET_MAX_LUN = 8'hFE;  // Get Max LUN (returns 0 for single LUN)
    localparam MSC_REQ_BULK_RESET  = 8'hFF;  // Bulk-Only Mass Storage Reset

    // Standard USB requests
    localparam REQ_GET_STATUS        = 8'h00;
    localparam REQ_CLEAR_FEATURE     = 8'h01;
    localparam REQ_SET_FEATURE       = 8'h03;
    localparam REQ_SET_ADDRESS       = 8'h05;
    localparam REQ_GET_DESCRIPTOR    = 8'h06;
    localparam REQ_GET_CONFIGURATION = 8'h08;
    localparam REQ_SET_CONFIGURATION = 8'h09;

    // KryoFlux vendor requests
    localparam KF_REQ_RESET     = 8'h05;
    localparam KF_REQ_DEVICE    = 8'h06;
    localparam KF_REQ_MOTOR     = 8'h07;
    localparam KF_REQ_DENSITY   = 8'h08;
    localparam KF_REQ_SIDE      = 8'h09;
    localparam KF_REQ_TRACK     = 8'h0A;
    localparam KF_REQ_STREAM    = 8'h0B;
    localparam KF_REQ_MIN_TRACK = 8'h0C;
    localparam KF_REQ_MAX_TRACK = 8'h0D;
    localparam KF_REQ_STATUS    = 8'h80;
    localparam KF_REQ_INFO      = 8'h81;

    // State machine
    localparam ST_IDLE             = 4'd0;
    localparam ST_PARSE_SETUP      = 4'd1;
    localparam ST_HANDLE_STANDARD  = 4'd2;
    localparam ST_HANDLE_KF_VENDOR = 4'd3;
    localparam ST_TX_DESCRIPTOR    = 4'd4;
    localparam ST_DATA_IN          = 4'd5;
    localparam ST_DATA_OUT         = 4'd6;
    localparam ST_STATUS_IN        = 4'd7;  // ZLP IN after OUT data
    localparam ST_STATUS_OUT       = 4'd8;  // Wait for OUT ZLP after IN data
    localparam ST_STALL            = 4'd9;
    localparam ST_HANDLE_CDC_CLASS = 4'd10; // CDC ACM class requests
    localparam ST_HANDLE_MSC_CLASS = 4'd11; // MSC (Mass Storage) class requests

    reg [3:0] state, next_state;

    // SETUP packet fields (stored on setup_valid)
    reg [7:0]  bmRequestType;
    reg [7:0]  bRequest;
    reg [15:0] wValue;
    reg [15:0] wIndex;
    reg [15:0] wLength;
    reg        data_dir_in;    // bmRequestType[7]
    reg [1:0]  req_type;       // bmRequestType[6:5]

    // Request processing
    reg [7:0]  pending_address;
    reg        address_pending;
    reg [15:0] bytes_remaining;
    reg [15:0] byte_count;

    // Status response (GET_STATUS)
    reg [15:0] status_word;
    reg [1:0]  status_byte_idx;

    // Pass OUT data to KryoFlux protocol
    assign kf_out_data_valid = (state == ST_DATA_OUT) && out_valid && (req_type == USB_TYPE_VENDOR);
    assign kf_out_data = out_data;

    // Pass OUT data to CDC (for SET_LINE_CODING)
    assign cdc_out_data_valid = (state == ST_DATA_OUT) && out_valid && (req_type == USB_TYPE_CLASS);
    assign cdc_out_data = out_data;

    //--------------------------------------------------------------------------
    // SETUP Packet Capture
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bmRequestType <= 8'h00;
            bRequest      <= 8'h00;
            wValue        <= 16'h0000;
            wIndex        <= 16'h0000;
            wLength       <= 16'h0000;
            data_dir_in   <= 1'b0;
            req_type      <= 2'b00;
        end else if (setup_valid) begin
            // setup_packet[63:0] = {byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7}
            bmRequestType <= setup_packet[63:56];
            bRequest      <= setup_packet[55:48];
            wValue        <= {setup_packet[39:32], setup_packet[47:40]};  // Little-endian
            wIndex        <= {setup_packet[23:16], setup_packet[31:24]};
            wLength       <= {setup_packet[7:0],   setup_packet[15:8]};
            data_dir_in   <= setup_packet[63];    // Bit 7 of bmRequestType
            req_type      <= setup_packet[62:61]; // Bits [6:5]
        end
    end

    //--------------------------------------------------------------------------
    // State Machine
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (setup_valid)
                    next_state = ST_PARSE_SETUP;
            end

            ST_PARSE_SETUP: begin
                // Decode request type and route to handler
                if (req_type == USB_TYPE_STD)
                    next_state = ST_HANDLE_STANDARD;
                else if (req_type == USB_TYPE_VENDOR && bmRequestType == 8'hC3)
                    next_state = ST_HANDLE_KF_VENDOR;
                else if (req_type == USB_TYPE_CLASS) begin
                    // Route class requests based on personality and interface
                    // Personality 3 (FluxRipper): IF0=MSC, IF1=Vendor, IF2/3=CDC
                    // Other personalities: IF0=Vendor, IF1/2=CDC
                    if (personality == 3'd3) begin
                        // FluxRipper composite: MSC + Vendor + CDC
                        if (wIndex[7:0] == 8'd0)
                            next_state = ST_HANDLE_MSC_CLASS;  // MSC on interface 0
                        else if (wIndex[7:0] == 8'd2 || wIndex[7:0] == 8'd3)
                            next_state = ST_HANDLE_CDC_CLASS;  // CDC on interfaces 2,3
                        else
                            next_state = ST_STALL;  // Unknown class interface
                    end else begin
                        // GW, HxC, KryoFlux: CDC on interfaces 1,2
                        if (wIndex[7:0] == 8'd1 || wIndex[7:0] == 8'd2)
                            next_state = ST_HANDLE_CDC_CLASS;
                        else
                            next_state = ST_STALL;  // Unknown class interface
                    end
                end
                else
                    next_state = ST_STALL;  // Unsupported request type
            end

            ST_HANDLE_STANDARD: begin
                // Route to appropriate handler based on bRequest
                case (bRequest)
                    REQ_GET_DESCRIPTOR: next_state = ST_TX_DESCRIPTOR;
                    REQ_GET_STATUS:     next_state = ST_DATA_IN;
                    REQ_SET_ADDRESS,
                    REQ_SET_CONFIGURATION,
                    REQ_CLEAR_FEATURE,
                    REQ_SET_FEATURE:    next_state = ST_STATUS_IN;  // No data phase
                    REQ_GET_CONFIGURATION: next_state = ST_DATA_IN;
                    default:            next_state = ST_STALL;
                endcase
            end

            ST_HANDLE_KF_VENDOR: begin
                // KryoFlux requests: check if IN or OUT data phase
                if (wLength == 16'd0)
                    next_state = ST_STATUS_IN;   // No data phase
                else if (data_dir_in)
                    next_state = ST_DATA_IN;     // Device to host
                else
                    next_state = ST_DATA_OUT;    // Host to device
            end

            ST_HANDLE_CDC_CLASS: begin
                // CDC ACM class requests:
                // SET_LINE_CODING (0x20): OUT data phase (7 bytes line coding)
                // GET_LINE_CODING (0x21): IN data phase (7 bytes line coding)
                // SET_CONTROL_LINE_STATE (0x22): No data phase
                case (bRequest)
                    CDC_REQ_SET_LINE_CODING:        next_state = ST_DATA_OUT;   // Host sends 7 bytes
                    CDC_REQ_GET_LINE_CODING:        next_state = ST_DATA_IN;    // Device sends 7 bytes
                    CDC_REQ_SET_CONTROL_LINE_STATE: next_state = ST_STATUS_IN;  // No data
                    default:                        next_state = ST_STALL;      // Unknown CDC request
                endcase
            end

            ST_HANDLE_MSC_CLASS: begin
                // MSC (Mass Storage Class) Bulk-Only Transport requests:
                // GET_MAX_LUN (0xFE): Returns max LUN number (1 byte, value 0 for single LUN)
                // Bulk-Only Reset (0xFF): Resets MSC interface, no data phase
                case (bRequest)
                    MSC_REQ_GET_MAX_LUN: next_state = ST_DATA_IN;    // Device sends 1 byte
                    MSC_REQ_BULK_RESET:  next_state = ST_STATUS_IN;  // No data phase
                    default:             next_state = ST_STALL;      // Unknown MSC request
                endcase
            end

            ST_TX_DESCRIPTOR: begin
                if (desc_valid && desc_last && in_ready && phase_done)
                    next_state = ST_STATUS_OUT;  // Wait for OUT ZLP
            end

            ST_DATA_IN: begin
                if (in_valid && in_last && in_ready && phase_done)
                    next_state = ST_STATUS_OUT;
            end

            ST_DATA_OUT: begin
                if (out_valid && out_last && phase_done)
                    next_state = ST_STATUS_IN;   // Send ZLP
            end

            ST_STATUS_IN: begin
                if (phase_done)
                    next_state = ST_IDLE;
            end

            ST_STATUS_OUT: begin
                if (phase_done)
                    next_state = ST_IDLE;
            end

            ST_STALL: begin
                if (phase_done)
                    next_state = ST_IDLE;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // Control Outputs
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            send_ack          <= 1'b0;
            send_stall        <= 1'b0;
            in_data           <= 8'h00;
            in_valid          <= 1'b0;
            in_last           <= 1'b0;
            address_valid     <= 1'b0;
            new_address       <= 7'h00;
            config_valid      <= 1'b0;
            new_config        <= 8'h00;
            desc_request      <= 1'b0;
            desc_type         <= 8'h00;
            desc_index        <= 8'h00;
            desc_length       <= 16'h0000;
            kf_cmd_valid      <= 1'b0;
            kf_cmd_request    <= 8'h00;
            kf_cmd_value      <= 16'h0000;
            kf_cmd_index      <= 16'h0000;
            kf_cmd_length     <= 16'h0000;
            cdc_setup_valid   <= 1'b0;
            cdc_request       <= 8'h00;
            cdc_value         <= 16'h0000;
            cdc_index         <= 16'h0000;
            cdc_length        <= 16'h0000;
            pending_address   <= 8'h00;
            address_pending   <= 1'b0;
            bytes_remaining   <= 16'h0000;
            byte_count        <= 16'h0000;
            status_word       <= 16'h0000;
            status_byte_idx   <= 2'd0;
        end else begin
            // Default: clear one-shot signals
            address_valid   <= 1'b0;
            config_valid    <= 1'b0;
            desc_request    <= 1'b0;
            kf_cmd_valid    <= 1'b0;
            cdc_setup_valid <= 1'b0;
            send_ack        <= 1'b0;
            send_stall      <= 1'b0;
            in_valid        <= 1'b0;
            in_last         <= 1'b0;

            case (state)
                ST_IDLE: begin
                    address_pending <= 1'b0;
                end

                ST_HANDLE_STANDARD: begin
                    case (bRequest)
                        REQ_SET_ADDRESS: begin
                            // Store address to latch after STATUS
                            pending_address <= wValue[6:0];
                            address_pending <= 1'b1;
                        end

                        REQ_SET_CONFIGURATION: begin
                            new_config   <= wValue[7:0];
                            config_valid <= 1'b1;
                        end

                        REQ_GET_DESCRIPTOR: begin
                            // wValue[15:8]=type, wValue[7:0]=index
                            desc_type    <= wValue[15:8];
                            desc_index   <= wValue[7:0];
                            desc_length  <= (wLength < bytes_remaining) ? wLength : bytes_remaining;
                            desc_request <= 1'b1;
                        end

                        REQ_GET_STATUS: begin
                            // Return 2-byte status word (self-powered, remote wakeup, etc.)
                            status_word     <= 16'h0001;  // Self-powered
                            bytes_remaining <= 16'd2;
                            status_byte_idx <= 2'd0;
                        end

                        REQ_GET_CONFIGURATION: begin
                            status_word     <= {8'h00, current_config};
                            bytes_remaining <= 16'd1;
                            status_byte_idx <= 2'd0;
                        end
                    endcase
                end

                ST_HANDLE_KF_VENDOR: begin
                    // Issue vendor command to KryoFlux protocol
                    kf_cmd_valid   <= 1'b1;
                    kf_cmd_request <= bRequest;
                    kf_cmd_value   <= wValue;
                    kf_cmd_index   <= wIndex;
                    kf_cmd_length  <= wLength;
                    bytes_remaining <= wLength;
                    byte_count     <= 16'd0;
                end

                ST_HANDLE_CDC_CLASS: begin
                    // Issue CDC ACM class request to CDC endpoint module
                    cdc_setup_valid <= 1'b1;
                    cdc_request     <= bRequest;
                    cdc_value       <= wValue;
                    cdc_index       <= wIndex;
                    cdc_length      <= wLength;
                    bytes_remaining <= wLength;
                    byte_count      <= 16'd0;
                end

                ST_HANDLE_MSC_CLASS: begin
                    // Handle MSC class requests inline
                    case (bRequest)
                        MSC_REQ_GET_MAX_LUN: begin
                            // Return 1 byte: max LUN number (0 = single LUN)
                            status_word     <= 16'h0000;  // LUN 0 only
                            bytes_remaining <= 16'd1;
                            status_byte_idx <= 2'd0;
                        end
                        MSC_REQ_BULK_RESET: begin
                            // No data phase - STATUS_IN will be sent
                            // Could add msc_reset pulse output here if needed
                        end
                    endcase
                end

                ST_TX_DESCRIPTOR: begin
                    if (desc_valid && in_ready) begin
                        in_data  <= desc_data;
                        in_valid <= 1'b1;
                        in_last  <= desc_last;
                        if (desc_last)
                            send_ack <= 1'b1;
                    end
                end

                ST_DATA_IN: begin
                    // Generic IN data phase (status, config, MSC, CDC, or KryoFlux response)
                    if (in_ready) begin
                        if (bRequest == REQ_GET_STATUS || bRequest == REQ_GET_CONFIGURATION ||
                            bRequest == MSC_REQ_GET_MAX_LUN) begin
                            // Standard or MSC request: send status_word bytes
                            case (status_byte_idx)
                                2'd0: in_data <= status_word[7:0];
                                2'd1: in_data <= status_word[15:8];
                                default: in_data <= 8'h00;
                            endcase
                            in_valid <= 1'b1;
                            in_last  <= (status_byte_idx == bytes_remaining - 1);
                            status_byte_idx <= status_byte_idx + 1'd1;
                            if (status_byte_idx == bytes_remaining - 1)
                                send_ack <= 1'b1;
                        end else if (req_type == USB_TYPE_CLASS) begin
                            // CDC class response (GET_LINE_CODING)
                            if (cdc_response_valid) begin
                                in_data  <= cdc_response_data;
                                in_valid <= 1'b1;
                                in_last  <= cdc_response_last;
                                byte_count <= byte_count + 1'd1;
                                if (cdc_response_last)
                                    send_ack <= 1'b1;
                            end
                        end else begin
                            // KryoFlux vendor response
                            if (kf_response_valid) begin
                                in_data  <= kf_response_data;
                                in_valid <= 1'b1;
                                in_last  <= kf_response_last;
                                byte_count <= byte_count + 1'd1;
                                if (kf_response_last)
                                    send_ack <= 1'b1;
                            end
                        end
                    end
                end

                ST_DATA_OUT: begin
                    // OUT data phase (KryoFlux or CDC receives data from host)
                    // Data routing handled by kf_out_data_valid/cdc_out_data_valid assigns
                    if (out_valid) begin
                        byte_count <= byte_count + 1'd1;
                        if (out_last)
                            send_ack <= 1'b1;  // ACK the OUT transaction
                    end
                end

                ST_STATUS_IN: begin
                    // Send ZLP (zero-length packet) for STATUS IN
                    if (in_ready) begin
                        in_valid <= 1'b1;
                        in_last  <= 1'b1;
                        send_ack <= 1'b1;

                        // Latch address if SET_ADDRESS was pending
                        if (address_pending && phase_done) begin
                            new_address   <= pending_address;
                            address_valid <= 1'b1;
                        end
                    end
                end

                ST_STATUS_OUT: begin
                    // Wait for host to send OUT ZLP, then ACK
                    if (out_valid && out_last) begin
                        send_ack <= 1'b1;

                        // Latch address if SET_ADDRESS (shouldn't happen, but handle)
                        if (address_pending && phase_done) begin
                            new_address   <= pending_address;
                            address_valid <= 1'b1;
                        end
                    end
                end

                ST_STALL: begin
                    send_stall <= 1'b1;
                end
            endcase
        end
    end

endmodule
