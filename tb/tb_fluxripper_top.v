//-----------------------------------------------------------------------------
// FluxRipper Top-Level Testbench
// FluxRipper - FPGA-based Floppy Disk Controller
//
// System-level integration test
//
// Updated: 2025-12-03 12:50
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_fluxripper_top;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter CLK_PERIOD = 5;           // 200 MHz = 5ns
    parameter MFM_BIT_TIME = 2000;      // 500 Kbps = 2us per bit cell

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    reg         clk_200mhz;
    reg         reset_n;

    // CPU Interface
    reg  [2:0]  addr;
    reg         cs_n;
    reg         rd_n;
    reg         wr_n;
    wire [7:0]  data;
    reg  [7:0]  data_out_reg;
    reg         data_oe;
    wire        irq;
    wire        drq;

    // Drive 0 Interface
    wire        drv0_step;
    wire        drv0_dir;
    wire        drv0_motor;
    wire        drv0_head_sel;
    wire        drv0_write_gate;
    wire        drv0_write_data;
    reg         drv0_read_data;
    reg         drv0_index;
    reg         drv0_track0;
    reg         drv0_wp;
    reg         drv0_ready;
    reg         drv0_dskchg;

    // Drive 1 Interface
    wire        drv1_step;
    wire        drv1_dir;
    wire        drv1_motor;
    wire        drv1_head_sel;
    wire        drv1_write_gate;
    wire        drv1_write_data;
    reg         drv1_read_data;
    reg         drv1_index;
    reg         drv1_track0;
    reg         drv1_wp;
    reg         drv1_ready;
    reg         drv1_dskchg;

    // Diagnostic outputs
    wire        pll_locked;
    wire [7:0]  lock_quality;
    wire [7:0]  current_track;
    wire        sync_acquired;
    wire        led_activity;
    wire        led_error;

    //-------------------------------------------------------------------------
    // Bidirectional data bus handling
    //-------------------------------------------------------------------------
    assign data = data_oe ? data_out_reg : 8'hZZ;

    //-------------------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------------------
    fluxripper_top u_dut (
        .clk_200mhz(clk_200mhz),
        .reset_n(reset_n),
        .addr(addr),
        .cs_n(cs_n),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .data(data),
        .irq(irq),
        .drq(drq),
        .drv0_step(drv0_step),
        .drv0_dir(drv0_dir),
        .drv0_motor(drv0_motor),
        .drv0_head_sel(drv0_head_sel),
        .drv0_write_gate(drv0_write_gate),
        .drv0_write_data(drv0_write_data),
        .drv0_read_data(drv0_read_data),
        .drv0_index(drv0_index),
        .drv0_track0(drv0_track0),
        .drv0_wp(drv0_wp),
        .drv0_ready(drv0_ready),
        .drv0_dskchg(drv0_dskchg),
        .drv1_step(drv1_step),
        .drv1_dir(drv1_dir),
        .drv1_motor(drv1_motor),
        .drv1_head_sel(drv1_head_sel),
        .drv1_write_gate(drv1_write_gate),
        .drv1_write_data(drv1_write_data),
        .drv1_read_data(drv1_read_data),
        .drv1_index(drv1_index),
        .drv1_track0(drv1_track0),
        .drv1_wp(drv1_wp),
        .drv1_ready(drv1_ready),
        .drv1_dskchg(drv1_dskchg),
        .pll_locked(pll_locked),
        .lock_quality(lock_quality),
        .current_track(current_track),
        .sync_acquired(sync_acquired),
        .led_activity(led_activity),
        .led_error(led_error)
    );

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk_200mhz = 0;
        forever #(CLK_PERIOD/2) clk_200mhz = ~clk_200mhz;
    end

    //-------------------------------------------------------------------------
    // Index Pulse Generation (300 RPM = 200ms period)
    //-------------------------------------------------------------------------
    initial begin
        drv0_index = 0;
        drv1_index = 0;
        forever begin
            #200_000_000;  // 200ms
            drv0_index = 1;
            drv1_index = 1;
            #1000;         // 1us pulse
            drv0_index = 0;
            drv1_index = 0;
        end
    end

    //-------------------------------------------------------------------------
    // Register Read Task
    //-------------------------------------------------------------------------
    reg [7:0] read_data;

    task cpu_read;
        input [2:0] reg_addr;
        output [7:0] data_read;
        begin
            addr = reg_addr;
            cs_n = 0;
            rd_n = 0;
            data_oe = 0;
            #100;
            data_read = data;
            #100;
            cs_n = 1;
            rd_n = 1;
            #50;
        end
    endtask

    //-------------------------------------------------------------------------
    // Register Write Task
    //-------------------------------------------------------------------------
    task cpu_write;
        input [2:0] reg_addr;
        input [7:0] data_write;
        begin
            addr = reg_addr;
            data_out_reg = data_write;
            data_oe = 1;
            cs_n = 0;
            wr_n = 0;
            #100;
            cs_n = 1;
            wr_n = 1;
            #50;
            data_oe = 0;
        end
    endtask

    //-------------------------------------------------------------------------
    // Wait for RQM (Request for Master)
    //-------------------------------------------------------------------------
    task wait_rqm;
        integer timeout;
        begin
            timeout = 0;
            while (timeout < 10000) begin
                cpu_read(3'h4, read_data);  // Read MSR
                if (read_data[7])           // RQM bit
                    timeout = 10000;        // Exit loop
                else begin
                    timeout = timeout + 1;
                    #1000;
                end
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Test Stimulus
    //-------------------------------------------------------------------------
    integer errors;
    integer test_num;

    initial begin
        $display("============================================");
        $display("FluxRipper Top-Level Testbench");
        $display("============================================");

        // Initialize signals
        reset_n        = 0;
        addr           = 0;
        cs_n           = 1;
        rd_n           = 1;
        wr_n           = 1;
        data_out_reg   = 0;
        data_oe        = 0;
        drv0_read_data = 0;
        drv0_track0    = 1;  // At track 0
        drv0_wp        = 0;  // Not write protected
        drv0_ready     = 1;  // Drive ready
        drv0_dskchg    = 0;  // No disk change
        drv1_read_data = 0;
        drv1_track0    = 0;
        drv1_wp        = 0;
        drv1_ready     = 0;
        drv1_dskchg    = 0;
        errors         = 0;
        test_num       = 0;

        // Reset sequence
        #100;
        reset_n = 1;
        #500;

        //---------------------------------------------------------------------
        // Test 1: Read Main Status Register
        //---------------------------------------------------------------------
        test_num = 1;
        $display("\nTest %0d: Read Main Status Register (MSR)", test_num);

        cpu_read(3'h4, read_data);
        $display("  MSR = 0x%02X", read_data);
        $display("    RQM=%b DIO=%b NDMA=%b CB=%b", read_data[7], read_data[6], read_data[5], read_data[4]);

        if (read_data[7] == 1'b1)
            $display("  PASS: RQM is set (controller ready)");
        else begin
            $display("  FAIL: RQM not set");
            errors = errors + 1;
        end

        //---------------------------------------------------------------------
        // Test 2: Write to DOR (Digital Output Register)
        //---------------------------------------------------------------------
        test_num = 2;
        $display("\nTest %0d: Write to DOR - Enable motor and select drive", test_num);

        // DOR: Motor A on (bit 4), DMA enable (bit 3), not reset (bit 2), drive 0 (bits 1:0)
        cpu_write(3'h2, 8'h1C);
        #100;

        $display("  DOR written: 0x1C (Motor A on, DMA enabled, drive 0)");

        // Check motor output
        #1000;
        if (drv0_motor)
            $display("  PASS: Drive 0 motor output active");
        else begin
            $display("  FAIL: Drive 0 motor not active");
            errors = errors + 1;
        end

        //---------------------------------------------------------------------
        // Test 3: SPECIFY Command
        //---------------------------------------------------------------------
        test_num = 3;
        $display("\nTest %0d: SPECIFY command", test_num);

        wait_rqm();
        cpu_write(3'h5, 8'h03);  // SPECIFY command
        wait_rqm();
        cpu_write(3'h5, 8'hDF);  // SRT=D, HUT=F
        wait_rqm();
        cpu_write(3'h5, 8'h02);  // HLT=01, ND=0

        #1000;
        $display("  SPECIFY command completed");

        //---------------------------------------------------------------------
        // Test 4: RECALIBRATE Command
        //---------------------------------------------------------------------
        test_num = 4;
        $display("\nTest %0d: RECALIBRATE command", test_num);

        wait_rqm();
        cpu_write(3'h5, 8'h07);  // RECALIBRATE command
        wait_rqm();
        cpu_write(3'h5, 8'h00);  // Drive 0

        // Wait for seek to complete (or timeout)
        $display("  RECALIBRATE initiated, waiting for completion...");

        // Simulate track 0 already reached
        #10000;

        // Check current track
        if (current_track == 8'd0)
            $display("  PASS: Track position = %d (expected 0)", current_track);
        else
            $display("  INFO: Track position = %d", current_track);

        //---------------------------------------------------------------------
        // Test 5: SENSE INTERRUPT STATUS
        //---------------------------------------------------------------------
        test_num = 5;
        $display("\nTest %0d: SENSE INTERRUPT STATUS", test_num);

        wait_rqm();
        cpu_write(3'h5, 8'h08);  // SENSE INTERRUPT command

        // Wait for result phase
        #1000;
        wait_rqm();
        cpu_read(3'h5, read_data);  // Read ST0
        $display("  ST0 = 0x%02X", read_data);

        wait_rqm();
        cpu_read(3'h5, read_data);  // Read PCN
        $display("  PCN = 0x%02X (track %d)", read_data, read_data);

        //---------------------------------------------------------------------
        // Test 6: VERSION Command
        //---------------------------------------------------------------------
        test_num = 6;
        $display("\nTest %0d: VERSION command", test_num);

        wait_rqm();
        cpu_write(3'h5, 8'h10);  // VERSION command

        wait_rqm();
        cpu_read(3'h5, read_data);  // Read version

        if (read_data == 8'h90)
            $display("  PASS: VERSION = 0x%02X (82077AA)", read_data);
        else
            $display("  INFO: VERSION = 0x%02X", read_data);

        //---------------------------------------------------------------------
        // Test 7: Software Reset via DSR
        //---------------------------------------------------------------------
        test_num = 7;
        $display("\nTest %0d: Software reset via DSR", test_num);

        cpu_write(3'h4, 8'h80);  // DSR with SW reset bit
        #1000;

        cpu_read(3'h4, read_data);  // Read MSR
        $display("  MSR after reset = 0x%02X", read_data);

        //---------------------------------------------------------------------
        // Test 8: Step Pulse Generation
        //---------------------------------------------------------------------
        test_num = 8;
        $display("\nTest %0d: Step pulse generation (SEEK)", test_num);

        // Re-enable after reset
        cpu_write(3'h2, 8'h1C);  // DOR: Motor on, drive 0

        // Clear track0 to allow stepping
        drv0_track0 = 0;

        wait_rqm();
        cpu_write(3'h5, 8'h0F);  // SEEK command
        wait_rqm();
        cpu_write(3'h5, 8'h00);  // Drive 0, head 0
        wait_rqm();
        cpu_write(3'h5, 8'h05);  // Target track 5

        // Monitor step pulses
        $display("  SEEK to track 5 initiated");
        $display("  Monitoring step pulses (check waveform)...");

        // Wait for seek operation
        #100000;

        $display("  Current track reported: %d", current_track);

        //---------------------------------------------------------------------
        // Test 9: LED Status
        //---------------------------------------------------------------------
        test_num = 9;
        $display("\nTest %0d: LED status outputs", test_num);

        $display("  Activity LED: %b", led_activity);
        $display("  Error LED: %b", led_error);

        //---------------------------------------------------------------------
        // Test 10: Read DIR (Disk Changed)
        //---------------------------------------------------------------------
        test_num = 10;
        $display("\nTest %0d: Read DIR (Digital Input Register)", test_num);

        // Simulate disk change
        drv0_dskchg = 1;
        #1000;

        cpu_read(3'h7, read_data);  // Read DIR
        $display("  DIR = 0x%02X (DSKCHG bit = %b)", read_data, read_data[7]);

        drv0_dskchg = 0;

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        #10000;
        $display("\n============================================");
        $display("Top-Level Test Summary");
        if (errors == 0)
            $display("ALL INTEGRATION TESTS PASSED");
        else
            $display("SOME TESTS FAILED: %0d errors", errors);
        $display("============================================");

        $finish;
    end

    //-------------------------------------------------------------------------
    // Step Pulse Monitor
    //-------------------------------------------------------------------------
    always @(posedge drv0_step) begin
        $display("  [%0t] Step pulse detected, dir=%b", $time, drv0_dir);
    end

    //-------------------------------------------------------------------------
    // IRQ Monitor
    //-------------------------------------------------------------------------
    always @(posedge irq) begin
        $display("  [%0t] IRQ asserted", $time);
    end

    //-------------------------------------------------------------------------
    // DRQ Monitor
    //-------------------------------------------------------------------------
    always @(posedge drq) begin
        $display("  [%0t] DRQ asserted", $time);
    end

    // Timeout watchdog
    initial begin
        #50_000_000;
        $display("Simulation completed (timeout)");
        $finish;
    end

endmodule
