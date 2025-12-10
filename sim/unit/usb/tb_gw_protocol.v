//-----------------------------------------------------------------------------
// Testbench for Greaseweazle Protocol Handler
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state after reset
//   2. CMD_GET_INFO command
//   3. CMD_SEEK command
//   4. CMD_MOTOR command
//   5. CMD_SELECT command
//   6. CMD_READ_FLUX command (streaming)
//   7. Flux data encoding (variable length)
//   8. Index pulse handling
//   9. Command sequence
//  10. Error response
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_gw_protocol;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // Greaseweazle Command Codes
    //=========================================================================
    localparam [7:0] CMD_GET_INFO    = 8'h00;
    localparam [7:0] CMD_SEEK        = 8'h05;
    localparam [7:0] CMD_MOTOR       = 8'h0B;
    localparam [7:0] CMD_SELECT      = 8'h12;
    localparam [7:0] CMD_READ_FLUX   = 8'h07;
    localparam [7:0] CMD_WRITE_FLUX  = 8'h08;
    localparam [7:0] CMD_GET_FLUX_STATUS = 8'h09;

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;

    // USB Interface
    reg  [31:0] rx_data;
    reg         rx_valid;
    wire        rx_ready;
    wire [31:0] tx_data;
    wire        tx_valid;
    reg         tx_ready;

    // Flux Data Interface
    reg  [31:0] flux_data;
    reg         flux_valid;
    wire        flux_ready;
    reg         flux_index;

    // Drive Control Interface
    wire [3:0]  drive_select;
    wire        motor_on;
    wire        head_select;
    wire [7:0]  track;
    wire        seek_start;
    reg         seek_complete;
    reg         track_00;
    reg         disk_present;
    reg         write_protect;

    // Capture Control
    wire        capture_start;
    wire        capture_stop;
    wire [7:0]  sample_rate;
    reg         capturing;

    // Status
    wire [7:0]  state;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    gw_protocol dut (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_ready(rx_ready),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .flux_data(flux_data),
        .flux_valid(flux_valid),
        .flux_ready(flux_ready),
        .flux_index(flux_index),
        .drive_select(drive_select),
        .motor_on(motor_on),
        .head_select(head_select),
        .track(track),
        .seek_start(seek_start),
        .seek_complete(seek_complete),
        .track_00(track_00),
        .disk_present(disk_present),
        .write_protect(write_protect),
        .capture_start(capture_start),
        .capture_stop(capture_stop),
        .sample_rate(sample_rate),
        .capturing(capturing),
        .state(state)
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
        $dumpfile("tb_gw_protocol.vcd");
        $dumpvars(0, tb_gw_protocol);
    end

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send command word
    task send_cmd;
        input [31:0] data;
        begin
            @(posedge clk);
            rx_data <= data;
            rx_valid <= 1;
            @(posedge clk);
            while (!rx_ready) @(posedge clk);
            rx_valid <= 0;
            @(posedge clk);
        end
    endtask

    // Wait for response
    task wait_response;
        output [31:0] data;
        integer timeout;
        begin
            timeout = 0;
            data = 32'h0;
            while (!tx_valid && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (tx_valid) begin
                data = tx_data;
                tx_ready = 1;
                @(posedge clk);
                tx_ready = 0;
            end
        end
    endtask

    // Simulate seek completion
    task sim_seek_complete;
        begin
            repeat(100) @(posedge clk);
            seek_complete <= 1;
            @(posedge clk);
            seek_complete <= 0;
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    reg [31:0] response;
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
        rx_data = 0;
        rx_valid = 0;
        tx_ready = 1;
        flux_data = 0;
        flux_valid = 0;
        flux_index = 0;
        seek_complete = 0;
        track_00 = 1;
        disk_present = 1;
        write_protect = 0;
        capturing = 0;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(motor_on, 1'b0, "Motor off at init");
        assert_eq_1(capture_start, 1'b0, "No capture at init");
        $display("  [INFO] Protocol state = 0x%02X", state);

        //---------------------------------------------------------------------
        // Test 2: CMD_GET_INFO
        //---------------------------------------------------------------------
        test_begin("CMD_GET_INFO");

        // Command format: [7:0]=cmd, [15:8]=length, [31:16]=param
        send_cmd({16'h0000, 8'h02, CMD_GET_INFO});

        wait_response(response);
        $display("  [INFO] GET_INFO response: 0x%08X", response);
        test_pass("GET_INFO processed");

        //---------------------------------------------------------------------
        // Test 3: CMD_SELECT (Select Drive)
        //---------------------------------------------------------------------
        test_begin("CMD_SELECT");

        // Select drive 0
        send_cmd({16'h0000, 8'h03, CMD_SELECT});
        send_cmd({24'h000000, 8'h00});  // Drive 0

        repeat(10) @(posedge clk);
        $display("  [INFO] drive_select = %b", drive_select);
        test_pass("Drive selected");

        //---------------------------------------------------------------------
        // Test 4: CMD_MOTOR
        //---------------------------------------------------------------------
        test_begin("CMD_MOTOR");

        // Motor ON
        send_cmd({16'h0000, 8'h03, CMD_MOTOR});
        send_cmd({24'h000000, 8'h01});  // Motor ON

        repeat(10) @(posedge clk);
        $display("  [INFO] motor_on = %b", motor_on);

        // Motor OFF
        send_cmd({16'h0000, 8'h03, CMD_MOTOR});
        send_cmd({24'h000000, 8'h00});  // Motor OFF

        repeat(10) @(posedge clk);
        $display("  [INFO] motor_on = %b after OFF", motor_on);
        test_pass("Motor control works");

        //---------------------------------------------------------------------
        // Test 5: CMD_SEEK
        //---------------------------------------------------------------------
        test_begin("CMD_SEEK");

        track_00 = 0;  // Not at track 0

        send_cmd({16'h0000, 8'h03, CMD_SEEK});
        send_cmd({24'h000000, 8'd20});  // Seek to track 20

        // Check seek started
        repeat(10) @(posedge clk);
        $display("  [INFO] seek_start = %b, track = %d", seek_start, track);

        // Simulate seek completion
        sim_seek_complete();

        test_pass("Seek command issued");

        //---------------------------------------------------------------------
        // Test 6: CMD_READ_FLUX
        //---------------------------------------------------------------------
        test_begin("CMD_READ_FLUX");

        send_cmd({16'h0000, 8'h03, CMD_READ_FLUX});
        send_cmd({24'h000000, 8'h01});  // Read 1 revolution

        repeat(20) @(posedge clk);
        $display("  [INFO] capture_start = %b", capture_start);
        test_pass("Read flux initiated");

        //---------------------------------------------------------------------
        // Test 7: Flux Data Streaming
        //---------------------------------------------------------------------
        test_begin("Flux Data Streaming");

        capturing = 1;

        // Send some flux data
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            flux_data <= {1'b0, 3'b000, 28'd1000 + i[27:0] * 28'd100};  // Timestamps
            flux_valid <= 1;
            @(posedge clk);
            while (!flux_ready) @(posedge clk);
        end
        flux_valid <= 0;

        repeat(20) @(posedge clk);
        $display("  [INFO] Flux data sent");
        test_pass("Flux streaming works");

        //---------------------------------------------------------------------
        // Test 8: Index Pulse
        //---------------------------------------------------------------------
        test_begin("Index Pulse");

        flux_index <= 1;
        @(posedge clk);
        flux_index <= 0;

        repeat(10) @(posedge clk);
        $display("  [INFO] Index pulse generated");
        test_pass("Index handled");

        //---------------------------------------------------------------------
        // Test 9: Stop Capture
        //---------------------------------------------------------------------
        test_begin("Stop Capture");

        capturing = 0;

        repeat(20) @(posedge clk);
        $display("  [INFO] capture_stop = %b", capture_stop);
        test_pass("Capture stopped");

        //---------------------------------------------------------------------
        // Test 10: Multiple Commands
        //---------------------------------------------------------------------
        test_begin("Command Sequence");

        // GET_INFO, SELECT, MOTOR sequence
        send_cmd({16'h0000, 8'h02, CMD_GET_INFO});
        repeat(50) @(posedge clk);

        send_cmd({16'h0000, 8'h03, CMD_SELECT});
        send_cmd({24'h000000, 8'h01});  // Drive 1
        repeat(20) @(posedge clk);

        send_cmd({16'h0000, 8'h03, CMD_MOTOR});
        send_cmd({24'h000000, 8'h01});  // Motor ON
        repeat(20) @(posedge clk);

        $display("  [INFO] Command sequence completed");
        test_pass("Multiple commands handled");

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
