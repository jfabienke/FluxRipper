//-----------------------------------------------------------------------------
// msc_protocol.v
// USB Mass Storage Class - Bulk-Only Transport (BBB) Protocol Handler
//
// Created: 2025-12-05 15:00
//
// Implements the USB Mass Storage Class Bulk-Only Transport protocol
// as defined in the USB Mass Storage Class Specification.
//
// Protocol flow:
//   1. Host sends 31-byte CBW (Command Block Wrapper) on EP1 OUT
//   2. Device processes SCSI command from CBW
//   3. Optional data phase (IN or OUT depending on command)
//   4. Device sends 13-byte CSW (Command Status Wrapper) on EP2 IN
//
// CBW Structure (31 bytes):
//   [3:0]   dCBWSignature    = 0x43425355 ("USBC")
//   [7:4]   dCBWTag          = Tag echoed in CSW
//   [11:8]  dCBWDataTransferLength
//   [12]    bmCBWFlags       = Bit 7: 0=OUT, 1=IN
//   [13]    bCBWLUN          = Bits 3:0
//   [14]    bCBWCBLength     = 1-16
//   [30:15] CBWCB            = SCSI CDB (Command Descriptor Block)
//
// CSW Structure (13 bytes):
//   [3:0]   dCSWSignature    = 0x53425355 ("USBS")
//   [7:4]   dCSWTag          = Echoed from CBW
//   [11:8]  dCSWDataResidue  = Bytes not transferred
//   [12]    bCSWStatus       = 0=Pass, 1=Fail, 2=Phase Error
//-----------------------------------------------------------------------------

