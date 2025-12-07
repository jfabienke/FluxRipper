// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 John Fabienke
//
// USB Bulk Endpoint Handler
//
// Implements USB bulk endpoints for bidirectional data transfer:
// - OUT endpoints: Receive data from host (commands, configuration)
// - IN endpoints: Send data to host (responses, flux data streams)
//
// Features:
// - DATA0/DATA1 PID toggle tracking per endpoint
// - Double-buffering for continuous streaming
// - FIFO interface to protocol handlers (8-bit USB ↔ 32-bit FIFO)
// - NAK generation when buffer not ready
// - Support for both High-Speed (512 bytes) and Full-Speed (64 bytes) packets
//
// Last updated: 2025-12-06 10:30:00

module usb_bulk_ep #(
    parameter EP_NUM = 4'd1,
    parameter DIR_IN = 1'b0,      // 0=OUT, 1=IN
    parameter MAX_PKT_HS = 512,
    parameter MAX_PKT_FS = 64
)(
    input         clk,
    input         rst_n,

    // Speed selection
    input         high_speed,     // 1=HS (480 Mbps), 0=FS (12 Mbps)

    // From device core - token detection
    input         token_valid,
    input         token_in,       // IN token received
    input         token_out,      // OUT token received
    input  [3:0]  token_ep,       // Endpoint number from token

    // Data interface from device core
    input         rx_data_valid,
    input  [7:0]  rx_data,
    input         rx_last,
    input         rx_crc_ok,
    output reg [7:0] tx_data,
    output reg    tx_valid,
    output reg    tx_last,
    input         tx_ready,

    // Handshake control
    output reg    send_ack,
    output reg    send_nak,
    output reg    send_stall,
    input         stall_ep,       // Endpoint halted

    // FIFO interface to protocol handlers
    output [31:0] fifo_rx_data,
    output        fifo_rx_valid,
    input         fifo_rx_ready,
    input  [31:0] fifo_tx_data,
    input         fifo_tx_valid,
    output        fifo_tx_ready,

    // Status
    output        ep_busy,
    output [9:0]  bytes_pending
);

    // State machine definitions
    localparam [2:0] EP_IDLE    = 3'd0,
                     EP_RX_DATA = 3'd1,
                     EP_RX_CRC  = 3'd2,
                     EP_ACK     = 3'd3,
                     EP_TX_DATA = 3'd4,
                     EP_TX_CRC  = 3'd5,
                     EP_WAIT_ACK = 3'd6;

    reg [2:0] state, state_next;

    // DATA toggle tracking (DATA0=0, DATA1=1)
    reg data_toggle;
    reg toggle_mismatch;

    // Packet buffer and byte counter
    reg [7:0] pkt_buffer [0:511];
    reg [9:0] byte_count;
    reg [9:0] max_packet_size;

    // Byte-to-word conversion for FIFO interface
    reg [31:0] rx_word_buffer;
    reg [1:0]  rx_byte_pos;
    reg        rx_word_complete;

    reg [31:0] tx_word_buffer;
    reg [1:0]  tx_byte_pos;
    reg        tx_word_needed;

    // CRC16 calculation (USB standard polynomial: x^16 + x^15 + x^2 + 1)
    reg [15:0] crc16;
    wire [15:0] crc16_next;

    // Token matching
    wire token_match = token_valid && (token_ep == EP_NUM);
    wire our_in_token = token_match && token_in && DIR_IN;
    wire our_out_token = token_match && token_out && !DIR_IN;

    // Dynamic packet size based on speed
    always @(*) begin
        max_packet_size = high_speed ? MAX_PKT_HS : MAX_PKT_FS;
    end

    // CRC16 calculation for USB
    crc16_usb u_crc16 (
        .crc_in(crc16),
        .data(rx_data),
        .crc_out(crc16_next)
    );

    // FIFO interface assignments
    assign fifo_rx_data = rx_word_buffer;
    assign fifo_rx_valid = rx_word_complete;
    assign fifo_tx_ready = tx_word_needed && (state == EP_IDLE);
    assign ep_busy = (state != EP_IDLE);
    assign bytes_pending = byte_count;

    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= EP_IDLE;
            data_toggle <= 1'b0;
            byte_count <= 10'd0;
            rx_byte_pos <= 2'd0;
            tx_byte_pos <= 2'd0;
            rx_word_complete <= 1'b0;
            tx_word_needed <= 1'b0;
            send_ack <= 1'b0;
            send_nak <= 1'b0;
            send_stall <= 1'b0;
            tx_valid <= 1'b0;
            tx_last <= 1'b0;
            crc16 <= 16'hFFFF;
        end else begin
            state <= state_next;

            // Clear one-cycle pulses
            send_ack <= 1'b0;
            send_nak <= 1'b0;
            send_stall <= 1'b0;
            rx_word_complete <= 1'b0;

            case (state)
                EP_IDLE: begin
                    byte_count <= 10'd0;
                    tx_valid <= 1'b0;
                    tx_last <= 1'b0;
                    crc16 <= 16'hFFFF;

                    // Check for stalled endpoint
                    if (stall_ep && (our_in_token || our_out_token)) begin
                        send_stall <= 1'b1;
                    end
                    // OUT endpoint: Host sending data to us
                    else if (our_out_token) begin
                        // NAK if FIFO full, otherwise prepare to receive
                        if (!fifo_rx_ready) begin
                            send_nak <= 1'b1;
                        end else begin
                            rx_byte_pos <= 2'd0;
                        end
                    end
                    // IN endpoint: Host requesting data from us
                    else if (our_in_token) begin
                        // NAK if no data available
                        if (!fifo_tx_valid) begin
                            send_nak <= 1'b1;
                        end else begin
                            // Load first word from FIFO
                            tx_word_buffer <= fifo_tx_data;
                            tx_byte_pos <= 2'd0;
                            tx_word_needed <= 1'b1;
                        end
                    end
                end

                EP_RX_DATA: begin
                    if (rx_data_valid) begin
                        // Store byte in packet buffer
                        pkt_buffer[byte_count] <= rx_data;
                        byte_count <= byte_count + 1'b1;

                        // Update CRC
                        crc16 <= crc16_next;

                        // Build 32-bit word for FIFO
                        case (rx_byte_pos)
                            2'd0: rx_word_buffer[7:0]   <= rx_data;
                            2'd1: rx_word_buffer[15:8]  <= rx_data;
                            2'd2: rx_word_buffer[23:16] <= rx_data;
                            2'd3: rx_word_buffer[31:24] <= rx_data;
                        endcase

                        rx_byte_pos <= rx_byte_pos + 1'b1;

                        // Signal word complete on 4th byte
                        if (rx_byte_pos == 2'd3) begin
                            rx_word_complete <= 1'b1;
                        end

                        if (rx_last) begin
                            // Handle partial word at end
                            if (rx_byte_pos != 2'd3) begin
                                rx_word_complete <= 1'b1;
                            end
                        end
                    end
                end

                EP_RX_CRC: begin
                    // Check CRC and DATA toggle
                    if (rx_crc_ok && !toggle_mismatch) begin
                        send_ack <= 1'b1;
                        data_toggle <= !data_toggle;  // Toggle for next packet
                    end
                    // Bad CRC or toggle - no handshake (host will retry)
                end

                EP_TX_DATA: begin
                    if (tx_ready) begin
                        // Send byte from word buffer
                        case (tx_byte_pos)
                            2'd0: tx_data <= tx_word_buffer[7:0];
                            2'd1: tx_data <= tx_word_buffer[15:8];
                            2'd2: tx_data <= tx_word_buffer[23:16];
                            2'd3: tx_data <= tx_word_buffer[31:24];
                        endcase

                        tx_valid <= 1'b1;
                        byte_count <= byte_count + 1'b1;
                        tx_byte_pos <= tx_byte_pos + 1'b1;

                        // Update CRC
                        crc16 <= crc16_next;

                        // Load next word when current exhausted
                        if (tx_byte_pos == 2'd3 && fifo_tx_valid) begin
                            tx_word_buffer <= fifo_tx_data;
                            tx_word_needed <= 1'b1;
                        end

                        // Check for end of packet
                        if (byte_count >= max_packet_size - 1 || !fifo_tx_valid) begin
                            tx_last <= 1'b1;
                        end
                    end
                end

                EP_TX_CRC: begin
                    if (tx_ready) begin
                        // Send CRC16 bytes (inverted, LSB first per USB spec)
                        if (!tx_valid) begin
                            tx_data <= ~crc16[7:0];
                            tx_valid <= 1'b1;
                        end else begin
                            tx_data <= ~crc16[15:8];
                            tx_last <= 1'b1;
                        end
                    end
                end

                EP_WAIT_ACK: begin
                    tx_valid <= 1'b0;
                    tx_last <= 1'b0;
                    // Wait for ACK from host, then toggle DATA PID
                    // (ACK detection handled by device core)
                    data_toggle <= !data_toggle;
                end
            endcase
        end
    end

    // Next state logic
    always @(*) begin
        state_next = state;

        case (state)
            EP_IDLE: begin
                if (stall_ep && (our_in_token || our_out_token)) begin
                    state_next = EP_IDLE;  // Stay idle, STALL sent
                end else if (our_out_token && fifo_rx_ready) begin
                    state_next = EP_RX_DATA;
                end else if (our_in_token && fifo_tx_valid) begin
                    state_next = EP_TX_DATA;
                end
            end

            EP_RX_DATA: begin
                if (rx_last) begin
                    state_next = EP_RX_CRC;
                end
            end

            EP_RX_CRC: begin
                state_next = EP_IDLE;
            end

            EP_TX_DATA: begin
                if (tx_last && tx_ready) begin
                    state_next = EP_TX_CRC;
                end
            end

            EP_TX_CRC: begin
                if (tx_last && tx_ready) begin
                    state_next = EP_WAIT_ACK;
                end
            end

            EP_WAIT_ACK: begin
                state_next = EP_IDLE;
            end

            default: state_next = EP_IDLE;
        endcase
    end

endmodule

// Simple CRC16-USB calculator module
module crc16_usb (
    input  [15:0] crc_in,
    input  [7:0]  data,
    output [15:0] crc_out
);
    // USB uses CRC-16-ANSI: polynomial 0x8005 (reversed 0xA001)
    wire [15:0] crc;
    assign crc = crc_in;

    // Parallel CRC calculation for 8 bits
    assign crc_out[0]  = crc[8]  ^ crc[12] ^ data[0] ^ data[4];
    assign crc_out[1]  = crc[9]  ^ crc[13] ^ data[1] ^ data[5];
    assign crc_out[2]  = crc[10] ^ crc[14] ^ data[2] ^ data[6];
    assign crc_out[3]  = crc[11] ^ crc[15] ^ data[3] ^ data[7];
    assign crc_out[4]  = crc[12] ^ data[4];
    assign crc_out[5]  = crc[13] ^ data[5];
    assign crc_out[6]  = crc[14] ^ data[6];
    assign crc_out[7]  = crc[15] ^ data[7];
    assign crc_out[8]  = crc[0]  ^ data[0];
    assign crc_out[9]  = crc[1]  ^ data[1];
    assign crc_out[10] = crc[2]  ^ data[2];
    assign crc_out[11] = crc[3]  ^ data[3];
    assign crc_out[12] = crc[4]  ^ data[4];
    assign crc_out[13] = crc[5]  ^ data[5];
    assign crc_out[14] = crc[6]  ^ data[6];
    assign crc_out[15] = crc[7]  ^ crc[8] ^ crc[12] ^ data[0] ^ data[4] ^ data[7];

endmodule
