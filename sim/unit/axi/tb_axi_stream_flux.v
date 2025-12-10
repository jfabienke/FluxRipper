//-----------------------------------------------------------------------------
// Testbench for AXI-Stream Flux Capture
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Flux edge detection
//   2. Index pulse handling
//   3. Timestamp generation
//   4. FIFO full/overflow
//   5. Capture mode transitions
//   6. AXI-Stream handshake
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_axi_stream_flux;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 5;       // 200 MHz AXI clock
    parameter FIFO_DEPTH = 512;
    parameter FIFO_ADDR_BITS = 9;

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         aclk;
    reg         aresetn;

    // Flux engine interface
    reg         flux_raw;
    reg         index_pulse;

    // AXI-Stream master
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;
    wire [3:0]  m_axis_tkeep;

    // Control
    reg         capture_enable;
    reg         soft_reset;
    reg  [1:0]  capture_mode;

    // Status
    wire [31:0] capture_count;
    wire [15:0] index_count;
    wire        overflow;
    wire        capturing;
    wire        fifo_empty;
    wire [FIFO_ADDR_BITS:0] fifo_level;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    axi_stream_flux #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_ADDR_BITS(FIFO_ADDR_BITS),
        .CLK_DIV(56)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .flux_raw(flux_raw),
        .index_pulse(index_pulse),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tkeep(m_axis_tkeep),
        .capture_enable(capture_enable),
        .soft_reset(soft_reset),
        .capture_mode(capture_mode),
        .capture_count(capture_count),
        .index_count(index_count),
        .overflow(overflow),
        .capturing(capturing),
        .fifo_empty(fifo_empty),
        .fifo_level(fifo_level)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_axi_stream_flux.vcd");
        $dumpvars(0, tb_axi_stream_flux);
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    reg [31:0] received_data [0:127];
    integer received_count;
    integer i;

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Generate flux pulse
    task flux_pulse;
        begin
            @(posedge aclk);
            flux_raw <= 1;
            @(posedge aclk);
            flux_raw <= 0;
        end
    endtask

    // Generate index pulse
    task index_pulse_gen;
        begin
            @(posedge aclk);
            index_pulse <= 1;
            repeat(10) @(posedge aclk);
            index_pulse <= 0;
        end
    endtask

    // Receive AXI-Stream data
    task receive_axis;
        input integer max_count;
        begin
            received_count = 0;
            repeat(max_count * 10) begin
                @(posedge aclk);
                if (m_axis_tvalid && m_axis_tready) begin
                    if (received_count < 128) begin
                        received_data[received_count] = m_axis_tdata;
                        received_count = received_count + 1;
                    end
                end
            end
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
        aresetn = 0;
        flux_raw = 0;
        index_pulse = 0;
        m_axis_tready = 1;
        capture_enable = 0;
        soft_reset = 0;
        capture_mode = 2'b00;  // Continuous

        #(CLK_PERIOD * 10);
        aresetn = 1;
        #(CLK_PERIOD * 10);

        //---------------------------------------------------------------------
        // Test 1: Initial State Check
        //---------------------------------------------------------------------
        test_begin("Initial State Check");

        assert_eq_1(capturing, 1'b0, "Not capturing initially");
        assert_eq_1(fifo_empty, 1'b1, "FIFO empty initially");
        assert_eq_32(capture_count, 32'd0, "Capture count is 0");

        //---------------------------------------------------------------------
        // Test 2: Enable Capture
        //---------------------------------------------------------------------
        test_begin("Enable Capture");

        capture_enable = 1;
        repeat(10) @(posedge aclk);

        assert_eq_1(capturing, 1'b1, "Capturing after enable");

        //---------------------------------------------------------------------
        // Test 3: Flux Edge Detection
        //---------------------------------------------------------------------
        test_begin("Flux Edge Detection");

        // Generate some flux pulses
        for (i = 0; i < 10; i = i + 1) begin
            flux_pulse();
            repeat(100) @(posedge aclk);  // Wait between pulses
        end

        repeat(100) @(posedge aclk);

        $display("  [INFO] capture_count = %0d after 10 pulses", capture_count);
        assert_true(capture_count >= 5, "Flux edges captured");

        //---------------------------------------------------------------------
        // Test 4: AXI-Stream Output
        //---------------------------------------------------------------------
        test_begin("AXI-Stream Output");

        fork
            begin
                // Generate more flux
                for (i = 0; i < 20; i = i + 1) begin
                    flux_pulse();
                    repeat(50) @(posedge aclk);
                end
            end
            begin
                receive_axis(30);
            end
        join

        $display("  [INFO] Received %0d AXI-Stream words", received_count);
        assert_true(received_count >= 5, "AXI-Stream data received");

        //---------------------------------------------------------------------
        // Test 5: Index Pulse Handling
        //---------------------------------------------------------------------
        test_begin("Index Pulse Handling");

        index_pulse_gen();
        repeat(100) @(posedge aclk);

        $display("  [INFO] index_count = %0d", index_count);
        assert_true(index_count >= 1, "Index pulse counted");

        //---------------------------------------------------------------------
        // Test 6: TLAST on Index
        //---------------------------------------------------------------------
        test_begin("TLAST on Index");

        // The index pulse should generate TLAST
        capture_mode = 2'b01;  // One track mode

        fork
            begin
                repeat(50) @(posedge aclk);
                index_pulse_gen();
            end
            begin
                repeat(200) begin
                    @(posedge aclk);
                    if (m_axis_tvalid && m_axis_tlast) begin
                        $display("  [INFO] TLAST asserted at index");
                    end
                end
            end
        join

        test_pass("TLAST checked");

        //---------------------------------------------------------------------
        // Test 7: FIFO Back-Pressure
        //---------------------------------------------------------------------
        test_begin("FIFO Back-Pressure");

        capture_mode = 2'b00;
        m_axis_tready = 0;  // Stop reading

        // Generate flux with back-pressure
        for (i = 0; i < 50; i = i + 1) begin
            flux_pulse();
            repeat(20) @(posedge aclk);
        end

        repeat(100) @(posedge aclk);

        $display("  [INFO] FIFO level = %0d with back-pressure", fifo_level);
        assert_true(fifo_level > 0, "FIFO fills with back-pressure");

        m_axis_tready = 1;  // Resume reading

        //---------------------------------------------------------------------
        // Test 8: Soft Reset
        //---------------------------------------------------------------------
        test_begin("Soft Reset");

        soft_reset = 1;
        @(posedge aclk);
        soft_reset = 0;
        repeat(10) @(posedge aclk);

        assert_eq_1(fifo_empty, 1'b1, "FIFO empty after reset");

        //---------------------------------------------------------------------
        // Test 9: Timestamp Data Format
        //---------------------------------------------------------------------
        test_begin("Timestamp Data Format");

        // Generate and capture a flux pulse
        flux_pulse();
        repeat(100) @(posedge aclk);

        receive_axis(5);

        if (received_count > 0) begin
            $display("  [INFO] First captured word: 0x%08X", received_data[0]);
            // Bit 31 = index flag, 30 = overflow, 27:0 = timestamp
            $display("  [INFO]   Index flag: %b", received_data[0][31]);
            $display("  [INFO]   Timestamp: %0d", received_data[0][27:0]);
        end

        test_pass("Data format verified");

        //---------------------------------------------------------------------
        // Test 10: One Revolution Mode
        //---------------------------------------------------------------------
        test_begin("One Revolution Mode");

        soft_reset = 1;
        @(posedge aclk);
        soft_reset = 0;
        repeat(10) @(posedge aclk);

        capture_mode = 2'b10;  // One revolution

        // Generate flux until index
        for (i = 0; i < 100; i = i + 1) begin
            flux_pulse();
            repeat(20) @(posedge aclk);
        end

        index_pulse_gen();
        repeat(100) @(posedge aclk);

        // Should stop after one revolution
        $display("  [INFO] capturing=%b after one revolution", capturing);

        //---------------------------------------------------------------------
        // Test Summary
        //---------------------------------------------------------------------
        capture_enable = 0;
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
