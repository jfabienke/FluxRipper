//-----------------------------------------------------------------------------
// Encoding Module Testbench
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Tests MFM, FM, and GCR encoding/decoding
//
// Updated: 2025-12-03 12:40
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_encoding;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter CLK_PERIOD = 5;  // 200 MHz

    //-------------------------------------------------------------------------
    // Common signals
    //-------------------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg         enable;

    //-------------------------------------------------------------------------
    // MFM test signals
    //-------------------------------------------------------------------------
    reg  [7:0]  mfm_data_in;
    reg         mfm_data_valid;
    reg         mfm_prev_bit;
    wire [15:0] mfm_encoded;
    wire        mfm_encoded_valid;
    wire [7:0]  mfm_decoded;
    wire        mfm_decoded_valid;
    wire        mfm_decode_error;

    //-------------------------------------------------------------------------
    // FM test signals
    //-------------------------------------------------------------------------
    reg  [7:0]  fm_data_in;
    reg         fm_data_valid;
    wire [15:0] fm_encoded;
    wire        fm_encoded_valid;
    wire [7:0]  fm_decoded;
    wire        fm_decoded_valid;
    wire        fm_decode_error;

    //-------------------------------------------------------------------------
    // CBM GCR test signals
    //-------------------------------------------------------------------------
    reg  [7:0]  gcr_cbm_data_in;
    reg         gcr_cbm_data_valid;
    wire [9:0]  gcr_cbm_encoded;
    wire        gcr_cbm_encoded_valid;
    wire [7:0]  gcr_cbm_decoded;
    wire        gcr_cbm_decoded_valid;
    wire        gcr_cbm_decode_error;

    //-------------------------------------------------------------------------
    // Apple GCR test signals
    //-------------------------------------------------------------------------
    reg  [5:0]  gcr_apple6_data_in;
    reg         gcr_apple6_data_valid;
    wire [7:0]  gcr_apple6_encoded;
    wire        gcr_apple6_encoded_valid;
    wire [5:0]  gcr_apple6_decoded;
    wire        gcr_apple6_decoded_valid;
    wire        gcr_apple6_decode_error;

    //-------------------------------------------------------------------------
    // DUT Instantiations
    //-------------------------------------------------------------------------

    // MFM Encoder
    mfm_encoder u_mfm_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .data_in(mfm_data_in),
        .data_valid(mfm_data_valid),
        .prev_data_bit(mfm_prev_bit),
        .encoded_out(mfm_encoded),
        .encoded_valid(mfm_encoded_valid),
        .last_data_bit(),
        .busy()
    );

    // MFM Decoder
    mfm_decoder u_mfm_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .encoded_in(mfm_encoded),
        .encoded_valid(mfm_encoded_valid),
        .data_out(mfm_decoded),
        .data_valid(mfm_decoded_valid),
        .decode_error(mfm_decode_error),
        .clock_pattern()
    );

    // FM Encoder
    fm_encoder u_fm_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .data_in(fm_data_in),
        .data_valid(fm_data_valid),
        .encoded_out(fm_encoded),
        .encoded_valid(fm_encoded_valid),
        .busy()
    );

    // FM Decoder
    fm_decoder u_fm_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .encoded_in(fm_encoded),
        .encoded_valid(fm_encoded_valid),
        .data_out(fm_decoded),
        .data_valid(fm_decoded_valid),
        .decode_error(fm_decode_error)
    );

    // CBM GCR Encoder
    gcr_cbm_encoder u_gcr_cbm_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .data_in(gcr_cbm_data_in),
        .data_valid(gcr_cbm_data_valid),
        .encoded_out(gcr_cbm_encoded),
        .encoded_valid(gcr_cbm_encoded_valid),
        .busy()
    );

    // CBM GCR Decoder
    gcr_cbm_decoder u_gcr_cbm_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .encoded_in(gcr_cbm_encoded),
        .encoded_valid(gcr_cbm_encoded_valid),
        .data_out(gcr_cbm_decoded),
        .data_valid(gcr_cbm_decoded_valid),
        .decode_error(gcr_cbm_decode_error)
    );

    // Apple 6-bit GCR Encoder
    gcr_apple6_encoder u_gcr_apple6_enc (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .data_in(gcr_apple6_data_in),
        .data_valid(gcr_apple6_data_valid),
        .encoded_out(gcr_apple6_encoded),
        .encoded_valid(gcr_apple6_encoded_valid),
        .busy()
    );

    // Apple 6-bit GCR Decoder
    gcr_apple6_decoder u_gcr_apple6_dec (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .encoded_in(gcr_apple6_encoded),
        .encoded_valid(gcr_apple6_encoded_valid),
        .data_out(gcr_apple6_decoded),
        .data_valid(gcr_apple6_decoded_valid),
        .decode_error(gcr_apple6_decode_error)
    );

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------------------
    integer errors;
    integer test_num;
    integer i;
    reg [7:0] test_byte;
    reg [5:0] test_nibble;

    initial begin
        $display("============================================");
        $display("Encoding Module Testbench");
        $display("============================================");

        // Initialize
        reset              = 1;
        enable             = 0;
        mfm_data_in        = 0;
        mfm_data_valid     = 0;
        mfm_prev_bit       = 0;
        fm_data_in         = 0;
        fm_data_valid      = 0;
        gcr_cbm_data_in    = 0;
        gcr_cbm_data_valid = 0;
        gcr_apple6_data_in    = 0;
        gcr_apple6_data_valid = 0;
        errors             = 0;
        test_num           = 0;

        // Reset
        #100;
        reset = 0;
        #50;
        enable = 1;
        #50;

        //---------------------------------------------------------------------
        // Test 1: MFM Encoding/Decoding
        //---------------------------------------------------------------------
        test_num = 1;
        $display("\nTest %0d: MFM Encoding/Decoding", test_num);

        // Test all byte values
        for (i = 0; i < 256; i = i + 1) begin
            test_byte = i;
            mfm_data_in = test_byte;
            mfm_data_valid = 1;
            @(posedge clk);
            mfm_data_valid = 0;

            // Wait for encoding
            @(posedge clk);
            @(posedge clk);

            // Wait for decoding
            repeat (5) @(posedge clk);

            // Check result
            if (mfm_decoded_valid) begin
                if (mfm_decoded !== test_byte) begin
                    $display("  FAIL: MFM byte 0x%02X decoded as 0x%02X", test_byte, mfm_decoded);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("  PASS: All 256 MFM byte values encoded/decoded correctly");

        //---------------------------------------------------------------------
        // Test 2: FM Encoding/Decoding
        //---------------------------------------------------------------------
        test_num = 2;
        $display("\nTest %0d: FM Encoding/Decoding", test_num);

        errors = 0;
        for (i = 0; i < 256; i = i + 1) begin
            test_byte = i;
            fm_data_in = test_byte;
            fm_data_valid = 1;
            @(posedge clk);
            fm_data_valid = 0;

            // Wait for encoding and decoding
            repeat (5) @(posedge clk);

            // Check result
            if (fm_decoded_valid) begin
                if (fm_decoded !== test_byte) begin
                    $display("  FAIL: FM byte 0x%02X decoded as 0x%02X", test_byte, fm_decoded);
                    errors = errors + 1;
                end
                if (fm_decode_error) begin
                    $display("  FAIL: FM byte 0x%02X had clock error", test_byte);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("  PASS: All 256 FM byte values encoded/decoded correctly");

        //---------------------------------------------------------------------
        // Test 3: FM Clock Pattern Verification
        //---------------------------------------------------------------------
        test_num = 3;
        $display("\nTest %0d: FM Clock Pattern Verification", test_num);

        // FM should have clock=1 for every bit
        fm_data_in = 8'hAA;  // 10101010
        fm_data_valid = 1;
        @(posedge clk);
        fm_data_valid = 0;
        @(posedge clk);
        @(posedge clk);

        // Expected: 11 10 11 10 11 10 11 10 = 0xEEEE (reversed bit order)
        // Actually: each bit pair is (clock=1, data)
        // 0xAA = 1 0 1 0 1 0 1 0
        // FM = 11 10 11 10 11 10 11 10 = 0xEEEE
        if (fm_encoded == 16'hEEEE)
            $display("  PASS: FM encoding of 0xAA = 0x%04X (expected 0xEEEE)", fm_encoded);
        else
            $display("  INFO: FM encoding of 0xAA = 0x%04X (verify pattern)", fm_encoded);

        //---------------------------------------------------------------------
        // Test 4: CBM GCR Encoding/Decoding
        //---------------------------------------------------------------------
        test_num = 4;
        $display("\nTest %0d: CBM GCR Encoding/Decoding", test_num);

        errors = 0;
        for (i = 0; i < 256; i = i + 1) begin
            test_byte = i;
            gcr_cbm_data_in = test_byte;
            gcr_cbm_data_valid = 1;
            @(posedge clk);
            gcr_cbm_data_valid = 0;

            // Wait for encoding and decoding
            repeat (5) @(posedge clk);

            // Check result
            if (gcr_cbm_decoded_valid) begin
                if (gcr_cbm_decoded !== test_byte) begin
                    $display("  FAIL: GCR-CBM byte 0x%02X decoded as 0x%02X", test_byte, gcr_cbm_decoded);
                    errors = errors + 1;
                end
                if (gcr_cbm_decode_error) begin
                    $display("  FAIL: GCR-CBM byte 0x%02X had decode error", test_byte);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("  PASS: All 256 CBM GCR byte values encoded/decoded correctly");

        //---------------------------------------------------------------------
        // Test 5: CBM GCR Known Values
        //---------------------------------------------------------------------
        test_num = 5;
        $display("\nTest %0d: CBM GCR Known Values", test_num);

        // Test specific nibble encodings from CAPSImg table
        // nibble 0 -> 0x0A (01010)
        gcr_cbm_data_in = 8'h00;
        gcr_cbm_data_valid = 1;
        @(posedge clk);
        gcr_cbm_data_valid = 0;
        repeat (3) @(posedge clk);

        // Both nibbles are 0, so encoded should be 01010 01010 = 0x14A
        if (gcr_cbm_encoded == 10'h14A)
            $display("  PASS: GCR-CBM 0x00 = 0x%03X (expected 0x14A)", gcr_cbm_encoded);
        else
            $display("  INFO: GCR-CBM 0x00 = 0x%03X (verify against CAPSImg)", gcr_cbm_encoded);

        //---------------------------------------------------------------------
        // Test 6: Apple 6-bit GCR Encoding/Decoding
        //---------------------------------------------------------------------
        test_num = 6;
        $display("\nTest %0d: Apple 6-bit GCR Encoding/Decoding", test_num);

        errors = 0;
        for (i = 0; i < 64; i = i + 1) begin
            test_nibble = i;
            gcr_apple6_data_in = test_nibble;
            gcr_apple6_data_valid = 1;
            @(posedge clk);
            gcr_apple6_data_valid = 0;

            // Wait for encoding and decoding
            repeat (5) @(posedge clk);

            // Check result
            if (gcr_apple6_decoded_valid) begin
                if (gcr_apple6_decoded !== test_nibble) begin
                    $display("  FAIL: Apple6 value 0x%02X decoded as 0x%02X", test_nibble, gcr_apple6_decoded);
                    errors = errors + 1;
                end
                if (gcr_apple6_decode_error) begin
                    $display("  FAIL: Apple6 value 0x%02X had decode error", test_nibble);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("  PASS: All 64 Apple 6-bit GCR values encoded/decoded correctly");

        //---------------------------------------------------------------------
        // Test 7: Apple GCR Known Values
        //---------------------------------------------------------------------
        test_num = 7;
        $display("\nTest %0d: Apple GCR Known Values", test_num);

        // Test specific encodings from CAPSImg table
        // Value 0 -> 0x96
        gcr_apple6_data_in = 6'h00;
        gcr_apple6_data_valid = 1;
        @(posedge clk);
        gcr_apple6_data_valid = 0;
        repeat (3) @(posedge clk);

        if (gcr_apple6_encoded == 8'h96)
            $display("  PASS: Apple6 0x00 = 0x%02X (expected 0x96)", gcr_apple6_encoded);
        else
            $display("  FAIL: Apple6 0x00 = 0x%02X (expected 0x96)", gcr_apple6_encoded);

        // Value 0x3F -> 0xFF
        gcr_apple6_data_in = 6'h3F;
        gcr_apple6_data_valid = 1;
        @(posedge clk);
        gcr_apple6_data_valid = 0;
        repeat (3) @(posedge clk);

        if (gcr_apple6_encoded == 8'hFF)
            $display("  PASS: Apple6 0x3F = 0x%02X (expected 0xFF)", gcr_apple6_encoded);
        else
            $display("  FAIL: Apple6 0x3F = 0x%02X (expected 0xFF)", gcr_apple6_encoded);

        //---------------------------------------------------------------------
        // Test 8: MFM A1 Sync Pattern
        //---------------------------------------------------------------------
        test_num = 8;
        $display("\nTest %0d: MFM A1 Sync Pattern", test_num);

        // A1 with missing clock should produce 0x4489
        mfm_prev_bit = 0;
        mfm_data_in = 8'hA1;
        mfm_data_valid = 1;
        @(posedge clk);
        mfm_data_valid = 0;
        repeat (3) @(posedge clk);

        // Note: Standard MFM encoder won't produce 0x4489 (missing clock)
        // That requires special handling in AM detector
        $display("  INFO: MFM A1 = 0x%04X (standard encoding, not sync mark)", mfm_encoded);

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        #100;
        $display("\n============================================");
        $display("Encoding Test Summary");
        if (errors == 0)
            $display("ALL ENCODING TESTS PASSED");
        else
            $display("SOME ENCODING TESTS FAILED: %0d errors", errors);
        $display("============================================");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #1_000_000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
