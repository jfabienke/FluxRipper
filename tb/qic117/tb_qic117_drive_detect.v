//==============================================================================
// QIC-117 Drive Detection Testbench
//==============================================================================
// File: tb_qic117_drive_detect.v
// Description: Testbench for qic117_drive_detect module.
//              Tests drive detection sequence, timeout handling, and
//              drive type decoding.
//
// Author: FluxRipper Project
// SPDX-License-Identifier: BSD-3-Clause
//==============================================================================

`timescale 1ns / 1ps

module tb_qic117_drive_detect;

    //=========================================================================
    // Parameters
    //=========================================================================
    // Use faster clock for simulation (1 MHz instead of 200 MHz)
    localparam CLK_FREQ_HZ = 1_000_000;
    localparam CLK_PERIOD  = 1000;  // 1us period

    //=========================================================================
    // QIC-117 Command Codes (for reference)
    //=========================================================================
    localparam [5:0] QIC_REPORT_STATUS    = 6'd4;
    localparam [5:0] QIC_REPORT_VENDOR    = 6'd38;
    localparam [5:0] QIC_REPORT_MODEL     = 6'd39;
    localparam [5:0] QIC_REPORT_ROM_VER   = 6'd40;
    localparam [5:0] QIC_REPORT_DRIVE_CFG = 6'd41;
    localparam [5:0] QIC_PHANTOM_SELECT   = 6'd46;

    //=========================================================================
    // Vendor IDs
    //=========================================================================
    localparam [7:0] VENDOR_CMS     = 8'h01;
    localparam [7:0] VENDOR_CONNER  = 8'h02;
    localparam [7:0] VENDOR_IOMEGA  = 8'h03;
    localparam [7:0] VENDOR_WANGTEK = 8'h05;

    //=========================================================================
    // Drive Type Enum
    //=========================================================================
    localparam [3:0] DRIVE_UNKNOWN  = 4'd0;
    localparam [3:0] DRIVE_QIC40    = 4'd1;
    localparam [3:0] DRIVE_QIC80    = 4'd2;
    localparam [3:0] DRIVE_QIC3010  = 4'd4;
    localparam [3:0] DRIVE_QIC3020  = 4'd5;
    localparam [3:0] DRIVE_DITTO    = 4'd9;

    //=========================================================================
    // Test Signals
    //=========================================================================
    reg         clk;
    reg         reset_n;
    reg         enable;
    reg         start_detect;
    reg         abort_detect;

    // Command interface
    wire [5:0]  cmd_code;
    wire        cmd_send;
    reg         cmd_done;

    // TRK0 decoder interface
    wire        trk0_capture_start;
    wire [3:0]  trk0_expected_bytes;
    reg  [63:0] trk0_response;
    reg  [3:0]  trk0_bytes_rcvd;
    reg         trk0_complete;
    reg         trk0_error;

    // Detection results
    wire        detect_complete;
    wire        detect_error;
    wire        drive_present;
    wire        cartridge_present;
    wire        write_protected;
    wire [7:0]  vendor_id;
    wire [7:0]  model_id;
    wire [7:0]  rom_version;
    wire [7:0]  drive_config;
    wire [3:0]  drive_type;
    wire [4:0]  max_tracks;
    wire [1:0]  supported_rates;
    wire        detecting;
    wire [3:0]  detect_phase;

    //=========================================================================
    // Simulated Drive Responses
    //=========================================================================
    // Storage for simulated drive
    reg  [7:0]  sim_vendor;
    reg  [7:0]  sim_model;
    reg  [7:0]  sim_config;
    reg  [7:0]  sim_status;
    reg         sim_drive_present;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    qic117_drive_detect #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_dut (
        .clk                (clk),
        .reset_n            (reset_n),
        .enable             (enable),
        .start_detect       (start_detect),
        .abort_detect       (abort_detect),
        .cmd_code           (cmd_code),
        .cmd_send           (cmd_send),
        .cmd_done           (cmd_done),
        .trk0_capture_start (trk0_capture_start),
        .trk0_expected_bytes(trk0_expected_bytes),
        .trk0_response      (trk0_response),
        .trk0_bytes_rcvd    (trk0_bytes_rcvd),
        .trk0_complete      (trk0_complete),
        .trk0_error         (trk0_error),
        .detect_complete    (detect_complete),
        .detect_error       (detect_error),
        .drive_present      (drive_present),
        .cartridge_present  (cartridge_present),
        .write_protected    (write_protected),
        .vendor_id          (vendor_id),
        .model_id           (model_id),
        .rom_version        (rom_version),
        .drive_config       (drive_config),
        .drive_type         (drive_type),
        .max_tracks         (max_tracks),
        .supported_rates    (supported_rates),
        .detecting          (detecting),
        .detect_phase       (detect_phase)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================================
    // Simulated Drive Response Logic
    //=========================================================================
    // This simulates the drive responding to commands
    always @(posedge clk) begin
        cmd_done      <= 1'b0;
        trk0_complete <= 1'b0;
        trk0_error    <= 1'b0;

        // Respond to commands after short delay
        if (cmd_send && sim_drive_present) begin
            // Command sent - simulate command completion after delay
            #(CLK_PERIOD * 10);
            @(posedge clk);
            cmd_done <= 1'b1;
        end

        // Respond to TRK0 capture requests
        if (trk0_capture_start && sim_drive_present) begin
            // Simulate TRK0 response after delay
            #(CLK_PERIOD * 20);
            @(posedge clk);

            case (cmd_code)
                QIC_REPORT_STATUS: begin
                    trk0_response   <= {56'd0, sim_status};
                    trk0_bytes_rcvd <= 4'd1;
                    trk0_complete   <= 1'b1;
                end

                QIC_REPORT_VENDOR: begin
                    trk0_response   <= {56'd0, sim_vendor};
                    trk0_bytes_rcvd <= 4'd1;
                    trk0_complete   <= 1'b1;
                end

                QIC_REPORT_MODEL: begin
                    trk0_response   <= {56'd0, sim_model};
                    trk0_bytes_rcvd <= 4'd1;
                    trk0_complete   <= 1'b1;
                end

                QIC_REPORT_DRIVE_CFG: begin
                    trk0_response   <= {48'd0, 8'h01, sim_config};  // config + version
                    trk0_bytes_rcvd <= 4'd2;
                    trk0_complete   <= 1'b1;
                end

                default: begin
                    trk0_response   <= 64'd0;
                    trk0_bytes_rcvd <= 4'd0;
                    trk0_error      <= 1'b1;
                end
            endcase
        end
    end

    //=========================================================================
    // Test Tasks
    //=========================================================================

    task reset_dut;
    begin
        reset_n      <= 1'b0;
        enable       <= 1'b0;
        start_detect <= 1'b0;
        abort_detect <= 1'b0;
        trk0_response <= 64'd0;
        trk0_bytes_rcvd <= 4'd0;
        trk0_complete <= 1'b0;
        trk0_error    <= 1'b0;
        cmd_done      <= 1'b0;

        // Simulated drive defaults
        sim_drive_present <= 1'b0;
        sim_vendor        <= 8'd0;
        sim_model         <= 8'd0;
        sim_config        <= 8'd0;
        sim_status        <= 8'd0;

        #(CLK_PERIOD * 10);
        reset_n <= 1'b1;
        #(CLK_PERIOD * 5);
    end
    endtask

    task configure_simulated_drive;
        input        present;
        input [7:0]  vendor;
        input [7:0]  model;
        input [7:0]  config_byte;
        input [7:0]  status;
    begin
        sim_drive_present <= present;
        sim_vendor        <= vendor;
        sim_model         <= model;
        sim_config        <= config_byte;
        sim_status        <= status;
        $display("  Configured simulated drive: present=%b vendor=0x%02X model=0x%02X config=0x%02X",
                 present, vendor, model, config_byte);
    end
    endtask

    task start_detection;
    begin
        @(posedge clk);
        start_detect <= 1'b1;
        @(posedge clk);
        start_detect <= 1'b0;
        $display("  Detection started at time %0t", $time);
    end
    endtask

    task wait_detection_complete;
        input integer max_cycles;
        integer cycle_count;
    begin
        cycle_count = 0;
        while (!detect_complete && !detect_error && cycle_count < max_cycles) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (cycle_count >= max_cycles) begin
            $display("  WARNING: Detection did not complete within %0d cycles", max_cycles);
        end else begin
            $display("  Detection completed in %0d cycles", cycle_count);
        end
    end
    endtask

    task print_detection_results;
    begin
        $display("  Results:");
        $display("    drive_present:     %b", drive_present);
        $display("    cartridge_present: %b", cartridge_present);
        $display("    write_protected:   %b", write_protected);
        $display("    vendor_id:         0x%02X", vendor_id);
        $display("    model_id:          0x%02X", model_id);
        $display("    drive_config:      0x%02X", drive_config);
        $display("    rom_version:       0x%02X", rom_version);
        $display("    drive_type:        %0d", drive_type);
        $display("    max_tracks:        %0d", max_tracks);
        $display("    supported_rates:   %b", supported_rates);
    end
    endtask

    //=========================================================================
    // Test Stimulus
    //=========================================================================
    integer errors;

    initial begin
        $display("==================================================");
        $display("QIC-117 Drive Detection Testbench");
        $display("==================================================");
        errors = 0;

        //=====================================================================
        // Test 1: No drive present (timeout)
        //=====================================================================
        $display("\nTest 1: No drive present");
        reset_dut;
        enable <= 1'b1;
        configure_simulated_drive(1'b0, 8'h00, 8'h00, 8'h00, 8'h00);

        start_detection;
        wait_detection_complete(100000);  // Allow for timeout

        if (drive_present) begin
            $display("  FAIL: drive_present should be 0");
            errors = errors + 1;
        end else begin
            $display("  PASS: No drive correctly detected");
        end

        //=====================================================================
        // Test 2: CMS QIC-40 Drive
        //=====================================================================
        $display("\nTest 2: CMS QIC-40 Drive");
        reset_dut;
        enable <= 1'b1;
        // Status: ready=1, cartridge=1, WP=0
        configure_simulated_drive(1'b1, VENDOR_CMS, 8'h10, 8'h02, 8'b01100000);

        start_detection;
        wait_detection_complete(10000);

        print_detection_results;

        if (!drive_present) begin
            $display("  FAIL: drive_present should be 1");
            errors = errors + 1;
        end else if (vendor_id != VENDOR_CMS) begin
            $display("  FAIL: vendor_id should be 0x%02X, got 0x%02X", VENDOR_CMS, vendor_id);
            errors = errors + 1;
        end else if (drive_type != DRIVE_QIC40) begin
            $display("  FAIL: drive_type should be %0d (QIC-40), got %0d", DRIVE_QIC40, drive_type);
            errors = errors + 1;
        end else if (max_tracks != 5'd20) begin
            $display("  FAIL: max_tracks should be 20, got %0d", max_tracks);
            errors = errors + 1;
        end else begin
            $display("  PASS: CMS QIC-40 correctly detected");
        end

        //=====================================================================
        // Test 3: CMS QIC-80 Drive
        //=====================================================================
        $display("\nTest 3: CMS QIC-80 Drive");
        reset_dut;
        enable <= 1'b1;
        // Config byte 0x04 = QIC-80
        configure_simulated_drive(1'b1, VENDOR_CMS, 8'h20, 8'h04, 8'b01110000);

        start_detection;
        wait_detection_complete(10000);

        print_detection_results;

        if (drive_type != DRIVE_QIC80) begin
            $display("  FAIL: drive_type should be %0d (QIC-80), got %0d", DRIVE_QIC80, drive_type);
            errors = errors + 1;
        end else if (max_tracks != 5'd28) begin
            $display("  FAIL: max_tracks should be 28, got %0d", max_tracks);
            errors = errors + 1;
        end else begin
            $display("  PASS: CMS QIC-80 correctly detected");
        end

        //=====================================================================
        // Test 4: Conner QIC-3010 Drive
        //=====================================================================
        $display("\nTest 4: Conner QIC-3010 Drive");
        reset_dut;
        enable <= 1'b1;
        // Model > 0x20 indicates QIC-3010
        configure_simulated_drive(1'b1, VENDOR_CONNER, 8'h30, 8'h08, 8'b01100000);

        start_detection;
        wait_detection_complete(10000);

        print_detection_results;

        if (vendor_id != VENDOR_CONNER) begin
            $display("  FAIL: vendor_id should be 0x%02X, got 0x%02X", VENDOR_CONNER, vendor_id);
            errors = errors + 1;
        end else if (drive_type != DRIVE_QIC3010) begin
            $display("  FAIL: drive_type should be %0d (QIC-3010), got %0d", DRIVE_QIC3010, drive_type);
            errors = errors + 1;
        end else if (max_tracks != 5'd40) begin
            $display("  FAIL: max_tracks should be 40, got %0d", max_tracks);
            errors = errors + 1;
        end else begin
            $display("  PASS: Conner QIC-3010 correctly detected");
        end

        //=====================================================================
        // Test 5: Iomega Ditto Drive
        //=====================================================================
        $display("\nTest 5: Iomega Ditto Drive");
        reset_dut;
        enable <= 1'b1;
        // Model <= 0x10 = Ditto
        configure_simulated_drive(1'b1, VENDOR_IOMEGA, 8'h08, 8'h05, 8'b01100000);

        start_detection;
        wait_detection_complete(10000);

        print_detection_results;

        if (vendor_id != VENDOR_IOMEGA) begin
            $display("  FAIL: vendor_id should be 0x%02X, got 0x%02X", VENDOR_IOMEGA, vendor_id);
            errors = errors + 1;
        end else if (drive_type != DRIVE_DITTO) begin
            $display("  FAIL: drive_type should be %0d (Ditto), got %0d", DRIVE_DITTO, drive_type);
            errors = errors + 1;
        end else begin
            $display("  PASS: Iomega Ditto correctly detected");
        end

        //=====================================================================
        // Test 6: Write-protected cartridge
        //=====================================================================
        $display("\nTest 6: Write-protected cartridge");
        reset_dut;
        enable <= 1'b1;
        // Status byte bit 4 = write protected
        configure_simulated_drive(1'b1, VENDOR_CMS, 8'h10, 8'h02, 8'b01110000);

        start_detection;
        wait_detection_complete(10000);

        print_detection_results;

        if (!write_protected) begin
            $display("  FAIL: write_protected should be 1");
            errors = errors + 1;
        end else begin
            $display("  PASS: Write protection correctly detected");
        end

        //=====================================================================
        // Test 7: Abort detection
        //=====================================================================
        $display("\nTest 7: Abort detection");
        reset_dut;
        enable <= 1'b1;
        configure_simulated_drive(1'b1, VENDOR_CMS, 8'h10, 8'h02, 8'b01100000);

        start_detection;

        // Wait for detection to start
        #(CLK_PERIOD * 50);

        // Abort
        @(posedge clk);
        abort_detect <= 1'b1;
        @(posedge clk);
        abort_detect <= 1'b0;

        // Wait a few cycles
        #(CLK_PERIOD * 10);

        if (detecting) begin
            $display("  FAIL: detecting should be 0 after abort");
            errors = errors + 1;
        end else if (!detect_error) begin
            $display("  FAIL: detect_error should be 1 after abort");
            errors = errors + 1;
        end else begin
            $display("  PASS: Detection correctly aborted");
        end

        //=====================================================================
        // Test 8: QIC-3020 (1 Mbps drive)
        //=====================================================================
        $display("\nTest 8: QIC-3020 (1 Mbps) Drive");
        reset_dut;
        enable <= 1'b1;
        // Config byte bit 6 = 1 Mbps support
        configure_simulated_drive(1'b1, VENDOR_CONNER, 8'h30, 8'b01001000, 8'b01100000);

        start_detection;
        wait_detection_complete(10000);

        print_detection_results;

        if (drive_type != DRIVE_QIC3020) begin
            $display("  FAIL: drive_type should be %0d (QIC-3020), got %0d", DRIVE_QIC3020, drive_type);
            errors = errors + 1;
        end else if (supported_rates != 2'b11) begin
            $display("  FAIL: supported_rates should be 0b11 (1Mbps), got %b", supported_rates);
            errors = errors + 1;
        end else begin
            $display("  PASS: QIC-3020 correctly detected");
        end

        //=====================================================================
        // Test 9: Unknown vendor with high capacity config
        //=====================================================================
        $display("\nTest 9: Unknown vendor, high capacity");
        reset_dut;
        enable <= 1'b1;
        // Unknown vendor, high bit set in config = QIC-3010 guess
        configure_simulated_drive(1'b1, 8'hFF, 8'h00, 8'b10000000, 8'b01100000);

        start_detection;
        wait_detection_complete(10000);

        print_detection_results;

        if (drive_type != DRIVE_QIC3010) begin
            $display("  FAIL: drive_type should be %0d (QIC-3010), got %0d", DRIVE_QIC3010, drive_type);
            errors = errors + 1;
        end else begin
            $display("  PASS: Unknown vendor high capacity correctly identified");
        end

        //=====================================================================
        // Test 10: Detection while disabled
        //=====================================================================
        $display("\nTest 10: Detection while disabled");
        reset_dut;
        enable <= 1'b0;  // Disabled
        configure_simulated_drive(1'b1, VENDOR_CMS, 8'h10, 8'h02, 8'b01100000);

        start_detection;
        #(CLK_PERIOD * 100);

        if (detecting) begin
            $display("  FAIL: should not be detecting when disabled");
            errors = errors + 1;
        end else begin
            $display("  PASS: Detection correctly blocked when disabled");
        end

        //=====================================================================
        // Summary
        //=====================================================================
        $display("\n==================================================");
        if (errors == 0) begin
            $display("All tests PASSED");
        end else begin
            $display("Tests completed with %0d errors", errors);
        end
        $display("==================================================");

        #(CLK_PERIOD * 100);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #100000000;  // 100ms simulation timeout
        $display("ERROR: Simulation timeout");
        $finish;
    end

    //=========================================================================
    // Monitor
    //=========================================================================
    always @(posedge detect_complete) begin
        $display("  [%0t] Detection complete - present=%b error=%b phase=%d",
                 $time, drive_present, detect_error, detect_phase);
    end

    always @(posedge detect_error) begin
        $display("  [%0t] Detection error occurred - phase=%d", $time, detect_phase);
    end

endmodule
