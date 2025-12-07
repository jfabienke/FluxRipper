// SPDX-License-Identifier: BSD-3-Clause
//
// usb_cdc_ep.v - USB CDC ACM Endpoint Module for Debug Console
//
// Part of FluxRipper - Open-source KryoFlux-compatible floppy disk reader
// Copyright (c) 2025 John Fabienke
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Created: 2025-12-06 10:30:00
// Updated: 2025-12-06 20:50:00
//
// This module implements a USB CDC ACM (Communications Device Class -
// Abstract Control Model) endpoint for providing a virtual COM port debug
// console over USB.
//
// CDC ACM Protocol Overview:
// - Communication Interface (control): Handles class-specific requests
//   * SET_LINE_CODING (0x20): Configure baud rate, stop bits, parity, data bits
//   * GET_LINE_CODING (0x21): Return current line coding settings
//   * SET_CONTROL_LINE_STATE (0x22): Set DTR/RTS signals from host
//
// - Data Interface: Bulk IN/OUT endpoints for actual data transfer
//   * EP3 IN (Bulk): Debug output from device to host
//   * EP3 OUT (Bulk): Commands from host to device
//
// Line Coding Structure (7 bytes):
//   Offset 0-3: dwDTERate (32-bit) - Baud rate in bits per second
//   Offset 4:   bCharFormat (8-bit) - Stop bits (0=1, 1=1.5, 2=2)
//   Offset 5:   bParityType (8-bit) - Parity (0=None, 1=Odd, 2=Even)
//   Offset 6:   bDataBits (8-bit)   - Data bits (5, 6, 7, 8)
//
// Features:
// - High-speed (512 bytes) and full-speed (64 bytes) bulk packet support
// - Internal TX FIFO (256 bytes) for debug output buffering
// - Internal RX FIFO (64 bytes) for command input buffering
// - DTR/RTS status tracking
// - Automatic DATA0/DATA1 toggle management
// - Zero-length packet (ZLP) handling for exact packet size multiples

module usb_cdc_ep (
    input         clk,
    input         rst_n,

    // Speed selection
    input         high_speed,           // 1=High Speed (512B), 0=Full Speed (64B)

    // Control transfer interface (from usb_control_ep)
    input         ctrl_setup_valid,     // SETUP packet received (cdc_setup_valid from control_ep)
    input  [7:0]  ctrl_request,         // bRequest field (cdc_request from control_ep)
    input  [15:0] ctrl_value,           // wValue field (cdc_value from control_ep)
    input  [15:0] ctrl_index,           // wIndex field (cdc_index from control_ep)
    input  [15:0] ctrl_length,          // wLength field (cdc_length from control_ep)
    output [7:0]  ctrl_response_data,   // Response data to send (to cdc_response_data)
    output        ctrl_response_valid,  // Response data valid (to cdc_response_valid)
    output        ctrl_response_last,   // Last byte of response (to cdc_response_last)
    input         ctrl_out_valid,       // OUT data phase valid (cdc_out_data_valid from control_ep)
    input  [7:0]  ctrl_out_data,        // OUT data phase byte (cdc_out_data from control_ep)
    output        ctrl_request_handled, // This module handled the request (to cdc_request_handled)

    // Bulk data interface (from device core)
    input         token_in,             // IN token received
    input         token_out,            // OUT token received
    input  [3:0]  token_ep,             // Endpoint number
    input  [7:0]  rx_data,              // Received data byte
    input         rx_valid,             // Received data valid
    input         rx_last,              // Last byte of packet
    output [7:0]  tx_data,              // Transmit data byte
    output        tx_valid,             // Transmit data valid
    output        tx_last,              // Last byte of packet
    input         tx_ready,             // Device core ready for next byte
    output        send_ack,             // Send ACK handshake
    output        send_nak,             // Send NAK handshake

    // Debug FIFO interface
    input  [7:0]  debug_tx_data,        // Debug data to send to host
    input         debug_tx_valid,       // Debug data valid
    output        debug_tx_ready,       // Ready to accept debug data
    output [7:0]  debug_rx_data,        // Command data from host
    output        debug_rx_valid,       // Command data valid
    input         debug_rx_ready,       // Ready to accept command data

    // Status outputs
    output        dtr_active,           // DTR signal (terminal connected)
    output        rts_active,           // RTS signal
    output        cdc_configured,       // CDC interface configured
    output [31:0] line_coding_baud      // Current baud rate setting
);

