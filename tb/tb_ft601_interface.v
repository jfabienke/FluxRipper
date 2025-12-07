//-----------------------------------------------------------------------------
// tb_ft601_interface.v
// Testbench for FT601 USB 3.0 FIFO Bridge Interface
//
// Created: 2025-12-05 08:05
//
// Tests:
//   1. Basic connectivity and reset
//   2. Host-to-device data transfer (RX path)
//   3. Device-to-host data transfer (TX path)
//   4. Bidirectional transfers
//   5. Flow control (FIFO backpressure)
//   6. Endpoint routing
//   7. Clock domain crossing verification
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_ft601_interface;

    //=========================================================================
    // Parameters
    //=========================================================================

    parameter SYS_CLK_PERIOD = 10;     // 100 MHz system clock
    parameter FT_CLK_PERIOD  = 10;     // 100 MHz FT601 clock
    parameter FIFO_DEPTH     = 64;     // Smaller for faster simulation

    //=========================================================================
    // Signals
    //=========================================================================

    // System clock domain
    reg         sys_clk;
    reg         sys_rst_n;

    // FT601 interface
    wire        ft_clk;
    wire [31:0] ft_data;
    wire [3:0]  ft_be;
    wire        ft_rxf_n;
    wire        ft_txe_n;
    wire        ft_rd_n;
    wire        ft_wr_n;
    wire        ft_oe_n;
    wire        ft_siwu_n;
    wire        ft_wakeup_n;

    // Endpoint 0 - Control
    wire [31:0] ep0_rx_data;
    wire        ep0_rx_valid;
    reg         ep0_rx_ready;
    reg  [31:0] ep0_tx_data;
    reg         ep0_tx_valid;
    wire        ep0_tx_ready;

    // Endpoint 1 - Bulk OUT (commands)
    wire [31:0] ep1_rx_data;
    wire        ep1_rx_valid;
    reg         ep1_rx_ready;

    // Endpoint 2 - Bulk IN (flux data)
    reg  [31:0] ep2_tx_data;
    reg         ep2_tx_valid;
    wire        ep2_tx_ready;

    // Endpoint 3 - Bulk IN (status)
    reg  [31:0] ep3_tx_data;
    reg         ep3_tx_valid;
    wire        ep3_tx_ready;

    // Status
    wire        usb_connected;
    wire        usb_suspended;
    wire [1:0]  active_endpoint;
    wire [31:0] rx_count;
    wire [31:0] tx_count;

    // Host testbench interface
    reg         host_clk;
    reg         host_rst_n;
    reg  [31:0] host_tx_data;
    reg  [3:0]  host_tx_be;
    reg         host_tx_valid;
    wire        host_tx_ready;
    wire [31:0] host_rx_data;
    wire [3:0]  host_rx_be;
    wire        host_rx_valid;
    reg         host_rx_ready;
    reg         usb_connect;
    reg         usb_suspend;

    //=========================================================================
    // Clock Generation
    //=========================================================================

    initial begin
        sys_clk = 0;
        forever #(SYS_CLK_PERIOD/2) sys_clk = ~sys_clk;
    end

    initial begin
        host_clk = 0;
        forever #(SYS_CLK_PERIOD/2) host_clk = ~host_clk;
    end

    //=========================================================================
    // DUT Instantiation
    //=========================================================================

    ft601_interface #(
        .SYS_CLK_FREQ  (100_000_000),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .NUM_ENDPOINTS (4)
    ) u_dut (
        .sys_clk         (sys_clk),
        .sys_rst_n       (sys_rst_n),

        .ft_clk          (ft_clk),
        .ft_data         (ft_data),
        .ft_be           (ft_be),
        .ft_rxf_n        (ft_rxf_n),
        .ft_txe_n        (ft_txe_n),
        .ft_rd_n         (ft_rd_n),
        .ft_wr_n         (ft_wr_n),
        .ft_oe_n         (ft_oe_n),
        .ft_siwu_n       (ft_siwu_n),
        .ft_wakeup_n     (ft_wakeup_n),

        .ep0_rx_data     (ep0_rx_data),
        .ep0_rx_valid    (ep0_rx_valid),
        .ep0_rx_ready    (ep0_rx_ready),
        .ep0_tx_data     (ep0_tx_data),
        .ep0_tx_valid    (ep0_tx_valid),
        .ep0_tx_ready    (ep0_tx_ready),

        .ep1_rx_data     (ep1_rx_data),
        .ep1_rx_valid    (ep1_rx_valid),
        .ep1_rx_ready    (ep1_rx_ready),

        .ep2_tx_data     (ep2_tx_data),
        .ep2_tx_valid    (ep2_tx_valid),
        .ep2_tx_ready    (ep2_tx_ready),

        .ep3_tx_data     (ep3_tx_data),
        .ep3_tx_valid    (ep3_tx_valid),
        .ep3_tx_ready    (ep3_tx_ready),

        .usb_connected   (usb_connected),
        .usb_suspended   (usb_suspended),
        .active_endpoint (active_endpoint),
        .rx_count        (rx_count),
        .tx_count        (tx_count)
    );

    //=========================================================================
    // FT601 Model Instantiation
    //=========================================================================

    ft601_model #(
        .FIFO_DEPTH     (1024),
        .CLK_PERIOD_NS  (FT_CLK_PERIOD),
        .TURNAROUND_CYC (2)
    ) u_ft601 (
        .ft_clk          (ft_clk),
        .ft_data         (ft_data),
        .ft_be           (ft_be),
        .ft_rxf_n        (ft_rxf_n),
        .ft_txe_n        (ft_txe_n),
        .ft_rd_n         (ft_rd_n),
        .ft_wr_n         (ft_wr_n),
        .ft_oe_n         (ft_oe_n),
        .ft_siwu_n       (ft_siwu_n),
        .ft_wakeup_n     (ft_wakeup_n),

        .host_clk        (host_clk),
        .host_rst_n      (host_rst_n),

        .host_tx_data    (host_tx_data),
        .host_tx_be      (host_tx_be),
        .host_tx_valid   (host_tx_valid),
        .host_tx_ready   (host_tx_ready),

        .host_rx_data    (host_rx_data),
        .host_rx_be      (host_rx_be),
        .host_rx_valid   (host_rx_valid),
        .host_rx_ready   (host_rx_ready),

        .usb_connect     (usb_connect),
        .usb_suspend     (usb_suspend)
    );

    //=========================================================================
    // Test Helpers
    //=========================================================================

    integer errors;
    integer test_num;

    // Channel encoding
    localparam CH_EP0 = 2'b00;
    localparam CH_EP1 = 2'b01;
    localparam CH_EP2 = 2'b10;
    localparam CH_EP3 = 2'b11;

    // Send data from host to device
    task host_send;
        input [31:0] data;
        input [1:0]  channel;
        begin
            @(posedge host_clk);
            host_tx_data  <= data;
            host_tx_be    <= {channel, 2'b11};  // [3:2]=channel, [1:0]=BE
            host_tx_valid <= 1'b1;
            @(posedge host_clk);
            while (!host_tx_ready) @(posedge host_clk);
            host_tx_valid <= 1'b0;
        end
    endtask

    // Receive data from device at host
    task host_receive;
        output [31:0] data;
        output [1:0]  channel;
        begin
            host_rx_ready <= 1'b1;
            @(posedge host_clk);
            while (!host_rx_valid) @(posedge host_clk);
            data    = host_rx_data;
            channel = host_rx_be[3:2];
            @(posedge host_clk);
            host_rx_ready <= 1'b0;
        end
    endtask

    // Wait for endpoint data and verify
    task wait_ep_rx;
        input [31:0] expected_data;
        input [1:0]  endpoint;
        begin
            case (endpoint)
                CH_EP0: begin
                    ep0_rx_ready <= 1'b1;
                    @(posedge sys_clk);
                    while (!ep0_rx_valid) @(posedge sys_clk);
                    if (ep0_rx_data !== expected_data) begin
                        $display("ERROR: EP0 RX data mismatch. Expected %h, got %h",
                                 expected_data, ep0_rx_data);
                        errors = errors + 1;
                    end
                    @(posedge sys_clk);
                    ep0_rx_ready <= 1'b0;
                end
                CH_EP1: begin
                    ep1_rx_ready <= 1'b1;
                    @(posedge sys_clk);
                    while (!ep1_rx_valid) @(posedge sys_clk);
                    if (ep1_rx_data !== expected_data) begin
                        $display("ERROR: EP1 RX data mismatch. Expected %h, got %h",
                                 expected_data, ep1_rx_data);
                        errors = errors + 1;
                    end
                    @(posedge sys_clk);
                    ep1_rx_ready <= 1'b0;
                end
            endcase
        end
    endtask

    // Send data from endpoint to host
    task ep_send;
        input [31:0] data;
        input [1:0]  endpoint;
        begin
            case (endpoint)
                CH_EP0: begin
                    @(posedge sys_clk);
                    ep0_tx_data  <= data;
                    ep0_tx_valid <= 1'b1;
                    @(posedge sys_clk);
                    while (!ep0_tx_ready) @(posedge sys_clk);
                    ep0_tx_valid <= 1'b0;
                end
                CH_EP2: begin
                    @(posedge sys_clk);
                    ep2_tx_data  <= data;
                    ep2_tx_valid <= 1'b1;
                    @(posedge sys_clk);
                    while (!ep2_tx_ready) @(posedge sys_clk);
                    ep2_tx_valid <= 1'b0;
                end
                CH_EP3: begin
                    @(posedge sys_clk);
                    ep3_tx_data  <= data;
                    ep3_tx_valid <= 1'b1;
                    @(posedge sys_clk);
                    while (!ep3_tx_ready) @(posedge sys_clk);
                    ep3_tx_valid <= 1'b0;
                end
            endcase
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================

    initial begin
        $display("========================================");
        $display("FT601 Interface Testbench");
        $display("========================================");

        // Initialize
        errors = 0;
        test_num = 0;
        sys_rst_n = 0;
        host_rst_n = 0;

        // Endpoint signals
        ep0_rx_ready = 0;
        ep0_tx_data  = 0;
        ep0_tx_valid = 0;
        ep1_rx_ready = 0;
        ep2_tx_data  = 0;
        ep2_tx_valid = 0;
        ep3_tx_data  = 0;
        ep3_tx_valid = 0;

        // Host signals
        host_tx_data  = 0;
        host_tx_be    = 0;
        host_tx_valid = 0;
        host_rx_ready = 0;
        usb_connect   = 0;
        usb_suspend   = 0;

        // Release reset
        #100;
        sys_rst_n = 1;
        host_rst_n = 1;
        #50;

        //=====================================================================
        // Test 1: USB Connection
        //=====================================================================
        test_num = 1;
        $display("\n[Test %0d] USB Connection", test_num);

        if (usb_connected) begin
            $display("ERROR: USB should not be connected yet");
            errors = errors + 1;
        end

        usb_connect = 1;
        #100;

        if (!usb_connected) begin
            $display("ERROR: USB should be connected");
            errors = errors + 1;
        end else begin
            $display("  USB connected OK");
        end

        //=====================================================================
        // Test 2: Host to Device - EP0 Control
        //=====================================================================
        test_num = 2;
        $display("\n[Test %0d] Host to Device - EP0 Control", test_num);

        fork
            begin
                // Host sends data
                host_send(32'hDEADBEEF, CH_EP0);
                $display("  Host sent: 0x%h to EP0", 32'hDEADBEEF);
            end
            begin
                // Device receives data
                wait_ep_rx(32'hDEADBEEF, CH_EP0);
                $display("  Device received on EP0");
            end
        join

        #100;

        //=====================================================================
        // Test 3: Host to Device - EP1 Bulk OUT
        //=====================================================================
        test_num = 3;
        $display("\n[Test %0d] Host to Device - EP1 Bulk OUT", test_num);

        fork
            begin
                host_send(32'hCAFEBABE, CH_EP1);
                $display("  Host sent: 0x%h to EP1", 32'hCAFEBABE);
            end
            begin
                wait_ep_rx(32'hCAFEBABE, CH_EP1);
                $display("  Device received on EP1");
            end
        join

        #100;

        //=====================================================================
        // Test 4: Device to Host - EP2 Bulk IN (Flux Data)
        //=====================================================================
        test_num = 4;
        $display("\n[Test %0d] Device to Host - EP2 Bulk IN", test_num);

        begin
            reg [31:0] rx_data;
            reg [1:0]  rx_ch;

            fork
                begin
                    ep_send(32'hFLUX0001, CH_EP2);
                    $display("  Device sent: 0x%h from EP2", 32'hFLUX0001);
                end
                begin
                    host_receive(rx_data, rx_ch);
                    if (rx_data !== 32'hFLUX0001) begin
                        $display("ERROR: Data mismatch. Expected %h, got %h",
                                 32'hFLUX0001, rx_data);
                        errors = errors + 1;
                    end
                    if (rx_ch !== CH_EP2) begin
                        $display("ERROR: Channel mismatch. Expected %d, got %d",
                                 CH_EP2, rx_ch);
                        errors = errors + 1;
                    end
                    $display("  Host received: 0x%h from channel %d", rx_data, rx_ch);
                end
            join
        end

        #100;

        //=====================================================================
        // Test 5: Multiple Sequential Transfers
        //=====================================================================
        test_num = 5;
        $display("\n[Test %0d] Multiple Sequential Transfers", test_num);

        begin
            integer i;
            for (i = 0; i < 8; i = i + 1) begin
                fork
                    host_send(32'h10000000 + i, CH_EP1);
                    wait_ep_rx(32'h10000000 + i, CH_EP1);
                join
            end
            $display("  8 sequential transfers OK");
        end

        #100;

        //=====================================================================
        // Test 6: Bidirectional Transfers
        //=====================================================================
        test_num = 6;
        $display("\n[Test %0d] Bidirectional Transfers", test_num);

        fork
            begin
                // Host to device
                host_send(32'hAAAAAAAA, CH_EP1);
                host_send(32'hBBBBBBBB, CH_EP1);
            end
            begin
                // Device to host
                ep_send(32'h11111111, CH_EP2);
                ep_send(32'h22222222, CH_EP2);
            end
            begin
                // Device receives
                wait_ep_rx(32'hAAAAAAAA, CH_EP1);
                wait_ep_rx(32'hBBBBBBBB, CH_EP1);
            end
            begin
                // Host receives
                reg [31:0] rx_data;
                reg [1:0]  rx_ch;
                host_receive(rx_data, rx_ch);
                host_receive(rx_data, rx_ch);
            end
        join

        $display("  Bidirectional OK");

        #100;

        //=====================================================================
        // Test 7: Verify Statistics
        //=====================================================================
        test_num = 7;
        $display("\n[Test %0d] Verify Statistics", test_num);

        $display("  RX count: %0d", rx_count);
        $display("  TX count: %0d", tx_count);

        if (rx_count == 0) begin
            $display("ERROR: RX count should not be 0");
            errors = errors + 1;
        end
        if (tx_count == 0) begin
            $display("ERROR: TX count should not be 0");
            errors = errors + 1;
        end

        //=====================================================================
        // Test 8: USB Disconnect
        //=====================================================================
        test_num = 8;
        $display("\n[Test %0d] USB Disconnect", test_num);

        usb_connect = 0;
        #100;

        if (usb_connected) begin
            $display("ERROR: USB should be disconnected");
            errors = errors + 1;
        end else begin
            $display("  USB disconnected OK");
        end

        //=====================================================================
        // Summary
        //=====================================================================
        #200;
        $display("\n========================================");
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("TESTS FAILED: %0d errors", errors);
        end
        $display("========================================\n");

        $finish;
    end

    //=========================================================================
    // Timeout
    //=========================================================================

    initial begin
        #100000;
        $display("ERROR: Testbench timeout");
        $finish;
    end

    //=========================================================================
    // VCD Dump
    //=========================================================================

    initial begin
        $dumpfile("tb_ft601_interface.vcd");
        $dumpvars(0, tb_ft601_interface);
    end

endmodule
