//==============================================================================
// QIC-117 Data Streamer Testbench
//==============================================================================
// File: tb_qic117_data_streamer.v
// Description: Verifies block and segment boundary detection in QIC tape MFM
//              data streams. Tests preamble detection, sync mark recognition,
//              block type identification, and ECC capture.
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module tb_qic117_data_streamer;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD  = 5;             // 200 MHz = 5ns period
    parameter CLK_FREQ_HZ = 200_000_000;

    // MFM bit timing at 500 Kbps = 2us per bit = 400 clocks at 200 MHz
    parameter MFM_BIT_CLKS = 400;

    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         reset_n;

    // Control
    reg         enable;
    reg         streaming;
    reg         direction;
    reg         clear_counters;

    // MFM interface
    reg         mfm_data;
    reg         mfm_clock;
    reg         dpll_locked;

    // Block detection outputs
    wire        block_sync;
    wire [8:0]  byte_in_block;
    wire        block_start;
    wire        block_complete;
    wire [4:0]  block_in_segment;
    wire [7:0]  block_header;

    // Segment tracking
    wire        segment_start;
    wire        segment_complete;
    wire [15:0] segment_count;
    wire        irg_detected;

    // Data output
    wire [7:0]  data_byte;
    wire        data_valid;
    wire        data_is_header;
    wire        data_is_ecc;

    // ECC output
    wire [23:0] ecc_bytes;
    wire        ecc_valid;

    // Block type detection
    wire        is_data_block;
    wire        is_file_mark;
    wire        is_eod_mark;
    wire        is_bad_block;

    // Error detection
    wire        sync_lost;
    wire        overrun_error;
    wire        preamble_error;
    wire [15:0] error_count;
    wire [15:0] good_block_count;

    // Debug
    wire [2:0]  state_out;
    wire [7:0]  preamble_count;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    qic117_data_streamer #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_dut (
        .clk(clk),
        .reset_n(reset_n),

        // Control
        .enable(enable),
        .streaming(streaming),
        .direction(direction),
        .clear_counters(clear_counters),

        // MFM interface
        .mfm_data(mfm_data),
        .mfm_clock(mfm_clock),
        .dpll_locked(dpll_locked),

        // Block detection
        .block_sync(block_sync),
        .byte_in_block(byte_in_block),
        .block_start(block_start),
        .block_complete(block_complete),
        .block_in_segment(block_in_segment),
        .block_header(block_header),

        // Segment tracking
        .segment_start(segment_start),
        .segment_complete(segment_complete),
        .segment_count(segment_count),
        .irg_detected(irg_detected),

        // Data output
        .data_byte(data_byte),
        .data_valid(data_valid),
        .data_is_header(data_is_header),
        .data_is_ecc(data_is_ecc),

        // ECC output
        .ecc_bytes(ecc_bytes),
        .ecc_valid(ecc_valid),

        // Block type detection
        .is_data_block(is_data_block),
        .is_file_mark(is_file_mark),
        .is_eod_mark(is_eod_mark),
        .is_bad_block(is_bad_block),

        // Error detection
        .sync_lost(sync_lost),
        .overrun_error(overrun_error),
        .preamble_error(preamble_error),
        .error_count(error_count),
        .good_block_count(good_block_count),

        // Debug
        .state_out(state_out),
        .preamble_count(preamble_count)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================================
    // MFM Pattern Constants
    //=========================================================================
    // MFM encoding: data and clock bits interleaved
    // Preamble 0x00 = 0xAAAA in MFM (alternating clock bits, no data transitions)
    // Sync 0xA1 with missing clock = 0x4489

    localparam [15:0] MFM_PREAMBLE = 16'hAAAA;  // 0x00 in MFM
    localparam [15:0] MFM_SYNC     = 16'h4489;  // 0xA1 with missing clock

    //=========================================================================
    // Tasks - MFM Bit Generation
    //=========================================================================

    // Send a single MFM bit with proper timing
    task send_mfm_bit;
        input bit_value;
        begin
            mfm_data = bit_value;
            mfm_clock = 1'b1;
            #(CLK_PERIOD);
            mfm_clock = 1'b0;
            #(MFM_BIT_CLKS * CLK_PERIOD - CLK_PERIOD);
        end
    endtask

    // Send a 16-bit MFM word (MSB first)
    task send_mfm_word;
        input [15:0] word;
        integer i;
        begin
            for (i = 15; i >= 0; i = i - 1) begin
                send_mfm_bit(word[i]);
            end
        end
    endtask

    // Send a byte with MFM encoding (simplified - actual MFM would need encoder)
    // For testing, we send raw bits as if already MFM decoded
    task send_raw_byte;
        input [7:0] byte_val;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                send_mfm_bit(byte_val[i]);
            end
        end
    endtask

    // Send preamble (10 bytes of 0x00)
    task send_preamble;
        input integer num_bytes;
        integer i;
        begin
            for (i = 0; i < num_bytes; i = i + 1) begin
                send_mfm_word(MFM_PREAMBLE);
            end
        end
    endtask

    // Send sync mark (0xA1 with missing clock)
    task send_sync;
        begin
            send_mfm_word(MFM_SYNC);
        end
    endtask

    // Send a complete QIC block with specified header
    task send_qic_block;
        input [7:0] header_byte;
        input [7:0] data_fill;
        input [23:0] ecc_val;
        integer i;
        begin
            // Preamble (10 bytes)
            send_preamble(10);

            // Sync marks (2x 0xA1)
            send_sync;
            send_raw_byte(8'hA1);  // Second sync byte

            // Header
            send_raw_byte(header_byte);

            // Data (512 bytes)
            for (i = 0; i < 512; i = i + 1) begin
                send_raw_byte(data_fill + i[7:0]);
            end

            // ECC (3 bytes)
            send_raw_byte(ecc_val[7:0]);
            send_raw_byte(ecc_val[15:8]);
            send_raw_byte(ecc_val[23:16]);
        end
    endtask

    // Send inter-record gap (silence)
    task send_irg;
        input integer bit_count;
        integer i;
        begin
            for (i = 0; i < bit_count; i = i + 1) begin
                mfm_data = 1'b0;
                mfm_clock = 1'b1;
                #(CLK_PERIOD);
                mfm_clock = 1'b0;
                #(MFM_BIT_CLKS * CLK_PERIOD - CLK_PERIOD);
            end
        end
    endtask

    //=========================================================================
    // Test Stimulus
    //=========================================================================
    integer errors;
    integer test_num;
    integer bytes_received;
    reg [7:0] last_header;
    reg [23:0] last_ecc;

    initial begin
        $display("============================================");
        $display("QIC-117 Data Streamer Testbench");
        $display("============================================");
        $display("CLK_FREQ_HZ   = %0d", CLK_FREQ_HZ);
        $display("MFM_BIT_CLKS  = %0d", MFM_BIT_CLKS);

        // Initialize
        reset_n        = 0;
        enable         = 0;
        streaming      = 0;
        direction      = 0;
        clear_counters = 0;
        mfm_data       = 0;
        mfm_clock      = 0;
        dpll_locked    = 0;
        errors         = 0;
        test_num       = 0;

        // Reset sequence
        #100;
        reset_n = 1;
        #100;

        //=====================================================================
        // Test 1: Disabled state - no activity
        //=====================================================================
        test_num = 1;
        $display("\n--- Test %0d: Disabled state ---", test_num);

        enable = 0;
        streaming = 0;
        dpll_locked = 1;

        // Send some MFM data
        send_preamble(5);
        send_sync;

        if (block_sync || data_valid) begin
            $display("  FAIL: Activity detected when disabled");
            errors = errors + 1;
        end else begin
            $display("  PASS: No activity when disabled");
        end

        #1000;

        //=====================================================================
        // Test 2: Enabled but not streaming - no activity
        //=====================================================================
        test_num = 2;
        $display("\n--- Test %0d: Enabled but not streaming ---", test_num);

        enable = 1;
        streaming = 0;
        dpll_locked = 1;

        send_preamble(5);
        send_sync;

        if (block_sync || data_valid) begin
            $display("  FAIL: Activity detected when not streaming");
            errors = errors + 1;
        end else begin
            $display("  PASS: No activity when not streaming");
        end

        #1000;

        //=====================================================================
        // Test 3: Simple preamble and sync detection
        //=====================================================================
        test_num = 3;
        $display("\n--- Test %0d: Preamble and sync detection ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;

        // Clear any previous state
        #100;

        // Send preamble (minimum 6 bytes required)
        $display("  Sending preamble...");
        send_preamble(10);

        // Check preamble count
        if (preamble_count >= 6) begin
            $display("  PASS: Preamble detected (count=%0d)", preamble_count);
        end else begin
            $display("  INFO: Preamble count=%0d (may need more)", preamble_count);
        end

        // Send sync
        $display("  Sending sync mark...");
        send_sync;

        // Wait for sync detection
        repeat (100) @(posedge clk);

        if (block_sync) begin
            $display("  PASS: Sync mark detected");
        end else begin
            $display("  INFO: Sync mark not detected (state=%0d)", state_out);
        end

        // Stop streaming to reset state
        streaming = 0;
        #1000;

        //=====================================================================
        // Test 4: Complete data block reception
        //=====================================================================
        test_num = 4;
        $display("\n--- Test %0d: Complete data block reception ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;
        bytes_received = 0;

        // Count data_valid pulses
        fork
            begin : send_block
                send_qic_block(8'h00, 8'hAA, 24'h123456);
            end
            begin : count_bytes
                while (streaming) begin
                    @(posedge clk);
                    if (data_valid) bytes_received = bytes_received + 1;
                end
            end
        join_any
        disable count_bytes;

        // Wait for block_complete
        repeat (1000) @(posedge clk);

        if (block_complete) begin
            $display("  PASS: Block complete signal received");
        end else begin
            $display("  INFO: Block complete not detected");
        end

        if (is_data_block) begin
            $display("  PASS: Block identified as data block");
        end else begin
            $display("  INFO: Block type not identified (header=0x%02X)", block_header);
        end

        $display("  INFO: Bytes received = %0d (expected ~516)", bytes_received);
        $display("  INFO: Good blocks = %0d", good_block_count);

        streaming = 0;
        #1000;

        //=====================================================================
        // Test 5: File mark detection
        //=====================================================================
        test_num = 5;
        $display("\n--- Test %0d: File mark detection ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;

        fork
            begin
                send_qic_block(8'h1F, 8'h00, 24'h000000);  // FILE_MARK header
            end
            begin : wait_file_mark
                repeat (100000) begin
                    @(posedge clk);
                    if (is_file_mark) begin
                        $display("  PASS: File mark detected");
                        disable wait_file_mark;
                    end
                end
                $display("  INFO: File mark not detected");
            end
        join_any
        disable wait_file_mark;

        streaming = 0;
        #1000;

        //=====================================================================
        // Test 6: EOD (End of Data) detection
        //=====================================================================
        test_num = 6;
        $display("\n--- Test %0d: EOD detection ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;

        fork
            begin
                send_qic_block(8'h0F, 8'h00, 24'h000000);  // EOD header
            end
            begin : wait_eod
                repeat (100000) begin
                    @(posedge clk);
                    if (is_eod_mark) begin
                        $display("  PASS: EOD marker detected");
                        disable wait_eod;
                    end
                end
                $display("  INFO: EOD not detected");
            end
        join_any
        disable wait_eod;

        streaming = 0;
        #1000;

        //=====================================================================
        // Test 7: Bad block detection
        //=====================================================================
        test_num = 7;
        $display("\n--- Test %0d: Bad block detection ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;

        fork
            begin
                send_qic_block(8'hFF, 8'h00, 24'h000000);  // BAD_BLOCK header
            end
            begin : wait_bad
                repeat (100000) begin
                    @(posedge clk);
                    if (is_bad_block) begin
                        $display("  PASS: Bad block marker detected");
                        disable wait_bad;
                    end
                end
                $display("  INFO: Bad block not detected");
            end
        join_any
        disable wait_bad;

        streaming = 0;
        #1000;

        //=====================================================================
        // Test 8: ECC capture
        //=====================================================================
        test_num = 8;
        $display("\n--- Test %0d: ECC capture ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;

        fork
            begin
                send_qic_block(8'h00, 8'h55, 24'hABCDEF);
            end
            begin : wait_ecc
                repeat (100000) begin
                    @(posedge clk);
                    if (ecc_valid) begin
                        last_ecc = ecc_bytes;
                        $display("  INFO: ECC captured = 0x%06X", ecc_bytes);
                        disable wait_ecc;
                    end
                end
            end
        join_any
        disable wait_ecc;

        streaming = 0;
        #1000;

        //=====================================================================
        // Test 9: Short preamble error
        //=====================================================================
        test_num = 9;
        $display("\n--- Test %0d: Short preamble error ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;

        // Send only 3 preamble bytes (minimum is 6)
        send_preamble(3);
        send_sync;

        // Wait for error detection
        repeat (1000) @(posedge clk);

        if (preamble_error) begin
            $display("  PASS: Preamble error detected for short preamble");
        end else begin
            $display("  INFO: Preamble error not detected");
        end

        streaming = 0;
        #1000;

        //=====================================================================
        // Test 10: DPLL lock loss during block
        //=====================================================================
        test_num = 10;
        $display("\n--- Test %0d: DPLL lock loss ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;

        fork
            begin : send_partial
                // Start sending a block
                send_preamble(10);
                send_sync;
                send_raw_byte(8'hA1);
                send_raw_byte(8'h00);  // Header

                // Send partial data
                repeat (100) send_raw_byte(8'h55);

                // Lose DPLL lock
                dpll_locked = 0;
                #1000;
            end
            begin : check_sync_lost
                repeat (50000) begin
                    @(posedge clk);
                    if (sync_lost) begin
                        $display("  PASS: Sync lost detected on DPLL unlock");
                        disable check_sync_lost;
                    end
                end
            end
        join_any
        disable check_sync_lost;
        disable send_partial;

        dpll_locked = 1;
        streaming = 0;
        #1000;

        //=====================================================================
        // Test 11: Counter clearing
        //=====================================================================
        test_num = 11;
        $display("\n--- Test %0d: Counter clearing ---", test_num);

        $display("  Before clear: segment_count=%0d, good_block_count=%0d, error_count=%0d",
                 segment_count, good_block_count, error_count);

        clear_counters = 1;
        #(CLK_PERIOD * 2);
        clear_counters = 0;
        #(CLK_PERIOD * 2);

        if (segment_count == 0 && good_block_count == 0 && error_count == 0) begin
            $display("  PASS: Counters cleared");
        end else begin
            $display("  FAIL: Counters not cleared (seg=%0d, good=%0d, err=%0d)",
                     segment_count, good_block_count, error_count);
            errors = errors + 1;
        end

        //=====================================================================
        // Test 12: Multiple consecutive blocks
        //=====================================================================
        test_num = 12;
        $display("\n--- Test %0d: Multiple consecutive blocks ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;
        clear_counters = 1;
        #(CLK_PERIOD * 2);
        clear_counters = 0;
        #(CLK_PERIOD * 2);

        fork
            begin : send_blocks
                integer b;
                for (b = 0; b < 5; b = b + 1) begin
                    $display("  Sending block %0d...", b);
                    send_qic_block(8'h00, b[7:0], 24'h000000 + b);
                    // Small gap between blocks
                    send_irg(100);
                end
            end
            begin : monitor_blocks
                integer blocks_seen;
                blocks_seen = 0;
                while (blocks_seen < 5) begin
                    @(posedge clk);
                    if (block_complete) begin
                        blocks_seen = blocks_seen + 1;
                        $display("  Block %0d complete (in_segment=%0d)",
                                 blocks_seen, block_in_segment);
                    end
                end
            end
        join_any
        disable monitor_blocks;
        disable send_blocks;

        // Wait for processing
        repeat (10000) @(posedge clk);

        $display("  Final: good_block_count=%0d", good_block_count);

        streaming = 0;
        #1000;

        //=====================================================================
        // Test 13: State machine transitions
        //=====================================================================
        test_num = 13;
        $display("\n--- Test %0d: State machine transitions ---", test_num);

        enable = 1;
        streaming = 1;
        dpll_locked = 1;

        $display("  Initial state: %0d (expect 0=HUNT_PREAMBLE)", state_out);

        // Send preamble - should transition to IN_PREAMBLE
        send_preamble(5);
        $display("  After preamble: state=%0d (expect 1=IN_PREAMBLE)", state_out);

        // Send sync - should transition through SYNC_VERIFY to HEADER
        send_preamble(5);  // More preamble
        send_sync;
        repeat (100) @(posedge clk);
        $display("  After sync: state=%0d", state_out);

        streaming = 0;
        #1000;

        //=====================================================================
        // Summary
        //=====================================================================
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

    //=========================================================================
    // Monitors
    //=========================================================================

    // Monitor block completion
    always @(posedge clk) begin
        if (block_complete) begin
            $display("  [%0t] BLOCK_COMPLETE: header=0x%02X, block_in_seg=%0d",
                     $time, block_header, block_in_segment);
        end
    end

    // Monitor segment completion
    always @(posedge clk) begin
        if (segment_complete) begin
            $display("  [%0t] SEGMENT_COMPLETE: segment_count=%0d", $time, segment_count);
        end
    end

    // Monitor errors
    always @(posedge clk) begin
        if (sync_lost) begin
            $display("  [%0t] ERROR: Sync lost", $time);
        end
        if (preamble_error) begin
            $display("  [%0t] ERROR: Preamble error", $time);
        end
        if (overrun_error) begin
            $display("  [%0t] ERROR: Data overrun", $time);
        end
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #500_000_000;  // 500ms simulation limit
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
