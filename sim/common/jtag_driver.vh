// FluxRipper JTAG Driver - Reusable Test Infrastructure
// Created: 2025-12-07 20:30
//
// Include this file in testbenches for consistent JTAG operations.
// Usage:
//   `include "jtag_driver.vh"
//   // Then call tasks like: jtag_reset(), shift_ir(5'h01), etc.

//-----------------------------------------------------------------------------
// JTAG Instruction Codes
//-----------------------------------------------------------------------------
localparam [4:0]
    JTAG_BYPASS    = 5'h1F,
    JTAG_IDCODE    = 5'h01,
    JTAG_DTMCS     = 5'h10,
    JTAG_DMI       = 5'h11,
    JTAG_MEM_READ  = 5'h02,
    JTAG_MEM_WRITE = 5'h03,
    JTAG_SIG_TAP   = 5'h04,
    JTAG_STATUS    = 5'h07,
    JTAG_CAPS      = 5'h08;

//-----------------------------------------------------------------------------
// Clock one TCK cycle
//-----------------------------------------------------------------------------
task jtag_clock;
    input tms_val;
    begin
        tms = tms_val;
        @(posedge tck);
        #1;
    end
endtask

//-----------------------------------------------------------------------------
// TAP Reset (5+ TMS=1 clocks, then TMS=0 to Run-Test/Idle)
//-----------------------------------------------------------------------------
task jtag_reset;
    begin
        repeat(6) jtag_clock(1);
        jtag_clock(0);
    end
endtask

//-----------------------------------------------------------------------------
// Navigate to Shift-IR from Run-Test/Idle
//-----------------------------------------------------------------------------
task goto_shift_ir;
    begin
        jtag_clock(1);  // Select-DR
        jtag_clock(1);  // Select-IR
        jtag_clock(0);  // Capture-IR
        jtag_clock(0);  // Shift-IR
    end
endtask

//-----------------------------------------------------------------------------
// Navigate to Shift-DR from Run-Test/Idle
//-----------------------------------------------------------------------------
task goto_shift_dr;
    begin
        jtag_clock(1);  // Select-DR
        jtag_clock(0);  // Capture-DR
        jtag_clock(0);  // Shift-DR
        @(negedge tck); // Wait for TDO to update
        #1;
    end
endtask

//-----------------------------------------------------------------------------
// Shift IR and return to Run-Test/Idle
//-----------------------------------------------------------------------------
task shift_ir;
    input [4:0] ir_data;
    integer i;
    begin
        goto_shift_ir;
        for (i = 0; i < 4; i = i + 1) begin
            tdi = ir_data[i];
            jtag_clock(0);
        end
        tdi = ir_data[4];
        jtag_clock(1);  // Exit1-IR
        jtag_clock(1);  // Update-IR
        jtag_clock(0);  // Run-Test/Idle
    end
endtask

//-----------------------------------------------------------------------------
// Shift DR (32-bit) and return to Run-Test/Idle
// Note: Last bit must be shifted with TMS=1 to exit Shift-DR properly
//-----------------------------------------------------------------------------
task shift_dr_32;
    input  [31:0] data_in;
    output [31:0] data_out;
    integer i;
    begin
        goto_shift_dr;
        data_out = 0;
        // Shift first 31 bits with TMS=0
        for (i = 0; i < 31; i = i + 1) begin
            tdi = data_in[i];
            data_out[i] = tdo;
            @(posedge tck);
            @(negedge tck);
            #1;
        end
        // Shift last bit with TMS=1 to exit to Exit1-DR
        tdi = data_in[31];
        data_out[31] = tdo;
        tms = 1;
        @(posedge tck);  // Shift bit 31 AND exit to Exit1-DR
        @(negedge tck);
        #1;
        @(posedge tck);  // Update-DR
        tms = 0;
        @(posedge tck);  // Run-Test/Idle
        #1;
    end
endtask

