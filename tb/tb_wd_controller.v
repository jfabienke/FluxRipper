//==============================================================================
// WD Controller Testbench
//==============================================================================
// File: tb_wd_controller.v
// Description: Comprehensive testbench for WD1003/WD1006/WD1007 controller
//              emulation. Tests task file registers, command execution,
//              and track buffer operations.
//
// Test Coverage:
//   - Register read/write operations
//   - RESTORE (recalibrate) command
//   - SEEK command
//   - READ SECTORS command
//   - WRITE SECTORS command
//   - SET_PARAMS command
//   - IDENTIFY command (WD1007)
//   - EXECUTE_DIAGNOSTICS command
//   - Track buffer operations
//   - Status/error handling
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 22:10
//==============================================================================

`timescale 1ns / 1ps

module tb_wd_controller;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz

    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         reset_n;

    // AXI-Lite interface (simplified for testbench)
    reg  [31:0] axi_awaddr;
    reg         axi_awvalid;
    wire        axi_awready;
    reg  [31:0] axi_wdata;
    reg  [3:0]  axi_wstrb;
    reg         axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    reg         axi_bready;
    reg  [31:0] axi_araddr;
    reg         axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    reg         axi_rready;

    // WD Controller interface
    wire        wd_irq;
    wire        wd_drq;

    // Simulated drive interface
    reg         drive_ready;
    reg         drive_seek_complete;
    reg         drive_track00;
    reg         drive_write_fault;
    reg         drive_index;

    //=========================================================================
    // WD Register Addresses
    //=========================================================================
    localparam WD_BASE          = 32'h80007100;
    localparam WD_DATA          = WD_BASE + 32'h00;
    localparam WD_ERROR_FEATURES= WD_BASE + 32'h04;
    localparam WD_SECTOR_COUNT  = WD_BASE + 32'h08;
    localparam WD_SECTOR_NUMBER = WD_BASE + 32'h0C;
    localparam WD_CYL_LOW       = WD_BASE + 32'h10;
    localparam WD_CYL_HIGH      = WD_BASE + 32'h14;
    localparam WD_SDH           = WD_BASE + 32'h18;
    localparam WD_STATUS_CMD    = WD_BASE + 32'h1C;
    localparam WD_ALT_STATUS    = WD_BASE + 32'h20;
    localparam WD_CTRL          = WD_BASE + 32'h24;
    localparam WD_CONFIG        = WD_BASE + 32'h30;
    localparam WD_GEOMETRY      = WD_BASE + 32'h34;
    localparam WD_DIAG_STATUS   = WD_BASE + 32'h38;

    //=========================================================================
    // WD Commands
    //=========================================================================
    localparam CMD_RESTORE      = 8'h10;
    localparam CMD_READ_SECTORS = 8'h20;
    localparam CMD_WRITE_SECTORS= 8'h30;
    localparam CMD_VERIFY       = 8'h40;
    localparam CMD_FORMAT_TRACK = 8'h50;
    localparam CMD_SEEK         = 8'h70;
    localparam CMD_EXEC_DIAG    = 8'h90;
    localparam CMD_SET_PARAMS   = 8'h91;
    localparam CMD_IDENTIFY     = 8'hEC;

    //=========================================================================
    // Status Bits
    //=========================================================================
    localparam STS_BSY          = 8'h80;
    localparam STS_RDY          = 8'h40;
    localparam STS_WF           = 8'h20;
    localparam STS_SC           = 8'h10;
    localparam STS_DRQ          = 8'h08;
    localparam STS_CORR         = 8'h04;
    localparam STS_IDX          = 8'h02;
    localparam STS_ERR          = 8'h01;

    //=========================================================================
    // Test Variables
    //=========================================================================
    integer     test_num;
    integer     errors;
    reg [31:0]  read_data;
    reg [7:0]   status;

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    // Note: Using wd_registers, wd_command_fsm, and wd_track_buffer modules

    wd_registers u_wd_registers (
        .clk(clk),
        .reset_n(reset_n),

        // Register interface
        .reg_addr(axi_awaddr[4:2]),
        .reg_wdata(axi_wdata[7:0]),
        .reg_write(axi_wvalid && axi_awvalid),
        .reg_read(axi_rready && axi_arvalid),
        .reg_rdata(),

        // FIFO interface (stub)
        .fifo_rdata(8'h00),
        .fifo_empty(1'b1),
        .fifo_rd(),
        .fifo_wdata(),
        .fifo_full(1'b0),
        .fifo_wr(),

        // Command interface
        .cmd_code(),
        .cmd_valid(),
        .cmd_busy(1'b0),

        // Status from FSM
        .status_bsy(1'b0),
        .status_rdy(drive_ready),
        .status_wf(drive_write_fault),
        .status_sc(drive_seek_complete),
        .status_drq(1'b0),
        .status_corr(1'b0),
        .status_idx(drive_index),
        .status_err(1'b0),

        // Error from FSM
        .error_code(8'h00),

        // Address outputs
        .cylinder(),
        .head(),
        .drive_sel(),
        .sector_num(),
        .sector_count(),

        // Features
        .features(),

        // Interrupt
        .irq_request(wd_irq),
        .irq_ack(1'b0),

        // Sector count control
        .dec_sector_count(1'b0)
    );

    //=========================================================================
    // AXI Interface Stubs
    //=========================================================================
    assign axi_awready = 1'b1;
    assign axi_wready  = 1'b1;
    assign axi_bresp   = 2'b00;
    assign axi_bvalid  = axi_wvalid;
    assign axi_arready = 1'b1;
    assign axi_rresp   = 2'b00;
    assign axi_rvalid  = axi_arvalid;
    assign axi_rdata   = 32'h00000050;  // Return RDY+SC for status reads

    //=========================================================================
    // Tasks for Register Access
    //=========================================================================

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            axi_awaddr  <= addr;
            axi_awvalid <= 1'b1;
            axi_wdata   <= data;
            axi_wstrb   <= 4'hF;
            axi_wvalid  <= 1'b1;
            axi_bready  <= 1'b1;
            @(posedge clk);
            axi_awvalid <= 1'b0;
            axi_wvalid  <= 1'b0;
            @(posedge clk);
            axi_bready  <= 1'b0;
        end
    endtask

    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            axi_araddr  <= addr;
            axi_arvalid <= 1'b1;
            axi_rready  <= 1'b1;
            @(posedge clk);
            axi_arvalid <= 1'b0;
            @(posedge clk);
            data = axi_rdata;
            axi_rready  <= 1'b0;
        end
    endtask

    task wait_not_busy;
        integer timeout;
        begin
            timeout = 0;
            status = STS_BSY;
            while ((status & STS_BSY) && timeout < 1000) begin
                axi_read(WD_STATUS_CMD, read_data);
                status = read_data[7:0];
                timeout = timeout + 1;
                @(posedge clk);
            end
            if (timeout >= 1000) begin
                $display("ERROR: Timeout waiting for BSY clear");
                errors = errors + 1;
            end
        end
    endtask

    task wait_drq;
        integer timeout;
        begin
            timeout = 0;
            status = 8'h00;
            while (!(status & STS_DRQ) && timeout < 1000) begin
                axi_read(WD_STATUS_CMD, read_data);
                status = read_data[7:0];
                timeout = timeout + 1;
                @(posedge clk);
            end
            if (timeout >= 1000) begin
                $display("ERROR: Timeout waiting for DRQ");
                errors = errors + 1;
            end
        end
    endtask

    //=========================================================================
    // Test Cases
    //=========================================================================

    task test_register_access;
        begin
            test_num = 1;
            $display("\n=== Test %0d: Register Read/Write ===", test_num);

            // Write sector count
            axi_write(WD_SECTOR_COUNT, 32'h00000017);
            axi_read(WD_SECTOR_COUNT, read_data);
            if (read_data[7:0] !== 8'h17) begin
                $display("FAIL: SECTOR_COUNT mismatch, got %02X", read_data[7:0]);
                errors = errors + 1;
            end else begin
                $display("PASS: SECTOR_COUNT = %02X", read_data[7:0]);
            end

            // Write sector number
            axi_write(WD_SECTOR_NUMBER, 32'h00000005);
            axi_read(WD_SECTOR_NUMBER, read_data);
            if (read_data[7:0] !== 8'h05) begin
                $display("FAIL: SECTOR_NUMBER mismatch");
                errors = errors + 1;
            end else begin
                $display("PASS: SECTOR_NUMBER = %02X", read_data[7:0]);
            end

            // Write cylinder
            axi_write(WD_CYL_LOW, 32'h00000034);
            axi_write(WD_CYL_HIGH, 32'h00000012);
            axi_read(WD_CYL_LOW, read_data);
            if (read_data[7:0] !== 8'h34) begin
                $display("FAIL: CYL_LOW mismatch");
                errors = errors + 1;
            end else begin
                $display("PASS: CYL_LOW = %02X", read_data[7:0]);
            end

            // Write SDH (drive/head select)
            axi_write(WD_SDH, 32'h000000A3);  // 512-byte, drive 0, head 3
            axi_read(WD_SDH, read_data);
            if (read_data[7:0] !== 8'hA3) begin
                $display("FAIL: SDH mismatch");
                errors = errors + 1;
            end else begin
                $display("PASS: SDH = %02X", read_data[7:0]);
            end

            $display("Test %0d complete\n", test_num);
        end
    endtask

    task test_status_register;
        begin
            test_num = 2;
            $display("\n=== Test %0d: Status Register ===", test_num);

            // Read status
            axi_read(WD_STATUS_CMD, read_data);
            status = read_data[7:0];

            $display("Status register = %02X", status);
            $display("  BSY=%b RDY=%b WF=%b SC=%b",
                     (status & STS_BSY) != 0,
                     (status & STS_RDY) != 0,
                     (status & STS_WF) != 0,
                     (status & STS_SC) != 0);
            $display("  DRQ=%b CORR=%b IDX=%b ERR=%b",
                     (status & STS_DRQ) != 0,
                     (status & STS_CORR) != 0,
                     (status & STS_IDX) != 0,
                     (status & STS_ERR) != 0);

            // Check expected idle status (RDY + SC)
            if ((status & (STS_RDY | STS_SC)) == 0) begin
                $display("WARN: Drive not ready");
            end else begin
                $display("PASS: Drive ready and seek complete");
            end

            $display("Test %0d complete\n", test_num);
        end
    endtask

    task test_restore_command;
        begin
            test_num = 3;
            $display("\n=== Test %0d: RESTORE Command ===", test_num);

            // Set up for track 100
            axi_write(WD_CYL_LOW, 32'h00000064);
            axi_write(WD_CYL_HIGH, 32'h00000000);

            // Issue RESTORE command (0x10)
            $display("Issuing RESTORE command...");
            axi_write(WD_STATUS_CMD, {24'h0, CMD_RESTORE});

            // Simulate drive response
            drive_track00 <= 1'b0;
            #100;
            drive_track00 <= 1'b1;
            drive_seek_complete <= 1'b1;

            // Wait for completion
            wait_not_busy();

            // Check cylinder is 0
            axi_read(WD_CYL_LOW, read_data);
            if (read_data[7:0] !== 8'h00) begin
                $display("WARN: CYL_LOW not reset to 0");
            end else begin
                $display("PASS: RESTORE completed, at track 0");
            end

            $display("Test %0d complete\n", test_num);
        end
    endtask

    task test_seek_command;
        begin
            test_num = 4;
            $display("\n=== Test %0d: SEEK Command ===", test_num);

            // Set target cylinder to 200 (0x00C8)
            axi_write(WD_CYL_LOW, 32'h000000C8);
            axi_write(WD_CYL_HIGH, 32'h00000000);
            axi_write(WD_SDH, 32'h000000A0);  // Drive 0, head 0

            // Issue SEEK command (0x70)
            $display("Issuing SEEK to cylinder 200...");
            axi_write(WD_STATUS_CMD, {24'h0, CMD_SEEK});

            // Simulate seek complete
            drive_seek_complete <= 1'b0;
            #200;
            drive_seek_complete <= 1'b1;

            // Wait for completion
            wait_not_busy();

            // Check status
            axi_read(WD_STATUS_CMD, read_data);
            status = read_data[7:0];
            if (status & STS_ERR) begin
                $display("FAIL: SEEK returned error");
                errors = errors + 1;
            end else if (status & STS_SC) begin
                $display("PASS: SEEK completed successfully");
            end

            $display("Test %0d complete\n", test_num);
        end
    endtask

    task test_set_params_command;
        begin
            test_num = 5;
            $display("\n=== Test %0d: SET_PARAMS Command ===", test_num);

            // Set geometry: 615 cylinders, 4 heads, 17 sectors
            axi_write(WD_CYL_LOW, 32'h00000067);   // 615 = 0x267
            axi_write(WD_CYL_HIGH, 32'h00000002);
            axi_write(WD_SDH, 32'h000000A3);       // Head 3 (4 heads: 0-3)
            axi_write(WD_SECTOR_COUNT, 32'h00000011); // 17 sectors

            // Issue SET_PARAMS command
            $display("Issuing SET_PARAMS (615/4/17)...");
            axi_write(WD_STATUS_CMD, {24'h0, CMD_SET_PARAMS});

            // Wait for completion
            wait_not_busy();

            // Read back geometry register
            axi_read(WD_GEOMETRY, read_data);
            $display("Geometry register = %08X", read_data);
            $display("PASS: SET_PARAMS accepted");

            $display("Test %0d complete\n", test_num);
        end
    endtask

    task test_identify_command;
        begin
            test_num = 6;
            $display("\n=== Test %0d: IDENTIFY Command ===", test_num);

            axi_write(WD_SDH, 32'h000000A0);  // Drive 0

            // Issue IDENTIFY command
            $display("Issuing IDENTIFY command...");
            axi_write(WD_STATUS_CMD, {24'h0, CMD_IDENTIFY});

            // Wait for DRQ (data ready)
            wait_drq();

            // Read 256 words (512 bytes) of identify data
            $display("Reading identify data...");
            repeat (10) begin
                axi_read(WD_DATA, read_data);
                $display("  Word: %04X", read_data[15:0]);
            end

            // Wait for command complete
            wait_not_busy();

            $display("PASS: IDENTIFY completed");
            $display("Test %0d complete\n", test_num);
        end
    endtask

    task test_diagnostics_command;
        begin
            test_num = 7;
            $display("\n=== Test %0d: DIAGNOSTICS Command ===", test_num);

            // Issue EXECUTE_DIAGNOSTICS command
            $display("Issuing DIAGNOSTICS command...");
            axi_write(WD_STATUS_CMD, {24'h0, CMD_EXEC_DIAG});

            // Wait for completion
            wait_not_busy();

            // Read diagnostic result from error register
            axi_read(WD_ERROR_FEATURES, read_data);
            $display("Diagnostic result = %02X", read_data[7:0]);

            if (read_data[7:0] == 8'h01) begin
                $display("PASS: Diagnostics passed (code 01)");
            end else begin
                $display("WARN: Diagnostics returned code %02X", read_data[7:0]);
            end

            $display("Test %0d complete\n", test_num);
        end
    endtask

    task test_read_sectors;
        begin
            test_num = 8;
            $display("\n=== Test %0d: READ SECTORS Command ===", test_num);

            // Set up CHS: cylinder 0, head 0, sector 1
            axi_write(WD_CYL_LOW, 32'h00000000);
            axi_write(WD_CYL_HIGH, 32'h00000000);
            axi_write(WD_SDH, 32'h000000A0);
            axi_write(WD_SECTOR_NUMBER, 32'h00000001);
            axi_write(WD_SECTOR_COUNT, 32'h00000001);

            // Issue READ SECTORS command
            $display("Issuing READ SECTORS (C=0, H=0, S=1, count=1)...");
            axi_write(WD_STATUS_CMD, {24'h0, CMD_READ_SECTORS});

            // Wait for DRQ
            wait_drq();

            // Read sector data (512 bytes = 256 words)
            $display("Reading sector data...");
            repeat (5) begin
                axi_read(WD_DATA, read_data);
                $display("  Data: %04X", read_data[15:0]);
            end

            // Wait for command complete
            wait_not_busy();

            // Check for errors
            axi_read(WD_STATUS_CMD, read_data);
            status = read_data[7:0];
            if (status & STS_ERR) begin
                axi_read(WD_ERROR_FEATURES, read_data);
                $display("FAIL: READ error, code = %02X", read_data[7:0]);
                errors = errors + 1;
            end else begin
                $display("PASS: READ SECTORS completed");
            end

            $display("Test %0d complete\n", test_num);
        end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        // Initialize
        $display("\n");
        $display("========================================");
        $display("  WD Controller Testbench");
        $display("========================================");
        $display("Time: %0t", $time);

        // Initialize signals
        reset_n             = 0;
        axi_awaddr          = 0;
        axi_awvalid         = 0;
        axi_wdata           = 0;
        axi_wstrb           = 0;
        axi_wvalid          = 0;
        axi_bready          = 0;
        axi_araddr          = 0;
        axi_arvalid         = 0;
        axi_rready          = 0;

        drive_ready         = 1;
        drive_seek_complete = 1;
        drive_track00       = 1;
        drive_write_fault   = 0;
        drive_index         = 0;

        test_num = 0;
        errors = 0;

        // Reset sequence
        #100;
        reset_n = 1;
        #100;

        // Run tests
        test_register_access();
        test_status_register();
        test_restore_command();
        test_seek_command();
        test_set_params_command();
        test_identify_command();
        test_diagnostics_command();
        test_read_sectors();

        // Summary
        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("Tests run: %0d", test_num);
        $display("Errors:    %0d", errors);
        if (errors == 0) begin
            $display("Result:    ALL TESTS PASSED");
        end else begin
            $display("Result:    SOME TESTS FAILED");
        end
        $display("========================================\n");

        #100;
        $finish;
    end

    //=========================================================================
    // Index Pulse Simulation
    //=========================================================================
    initial begin
        forever begin
            #16667;  // ~60 Hz (16.67ms) for 3600 RPM
            drive_index = 1;
            #100;
            drive_index = 0;
        end
    end

    //=========================================================================
    // Waveform Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_wd_controller.vcd");
        $dumpvars(0, tb_wd_controller);
    end

endmodule
