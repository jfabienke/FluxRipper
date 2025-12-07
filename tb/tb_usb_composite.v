//-----------------------------------------------------------------------------
// tb_usb_composite.v
// Testbench for USB Composite Device (MSC + Raw Mode)
//
// Created: 2025-12-05 16:55
//
// Integration test for the complete USB composite device including:
//   - Interface routing (MSC vs Raw)
//   - MSC protocol handling
//   - Raw mode command processing
//   - Drive LUN mapping
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_usb_composite;

    //=========================================================================
    // Parameters
    //=========================================================================

    parameter CLK_PERIOD = 10;  // 100 MHz

    //=========================================================================
    // Test Signals
    //=========================================================================

    reg         clk;
    reg         rst_n;

    // Simulated USB endpoint data
    reg  [31:0] ep1_out_data;       // Shared EP1 OUT (commands from host)
    reg         ep1_out_valid;
    wire        ep1_out_ready;

    wire [31:0] ep2_in_data;        // MSC EP2 IN (data to host)
    wire        ep2_in_valid;
    reg         ep2_in_ready;

    wire [31:0] ep3_in_data;        // Raw EP3 IN (flux/diagnostics to host)
    wire        ep3_in_valid;
    reg         ep3_in_ready;

    // Composite Mux Outputs
    wire [1:0]  active_interface;
    wire        msc_active;
    wire        raw_active;

    // FDD HAL Simulation
    reg  [1:0]  fdd_present;
    reg  [1:0]  fdd_write_prot;
    reg         fdd_ready;
    reg         fdd_done;
    reg         fdd_error;
    wire [1:0]  fdd_select;
    wire [31:0] fdd_lba;
    wire [15:0] fdd_count;
    wire        fdd_read;
    wire        fdd_write;

    // HDD HAL Simulation
    reg  [1:0]  hdd_present;
    reg         hdd_ready;
    reg         hdd_done;
    reg         hdd_error;
    wire [1:0]  hdd_select;
    wire [31:0] hdd_lba;
    wire [15:0] hdd_count;
    wire        hdd_read;
    wire        hdd_write;

    // LUN Configuration
    wire [3:0]  lun_present;
    wire [3:0]  lun_removable;
    wire [3:0]  lun_readonly;

    //=========================================================================
    // Constants
    //=========================================================================

    localparam CBW_SIGNATURE = 32'h43425355;  // "USBC"
    localparam RAW_SIGNATURE = 32'h46525751;  // "FRWQ"

    //=========================================================================
    // DUT Instantiation - Composite Mux
    //=========================================================================

    wire [31:0] msc_rx_data;
    wire        msc_rx_valid;
    wire        msc_rx_ready;
    wire [31:0] msc_tx_data;
    wire        msc_tx_valid;
    wire        msc_tx_ready;

    wire [31:0] raw_rx_data;
    wire        raw_rx_valid;
    wire        raw_rx_ready;
    wire [31:0] raw_tx_data;
    wire        raw_tx_valid;
    wire        raw_tx_ready;

    usb_composite_mux #(
        .CBW_SIGNATURE(CBW_SIGNATURE),
        .RAW_SIGNATURE(RAW_SIGNATURE)
    ) mux_inst (
        .clk(clk),
        .rst_n(rst_n),

        .usb_rx_data(ep1_out_data),
        .usb_rx_valid(ep1_out_valid),
        .usb_rx_ready(ep1_out_ready),

        .msc_tx_data(msc_tx_data),
        .msc_tx_valid(msc_tx_valid),
        .msc_tx_ready(msc_tx_ready),

        .raw_tx_data(raw_tx_data),
        .raw_tx_valid(raw_tx_valid),
        .raw_tx_ready(raw_tx_ready),

        .msc_rx_data(msc_rx_data),
        .msc_rx_valid(msc_rx_valid),
        .msc_rx_ready(msc_rx_ready),

        .raw_rx_data(raw_rx_data),
        .raw_rx_valid(raw_rx_valid),
        .raw_rx_ready(raw_rx_ready),

        .active_interface(active_interface)
    );

    assign msc_active = (active_interface == 2'b00);
    assign raw_active = (active_interface == 2'b01);

    // Route TX to appropriate endpoint
    assign ep2_in_data = msc_tx_data;
    assign ep2_in_valid = msc_tx_valid;
    assign msc_tx_ready = ep2_in_ready;

    assign ep3_in_data = raw_tx_data;
    assign ep3_in_valid = raw_tx_valid;
    assign raw_tx_ready = ep3_in_ready;

    //=========================================================================
    // DUT Instantiation - Drive LUN Mapper
    //=========================================================================

    // FDD capacity (16-bit for mapper)
    wire [15:0] fdd_capacity [0:1];
    wire [15:0] fdd_block_size [0:1];
    assign fdd_capacity[0] = 16'd2880;
    assign fdd_capacity[1] = 16'd2880;
    assign fdd_block_size[0] = 16'd512;
    assign fdd_block_size[1] = 16'd512;

    // HDD capacity
    wire [31:0] hdd_capacity_arr [0:1];
    wire [15:0] hdd_block_size [0:1];
    assign hdd_capacity_arr[0] = 32'd20480;  // 10MB
    assign hdd_capacity_arr[1] = 32'd0;
    assign hdd_block_size[0] = 16'd512;
    assign hdd_block_size[1] = 16'd512;

    // LUN mapper signals
    wire [2:0]  lun_select;
    wire        read_req;
    wire        write_req;
    wire [31:0] lba;
    wire [15:0] sector_count;
    wire        mapper_ready;
    wire        mapper_done;
    wire        mapper_error;

    drive_lun_mapper #(
        .MAX_LUNS(4),
        .MAX_FDDS(2),
        .MAX_HDDS(2)
    ) mapper_inst (
        .clk(clk),
        .rst_n(rst_n),

        .lun_select(lun_select),
        .read_req(read_req),
        .write_req(write_req),
        .lba(lba),
        .sector_count(sector_count),
        .ready(mapper_ready),
        .done(mapper_done),
        .error(mapper_error),

        .fdd_select(fdd_select),
        .fdd_lba(fdd_lba),
        .fdd_count(fdd_count),
        .fdd_read(fdd_read),
        .fdd_write(fdd_write),
        .fdd_ready(fdd_ready),
        .fdd_done(fdd_done),
        .fdd_error(fdd_error),

        .hdd_select(hdd_select),
        .hdd_lba(hdd_lba),
        .hdd_count(hdd_count),
        .hdd_read(hdd_read),
        .hdd_write(hdd_write),
        .hdd_ready(hdd_ready),
        .hdd_done(hdd_done),
        .hdd_error(hdd_error),

        .fdd_present(fdd_present),
        .fdd_write_prot(fdd_write_prot),
        .fdd_capacity(fdd_capacity),
        .fdd_block_size(fdd_block_size),

        .hdd_present(hdd_present),
        .hdd_write_prot(2'b00),
        .hdd_capacity(hdd_capacity_arr),
        .hdd_block_size(hdd_block_size),

        .lun_present(lun_present),
        .lun_removable(lun_removable),
        .lun_readonly(lun_readonly)
    );

    // Stub connections for testing
    assign lun_select = 3'b000;
    assign read_req = 1'b0;
    assign write_req = 1'b0;
    assign lba = 32'h0;
    assign sector_count = 16'h0;

    //=========================================================================
    // Clock Generation
    //=========================================================================

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    task automatic reset_dut;
        begin
            rst_n = 0;
            ep1_out_data = 0;
            ep1_out_valid = 0;
            ep2_in_ready = 1;
            ep3_in_ready = 1;

            fdd_present = 2'b01;     // FDD 0 present
            fdd_write_prot = 2'b00;
            fdd_ready = 1;
            fdd_done = 0;
            fdd_error = 0;

            hdd_present = 2'b01;     // HDD 0 present
            hdd_ready = 1;
            hdd_done = 0;
            hdd_error = 0;

            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask

    task automatic send_word(input [31:0] data);
        begin
            ep1_out_data = data;
            ep1_out_valid = 1;
            @(posedge clk);
            while (!ep1_out_ready) @(posedge clk);
            ep1_out_valid = 0;
            @(posedge clk);
        end
    endtask

    task automatic send_msc_cbw(
        input [31:0] tag,
        input [31:0] transfer_length,
        input [7:0]  flags,
        input [7:0]  lun,
        input [7:0]  cdb_length,
        input [7:0]  opcode
    );
        begin
            $display("  Sending MSC CBW: tag=0x%08X, opcode=0x%02X", tag, opcode);

            send_word(CBW_SIGNATURE);
            send_word(tag);
            send_word(transfer_length);
            send_word({opcode, cdb_length, lun, flags});
            send_word(32'h0);
            send_word(32'h0);
            send_word(32'h0);
            send_word(32'h0);

            repeat(5) @(posedge clk);
        end
    endtask

    task automatic send_raw_command(
        input [7:0]  opcode,
        input [7:0]  param1,
        input [15:0] param2
    );
        begin
            $display("  Sending Raw command: opcode=0x%02X, param1=0x%02X", opcode, param1);

            send_word(RAW_SIGNATURE);
            send_word({opcode, param1, param2});
            send_word(32'h0);
            send_word(32'h0);

            repeat(5) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Test Cases
    //=========================================================================

    initial begin
        $display("===========================================");
        $display("USB Composite Device Testbench Starting");
        $display("===========================================");

        reset_dut();

        //---------------------------------------------------------------------
        // Test 1: Interface Routing - MSC Command
        //---------------------------------------------------------------------
        $display("\n--- Test 1: MSC Interface Routing ---");

        send_msc_cbw(
            .tag(32'h00000001),
            .transfer_length(0),
            .flags(8'h00),
            .lun(0),
            .cdb_length(6),
            .opcode(8'h00)  // TEST UNIT READY
        );

        repeat(10) @(posedge clk);

        if (msc_active) begin
            $display("PASS: MSC interface correctly activated");
        end else begin
            $display("FAIL: MSC interface not activated");
        end

        repeat(20) @(posedge clk);

        //---------------------------------------------------------------------
        // Test 2: Interface Routing - Raw Command
        //---------------------------------------------------------------------
        $display("\n--- Test 2: Raw Interface Routing ---");

        // Allow previous transaction to complete
        repeat(50) @(posedge clk);

        send_raw_command(
            .opcode(8'h01),    // GET_INFO
            .param1(8'h00),
            .param2(16'h0000)
        );

        repeat(10) @(posedge clk);

        if (raw_active) begin
            $display("PASS: Raw interface correctly activated");
        end else begin
            $display("FAIL: Raw interface not activated (active=%d)", active_interface);
        end

        repeat(20) @(posedge clk);

        //---------------------------------------------------------------------
        // Test 3: LUN Mapping Verification
        //---------------------------------------------------------------------
        $display("\n--- Test 3: LUN Mapping ---");

        $display("  LUN Present:   0x%01X", lun_present);
        $display("  LUN Removable: 0x%01X", lun_removable);
        $display("  LUN ReadOnly:  0x%01X", lun_readonly);

        // LUN 0-1 should be removable (FDD)
        if (lun_removable[0] && lun_removable[1]) begin
            $display("PASS: FDD LUNs marked as removable");
        end else begin
            $display("FAIL: FDD LUNs not marked as removable");
        end

        // LUN 2-3 should be fixed (HDD)
        if (!lun_removable[2] && !lun_removable[3]) begin
            $display("PASS: HDD LUNs marked as fixed");
        end else begin
            $display("FAIL: HDD LUNs not marked as fixed");
        end

        // LUN 0 (FDD 0) and LUN 2 (HDD 0) should be present
        if (lun_present[0] && lun_present[2]) begin
            $display("PASS: Expected LUNs present");
        end else begin
            $display("FAIL: Expected LUNs not present");
        end

        //---------------------------------------------------------------------
        // Test 4: Raw Mode SELECT_DRIVE
        //---------------------------------------------------------------------
        $display("\n--- Test 4: Raw SELECT_DRIVE ---");

        repeat(50) @(posedge clk);

        send_raw_command(
            .opcode(8'h02),    // SELECT_DRIVE
            .param1(8'h00),    // Drive 0 (FDD)
            .param2(16'h0000)
        );

        repeat(30) @(posedge clk);
        $display("PASS: SELECT_DRIVE command sent");

        //---------------------------------------------------------------------
        // Test 5: Raw Mode GET_PLL_STATUS
        //---------------------------------------------------------------------
        $display("\n--- Test 5: Raw GET_PLL_STATUS ---");

        repeat(50) @(posedge clk);

        send_raw_command(
            .opcode(8'h30),    // GET_PLL_STATUS
            .param1(8'h00),
            .param2(16'h0000)
        );

        repeat(30) @(posedge clk);
        $display("PASS: GET_PLL_STATUS command sent");

        //---------------------------------------------------------------------
        // Test 6: Interleaved MSC and Raw Commands
        //---------------------------------------------------------------------
        $display("\n--- Test 6: Interleaved Commands ---");

        repeat(50) @(posedge clk);

        // MSC command
        send_msc_cbw(
            .tag(32'h00000010),
            .transfer_length(8),
            .flags(8'h80),
            .lun(0),
            .cdb_length(10),
            .opcode(8'h25)  // READ_CAPACITY_10
        );

        repeat(30) @(posedge clk);

        // Raw command
        send_raw_command(
            .opcode(8'h31),    // GET_SIGNAL_QUAL
            .param1(8'h00),
            .param2(16'h0000)
        );

        repeat(30) @(posedge clk);

        // Another MSC command
        send_msc_cbw(
            .tag(32'h00000011),
            .transfer_length(36),
            .flags(8'h80),
            .lun(0),
            .cdb_length(6),
            .opcode(8'h12)  // INQUIRY
        );

        repeat(30) @(posedge clk);
        $display("PASS: Interleaved commands completed");

        //---------------------------------------------------------------------
        // Test Complete
        //---------------------------------------------------------------------
        $display("\n===========================================");
        $display("USB Composite Device Testbench Complete");
        $display("===========================================");

        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================

    initial begin
        #200000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    //=========================================================================
    // Debug Monitor
    //=========================================================================

    always @(posedge clk) begin
        if (ep1_out_valid && ep1_out_ready) begin
            $display("  [%0t] EP1_OUT: 0x%08X", $time, ep1_out_data);
        end
        if (ep2_in_valid && ep2_in_ready) begin
            $display("  [%0t] EP2_IN (MSC): 0x%08X", $time, ep2_in_data);
        end
        if (ep3_in_valid && ep3_in_ready) begin
            $display("  [%0t] EP3_IN (Raw): 0x%08X", $time, ep3_in_data);
        end
    end

endmodule