// ============================================================================
// CDC ACM Class Request Definitions
// ============================================================================
localparam [7:0] CDC_REQ_SET_LINE_CODING        = 8'h20;
localparam [7:0] CDC_REQ_GET_LINE_CODING        = 8'h21;
localparam [7:0] CDC_REQ_SET_CONTROL_LINE_STATE = 8'h22;

// Request type fields
localparam [7:0] REQ_TYPE_HOST_TO_DEV_CLASS_IF = 8'h21;
localparam [7:0] REQ_TYPE_DEV_TO_HOST_CLASS_IF = 8'hA1;

// Endpoint definitions
localparam [3:0] EP_CDC_IN  = 4'd3;  // Bulk IN endpoint
localparam [3:0] EP_CDC_OUT = 4'd3;  // Bulk OUT endpoint

// Packet sizes
localparam [9:0] HS_MAX_PACKET_SIZE = 10'd512;  // High-speed bulk
localparam [9:0] FS_MAX_PACKET_SIZE = 10'd64;   // Full-speed bulk

// FIFO sizes
localparam TX_FIFO_DEPTH = 256;  // TX FIFO depth
localparam RX_FIFO_DEPTH = 64;   // RX FIFO depth

// ============================================================================
// Line Coding Storage (7 bytes)
// ============================================================================
reg [31:0] line_coding_rate;      // dwDTERate (bytes 0-3)
reg [7:0]  line_coding_stop;      // bCharFormat (byte 4)
reg [7:0]  line_coding_parity;    // bParityType (byte 5)
reg [7:0]  line_coding_databits;  // bDataBits (byte 6)

// Control line state
reg        dtr_bit;               // DTR (Data Terminal Ready)
reg        rts_bit;               // RTS (Request To Send)

// Configuration state
reg        cdc_configured_reg;

// ============================================================================
// Control Request Handling
// ============================================================================
reg [2:0]  ctrl_state;
reg [2:0]  ctrl_byte_count;
reg [7:0]  ctrl_resp_data_reg;
reg        ctrl_resp_valid_reg;
reg        ctrl_resp_last_reg;
reg        ctrl_handled_reg;

// Control state machine states
localparam CTRL_IDLE       = 3'd0;
localparam CTRL_GET_CODING = 3'd1;
localparam CTRL_SET_CODING = 3'd2;
localparam CTRL_SET_CTRL   = 3'd3;
localparam CTRL_DONE       = 3'd4;

// Assign outputs
assign ctrl_response_data   = ctrl_resp_data_reg;
assign ctrl_response_valid  = ctrl_resp_valid_reg;
assign ctrl_response_last   = ctrl_resp_last_reg;
assign ctrl_request_handled = ctrl_handled_reg;

