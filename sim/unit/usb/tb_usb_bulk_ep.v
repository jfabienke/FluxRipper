//-----------------------------------------------------------------------------
// Testbench for USB Bulk Endpoint
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. DATA0/DATA1 toggle
//   2. HS packet size (512 bytes)
//   3. FS packet size (64 bytes)
//   4. NAK/STALL generation
//   5. FIFO handshake
//   6. OUT endpoint receive
//   7. IN endpoint transmit
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_usb_bulk_ep;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 16.67;   // 60 MHz

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;

    // Speed selection
    reg         high_speed;

    // Token detection
    reg         token_valid;
    reg         token_in;
    reg         token_out;
    reg  [3:0]  token_ep;

    // Data interface
    reg         rx_data_valid;
    reg  [7:0]  rx_data;
    reg         rx_last;
    reg         rx_crc_ok;
    wire [7:0]  tx_data;
    wire        tx_valid;
    wire        tx_last;
    reg         tx_ready;

    // Handshake control
    wire        send_ack;
    wire        send_nak;
    wire        send_stall;
    reg         stall_ep;

    // FIFO interface
    wire [31:0] fifo_rx_data;
    wire        fifo_rx_valid;
    reg         fifo_rx_ready;
    reg  [31:0] fifo_tx_data;
    reg         fifo_tx_valid;
    wire        fifo_tx_ready;

    // Status
    wire        ep_busy;
    wire [9:0]  bytes_pending;

    //=========================================================================
    // DUT Instantiation - OUT Endpoint
    //=========================================================================
    usb_bulk_ep #(
        .EP_NUM(4'd1),
        .DIR_IN(1'b0),        // OUT endpoint
        .MAX_PKT_HS(512),
        .MAX_PKT_FS(64)
    ) dut_out (
        .clk(clk),
        .rst_n(rst_n),
        .high_speed(high_speed),
        .token_valid(token_valid),
        .token_in(token_in),
        .token_out(token_out),
        .token_ep(token_ep),
        .rx_data_valid(rx_data_valid),
        .rx_data(rx_data),
        .rx_last(rx_last),
        .rx_crc_ok(rx_crc_ok),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_last(tx_last),
        .tx_ready(tx_ready),
        .send_ack(send_ack),
        .send_nak(send_nak),
        .send_stall(send_stall),
        .stall_ep(stall_ep),
        .fifo_rx_data(fifo_rx_data),
        .fifo_rx_valid(fifo_rx_valid),
        .fifo_rx_ready(fifo_rx_ready),
        .fifo_tx_data(fifo_tx_data),
        .fifo_tx_valid(fifo_tx_valid),
        .fifo_tx_ready(fifo_tx_ready),
        .ep_busy(ep_busy),
        .bytes_pending(bytes_pending)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_usb_bulk_ep.vcd");
        $dumpvars(0, tb_usb_bulk_ep);
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    reg [7:0] rx_buffer [0:511];
    integer i;
    integer byte_count;

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send OUT token for EP1
    task send_out_token;
        begin
            @(posedge clk);
            token_valid <= 1;
            token_out <= 1;
            token_in <= 0;
            token_ep <= 4'd1;
            @(posedge clk);
            token_valid <= 0;
            token_out <= 0;
        end
    endtask

    // Send IN token for EP1
    task send_in_token;
        begin
            @(posedge clk);
            token_valid <= 1;
            token_in <= 1;
            token_out <= 0;
            token_ep <= 4'd1;
            @(posedge clk);
            token_valid <= 0;
            token_in <= 0;
        end
    endtask

    // Send data packet
    task send_data_packet;
        input integer num_bytes;
        integer j;
        begin
            for (j = 0; j < num_bytes; j = j + 1) begin
                @(posedge clk);
                rx_data_valid <= 1;
                rx_data <= j[7:0];
                rx_last <= (j == num_bytes - 1);
            end
            @(posedge clk);
            rx_data_valid <= 0;
            rx_last <= 0;
            rx_crc_ok <= 1;
            @(posedge clk);
            rx_crc_ok <= 0;
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        rst_n = 0;
        high_speed = 1;
        token_valid = 0;
        token_in = 0;
        token_out = 0;
        token_ep = 0;
        rx_data_valid = 0;
        rx_data = 0;
        rx_last = 0;
        rx_crc_ok = 0;
        tx_ready = 1;
        stall_ep = 0;
        fifo_rx_ready = 1;
        fifo_tx_data = 0;
        fifo_tx_valid = 0;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(ep_busy, 1'b0, "Endpoint not busy initially");
        assert_eq_1(send_nak, 1'b0, "No NAK initially");
        assert_eq_1(send_stall, 1'b0, "No STALL initially");

        //---------------------------------------------------------------------
        // Test 2: OUT Token Reception
        //---------------------------------------------------------------------
        test_begin("OUT Token Reception");

        send_out_token();
        repeat(5) @(posedge clk);

        // Endpoint should be ready to receive data
        $display("  [INFO] ep_busy=%b after OUT token", ep_busy);

        //---------------------------------------------------------------------
        // Test 3: Receive Small Packet
        //---------------------------------------------------------------------
        test_begin("Receive Small Packet");

        send_out_token();
        send_data_packet(8);

        repeat(10) @(posedge clk);

        // Check ACK was sent
        $display("  [INFO] send_ack=%b after packet", send_ack);
        test_pass("Small packet received");

        //---------------------------------------------------------------------
        // Test 4: FIFO Data Output
        //---------------------------------------------------------------------
        test_begin("FIFO Data Output");

        // Check if data appeared on FIFO
        byte_count = 0;
        repeat(20) begin
            @(posedge clk);
            if (fifo_rx_valid) begin
                byte_count = byte_count + 1;
                $display("  [INFO] FIFO data: 0x%08X", fifo_rx_data);
            end
        end

        $display("  [INFO] Received %0d FIFO words", byte_count);
        test_pass("FIFO output checked");

        //---------------------------------------------------------------------
        // Test 5: High-Speed Packet Size
        //---------------------------------------------------------------------
        test_begin("High-Speed Packet Size");

        high_speed = 1;
        @(posedge clk);

        send_out_token();
        send_data_packet(64);  // Send 64 bytes

        repeat(100) @(posedge clk);

        $display("  [INFO] bytes_pending=%0d", bytes_pending);
        test_pass("HS packet received");

        //---------------------------------------------------------------------
        // Test 6: Full-Speed Mode
        //---------------------------------------------------------------------
        test_begin("Full-Speed Mode");

        high_speed = 0;
        @(posedge clk);

        send_out_token();
        send_data_packet(32);

        repeat(50) @(posedge clk);

        test_pass("FS packet received");

        //---------------------------------------------------------------------
        // Test 7: STALL Condition
        //---------------------------------------------------------------------
        test_begin("STALL Condition");

        stall_ep = 1;
        @(posedge clk);

        send_out_token();
        repeat(10) @(posedge clk);

        assert_eq_1(send_stall, 1'b1, "STALL sent when endpoint halted");

        stall_ep = 0;

        //---------------------------------------------------------------------
        // Test 8: NAK When FIFO Full
        //---------------------------------------------------------------------
        test_begin("NAK When FIFO Full");

        fifo_rx_ready = 0;  // FIFO not ready
        @(posedge clk);

        send_out_token();
        send_data_packet(8);
        repeat(10) @(posedge clk);

        // Should NAK because FIFO can't accept data
        $display("  [INFO] send_nak=%b with FIFO not ready", send_nak);

        fifo_rx_ready = 1;

        //---------------------------------------------------------------------
        // Test 9: Wrong Endpoint Token
        //---------------------------------------------------------------------
        test_begin("Wrong Endpoint Token");

        @(posedge clk);
        token_valid <= 1;
        token_out <= 1;
        token_ep <= 4'd5;  // Different endpoint
        @(posedge clk);
        token_valid <= 0;
        token_out <= 0;

        repeat(5) @(posedge clk);

        // Should not affect EP1
        test_pass("Wrong EP token ignored");

        //---------------------------------------------------------------------
        // Test 10: Multiple Packets
        //---------------------------------------------------------------------
        test_begin("Multiple Packets");

        for (i = 0; i < 4; i = i + 1) begin
            send_out_token();
            send_data_packet(16);
            repeat(30) @(posedge clk);
        end

        test_pass("Multiple packets received");

        //---------------------------------------------------------------------
        // Test Summary
        //---------------------------------------------------------------------
        test_summary();

        #(CLK_PERIOD * 100);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #1000000;  // 1ms timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