module msc_protocol #(
    parameter MAX_LUNS         = 4,          // Maximum LUN count
    parameter MAX_SECTOR_COUNT = 128,        // Max sectors per transfer
    parameter SECTOR_SIZE      = 512         // Bytes per sector
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // USB Interface
    //=========================================================================

    // Commands from host (EP1 OUT via composite mux)
    input  wire [31:0] usb_rx_data,
    input  wire        usb_rx_valid,
    output reg         usb_rx_ready,

    // Responses to host (EP2 IN via composite mux)
    output reg  [31:0] usb_tx_data,
    output reg         usb_tx_valid,
    input  wire        usb_tx_ready,

    //=========================================================================
    // SCSI Engine Interface
    //=========================================================================

    // SCSI command output
    output reg  [127:0] scsi_cdb,           // 16-byte SCSI CDB
    output reg  [7:0]   scsi_cdb_length,    // Actual CDB length (1-16)
    output reg  [2:0]   scsi_lun,           // Logical Unit Number
    output reg          scsi_cmd_valid,     // Command is valid
    input  wire         scsi_cmd_ready,     // SCSI engine ready

    // SCSI response input
    input  wire [7:0]   scsi_status,        // SCSI status byte
    input  wire         scsi_status_valid,  // Status is valid
    output reg          scsi_status_ready,  // Ready for status

    // Data transfer signaling
    output reg          scsi_data_out,      // Expecting data from host
    output reg          scsi_data_in,       // Sending data to host
    output reg  [31:0]  scsi_xfer_length,   // Expected transfer length
    input  wire         scsi_xfer_done,     // Transfer complete
    input  wire [31:0]  scsi_residue,       // Bytes not transferred

    //=========================================================================
    // Sector Buffer Interface
    //=========================================================================

    // Write to buffer (data from host for WRITE commands)
    output wire [31:0] buf_wr_data,
    output wire        buf_wr_valid,
    input  wire        buf_wr_ready,

    // Read from buffer (data to host for READ commands)
    input  wire [31:0] buf_rd_data,
    input  wire        buf_rd_valid,
    output wire        buf_rd_ready,

    //=========================================================================
    // Status
    //=========================================================================

    output reg         transfer_active,     // BBB transfer in progress
    output reg         transfer_done,       // Transfer complete
    output reg  [7:0]  msc_state,          // Current state for debug
    output reg  [31:0] cbw_count,          // CBW packets received
    output reg  [31:0] csw_count,          // CSW packets sent
    output reg  [7:0]  last_error          // Last error code
);

    //=========================================================================
    // Constants
    //=========================================================================

    localparam CBW_SIGNATURE = 32'h43425355;  // "USBC"
    localparam CSW_SIGNATURE = 32'h53425355;  // "USBS"

    // CSW Status values
    localparam CSW_STATUS_PASS        = 8'h00;
    localparam CSW_STATUS_FAIL        = 8'h01;
    localparam CSW_STATUS_PHASE_ERROR = 8'h02;

    // State machine states
    localparam ST_IDLE           = 4'd0;
    localparam ST_RX_CBW_1       = 4'd1;   // Receive CBW word 0 (signature)
    localparam ST_RX_CBW_2       = 4'd2;   // Receive CBW word 1 (tag)
    localparam ST_RX_CBW_3       = 4'd3;   // Receive CBW word 2 (length)
    localparam ST_RX_CBW_4       = 4'd4;   // Receive CBW word 3 (flags/LUN/CBLen)
    localparam ST_RX_CBW_CDB     = 4'd5;   // Receive CBW words 4-7 (CDB)
    localparam ST_VALIDATE_CBW   = 4'd6;   // Validate CBW
    localparam ST_EXEC_SCSI      = 4'd7;   // Execute SCSI command
    localparam ST_DATA_OUT       = 4'd8;   // Data from host (WRITE)
    localparam ST_DATA_IN        = 4'd9;   // Data to host (READ)
    localparam ST_WAIT_SCSI      = 4'd10;  // Wait for SCSI completion
    localparam ST_BUILD_CSW      = 4'd11;  // Build CSW response
    localparam ST_TX_CSW         = 4'd12;  // Transmit CSW
    localparam ST_ERROR          = 4'd13;  // Error state

    //=========================================================================
    // Registers
    //=========================================================================

    reg [3:0]  state;
    reg [3:0]  state_next;

    // CBW fields
    reg [31:0] cbw_tag;
    reg [31:0] cbw_data_length;
    reg        cbw_direction;          // 0=OUT, 1=IN
    reg [3:0]  cbw_lun;
    reg [4:0]  cbw_cb_length;

    // CDB capture (16 bytes = 4 words)
    reg [31:0] cdb_word [0:3];
    reg [2:0]  cdb_word_cnt;

    // CSW fields
    reg [31:0] csw_residue;
    reg [7:0]  csw_status;
    reg [1:0]  csw_word_cnt;

    // Error tracking
    reg        cbw_valid;

    //=========================================================================
    // State Machine
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= state_next;
        end
    end

    always @(*) begin
        state_next = state;

        case (state)
            ST_IDLE: begin
                if (usb_rx_valid) begin
                    state_next = ST_RX_CBW_1;
                end
            end

            ST_RX_CBW_1: begin
                // Check signature
                if (usb_rx_valid && usb_rx_ready) begin
                    if (usb_rx_data == CBW_SIGNATURE)
                        state_next = ST_RX_CBW_2;
                    else
                        state_next = ST_ERROR;
                end
            end

            ST_RX_CBW_2: begin
                // Receive tag
                if (usb_rx_valid && usb_rx_ready)
                    state_next = ST_RX_CBW_3;
            end

            ST_RX_CBW_3: begin
                // Receive data transfer length
                if (usb_rx_valid && usb_rx_ready)
                    state_next = ST_RX_CBW_4;
            end

            ST_RX_CBW_4: begin
                // Receive flags/LUN/CB length
                if (usb_rx_valid && usb_rx_ready)
                    state_next = ST_RX_CBW_CDB;
            end

            ST_RX_CBW_CDB: begin
                // Receive CDB (4 words = 16 bytes)
                if (usb_rx_valid && usb_rx_ready) begin
                    if (cdb_word_cnt == 3'd3)
                        state_next = ST_VALIDATE_CBW;
                end
            end

            ST_VALIDATE_CBW: begin
                if (cbw_valid)
                    state_next = ST_EXEC_SCSI;
                else
                    state_next = ST_ERROR;
            end

            ST_EXEC_SCSI: begin
                // Send command to SCSI engine
                if (scsi_cmd_ready) begin
                    if (cbw_data_length > 0) begin
                        if (cbw_direction)
                            state_next = ST_DATA_IN;
                        else
                            state_next = ST_DATA_OUT;
                    end else begin
                        state_next = ST_WAIT_SCSI;
                    end
                end
            end

            ST_DATA_OUT: begin
                // Receive data from host
                if (scsi_xfer_done)
                    state_next = ST_WAIT_SCSI;
            end

            ST_DATA_IN: begin
                // Send data to host
                if (scsi_xfer_done)
                    state_next = ST_WAIT_SCSI;
            end

            ST_WAIT_SCSI: begin
                // Wait for SCSI status
                if (scsi_status_valid)
                    state_next = ST_BUILD_CSW;
            end

            ST_BUILD_CSW: begin
                state_next = ST_TX_CSW;
            end

            ST_TX_CSW: begin
                // Transmit 4 words (13 bytes, padded to 16)
                if (usb_tx_valid && usb_tx_ready) begin
                    if (csw_word_cnt == 2'd3)
                        state_next = ST_IDLE;
                end
            end

            ST_ERROR: begin
                // Build error CSW
                state_next = ST_BUILD_CSW;
            end

            default: state_next = ST_IDLE;
        endcase
    end

    //=========================================================================
    // CBW Reception
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cbw_tag <= 32'h0;
            cbw_data_length <= 32'h0;
            cbw_direction <= 1'b0;
            cbw_lun <= 4'h0;
            cbw_cb_length <= 5'h0;
            cdb_word[0] <= 32'h0;
            cdb_word[1] <= 32'h0;
            cdb_word[2] <= 32'h0;
            cdb_word[3] <= 32'h0;
            cdb_word_cnt <= 3'h0;
            cbw_valid <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    cdb_word_cnt <= 3'h0;
                    cbw_valid <= 1'b0;
                end

                ST_RX_CBW_2: begin
                    if (usb_rx_valid && usb_rx_ready)
                        cbw_tag <= usb_rx_data;
                end

                ST_RX_CBW_3: begin
                    if (usb_rx_valid && usb_rx_ready)
                        cbw_data_length <= usb_rx_data;
                end

                ST_RX_CBW_4: begin
                    if (usb_rx_valid && usb_rx_ready) begin
                        cbw_direction <= usb_rx_data[7];      // Bit 7 of byte 12
                        cbw_lun <= usb_rx_data[11:8];         // Bits 3:0 of byte 13
                        cbw_cb_length <= usb_rx_data[20:16];  // Bits 4:0 of byte 14
                    end
                end

                ST_RX_CBW_CDB: begin
                    if (usb_rx_valid && usb_rx_ready) begin
                        cdb_word[cdb_word_cnt] <= usb_rx_data;
                        cdb_word_cnt <= cdb_word_cnt + 1'b1;
                    end
                end

                ST_VALIDATE_CBW: begin
                    // Validate CBW
                    // LUN must be < MAX_LUNS
                    // CB length must be 1-16
                    if (cbw_lun < MAX_LUNS && cbw_cb_length >= 1 && cbw_cb_length <= 16)
                        cbw_valid <= 1'b1;
                    else
                        cbw_valid <= 1'b0;
                end
            endcase
        end
    end

    //=========================================================================
    // SCSI Command Output
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scsi_cdb <= 128'h0;
            scsi_cdb_length <= 8'h0;
            scsi_lun <= 3'h0;
            scsi_cmd_valid <= 1'b0;
            scsi_data_out <= 1'b0;
            scsi_data_in <= 1'b0;
            scsi_xfer_length <= 32'h0;
        end else begin
            case (state)
                ST_EXEC_SCSI: begin
                    // Pack CDB words into 128-bit CDB
                    scsi_cdb <= {cdb_word[3], cdb_word[2], cdb_word[1], cdb_word[0]};
                    scsi_cdb_length <= {3'h0, cbw_cb_length};
                    scsi_lun <= cbw_lun[2:0];
                    scsi_cmd_valid <= 1'b1;
                    scsi_xfer_length <= cbw_data_length;
                    scsi_data_out <= (cbw_data_length > 0) && !cbw_direction;
                    scsi_data_in <= (cbw_data_length > 0) && cbw_direction;
                end

                ST_WAIT_SCSI, ST_BUILD_CSW, ST_TX_CSW, ST_IDLE: begin
                    scsi_cmd_valid <= 1'b0;
                    scsi_data_out <= 1'b0;
                    scsi_data_in <= 1'b0;
                end
            endcase
        end
    end

    //=========================================================================
    // CSW Transmission
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csw_residue <= 32'h0;
            csw_status <= CSW_STATUS_PASS;
            csw_word_cnt <= 2'h0;
        end else begin
            case (state)
                ST_IDLE: begin
                    csw_word_cnt <= 2'h0;
                end

                ST_WAIT_SCSI: begin
                    if (scsi_status_valid) begin
                        csw_residue <= scsi_residue;
                        // Map SCSI status to CSW status
                        if (scsi_status == 8'h00)
                            csw_status <= CSW_STATUS_PASS;
                        else
                            csw_status <= CSW_STATUS_FAIL;
                    end
                end

                ST_ERROR: begin
                    csw_residue <= cbw_data_length;
                    csw_status <= CSW_STATUS_PHASE_ERROR;
                end

                ST_TX_CSW: begin
                    if (usb_tx_valid && usb_tx_ready)
                        csw_word_cnt <= csw_word_cnt + 1'b1;
                end
            endcase
        end
    end

    // CSW TX data mux
    always @(*) begin
        case (csw_word_cnt)
            2'd0: usb_tx_data = CSW_SIGNATURE;
            2'd1: usb_tx_data = cbw_tag;
            2'd2: usb_tx_data = csw_residue;
            2'd3: usb_tx_data = {24'h0, csw_status};
            default: usb_tx_data = 32'h0;
        endcase
    end

    //=========================================================================
    // Control Signals
    //=========================================================================

    // USB RX ready - accept data during CBW reception and DATA_OUT
    always @(*) begin
        case (state)
            ST_IDLE, ST_RX_CBW_1, ST_RX_CBW_2, ST_RX_CBW_3, ST_RX_CBW_4, ST_RX_CBW_CDB:
                usb_rx_ready = 1'b1;
            ST_DATA_OUT:
                usb_rx_ready = buf_wr_ready;
            default:
                usb_rx_ready = 1'b0;
        endcase
    end

    // USB TX valid - assert during CSW transmission and DATA_IN
    always @(*) begin
        case (state)
            ST_TX_CSW:
                usb_tx_valid = 1'b1;
            ST_DATA_IN:
                usb_tx_valid = buf_rd_valid;
            default:
                usb_tx_valid = 1'b0;
        endcase
    end

    // Sector buffer interface
    assign buf_wr_data = usb_rx_data;
    assign buf_wr_valid = (state == ST_DATA_OUT) && usb_rx_valid;
    assign buf_rd_ready = (state == ST_DATA_IN) && usb_tx_ready;

    // SCSI status ready
    always @(*) begin
        scsi_status_ready = (state == ST_WAIT_SCSI);
    end

    //=========================================================================
    // Status Outputs
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            transfer_active <= 1'b0;
            transfer_done <= 1'b0;
            msc_state <= 8'h0;
            cbw_count <= 32'h0;
            csw_count <= 32'h0;
            last_error <= 8'h0;
        end else begin
            msc_state <= {4'h0, state};
            transfer_done <= 1'b0;

            // Transfer active when not idle
            transfer_active <= (state != ST_IDLE);

            // Count CBWs
            if (state == ST_VALIDATE_CBW && cbw_valid)
                cbw_count <= cbw_count + 1'b1;

            // Count CSWs
            if (state == ST_TX_CSW && csw_word_cnt == 2'd3 && usb_tx_valid && usb_tx_ready) begin
                csw_count <= csw_count + 1'b1;
                transfer_done <= 1'b1;
            end

            // Track errors
            if (state == ST_ERROR)
                last_error <= 8'h01;
            else if (state == ST_IDLE)
                last_error <= 8'h00;
        end
    end

endmodule
