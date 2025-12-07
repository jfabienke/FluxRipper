`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_system_bus.v - Layer 3 Testbench: Full Debug Path + Bus Fabric
//
// Tests end-to-end JTAG access through system bus to multiple peripherals.
// Validates address decoding and memory-mapped I/O.
//
// Created: 2025-12-07 21:25
//-----------------------------------------------------------------------------

module tb_system_bus;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter TCK_PERIOD = 100;    // JTAG clock (10 MHz)
    parameter CLK_PERIOD = 10;     // System clock (100 MHz)

    //=========================================================================
    // Signals
    //=========================================================================
    // JTAG interface
    reg         tck;
    reg         tms;
    reg         tdi;
    reg         trst_n;
    wire        tdo;

    // System clock/reset
    reg         clk;
    reg         rst_n;

    // DMI interface (internal)
    wire [6:0]  dmi_addr;
    wire [31:0] dmi_wdata;
    wire [1:0]  dmi_op;
    wire        dmi_req;
    wire [31:0] dmi_rdata;
    wire [1:0]  dmi_resp;
    wire        dmi_ack;

    // System bus master (DM -> Bus)
    wire [31:0] sb_addr;
    wire [31:0] sb_wdata;
    wire [31:0] sb_rdata;
    wire [2:0]  sb_size;
    wire        sb_read;
    wire        sb_write;
    wire        sb_busy;
    wire        sb_error;

    // Slave interfaces
    wire [15:0] rom_addr;
    wire        rom_read;
    wire [31:0] rom_rdata;
    wire        rom_ready;

    wire [27:0] ram_addr;
    wire [31:0] ram_wdata;
    wire        ram_read;
    wire        ram_write;
    wire [31:0] ram_rdata;
    wire        ram_ready;

    wire [7:0]  sysctrl_addr;
    wire [31:0] sysctrl_wdata;
    wire        sysctrl_read;
    wire        sysctrl_write;
    wire [31:0] sysctrl_rdata;
    wire        sysctrl_ready;

    wire [7:0]  disk_addr;
    wire [31:0] disk_wdata;
    wire        disk_read;
    wire        disk_write;
    wire [31:0] disk_rdata;
    wire        disk_ready;

    wire [7:0]  usb_addr;
    wire [31:0] usb_wdata;
    wire        usb_read;
    wire        usb_write;
    wire [31:0] usb_rdata;
    wire        usb_ready;

    wire [7:0]  sigtap_addr;
    wire [31:0] sigtap_wdata;
    wire        sigtap_read;
    wire        sigtap_write;
    wire [31:0] sigtap_rdata;
    wire        sigtap_ready;

    // TAP internal signals
    wire [4:0]  ir_value;
    wire        dr_capture, dr_shift, dr_update;
    wire        tap_tdo, dtm_tdo;

    assign tdo = (ir_value == 5'h10 || ir_value == 5'h11) ? dtm_tdo : tap_tdo;

    // Test control
    integer     errors;
    integer     test_num;
    integer     i;
    reg [31:0]  captured_data;

    //=========================================================================
    // DUT Instantiation: Full Debug Chain
    //=========================================================================
    jtag_tap_controller #(
        .IDCODE(32'hFB010001),
        .IR_LENGTH(5)
    ) tap (
        .tck(tck),
        .tms(tms),
        .tdi(tdi),
        .tdo(tap_tdo),
        .trst_n(trst_n),
        .ir_value(ir_value),
        .dr_capture(dr_capture),
        .dr_shift(dr_shift),
        .dr_update(dr_update)
    );

    jtag_dtm dtm (
        .tck(tck),
        .trst_n(trst_n),
        .ir_value(ir_value),
        .dr_capture(dr_capture),
        .dr_shift(dr_shift),
        .dr_update(dr_update),
        .tdi(tdi),
        .tdo(dtm_tdo),
        .dmi_addr(dmi_addr),
        .dmi_wdata(dmi_wdata),
        .dmi_op(dmi_op),
        .dmi_req(dmi_req),
        .dmi_rdata(dmi_rdata),
        .dmi_resp(dmi_resp),
        .dmi_ack(dmi_ack)
    );

    debug_module dm (
        .clk(clk),
        .rst_n(rst_n),
        .dmi_addr(dmi_addr),
        .dmi_wdata(dmi_wdata),
        .dmi_op(dmi_op),
        .dmi_req(dmi_req),
        .dmi_rdata(dmi_rdata),
        .dmi_resp(dmi_resp),
        .dmi_ack(dmi_ack),
        .sbaddr(sb_addr),
        .sbdata_o(sb_wdata),
        .sbdata_i(sb_rdata),
        .sbsize(sb_size),
        .sbread(sb_read),
        .sbwrite(sb_write),
        .sbbusy(sb_busy),
        .sberror(sb_error)
    );

    system_bus bus (
        .clk(clk),
        .rst_n(rst_n),
        .m_addr(sb_addr),
        .m_wdata(sb_wdata),
        .m_rdata(sb_rdata),
        .m_size(sb_size),
        .m_read(sb_read),
        .m_write(sb_write),
        .m_busy(sb_busy),
        .m_error(sb_error),
        // ROM
        .s0_addr(rom_addr),
        .s0_read(rom_read),
        .s0_rdata(rom_rdata),
        .s0_ready(rom_ready),
        // RAM
        .s1_addr(ram_addr),
        .s1_wdata(ram_wdata),
        .s1_read(ram_read),
        .s1_write(ram_write),
        .s1_rdata(ram_rdata),
        .s1_ready(ram_ready),
        // System Control
        .s2_addr(sysctrl_addr),
        .s2_wdata(sysctrl_wdata),
        .s2_read(sysctrl_read),
        .s2_write(sysctrl_write),
        .s2_rdata(sysctrl_rdata),
        .s2_ready(sysctrl_ready),
        // Disk Controller
        .s3_addr(disk_addr),
        .s3_wdata(disk_wdata),
        .s3_read(disk_read),
        .s3_write(disk_write),
        .s3_rdata(disk_rdata),
        .s3_ready(disk_ready),
        // USB Controller
        .s4_addr(usb_addr),
        .s4_wdata(usb_wdata),
        .s4_read(usb_read),
        .s4_write(usb_write),
        .s4_rdata(usb_rdata),
        .s4_ready(usb_ready),
        // Signal Tap
        .s5_addr(sigtap_addr),
        .s5_wdata(sigtap_wdata),
        .s5_read(sigtap_read),
        .s5_write(sigtap_write),
        .s5_rdata(sigtap_rdata),
        .s5_ready(sigtap_ready)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial tck = 0;
    always #(TCK_PERIOD/2) tck = ~tck;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //=========================================================================
    // Include JTAG Driver Tasks
    //=========================================================================
    `include "../common/jtag_driver.vh"

    //=========================================================================
    // Mock Peripherals
    //=========================================================================

    // Boot ROM (read-only, pre-initialized)
    reg [31:0] rom_mem [0:16383];  // 64KB
    reg [31:0] rom_rdata_reg;
    initial begin
        for (i = 0; i < 16384; i = i + 1)
            rom_mem[i] = 32'hB0070000 + i;  // Boot ROM pattern
        rom_mem[0] = 32'h13000000;  // NOP instruction at reset vector
    end
    always @(posedge clk) begin
        if (rom_read)
            rom_rdata_reg <= rom_mem[rom_addr[15:2]];
    end
    assign rom_rdata = rom_rdata_reg;
    assign rom_ready = 1'b1;

    // Main RAM (read/write)
    reg [31:0] ram_mem [0:1023];  // 4KB for simulation
    reg [31:0] ram_rdata_reg;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            ram_mem[i] = 32'h5A000000 + i;  // RAM pattern
    end
    always @(posedge clk) begin
        if (ram_read)
            ram_rdata_reg <= ram_mem[ram_addr[11:2]];
        if (ram_write)
            ram_mem[ram_addr[11:2]] <= ram_wdata;
    end
    assign ram_rdata = ram_rdata_reg;
    assign ram_ready = 1'b1;

    // System Control (simple ID register)
    reg [31:0] sysctrl_id = 32'hFB010100;  // FluxRipper v1.0
    assign sysctrl_rdata = (sysctrl_addr == 8'h00) ? sysctrl_id : 32'h0;
    assign sysctrl_ready = 1'b1;

    // Disk Controller (stub with status register)
    reg [31:0] disk_status = 32'h00000001;  // bit 0 = ready
    reg [31:0] disk_ctrl = 32'h0;
    always @(posedge clk) begin
        if (disk_write && disk_addr == 8'h04)
            disk_ctrl <= disk_wdata;
    end
    assign disk_rdata = (disk_addr == 8'h00) ? disk_status :
                        (disk_addr == 8'h04) ? disk_ctrl : 32'h0;
    assign disk_ready = 1'b1;

    // USB Controller (stub)
    assign usb_rdata = 32'h05B00000;  // USB ID
    assign usb_ready = 1'b1;

    // Signal Tap (stub)
    assign sigtap_rdata = 32'h51670000;  // SigTap ID
    assign sigtap_ready = 1'b1;

    //=========================================================================
    // High-Level Memory Access Tasks
    //=========================================================================

    task dmi_reg_read;
        input  [6:0]  addr;
        output [31:0] data;
        reg [40:0] dmi_in, dmi_out;
        begin
            shift_ir(5'h11);
            dmi_in = {addr, 32'h0, 2'b01};
            shift_dr_41(dmi_in, dmi_out);
            repeat(10) @(posedge clk);
            dmi_in = 41'h0;
            shift_dr_41(dmi_in, dmi_out);
            data = dmi_out[33:2];
        end
    endtask

    task dmi_reg_write;
        input [6:0]  addr;
        input [31:0] data;
        reg [40:0] dmi_in, dmi_out;
        begin
            shift_ir(5'h11);
            dmi_in = {addr, data, 2'b10};
            shift_dr_41(dmi_in, dmi_out);
            repeat(10) @(posedge clk);
            dmi_in = 41'h0;
            shift_dr_41(dmi_in, dmi_out);
        end
    endtask

    // Memory read via JTAG debug path
    task jtag_mem_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            // Configure sbcs for 32-bit, read-on-addr
            dmi_reg_write(7'h38, 32'h00000404);
            // Write address (triggers read)
            dmi_reg_write(7'h39, addr);
            repeat(20) @(posedge clk);
            // Read result
            dmi_reg_read(7'h3C, data);
        end
    endtask

    // Memory write via JTAG debug path
    task jtag_mem_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // Configure sbcs for 32-bit
            dmi_reg_write(7'h38, 32'h00000004);
            // Write address
            dmi_reg_write(7'h39, addr);
            // Write data (triggers bus write)
            dmi_reg_write(7'h3C, data);
            repeat(20) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        $display("");
        $display("========================================");
        $display("  Layer 3: System Bus Integration");
        $display("  FluxRipper Simulation");
        $display("========================================");
        $display("");

        errors = 0;
        test_num = 0;
        tms = 1;
        tdi = 0;
        trst_n = 0;
        rst_n = 0;

        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(TCK_PERIOD * 2);
        trst_n = 1;
        #(TCK_PERIOD * 2);

        jtag_reset;

        //---------------------------------------------------------------------
        // Test 1: Read Boot ROM
        //---------------------------------------------------------------------
        test_num = 1;
        $display("Test %0d: Read Boot ROM (0x0000_0000)", test_num);

        jtag_mem_read(32'h00000000, captured_data);

        if (captured_data != 32'h13000000) begin
            $display("  FAIL: ROM[0] = 0x%08X (expected 0x13000000)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  ROM[0] = 0x%08X (NOP instruction)", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 2: Read/Write Main RAM
        //---------------------------------------------------------------------
        test_num = 2;
        $display("Test %0d: Read/Write RAM (0x1000_0000)", test_num);

        jtag_mem_write(32'h10000000, 32'hCAFEBABE);
        jtag_mem_read(32'h10000000, captured_data);

        if (captured_data != 32'hCAFEBABE) begin
            $display("  FAIL: RAM[0] = 0x%08X (expected 0xCAFEBABE)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Write 0xCAFEBABE, read: 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 3: Read System Control ID
        //---------------------------------------------------------------------
        test_num = 3;
        $display("Test %0d: Read System Control (0x4000_0000)", test_num);

        jtag_mem_read(32'h40000000, captured_data);

        if (captured_data != 32'hFB010100) begin
            $display("  FAIL: SYSCTRL_ID = 0x%08X (expected 0xFB010100)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  SYSCTRL_ID = 0x%08X (FluxRipper v1.0)", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 4: Disk Controller access
        //---------------------------------------------------------------------
        test_num = 4;
        $display("Test %0d: Disk Controller (0x4001_0000)", test_num);

        // Read status
        jtag_mem_read(32'h40010000, captured_data);
        if (captured_data[0] != 1'b1) begin
            $display("  FAIL: DISK_STATUS ready bit not set");
            errors = errors + 1;
        end else begin
            $display("  DISK_STATUS = 0x%08X (ready=1)", captured_data);
        end

        // Write control register
        jtag_mem_write(32'h40010004, 32'h0000000F);
        jtag_mem_read(32'h40010004, captured_data);
        if (captured_data != 32'h0000000F) begin
            $display("  FAIL: DISK_CTRL = 0x%08X (expected 0x0000000F)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  DISK_CTRL = 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 5: USB Controller access
        //---------------------------------------------------------------------
        test_num = 5;
        $display("Test %0d: USB Controller (0x4002_0000)", test_num);

        jtag_mem_read(32'h40020000, captured_data);

        if (captured_data != 32'h05B00000) begin
            $display("  FAIL: USB read = 0x%08X (expected 0x05B00000)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  USB_ID = 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 6: Signal Tap access
        //---------------------------------------------------------------------
        test_num = 6;
        $display("Test %0d: Signal Tap (0x4003_0000)", test_num);

        jtag_mem_read(32'h40030000, captured_data);

        if (captured_data != 32'h51670000) begin
            $display("  FAIL: SIGTAP read = 0x%08X (expected 0x51670000)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  SIGTAP_ID = 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 7: Multiple RAM locations
        //---------------------------------------------------------------------
        test_num = 7;
        $display("Test %0d: Multiple RAM writes/reads", test_num);

        jtag_mem_write(32'h10000100, 32'h11111111);
        jtag_mem_write(32'h10000104, 32'h22222222);
        jtag_mem_write(32'h10000108, 32'h33333333);

        jtag_mem_read(32'h10000100, captured_data);
        if (captured_data != 32'h11111111) errors = errors + 1;

        jtag_mem_read(32'h10000104, captured_data);
        if (captured_data != 32'h22222222) errors = errors + 1;

        jtag_mem_read(32'h10000108, captured_data);
        if (captured_data != 32'h33333333) errors = errors + 1;

        if (errors == 0) begin
            $display("  3 locations verified");
            $display("  PASS");
        end else begin
            $display("  FAIL");
        end

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("");
        $display("========================================");
        if (errors == 0) begin
            $display("  ALL %0d TESTS PASSED", test_num);
        end else begin
            $display("  FAILED: %0d errors in %0d tests", errors, test_num);
        end
        $display("========================================");
        $display("");

        #(CLK_PERIOD * 100);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #(TCK_PERIOD * 1000000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_system_bus.vcd");
        $dumpvars(0, tb_system_bus);
    end

endmodule
