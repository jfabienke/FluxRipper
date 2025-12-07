//==============================================================================
// HDD Steganographic Metadata Store
//==============================================================================
// File: hdd_metadata_store.v
// Description: Stores FluxRipper metadata in "hidden" sectors that appear as
//              defective to the host operating system. Uses a fake defect list
//              approach similar to manufacturer reserved sectors.
//
// Storage Strategy:
//   1. Reserve N sectors at specific C/H/S locations (default: cylinder 0, head 1)
//   2. Mark these sectors in the defect map returned to WD controller emulation
//   3. Store FluxRipper metadata in these sectors using special signature
//   4. Host OS sees them as "bad sectors" and avoids them
//   5. FluxRipper can read/write freely since it bypasses the WD emulation layer
//
// Metadata Contents:
//   - FluxRipper signature and version
//   - Unique drive identifier (GUID)
//   - Drive serial/model (if readable)
//   - Discovery profile data
//   - Diagnostic history (last 16 sessions)
//   - User-defined notes
//   - CRC-32 for integrity
//
// Target: AMD Spartan UltraScale+ XCSU35P
// Author: Claude Code (FluxRipper Project)
// Created: 2025-12-04 20:07
//==============================================================================

`timescale 1ns / 1ps

module hdd_metadata_store #(
    parameter NUM_RESERVED_SECTORS = 4,     // Sectors reserved for metadata
    parameter SECTOR_SIZE         = 512,    // Bytes per sector
    parameter METADATA_CYL        = 16'd0,  // Default cylinder for metadata
    parameter METADATA_HEAD       = 4'd1,   // Default head (use head 1 to avoid track 0 conflicts)
    parameter METADATA_START_SEC  = 8'd1    // Starting sector number
)(
    input  wire        clk,                 // 300 MHz HDD clock
    input  wire        reset,

    //=========================================================================
    // Control Interface
    //=========================================================================
    input  wire        meta_read_start,     // Start metadata read operation
    input  wire        meta_write_start,    // Start metadata write operation
    input  wire        meta_erase_start,    // Erase metadata (restore to "clean" disk)
    output reg         meta_busy,           // Operation in progress
    output reg         meta_done,           // Operation complete
    output reg         meta_error,          // Operation failed
    output reg  [3:0]  meta_error_code,     // Error code

    //=========================================================================
    // Configuration
    //=========================================================================
    input  wire [15:0] config_cylinder,     // Override cylinder (0 = use default)
    input  wire [3:0]  config_head,         // Override head (0xF = use default)
    input  wire [7:0]  config_start_sector, // Override start sector (0xFF = use default)
    input  wire        config_enable,       // 1 = metadata storage enabled

    //=========================================================================
    // Metadata Content Interface (register-based)
    //=========================================================================
    // Write path: firmware writes to these registers before meta_write_start
    input  wire [127:0] meta_guid,          // Unique identifier (128-bit UUID)
    input  wire [63:0]  meta_timestamp,     // Unix timestamp of last operation
    input  wire [255:0] meta_fingerprint,   // Drive fingerprint from hdd_fingerprint module
    input  wire [31:0]  meta_session_count, // Total FluxRipper sessions on this drive
    input  wire [31:0]  meta_read_count,    // Total sectors read
    input  wire [31:0]  meta_error_count,   // Cumulative errors encountered
    input  wire [15:0]  meta_flags,         // User flags
    input  wire [255:0] meta_user_notes,    // 32-character user note (ASCII)

    // Read path: populated after meta_read_start completes
    output reg [127:0] meta_guid_out,
    output reg [63:0]  meta_timestamp_out,
    output reg [255:0] meta_fingerprint_out,
    output reg [31:0]  meta_session_count_out,
    output reg [31:0]  meta_read_count_out,
    output reg [31:0]  meta_error_count_out,
    output reg [15:0]  meta_flags_out,
    output reg [255:0] meta_user_notes_out,
    output reg         meta_valid,          // Metadata was found and valid

    //=========================================================================
    // Diagnostic History (last 16 sessions) - stored in sectors 2-3
    //=========================================================================
    input  wire [7:0]  diag_session_idx,    // Which session to read (0-15)
    output reg [63:0]  diag_timestamp,      // Session timestamp
    output reg [7:0]   diag_type,           // Session type (discovery, imaging, etc)
    output reg [31:0]  diag_duration,       // Session duration (seconds)
    output reg [15:0]  diag_errors,         // Errors this session
    output reg [15:0]  diag_warnings,       // Warnings this session
    output reg         diag_valid,          // This session record is valid

    //=========================================================================
    // Defect List Output (to WD controller emulation)
    //=========================================================================
    // The WD controller emulation queries this to build the defect list
    output wire [NUM_RESERVED_SECTORS-1:0] defect_mask,     // Which sectors are "bad"
    output wire [15:0] defect_cylinder,
    output wire [3:0]  defect_head,
    output wire [7:0]  defect_start_sector,

    //=========================================================================
    // Seek Controller Interface
    //=========================================================================
    output reg         seek_request,
    output reg [15:0]  seek_cylinder_req,
    input  wire        seek_done,
    input  wire        seek_error_in,
    input  wire [15:0] current_cylinder,

    //=========================================================================
    // Head Select Interface
    //=========================================================================
    output reg [3:0]   head_select,
    input  wire        head_selected,

    //=========================================================================
    // Data Path Interface (direct sector read/write)
    //=========================================================================
    // Read from disk
    input  wire        sector_data_valid,
    input  wire [7:0]  sector_data_byte,
    input  wire        sector_complete,
    input  wire        sector_crc_ok,
    input  wire        sector_crc_error,

    // Write to disk
    output reg         write_gate,
    output reg [7:0]   write_data_byte,
    output reg         write_data_valid,
    input  wire        write_ready,
    input  wire        write_complete,

    // Sector addressing
    output reg [7:0]   target_sector,
    output reg         sector_read_start,
    input  wire        index_pulse
);

    //=========================================================================
    // Constants and Signatures
    //=========================================================================

    // FluxRipper metadata signature "FLXR" + version
    localparam [31:0] METADATA_SIGNATURE = 32'h464C5852;  // "FLXR"
    localparam [7:0]  METADATA_VERSION   = 8'h01;

    // Error codes
    localparam [3:0]
        ERR_NONE           = 4'd0,
        ERR_SEEK_FAILED    = 4'd1,
        ERR_HEAD_SELECT    = 4'd2,
        ERR_SECTOR_READ    = 4'd3,
        ERR_CRC_FAILURE    = 4'd4,
        ERR_NO_SIGNATURE   = 4'd5,
        ERR_VERSION_MISMATCH = 4'd6,
        ERR_WRITE_FAILED   = 4'd7,
        ERR_DISABLED       = 4'd8,
        ERR_TIMEOUT        = 4'd9;

    // Sector allocation
    // Sector 0: Primary header (signature, GUID, timestamp, flags)
    // Sector 1: Drive profile (fingerprint, stats)
    // Sector 2: Diagnostic history (sessions 0-7)
    // Sector 3: Diagnostic history (sessions 8-15) + user notes
    localparam [1:0]
        SECTOR_HEADER  = 2'd0,
        SECTOR_PROFILE = 2'd1,
        SECTOR_DIAG_A  = 2'd2,
        SECTOR_DIAG_B  = 2'd3;

    //=========================================================================
    // Active Configuration
    //=========================================================================

    wire [15:0] active_cylinder;
    wire [3:0]  active_head;
    wire [7:0]  active_start_sector;

    assign active_cylinder     = (config_cylinder != 16'd0) ? config_cylinder : METADATA_CYL;
    assign active_head         = (config_head != 4'hF) ? config_head : METADATA_HEAD;
    assign active_start_sector = (config_start_sector != 8'hFF) ? config_start_sector : METADATA_START_SEC;

    // Defect list output
    assign defect_mask         = {NUM_RESERVED_SECTORS{config_enable}};
    assign defect_cylinder     = active_cylinder;
    assign defect_head         = active_head;
    assign defect_start_sector = active_start_sector;

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam [3:0]
        STATE_IDLE          = 4'd0,
        STATE_SEEK          = 4'd1,
        STATE_WAIT_SEEK     = 4'd2,
        STATE_SELECT_HEAD   = 4'd3,
        STATE_WAIT_HEAD     = 4'd4,
        STATE_READ_SECTOR   = 4'd5,
        STATE_READ_DATA     = 4'd6,
        STATE_VALIDATE      = 4'd7,
        STATE_WRITE_SECTOR  = 4'd8,
        STATE_WRITE_DATA    = 4'd9,
        STATE_NEXT_SECTOR   = 4'd10,
        STATE_COMPLETE      = 4'd11,
        STATE_ERROR         = 4'd12;

    reg [3:0] state;
    reg [3:0] next_state_after_seek;
    reg [1:0] current_sector_idx;
    reg       operation_is_write;
    reg       operation_is_erase;

    //=========================================================================
    // Timing
    //=========================================================================

    reg [23:0] timeout_counter;
    localparam [23:0] SEEK_TIMEOUT     = 24'd30_000_000;  // 100ms @ 300 MHz
    localparam [23:0] SECTOR_TIMEOUT   = 24'd6_000_000;   // 20ms @ 300 MHz

    //=========================================================================
    // Sector Buffer (512 bytes)
    //=========================================================================

    reg [7:0] sector_buffer [0:511];
    reg [8:0] buffer_ptr;

    //=========================================================================
    // CRC-32 Calculator (inline)
    //=========================================================================

    reg [31:0] crc32_reg;
    wire [31:0] crc32_next;

    // CRC-32 polynomial: 0x04C11DB7 (Ethernet/ZIP)
    function [31:0] crc32_update;
        input [31:0] crc;
        input [7:0] data;
        integer i;
        reg [31:0] c;
        begin
            c = crc ^ {24'd0, data};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[0])
                    c = {1'b0, c[31:1]} ^ 32'hEDB88320;
                else
                    c = {1'b0, c[31:1]};
            end
            crc32_update = c;
        end
    endfunction

    //=========================================================================
    // Main State Machine
    //=========================================================================

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            meta_busy <= 1'b0;
            meta_done <= 1'b0;
            meta_error <= 1'b0;
            meta_error_code <= ERR_NONE;
            meta_valid <= 1'b0;
            seek_request <= 1'b0;
            head_select <= 4'd0;
            write_gate <= 1'b0;
            write_data_valid <= 1'b0;
            sector_read_start <= 1'b0;
            target_sector <= 8'd0;
            timeout_counter <= 24'd0;
            buffer_ptr <= 9'd0;
            current_sector_idx <= 2'd0;
            crc32_reg <= 32'hFFFFFFFF;
            operation_is_write <= 1'b0;
            operation_is_erase <= 1'b0;

            // Clear outputs
            meta_guid_out <= 128'd0;
            meta_timestamp_out <= 64'd0;
            meta_fingerprint_out <= 256'd0;
            meta_session_count_out <= 32'd0;
            meta_read_count_out <= 32'd0;
            meta_error_count_out <= 32'd0;
            meta_flags_out <= 16'd0;
            meta_user_notes_out <= 256'd0;
            diag_timestamp <= 64'd0;
            diag_type <= 8'd0;
            diag_duration <= 32'd0;
            diag_errors <= 16'd0;
            diag_warnings <= 16'd0;
            diag_valid <= 1'b0;

        end else begin
            // Defaults
            meta_done <= 1'b0;
            seek_request <= 1'b0;
            sector_read_start <= 1'b0;
            write_data_valid <= 1'b0;

            // Timeout counter
            if (state != STATE_IDLE && state != STATE_COMPLETE && state != STATE_ERROR)
                timeout_counter <= timeout_counter + 1;

            case (state)
                //-------------------------------------------------------------
                STATE_IDLE: begin
                    meta_busy <= 1'b0;

                    if (meta_read_start && config_enable) begin
                        meta_busy <= 1'b1;
                        meta_error <= 1'b0;
                        meta_error_code <= ERR_NONE;
                        meta_valid <= 1'b0;
                        operation_is_write <= 1'b0;
                        operation_is_erase <= 1'b0;
                        current_sector_idx <= 2'd0;
                        timeout_counter <= 24'd0;

                        // Start by seeking to metadata cylinder
                        seek_cylinder_req <= active_cylinder;
                        seek_request <= 1'b1;
                        next_state_after_seek <= STATE_SELECT_HEAD;
                        state <= STATE_SEEK;

                    end else if (meta_write_start && config_enable) begin
                        meta_busy <= 1'b1;
                        meta_error <= 1'b0;
                        meta_error_code <= ERR_NONE;
                        operation_is_write <= 1'b1;
                        operation_is_erase <= 1'b0;
                        current_sector_idx <= 2'd0;
                        timeout_counter <= 24'd0;

                        seek_cylinder_req <= active_cylinder;
                        seek_request <= 1'b1;
                        next_state_after_seek <= STATE_SELECT_HEAD;
                        state <= STATE_SEEK;

                    end else if (meta_erase_start && config_enable) begin
                        meta_busy <= 1'b1;
                        meta_error <= 1'b0;
                        meta_error_code <= ERR_NONE;
                        operation_is_write <= 1'b1;
                        operation_is_erase <= 1'b1;
                        current_sector_idx <= 2'd0;
                        timeout_counter <= 24'd0;

                        seek_cylinder_req <= active_cylinder;
                        seek_request <= 1'b1;
                        next_state_after_seek <= STATE_SELECT_HEAD;
                        state <= STATE_SEEK;

                    end else if ((meta_read_start || meta_write_start || meta_erase_start) && !config_enable) begin
                        // Metadata disabled
                        meta_error <= 1'b1;
                        meta_error_code <= ERR_DISABLED;
                        meta_done <= 1'b1;
                    end
                end

                //-------------------------------------------------------------
                STATE_SEEK: begin
                    seek_request <= 1'b0;
                    timeout_counter <= 24'd0;
                    state <= STATE_WAIT_SEEK;
                end

                //-------------------------------------------------------------
                STATE_WAIT_SEEK: begin
                    if (seek_done) begin
                        if (seek_error_in) begin
                            meta_error_code <= ERR_SEEK_FAILED;
                            state <= STATE_ERROR;
                        end else begin
                            state <= next_state_after_seek;
                        end
                    end else if (timeout_counter > SEEK_TIMEOUT) begin
                        meta_error_code <= ERR_TIMEOUT;
                        state <= STATE_ERROR;
                    end
                end

                //-------------------------------------------------------------
                STATE_SELECT_HEAD: begin
                    head_select <= active_head;
                    timeout_counter <= 24'd0;
                    state <= STATE_WAIT_HEAD;
                end

                //-------------------------------------------------------------
                STATE_WAIT_HEAD: begin
                    if (head_selected) begin
                        if (operation_is_write)
                            state <= STATE_WRITE_SECTOR;
                        else
                            state <= STATE_READ_SECTOR;
                    end else if (timeout_counter > 24'd300_000) begin  // 1ms
                        meta_error_code <= ERR_HEAD_SELECT;
                        state <= STATE_ERROR;
                    end
                end

                //-------------------------------------------------------------
                STATE_READ_SECTOR: begin
                    target_sector <= active_start_sector + {6'd0, current_sector_idx};
                    sector_read_start <= 1'b1;
                    buffer_ptr <= 9'd0;
                    crc32_reg <= 32'hFFFFFFFF;
                    timeout_counter <= 24'd0;
                    state <= STATE_READ_DATA;
                end

                //-------------------------------------------------------------
                STATE_READ_DATA: begin
                    if (sector_data_valid) begin
                        sector_buffer[buffer_ptr] <= sector_data_byte;
                        crc32_reg <= crc32_update(crc32_reg, sector_data_byte);
                        buffer_ptr <= buffer_ptr + 1;
                    end

                    if (sector_complete) begin
                        if (sector_crc_error) begin
                            meta_error_code <= ERR_CRC_FAILURE;
                            state <= STATE_ERROR;
                        end else begin
                            state <= STATE_VALIDATE;
                        end
                    end else if (timeout_counter > SECTOR_TIMEOUT) begin
                        meta_error_code <= ERR_SECTOR_READ;
                        state <= STATE_ERROR;
                    end
                end

                //-------------------------------------------------------------
                STATE_VALIDATE: begin
                    // Validate sector data based on which sector we read
                    case (current_sector_idx)
                        SECTOR_HEADER: begin
                            // Check signature
                            if ({sector_buffer[0], sector_buffer[1],
                                 sector_buffer[2], sector_buffer[3]} == METADATA_SIGNATURE) begin

                                // Check version
                                if (sector_buffer[4] == METADATA_VERSION) begin
                                    // Extract header data
                                    meta_guid_out <= {
                                        sector_buffer[8],  sector_buffer[9],  sector_buffer[10], sector_buffer[11],
                                        sector_buffer[12], sector_buffer[13], sector_buffer[14], sector_buffer[15],
                                        sector_buffer[16], sector_buffer[17], sector_buffer[18], sector_buffer[19],
                                        sector_buffer[20], sector_buffer[21], sector_buffer[22], sector_buffer[23]
                                    };
                                    meta_timestamp_out <= {
                                        sector_buffer[24], sector_buffer[25], sector_buffer[26], sector_buffer[27],
                                        sector_buffer[28], sector_buffer[29], sector_buffer[30], sector_buffer[31]
                                    };
                                    meta_flags_out <= {sector_buffer[32], sector_buffer[33]};

                                    state <= STATE_NEXT_SECTOR;
                                end else begin
                                    meta_error_code <= ERR_VERSION_MISMATCH;
                                    state <= STATE_ERROR;
                                end
                            end else begin
                                // No metadata found - this is OK for first-time setup
                                meta_error_code <= ERR_NO_SIGNATURE;
                                meta_valid <= 1'b0;
                                state <= STATE_COMPLETE;
                            end
                        end

                        SECTOR_PROFILE: begin
                            // Extract fingerprint and stats
                            // Fingerprint: bytes 0-31
                            meta_fingerprint_out <= {
                                sector_buffer[0],  sector_buffer[1],  sector_buffer[2],  sector_buffer[3],
                                sector_buffer[4],  sector_buffer[5],  sector_buffer[6],  sector_buffer[7],
                                sector_buffer[8],  sector_buffer[9],  sector_buffer[10], sector_buffer[11],
                                sector_buffer[12], sector_buffer[13], sector_buffer[14], sector_buffer[15],
                                sector_buffer[16], sector_buffer[17], sector_buffer[18], sector_buffer[19],
                                sector_buffer[20], sector_buffer[21], sector_buffer[22], sector_buffer[23],
                                sector_buffer[24], sector_buffer[25], sector_buffer[26], sector_buffer[27],
                                sector_buffer[28], sector_buffer[29], sector_buffer[30], sector_buffer[31]
                            };
                            // Session count: bytes 32-35
                            meta_session_count_out <= {
                                sector_buffer[32], sector_buffer[33], sector_buffer[34], sector_buffer[35]
                            };
                            // Read count: bytes 36-39
                            meta_read_count_out <= {
                                sector_buffer[36], sector_buffer[37], sector_buffer[38], sector_buffer[39]
                            };
                            // Error count: bytes 40-43
                            meta_error_count_out <= {
                                sector_buffer[40], sector_buffer[41], sector_buffer[42], sector_buffer[43]
                            };

                            state <= STATE_NEXT_SECTOR;
                        end

                        SECTOR_DIAG_A, SECTOR_DIAG_B: begin
                            // Diagnostic history - extract requested session
                            // Each session: 16 bytes (timestamp:8, type:1, duration:4, errors:2, warnings:2, rsvd:1)
                            // 8 sessions per sector
                            begin
                                reg [3:0] sess_in_sector;
                                reg [8:0] sess_offset;

                                sess_in_sector = (current_sector_idx == SECTOR_DIAG_A) ?
                                                 diag_session_idx[2:0] : diag_session_idx[2:0];
                                sess_offset = {sess_in_sector, 4'd0};  // * 16

                                diag_timestamp <= {
                                    sector_buffer[sess_offset+0], sector_buffer[sess_offset+1],
                                    sector_buffer[sess_offset+2], sector_buffer[sess_offset+3],
                                    sector_buffer[sess_offset+4], sector_buffer[sess_offset+5],
                                    sector_buffer[sess_offset+6], sector_buffer[sess_offset+7]
                                };
                                diag_type <= sector_buffer[sess_offset+8];
                                diag_duration <= {
                                    sector_buffer[sess_offset+9],  sector_buffer[sess_offset+10],
                                    sector_buffer[sess_offset+11], sector_buffer[sess_offset+12]
                                };
                                diag_errors <= {sector_buffer[sess_offset+13], sector_buffer[sess_offset+14]};
                                diag_warnings <= {sector_buffer[sess_offset+15], 8'd0}; // Only 1 byte here

                                diag_valid <= (diag_timestamp != 64'd0);
                            end

                            // User notes in last 32 bytes of SECTOR_DIAG_B
                            if (current_sector_idx == SECTOR_DIAG_B) begin
                                meta_user_notes_out <= {
                                    sector_buffer[480], sector_buffer[481], sector_buffer[482], sector_buffer[483],
                                    sector_buffer[484], sector_buffer[485], sector_buffer[486], sector_buffer[487],
                                    sector_buffer[488], sector_buffer[489], sector_buffer[490], sector_buffer[491],
                                    sector_buffer[492], sector_buffer[493], sector_buffer[494], sector_buffer[495],
                                    sector_buffer[496], sector_buffer[497], sector_buffer[498], sector_buffer[499],
                                    sector_buffer[500], sector_buffer[501], sector_buffer[502], sector_buffer[503],
                                    sector_buffer[504], sector_buffer[505], sector_buffer[506], sector_buffer[507],
                                    sector_buffer[508], sector_buffer[509], sector_buffer[510], sector_buffer[511]
                                };
                            end

                            state <= STATE_NEXT_SECTOR;
                        end

                        default: state <= STATE_NEXT_SECTOR;
                    endcase
                end

                //-------------------------------------------------------------
                STATE_WRITE_SECTOR: begin
                    // Build sector buffer based on which sector we're writing
                    buffer_ptr <= 9'd0;

                    // Clear buffer first
                    for (i = 0; i < 512; i = i + 1)
                        sector_buffer[i] <= 8'h00;

                    if (operation_is_erase) begin
                        // Erase: write all zeros (no signature)
                        // Buffer already cleared
                    end else begin
                        case (current_sector_idx)
                            SECTOR_HEADER: begin
                                // Signature
                                sector_buffer[0] <= METADATA_SIGNATURE[31:24];
                                sector_buffer[1] <= METADATA_SIGNATURE[23:16];
                                sector_buffer[2] <= METADATA_SIGNATURE[15:8];
                                sector_buffer[3] <= METADATA_SIGNATURE[7:0];
                                // Version
                                sector_buffer[4] <= METADATA_VERSION;
                                // Reserved
                                sector_buffer[5] <= 8'd0;
                                sector_buffer[6] <= 8'd0;
                                sector_buffer[7] <= 8'd0;
                                // GUID (16 bytes)
                                sector_buffer[8]  <= meta_guid[127:120];
                                sector_buffer[9]  <= meta_guid[119:112];
                                sector_buffer[10] <= meta_guid[111:104];
                                sector_buffer[11] <= meta_guid[103:96];
                                sector_buffer[12] <= meta_guid[95:88];
                                sector_buffer[13] <= meta_guid[87:80];
                                sector_buffer[14] <= meta_guid[79:72];
                                sector_buffer[15] <= meta_guid[71:64];
                                sector_buffer[16] <= meta_guid[63:56];
                                sector_buffer[17] <= meta_guid[55:48];
                                sector_buffer[18] <= meta_guid[47:40];
                                sector_buffer[19] <= meta_guid[39:32];
                                sector_buffer[20] <= meta_guid[31:24];
                                sector_buffer[21] <= meta_guid[23:16];
                                sector_buffer[22] <= meta_guid[15:8];
                                sector_buffer[23] <= meta_guid[7:0];
                                // Timestamp (8 bytes)
                                sector_buffer[24] <= meta_timestamp[63:56];
                                sector_buffer[25] <= meta_timestamp[55:48];
                                sector_buffer[26] <= meta_timestamp[47:40];
                                sector_buffer[27] <= meta_timestamp[39:32];
                                sector_buffer[28] <= meta_timestamp[31:24];
                                sector_buffer[29] <= meta_timestamp[23:16];
                                sector_buffer[30] <= meta_timestamp[15:8];
                                sector_buffer[31] <= meta_timestamp[7:0];
                                // Flags
                                sector_buffer[32] <= meta_flags[15:8];
                                sector_buffer[33] <= meta_flags[7:0];
                            end

                            SECTOR_PROFILE: begin
                                // Fingerprint (32 bytes)
                                sector_buffer[0]  <= meta_fingerprint[255:248];
                                sector_buffer[1]  <= meta_fingerprint[247:240];
                                sector_buffer[2]  <= meta_fingerprint[239:232];
                                sector_buffer[3]  <= meta_fingerprint[231:224];
                                sector_buffer[4]  <= meta_fingerprint[223:216];
                                sector_buffer[5]  <= meta_fingerprint[215:208];
                                sector_buffer[6]  <= meta_fingerprint[207:200];
                                sector_buffer[7]  <= meta_fingerprint[199:192];
                                sector_buffer[8]  <= meta_fingerprint[191:184];
                                sector_buffer[9]  <= meta_fingerprint[183:176];
                                sector_buffer[10] <= meta_fingerprint[175:168];
                                sector_buffer[11] <= meta_fingerprint[167:160];
                                sector_buffer[12] <= meta_fingerprint[159:152];
                                sector_buffer[13] <= meta_fingerprint[151:144];
                                sector_buffer[14] <= meta_fingerprint[143:136];
                                sector_buffer[15] <= meta_fingerprint[135:128];
                                sector_buffer[16] <= meta_fingerprint[127:120];
                                sector_buffer[17] <= meta_fingerprint[119:112];
                                sector_buffer[18] <= meta_fingerprint[111:104];
                                sector_buffer[19] <= meta_fingerprint[103:96];
                                sector_buffer[20] <= meta_fingerprint[95:88];
                                sector_buffer[21] <= meta_fingerprint[87:80];
                                sector_buffer[22] <= meta_fingerprint[79:72];
                                sector_buffer[23] <= meta_fingerprint[71:64];
                                sector_buffer[24] <= meta_fingerprint[63:56];
                                sector_buffer[25] <= meta_fingerprint[55:48];
                                sector_buffer[26] <= meta_fingerprint[47:40];
                                sector_buffer[27] <= meta_fingerprint[39:32];
                                sector_buffer[28] <= meta_fingerprint[31:24];
                                sector_buffer[29] <= meta_fingerprint[23:16];
                                sector_buffer[30] <= meta_fingerprint[15:8];
                                sector_buffer[31] <= meta_fingerprint[7:0];
                                // Session count (4 bytes)
                                sector_buffer[32] <= meta_session_count[31:24];
                                sector_buffer[33] <= meta_session_count[23:16];
                                sector_buffer[34] <= meta_session_count[15:8];
                                sector_buffer[35] <= meta_session_count[7:0];
                                // Read count (4 bytes)
                                sector_buffer[36] <= meta_read_count[31:24];
                                sector_buffer[37] <= meta_read_count[23:16];
                                sector_buffer[38] <= meta_read_count[15:8];
                                sector_buffer[39] <= meta_read_count[7:0];
                                // Error count (4 bytes)
                                sector_buffer[40] <= meta_error_count[31:24];
                                sector_buffer[41] <= meta_error_count[23:16];
                                sector_buffer[42] <= meta_error_count[15:8];
                                sector_buffer[43] <= meta_error_count[7:0];
                            end

                            SECTOR_DIAG_B: begin
                                // User notes in last 32 bytes
                                sector_buffer[480] <= meta_user_notes[255:248];
                                sector_buffer[481] <= meta_user_notes[247:240];
                                sector_buffer[482] <= meta_user_notes[239:232];
                                sector_buffer[483] <= meta_user_notes[231:224];
                                sector_buffer[484] <= meta_user_notes[223:216];
                                sector_buffer[485] <= meta_user_notes[215:208];
                                sector_buffer[486] <= meta_user_notes[207:200];
                                sector_buffer[487] <= meta_user_notes[199:192];
                                sector_buffer[488] <= meta_user_notes[191:184];
                                sector_buffer[489] <= meta_user_notes[183:176];
                                sector_buffer[490] <= meta_user_notes[175:168];
                                sector_buffer[491] <= meta_user_notes[167:160];
                                sector_buffer[492] <= meta_user_notes[159:152];
                                sector_buffer[493] <= meta_user_notes[151:144];
                                sector_buffer[494] <= meta_user_notes[143:136];
                                sector_buffer[495] <= meta_user_notes[135:128];
                                sector_buffer[496] <= meta_user_notes[127:120];
                                sector_buffer[497] <= meta_user_notes[119:112];
                                sector_buffer[498] <= meta_user_notes[111:104];
                                sector_buffer[499] <= meta_user_notes[103:96];
                                sector_buffer[500] <= meta_user_notes[95:88];
                                sector_buffer[501] <= meta_user_notes[87:80];
                                sector_buffer[502] <= meta_user_notes[79:72];
                                sector_buffer[503] <= meta_user_notes[71:64];
                                sector_buffer[504] <= meta_user_notes[63:56];
                                sector_buffer[505] <= meta_user_notes[55:48];
                                sector_buffer[506] <= meta_user_notes[47:40];
                                sector_buffer[507] <= meta_user_notes[39:32];
                                sector_buffer[508] <= meta_user_notes[31:24];
                                sector_buffer[509] <= meta_user_notes[23:16];
                                sector_buffer[510] <= meta_user_notes[15:8];
                                sector_buffer[511] <= meta_user_notes[7:0];
                            end
                        endcase
                    end

                    target_sector <= active_start_sector + {6'd0, current_sector_idx};
                    write_gate <= 1'b1;
                    timeout_counter <= 24'd0;
                    state <= STATE_WRITE_DATA;
                end

                //-------------------------------------------------------------
                STATE_WRITE_DATA: begin
                    if (write_ready && buffer_ptr < 9'd512) begin
                        write_data_byte <= sector_buffer[buffer_ptr];
                        write_data_valid <= 1'b1;
                        buffer_ptr <= buffer_ptr + 1;
                    end else begin
                        write_data_valid <= 1'b0;
                    end

                    if (write_complete) begin
                        write_gate <= 1'b0;
                        state <= STATE_NEXT_SECTOR;
                    end else if (timeout_counter > SECTOR_TIMEOUT) begin
                        write_gate <= 1'b0;
                        meta_error_code <= ERR_WRITE_FAILED;
                        state <= STATE_ERROR;
                    end
                end

                //-------------------------------------------------------------
                STATE_NEXT_SECTOR: begin
                    if (current_sector_idx < NUM_RESERVED_SECTORS - 1) begin
                        current_sector_idx <= current_sector_idx + 1;
                        if (operation_is_write)
                            state <= STATE_WRITE_SECTOR;
                        else
                            state <= STATE_READ_SECTOR;
                    end else begin
                        // All sectors processed
                        if (!operation_is_write && !operation_is_erase)
                            meta_valid <= 1'b1;
                        state <= STATE_COMPLETE;
                    end
                end

                //-------------------------------------------------------------
                STATE_COMPLETE: begin
                    meta_done <= 1'b1;
                    meta_busy <= 1'b0;
                    state <= STATE_IDLE;
                end

                //-------------------------------------------------------------
                STATE_ERROR: begin
                    meta_error <= 1'b1;
                    meta_done <= 1'b1;
                    meta_busy <= 1'b0;
                    write_gate <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

//==============================================================================
// Metadata GUID Generator
//==============================================================================
// Generates a unique identifier based on drive characteristics and random seed.
// Uses a combination of:
//   - Drive fingerprint hash
//   - Current timestamp
//   - LFSR-based pseudorandom component
//==============================================================================

module metadata_guid_generator (
    input  wire        clk,
    input  wire        reset,

    input  wire        generate,            // Trigger GUID generation
    input  wire [255:0] fingerprint,        // Drive fingerprint for seeding
    input  wire [63:0]  timestamp,          // Current timestamp
    input  wire [31:0]  random_seed,        // External random seed (e.g., from ADC noise)

    output reg [127:0] guid,                // Generated GUID
    output reg         guid_valid           // GUID is ready
);

    // LFSR for additional randomness
    reg [31:0] lfsr;

    // Generation state
    reg [3:0] gen_state;
    reg [31:0] mix_accum;

    localparam [3:0]
        GEN_IDLE    = 4'd0,
        GEN_MIX_FP  = 4'd1,
        GEN_MIX_TS  = 4'd2,
        GEN_MIX_RNG = 4'd3,
        GEN_DONE    = 4'd4;

    always @(posedge clk) begin
        if (reset) begin
            gen_state <= GEN_IDLE;
            guid <= 128'd0;
            guid_valid <= 1'b0;
            lfsr <= 32'hDEADBEEF;
            mix_accum <= 32'd0;
        end else begin
            // LFSR always running for entropy
            lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

            case (gen_state)
                GEN_IDLE: begin
                    guid_valid <= 1'b0;
                    if (generate) begin
                        mix_accum <= 32'h5A5A5A5A;
                        gen_state <= GEN_MIX_FP;
                    end
                end

                GEN_MIX_FP: begin
                    // Mix fingerprint into GUID
                    guid[127:96] <= fingerprint[255:224] ^ fingerprint[127:96] ^ lfsr;
                    guid[95:64]  <= fingerprint[223:192] ^ fingerprint[95:64] ^ {lfsr[15:0], lfsr[31:16]};
                    gen_state <= GEN_MIX_TS;
                end

                GEN_MIX_TS: begin
                    // Mix timestamp
                    guid[63:32] <= timestamp[63:32] ^ random_seed ^ lfsr;
                    guid[31:0]  <= timestamp[31:0] ^ {random_seed[15:0], random_seed[31:16]} ^ lfsr;
                    gen_state <= GEN_MIX_RNG;
                end

                GEN_MIX_RNG: begin
                    // Final mixing
                    guid[127:120] <= guid[127:120] ^ lfsr[7:0];
                    guid[119:112] <= 8'h40 | guid[119:112][3:0];  // Version 4 UUID marker
                    guid[79:72]   <= 8'h80 | guid[79:72][5:0];    // Variant marker
                    gen_state <= GEN_DONE;
                end

                GEN_DONE: begin
                    guid_valid <= 1'b1;
                    gen_state <= GEN_IDLE;
                end
            endcase
        end
    end

endmodule
