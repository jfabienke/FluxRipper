//-----------------------------------------------------------------------------
// tb_msc_protocol.v
// Testbench for USB Mass Storage Class BBB Protocol Handler
//
// Created: 2025-12-05 16:50
//
// Tests:
//   - CBW parsing and validation
//   - SCSI command extraction
//   - CSW generation
//   - Error handling
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_msc_protocol;

    //=========================================================================
    // Parameters
    //=========================================================================

    parameter CLK_PERIOD = 10;  // 100 MHz

    //=========================================================================
    // Test Signals
    //=========================================================================

    reg         clk;
    reg         rst_n;

    // USB RX (from host)
    reg  [31:0] usb_rx_data;
    reg         usb_rx_valid;
    wire        usb_rx_ready;

    // USB TX (to host)
    wire [31:0] usb_tx_data;
    wire        usb_tx_valid;
    reg         usb_tx_ready;

    // SCSI Engine Interface
    wire [127:0] scsi_cdb;
    wire [7:0]   scsi_cdb_length;
    wire [2:0]   scsi_lun;
    wire [31:0]  scsi_transfer_length;
    wire         scsi_data_in;
    wire         scsi_valid;
    reg          scsi_ready;
    reg          scsi_done;
    reg  [7:0]   scsi_status;

    // Data Interface
    wire [31:0] data_out;
    wire        data_out_valid;
    reg         data_out_ready;
    reg  [31:0] data_in;
    reg         data_in_valid;
    wire        data_in_ready;

    // Status
    wire [7:0]  msc_state;
    wire        cbw_valid;
    wire        cbw_error;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================

    msc_protocol #(
        .MAX_LUNS(4),
        .MAX_SECTOR_COUNT(128),
        .SECTOR_SIZE(512)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .usb_rx_data(usb_rx_data),
        .usb_rx_valid(usb_rx_valid),
        .usb_rx_ready(usb_rx_ready),

        .usb_tx_data(usb_tx_data),
        .usb_tx_valid(usb_tx_valid),
        .usb_tx_ready(usb_tx_ready),

        .scsi_cdb(scsi_cdb),
        .scsi_cdb_length(scsi_cdb_length),
        .scsi_lun(scsi_lun),
        .scsi_transfer_length(scsi_transfer_length),
        .scsi_data_in(scsi_data_in),
        .scsi_valid(scsi_valid),
        .scsi_ready(scsi_ready),
        .scsi_done(scsi_done),
        .scsi_status(scsi_status),

        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .data_out_ready(data_out_ready),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .data_in_ready(data_in_ready),

        .msc_state(msc_state),
        .cbw_valid(cbw_valid),
        .cbw_error(cbw_error)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //=========================================================================
    // CBW Constants
    //=========================================================================

    localparam CBW_SIGNATURE = 32'h43425355;  // "USBC"
    localparam CSW_SIGNATURE = 32'h53425355;  // "USBS"

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    task automatic reset_dut;
        begin
            rst_n = 0;
            usb_rx_data = 0;
            usb_rx_valid = 0;
            usb_tx_ready = 1;
            scsi_ready = 0;
            scsi_done = 0;
            scsi_status = 0;
            data_out_ready = 1;
            data_in = 0;
            data_in_valid = 0;

            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask

    task automatic send_word(input [31:0] data);
        begin
            usb_rx_data = data;
            usb_rx_valid = 1;
            @(posedge clk);
            while (!usb_rx_ready) @(posedge clk);
            usb_rx_valid = 0;
            @(posedge clk);
        end
    endtask

    task automatic send_cbw(
        input [31:0] tag,
        input [31:0] transfer_length,
        input [7:0]  flags,
        input [7:0]  lun,
        input [7:0]  cdb_length,
        input [127:0] cdb
    );
        begin
            // Word 0: Signature
            send_word(CBW_SIGNATURE);

            // Word 1: Tag
            send_word(tag);

            // Word 2: Transfer length
            send_word(transfer_length);

            // Word 3: Flags, LUN, CDB length, CDB[0]
            send_word({cdb[7:0], cdb_length, lun, flags});

            // Word 4-7: CDB[1-15] (padded to 16 bytes)
            send_word({cdb[39:32], cdb[31:24], cdb[23:16], cdb[15:8]});
            send_word({cdb[71:64], cdb[63:56], cdb[55:48], cdb[47:40]});
            send_word({cdb[103:96], cdb[95:88], cdb[87:80], cdb[79:72]});
            send_word({8'h00, 8'h00, cdb[119:112], cdb[111:104]});
        end
    endtask

    task automatic complete_scsi_command(input [7:0] status);
        begin
            scsi_ready = 1;
            @(posedge clk);
            while (!scsi_valid) @(posedge clk);
            scsi_ready = 0;

            // Process command (simulate some delay)
            repeat(5) @(posedge clk);

            scsi_status = status;
            scsi_done = 1;
            @(posedge clk);
            scsi_done = 0;
        end
    endtask

    task automatic wait_for_csw;
        reg [31:0] csw_words [0:3];
        integer i;
        begin
            i = 0;
            while (i < 4) begin
                @(posedge clk);
                if (usb_tx_valid && usb_tx_ready) begin
                    csw_words[i] = usb_tx_data;
                    i = i + 1;
                end
            end

            // Verify CSW signature
            if (csw_words[0] != CSW_SIGNATURE) begin
                $display("ERROR: Invalid CSW signature: 0x%08X", csw_words[0]);
            end else begin
                $display("CSW received: Tag=0x%08X, Residue=%d, Status=%d",
                         csw_words[1], csw_words[2], csw_words[3][7:0]);
            end
        end
    endtask

    //=========================================================================
    // Test Cases
    //=========================================================================

    initial begin
        $display("===========================================");
        $display("MSC Protocol Testbench Starting");
        $display("===========================================");

        reset_dut();

        //---------------------------------------------------------------------
        // Test 1: TEST UNIT READY Command
        //---------------------------------------------------------------------
        $display("\n--- Test 1: TEST UNIT READY ---");

        // send_cbw(tag, transfer_length, flags, lun, cdb_length, cdb)
        send_cbw(32'h00000001, 32'd0, 8'h00, 8'd0, 8'd6, {120'h0, 8'h00});

        complete_scsi_command(8'h00);  // Good status
        wait_for_csw();

        repeat(10) @(posedge clk);

        //---------------------------------------------------------------------
        // Test 2: INQUIRY Command (Data-In)
        //---------------------------------------------------------------------
        $display("\n--- Test 2: INQUIRY ---");

        // INQUIRY: tag=2, len=36, flags=0x80 (Data-In), lun=0, cdb_len=6
        send_cbw(32'h00000002, 32'd36, 8'h80, 8'd0, 8'd6, {88'h0, 8'd36, 16'h0, 8'h12});

        complete_scsi_command(8'h00);

        // Send INQUIRY data (simplified - just 9 words)
        repeat(9) begin
            data_in = 32'hDEADBEEF;
            data_in_valid = 1;
            @(posedge clk);
            while (!data_in_ready) @(posedge clk);
        end
        data_in_valid = 0;

        wait_for_csw();

        repeat(10) @(posedge clk);

        //---------------------------------------------------------------------
        // Test 3: READ_10 Command
        //---------------------------------------------------------------------
        $display("\n--- Test 3: READ_10 ---");

        // READ_10: tag=3, len=512, flags=0x80 (Data-In), lun=0, cdb_len=10
        send_cbw(32'h00000003, 32'd512, 8'h80, 8'd0, 8'd10, {48'h0, 16'h0001, 32'h00000000, 8'h00, 8'h28});

        complete_scsi_command(8'h00);

        // Send sector data (128 words)
        repeat(128) begin
            data_in = 32'hCAFEBABE;
            data_in_valid = 1;
            @(posedge clk);
            while (!data_in_ready) @(posedge clk);
        end
        data_in_valid = 0;

        wait_for_csw();

        repeat(10) @(posedge clk);

        //---------------------------------------------------------------------
        // Test 4: Invalid CBW Signature
        //---------------------------------------------------------------------
        $display("\n--- Test 4: Invalid CBW Signature ---");

        send_word(32'hBADC0FFE);  // Invalid signature
        send_word(32'h00000004);  // Tag
        send_word(32'h00000000);  // Transfer length
        send_word(32'h00000006);  // Flags/LUN/CDB length
        send_word(32'h00000000);
        send_word(32'h00000000);
        send_word(32'h00000000);
        send_word(32'h00000000);

        repeat(20) @(posedge clk);

        if (cbw_error) begin
            $display("PASS: CBW error detected for invalid signature");
        end else begin
            $display("FAIL: CBW error not detected");
        end

        //---------------------------------------------------------------------
        // Test 5: WRITE_10 Command
        //---------------------------------------------------------------------
        $display("\n--- Test 5: WRITE_10 ---");

        // WRITE_10: tag=5, len=512, flags=0x00 (Data-Out), lun=0, cdb_len=10
        send_cbw(32'h00000005, 32'd512, 8'h00, 8'd0, 8'd10, {48'h0, 16'h0001, 32'h00000010, 8'h00, 8'h2A});

        // Receive write data
        repeat(128) begin
            @(posedge clk);
            if (data_out_valid && data_out_ready) begin
                // Data received
            end
        end

        complete_scsi_command(8'h00);
        wait_for_csw();

        repeat(10) @(posedge clk);

        //---------------------------------------------------------------------
        // Test Complete
        //---------------------------------------------------------------------
        $display("\n===========================================");
        $display("MSC Protocol Testbench Complete");
        $display("===========================================");

        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================

    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
