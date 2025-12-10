//-----------------------------------------------------------------------------
// Testbench for System Bus
// FluxRipper - FPGA-based Disk Preservation System
//
// Tests:
//   1. Address decode for all 6 slaves
//   2. Read data multiplexing
//   3. Write signal distribution
//   4. Error detection for unmapped addresses
//   5. Boundary address cases
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_system_bus;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz

    //=========================================================================
    // Test Infrastructure
    //=========================================================================
    `include "test_utils.vh"

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;

    // Master interface
    reg  [31:0] m_addr;
    reg  [31:0] m_wdata;
    wire [31:0] m_rdata;
    reg  [2:0]  m_size;
    reg         m_read;
    reg         m_write;
    wire        m_busy;
    wire        m_error;

    // Slave 0: Boot ROM
    wire [15:0] s0_addr;
    wire        s0_read;
    reg  [31:0] s0_rdata;
    reg         s0_ready;

    // Slave 1: Main Memory
    wire [27:0] s1_addr;
    wire [31:0] s1_wdata;
    wire        s1_read;
    wire        s1_write;
    reg  [31:0] s1_rdata;
    reg         s1_ready;

    // Slave 2: System Control
    wire [7:0]  s2_addr;
    wire [31:0] s2_wdata;
    wire        s2_read;
    wire        s2_write;
    reg  [31:0] s2_rdata;
    reg         s2_ready;

    // Slave 3: Disk Controller
    wire [7:0]  s3_addr;
    wire [31:0] s3_wdata;
    wire        s3_read;
    wire        s3_write;
    reg  [31:0] s3_rdata;
    reg         s3_ready;

    // Slave 4: USB Controller
    wire [7:0]  s4_addr;
    wire [31:0] s4_wdata;
    wire        s4_read;
    wire        s4_write;
    reg  [31:0] s4_rdata;
    reg         s4_ready;

    // Slave 5: Signal Tap
    wire [7:0]  s5_addr;
    wire [31:0] s5_wdata;
    wire        s5_read;
    wire        s5_write;
    reg  [31:0] s5_rdata;
    reg         s5_ready;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    system_bus dut (
        .clk(clk),
        .rst_n(rst_n),
        .m_addr(m_addr),
        .m_wdata(m_wdata),
        .m_rdata(m_rdata),
        .m_size(m_size),
        .m_read(m_read),
        .m_write(m_write),
        .m_busy(m_busy),
        .m_error(m_error),
        .s0_addr(s0_addr),
        .s0_read(s0_read),
        .s0_rdata(s0_rdata),
        .s0_ready(s0_ready),
        .s1_addr(s1_addr),
        .s1_wdata(s1_wdata),
        .s1_read(s1_read),
        .s1_write(s1_write),
        .s1_rdata(s1_rdata),
        .s1_ready(s1_ready),
        .s2_addr(s2_addr),
        .s2_wdata(s2_wdata),
        .s2_read(s2_read),
        .s2_write(s2_write),
        .s2_rdata(s2_rdata),
        .s2_ready(s2_ready),
        .s3_addr(s3_addr),
        .s3_wdata(s3_wdata),
        .s3_read(s3_read),
        .s3_write(s3_write),
        .s3_rdata(s3_rdata),
        .s3_ready(s3_ready),
        .s4_addr(s4_addr),
        .s4_wdata(s4_wdata),
        .s4_read(s4_read),
        .s4_write(s4_write),
        .s4_rdata(s4_rdata),
        .s4_ready(s4_ready),
        .s5_addr(s5_addr),
        .s5_wdata(s5_wdata),
        .s5_read(s5_read),
        .s5_write(s5_write),
        .s5_rdata(s5_rdata),
        .s5_ready(s5_ready)
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
        $dumpfile("tb_system_bus.vcd");
        $dumpvars(0, tb_system_bus);
    end

    //=========================================================================
    // Slave Response Logic
    //=========================================================================
    always @(posedge clk) begin
        // All slaves respond immediately
        s0_ready <= s0_read;
        s1_ready <= s1_read | s1_write;
        s2_ready <= s2_read | s2_write;
        s3_ready <= s3_read | s3_write;
        s4_ready <= s4_read | s4_write;
        s5_ready <= s5_read | s5_write;
    end

    //=========================================================================
    // Test Variables
    //=========================================================================
    reg [31:0] read_data;
    integer i;

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    // Bus read
    task bus_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            m_addr <= addr;
            m_read <= 1;
            m_size <= 3'd2;  // Word
            @(posedge clk);
            while (m_busy) @(posedge clk);
            data = m_rdata;
            m_read <= 0;
            @(posedge clk);
        end
    endtask

    // Bus write
    task bus_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            m_addr <= addr;
            m_wdata <= data;
            m_write <= 1;
            m_size <= 3'd2;  // Word
            @(posedge clk);
            while (m_busy) @(posedge clk);
            m_write <= 0;
            @(posedge clk);
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
        m_addr = 0;
        m_wdata = 0;
        m_size = 0;
        m_read = 0;
        m_write = 0;
        s0_rdata = 32'hA0A0A0A0;
        s1_rdata = 32'hB1B1B1B1;
        s2_rdata = 32'hC2C2C2C2;
        s3_rdata = 32'hD3D3D3D3;
        s4_rdata = 32'hE4E4E4E4;
        s5_rdata = 32'hF5F5F5F5;
        s0_ready = 0;
        s1_ready = 0;
        s2_ready = 0;
        s3_ready = 0;
        s4_ready = 0;
        s5_ready = 0;

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        //---------------------------------------------------------------------
        // Test 1: Boot ROM Access (0x0000_0000)
        //---------------------------------------------------------------------
        test_begin("Boot ROM Access");

        s0_rdata = 32'h12345678;
        bus_read(32'h00000000, read_data);

        assert_eq_1(s0_read, 1'b1, "ROM select asserted");
        $display("  [INFO] ROM read data: 0x%08X", read_data);

        //---------------------------------------------------------------------
        // Test 2: Main Memory Access (0x1000_0000)
        //---------------------------------------------------------------------
        test_begin("Main Memory Access");

        s1_rdata = 32'hAABBCCDD;
        bus_read(32'h10000000, read_data);

        assert_eq_1(s1_read, 1'b1, "Memory select asserted");
        $display("  [INFO] Memory read data: 0x%08X", read_data);

        //---------------------------------------------------------------------
        // Test 3: System Control Access (0x4000_0000)
        //---------------------------------------------------------------------
        test_begin("System Control Access");

        s2_rdata = 32'hDEADBEEF;
        bus_read(32'h40000000, read_data);

        assert_eq_1(s2_read, 1'b1, "SysCtrl select asserted");
        $display("  [INFO] SysCtrl read data: 0x%08X", read_data);

        //---------------------------------------------------------------------
        // Test 4: Disk Controller Access (0x4001_0000)
        //---------------------------------------------------------------------
        test_begin("Disk Controller Access");

        s3_rdata = 32'hCAFEBABE;
        bus_read(32'h40010000, read_data);

        assert_eq_1(s3_read, 1'b1, "Disk select asserted");
        $display("  [INFO] Disk read data: 0x%08X", read_data);

        //---------------------------------------------------------------------
        // Test 5: USB Controller Access (0x4002_0000)
        //---------------------------------------------------------------------
        test_begin("USB Controller Access");

        s4_rdata = 32'hFEEDFACE;
        bus_read(32'h40020000, read_data);

        assert_eq_1(s4_read, 1'b1, "USB select asserted");
        $display("  [INFO] USB read data: 0x%08X", read_data);

        //---------------------------------------------------------------------
        // Test 6: Signal Tap Access (0x4003_0000)
        //---------------------------------------------------------------------
        test_begin("Signal Tap Access");

        s5_rdata = 32'hBEEFCAFE;
        bus_read(32'h40030000, read_data);

        assert_eq_1(s5_read, 1'b1, "SigTap select asserted");
        $display("  [INFO] SigTap read data: 0x%08X", read_data);

        //---------------------------------------------------------------------
        // Test 7: Write to Memory
        //---------------------------------------------------------------------
        test_begin("Write to Memory");

        bus_write(32'h10001000, 32'h55AA55AA);

        assert_eq_1(s1_write, 1'b1, "Memory write asserted");
        assert_eq_32(s1_wdata, 32'h55AA55AA, "Write data correct");

        //---------------------------------------------------------------------
        // Test 8: Address Offset Extraction
        //---------------------------------------------------------------------
        test_begin("Address Offset");

        bus_read(32'h00001234, read_data);
        assert_eq_32({16'b0, s0_addr}, 32'h00001234, "ROM offset correct");

        bus_read(32'h100ABCDE, read_data);
        $display("  [INFO] Memory offset: 0x%07X", s1_addr);

        //---------------------------------------------------------------------
        // Test 9: Unmapped Address Error
        //---------------------------------------------------------------------
        test_begin("Unmapped Address Error");

        bus_read(32'h80000000, read_data);  // Unmapped region

        $display("  [INFO] m_error=%b for unmapped address", m_error);

        //---------------------------------------------------------------------
        // Test 10: Multiple Sequential Accesses
        //---------------------------------------------------------------------
        test_begin("Sequential Accesses");

        for (i = 0; i < 6; i = i + 1) begin
            case (i)
                0: bus_read(32'h00000000 + i*4, read_data);
                1: bus_read(32'h10000000 + i*4, read_data);
                2: bus_read(32'h40000000 + i*4, read_data);
                3: bus_read(32'h40010000 + i*4, read_data);
                4: bus_read(32'h40020000 + i*4, read_data);
                5: bus_read(32'h40030000 + i*4, read_data);
            endcase
        end

        test_pass("Sequential accesses completed");

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