//-----------------------------------------------------------------------------
// Shift DR (41-bit for DMI) and return to Run-Test/Idle
// Note: Last bit must be shifted with TMS=1 to exit Shift-DR properly
//-----------------------------------------------------------------------------
task shift_dr_41;
    input  [40:0] data_in;
    output [40:0] data_out;
    integer i;
    begin
        goto_shift_dr;
        data_out = 0;
        // Shift first 40 bits with TMS=0
        for (i = 0; i < 40; i = i + 1) begin
            tdi = data_in[i];
            data_out[i] = tdo;
            @(posedge tck);
            @(negedge tck);
            #1;
        end
        // Shift last bit with TMS=1 to exit to Exit1-DR
        tdi = data_in[40];
        data_out[40] = tdo;
        tms = 1;
        @(posedge tck);  // Shift bit 40 AND exit to Exit1-DR
        @(negedge tck);
        #1;
        @(posedge tck);  // Update-DR
        tms = 0;
        @(posedge tck);  // Run-Test/Idle
        #1;
    end
endtask

//-----------------------------------------------------------------------------
// Shift DR (64-bit) and return to Run-Test/Idle
// Note: Last bit must be shifted with TMS=1 to exit Shift-DR properly
//-----------------------------------------------------------------------------
task shift_dr_64;
    input  [63:0] data_in;
    output [63:0] data_out;
    integer i;
    begin
        goto_shift_dr;
        data_out = 0;
        // Shift first 63 bits with TMS=0
        for (i = 0; i < 63; i = i + 1) begin
            tdi = data_in[i];
            data_out[i] = tdo;
            @(posedge tck);
            @(negedge tck);
            #1;
        end
        // Shift last bit with TMS=1 to exit to Exit1-DR
        tdi = data_in[63];
        data_out[63] = tdo;
        tms = 1;
        @(posedge tck);  // Shift bit 63 AND exit to Exit1-DR
        @(negedge tck);
        #1;
        @(posedge tck);  // Update-DR
        tms = 0;
        @(posedge tck);  // Run-Test/Idle
        #1;
    end
endtask

//-----------------------------------------------------------------------------
// Read IDCODE (convenience wrapper)
//-----------------------------------------------------------------------------
task read_idcode;
    output [31:0] idcode;
    begin
        shift_ir(JTAG_IDCODE);
        shift_dr_32(32'h0, idcode);
    end
endtask

//-----------------------------------------------------------------------------
// DMI Read (Layer 1+)
//   DMI format: [40:34]=addr, [33:2]=data, [1:0]=op
//   op: 0=nop, 1=read, 2=write
//-----------------------------------------------------------------------------
task dmi_read;
    input  [6:0]  addr;
    output [31:0] data;
    reg [40:0] dmi_in, dmi_out;
    begin
        shift_ir(JTAG_DMI);
        // Send read request
        dmi_in = {addr, 32'h0, 2'b01};  // op=1 (read)
        shift_dr_41(dmi_in, dmi_out);
        // Get result
        dmi_in = {7'h0, 32'h0, 2'b00};  // op=0 (nop)
        shift_dr_41(dmi_in, dmi_out);
        data = dmi_out[33:2];
    end
endtask

//-----------------------------------------------------------------------------
// DMI Write (Layer 1+)
//-----------------------------------------------------------------------------
task dmi_write;
    input [6:0]  addr;
    input [31:0] data;
    reg [40:0] dmi_in, dmi_out;
    begin
        shift_ir(JTAG_DMI);
        dmi_in = {addr, data, 2'b10};  // op=2 (write)
        shift_dr_41(dmi_in, dmi_out);
    end
endtask

//-----------------------------------------------------------------------------
// Memory Read via Debug Module (Layer 2+)
//   Assumes sbcs is configured for 32-bit auto-increment
//-----------------------------------------------------------------------------
task mem_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
        // Write address to sbaddress0 (DM register 0x39)
        dmi_write(7'h39, addr);
        // Read data from sbdata0 (DM register 0x3C)
        dmi_read(7'h3C, data);
    end
endtask

//-----------------------------------------------------------------------------
// Memory Write via Debug Module (Layer 2+)
//-----------------------------------------------------------------------------
task mem_write;
    input [31:0] addr;
    input [31:0] data;
    begin
        // Write address to sbaddress0
        dmi_write(7'h39, addr);
        // Write data to sbdata0 (triggers write)
        dmi_write(7'h3C, data);
    end
endtask
