`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_jtag_dtm.v - Layer 1 Testbench: TAP + DTM Integration
//
// Tests JTAG access to Debug Transport Module (DTM).
// Validates DTMCS register and DMI read/write operations.
//
// Created: 2025-12-07 20:45
//-----------------------------------------------------------------------------

module tb_jtag_dtm;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 100;

    //=========================================================================
    // Signals
    //=========================================================================
    reg         tck;
    reg         tms;
    reg         tdi;
    reg         trst_n;
    wire        tdo;

    // DMI interface (directly usable for stimulus/checking)
    wire [6:0]  dmi_addr;
    wire [31:0] dmi_wdata;
    wire [1:0]  dmi_op;
    wire        dmi_req;
    reg  [31:0] dmi_rdata;
    reg  [1:0]  dmi_resp;
    reg         dmi_ack;

    // TAP internal signals
    wire [4:0]  ir_value;
    wire        ir_capture, ir_shift, ir_update;
    wire        dr_capture, dr_shift, dr_update;

    // TDO sources
    wire        tap_tdo;
    wire        dtm_tdo;

    // Multiplex TDO based on instruction (DTM handles 0x10, 0x11)
    assign tdo = (ir_value == 5'h10 || ir_value == 5'h11) ? dtm_tdo : tap_tdo;

    // Test control
    integer     errors;
    integer     test_num;
    integer     i;  // Loop variable
    reg [31:0]  captured_data;
    reg [40:0]  dmi_captured;

    //=========================================================================
    // DUT Instantiation: TAP + DTM
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

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial tck = 0;
    always #(CLK_PERIOD/2) tck = ~tck;

    //=========================================================================
    // Include JTAG Driver Tasks
    //=========================================================================
    `include "../common/jtag_driver.vh"

    //=========================================================================
    // DMI Mock Response Generator
    //=========================================================================
    reg [31:0] mock_registers [0:127];
    reg [31:0] last_read_data;

    initial begin
        for (i = 0; i < 128; i = i + 1)
            mock_registers[i] = 32'hDEAD0000 + i;
        last_read_data = 0;
    end

    // Synchronous mock - updates on posedge
    always @(posedge tck) begin
        dmi_ack <= 0;
        if (dmi_req) begin
            dmi_ack <= 1;
            dmi_resp <= 2'b00;  // OK
            case (dmi_op)
                2'b01: last_read_data <= mock_registers[dmi_addr];  // Read
                2'b10: mock_registers[dmi_addr] <= dmi_wdata;       // Write
            endcase
        end
    end

    // dmi_rdata reflects the last read result
    always @(*) begin
        dmi_rdata = last_read_data;
    end

    //=========================================================================
    // Additional Tasks for Layer 1
    //=========================================================================
    
    // Read DTMCS register
    task read_dtmcs;
        output [31:0] dtmcs;
        begin
            shift_ir(5'h10);  // DTMCS
            shift_dr_32(32'h0, dtmcs);
        end
    endtask

    // DMI read operation
    task do_dmi_read;
        input  [6:0]  addr;
        output [31:0] data;
        reg [40:0] dmi_in, dmi_out;
        begin
            shift_ir(5'h11);  // DMI
            // Send read request
            dmi_in = {addr, 32'h0, 2'b01};  // op=1 (read)
            shift_dr_41(dmi_in, dmi_out);
            // Get result with nop
            dmi_in = 41'h0;  // op=0 (nop)
            shift_dr_41(dmi_in, dmi_out);
            data = dmi_out[33:2];
        end
    endtask

    // DMI write operation (with flush to ensure write completes)
    task do_dmi_write;
        input [6:0]  addr;
        input [31:0] data;
        reg [40:0] dmi_in, dmi_out;
        begin
            shift_ir(5'h11);  // DMI
            dmi_in = {addr, data, 2'b10};  // op=2 (write)
            shift_dr_41(dmi_in, dmi_out);
            // Flush with nop to ensure write completes before next access
            dmi_in = 41'h0;  // nop
            shift_dr_41(dmi_in, dmi_out);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        $display("");
        $display("========================================");
        $display("  Layer 1: TAP + DTM Integration Test");
        $display("  FluxRipper Simulation");
        $display("========================================");
        $display("");

        errors = 0;
        test_num = 0;
        tms = 1;
        tdi = 0;
        trst_n = 0;  // Assert reset
        dmi_rdata = 0;
        dmi_resp = 0;
        dmi_ack = 0;

        #(CLK_PERIOD * 2);
        trst_n = 1;  // Release reset
        #(CLK_PERIOD * 2);

        //---------------------------------------------------------------------
        // Test 1: TAP Reset and IDCODE (Layer 0 regression)
        //---------------------------------------------------------------------
        test_num = 1;
        $display("Test %0d: TAP Reset and IDCODE", test_num);

        jtag_reset;
        read_idcode(captured_data);

        if (captured_data != 32'hFB010001) begin
            $display("  FAIL: IDCODE = 0x%08X (expected 0xFB010001)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  IDCODE = 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 2: Read DTMCS register
        //---------------------------------------------------------------------
        test_num = 2;
        $display("Test %0d: Read DTMCS", test_num);

        read_dtmcs(captured_data);

        // Expected: version=1, abits=7, idle=1, status=0
        if (captured_data[3:0] != 4'd1) begin
            $display("  FAIL: version = %0d (expected 1)", captured_data[3:0]);
            errors = errors + 1;
        end else if (captured_data[9:4] != 6'd7) begin
            $display("  FAIL: abits = %0d (expected 7)", captured_data[9:4]);
            errors = errors + 1;
        end else begin
            $display("  DTMCS = 0x%08X", captured_data);
            $display("    version = %0d, abits = %0d, idle = %0d, status = %0d",
                     captured_data[3:0], captured_data[9:4],
                     captured_data[14:12], captured_data[11:10]);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 3: DMI Read Operation
        //---------------------------------------------------------------------
        test_num = 3;
        $display("Test %0d: DMI Read", test_num);

        do_dmi_read(7'h10, captured_data);

        if (captured_data != 32'hDEAD0010) begin
            $display("  FAIL: Read data = 0x%08X (expected 0xDEAD0010)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Read addr=0x10: 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 4: DMI Write Operation
        //---------------------------------------------------------------------
        test_num = 4;
        $display("Test %0d: DMI Write", test_num);

        do_dmi_write(7'h20, 32'hCAFEBABE);
        do_dmi_read(7'h20, captured_data);

        if (captured_data != 32'hCAFEBABE) begin
            $display("  FAIL: Read back = 0x%08X (expected 0xCAFEBABE)", captured_data);
            errors = errors + 1;
        end else begin
            $display("  Write/Read addr=0x20: 0x%08X", captured_data);
            $display("  PASS");
        end

        //---------------------------------------------------------------------
        // Test 5: Multiple DMI accesses
        //---------------------------------------------------------------------
        test_num = 5;
        $display("Test %0d: Multiple DMI accesses", test_num);

        do_dmi_write(7'h30, 32'h11111111);
        do_dmi_write(7'h31, 32'h22222222);
        do_dmi_write(7'h32, 32'h33333333);

        do_dmi_read(7'h30, captured_data);
        if (captured_data != 32'h11111111) errors = errors + 1;
        
        do_dmi_read(7'h31, captured_data);
        if (captured_data != 32'h22222222) errors = errors + 1;
        
        do_dmi_read(7'h32, captured_data);
        if (captured_data != 32'h33333333) errors = errors + 1;

        if (errors == 0) begin
            $display("  3 writes, 3 reads verified");
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

        #(CLK_PERIOD * 10);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #(CLK_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_jtag_dtm.vcd");
        $dumpvars(0, tb_jtag_dtm);
    end

endmodule
