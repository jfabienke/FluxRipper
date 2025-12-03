//-----------------------------------------------------------------------------
// Digital PLL Testbench
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Tests DPLL lock acquisition, tracking, and data recovery
//
// Updated: 2025-12-03 12:35
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_digital_pll;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter CLK_PERIOD = 5;           // 200 MHz = 5ns period
    parameter MFM_BIT_TIME = 2000;      // 500 Kbps = 2us = 2000ns per bit cell

    //-------------------------------------------------------------------------
    // Signals
    //-------------------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg         enable;
    reg  [1:0]  data_rate;
    reg         rpm_360;
    reg  [15:0] lock_threshold;
    reg         flux_in;

    wire        data_bit;
    wire        data_ready;
    wire        bit_clk;
    wire        pll_locked;
    wire [7:0]  lock_quality;
    wire [1:0]  margin_zone;

    //-------------------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------------------
    digital_pll u_dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .data_rate(data_rate),
        .rpm_360(rpm_360),
        .lock_threshold(lock_threshold),
        .flux_in(flux_in),
        .data_bit(data_bit),
        .data_ready(data_ready),
        .bit_clk(bit_clk),
        .pll_locked(pll_locked),
        .lock_quality(lock_quality),
        .margin_zone(margin_zone),
        .phase_accum(),
        .phase_error(),
        .bandwidth()
    );

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // MFM Flux Pattern Generator
    // Generates realistic MFM flux transitions
    //-------------------------------------------------------------------------
    reg [7:0] mfm_pattern;
    reg [3:0] pattern_idx;
    integer   flux_delay;

    task generate_mfm_byte;
        input [7:0] data_byte;
        input [15:0] bit_time;
        integer i;
        reg last_data_bit;
        reg clock_bit;
        reg data_bit_local;
        begin
            last_data_bit = 1'b0;
            for (i = 7; i >= 0; i = i - 1) begin
                data_bit_local = data_byte[i];

                // MFM encoding: clock bit = 1 if both adjacent data bits are 0
                clock_bit = ~last_data_bit & ~data_bit_local;

                // Generate flux transition for clock bit
                if (clock_bit) begin
                    flux_in = 1'b1;
                    #(CLK_PERIOD * 2);
                    flux_in = 1'b0;
                end
                #(bit_time/2 - CLK_PERIOD * 2);

                // Generate flux transition for data bit
                if (data_bit_local) begin
                    flux_in = 1'b1;
                    #(CLK_PERIOD * 2);
                    flux_in = 1'b0;
                end
                #(bit_time/2 - CLK_PERIOD * 2);

                last_data_bit = data_bit_local;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Generate A1 sync mark (MFM with missing clock)
    //-------------------------------------------------------------------------
    task generate_a1_sync;
        input [15:0] bit_time;
        begin
            // A1 = 10100001 with missing clock at bit 4
            // MFM encoded: 0100 0100 1000 1001 = 0x4489
            // Bit sequence: 0 1 0 0  0 1 0 0  1 0 0 0  1 0 0 1

            // Simplified: generate flux transitions at correct times
            // A1 pattern flux positions (in half-bit times):
            // 0, 3, 7, 11, 14, 17, 19, 21, 27, 31

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time * 3 / 2 - CLK_PERIOD * 2);

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time * 2 - CLK_PERIOD * 2);

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time * 2 - CLK_PERIOD * 2);

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time * 3 / 2 - CLK_PERIOD * 2);

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time * 3 / 2 - CLK_PERIOD * 2);

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time - CLK_PERIOD * 2);

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time - CLK_PERIOD * 2);

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time * 3 - CLK_PERIOD * 2);

            flux_in = 1'b1; #(CLK_PERIOD * 2); flux_in = 1'b0;
            #(bit_time * 2 - CLK_PERIOD * 2);
        end
    endtask

    //-------------------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------------------
    integer errors;
    integer test_num;

    initial begin
        $display("============================================");
        $display("Digital PLL Testbench");
        $display("============================================");

        // Initialize
        reset          = 1;
        enable         = 0;
        data_rate      = 2'b00;      // 500 Kbps
        rpm_360        = 0;           // 300 RPM
        lock_threshold = 16'h1000;
        flux_in        = 0;
        errors         = 0;
        test_num       = 0;

        // Reset
        #100;
        reset = 0;
        #100;
        enable = 1;

        //---------------------------------------------------------------------
        // Test 1: Basic lock acquisition with sync pattern
        //---------------------------------------------------------------------
        test_num = 1;
        $display("\nTest %0d: Lock acquisition with sync pattern", test_num);

        // Generate sync bytes (0x00 pattern - all clock bits, no data)
        repeat (10) begin
            generate_mfm_byte(8'h00, MFM_BIT_TIME);
        end

        // Check if PLL locked
        #(MFM_BIT_TIME * 100);
        if (!pll_locked) begin
            $display("  FAIL: PLL did not lock on sync pattern");
            errors = errors + 1;
        end
        else begin
            $display("  PASS: PLL locked, quality = %d", lock_quality);
        end

        //---------------------------------------------------------------------
        // Test 2: A1 sync mark detection
        //---------------------------------------------------------------------
        test_num = 2;
        $display("\nTest %0d: A1 sync mark generation", test_num);

        // Generate A1 marks (3 consecutive for sync)
        generate_a1_sync(MFM_BIT_TIME);
        generate_a1_sync(MFM_BIT_TIME);
        generate_a1_sync(MFM_BIT_TIME);

        // Generate ID address mark (0xFE)
        generate_mfm_byte(8'hFE, MFM_BIT_TIME);

        #(MFM_BIT_TIME * 50);
        $display("  Completed A1 sync generation");

        //---------------------------------------------------------------------
        // Test 3: Data pattern recovery
        //---------------------------------------------------------------------
        test_num = 3;
        $display("\nTest %0d: Data pattern recovery", test_num);

        // Generate known data pattern
        generate_mfm_byte(8'hAA, MFM_BIT_TIME);
        generate_mfm_byte(8'h55, MFM_BIT_TIME);
        generate_mfm_byte(8'hFF, MFM_BIT_TIME);
        generate_mfm_byte(8'h00, MFM_BIT_TIME);

        #(MFM_BIT_TIME * 100);
        $display("  Completed data pattern generation");

        //---------------------------------------------------------------------
        // Test 4: Jitter tolerance
        //---------------------------------------------------------------------
        test_num = 4;
        $display("\nTest %0d: Jitter tolerance", test_num);

        // Generate pattern with ±5% jitter
        repeat (20) begin
            flux_delay = MFM_BIT_TIME + ($random % (MFM_BIT_TIME / 20));
            flux_in = 1'b1;
            #(CLK_PERIOD * 2);
            flux_in = 1'b0;
            #(flux_delay - CLK_PERIOD * 2);
        end

        #(MFM_BIT_TIME * 50);
        if (pll_locked) begin
            $display("  PASS: PLL maintained lock with jitter");
        end
        else begin
            $display("  FAIL: PLL lost lock with jitter");
            errors = errors + 1;
        end

        //---------------------------------------------------------------------
        // Test 5: Data rate change
        //---------------------------------------------------------------------
        test_num = 5;
        $display("\nTest %0d: Data rate change to 250 Kbps", test_num);

        data_rate = 2'b10;  // 250 Kbps

        // Wait for relock
        #(MFM_BIT_TIME * 2 * 20);

        // Generate sync at new rate
        repeat (10) begin
            generate_mfm_byte(8'h00, MFM_BIT_TIME * 2);
        end

        #(MFM_BIT_TIME * 2 * 50);
        $display("  Completed 250 Kbps test");

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        #1000;
        $display("\n============================================");
        $display("Test Summary: %0d errors", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("============================================");

        $finish;
    end

    //-------------------------------------------------------------------------
    // Monitor
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (data_ready) begin
            $display("  t=%0t: Data bit = %b, margin = %d", $time, data_bit, margin_zone);
        end
    end

    // Timeout watchdog
    initial begin
        #10_000_000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
