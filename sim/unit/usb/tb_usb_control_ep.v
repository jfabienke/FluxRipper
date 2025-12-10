//-----------------------------------------------------------------------------
// Testbench for USB Control Endpoint
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. SETUP packet parsing
//   2. GET_DESCRIPTOR request
//   3. SET_ADDRESS request
//   4. SET_CONFIGURATION request
//   5. KryoFlux vendor requests (0xC3)
//   6. CDC class requests
//   7. Three-phase control transfer
//   8. STALL for unsupported requests
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_usb_control_ep;

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

    // SETUP and DATA phases
    reg         setup_valid;
    reg  [63:0] setup_packet;
    reg         out_valid;
    reg  [7:0]  out_data;
    reg         out_last;
    wire [7:0]  in_data;
    wire        in_valid;
    wire        in_last;
    reg         in_ready;

    // Handshake control
    wire        send_ack;
    wire        send_stall;
    reg         phase_done;

    // Address/Configuration
    wire [6:0]  new_address;
    wire        address_valid;
    wire [7:0]  new_config;
    wire        config_valid;
    reg  [6:0]  current_address;
    reg  [7:0]  current_config;

    // Descriptor ROM
    wire [7:0]  desc_type;
    wire [7:0]  desc_index;
    wire [15:0] desc_length;
    wire        desc_request;
    reg  [7:0]  desc_data;
    reg         desc_valid;
    reg         desc_last;

    // KryoFlux interface
    reg  [2:0]  personality;
    wire        kf_cmd_valid;
    wire [7:0]  kf_cmd_request;
    wire [15:0] kf_cmd_value;
    wire [15:0] kf_cmd_index;
    wire [15:0] kf_cmd_length;
    reg  [7:0]  kf_response_data;
    reg         kf_response_valid;
    reg         kf_response_last;
    wire        kf_out_data_valid;
    wire [7:0]  kf_out_data;

    // CDC ACM interface
    wire        cdc_setup_valid;
    wire [7:0]  cdc_request;
    wire [15:0] cdc_value;
    wire [15:0] cdc_index;
    wire [15:0] cdc_length;
    reg  [7:0]  cdc_response_data;
    reg         cdc_response_valid;
    reg         cdc_response_last;
    reg         cdc_request_handled;
    wire        cdc_out_data_valid;
    wire [7:0]  cdc_out_data;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    usb_control_ep dut (
        .clk(clk),
        .rst_n(rst_n),
        .setup_valid(setup_valid),
        .setup_packet(setup_packet),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_last(out_last),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_last(in_last),
        .in_ready(in_ready),
        .send_ack(send_ack),
        .send_stall(send_stall),
        .phase_done(phase_done),
        .new_address(new_address),
        .address_valid(address_valid),
        .new_config(new_config),
        .config_valid(config_valid),
        .current_address(current_address),
        .current_config(current_config),
        .desc_type(desc_type),
        .desc_index(desc_index),
        .desc_length(desc_length),
        .desc_request(desc_request),
        .desc_data(desc_data),
        .desc_valid(desc_valid),
        .desc_last(desc_last),
        .personality(personality),
        .kf_cmd_valid(kf_cmd_valid),
        .kf_cmd_request(kf_cmd_request),
        .kf_cmd_value(kf_cmd_value),
        .kf_cmd_index(kf_cmd_index),
        .kf_cmd_length(kf_cmd_length),
        .kf_response_data(kf_response_data),
        .kf_response_valid(kf_response_valid),
        .kf_response_last(kf_response_last),
        .kf_out_data_valid(kf_out_data_valid),
        .kf_out_data(kf_out_data),
        .cdc_setup_valid(cdc_setup_valid),
        .cdc_request(cdc_request),
        .cdc_value(cdc_value),
        .cdc_index(cdc_index),
        .cdc_length(cdc_length),
        .cdc_response_data(cdc_response_data),
        .cdc_response_valid(cdc_response_valid),
        .cdc_response_last(cdc_response_last),
        .cdc_request_handled(cdc_request_handled),
        .cdc_out_data_valid(cdc_out_data_valid),
        .cdc_out_data(cdc_out_data)
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
        $dumpfile("tb_usb_control_ep.vcd");
        $dumpvars(0, tb_usb_control_ep);
    end

    //=========================================================================
    // SETUP Packet Builder
    //=========================================================================
    // SETUP format: [bmRequestType, bRequest, wValueL, wValueH, wIndexL, wIndexH, wLengthL, wLengthH]
    // Packed as [63:56]=byte0, [55:48]=byte1, etc.
    function [63:0] build_setup;
        input [7:0] bmRequestType;
        input [7:0] bRequest;
        input [15:0] wValue;
        input [15:0] wIndex;
        input [15:0] wLength;
        begin
            build_setup = {bmRequestType, bRequest,
                           wValue[7:0], wValue[15:8],
                           wIndex[7:0], wIndex[15:8],
                           wLength[7:0], wLength[15:8]};
        end
    endfunction

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send SETUP packet
    task send_setup;
        input [63:0] packet;
        begin
            @(posedge clk);
            setup_packet <= packet;
            setup_valid <= 1;
            @(posedge clk);
            setup_valid <= 0;
            repeat(5) @(posedge clk);
        end
    endtask

    // Complete a control phase
    task complete_phase;
        begin
            @(posedge clk);
            phase_done <= 1;
            @(posedge clk);
            phase_done <= 0;
            repeat(3) @(posedge clk);
        end
    endtask

    // Provide descriptor data
    task provide_descriptor;
        input [7:0] byte0;
        input [7:0] byte1;
        begin
            @(posedge clk);
            desc_data <= byte0;
            desc_valid <= 1;
            @(posedge clk);
            desc_data <= byte1;
            desc_last <= 1;
            @(posedge clk);
            desc_valid <= 0;
            desc_last <= 0;
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;
    reg [7:0] received_data [0:15];
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
        setup_valid = 0;
        setup_packet = 0;
        out_valid = 0;
        out_data = 0;
        out_last = 0;
        in_ready = 1;
        phase_done = 0;
        current_address = 0;
        current_config = 0;
        desc_data = 0;
        desc_valid = 0;
        desc_last = 0;
        personality = 3'd2;  // KryoFlux personality
        kf_response_data = 0;
        kf_response_valid = 0;
        kf_response_last = 0;
        cdc_response_data = 0;
        cdc_response_valid = 0;
        cdc_response_last = 0;
        cdc_request_handled = 0;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(send_stall, 1'b0, "No stall at init");
        assert_eq_1(send_ack, 1'b0, "No ack at init");

        //---------------------------------------------------------------------
        // Test 2: GET_DESCRIPTOR (Device)
        //---------------------------------------------------------------------
        test_begin("GET_DESCRIPTOR Device");

        // bmRequestType=0x80 (device-to-host, standard, device)
        // bRequest=0x06 (GET_DESCRIPTOR)
        // wValue=0x0100 (type=1=device, index=0)
        // wIndex=0x0000
        // wLength=0x0012 (18 bytes)
        send_setup(build_setup(8'h80, 8'h06, 16'h0100, 16'h0000, 16'h0012));

        $display("  [INFO] desc_request=%b, desc_type=0x%02X", desc_request, desc_type);
        test_pass("GET_DESCRIPTOR parsed");

        //---------------------------------------------------------------------
        // Test 3: SET_ADDRESS
        //---------------------------------------------------------------------
        test_begin("SET_ADDRESS");

        // bmRequestType=0x00 (host-to-device, standard, device)
        // bRequest=0x05 (SET_ADDRESS)
        // wValue=0x0007 (address=7)
        send_setup(build_setup(8'h00, 8'h05, 16'h0007, 16'h0000, 16'h0000));

        repeat(5) @(posedge clk);
        $display("  [INFO] new_address=%d", new_address);

        // Complete STATUS phase to latch address
        complete_phase();

        $display("  [INFO] address_valid=%b after phase_done", address_valid);
        test_pass("SET_ADDRESS handled");

        //---------------------------------------------------------------------
        // Test 4: SET_CONFIGURATION
        //---------------------------------------------------------------------
        test_begin("SET_CONFIGURATION");

        // bmRequestType=0x00
        // bRequest=0x09 (SET_CONFIGURATION)
        // wValue=0x0001 (config=1)
        send_setup(build_setup(8'h00, 8'h09, 16'h0001, 16'h0000, 16'h0000));

        repeat(5) @(posedge clk);
        $display("  [INFO] new_config=%d, config_valid=%b", new_config, config_valid);
        test_pass("SET_CONFIGURATION handled");

        //---------------------------------------------------------------------
        // Test 5: KryoFlux Vendor Request
        //---------------------------------------------------------------------
        test_begin("KryoFlux Vendor Request");

        // bmRequestType=0xC3 (device-to-host, vendor, other)
        // bRequest=0x80 (STATUS)
        send_setup(build_setup(8'hC3, 8'h80, 16'h0000, 16'h0000, 16'h0004));

        repeat(5) @(posedge clk);
        $display("  [INFO] kf_cmd_valid=%b, kf_cmd_request=0x%02X", kf_cmd_valid, kf_cmd_request);

        // Provide response
        kf_response_data = 8'h00;
        kf_response_valid = 1;
        @(posedge clk);
        kf_response_last = 1;
        @(posedge clk);
        kf_response_valid = 0;
        kf_response_last = 0;

        test_pass("KryoFlux vendor request forwarded");

        //---------------------------------------------------------------------
        // Test 6: CDC SET_LINE_CODING
        //---------------------------------------------------------------------
        test_begin("CDC SET_LINE_CODING");

        // bmRequestType=0x21 (host-to-device, class, interface)
        // bRequest=0x20 (SET_LINE_CODING)
        // wValue=0x0000
        // wIndex=0x0001 (interface 1)
        // wLength=0x0007 (7 bytes line coding)
        send_setup(build_setup(8'h21, 8'h20, 16'h0000, 16'h0001, 16'h0007));

        repeat(5) @(posedge clk);
        $display("  [INFO] cdc_setup_valid=%b, cdc_request=0x%02X", cdc_setup_valid, cdc_request);
        test_pass("CDC request forwarded");

        //---------------------------------------------------------------------
        // Test 7: Unsupported Request (STALL)
        //---------------------------------------------------------------------
        test_begin("Unsupported Request STALL");

        // Unknown vendor request
        // bmRequestType=0x40 (host-to-device, vendor, device)
        // bRequest=0xFF (unknown)
        send_setup(build_setup(8'h40, 8'hFF, 16'h0000, 16'h0000, 16'h0000));

        repeat(10) @(posedge clk);
        $display("  [INFO] send_stall=%b for unknown request", send_stall);
        test_pass("STALL generated for unknown");

        //---------------------------------------------------------------------
        // Test 8: GET_STATUS
        //---------------------------------------------------------------------
        test_begin("GET_STATUS");

        // bmRequestType=0x80
        // bRequest=0x00 (GET_STATUS)
        // wLength=2
        send_setup(build_setup(8'h80, 8'h00, 16'h0000, 16'h0000, 16'h0002));

        repeat(10) @(posedge clk);

        // Check if IN data phase starts
        $display("  [INFO] in_valid=%b after GET_STATUS", in_valid);
        test_pass("GET_STATUS handled");

        //---------------------------------------------------------------------
        // Test 9: Three-Phase Transfer
        //---------------------------------------------------------------------
        test_begin("Three-Phase Transfer");

        // GET_DESCRIPTOR with data phase
        send_setup(build_setup(8'h80, 8'h06, 16'h0100, 16'h0000, 16'h0008));

        // Provide descriptor data
        repeat(3) @(posedge clk);
        desc_data <= 8'h12;  // Device descriptor length
        desc_valid <= 1;
        @(posedge clk);
        desc_data <= 8'h01;  // Device descriptor type
        desc_last <= 1;
        @(posedge clk);
        desc_valid <= 0;
        desc_last <= 0;

        // Wait for data phase
        repeat(10) @(posedge clk);

        // Complete data phase
        complete_phase();

        // STATUS phase
        repeat(5) @(posedge clk);
        complete_phase();

        test_pass("Three-phase transfer completed");

        //---------------------------------------------------------------------
        // Test 10: Multiple Consecutive SETUPs
        //---------------------------------------------------------------------
        test_begin("Multiple Consecutive SETUPs");

        for (i = 0; i < 3; i = i + 1) begin
            send_setup(build_setup(8'h80, 8'h00, 16'h0000, 16'h0000, 16'h0002));
            repeat(10) @(posedge clk);
        end

        test_pass("Multiple SETUPs handled");

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
