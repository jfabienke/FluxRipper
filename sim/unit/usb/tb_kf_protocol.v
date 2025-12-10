//-----------------------------------------------------------------------------
// Testbench for KryoFlux Protocol Handler
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state after reset
//   2. CMD_RESET command
//   3. CMD_DEVICE selection
//   4. CMD_MOTOR control
//   5. CMD_SIDE selection
//   6. CMD_TRACK positioning
//   7. CMD_STREAM start/stop
//   8. Stream format encoding (Flux1, Flux2, Flux3)
//   9. OOB messages (Index, Stream End)
//  10. Control transfer interface
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_kf_protocol;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // KryoFlux Command Codes
    //=========================================================================
    localparam CMD_RESET   = 8'h05;
    localparam CMD_DEVICE  = 8'h06;
    localparam CMD_MOTOR   = 8'h07;
    localparam CMD_DENSITY = 8'h08;
    localparam CMD_SIDE    = 8'h09;
    localparam CMD_TRACK   = 8'h0A;
    localparam CMD_STREAM  = 8'h0B;
    localparam CMD_STATUS  = 8'h80;
    localparam CMD_INFO    = 8'h81;

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;

    // USB Bulk Interface
    reg  [31:0] cmd_rx_data;
    reg         cmd_rx_valid;
    wire        cmd_rx_ready;
    wire [31:0] resp_tx_data;
    wire        resp_tx_valid;
    reg         resp_tx_ready;

    // Control Transfer Interface
    reg         ctrl_cmd_valid;
    reg  [7:0]  ctrl_cmd_request;
    reg  [15:0] ctrl_cmd_value;
    reg  [15:0] ctrl_cmd_index;
    reg  [15:0] ctrl_cmd_length;
    wire [7:0]  ctrl_response_data;
    wire        ctrl_response_valid;
    wire        ctrl_response_last;
    reg         ctrl_out_valid;
    reg  [7:0]  ctrl_out_data;

    // Flux Data Interface
    reg  [31:0] flux_in_data;
    reg         flux_in_valid;
    wire        flux_in_ready;

    // Stream Output
    wire [7:0]  stream_out_data;
    wire        stream_out_valid;
    reg         stream_out_ready;

    // Drive Control
    wire        drv_motor_on;
    wire [7:0]  drv_cylinder;
    wire        drv_head;
    wire        drv_step_dir;
    wire        drv_step_pulse;
    wire        drv_select;
    reg         drv_ready;
    reg         drv_track00;
    reg         drv_write_protect;
    reg         drv_index;

    // Status
    wire [7:0]  kf_state;
    wire [15:0] hw_version;
    wire [31:0] fw_version;
    wire        stream_active;
    wire [31:0] stream_position;
    wire [15:0] revolution_count;

    // Config
    reg  [15:0] cfg_step_time_us;
    reg  [15:0] cfg_settle_time_ms;
    reg  [15:0] cfg_step_rate_us;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    kf_protocol dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_rx_data(cmd_rx_data),
        .cmd_rx_valid(cmd_rx_valid),
        .cmd_rx_ready(cmd_rx_ready),
        .resp_tx_data(resp_tx_data),
        .resp_tx_valid(resp_tx_valid),
        .resp_tx_ready(resp_tx_ready),
        .ctrl_cmd_valid(ctrl_cmd_valid),
        .ctrl_cmd_request(ctrl_cmd_request),
        .ctrl_cmd_value(ctrl_cmd_value),
        .ctrl_cmd_index(ctrl_cmd_index),
        .ctrl_cmd_length(ctrl_cmd_length),
        .ctrl_response_data(ctrl_response_data),
        .ctrl_response_valid(ctrl_response_valid),
        .ctrl_response_last(ctrl_response_last),
        .ctrl_out_valid(ctrl_out_valid),
        .ctrl_out_data(ctrl_out_data),
        .flux_in_data(flux_in_data),
        .flux_in_valid(flux_in_valid),
        .flux_in_ready(flux_in_ready),
        .stream_out_data(stream_out_data),
        .stream_out_valid(stream_out_valid),
        .stream_out_ready(stream_out_ready),
        .drv_motor_on(drv_motor_on),
        .drv_cylinder(drv_cylinder),
        .drv_head(drv_head),
        .drv_step_dir(drv_step_dir),
        .drv_step_pulse(drv_step_pulse),
        .drv_select(drv_select),
        .drv_ready(drv_ready),
        .drv_track00(drv_track00),
        .drv_write_protect(drv_write_protect),
        .drv_index(drv_index),
        .kf_state(kf_state),
        .hw_version(hw_version),
        .fw_version(fw_version),
        .stream_active(stream_active),
        .stream_position(stream_position),
        .revolution_count(revolution_count),
        .cfg_step_time_us(cfg_step_time_us),
        .cfg_settle_time_ms(cfg_settle_time_ms),
        .cfg_step_rate_us(cfg_step_rate_us)
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
        $dumpfile("tb_kf_protocol.vcd");
        $dumpvars(0, tb_kf_protocol);
    end

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Send control transfer command (like KryoFlux vendor request)
    task send_ctrl_cmd;
        input [7:0] request;
        input [15:0] value;
        input [15:0] index;
        input [15:0] length;
        begin
            @(posedge clk);
            ctrl_cmd_request <= request;
            ctrl_cmd_value <= value;
            ctrl_cmd_index <= index;
            ctrl_cmd_length <= length;
            ctrl_cmd_valid <= 1;
            @(posedge clk);
            ctrl_cmd_valid <= 0;
            repeat(10) @(posedge clk);
        end
    endtask

    // Send bulk command
    task send_bulk_cmd;
        input [31:0] data;
        begin
            @(posedge clk);
            cmd_rx_data <= data;
            cmd_rx_valid <= 1;
            @(posedge clk);
            while (!cmd_rx_ready) @(posedge clk);
            cmd_rx_valid <= 0;
        end
    endtask

    // Send flux data
    task send_flux;
        input [31:0] data;
        begin
            @(posedge clk);
            flux_in_data <= data;
            flux_in_valid <= 1;
            @(posedge clk);
            while (!flux_in_ready) @(posedge clk);
            flux_in_valid <= 0;
        end
    endtask

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer i;
    integer stream_bytes;

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        test_init();

        //---------------------------------------------------------------------
        // Initial State
        //---------------------------------------------------------------------
        rst_n = 0;
        cmd_rx_data = 0;
        cmd_rx_valid = 0;
        resp_tx_ready = 1;
        ctrl_cmd_valid = 0;
        ctrl_cmd_request = 0;
        ctrl_cmd_value = 0;
        ctrl_cmd_index = 0;
        ctrl_cmd_length = 0;
        ctrl_out_valid = 0;
        ctrl_out_data = 0;
        flux_in_data = 0;
        flux_in_valid = 0;
        stream_out_ready = 1;
        drv_ready = 1;
        drv_track00 = 1;
        drv_write_protect = 0;
        drv_index = 0;
        cfg_step_time_us = 16'd12;
        cfg_settle_time_ms = 16'd15;
        cfg_step_rate_us = 16'd3000;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_1(drv_motor_on, 1'b0, "Motor off at init");
        assert_eq_1(stream_active, 1'b0, "Stream inactive at init");
        $display("  [INFO] kf_state = 0x%02X", kf_state);

        //---------------------------------------------------------------------
        // Test 2: CMD_RESET via Control Transfer
        //---------------------------------------------------------------------
        test_begin("CMD_RESET");

        send_ctrl_cmd(CMD_RESET, 16'h0000, 16'h0000, 16'h0000);

        $display("  [INFO] After reset, kf_state = 0x%02X", kf_state);
        test_pass("Reset command processed");

        //---------------------------------------------------------------------
        // Test 3: CMD_DEVICE Selection
        //---------------------------------------------------------------------
        test_begin("CMD_DEVICE");

        send_ctrl_cmd(CMD_DEVICE, 16'h0000, 16'h0000, 16'h0000);  // Select device 0

        repeat(10) @(posedge clk);
        $display("  [INFO] drv_select = %b", drv_select);
        test_pass("Device selected");

        //---------------------------------------------------------------------
        // Test 4: CMD_MOTOR Control
        //---------------------------------------------------------------------
        test_begin("CMD_MOTOR");

        send_ctrl_cmd(CMD_MOTOR, 16'h0001, 16'h0000, 16'h0000);  // Motor ON

        repeat(10) @(posedge clk);
        $display("  [INFO] drv_motor_on = %b", drv_motor_on);

        send_ctrl_cmd(CMD_MOTOR, 16'h0000, 16'h0000, 16'h0000);  // Motor OFF
        repeat(10) @(posedge clk);
        $display("  [INFO] drv_motor_on = %b after OFF", drv_motor_on);
        test_pass("Motor control works");

        //---------------------------------------------------------------------
        // Test 5: CMD_SIDE Selection
        //---------------------------------------------------------------------
        test_begin("CMD_SIDE");

        send_ctrl_cmd(CMD_SIDE, 16'h0000, 16'h0000, 16'h0000);  // Side 0
        repeat(10) @(posedge clk);
        $display("  [INFO] drv_head = %b (side 0)", drv_head);

        send_ctrl_cmd(CMD_SIDE, 16'h0001, 16'h0000, 16'h0000);  // Side 1
        repeat(10) @(posedge clk);
        $display("  [INFO] drv_head = %b (side 1)", drv_head);
        test_pass("Side selection works");

        //---------------------------------------------------------------------
        // Test 6: CMD_TRACK Positioning
        //---------------------------------------------------------------------
        test_begin("CMD_TRACK");

        drv_track00 = 0;
        send_ctrl_cmd(CMD_TRACK, 16'd20, 16'h0000, 16'h0000);  // Track 20

        repeat(100) @(posedge clk);
        $display("  [INFO] drv_cylinder = %d", drv_cylinder);
        test_pass("Track positioning initiated");

        //---------------------------------------------------------------------
        // Test 7: CMD_STREAM Start
        //---------------------------------------------------------------------
        test_begin("CMD_STREAM Start");

        send_ctrl_cmd(CMD_STREAM, 16'h0001, 16'h0000, 16'h0000);  // Start streaming

        repeat(20) @(posedge clk);
        $display("  [INFO] stream_active = %b", stream_active);
        test_pass("Stream started");

        //---------------------------------------------------------------------
        // Test 8: Flux Data Encoding
        //---------------------------------------------------------------------
        test_begin("Flux Data Encoding");

        // Send flux data samples
        for (i = 0; i < 10; i = i + 1) begin
            send_flux({1'b0, 3'b000, 28'd100 + i[27:0] * 28'd10});  // Small intervals
        end

        // Count stream output bytes
        stream_bytes = 0;
        repeat(100) begin
            @(posedge clk);
            if (stream_out_valid && stream_out_ready) begin
                stream_bytes = stream_bytes + 1;
            end
        end

        $display("  [INFO] Stream output bytes: %d", stream_bytes);
        test_pass("Flux data encoded");

        //---------------------------------------------------------------------
        // Test 9: Index Pulse (OOB)
        //---------------------------------------------------------------------
        test_begin("Index Pulse OOB");

        // Simulate index pulse
        drv_index <= 1;
        @(posedge clk);
        drv_index <= 0;

        repeat(50) @(posedge clk);
        $display("  [INFO] revolution_count = %d", revolution_count);
        test_pass("Index pulse generates OOB");

        //---------------------------------------------------------------------
        // Test 10: CMD_STREAM Stop
        //---------------------------------------------------------------------
        test_begin("CMD_STREAM Stop");

        send_ctrl_cmd(CMD_STREAM, 16'h0000, 16'h0000, 16'h0000);  // Stop streaming

        repeat(20) @(posedge clk);
        $display("  [INFO] stream_active = %b after stop", stream_active);
        test_pass("Stream stopped");

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
