`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_peripherals.v - Layer 5 Testbench: Real Peripheral Controllers
//
// Tests actual peripheral RTL through the full JTAG debug path + bus fabric.
// Validates: Disk Controller, USB Controller, Signal Tap
//
// Created: 2025-12-07 22:15
//-----------------------------------------------------------------------------

module tb_peripherals;

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

    // Disk physical interface
    wire [31:0] dma_addr;
    wire [31:0] dma_wdata;
    wire        dma_write;
    wire        motor_on;
    wire        head_sel;
    wire        dir;
    wire        step;
    reg         flux_in;
    reg         index_in;

    // USB physical interface
    wire        usb_connected;
    wire        usb_configured;

    // Signal Tap probes
    reg [31:0]  probes;

    // Test control
    integer     errors;
    integer     pass_count;
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
    // Real Peripheral Controllers (Layer 5 specific)
    //=========================================================================

    disk_controller u_disk (
        .clk(clk),
        .rst_n(rst_n),
        .addr(disk_addr),
        .wdata(disk_wdata),
        .read(disk_read),
        .write(disk_write),
        .rdata(disk_rdata),
        .ready(disk_ready),
        .dma_addr(dma_addr),
        .dma_wdata(dma_wdata),
        .dma_write(dma_write),
        .dma_ready(1'b1),
        .flux_in(flux_in),
        .index_in(index_in),
        .motor_on(motor_on),
        .head_sel(head_sel),
        .dir(dir),
        .step(step)
    );

    usb_controller u_usb (
        .clk(clk),
        .rst_n(rst_n),
        .addr(usb_addr),
        .wdata(usb_wdata),
        .read(usb_read),
        .write(usb_write),
        .rdata(usb_rdata),
        .ready(usb_ready),
        .usb_connected(usb_connected),
        .usb_configured(usb_configured)
    );

    signal_tap #(
        .BUFFER_DEPTH(64),
        .PROBE_WIDTH(32)
    ) u_sigtap (
        .clk(clk),
        .rst_n(rst_n),
        .addr(sigtap_addr),
        .wdata(sigtap_wdata),
        .read(sigtap_read),
        .write(sigtap_write),
        .rdata(sigtap_rdata),
        .ready(sigtap_ready),
        .probes(probes)
    );

    //=========================================================================
    // Stubs for ROM/RAM/SysCtrl (keeping Layer 3 stubs)
    //=========================================================================
    reg [31:0] rom_mem [0:16383];
    reg [31:0] rom_rdata_reg;
    initial begin
        for (i = 0; i < 16384; i = i + 1)
            rom_mem[i] = 32'hB0070000 + i;
        rom_mem[0] = 32'h13000000;
    end
    always @(posedge clk) begin
        if (rom_read)
            rom_rdata_reg <= rom_mem[rom_addr[15:2]];
    end
    assign rom_rdata = rom_rdata_reg;
    assign rom_ready = 1'b1;

    reg [31:0] ram_mem [0:1023];
    reg [31:0] ram_rdata_reg;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            ram_mem[i] = 32'h5A000000 + i;
    end
    always @(posedge clk) begin
        if (ram_read)
            ram_rdata_reg <= ram_mem[ram_addr[11:2]];
        if (ram_write)
            ram_mem[ram_addr[11:2]] <= ram_wdata;
    end
    assign ram_rdata = ram_rdata_reg;
    assign ram_ready = 1'b1;

    reg [31:0] sysctrl_id = 32'hFB010100;
    assign sysctrl_rdata = (sysctrl_addr == 8'h00) ? sysctrl_id : 32'h0;
    assign sysctrl_ready = 1'b1;

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

    task jtag_mem_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            dmi_reg_write(7'h38, 32'h00000404);
            dmi_reg_write(7'h39, addr);
            repeat(20) @(posedge clk);
            dmi_reg_read(7'h3C, data);
        end
    endtask

    task jtag_mem_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            dmi_reg_write(7'h38, 32'h00000004);
            dmi_reg_write(7'h39, addr);
            dmi_reg_write(7'h3C, data);
            repeat(20) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        $display("");
        $display("===========================================");
        $display("  Layer 5: Peripheral Subsystems Test");
        $display("  FluxRipper Simulation");
        $display("===========================================");
        $display("");

        errors = 0;
        pass_count = 0;
        test_num = 0;
        tms = 1;
        tdi = 0;
        trst_n = 0;
        rst_n = 0;
        flux_in = 0;
        index_in = 0;
        probes = 32'h00000000;

        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(TCK_PERIOD * 2);
        trst_n = 1;
        #(TCK_PERIOD * 2);

        jtag_reset;

        //---------------------------------------------------------------------
        // Test 1: Disk Controller Status Read
        //---------------------------------------------------------------------
        test_num = 1;
        $display("Test %0d: Disk Controller Status Read", test_num);

        jtag_mem_read(32'h40010000, captured_data);

        if (captured_data[0] != 1'b1) begin
            $display("  FAIL: DISK_STATUS ready=0 (expected 1)");
            $display("        Got: 0x%08X", captured_data);
            errors = errors + 1;
        end else begin
            $display("  DISK_STATUS = 0x%08X (ready=1)", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 2: Disk Motor Control
        //---------------------------------------------------------------------
        test_num = 2;
        $display("Test %0d: Disk Motor Control", test_num);

        // Turn motor on (bit 2)
        jtag_mem_write(32'h40010004, 32'h00000004);
        repeat(20) @(posedge clk);

        if (motor_on != 1'b1) begin
            $display("  FAIL: motor_on=%b (expected 1)", motor_on);
            errors = errors + 1;
        end else begin
            $display("  Motor ON: motor_on=%b", motor_on);
        end

        // Turn motor off
        jtag_mem_write(32'h40010004, 32'h00000000);
        repeat(20) @(posedge clk);

        if (motor_on != 1'b0) begin
            $display("  FAIL: motor_on=%b (expected 0)", motor_on);
            errors = errors + 1;
        end else begin
            $display("  Motor OFF: motor_on=%b", motor_on);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 3: Disk Index Counter
        //---------------------------------------------------------------------
        test_num = 3;
        $display("Test %0d: Disk Index Counter", test_num);

        // Generate 3 index pulses
        repeat (3) begin
            index_in = 1;
            repeat(10) @(posedge clk);
            index_in = 0;
            repeat(100) @(posedge clk);
        end

        jtag_mem_read(32'h40010010, captured_data);

        if (captured_data != 32'd3) begin
            $display("  FAIL: INDEX_CNT=%0d (expected 3)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  INDEX_CNT = %0d pulses", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 4: USB Controller ID Read
        //---------------------------------------------------------------------
        test_num = 4;
        $display("Test %0d: USB Controller ID Read", test_num);

        jtag_mem_read(32'h40020000, captured_data);

        if (captured_data != 32'h05B20001) begin
            $display("  FAIL: USB_ID=0x%08X (expected 0x05B20001)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  USB_ID = 0x%08X", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 5: USB Connection Control
        //---------------------------------------------------------------------
        test_num = 5;
        $display("Test %0d: USB Connection Control", test_num);

        // Enable USB and force configured
        jtag_mem_write(32'h40020008, 32'h00000003);
        repeat(20) @(posedge clk);

        if (usb_connected != 1'b1 || usb_configured != 1'b1) begin
            $display("  FAIL: connected=%b configured=%b", usb_connected, usb_configured);
            errors = errors + 1;
        end else begin
            $display("  USB connected=%b configured=%b", usb_connected, usb_configured);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 6: Signal Tap ID Read
        //---------------------------------------------------------------------
        test_num = 6;
        $display("Test %0d: Signal Tap ID Read", test_num);

        jtag_mem_read(32'h40030000, captured_data);

        if (captured_data != 32'h51670001) begin
            $display("  FAIL: SIGTAP_ID=0x%08X (expected 0x51670001)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  SIGTAP_ID = 0x%08X", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 7: Signal Tap Capture
        //---------------------------------------------------------------------
        test_num = 7;
        $display("Test %0d: Signal Tap Capture", test_num);

        // Set trigger value and mask
        jtag_mem_write(32'h4003000C, 32'hDEADBEEF);  // TRIGGER
        jtag_mem_write(32'h40030010, 32'hFFFFFFFF);  // TRIG_MASK

        // Arm capture
        jtag_mem_write(32'h40030008, 32'h00000001);  // CONTROL arm=1
        repeat(20) @(posedge clk);

        // Check armed status
        jtag_mem_read(32'h40030004, captured_data);
        if (captured_data[0] != 1'b1) begin
            $display("  FAIL: Signal Tap not armed");
            errors = errors + 1;
        end else begin
            $display("  Signal Tap armed: STATUS=0x%08X", captured_data);
        end

        // Generate trigger condition
        probes = 32'hDEADBEEF;
        repeat(200) @(posedge clk);

        // Check triggered status
        jtag_mem_read(32'h40030004, captured_data);
        if (captured_data[3] != 1'b1) begin
            $display("  FAIL: Signal Tap not triggered, STATUS=0x%08X", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Signal Tap triggered: STATUS=0x%08X", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Test 8: Disk DMA Configuration
        //---------------------------------------------------------------------
        test_num = 8;
        $display("Test %0d: Disk DMA Configuration", test_num);

        jtag_mem_write(32'h40010008, 32'h10000000);  // DMA_ADDR
        jtag_mem_write(32'h4001000C, 32'h00001000);  // DMA_LEN

        jtag_mem_read(32'h40010008, captured_data);
        if (captured_data != 32'h10000000) begin
            $display("  FAIL: DMA_ADDR=0x%08X", captured_data);
            errors = errors + 1;
        end else begin
            $display("  DMA_ADDR = 0x%08X", captured_data);
        end

        jtag_mem_read(32'h4001000C, captured_data);
        if (captured_data != 32'h00001000) begin
            $display("  FAIL: DMA_LEN=0x%08X", captured_data);
            errors = errors + 1;
        end else begin
            $display("  DMA_LEN = 0x%08X", captured_data);
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("");
        $display("===========================================");
        $display("  Layer 5 Test Summary");
        $display("===========================================");
        $display("  Tests Run:    %0d", test_num);
        $display("  Tests Passed: %0d", pass_count);
        $display("  Tests Failed: %0d", errors);
        $display("===========================================");

        if (errors == 0) begin
            $display("  ALL TESTS PASSED!");
        end else begin
            $display("  SOME TESTS FAILED!");
        end

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
        $dumpfile("tb_peripherals.vcd");
        $dumpvars(0, tb_peripherals);
    end

endmodule