// Control request handler
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ctrl_state          <= CTRL_IDLE;
        ctrl_byte_count     <= 3'd0;
        ctrl_resp_data_reg  <= 8'd0;
        ctrl_resp_valid_reg <= 1'b0;
        ctrl_resp_last_reg  <= 1'b0;
        ctrl_handled_reg    <= 1'b0;
        line_coding_rate    <= 32'd115200;  // Default 115200 baud
        line_coding_stop    <= 8'd0;        // 1 stop bit
        line_coding_parity  <= 8'd0;        // No parity
        line_coding_databits<= 8'd8;        // 8 data bits
        dtr_bit             <= 1'b0;
        rts_bit             <= 1'b0;
        cdc_configured_reg  <= 1'b0;
    end else begin
        case (ctrl_state)
            CTRL_IDLE: begin
                ctrl_resp_valid_reg <= 1'b0;
                ctrl_resp_last_reg  <= 1'b0;
                ctrl_handled_reg    <= 1'b0;
                ctrl_byte_count     <= 3'd0;

                if (ctrl_setup_valid) begin
                    // Check for CDC class requests
                    if (ctrl_request == CDC_REQ_GET_LINE_CODING) begin
                        ctrl_state       <= CTRL_GET_CODING;
                        ctrl_handled_reg <= 1'b1;
                        ctrl_byte_count  <= 3'd0;
                    end else if (ctrl_request == CDC_REQ_SET_LINE_CODING) begin
                        ctrl_state       <= CTRL_SET_CODING;
                        ctrl_handled_reg <= 1'b1;
                        ctrl_byte_count  <= 3'd0;
                    end else if (ctrl_request == CDC_REQ_SET_CONTROL_LINE_STATE) begin
                        ctrl_state       <= CTRL_SET_CTRL;
                        ctrl_handled_reg <= 1'b1;
                        // Update control line state from wValue
                        dtr_bit          <= ctrl_value[0];
                        rts_bit          <= ctrl_value[1];
                        cdc_configured_reg <= ctrl_value[0]; // Use DTR as configured indicator
                    end
                end
            end

            CTRL_GET_CODING: begin
                // Send line coding structure (7 bytes)
                ctrl_resp_valid_reg <= 1'b1;

                case (ctrl_byte_count)
                    3'd0: ctrl_resp_data_reg <= line_coding_rate[7:0];
                    3'd1: ctrl_resp_data_reg <= line_coding_rate[15:8];
                    3'd2: ctrl_resp_data_reg <= line_coding_rate[23:16];
                    3'd3: ctrl_resp_data_reg <= line_coding_rate[31:24];
                    3'd4: ctrl_resp_data_reg <= line_coding_stop;
                    3'd5: ctrl_resp_data_reg <= line_coding_parity;
                    3'd6: begin
                        ctrl_resp_data_reg <= line_coding_databits;
                        ctrl_resp_last_reg <= 1'b1;  // Last byte
                    end
                    default: ctrl_resp_data_reg <= 8'd0;
                endcase

                ctrl_byte_count <= ctrl_byte_count + 3'd1;

                if (ctrl_byte_count == 3'd6) begin
                    ctrl_state <= CTRL_DONE;
                end
            end

            CTRL_SET_CODING: begin
                // Receive line coding structure (7 bytes)
                if (ctrl_out_valid) begin
                    case (ctrl_byte_count)
                        3'd0: line_coding_rate[7:0]   <= ctrl_out_data;
                        3'd1: line_coding_rate[15:8]  <= ctrl_out_data;
                        3'd2: line_coding_rate[23:16] <= ctrl_out_data;
                        3'd3: line_coding_rate[31:24] <= ctrl_out_data;
                        3'd4: line_coding_stop        <= ctrl_out_data;
                        3'd5: line_coding_parity      <= ctrl_out_data;
                        3'd6: line_coding_databits    <= ctrl_out_data;
                    endcase

                    ctrl_byte_count <= ctrl_byte_count + 3'd1;

                    if (ctrl_byte_count == 3'd6) begin
                        ctrl_state <= CTRL_DONE;
                    end
                end
            end

            CTRL_SET_CTRL: begin
                // Control line state already updated in IDLE state
                ctrl_state <= CTRL_DONE;
            end

            CTRL_DONE: begin
                ctrl_resp_valid_reg <= 1'b0;
                ctrl_resp_last_reg  <= 1'b0;
                ctrl_handled_reg    <= 1'b0;
                ctrl_state          <= CTRL_IDLE;
            end

            default: ctrl_state <= CTRL_IDLE;
        endcase
    end
end

// ============================================================================
// TX FIFO (Debug Output to Host)
// ============================================================================
reg [7:0]  tx_fifo_mem [0:TX_FIFO_DEPTH-1];
reg [7:0]  tx_fifo_wr_ptr;
reg [7:0]  tx_fifo_rd_ptr;
reg [8:0]  tx_fifo_count;  // 9 bits to represent 0-256
wire       tx_fifo_full;
wire       tx_fifo_empty;
wire       tx_fifo_rd_en;
wire [7:0] tx_fifo_rd_data;

assign tx_fifo_full     = (tx_fifo_count == TX_FIFO_DEPTH);
assign tx_fifo_empty    = (tx_fifo_count == 9'd0);
assign debug_tx_ready   = !tx_fifo_full;
assign tx_fifo_rd_data  = tx_fifo_mem[tx_fifo_rd_ptr];

// TX FIFO write logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_fifo_wr_ptr <= 8'd0;
    end else begin
        if (debug_tx_valid && !tx_fifo_full) begin
            tx_fifo_mem[tx_fifo_wr_ptr] <= debug_tx_data;
            tx_fifo_wr_ptr <= tx_fifo_wr_ptr + 8'd1;
        end
    end
end

// TX FIFO read logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_fifo_rd_ptr <= 8'd0;
    end else begin
        if (tx_fifo_rd_en && !tx_fifo_empty) begin
            tx_fifo_rd_ptr <= tx_fifo_rd_ptr + 8'd1;
        end
    end
end

// TX FIFO count
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_fifo_count <= 9'd0;
    end else begin
        case ({debug_tx_valid && !tx_fifo_full, tx_fifo_rd_en && !tx_fifo_empty})
            2'b10:   tx_fifo_count <= tx_fifo_count + 9'd1;  // Write only
            2'b01:   tx_fifo_count <= tx_fifo_count - 9'd1;  // Read only
            default: tx_fifo_count <= tx_fifo_count;         // Both or neither
        endcase
    end
end

// ============================================================================
// RX FIFO (Commands from Host)
// ============================================================================
reg [7:0]  rx_fifo_mem [0:RX_FIFO_DEPTH-1];
reg [5:0]  rx_fifo_wr_ptr;
reg [5:0]  rx_fifo_rd_ptr;
reg [6:0]  rx_fifo_count;  // 7 bits to represent 0-64
wire       rx_fifo_full;
wire       rx_fifo_empty;
wire       rx_fifo_wr_en;
wire [7:0] rx_fifo_wr_data;

assign rx_fifo_full     = (rx_fifo_count == RX_FIFO_DEPTH);
assign rx_fifo_empty    = (rx_fifo_count == 7'd0);
assign debug_rx_data    = rx_fifo_mem[rx_fifo_rd_ptr];
assign debug_rx_valid   = !rx_fifo_empty;

// RX FIFO write logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_fifo_wr_ptr <= 6'd0;
    end else begin
        if (rx_fifo_wr_en && !rx_fifo_full) begin
            rx_fifo_mem[rx_fifo_wr_ptr] <= rx_fifo_wr_data;
            rx_fifo_wr_ptr <= rx_fifo_wr_ptr + 6'd1;
        end
    end
end

// RX FIFO read logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_fifo_rd_ptr <= 6'd0;
    end else begin
        if (debug_rx_ready && !rx_fifo_empty) begin
            rx_fifo_rd_ptr <= rx_fifo_rd_ptr + 6'd1;
        end
    end
end

// RX FIFO count
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_fifo_count <= 7'd0;
    end else begin
        case ({rx_fifo_wr_en && !rx_fifo_full, debug_rx_ready && !rx_fifo_empty})
            2'b10:   rx_fifo_count <= rx_fifo_count + 7'd1;  // Write only
            2'b01:   rx_fifo_count <= rx_fifo_count - 7'd1;  // Read only
            default: rx_fifo_count <= rx_fifo_count;         // Both or neither
        endcase
    end
end

// ============================================================================
// Bulk IN Transfer State Machine (Device to Host)
// ============================================================================
reg [2:0]  tx_state;
reg [9:0]  tx_byte_count;
reg [9:0]  tx_packet_size;
reg        tx_data_toggle;
reg [7:0]  tx_data_reg;
reg        tx_valid_reg;
reg        tx_last_reg;
reg        send_nak_reg;

// TX states
localparam TX_IDLE     = 3'd0;
localparam TX_SEND     = 3'd1;
localparam TX_LAST     = 3'd2;
localparam TX_ZLP      = 3'd3;  // Zero-length packet
localparam TX_WAIT     = 3'd4;

assign tx_data       = tx_data_reg;
assign tx_valid      = tx_valid_reg;
assign tx_last       = tx_last_reg;
assign tx_fifo_rd_en = (tx_state == TX_SEND && tx_ready && !tx_fifo_empty);

// Determine max packet size based on speed
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_packet_size <= FS_MAX_PACKET_SIZE;
    end else begin
        tx_packet_size <= high_speed ? HS_MAX_PACKET_SIZE : FS_MAX_PACKET_SIZE;
    end
end

// Bulk IN state machine
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_state       <= TX_IDLE;
        tx_byte_count  <= 10'd0;
        tx_data_toggle <= 1'b0;
        tx_data_reg    <= 8'd0;
        tx_valid_reg   <= 1'b0;
        tx_last_reg    <= 1'b0;
        send_nak_reg   <= 1'b0;
    end else begin
        case (tx_state)
            TX_IDLE: begin
                tx_valid_reg  <= 1'b0;
                tx_last_reg   <= 1'b0;
                send_nak_reg  <= 1'b0;
                tx_byte_count <= 10'd0;

                // Wait for IN token on CDC endpoint
                if (token_in && token_ep == EP_CDC_IN) begin
                    if (tx_fifo_empty) begin
                        // No data to send, NAK the request
                        send_nak_reg <= 1'b1;
                        tx_state     <= TX_WAIT;
                    end else begin
                        // Start sending data
                        tx_state <= TX_SEND;
                    end
                end
            end

            TX_SEND: begin
                if (!tx_fifo_empty && tx_ready) begin
                    tx_data_reg   <= tx_fifo_rd_data;
                    tx_valid_reg  <= 1'b1;
                    tx_byte_count <= tx_byte_count + 10'd1;

                    // Check if this is the last byte of packet
                    if (tx_byte_count + 10'd1 == tx_packet_size || tx_fifo_count == 9'd1) begin
                        tx_last_reg <= 1'b1;
                        tx_state    <= TX_LAST;
                    end
                end else begin
                    tx_valid_reg <= 1'b0;
                end
            end

            TX_LAST: begin
                tx_valid_reg <= 1'b0;
                tx_last_reg  <= 1'b0;

                // Toggle DATA0/DATA1
                tx_data_toggle <= !tx_data_toggle;

                // Check if we need to send ZLP
                // ZLP required if packet is exactly max packet size and more data may follow
                if (tx_byte_count == tx_packet_size && !tx_fifo_empty) begin
                    tx_state      <= TX_ZLP;
                    tx_byte_count <= 10'd0;
                end else begin
                    tx_state <= TX_WAIT;
                end
            end

            TX_ZLP: begin
                // Send zero-length packet to indicate end of transfer
                tx_valid_reg <= 1'b0;
                tx_last_reg  <= 1'b1;  // Immediately assert last with no data
                tx_state     <= TX_WAIT;
                tx_data_toggle <= !tx_data_toggle;
            end

            TX_WAIT: begin
                tx_last_reg  <= 1'b0;
                send_nak_reg <= 1'b0;
                tx_state     <= TX_IDLE;
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

// ============================================================================
// Bulk OUT Transfer State Machine (Host to Device)
// ============================================================================
reg [2:0]  rx_state;
reg        rx_data_toggle;
reg        send_ack_reg;

// RX states
localparam RX_IDLE = 3'd0;
localparam RX_DATA = 3'd1;
localparam RX_ACK  = 3'd2;

assign rx_fifo_wr_en   = (rx_state == RX_DATA && rx_valid && !rx_fifo_full);
assign rx_fifo_wr_data = rx_data;
assign send_ack        = send_ack_reg;
assign send_nak        = send_nak_reg;  // Already defined in TX section

// Bulk OUT state machine
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_state       <= RX_IDLE;
        rx_data_toggle <= 1'b0;
        send_ack_reg   <= 1'b0;
    end else begin
        case (rx_state)
            RX_IDLE: begin
                send_ack_reg <= 1'b0;

                // Wait for OUT token on CDC endpoint
                if (token_out && token_ep == EP_CDC_OUT) begin
                    if (rx_fifo_full) begin
                        // FIFO full, NAK the transfer
                        send_nak_reg <= 1'b1;
                    end else begin
                        rx_state <= RX_DATA;
                    end
                end
            end

            RX_DATA: begin
                send_nak_reg <= 1'b0;

                // Receive data and write to FIFO
                if (rx_valid && rx_last) begin
                    // End of packet
                    rx_state <= RX_ACK;
                end
            end

            RX_ACK: begin
                // Send ACK handshake
                send_ack_reg   <= 1'b1;
                rx_data_toggle <= !rx_data_toggle;
                rx_state       <= RX_IDLE;
            end

            default: rx_state <= RX_IDLE;
        endcase
    end
end

// ============================================================================
// Status Outputs
// ============================================================================
assign dtr_active       = dtr_bit;
assign rts_active       = rts_bit;
assign cdc_configured   = cdc_configured_reg;
assign line_coding_baud = line_coding_rate;

endmodule
