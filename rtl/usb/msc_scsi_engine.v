//-----------------------------------------------------------------------------
// msc_scsi_engine.v
// USB Mass Storage Class - SCSI Command Decoder and Executor
//
// Created: 2025-12-05 15:25
//
// Decodes SCSI commands from the MSC protocol layer and translates them
// to drive operations. Supports the minimal SCSI command set required
// for USB Mass Storage compliance.
//
// Supported SCSI Commands:
//   0x00  TEST_UNIT_READY     - Check if drive is ready
//   0x03  REQUEST_SENSE       - Return sense data
//   0x12  INQUIRY             - Return device identification
//   0x1A  MODE_SENSE_6        - Return mode parameters
//   0x1B  START_STOP_UNIT     - Control motor
//   0x1E  PREVENT_ALLOW_MEDIUM_REMOVAL
//   0x23  READ_FORMAT_CAPACITIES
//   0x25  READ_CAPACITY_10    - Return capacity
//   0x28  READ_10             - Read sectors
//   0x2A  WRITE_10            - Write sectors
//   0x5A  MODE_SENSE_10       - Return mode parameters (10-byte)
//-----------------------------------------------------------------------------

module msc_scsi_engine #(
    parameter MAX_LUNS = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // Command Interface (from msc_protocol)
    //=========================================================================

    input  wire [127:0] scsi_cdb,           // 16-byte SCSI CDB
    input  wire [7:0]   scsi_cdb_length,    // Actual CDB length
    input  wire [2:0]   scsi_lun,           // Logical Unit Number
    input  wire         scsi_cmd_valid,     // Command is valid
    output reg          scsi_cmd_ready,     // Ready for command

    // Status output
    output reg  [7:0]   scsi_status,        // SCSI status byte
    output reg          scsi_status_valid,  // Status is valid
    input  wire         scsi_status_ready,  // Protocol ready for status

    // Data transfer signaling
    input  wire         scsi_data_out,      // Expecting data from host
    input  wire         scsi_data_in,       // Sending data to host
    input  wire [31:0]  scsi_xfer_length,   // Expected transfer length
    output reg          scsi_xfer_done,     // Transfer complete
    output reg  [31:0]  scsi_residue,       // Bytes not transferred

    //=========================================================================
    // Response Data Interface
    //=========================================================================

    output reg  [31:0] resp_data,           // Response data (INQUIRY, etc.)
    output reg         resp_valid,
    input  wire        resp_ready,
    output reg  [15:0] resp_length,         // Total response length

    //=========================================================================
    // Drive Control Interface (to drive_lun_mapper)
    //=========================================================================

    output reg  [2:0]  drive_lun,           // Target LUN
    output reg         drive_read_req,      // Read sector request
    output reg         drive_write_req,     // Write sector request
    output reg  [31:0] drive_lba,           // Logical Block Address
    output reg  [15:0] drive_sector_count,  // Sector count
    input  wire        drive_ready,         // Drive ready for command
    input  wire        drive_done,          // Command complete
    input  wire        drive_error,         // Command error

    // Motor control
    output reg         drive_motor_on,
    output reg         drive_motor_off,

    //=========================================================================
    // LUN Configuration (from drive_lun_mapper)
    //=========================================================================

    input  wire [MAX_LUNS-1:0] lun_present,
    input  wire [MAX_LUNS-1:0] lun_removable,
    input  wire [MAX_LUNS-1:0] lun_readonly,
    output reg  [2:0]  lun_query_sel,                 // Which LUN to query
    input  wire [31:0] lun_capacity_sel,              // Capacity of selected LUN
    input  wire [15:0] lun_block_size_sel,            // Block size of selected LUN

    //=========================================================================
    // Status
    //=========================================================================

    output reg  [7:0]  engine_state,
    output reg  [7:0]  last_opcode,
    output reg  [7:0]  sense_key,
    output reg  [7:0]  asc,                 // Additional Sense Code
    output reg  [7:0]  ascq                 // Additional Sense Code Qualifier
);

    //=========================================================================
    // SCSI Constants
    //=========================================================================

    // SCSI Opcodes
    localparam OP_TEST_UNIT_READY     = 8'h00;
    localparam OP_REQUEST_SENSE       = 8'h03;
    localparam OP_INQUIRY             = 8'h12;
    localparam OP_MODE_SENSE_6        = 8'h1A;
    localparam OP_START_STOP_UNIT     = 8'h1B;
    localparam OP_PREVENT_ALLOW       = 8'h1E;
    localparam OP_READ_FORMAT_CAP     = 8'h23;
    localparam OP_READ_CAPACITY_10    = 8'h25;
    localparam OP_READ_10             = 8'h28;
    localparam OP_WRITE_10            = 8'h2A;
    localparam OP_MODE_SENSE_10       = 8'h5A;

    // SCSI Status
    localparam STATUS_GOOD            = 8'h00;
    localparam STATUS_CHECK_CONDITION = 8'h02;

    // Sense Keys
    localparam SK_NO_SENSE            = 4'h0;
    localparam SK_NOT_READY           = 4'h2;
    localparam SK_MEDIUM_ERROR        = 4'h3;
    localparam SK_ILLEGAL_REQUEST     = 4'h5;
    localparam SK_UNIT_ATTENTION      = 4'h6;
    localparam SK_DATA_PROTECT        = 4'h7;

    // ASC/ASCQ
    localparam ASC_NO_SENSE           = 8'h00;
    localparam ASC_LUN_NOT_READY      = 8'h04;
    localparam ASC_INVALID_OPCODE     = 8'h20;
    localparam ASC_LBA_OUT_OF_RANGE   = 8'h21;
    localparam ASC_INVALID_FIELD      = 8'h24;
    localparam ASC_WRITE_PROTECTED    = 8'h27;
    localparam ASC_MEDIUM_NOT_PRESENT = 8'h3A;

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_IDLE          = 4'd0;
    localparam ST_DECODE        = 4'd1;
    localparam ST_TEST_UNIT     = 4'd2;
    localparam ST_INQUIRY       = 4'd3;
    localparam ST_READ_CAP      = 4'd4;
    localparam ST_READ_10       = 4'd5;
    localparam ST_WRITE_10      = 4'd6;
    localparam ST_WAIT_DRIVE    = 4'd7;
    localparam ST_SEND_RESP     = 4'd8;
    localparam ST_COMPLETE      = 4'd9;
    localparam ST_ERROR         = 4'd10;

    reg [3:0]  state;
    reg [3:0]  state_next;

    //=========================================================================
    // CDB Field Extraction
    //=========================================================================

    wire [7:0]  cdb_opcode   = scsi_cdb[7:0];
    wire [7:0]  cdb_byte1    = scsi_cdb[15:8];
    wire [7:0]  cdb_byte2    = scsi_cdb[23:16];
    wire [7:0]  cdb_byte3    = scsi_cdb[31:24];
    wire [7:0]  cdb_byte4    = scsi_cdb[39:32];
    wire [7:0]  cdb_byte5    = scsi_cdb[47:40];
    wire [7:0]  cdb_byte6    = scsi_cdb[55:48];
    wire [7:0]  cdb_byte7    = scsi_cdb[63:56];
    wire [7:0]  cdb_byte8    = scsi_cdb[71:64];
    wire [7:0]  cdb_byte9    = scsi_cdb[79:72];

    // READ_10 / WRITE_10 field extraction
    wire [31:0] rw10_lba = {cdb_byte2, cdb_byte3, cdb_byte4, cdb_byte5};
    wire [15:0] rw10_count = {cdb_byte7, cdb_byte8};

    // LUN validity check
    wire lun_valid = (scsi_lun < MAX_LUNS) && lun_present[scsi_lun];

    //=========================================================================
    // Response Data Generation
    //=========================================================================

    // Response buffer for fixed responses (INQUIRY, READ_CAPACITY, etc.)
    reg [31:0] resp_buffer [0:15];  // 64 bytes max
    reg [3:0]  resp_word_idx;
    reg [3:0]  resp_word_count;

    // INQUIRY response (36 bytes)
    wire [7:0] inq_pdt = lun_removable[scsi_lun] ? 8'h00 : 8'h00;  // Direct access
    wire [7:0] inq_rmb = lun_removable[scsi_lun] ? 8'h80 : 8'h00;  // Removable bit

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
                if (scsi_cmd_valid)
                    state_next = ST_DECODE;
            end

            ST_DECODE: begin
                if (!lun_valid && cdb_opcode != OP_INQUIRY && cdb_opcode != OP_REQUEST_SENSE) begin
                    state_next = ST_ERROR;
                end else begin
                    case (cdb_opcode)
                        OP_TEST_UNIT_READY: state_next = ST_TEST_UNIT;
                        OP_INQUIRY:         state_next = ST_INQUIRY;
                        OP_READ_CAPACITY_10:state_next = ST_READ_CAP;
                        OP_READ_10:         state_next = ST_READ_10;
                        OP_WRITE_10:        state_next = ST_WRITE_10;
                        OP_REQUEST_SENSE:   state_next = ST_SEND_RESP;
                        OP_MODE_SENSE_6:    state_next = ST_SEND_RESP;
                        OP_MODE_SENSE_10:   state_next = ST_SEND_RESP;
                        OP_START_STOP_UNIT: state_next = ST_COMPLETE;
                        OP_PREVENT_ALLOW:   state_next = ST_COMPLETE;
                        OP_READ_FORMAT_CAP: state_next = ST_SEND_RESP;
                        default:            state_next = ST_ERROR;
                    endcase
                end
            end

            ST_TEST_UNIT: begin
                state_next = ST_COMPLETE;
            end

            ST_INQUIRY: begin
                state_next = ST_SEND_RESP;
            end

            ST_READ_CAP: begin
                state_next = ST_SEND_RESP;
            end

            ST_READ_10, ST_WRITE_10: begin
                if (drive_ready)
                    state_next = ST_WAIT_DRIVE;
            end

            ST_WAIT_DRIVE: begin
                if (drive_done || drive_error)
                    state_next = drive_error ? ST_ERROR : ST_COMPLETE;
            end

            ST_SEND_RESP: begin
                if (resp_valid && resp_ready) begin
                    if (resp_word_idx >= resp_word_count - 1)
                        state_next = ST_COMPLETE;
                end
            end

            ST_COMPLETE: begin
                if (scsi_status_ready)
                    state_next = ST_IDLE;
            end

            ST_ERROR: begin
                if (scsi_status_ready)
                    state_next = ST_IDLE;
            end

            default: state_next = ST_IDLE;
        endcase
    end

    //=========================================================================
    // Control Logic
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scsi_cmd_ready <= 1'b1;
            scsi_status <= STATUS_GOOD;
            scsi_status_valid <= 1'b0;
            scsi_xfer_done <= 1'b0;
            scsi_residue <= 32'h0;

            resp_data <= 32'h0;
            resp_valid <= 1'b0;
            resp_length <= 16'h0;
            resp_word_idx <= 4'h0;
            resp_word_count <= 4'h0;

            drive_lun <= 3'h0;
            drive_read_req <= 1'b0;
            drive_write_req <= 1'b0;
            drive_lba <= 32'h0;
            drive_sector_count <= 16'h0;
            drive_motor_on <= 1'b0;
            drive_motor_off <= 1'b0;

            engine_state <= 8'h0;
            last_opcode <= 8'h0;
            sense_key <= SK_NO_SENSE;
            asc <= ASC_NO_SENSE;
            ascq <= 8'h00;

            // Initialize response buffer
            resp_buffer[0] <= 32'h0;
            resp_buffer[1] <= 32'h0;
            resp_buffer[2] <= 32'h0;
            resp_buffer[3] <= 32'h0;
            resp_buffer[4] <= 32'h0;
            resp_buffer[5] <= 32'h0;
            resp_buffer[6] <= 32'h0;
            resp_buffer[7] <= 32'h0;
            resp_buffer[8] <= 32'h0;
        end else begin
            engine_state <= {4'h0, state};

            // Default pulse signals
            drive_motor_on <= 1'b0;
            drive_motor_off <= 1'b0;
            scsi_xfer_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    scsi_cmd_ready <= 1'b1;
                    scsi_status_valid <= 1'b0;
                    resp_valid <= 1'b0;
                    drive_read_req <= 1'b0;
                    drive_write_req <= 1'b0;
                end

                ST_DECODE: begin
                    scsi_cmd_ready <= 1'b0;
                    last_opcode <= cdb_opcode;
                    drive_lun <= scsi_lun;

                    // Clear sense on new command (except REQUEST_SENSE)
                    if (cdb_opcode != OP_REQUEST_SENSE) begin
                        sense_key <= SK_NO_SENSE;
                        asc <= ASC_NO_SENSE;
                        ascq <= 8'h00;
                    end
                end

                ST_TEST_UNIT: begin
                    // Check if unit is ready
                    if (!lun_valid) begin
                        sense_key <= SK_NOT_READY;
                        asc <= ASC_MEDIUM_NOT_PRESENT;
                        scsi_status <= STATUS_CHECK_CONDITION;
                    end else begin
                        scsi_status <= STATUS_GOOD;
                    end
                end

                ST_INQUIRY: begin
                    // Build INQUIRY response (36 bytes = 9 words)
                    // Byte 0: Peripheral device type
                    // Byte 1: Removable bit
                    // Byte 2: Version (SPC-3)
                    // Byte 3: Response format
                    // Byte 4: Additional length (31)
                    resp_buffer[0] <= {8'h02, inq_rmb, inq_pdt, 8'h00};  // PDT, RMB, Version, Format
                    resp_buffer[1] <= {8'h00, 8'h00, 8'h00, 8'h1F};      // Additional length

                    // Vendor: "FLUXRIP " (8 bytes)
                    resp_buffer[2] <= 32'h58554C46;  // "FLUX"
                    resp_buffer[3] <= 32'h20504952;  // "RIP "

                    // Product: "FluxRipper      " (16 bytes)
                    resp_buffer[4] <= 32'h78756C46;  // "Flux"
                    resp_buffer[5] <= 32'h70706952;  // "Ripp"
                    resp_buffer[6] <= 32'h20207265;  // "er  "
                    resp_buffer[7] <= 32'h20202020;  // "    "

                    // Revision: "1.00" (4 bytes)
                    resp_buffer[8] <= 32'h30302E31;  // "1.00"

                    resp_word_count <= 4'd9;
                    resp_word_idx <= 4'd0;
                    resp_length <= 16'd36;
                    scsi_status <= STATUS_GOOD;
                end

                ST_READ_CAP: begin
                    // Set LUN query selection
                    lun_query_sel <= scsi_lun;

                    // READ_CAPACITY_10 response (8 bytes = 2 words)
                    // Last LBA (big-endian) - uses selected LUN data
                    resp_buffer[0] <= {lun_capacity_sel[7:0],
                                       lun_capacity_sel[15:8],
                                       lun_capacity_sel[23:16],
                                       lun_capacity_sel[31:24]};
                    // Block size (big-endian, typically 512 = 0x00000200)
                    resp_buffer[1] <= {lun_block_size_sel[7:0],
                                       lun_block_size_sel[15:8],
                                       8'h00, 8'h00};

                    resp_word_count <= 4'd2;
                    resp_word_idx <= 4'd0;
                    resp_length <= 16'd8;
                    scsi_status <= STATUS_GOOD;
                end

                ST_READ_10: begin
                    lun_query_sel <= scsi_lun;
                    drive_lba <= rw10_lba;
                    drive_sector_count <= rw10_count;
                    drive_read_req <= 1'b1;

                    // Check for write-protected on write commands (not applicable here)
                    // Check LBA range
                    if (rw10_lba + rw10_count > lun_capacity_sel) begin
                        sense_key <= SK_ILLEGAL_REQUEST;
                        asc <= ASC_LBA_OUT_OF_RANGE;
                        scsi_status <= STATUS_CHECK_CONDITION;
                    end
                end

                ST_WRITE_10: begin
                    drive_lba <= rw10_lba;
                    drive_sector_count <= rw10_count;

                    // Check write protection
                    if (lun_readonly[scsi_lun]) begin
                        sense_key <= SK_DATA_PROTECT;
                        asc <= ASC_WRITE_PROTECTED;
                        scsi_status <= STATUS_CHECK_CONDITION;
                    end else begin
                        drive_write_req <= 1'b1;
                    end
                end

                ST_WAIT_DRIVE: begin
                    drive_read_req <= 1'b0;
                    drive_write_req <= 1'b0;

                    if (drive_done) begin
                        scsi_status <= STATUS_GOOD;
                        scsi_xfer_done <= 1'b1;
                        scsi_residue <= 32'h0;
                    end else if (drive_error) begin
                        sense_key <= SK_MEDIUM_ERROR;
                        asc <= ASC_NO_SENSE;
                        scsi_status <= STATUS_CHECK_CONDITION;
                    end
                end

                ST_SEND_RESP: begin
                    resp_valid <= 1'b1;
                    resp_data <= resp_buffer[resp_word_idx];

                    if (resp_valid && resp_ready) begin
                        resp_word_idx <= resp_word_idx + 1'b1;
                        if (resp_word_idx >= resp_word_count - 1) begin
                            resp_valid <= 1'b0;
                            scsi_xfer_done <= 1'b1;
                            scsi_residue <= scsi_xfer_length - resp_length;
                        end
                    end
                end

                ST_COMPLETE: begin
                    scsi_status_valid <= 1'b1;
                end

                ST_ERROR: begin
                    if (sense_key == SK_NO_SENSE) begin
                        sense_key <= SK_ILLEGAL_REQUEST;
                        asc <= ASC_INVALID_OPCODE;
                    end
                    scsi_status <= STATUS_CHECK_CONDITION;
                    scsi_status_valid <= 1'b1;
                    scsi_residue <= scsi_xfer_length;
                end
            endcase
        end
    end

endmodule
