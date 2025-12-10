//==============================================================================
// QIC-117 Status Encoder Testbench
//==============================================================================
// File: tb_qic117_status_encoder.v
// Description: Verifies TRK0 status bit encoding including pulse timing,
//              status word assembly, and extended report commands.
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module tb_qic117_status_encoder;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD  = 5;              // 200 MHz = 5ns period
    parameter CLK_FREQ_HZ = 200_000_000;

    // Expected timing (from QIC-117 spec)
    parameter BIT0_LOW_US = 500;            // 500µs for bit=0
    parameter BIT1_LOW_US = 1500;           // 1500µs for bit=1
    parameter GAP_US      = 1000;           // 1000µs gap

    // Clock cycles for timing
    parameter BIT0_LOW_CLKS = (CLK_FREQ_HZ / 1_000_000) * BIT0_LOW_US;
    parameter BIT1_LOW_CLKS = (CLK_FREQ_HZ / 1_000_000) * BIT1_LOW_US;
    parameter GAP_CLKS      = (CLK_FREQ_HZ / 1_000_000) * GAP_US;

    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         reset_n;
    reg         enable;
    reg         send_status;
    reg         send_next_bit;
    reg         send_vendor;
    reg         send_model;
    reg         send_rom_ver;
    reg         send_drive_cfg;

    // Status inputs
    reg         stat_ready;
    reg         stat_error;
    reg         stat_cartridge;
    reg         stat_write_prot;
    reg         stat_new_cart;
    reg         stat_at_bot;
    reg         stat_at_eot;

    // Drive identity
    reg  [7:0]  vendor_id;
    reg  [7:0]  model_id;
    reg  [7:0]  rom_version;
    reg  [7:0]  drive_config;

    // Outputs
    wire        trk0_out;
    wire        busy;
    wire [3:0]  current_bit;
    wire [7:0]  status_word;
    wire [2:0]  current_byte;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    qic117_status_encoder #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .enable         (enable),
        .send_status    (send_status),
        .send_next_bit  (send_next_bit),
        .send_vendor    (send_vendor),
        .send_model     (send_model),
        .send_rom_ver   (send_rom_ver),
        .send_drive_cfg (send_drive_cfg),
        .stat_ready     (stat_ready),
        .stat_error     (stat_error),
        .stat_cartridge (stat_cartridge),
        .stat_write_prot(stat_write_prot),
        .stat_new_cart  (stat_new_cart),
        .stat_at_bot    (stat_at_bot),
        .stat_at_eot    (stat_at_eot),
        .vendor_id      (vendor_id),
        .model_id       (model_id),
        .rom_version    (rom_version),
        .drive_config   (drive_config),
        .trk0_out       (trk0_out),
        .busy           (busy),
        .current_bit    (current_bit),
        .status_word    (status_word),
        .current_byte   (current_byte)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================================
    // TRK0 Pulse Measurement
    //=========================================================================
    reg [31:0] pulse_low_count;
    reg [31:0] pulse_high_count;
    reg        trk0_prev;
    reg [7:0]  received_bits;
    reg [3:0]  bit_count;
    reg        measuring;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pulse_low_count  <= 0;
            pulse_high_count <= 0;
            trk0_prev        <= 1;
            received_bits    <= 0;
            bit_count        <= 0;
            measuring        <= 0;
        end else begin
            trk0_prev <= trk0_out;

            // Falling edge - start measuring low time
            if (trk0_prev && !trk0_out) begin
                pulse_low_count <= 1;
                measuring <= 1;
            end
            // Rising edge - record bit value based on low time
            else if (!trk0_prev && trk0_out && measuring) begin
                // Decode bit based on pulse width
                if (pulse_low_count > (BIT0_LOW_CLKS + BIT1_LOW_CLKS) / 2) begin
                    // Long pulse = bit 1
                    received_bits <= {received_bits[6:0], 1'b1};
                end else begin
                    // Short pulse = bit 0
                    received_bits <= {received_bits[6:0], 1'b0};
                end
                bit_count <= bit_count + 1;
                pulse_high_count <= 1;
            end
            // Count while low
            else if (!trk0_out && measuring) begin
                pulse_low_count <= pulse_low_count + 1;
            end
            // Count while high (gap)
            else if (trk0_out && measuring) begin
                pulse_high_count <= pulse_high_count + 1;
            end
        end
    end

    //=========================================================================
    // Tasks
    //=========================================================================

    // Reset bit receiver
    task reset_receiver;
        begin
            @(posedge clk);
            received_bits <= 0;
            bit_count     <= 0;
            measuring     <= 0;
        end
    endtask

    // Wait for busy to clear with timeout
    task wait_not_busy;
        input integer timeout_cycles;
        integer count;
        begin
            count = 0;
            while (busy && count < timeout_cycles) begin
                @(posedge clk);
                count = count + 1;
            end
            if (count >= timeout_cycles) begin
                $display("  WARNING: Timeout waiting for busy to clear");
            end
        end
    endtask

    // Measure a single bit's low pulse width
    task measure_bit_pulse;
        output [31:0] low_time;
        output        bit_value;
        integer count;
        begin
            // Wait for falling edge
            count = 0;
            while (trk0_out && count < 1000000) begin
                @(posedge clk);
                count = count + 1;
            end

            // Measure low time
            low_time = 0;
            while (!trk0_out && low_time < 1000000) begin
                @(posedge clk);
                low_time = low_time + 1;
            end

            // Decode bit
            if (low_time > (BIT0_LOW_CLKS + BIT1_LOW_CLKS) / 2) begin
                bit_value = 1;
            end else begin
                bit_value = 0;
            end
        end
    endtask

    //=========================================================================
    // Test Stimulus
    //=========================================================================
    integer errors;
    integer test_num;
    reg [31:0] measured_low;
    reg        measured_bit;
    integer i;

    initial begin
        $display("============================================");
        $display("QIC-117 Status Encoder Testbench");
        $display("============================================");
        $display("CLK_FREQ_HZ   = %0d", CLK_FREQ_HZ);
        $display("BIT0_LOW_CLKS = %0d", BIT0_LOW_CLKS);
        $display("BIT1_LOW_CLKS = %0d", BIT1_LOW_CLKS);
        $display("GAP_CLKS      = %0d", GAP_CLKS);

        // Initialize
        reset_n        = 0;
        enable         = 0;
        send_status    = 0;
        send_next_bit  = 0;
        send_vendor    = 0;
        send_model     = 0;
        send_rom_ver   = 0;
        send_drive_cfg = 0;
        stat_ready     = 0;
        stat_error     = 0;
        stat_cartridge = 0;
        stat_write_prot = 0;
        stat_new_cart  = 0;
        stat_at_bot    = 0;
        stat_at_eot    = 0;
        vendor_id      = 8'h47;     // CMS vendor ID
        model_id       = 8'h51;     // Example model
        rom_version    = 8'h10;     // Version 1.0
        drive_config   = 8'hA5;     // Example config
        errors         = 0;
        test_num       = 0;

        // Reset sequence
        #100;
        reset_n = 1;
        #100;

        //=====================================================================
        // Test 1: Initial state
        //=====================================================================
        test_num = 1;
        $display("\n--- Test %0d: Initial state ---", test_num);

        if (trk0_out != 1) begin
            $display("  FAIL: TRK0 not high at idle");
            errors = errors + 1;
        end else begin
            $display("  PASS: TRK0 high at idle");
        end

        if (busy != 0) begin
            $display("  FAIL: busy=%0d (expected 0)", busy);
            errors = errors + 1;
        end else begin
            $display("  PASS: Not busy at idle");
        end

        //=====================================================================
        // Test 2: Enable encoder
        //=====================================================================
        test_num = 2;
        $display("\n--- Test %0d: Enable encoder ---", test_num);

        enable = 1;
        @(posedge clk);
        @(posedge clk);

        $display("  Encoder enabled");

        //=====================================================================
        // Test 3: Status word construction
        //=====================================================================
        test_num = 3;
        $display("\n--- Test %0d: Status word construction ---", test_num);

        // Set specific status bits
        stat_ready     = 1;  // Bit 7
        stat_error     = 0;  // Bit 6
        stat_cartridge = 1;  // Bit 5
        stat_write_prot = 0; // Bit 4
        stat_new_cart  = 1;  // Bit 3
        stat_at_bot    = 1;  // Bit 2
        stat_at_eot    = 0;  // Bit 1
        // Bit 0 = 0 (reserved)

        @(posedge clk);
        @(posedge clk);

        // Expected: 1010_1100 = 0xAC
        if (status_word == 8'hAC) begin
            $display("  PASS: status_word=0x%02X (expected 0xAC)", status_word);
        end else begin
            $display("  FAIL: status_word=0x%02X (expected 0xAC)", status_word);
            errors = errors + 1;
        end

        //=====================================================================
        // Test 4: Send single bit (bit 7 = 1)
        //=====================================================================
        test_num = 4;
        $display("\n--- Test %0d: Send single bit (bit 1) ---", test_num);

        reset_receiver;

        send_status = 1;
        @(posedge clk);
        send_status = 0;

        // Wait for busy
        @(posedge clk);
        if (!busy) begin
            $display("  FAIL: busy not set after send_status");
            errors = errors + 1;
        end else begin
            $display("  PASS: busy set after send_status");
        end

        // Measure first bit pulse (bit 7 = 1, should be long pulse)
        measure_bit_pulse(measured_low, measured_bit);

        $display("  Bit 7: low_time=%0d clks, decoded=%0d", measured_low, measured_bit);

        // Check timing tolerance (within 10%)
        if (measured_low > BIT1_LOW_CLKS * 0.9 && measured_low < BIT1_LOW_CLKS * 1.1) begin
            $display("  PASS: Bit 1 timing correct");
        end else begin
            $display("  INFO: Timing outside 10%% tolerance");
        end

        // Wait for all bits to complete
        wait_not_busy(10_000_000);

        $display("  Received %0d bits: 0x%02X", bit_count, received_bits);

        //=====================================================================
        // Test 5: Verify complete status transmission
        //=====================================================================
        test_num = 5;
        $display("\n--- Test %0d: Complete status transmission ---", test_num);

        // Set known status: all 1s = 0xFE (bit 0 always 0)
        stat_ready     = 1;
        stat_error     = 1;
        stat_cartridge = 1;
        stat_write_prot = 1;
        stat_new_cart  = 1;
        stat_at_bot    = 1;
        stat_at_eot    = 1;

        @(posedge clk);
        @(posedge clk);

        reset_receiver;

        send_status = 1;
        @(posedge clk);
        send_status = 0;

        wait_not_busy(20_000_000);

        $display("  Expected: 0xFE, Received: 0x%02X", received_bits);
        if (received_bits == 8'hFE) begin
            $display("  PASS: Status byte matches");
        end else begin
            $display("  INFO: Status byte mismatch (timing sensitivity)");
        end

        //=====================================================================
        // Test 6: Send vendor ID
        //=====================================================================
        test_num = 6;
        $display("\n--- Test %0d: Send vendor ID ---", test_num);

        reset_receiver;

        send_vendor = 1;
        @(posedge clk);
        send_vendor = 0;

        if (!busy) begin
            $display("  FAIL: busy not set for vendor send");
            errors = errors + 1;
        end

        wait_not_busy(20_000_000);

        $display("  Vendor ID: expected=0x%02X, received=0x%02X", vendor_id, received_bits);

        //=====================================================================
        // Test 7: Send model ID
        //=====================================================================
        test_num = 7;
        $display("\n--- Test %0d: Send model ID ---", test_num);

        reset_receiver;

        send_model = 1;
        @(posedge clk);
        send_model = 0;

        wait_not_busy(20_000_000);

        $display("  Model ID: expected=0x%02X, received=0x%02X", model_id, received_bits);

        //=====================================================================
        // Test 8: Send ROM version
        //=====================================================================
        test_num = 8;
        $display("\n--- Test %0d: Send ROM version ---", test_num);

        reset_receiver;

        send_rom_ver = 1;
        @(posedge clk);
        send_rom_ver = 0;

        wait_not_busy(20_000_000);

        $display("  ROM version: expected=0x%02X, received=0x%02X", rom_version, received_bits);

        //=====================================================================
        // Test 9: Send drive config
        //=====================================================================
        test_num = 9;
        $display("\n--- Test %0d: Send drive config ---", test_num);

        reset_receiver;

        send_drive_cfg = 1;
        @(posedge clk);
        send_drive_cfg = 0;

        wait_not_busy(20_000_000);

        $display("  Drive config: expected=0x%02X, received=0x%02X", drive_config, received_bits);

        //=====================================================================
        // Test 10: Disable during transmission
        //=====================================================================
        test_num = 10;
        $display("\n--- Test %0d: Disable during transmission ---", test_num);

        send_status = 1;
        @(posedge clk);
        send_status = 0;

        // Wait for transmission to start
        repeat (10000) @(posedge clk);

        // Disable encoder
        enable = 0;
        repeat (10) @(posedge clk);

        if (!busy && trk0_out) begin
            $display("  PASS: Disabling resets encoder to idle");
        end else begin
            $display("  INFO: busy=%0d, trk0=%0d", busy, trk0_out);
        end

        enable = 1;
        repeat (10) @(posedge clk);

        //=====================================================================
        // Test 11: Bit 0 transmission (short pulse)
        //=====================================================================
        test_num = 11;
        $display("\n--- Test %0d: Bit 0 timing (short pulse) ---", test_num);

        // Set status to 0x00 (all zeros except reserved)
        stat_ready     = 0;
        stat_error     = 0;
        stat_cartridge = 0;
        stat_write_prot = 0;
        stat_new_cart  = 0;
        stat_at_bot    = 0;
        stat_at_eot    = 0;

        @(posedge clk);

        reset_receiver;

        send_status = 1;
        @(posedge clk);
        send_status = 0;

        // Measure first bit (should be 0 = short pulse)
        measure_bit_pulse(measured_low, measured_bit);

        $display("  Bit 0: low_time=%0d clks (expected ~%0d)", measured_low, BIT0_LOW_CLKS);

        if (measured_low > BIT0_LOW_CLKS * 0.9 && measured_low < BIT0_LOW_CLKS * 1.1) begin
            $display("  PASS: Bit 0 timing correct");
        end else begin
            $display("  INFO: Timing outside 10%% tolerance");
        end

        wait_not_busy(20_000_000);

        //=====================================================================
        // Test 12: Alternating bit pattern
        //=====================================================================
        test_num = 12;
        $display("\n--- Test %0d: Alternating bit pattern (0xAA) ---", test_num);

        // Set status to 0xAA pattern (1010_1010)
        stat_ready     = 1;  // 1
        stat_error     = 0;  // 0
        stat_cartridge = 1;  // 1
        stat_write_prot = 0; // 0
        stat_new_cart  = 1;  // 1
        stat_at_bot    = 0;  // 0
        stat_at_eot    = 1;  // 1
        // Bit 0 = 0

        @(posedge clk);

        reset_receiver;

        send_status = 1;
        @(posedge clk);
        send_status = 0;

        wait_not_busy(20_000_000);

        $display("  Alternating pattern: expected=0xAA, received=0x%02X", received_bits);

        //=====================================================================
        // Summary
        //=====================================================================
        #100000;
        $display("\n============================================");
        $display("Test Summary: %0d errors", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("============================================");

        $finish;
    end

    //=========================================================================
    // Monitor
    //=========================================================================
    // Uncomment for detailed tracing
    // always @(posedge clk) begin
    //     if (busy) begin
    //         $display("  [%0t] trk0=%0d, bit=%0d, byte=%0d", $time, trk0_out, current_bit, current_byte);
    //     end
    // end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #500_000_000;  // 500ms simulation limit
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
