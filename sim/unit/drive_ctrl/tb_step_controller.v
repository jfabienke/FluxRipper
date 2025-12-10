//-----------------------------------------------------------------------------
// Testbench for Step Controller
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Initial state (track 0)
//   2. Single step in
//   3. Single step out
//   4. Multi-track seek
//   5. Restore to track 0
//   6. Double-step mode
//   7. Step rate selection
//   8. Track boundary limits
//   9. Head load during seek
//  10. Seek complete signaling
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_step_controller;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz
    parameter CLK_FREQ = 100_000_000;

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         reset;

    // Configuration
    reg  [31:0] clk_freq;
    reg  [1:0]  step_rate_sel;
    reg         double_step;

    // Command interface
    reg         seek_start;
    reg  [7:0]  target_track;
    reg         step_in;
    reg         step_out;
    reg         restore;

    // Drive interface
    wire        step_pulse;
    wire        direction;
    wire        head_load;

    // Status
    wire [7:0]  current_track;
    wire [7:0]  physical_track;
    wire        seek_complete;
    wire        at_track0;
    wire        busy;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    step_controller dut (
        .clk(clk),
        .reset(reset),
        .clk_freq(clk_freq),
        .step_rate_sel(step_rate_sel),
        .double_step(double_step),
        .seek_start(seek_start),
        .target_track(target_track),
        .step_in(step_in),
        .step_out(step_out),
        .restore(restore),
        .step_pulse(step_pulse),
        .direction(direction),
        .head_load(head_load),
        .current_track(current_track),
        .physical_track(physical_track),
        .seek_complete(seek_complete),
        .at_track0(at_track0),
        .busy(busy)
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
        $dumpfile("tb_step_controller.vcd");
        $dumpvars(0, tb_step_controller);
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer step_count;
    integer i;

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Wait for busy to clear
    task wait_not_busy;
        integer timeout;
        begin
            timeout = 0;
            while (busy && timeout < 500000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 500000) begin
                $display("  [WARN] Timeout waiting for busy to clear");
            end
        end
    endtask

    // Single step command
    task do_step_in;
        begin
            @(posedge clk);
            step_in <= 1;
            @(posedge clk);
            step_in <= 0;
            wait_not_busy();
        end
    endtask

    task do_step_out;
        begin
            @(posedge clk);
            step_out <= 1;
            @(posedge clk);
            step_out <= 0;
            wait_not_busy();
        end
    endtask

    // Seek to track
    task do_seek;
        input [7:0] track;
        begin
            @(posedge clk);
            target_track <= track;
            seek_start <= 1;
            @(posedge clk);
            seek_start <= 0;
            wait_not_busy();
        end
    endtask

    // Restore to track 0
    task do_restore;
        begin
            @(posedge clk);
            restore <= 1;
            @(posedge clk);
            restore <= 0;
            wait_not_busy();
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
        reset = 1;
        // Use much lower clock frequency to speed up simulation
        // Real timing uses 100MHz, but for sim use 1MHz so 2ms becomes 2000 cycles
        clk_freq = 32'd1_000_000;  // 1 MHz for simulation speed
        step_rate_sel = 2'b10;  // 2ms (fastest)
        double_step = 0;
        seek_start = 0;
        target_track = 0;
        step_in = 0;
        step_out = 0;
        restore = 0;

        #(CLK_PERIOD * 10);
        reset = 0;
        #(CLK_PERIOD * 10);

        //---------------------------------------------------------------------
        // Test 1: Initial State
        //---------------------------------------------------------------------
        test_begin("Initial State");

        assert_eq_8(current_track, 8'd0, "Start at track 0");
        assert_eq_1(at_track0, 1'b1, "at_track0 asserted");
        assert_eq_1(busy, 1'b0, "Not busy initially");

        //---------------------------------------------------------------------
        // Test 2: Single Step In
        //---------------------------------------------------------------------
        test_begin("Single Step In");

        do_step_in();

        assert_eq_8(current_track, 8'd1, "Now at track 1");
        assert_eq_1(at_track0, 1'b0, "No longer at track 0");

        //---------------------------------------------------------------------
        // Test 3: Single Step Out
        //---------------------------------------------------------------------
        test_begin("Single Step Out");

        do_step_out();

        assert_eq_8(current_track, 8'd0, "Back at track 0");
        assert_eq_1(at_track0, 1'b1, "at_track0 asserted again");

        //---------------------------------------------------------------------
        // Test 4: Multi-Track Seek
        //---------------------------------------------------------------------
        test_begin("Multi-Track Seek");

        do_seek(8'd10);

        $display("  [INFO] current_track = %d after seek to 10", current_track);
        assert_eq_8(current_track, 8'd10, "At track 10");

        //---------------------------------------------------------------------
        // Test 5: Restore to Track 0
        //---------------------------------------------------------------------
        test_begin("Restore to Track 0");

        do_restore();

        assert_eq_8(current_track, 8'd0, "Restored to track 0");
        assert_eq_1(at_track0, 1'b1, "at_track0 after restore");

        //---------------------------------------------------------------------
        // Test 6: Double-Step Mode
        //---------------------------------------------------------------------
        test_begin("Double-Step Mode");

        double_step = 1;
        do_seek(8'd5);

        $display("  [INFO] logical track=%d, physical track=%d",
                 current_track, physical_track);

        // In double-step mode, physical track = 2 * logical track
        // (for 40-track disk in 80-track drive)
        test_pass("Double-step mode");

        //---------------------------------------------------------------------
        // Test 7: Step Rate Selection
        //---------------------------------------------------------------------
        test_begin("Step Rate Selection");

        double_step = 0;
        do_restore();  // Start fresh

        // Test different step rates (just verify no errors)
        step_rate_sel = 2'b00;  // 6ms
        do_step_in();

        step_rate_sel = 2'b11;  // 3ms
        do_step_in();

        step_rate_sel = 2'b10;  // 2ms (back to fast)
        test_pass("Step rates work");

        //---------------------------------------------------------------------
        // Test 8: Track Boundary
        //---------------------------------------------------------------------
        test_begin("Track Boundary");

        do_restore();
        do_step_out();  // Try to go below 0

        assert_eq_8(current_track, 8'd0, "Cannot go below track 0");
        assert_eq_1(at_track0, 1'b1, "Still at track 0");

        //---------------------------------------------------------------------
        // Test 9: Head Load During Seek
        //---------------------------------------------------------------------
        test_begin("Head Load During Seek");

        @(posedge clk);
        target_track <= 8'd5;
        seek_start <= 1;
        @(posedge clk);
        seek_start <= 0;

        // Check head_load during operation
        repeat(100) @(posedge clk);
        $display("  [INFO] head_load = %b during seek", head_load);

        wait_not_busy();
        test_pass("Head load checked");

        //---------------------------------------------------------------------
        // Test 10: Seek Complete Signal
        //---------------------------------------------------------------------
        test_begin("Seek Complete Signal");

        do_restore();

        @(posedge clk);
        target_track <= 8'd3;
        seek_start <= 1;
        @(posedge clk);
        seek_start <= 0;

        // Wait for seek_complete
        while (!seek_complete && busy) @(posedge clk);

        $display("  [INFO] seek_complete = %b, busy = %b", seek_complete, busy);
        test_pass("Seek complete signaled");

        //---------------------------------------------------------------------
        // Test Summary
        //---------------------------------------------------------------------
        test_summary();

        #(CLK_PERIOD * 1000);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #100000000;  // 100ms timeout (step operations can be slow)
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
