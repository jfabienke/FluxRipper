`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_debug_module.v - Layer 2 Testbench: TAP + DTM + Debug Module
//
// Tests JTAG access to Debug Module and system bus operations.
// Validates debug registers and memory read/write via JTAG.
//
// Created: 2025-12-07 21:35
//-----------------------------------------------------------------------------

module tb_debug_module;

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

    // DMI interface (TAP -> DTM -> DM)
    wire [6:0]  dmi_addr;
    wire [31:0] dmi_wdata;
    wire [1:0]  dmi_op;
    wire        dmi_req;
    wire [31:0] dmi_rdata;
    wire [1:0]  dmi_resp;
    wire        dmi_ack;

    // System bus interface (DM -> Memory)
    wire [31:0] sbaddr;
    wire [31:0] sbdata_o;
    wire [31:0] sbdata_i;
    wire [2:0]  sbsize;
    wire        sbread;
    wire        sbwrite;
    reg         sbbusy;
    reg         sberror;

    // TAP internal signals
    wire [4:0]  ir_value;
    wire        ir_capture, ir_shift, ir_update;
    wire        dr_capture, dr_shift, dr_update;

    // TDO sources
    wire        tap_tdo;
    wire        dtm_tdo;

    // Multiplex TDO based on instruction
    assign tdo = (ir_value == 5'h10 || ir_value == 5'h11) ? dtm_tdo : tap_tdo;

    // Test control
    integer     errors;
    integer     test_num;
    integer     i;
    reg [31:0]  captured_data;

    //=========================================================================
    // DUT Instantiation: TAP + DTM + Debug Module
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
        .ir_capture(ir_capture),
        .ir_shift(ir_shift),
        .ir_update(ir_update),
        .dr_capture_data(64'h0),
        .dr_shift_in(1'b0),
        .dr_shift_out(),
        .dr_capture(dr_capture),
        .dr_shift(dr_shift),
        .dr_update(dr_update),
        .dr_length()
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
        .sbaddr(sbaddr),
        .sbdata_o(sbdata_o),
        .sbdata_i(sbdata_i),
        .sbsize(sbsize),
        .sbread(sbread),
        .sbwrite(sbwrite),
        .sbbusy(sbbusy),
        .sberror(sberror)
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
    // Mock Memory Model
    //=========================================================================
    reg [31:0] mock_memory [0:255];  // 1KB memory
    reg [31:0] sb_rdata_reg;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            mock_memory[i] = 32'hDEAD0000 + i;
        sb_rdata_reg = 0;
    end

    assign sbdata_i = sb_rdata_reg;

    // Memory access handler
    always @(posedge clk) begin
        if (sbread) begin
            sb_rdata_reg <= mock_memory[sbaddr[9:2]];  // Word-aligned
        end
        if (sbwrite) begin
            mock_memory[sbaddr[9:2]] <= sbdata_o;
        end
    end

    //=========================================================================
    // DMI Access Tasks
    //=========================================================================

    // Read a DMI register and return result
    task dmi_reg_read;
        input  [6:0]  addr;
        output [31:0] data;
        reg [40:0] dmi_in, dmi_out;
        begin
            shift_ir(5'h11);  // DMI
            // Send read request
            dmi_in = {addr, 32'h0, 2'b01};  // op=1 (read)
            shift_dr_41(dmi_in, dmi_out);
            // Wait for DM to process (cross clock domains)
            repeat(10) @(posedge clk);
            // Get result
            dmi_in = 41'h0;  // op=0 (nop)
            shift_dr_41(dmi_in, dmi_out);
            data = dmi_out[33:2];
        end
    endtask

    // Write a DMI register
    task dmi_reg_write;
        input [6:0]  addr;
        input [31:0] data;
        reg [40:0] dmi_in, dmi_out;
        begin
            shift_ir(5'h11);  // DMI
            dmi_in = {addr, data, 2'b10};  // op=2 (write)
            shift_dr_41(dmi_in, dmi_out);
            // Wait for DM to process
            repeat(10) @(posedge clk);
            // Flush with nop
            dmi_in = 41'h0;
            shift_dr_41(dmi_in, dmi_out);
        end
    endtask

    // Read memory via system bus (non-auto-increment mode)
    task sb_mem_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            // Write address to sbaddress0
            dmi_reg_write(7'h39, addr);
            // Trigger read by setting sbreadonaddr (write to sbcs)
            // For simplicity, we'll configure sbcs and manually trigger
            // Write sbcs: sbaccess=2 (32-bit), sbreadonaddr=1
            dmi_reg_write(7'h38, 32'h00000404);  // sbreadonaddr=1, sbaccess=2
            // Write address again to trigger read
            dmi_reg_write(7'h39, addr);
            // Wait for bus operation
            repeat(20) @(posedge clk);
            // Read sbdata0
            dmi_reg_read(7'h3C, data);
        end
    endtask

    // Write memory via system bus
    task sb_mem_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // Configure sbcs for 32-bit access
            dmi_reg_write(7'h38, 32'h00000004);  // sbaccess=2 (32-bit)
            // Write address
            dmi_reg_write(7'h39, addr);
            // Write data (triggers bus write)
            dmi_reg_write(7'h3C, data);
            // Wait for bus operation
            repeat(20) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        $display("");
        $display("========================================");
        $display("  Layer 2: Debug Module Integration");
        $display("  FluxRipper Simulation");
        $display("========================================");
        $display("");

        errors = 0;
        test_num = 0;
        tms = 1;
        tdi = 0;
        trst_n = 0;
        rst_n = 0;
        sbbusy = 0;
        sberror = 0;

        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(TCK_PERIOD * 2);
        trst_n = 1;
        #(TCK_PERIOD * 2);

        //---------------------------------------------------------------------
        // Test 1: Read IDCODE (Layer 0 regression)
        //---------------------------------------------------------------------
        test_num = 1;
        $display("Test %0d: TAP IDCODE (regression)", test_num);

        jtag_reset;
        read_idcode(captured_data);

        if (captured_data != 32'hFB010001) begin
            $display("  FAIL: IDCODE = 0x%08X", captured_data);
            errors = errors + 1;
        end else begin
            $display("  IDCODE = 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 2: Read dmstatus register
        //---------------------------------------------------------------------
        test_num = 2;
        $display("Test %0d: Read dmstatus", test_num);

        dmi_reg_read(7'h11, captured_data);

        // Check version=2 [3:0], authenticated=1 [7]
        if (captured_data[3:0] != 4'd2) begin
            $display("  FAIL: version = %0d (expected 2)", captured_data[3:0]);
            errors = errors + 1;
        end else if (captured_data[7] != 1'b1) begin
            $display("  FAIL: authenticated = %0d (expected 1)", captured_data[7]);
            errors = errors + 1;
        end else begin
            $display("  dmstatus = 0x%08X", captured_data);
            $display("    version=%0d, authenticated=%0d",
                     captured_data[3:0], captured_data[7]);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 3: Write/Read dmcontrol
        //---------------------------------------------------------------------
        test_num = 3;
        $display("Test %0d: Write/Read dmcontrol", test_num);

        // Write dmactive=1
        dmi_reg_write(7'h10, 32'h00000001);
        dmi_reg_read(7'h10, captured_data);

        if (captured_data[0] != 1'b1) begin
            $display("  FAIL: dmactive = %0d (expected 1)", captured_data[0]);
            errors = errors + 1;
        end else begin
            $display("  dmcontrol = 0x%08X (dmactive=1)", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 4: Read sbcs register
        //---------------------------------------------------------------------
        test_num = 4;
        $display("Test %0d: Read sbcs", test_num);

        dmi_reg_read(7'h38, captured_data);

        // Check sbversion=1 [31:29], sbaccess32=1 [17]
        if (captured_data[31:29] != 3'd1) begin
            $display("  FAIL: sbversion = %0d (expected 1)", captured_data[31:29]);
            errors = errors + 1;
        end else if (captured_data[17] != 1'b1) begin
            $display("  FAIL: sbaccess32 = %0d (expected 1)", captured_data[17]);
            errors = errors + 1;
        end else begin
            $display("  sbcs = 0x%08X", captured_data);
            $display("    sbversion=%0d, sbaccess32/16/8=%b%b%b",
                     captured_data[31:29], captured_data[17],
                     captured_data[16], captured_data[15]);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 5: System bus write + read
        //---------------------------------------------------------------------
        test_num = 5;
        $display("Test %0d: System bus write/read", test_num);

        // Write 0xCAFEBABE to address 0x100
        sb_mem_write(32'h00000100, 32'hCAFEBABE);

        // Read it back
        sb_mem_read(32'h00000100, captured_data);

        if (captured_data != 32'hCAFEBABE) begin
            $display("  FAIL: Read = 0x%08X (expected 0xCAFEBABE)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Write 0xCAFEBABE to 0x100, read back: 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 6: Read pre-initialized memory
        //---------------------------------------------------------------------
        test_num = 6;
        $display("Test %0d: Read pre-initialized memory", test_num);

        // Address 0x000 should have 0xDEAD0000
        sb_mem_read(32'h00000000, captured_data);

        if (captured_data != 32'hDEAD0000) begin
            $display("  FAIL: Read = 0x%08X (expected 0xDEAD0000)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Read addr=0x000: 0x%08X", captured_data);
            $display("  PASS");
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
        #(TCK_PERIOD * 500000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_debug_module.vcd");
        $dumpvars(0, tb_debug_module);
    end

endmodule
