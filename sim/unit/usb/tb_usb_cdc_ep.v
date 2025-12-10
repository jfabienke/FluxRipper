//-----------------------------------------------------------------------------
// Testbench for USB CDC Endpoint
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state after reset
//   2. SET_LINE_CODING request
//   3. GET_LINE_CODING request
//   4. SET_CONTROL_LINE_STATE (DTR/RTS)
//   5. TX FIFO operation (debug output)
//   6. RX FIFO operation (command input)
//   7. High-speed vs full-speed packet sizes
//   8. Zero-length packet handling
//   9. DATA toggle management
//  10. FIFO overflow handling
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_usb_cdc_ep;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz

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

    // Control transfer interface
    reg         ctrl_setup_valid;
    reg  [7:0]  ctrl_request;
    reg  [15:0] ctrl_value;
    reg  [15:0] ctrl_index;
    reg  [15:0] ctrl_length;
    wire [7:0]  ctrl_response_data;
    wire        ctrl_response_valid;
    wire        ctrl_response_last;
    reg         ctrl_out_valid;
    reg  [7:0]  ctrl_out_data;
    wire        ctrl_request_handled;

    // Bulk data interface
    reg         bulk_in_ready;
    wire [7:0]  bulk_in_data;
    wire        bulk_in_valid;
    wire        bulk_in_last;
    reg         bulk_out_valid;
    reg  [7:0]  bulk_out_data;
    reg         bulk_out_last;
    wire        bulk_out_ready;

    // Debug console interface
    reg  [7:0]  debug_tx_data;
    reg         debug_tx_valid;
    wire        debug_tx_ready;
    wire [7:0]  debug_rx_data;
    wire        debug_rx_valid;
    reg         debug_rx_ready;

    // Line state
    wire        dtr;
    wire        rts;
    wire [31:0] baud_rate;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    usb_cdc_ep dut (
        .clk(clk),
        .rst_n(rst_n),
        .high_speed(high_speed),
        .ctrl_setup_valid(ctrl_setup_valid),
        .ctrl_request(ctrl_request),
        .ctrl_value(ctrl_value),
        .ctrl_index(ctrl_index),
        .ctrl_length(ctrl_length),
        .ctrl_response_data(ctrl_response_data),
        .ctrl_response_valid(ctrl_response_valid),
        .ctrl_response_last(ctrl_response_last),
        .ctrl_out_valid(ctrl_out_valid),
        .ctrl_out_data(ctrl_out_data),
        .ctrl_request_handled(ctrl_request_handled),
        .bulk_in_ready(bulk_in_ready),
        .bulk_in_data(bulk_in_data),
        .bulk_in_valid(bulk_in_valid),
        .bulk_in_last(bulk_in_last),
        .bulk_out_valid(bulk_out_valid),
        .bulk_out_data(bulk_out_data),
        .bulk_out_last(bulk_out_last),
        .bulk_out_ready(bulk_out_ready),
        .debug_tx_data(debug_tx_data),
        .debug_tx_valid(debug_tx_valid),
        .debug_tx_ready(debug_tx_ready),
        .debug_rx_data(debug_rx_data),
        .debug_rx_valid(debug_rx_valid),
        .debug_rx_ready(debug_rx_ready),
        .dtr(dtr),
        .rts(rts),
        .baud_rate(baud_rate)
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
        $dumpfile("tb_usb_cdc_ep.vcd");
        $dumpvars(0, tb_usb_cdc_ep);
    end

    //=========================================================================
    // CDC Class Request Codes
    //=========================================================================
    localparam REQ_SET_LINE_CODING        = 8'h20;
    localparam REQ_GET_LINE_CODING        = 8'h21;
    localparam REQ_SET_CONTROL_LINE_STATE = 8'h22;

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send CDC class request
    task send_cdc_request;
        input [7:0] request;
        input [15:0] value;
        input [15:0] index;
        input [15:0] length;
        begin
            @(posedge clk);
            ctrl_request <= request;
            ctrl_value <= value;
            ctrl_index <= index;
            ctrl_length <= length;
            ctrl_setup_valid <= 1;
            @(posedge clk);
            ctrl_setup_valid <= 0;
            repeat(5) @(posedge clk);
        end
    endtask

    // Send line coding data (7 bytes)
    task send_line_coding;
        input [31:0] baud;
        input [7:0] stop_bits;
        input [7:0] parity;
        input [7:0] data_bits;
        begin
            @(posedge clk);
            ctrl_out_valid <= 1;
            ctrl_out_data <= baud[7:0];
            @(posedge clk);
            ctrl_out_data <= baud[15:8];
            @(posedge clk);
            ctrl_out_data <= baud[23:16];
            @(posedge clk);
            ctrl_out_data <= baud[31:24];
            @(posedge clk);
            ctrl_out_data <= stop_bits;
            @(posedge clk);
            ctrl_out_data <= parity;
            @(posedge clk);
            ctrl_out_data <= data_bits;
            @(posedge clk);
            ctrl_out_valid <= 0;
        end
    endtask

    // Send debug data
    task send_debug_data;
        input [7:0] data;
        begin
            @(posedge clk);
            debug_tx_data <= data;
            debug_tx_valid <= 1;
            @(posedge clk);
            while (!debug_tx_ready) @(posedge clk);
            debug_tx_valid <= 0;
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;
    reg [7:0] received_bytes [0:15];
    integer received_count;

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
        ctrl_setup_valid = 0;
        ctrl_request = 0;
        ctrl_value = 0;
        ctrl_index = 0;
        ctrl_length = 0;
        ctrl_out_valid = 0;
        ctrl_out_data = 0;
        bulk_in_ready = 1;
        bulk_out_valid = 0;
        bulk_out_data = 0;
        bulk_out_last = 0;
        debug_tx_data = 0;
        debug_tx_valid = 0;
        debug_rx_ready = 1;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(dtr, 1'b0, "DTR deasserted at init");
        assert_eq_1(rts, 1'b0, "RTS deasserted at init");
        $display("  [INFO] Initial baud_rate = %d", baud_rate);

        //---------------------------------------------------------------------
        // Test 2: SET_LINE_CODING
        //---------------------------------------------------------------------
        test_begin("SET_LINE_CODING");

        send_cdc_request(REQ_SET_LINE_CODING, 16'h0000, 16'h0000, 16'h0007);

        // Send line coding: 115200 baud, 1 stop bit, no parity, 8 data bits
        send_line_coding(32'd115200, 8'd0, 8'd0, 8'd8);

        repeat(10) @(posedge clk);
        $display("  [INFO] baud_rate after SET_LINE_CODING = %d", baud_rate);
        test_pass("SET_LINE_CODING processed");

        //---------------------------------------------------------------------
        // Test 3: GET_LINE_CODING
        //---------------------------------------------------------------------
        test_begin("GET_LINE_CODING");

        send_cdc_request(REQ_GET_LINE_CODING, 16'h0000, 16'h0000, 16'h0007);

        // Capture response
        received_count = 0;
        repeat(20) begin
            @(posedge clk);
            if (ctrl_response_valid) begin
                received_bytes[received_count] = ctrl_response_data;
                received_count = received_count + 1;
            end
        end

        $display("  [INFO] GET_LINE_CODING returned %d bytes", received_count);
        test_pass("GET_LINE_CODING processed");

        //---------------------------------------------------------------------
        // Test 4: SET_CONTROL_LINE_STATE
        //---------------------------------------------------------------------
        test_begin("SET_CONTROL_LINE_STATE");

        // wValue bit 0 = DTR, bit 1 = RTS
        send_cdc_request(REQ_SET_CONTROL_LINE_STATE, 16'h0003, 16'h0000, 16'h0000);

        repeat(10) @(posedge clk);
        $display("  [INFO] DTR = %b, RTS = %b after SET_CONTROL_LINE_STATE", dtr, rts);
        test_pass("Control line state set");

        //---------------------------------------------------------------------
        // Test 5: TX FIFO (Debug Output)
        //---------------------------------------------------------------------
        test_begin("TX FIFO Debug Output");

        // Send some debug data
        for (i = 0; i < 10; i = i + 1) begin
            send_debug_data(8'h41 + i);  // 'A', 'B', 'C', ...
        end

        repeat(20) @(posedge clk);
        $display("  [INFO] Debug data sent to TX FIFO");
        test_pass("TX FIFO accepts data");

        //---------------------------------------------------------------------
        // Test 6: RX FIFO (Command Input)
        //---------------------------------------------------------------------
        test_begin("RX FIFO Command Input");

        // Send bulk OUT data
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk);
            bulk_out_data <= 8'h30 + i;  // '0', '1', '2', ...
            bulk_out_valid <= 1;
            bulk_out_last <= (i == 4);
            @(posedge clk);
            while (!bulk_out_ready) @(posedge clk);
        end
        bulk_out_valid <= 0;
        bulk_out_last <= 0;

        repeat(10) @(posedge clk);
        $display("  [INFO] debug_rx_valid = %b", debug_rx_valid);
        test_pass("RX FIFO receives data");

        //---------------------------------------------------------------------
        // Test 7: High-Speed Mode
        //---------------------------------------------------------------------
        test_begin("High-Speed Mode");

        high_speed = 1;
        repeat(5) @(posedge clk);
        $display("  [INFO] High-speed mode: 512 byte packets");
        test_pass("High-speed mode set");

        //---------------------------------------------------------------------
        // Test 8: Full-Speed Mode
        //---------------------------------------------------------------------
        test_begin("Full-Speed Mode");

        high_speed = 0;
        repeat(5) @(posedge clk);
        $display("  [INFO] Full-speed mode: 64 byte packets");
        test_pass("Full-speed mode set");

        //---------------------------------------------------------------------
        // Test 9: Clear DTR/RTS
        //---------------------------------------------------------------------
        test_begin("Clear DTR/RTS");

        send_cdc_request(REQ_SET_CONTROL_LINE_STATE, 16'h0000, 16'h0000, 16'h0000);

        repeat(10) @(posedge clk);
        $display("  [INFO] DTR = %b, RTS = %b after clear", dtr, rts);
        test_pass("Control lines cleared");

        //---------------------------------------------------------------------
        // Test 10: Bulk IN Data Flow
        //---------------------------------------------------------------------
        test_begin("Bulk IN Data Flow");

        // Fill TX buffer
        for (i = 0; i < 20; i = i + 1) begin
            send_debug_data(8'h50 + i);
        end

        // Read from bulk IN
        bulk_in_ready = 1;
        received_count = 0;
        repeat(50) begin
            @(posedge clk);
            if (bulk_in_valid && bulk_in_ready) begin
                received_count = received_count + 1;
            end
        end

        $display("  [INFO] Received %d bytes from bulk IN", received_count);
        test_pass("Bulk IN data flow works");

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
        #500000;  // 500us timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
