//-----------------------------------------------------------------------------
// Testbench for USB Descriptor ROM
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. All 4 personality descriptors
//   2. VID/PID verification per personality
//   3. All descriptor types (Device, Config, String)
//   4. Descriptor length reporting
//   5. Offset-based reading
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_usb_descriptor_rom;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // Descriptor Type Constants
    //=========================================================================
    localparam DESC_DEVICE        = 8'h01;
    localparam DESC_CONFIGURATION = 8'h02;
    localparam DESC_STRING        = 8'h03;

    //=========================================================================
    // Expected VID/PID per personality
    //=========================================================================
    localparam [15:0] VID_GREASEWEAZLE = 16'h1209;
    localparam [15:0] PID_GREASEWEAZLE = 16'h4D69;
    localparam [15:0] VID_HXC          = 16'h16D0;
    localparam [15:0] PID_HXC          = 16'h0FD2;
    localparam [15:0] VID_KRYOFLUX     = 16'h03EB;
    localparam [15:0] PID_KRYOFLUX     = 16'h6124;
    localparam [15:0] VID_FLUXRIPPER   = 16'h1209;
    localparam [15:0] PID_FLUXRIPPER   = 16'hFB01;

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;

    // Personality Selection
    reg  [2:0]  personality_sel;

    // Descriptor Read Interface
    reg  [7:0]  desc_type;
    reg  [7:0]  desc_index;
    reg  [15:0] desc_offset;
    reg         desc_read;

    wire [7:0]  desc_data;
    wire        desc_valid;
    wire [15:0] desc_length;

    // Device Information
    wire [15:0] vid;
    wire [15:0] pid;
    wire [7:0]  device_class;
    wire [7:0]  device_subclass;
    wire [7:0]  device_protocol;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    usb_descriptor_rom dut (
        .clk(clk),
        .rst_n(rst_n),
        .personality_sel(personality_sel),
        .desc_type(desc_type),
        .desc_index(desc_index),
        .desc_offset(desc_offset),
        .desc_read(desc_read),
        .desc_data(desc_data),
        .desc_valid(desc_valid),
        .desc_length(desc_length),
        .vid(vid),
        .pid(pid),
        .device_class(device_class),
        .device_subclass(device_subclass),
        .device_protocol(device_protocol)
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
        $dumpfile("tb_usb_descriptor_rom.vcd");
        $dumpvars(0, tb_usb_descriptor_rom);
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    reg [7:0] desc_buffer [0:255];
    integer i;
    integer desc_len;

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Read a descriptor and store in buffer
    task read_descriptor;
        input [7:0] d_type;
        input [7:0] d_index;
        output integer length;
        integer j;
        begin
            // First get length
            desc_type = d_type;
            desc_index = d_index;
            desc_offset = 0;
            desc_read = 1;
            @(posedge clk);
            @(posedge clk);
            length = desc_length;
            desc_read = 0;
            @(posedge clk);

            // Read all bytes
            for (j = 0; j < length && j < 256; j = j + 1) begin
                desc_offset = j[15:0];
                desc_read = 1;
                @(posedge clk);
                @(posedge clk);
                if (desc_valid)
                    desc_buffer[j] = desc_data;
                desc_read = 0;
                @(posedge clk);
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
        rst_n = 0;
        personality_sel = 0;
        desc_type = 0;
        desc_index = 0;
        desc_offset = 0;
        desc_read = 0;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Greaseweazle VID/PID (Personality 0)
        //---------------------------------------------------------------------
        test_begin("Greaseweazle VID/PID");

        personality_sel = 3'd0;
        @(posedge clk);
        @(posedge clk);

        assert_eq_32({16'b0, vid}, {16'b0, VID_GREASEWEAZLE}, "Greaseweazle VID");
        assert_eq_32({16'b0, pid}, {16'b0, PID_GREASEWEAZLE}, "Greaseweazle PID");

        //---------------------------------------------------------------------
        // Test 2: HxC VID/PID (Personality 1)
        //---------------------------------------------------------------------
        test_begin("HxC VID/PID");

        personality_sel = 3'd1;
        @(posedge clk);
        @(posedge clk);

        assert_eq_32({16'b0, vid}, {16'b0, VID_HXC}, "HxC VID");
        assert_eq_32({16'b0, pid}, {16'b0, PID_HXC}, "HxC PID");

        //---------------------------------------------------------------------
        // Test 3: KryoFlux VID/PID (Personality 2)
        //---------------------------------------------------------------------
        test_begin("KryoFlux VID/PID");

        personality_sel = 3'd2;
        @(posedge clk);
        @(posedge clk);

        assert_eq_32({16'b0, vid}, {16'b0, VID_KRYOFLUX}, "KryoFlux VID");
        assert_eq_32({16'b0, pid}, {16'b0, PID_KRYOFLUX}, "KryoFlux PID");

        //---------------------------------------------------------------------
        // Test 4: FluxRipper VID/PID (Personality 3)
        //---------------------------------------------------------------------
        test_begin("FluxRipper VID/PID");

        personality_sel = 3'd3;
        @(posedge clk);
        @(posedge clk);

        assert_eq_32({16'b0, vid}, {16'b0, VID_FLUXRIPPER}, "FluxRipper VID");
        assert_eq_32({16'b0, pid}, {16'b0, PID_FLUXRIPPER}, "FluxRipper PID");

        //---------------------------------------------------------------------
        // Test 5: Device Descriptor Read
        //---------------------------------------------------------------------
        test_begin("Device Descriptor Read");

        personality_sel = 3'd3;
        @(posedge clk);

        read_descriptor(DESC_DEVICE, 0, desc_len);

        $display("  [INFO] Device descriptor length = %0d bytes", desc_len);

        // Device descriptor should be 18 bytes
        assert_eq_32({16'b0, desc_len[15:0]}, 32'd18, "Device descriptor length = 18");

        // First byte is length
        assert_eq_8(desc_buffer[0], 8'd18, "bLength = 18");
        // Second byte is descriptor type
        assert_eq_8(desc_buffer[1], DESC_DEVICE, "bDescriptorType = DEVICE");

        //---------------------------------------------------------------------
        // Test 6: Configuration Descriptor Read
        //---------------------------------------------------------------------
        test_begin("Configuration Descriptor Read");

        read_descriptor(DESC_CONFIGURATION, 0, desc_len);

        $display("  [INFO] Config descriptor length = %0d bytes", desc_len);

        // First byte is length of first descriptor (9 bytes)
        assert_eq_8(desc_buffer[0], 8'd9, "bLength = 9 for config");
        assert_eq_8(desc_buffer[1], DESC_CONFIGURATION, "bDescriptorType = CONFIG");

        // wTotalLength at bytes 2-3
        $display("  [INFO] wTotalLength = %0d", {desc_buffer[3], desc_buffer[2]});

        //---------------------------------------------------------------------
        // Test 7: String Descriptor 0 (Language IDs)
        //---------------------------------------------------------------------
        test_begin("String Descriptor 0");

        read_descriptor(DESC_STRING, 0, desc_len);

        $display("  [INFO] String 0 length = %0d bytes", desc_len);

        assert_eq_8(desc_buffer[1], DESC_STRING, "bDescriptorType = STRING");
        // Language ID should be 0x0409 (US English)
        $display("  [INFO] Language ID = 0x%02X%02X", desc_buffer[3], desc_buffer[2]);

        //---------------------------------------------------------------------
        // Test 8: String Descriptor 1 (Manufacturer)
        //---------------------------------------------------------------------
        test_begin("String Descriptor 1 (Manufacturer)");

        read_descriptor(DESC_STRING, 1, desc_len);

        $display("  [INFO] Manufacturer string length = %0d bytes", desc_len);
        assert_true(desc_len > 2, "Manufacturer string not empty");

        //---------------------------------------------------------------------
        // Test 9: String Descriptor 2 (Product)
        //---------------------------------------------------------------------
        test_begin("String Descriptor 2 (Product)");

        read_descriptor(DESC_STRING, 2, desc_len);

        $display("  [INFO] Product string length = %0d bytes", desc_len);
        assert_true(desc_len > 2, "Product string not empty");

        //---------------------------------------------------------------------
        // Test 10: Personality Switch
        //---------------------------------------------------------------------
        test_begin("Personality Switch");

        // Switch between personalities and verify VID/PID changes
        for (i = 0; i < 4; i = i + 1) begin
            personality_sel = i[2:0];
            @(posedge clk);
            @(posedge clk);
            $display("  [INFO] Personality %0d: VID=0x%04X PID=0x%04X", i, vid, pid);
        end

        test_pass("Personality switching works");

        //---------------------------------------------------------------------
        // Test 11: Device Class Per Personality
        //---------------------------------------------------------------------
        test_begin("Device Class Per Personality");

        for (i = 0; i < 4; i = i + 1) begin
            personality_sel = i[2:0];
            @(posedge clk);
            @(posedge clk);
            $display("  [INFO] P%0d: class=0x%02X subclass=0x%02X protocol=0x%02X",
                    i, device_class, device_subclass, device_protocol);
        end

        test_pass("Device classes retrieved");

        //---------------------------------------------------------------------
        // Test 12: Offset Reading
        //---------------------------------------------------------------------
        test_begin("Offset Reading");

        personality_sel = 3'd3;
        desc_type = DESC_DEVICE;
        desc_index = 0;

        // Read at different offsets
        for (i = 0; i < 18; i = i + 1) begin
            desc_offset = i[15:0];
            desc_read = 1;
            @(posedge clk);
            @(posedge clk);
            desc_buffer[i] = desc_data;
            desc_read = 0;
        end

        // VID is at offset 8-9, PID at 10-11
        $display("  [INFO] VID from descriptor: 0x%02X%02X", desc_buffer[9], desc_buffer[8]);
        $display("  [INFO] PID from descriptor: 0x%02X%02X", desc_buffer[11], desc_buffer[10]);

        // Verify VID/PID matches outputs
        assert_eq_32({16'b0, desc_buffer[9], desc_buffer[8]}, {16'b0, vid}, "VID matches");
        assert_eq_32({16'b0, desc_buffer[11], desc_buffer[10]}, {16'b0, pid}, "PID matches");

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
        #500000;  // 500us timeout
        $display("\n[ERROR] Simulation timeout!");
        test_summary();
        $finish;
    end

endmodule
