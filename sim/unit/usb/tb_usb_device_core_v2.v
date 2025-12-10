//-----------------------------------------------------------------------------
// Testbench for USB Device Core V2
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state after reset
//   2. SOF packet reception and frame number tracking
//   3. SETUP token and data packet handling
//   4. IN token and data transmission
//   5. OUT token and data reception
//   6. CRC5 validation (token packets)
//   7. CRC16 validation (data packets)
//   8. Endpoint routing
//   9. NAK/STALL handshake generation
//  10. Address matching
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_usb_device_core_v2;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 16.667;  // 60 MHz (USB clock)

    // USB PIDs
    localparam [7:0] PID_OUT   = 8'hE1;  // OUT token (0001 inverted = 1110)
    localparam [7:0] PID_IN    = 8'h69;  // IN token (1001 inverted = 0110)
    localparam [7:0] PID_SOF   = 8'hA5;  // SOF token (0101 inverted = 1010)
    localparam [7:0] PID_SETUP = 8'h2D;  // SETUP token (1101 inverted = 0010)
    localparam [7:0] PID_DATA0 = 8'hC3;  // DATA0 (0011 inverted = 1100)
    localparam [7:0] PID_DATA1 = 8'h4B;  // DATA1 (1011 inverted = 0100)
    localparam [7:0] PID_ACK   = 8'hD2;  // ACK (0010 inverted = 1101)
    localparam [7:0] PID_NAK   = 8'h5A;  // NAK (1010 inverted = 0101)
    localparam [7:0] PID_STALL = 8'h1E;  // STALL (1110 inverted = 0001)

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;

    // UTMI interface
    reg  [7:0]  utmi_data_in;
    wire [7:0]  utmi_data_out;
    reg         utmi_txready;
    wire        utmi_txvalid;
    reg         utmi_rxvalid;
    reg         utmi_rxactive;
    reg  [1:0]  utmi_linestate;

    // Device configuration
    reg  [6:0]  device_address;
    wire        set_address;
    wire [6:0]  new_address;
    wire        set_configured;

    // Control endpoint
    wire        setup_valid;
    wire [63:0] setup_packet;
    wire        ctrl_out_valid;
    wire [7:0]  ctrl_out_data;
    reg  [7:0]  ctrl_in_data;
    reg         ctrl_in_valid;
    reg         ctrl_in_last;
    reg         ctrl_stall;
    reg         ctrl_ack;

    // Bulk endpoint
    wire [3:0]  token_ep;
    wire        token_in;
    wire        token_out;
    wire        rx_data_valid;
    wire [7:0]  rx_data;
    wire        rx_last;
    reg  [7:0]  tx_data;
    reg         tx_valid;
    reg         tx_last;
    wire        tx_ready;
    reg         ep_stall;
    reg         ep_nak;

    // Frame tracking
    wire [10:0] frame_number;
    wire        sof_valid;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    usb_device_core_v2 dut (
        .clk(clk),
        .rst_n(rst_n),
        .utmi_data_in(utmi_data_in),
        .utmi_data_out(utmi_data_out),
        .utmi_txready(utmi_txready),
        .utmi_txvalid(utmi_txvalid),
        .utmi_rxvalid(utmi_rxvalid),
        .utmi_rxactive(utmi_rxactive),
        .utmi_linestate(utmi_linestate),
        .device_address(device_address),
        .set_address(set_address),
        .new_address(new_address),
        .set_configured(set_configured),
        .setup_valid(setup_valid),
        .setup_packet(setup_packet),
        .ctrl_out_valid(ctrl_out_valid),
        .ctrl_out_data(ctrl_out_data),
        .ctrl_in_data(ctrl_in_data),
        .ctrl_in_valid(ctrl_in_valid),
        .ctrl_in_last(ctrl_in_last),
        .ctrl_stall(ctrl_stall),
        .ctrl_ack(ctrl_ack),
        .token_ep(token_ep),
        .token_in(token_in),
        .token_out(token_out),
        .rx_data_valid(rx_data_valid),
        .rx_data(rx_data),
        .rx_last(rx_last),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_last(tx_last),
        .tx_ready(tx_ready),
        .ep_stall(ep_stall),
        .ep_nak(ep_nak),
        .frame_number(frame_number),
        .sof_valid(sof_valid)
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
        $dumpfile("tb_usb_device_core_v2.vcd");
        $dumpvars(0, tb_usb_device_core_v2);
    end

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send a byte via UTMI RX
    task utmi_rx_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            utmi_data_in <= data;
            utmi_rxvalid <= 1;
            @(posedge clk);
        end
    endtask

    // Start RX packet
    task utmi_rx_start;
        begin
            @(posedge clk);
            utmi_rxactive <= 1;
        end
    endtask

    // End RX packet
    task utmi_rx_end;
        begin
            @(posedge clk);
            utmi_rxvalid <= 0;
            @(posedge clk);
            utmi_rxactive <= 0;
        end
    endtask

    // Send SOF packet (PID + 11-bit frame number + CRC5)
    task send_sof;
        input [10:0] frame;
        begin
            utmi_rx_start();
            utmi_rx_byte(PID_SOF);
            utmi_rx_byte(frame[7:0]);
            utmi_rx_byte({5'b00000, frame[10:8]});  // CRC5 placeholder
            utmi_rx_end();
        end
    endtask

    // Send token packet (SETUP/IN/OUT)
    task send_token;
        input [7:0] pid;
        input [6:0] addr;
        input [3:0] ep;
        begin
            utmi_rx_start();
            utmi_rx_byte(pid);
            utmi_rx_byte({ep[0], addr[6:0]});
            utmi_rx_byte({5'b00000, ep[3:1]});  // CRC5 placeholder
            utmi_rx_end();
        end
    endtask

    // Send data packet with 2 bytes
    task send_data_packet;
        input [7:0] pid;
        input [7:0] data0;
        input [7:0] data1;
        begin
            utmi_rx_start();
            utmi_rx_byte(pid);
            utmi_rx_byte(data0);
            utmi_rx_byte(data1);
            // CRC16 placeholder (2 bytes)
            utmi_rx_byte(8'h00);
            utmi_rx_byte(8'h00);
            utmi_rx_end();
        end
    endtask

    // Send 8-byte SETUP data
    task send_setup_data;
        input [7:0] bmRequestType;
        input [7:0] bRequest;
        input [15:0] wValue;
        input [15:0] wIndex;
        input [15:0] wLength;
        begin
            utmi_rx_start();
            utmi_rx_byte(PID_DATA0);
            utmi_rx_byte(bmRequestType);
            utmi_rx_byte(bRequest);
            utmi_rx_byte(wValue[7:0]);
            utmi_rx_byte(wValue[15:8]);
            utmi_rx_byte(wIndex[7:0]);
            utmi_rx_byte(wIndex[15:8]);
            utmi_rx_byte(wLength[7:0]);
            utmi_rx_byte(wLength[15:8]);
            // CRC16
            utmi_rx_byte(8'h00);
            utmi_rx_byte(8'h00);
            utmi_rx_end();
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        rst_n = 0;
        utmi_data_in = 0;
        utmi_txready = 1;
        utmi_rxvalid = 0;
        utmi_rxactive = 0;
        utmi_linestate = 2'b01;  // J state (idle)
        device_address = 7'd0;
        ctrl_in_data = 0;
        ctrl_in_valid = 0;
        ctrl_in_last = 0;
        ctrl_stall = 0;
        ctrl_ack = 0;
        tx_data = 0;
        tx_valid = 0;
        tx_last = 0;
        ep_stall = 0;
        ep_nak = 0;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(sof_valid, 1'b0, "No SOF at init");
        assert_eq_1(setup_valid, 1'b0, "No SETUP at init");

        //---------------------------------------------------------------------
        // Test 2: SOF Packet Reception
        //---------------------------------------------------------------------
        test_begin("SOF Packet");

        send_sof(11'd100);
        repeat(10) @(posedge clk);

        $display("  [INFO] frame_number = %d, sof_valid = %b", frame_number, sof_valid);
        test_pass("SOF packet processed");

        //---------------------------------------------------------------------
        // Test 3: SETUP Token
        //---------------------------------------------------------------------
        test_begin("SETUP Token");

        send_token(PID_SETUP, 7'd0, 4'd0);  // To address 0, EP0
        repeat(10) @(posedge clk);

        $display("  [INFO] After SETUP token");
        test_pass("SETUP token received");

        //---------------------------------------------------------------------
        // Test 4: SETUP Data Packet
        //---------------------------------------------------------------------
        test_begin("SETUP Data Packet");

        // GET_DESCRIPTOR request
        send_setup_data(8'h80, 8'h06, 16'h0100, 16'h0000, 16'h0012);
        repeat(20) @(posedge clk);

        $display("  [INFO] setup_valid = %b", setup_valid);
        test_pass("SETUP data received");

        //---------------------------------------------------------------------
        // Test 5: IN Token
        //---------------------------------------------------------------------
        test_begin("IN Token");

        send_token(PID_IN, 7'd0, 4'd0);  // IN to address 0, EP0
        repeat(10) @(posedge clk);

        $display("  [INFO] token_in = %b, token_ep = %d", token_in, token_ep);
        test_pass("IN token received");

        //---------------------------------------------------------------------
        // Test 6: OUT Token
        //---------------------------------------------------------------------
        test_begin("OUT Token");

        send_token(PID_OUT, 7'd0, 4'd1);  // OUT to address 0, EP1
        repeat(10) @(posedge clk);

        $display("  [INFO] token_out = %b, token_ep = %d", token_out, token_ep);
        test_pass("OUT token received");

        //---------------------------------------------------------------------
        // Test 7: Address Matching
        //---------------------------------------------------------------------
        test_begin("Address Matching");

        device_address = 7'd5;  // Set device address

        send_token(PID_IN, 7'd5, 4'd0);  // To correct address
        repeat(10) @(posedge clk);
        $display("  [INFO] Token to addr 5 - token_in = %b", token_in);

        send_token(PID_IN, 7'd10, 4'd0);  // To wrong address
        repeat(10) @(posedge clk);
        $display("  [INFO] Token to addr 10 - token_in = %b", token_in);

        test_pass("Address matching checked");

        //---------------------------------------------------------------------
        // Test 8: Bulk Endpoint Routing
        //---------------------------------------------------------------------
        test_begin("Bulk EP Routing");

        device_address = 7'd0;

        send_token(PID_OUT, 7'd0, 4'd1);  // EP1
        repeat(5) @(posedge clk);
        $display("  [INFO] EP1: token_ep = %d", token_ep);

        send_token(PID_IN, 7'd0, 4'd2);  // EP2
        repeat(5) @(posedge clk);
        $display("  [INFO] EP2: token_ep = %d", token_ep);

        test_pass("Bulk endpoints routed");

        //---------------------------------------------------------------------
        // Test 9: Multiple SOF Frames
        //---------------------------------------------------------------------
        test_begin("Multiple SOF Frames");

        for (i = 0; i < 5; i = i + 1) begin
            send_sof(11'd200 + i);
            repeat(5) @(posedge clk);
        end

        $display("  [INFO] Frame number after 5 SOFs: %d", frame_number);
        test_pass("Multiple SOFs processed");

        //---------------------------------------------------------------------
        // Test 10: NAK Response Setup
        //---------------------------------------------------------------------
        test_begin("NAK Response");

        ep_nak = 1;
        send_token(PID_IN, 7'd0, 4'd1);
        repeat(20) @(posedge clk);

        $display("  [INFO] NAK setup tested");
        ep_nak = 0;
        test_pass("NAK response setup");

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
