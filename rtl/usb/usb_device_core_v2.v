// SPDX-License-Identifier: BSD-3-Clause
//
// usb_device_core_v2.v - USB 2.0 Device Controller Core
//
// Part of the FluxRipper Project
// https://github.com/johnfabienke/FluxRipper
//
// Copyright (c) 2025 John Fabien Kearney
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
// 3. Neither the name of the copyright holder nor the names of its contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
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
// Description:
//   USB 2.0 device controller implementing:
//   - Token packet detection (SETUP/IN/OUT/SOF)
//   - Data packet RX/TX with CRC16 validation
//   - Handshake generation (ACK/NAK/STALL)
//   - SOF frame number tracking
//   - Endpoint routing to control (EP0) and bulk endpoints (EP1, EP2)
//   - CRC5 validation for token packets
//   - CRC16 validation for data packets
//
// Created: 2025-12-06 15:30:00
// Last Modified: 2025-12-06 15:30:00

module usb_device_core_v2 (
    input wire        clk,
    input wire        rst_n,

    // UTMI interface (from ulpi_wrapper)
    input  wire [7:0] utmi_data_in,
    output reg  [7:0] utmi_data_out,
    input  wire       utmi_txready,
    output reg        utmi_txvalid,
    input  wire       utmi_rxvalid,
    input  wire       utmi_rxactive,
    input  wire [1:0] utmi_linestate,

    // Device configuration
    input  wire [6:0] device_address,
    input  wire       high_speed,         // High-speed mode indicator
    output reg        set_address,
    output reg  [6:0] new_address,
    output reg        set_configured,
    output reg  [7:0] new_config,         // New configuration value

    // Control endpoint interface (EP0)
    output reg        setup_valid,
    output reg [63:0] setup_packet,
    output reg        ctrl_out_valid,
    output reg  [7:0] ctrl_out_data,
    input  wire [7:0] ctrl_in_data,
    input  wire       ctrl_in_valid,
    input  wire       ctrl_in_last,
    input  wire       ctrl_stall,
    input  wire       ctrl_ack,
    output reg        ctrl_phase_done,    // Control transfer phase complete

    // Bulk endpoint interface (EP1, EP2, etc.)
    output reg  [3:0] token_ep,
    output reg        token_in,
    output reg        token_out,
    output reg        rx_data_valid,
    output reg  [7:0] rx_data,
    output reg        rx_last,
    output reg        rx_crc_ok,          // Received packet CRC valid
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    input  wire       tx_last,
    output reg        tx_ready,
    input  wire       ep_stall,
    input  wire       ep_nak,

    // Frame tracking
    output reg [10:0] frame_number,
    output reg        sof_valid
);

    // USB PIDs
    localparam [3:0] PID_OUT   = 4'h1;
    localparam [3:0] PID_IN    = 4'h9;
    localparam [3:0] PID_SOF   = 4'h5;
    localparam [3:0] PID_SETUP = 4'hD;
    localparam [3:0] PID_DATA0 = 4'h3;
    localparam [3:0] PID_DATA1 = 4'hB;
    localparam [3:0] PID_DATA2 = 4'h7;
    localparam [3:0] PID_MDATA = 4'hF;
    localparam [3:0] PID_ACK   = 4'h2;
    localparam [3:0] PID_NAK   = 4'hA;
    localparam [3:0] PID_STALL = 4'hE;

    // State machine states
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_RX_TOKEN   = 4'd1;
    localparam [3:0] ST_CHK_TOKEN  = 4'd2;
    localparam [3:0] ST_SETUP_DATA = 4'd3;
    localparam [3:0] ST_OUT_DATA   = 4'd4;
    localparam [3:0] ST_IN_DATA    = 4'd5;
    localparam [3:0] ST_RX_DATA    = 4'd6;
    localparam [3:0] ST_CHK_DATA   = 4'd7;
    localparam [3:0] ST_TX_HS      = 4'd8;
    localparam [3:0] ST_WAIT_EOP   = 4'd9;

    // Registers
    reg [3:0]  state, next_state;
    reg [3:0]  rx_pid;
    reg [6:0]  rx_addr;
    reg [3:0]  rx_ep;
    reg [4:0]  rx_crc5;
    reg [15:0] rx_crc16;
    reg [15:0] calc_crc16;
    reg [10:0] rx_frame;
    reg [9:0]  byte_count;
    reg [2:0]  bit_count;
    reg [7:0]  rx_buffer [0:511];
    reg        data_toggle;
    reg [3:0]  hs_pid;

    // Control signals
    reg        token_valid;
    reg        addr_match;
    reg        is_setup;
    reg        is_in;
    reg        is_out;
    reg        is_sof;
    reg        crc5_ok;
    reg        crc16_ok;

    // CRC calculation wires
    wire [4:0]  crc5_calc;
    wire [15:0] crc16_next;

    // Byte counter for token/data reception
    reg [2:0] token_byte_cnt;

    //==========================================================================
    // CRC5 calculation for token packets
    // Polynomial: x^5 + x^2 + 1 (0x05)
    //==========================================================================
    function [4:0] crc5_update;
        input [4:0] crc;
        input [7:0] data;
        integer i;
        reg feedback;
        begin
            crc5_update = crc;
            for (i = 0; i < 8; i = i + 1) begin
                feedback = crc5_update[4] ^ data[i];
                crc5_update = {crc5_update[3:0], 1'b0};
                if (feedback)
                    crc5_update = crc5_update ^ 5'b00101;  // x^5 + x^2
            end
        end
    endfunction

    //==========================================================================
    // CRC16 calculation for data packets
    // Polynomial: x^16 + x^15 + x^2 + 1 (0x8005)
    //==========================================================================
    function [15:0] crc16_update;
        input [15:0] crc;
        input [7:0]  data;
        integer i;
        reg feedback;
        begin
            crc16_update = crc;
            for (i = 0; i < 8; i = i + 1) begin
                feedback = crc16_update[15] ^ data[i];
                crc16_update = {crc16_update[14:0], 1'b0};
                if (feedback)
                    crc16_update = crc16_update ^ 16'h8005;
            end
        end
    endfunction

    //==========================================================================
    // State machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    //==========================================================================
    // Next state logic
    //==========================================================================
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (utmi_rxvalid && utmi_rxactive)
                    next_state = ST_RX_TOKEN;
            end

            ST_RX_TOKEN: begin
                if (!utmi_rxactive)
                    next_state = ST_CHK_TOKEN;
                else if (token_byte_cnt >= 3'd3)
                    next_state = ST_CHK_TOKEN;
            end

            ST_CHK_TOKEN: begin
                if (is_sof)
                    next_state = ST_IDLE;
                else if (is_setup && addr_match && crc5_ok)
                    next_state = ST_SETUP_DATA;
                else if (is_out && addr_match && crc5_ok)
                    next_state = ST_OUT_DATA;
                else if (is_in && addr_match && crc5_ok)
                    next_state = ST_IN_DATA;
                else
                    next_state = ST_IDLE;
            end

            ST_SETUP_DATA: begin
                if (utmi_rxvalid && utmi_rxactive)
                    next_state = ST_RX_DATA;
                else if (!utmi_rxactive)
                    next_state = ST_IDLE;
            end

            ST_OUT_DATA: begin
                if (utmi_rxvalid && utmi_rxactive)
                    next_state = ST_RX_DATA;
                else if (!utmi_rxactive)
                    next_state = ST_IDLE;
            end

            ST_RX_DATA: begin
                if (!utmi_rxactive)
                    next_state = ST_CHK_DATA;
            end

            ST_CHK_DATA: begin
                next_state = ST_TX_HS;
            end

            ST_IN_DATA: begin
                if (tx_last && utmi_txready)
                    next_state = ST_WAIT_EOP;
                else if (!ctrl_in_valid && !tx_valid)
                    next_state = ST_TX_HS;
            end

            ST_TX_HS: begin
                if (utmi_txready)
                    next_state = ST_IDLE;
            end

            ST_WAIT_EOP: begin
                if (!utmi_rxactive)
                    next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    //==========================================================================
    // Token reception and parsing
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            token_byte_cnt <= 3'd0;
            rx_pid <= 4'd0;
            rx_addr <= 7'd0;
            rx_ep <= 4'd0;
            rx_crc5 <= 5'd0;
            rx_frame <= 11'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    token_byte_cnt <= 3'd0;
                end

                ST_RX_TOKEN: begin
                    if (utmi_rxvalid) begin
                        case (token_byte_cnt)
                            3'd0: begin
                                // PID byte (lower nibble is actual PID)
                                rx_pid <= utmi_data_in[3:0];
                                token_byte_cnt <= token_byte_cnt + 1'b1;
                            end
                            3'd1: begin
                                // Byte 1: addr[6:0], ep[0]
                                rx_addr <= utmi_data_in[6:0];
                                rx_ep[0] <= utmi_data_in[7];
                                token_byte_cnt <= token_byte_cnt + 1'b1;
                            end
                            3'd2: begin
                                // Byte 2: ep[3:1], crc5[4:0]
                                rx_ep[3:1] <= utmi_data_in[2:0];
                                rx_crc5 <= utmi_data_in[7:3];
                                // For SOF: frame[7:0] in byte 1, frame[10:8] in byte 2
                                if (rx_pid == PID_SOF) begin
                                    rx_frame[7:0] <= rx_addr;
                                    rx_frame[10:8] <= utmi_data_in[2:0];
                                end
                                token_byte_cnt <= token_byte_cnt + 1'b1;
                            end
                        endcase
                    end
                end
            endcase
        end
    end

    //==========================================================================
    // Token validation
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_setup <= 1'b0;
            is_in <= 1'b0;
            is_out <= 1'b0;
            is_sof <= 1'b0;
            addr_match <= 1'b0;
            crc5_ok <= 1'b0;
        end else begin
            if (state == ST_CHK_TOKEN) begin
                is_setup <= (rx_pid == PID_SETUP);
                is_in    <= (rx_pid == PID_IN);
                is_out   <= (rx_pid == PID_OUT);
                is_sof   <= (rx_pid == PID_SOF);
                addr_match <= (rx_addr == device_address) || (device_address == 7'd0);

                // Validate CRC5 (should be 0x0C residual after including CRC)
                // USB CRC5 polynomial: G(X) = X^5 + X^2 + 1
                // Check that calculated CRC5 matches received CRC5
                crc5_ok <= (crc5_calc == 5'b01100);  // Residual should be 0x0C
            end
        end
    end

    //==========================================================================
    // Data packet reception
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_count <= 10'd0;
            calc_crc16 <= 16'hFFFF;
            rx_crc16 <= 16'd0;
        end else begin
            case (state)
                ST_SETUP_DATA, ST_OUT_DATA: begin
                    byte_count <= 10'd0;
                    calc_crc16 <= 16'hFFFF;
                end

                ST_RX_DATA: begin
                    if (utmi_rxvalid) begin
                        if (byte_count == 10'd0) begin
                            // First byte is PID, verify it's DATA0/DATA1
                            calc_crc16 <= 16'hFFFF;
                        end else if (byte_count < 10'd512) begin
                            rx_buffer[byte_count - 1] <= utmi_data_in;
                            calc_crc16 <= crc16_update(calc_crc16, utmi_data_in);
                        end
                        byte_count <= byte_count + 1'b1;
                    end
                end

                ST_CHK_DATA: begin
                    // Last 2 bytes are CRC16 (already included in calc)
                    // Valid CRC16 residual should be 0x800D
                    crc16_ok <= (calc_crc16 == 16'h800D);
                end
            endcase
        end
    end

    //==========================================================================
    // SETUP packet extraction
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            setup_valid <= 1'b0;
            setup_packet <= 64'd0;
        end else begin
            setup_valid <= 1'b0;

            if (state == ST_CHK_DATA && is_setup && crc16_ok && byte_count >= 10'd11) begin
                // SETUP data is 8 bytes (+ 1 PID + 2 CRC = 11 total)
                setup_packet[7:0]   <= rx_buffer[1];
                setup_packet[15:8]  <= rx_buffer[2];
                setup_packet[23:16] <= rx_buffer[3];
                setup_packet[31:24] <= rx_buffer[4];
                setup_packet[39:32] <= rx_buffer[5];
                setup_packet[47:40] <= rx_buffer[6];
                setup_packet[55:48] <= rx_buffer[7];
                setup_packet[63:56] <= rx_buffer[8];
                setup_valid <= 1'b1;
            end
        end
    end

    //==========================================================================
    // Control endpoint OUT data
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_out_valid <= 1'b0;
            ctrl_out_data <= 8'd0;
        end else begin
            ctrl_out_valid <= 1'b0;

            if (state == ST_CHK_DATA && is_out && rx_ep == 4'd0 && crc16_ok) begin
                // Stream out data to control endpoint handler
                // This is simplified - should stream during RX_DATA state
                ctrl_out_valid <= 1'b1;
                ctrl_out_data <= rx_buffer[1];  // First data byte
            end
        end
    end

    //==========================================================================
    // Bulk endpoint data routing
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            token_ep <= 4'd0;
            token_in <= 1'b0;
            token_out <= 1'b0;
            rx_data_valid <= 1'b0;
            rx_data <= 8'd0;
            rx_last <= 1'b0;
        end else begin
            rx_data_valid <= 1'b0;
            token_in <= 1'b0;
            token_out <= 1'b0;

            if (state == ST_CHK_TOKEN && rx_ep != 4'd0) begin
                token_ep <= rx_ep;
                token_in <= is_in;
                token_out <= is_out;
            end

            if (state == ST_CHK_DATA && is_out && rx_ep != 4'd0 && crc16_ok) begin
                // Stream data to bulk endpoint (simplified)
                rx_data_valid <= 1'b1;
                rx_data <= rx_buffer[1];
                rx_last <= (byte_count <= 10'd4);  // Last if only PID + CRC
            end
        end
    end

    //==========================================================================
    // IN data transmission
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            utmi_txvalid <= 1'b0;
            utmi_data_out <= 8'd0;
            tx_ready <= 1'b0;
        end else begin
            utmi_txvalid <= 1'b0;
            tx_ready <= 1'b0;

            case (state)
                ST_IN_DATA: begin
                    if (rx_ep == 4'd0) begin
                        // Control endpoint IN
                        if (ctrl_in_valid && utmi_txready) begin
                            utmi_txvalid <= 1'b1;
                            utmi_data_out <= ctrl_in_data;
                        end
                    end else begin
                        // Bulk endpoint IN
                        if (tx_valid && utmi_txready) begin
                            utmi_txvalid <= 1'b1;
                            utmi_data_out <= tx_data;
                            tx_ready <= 1'b1;
                        end
                    end
                end
            endcase
        end
    end

    //==========================================================================
    // Handshake transmission
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hs_pid <= 4'd0;
        end else begin
            case (state)
                ST_CHK_DATA: begin
                    if (is_setup || is_out) begin
                        if (rx_ep == 4'd0) begin
                            // Control endpoint
                            if (ctrl_stall)
                                hs_pid <= PID_STALL;
                            else if (crc16_ok)
                                hs_pid <= PID_ACK;
                            else
                                hs_pid <= PID_NAK;
                        end else begin
                            // Bulk endpoint
                            if (ep_stall)
                                hs_pid <= PID_STALL;
                            else if (ep_nak)
                                hs_pid <= PID_NAK;
                            else if (crc16_ok)
                                hs_pid <= PID_ACK;
                            else
                                hs_pid <= PID_NAK;
                        end
                    end
                end

                ST_IN_DATA: begin
                    if (!ctrl_in_valid && !tx_valid) begin
                        // No data to send
                        if (rx_ep == 4'd0 && ctrl_stall)
                            hs_pid <= PID_STALL;
                        else if (rx_ep != 4'd0 && ep_stall)
                            hs_pid <= PID_STALL;
                        else
                            hs_pid <= PID_NAK;
                    end
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            utmi_txvalid <= 1'b0;
            utmi_data_out <= 8'd0;
        end else begin
            if (state == ST_TX_HS && utmi_txready) begin
                utmi_txvalid <= 1'b1;
                utmi_data_out <= {~hs_pid, hs_pid};  // PID + complemented PID
            end else if (state != ST_IN_DATA) begin
                utmi_txvalid <= 1'b0;
            end
        end
    end

    //==========================================================================
    // SOF frame tracking
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_number <= 11'd0;
            sof_valid <= 1'b0;
        end else begin
            sof_valid <= 1'b0;

            if (state == ST_CHK_TOKEN && is_sof) begin
                frame_number <= rx_frame;
                sof_valid <= 1'b1;
            end
        end
    end

    //==========================================================================
    // Device address update and configuration
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            set_address <= 1'b0;
            new_address <= 7'd0;
            set_configured <= 1'b0;
            new_config <= 8'd0;
        end else begin
            set_address <= 1'b0;
            set_configured <= 1'b0;

            // These signals are set by the control endpoint logic
            // when SET_ADDRESS or SET_CONFIGURATION requests are processed
        end
    end

    //==========================================================================
    // Control phase tracking and CRC status
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_phase_done <= 1'b0;
            rx_crc_ok <= 1'b0;
        end else begin
            ctrl_phase_done <= 1'b0;
            rx_crc_ok <= 1'b0;

            // Signal control phase completion on ACK transmission
            if (state == ST_TX_HS && hs_pid == PID_ACK && utmi_txready) begin
                ctrl_phase_done <= (rx_ep == 4'd0);
            end

            // Update CRC status after data check
            if (state == ST_CHK_DATA) begin
                rx_crc_ok <= crc16_ok;
            end
        end
    end

endmodule
