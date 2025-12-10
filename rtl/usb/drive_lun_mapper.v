//-----------------------------------------------------------------------------
// drive_lun_mapper.v
// USB Mass Storage Class - Physical Drive to LUN Mapper
//
// Created: 2025-12-05 15:35
//
// Maps physical FluxRipper drives to USB Mass Storage LUNs.
// Handles geometry translation and drive type differentiation.
//
// LUN Mapping:
//   LUN 0: FDD Interface A, Drive 0 (removable)
//   LUN 1: FDD Interface A, Drive 1 (removable)
//   LUN 2: HDD Interface B, Drive 0 (fixed)
//   LUN 3: HDD Interface B, Drive 1 (fixed)
//
// Drive Types:
//   FDD: Removable media, 512-byte sectors, auto-detected geometry
//   HDD: Fixed media, 512-byte sectors, discovered geometry
//-----------------------------------------------------------------------------

module drive_lun_mapper #(
    parameter MAX_LUNS = 4,
    parameter MAX_FDDS = 2,
    parameter MAX_HDDS = 2
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // SCSI Engine Interface
    //=========================================================================

    input  wire [2:0]  lun_select,          // Selected LUN
    input  wire        read_req,            // Read sector request
    input  wire        write_req,           // Write sector request
    input  wire [31:0] lba,                 // Logical Block Address
    input  wire [15:0] sector_count,        // Sector count
    output reg         ready,               // Ready for command
    output reg         done,                // Command complete
    output reg         error,               // Command error

    //=========================================================================
    // FDD HAL Interface (to existing fluxripper_hal)
    //=========================================================================

    output reg  [1:0]  fdd_select,          // FDD drive select (0-1)
    output reg  [31:0] fdd_lba,             // LBA for FDD
    output reg  [15:0] fdd_count,           // Sector count for FDD
    output reg         fdd_read,            // FDD read request
    output reg         fdd_write,           // FDD write request
    input  wire        fdd_ready,           // FDD ready
    input  wire        fdd_done,            // FDD operation complete
    input  wire        fdd_error,           // FDD error

    //=========================================================================
    // HDD HAL Interface (to hdd_hal)
    //=========================================================================

    output reg  [1:0]  hdd_select,          // HDD drive select (0-1)
    output reg  [31:0] hdd_lba,             // LBA for HDD
    output reg  [15:0] hdd_count,           // Sector count for HDD
    output reg         hdd_read,            // HDD read request
    output reg         hdd_write,           // HDD write request
    input  wire        hdd_ready,           // HDD ready
    input  wire        hdd_done,            // HDD operation complete
    input  wire        hdd_error,           // HDD error

    //=========================================================================
    // Drive Presence and Status
    //=========================================================================

    // FDD status (directly from HAL)
    input  wire [MAX_FDDS-1:0] fdd_present,     // Disk inserted
    input  wire [MAX_FDDS-1:0] fdd_write_prot,  // Write protected

    // FDD geometry (selection-based for Verilog compatibility)
    input  wire [1:0]  fdd_query_sel,           // Which FDD to query
    input  wire [15:0] fdd_capacity_sel,        // Capacity of selected FDD
    input  wire [15:0] fdd_block_size_sel,      // Block size of selected FDD

    // HDD status (from hdd_hal)
    input  wire [MAX_HDDS-1:0] hdd_present,     // Drive ready
    input  wire [MAX_HDDS-1:0] hdd_write_prot,  // Write protected (rare)

    // HDD geometry (selection-based for Verilog compatibility)
    input  wire [1:0]  hdd_query_sel,           // Which HDD to query
    input  wire [31:0] hdd_capacity_sel,        // Capacity of selected HDD
    input  wire [15:0] hdd_block_size_sel,      // Block size of selected HDD

    //=========================================================================
    // LUN Configuration Outputs (to SCSI engine)
    //=========================================================================

    output wire [MAX_LUNS-1:0] lun_present,     // LUN has media
    output wire [MAX_LUNS-1:0] lun_removable,   // LUN is removable
    output wire [MAX_LUNS-1:0] lun_readonly,    // LUN is write-protected
    input  wire [2:0]  lun_query_sel,           // Which LUN to query
    output reg  [31:0] lun_capacity_sel,        // Capacity of selected LUN
    output reg  [15:0] lun_block_size_sel,      // Block size of selected LUN

    //=========================================================================
    // Status
    //=========================================================================

    output reg  [7:0]  mapper_state,
    output reg  [2:0]  active_lun,
    output reg         is_fdd_op,               // Current op is FDD
    output reg         is_hdd_op                // Current op is HDD
);

    //=========================================================================
    // LUN to Drive Type Mapping
    //=========================================================================

    // LUN 0-1 = FDD (removable)
    // LUN 2-3 = HDD (fixed)
    wire lun_is_fdd = (lun_select < 2);
    wire lun_is_hdd = (lun_select >= 2);

    // Physical drive index within type
    wire [1:0] fdd_index = lun_select[0];      // 0 or 1
    wire [1:0] hdd_index = lun_select[0];      // 0 or 1 (after offset)

    //=========================================================================
    // LUN Configuration
    //=========================================================================

    // Presence
    assign lun_present[0] = fdd_present[0];
    assign lun_present[1] = (MAX_FDDS > 1) ? fdd_present[1] : 1'b0;
    assign lun_present[2] = hdd_present[0];
    assign lun_present[3] = (MAX_HDDS > 1) ? hdd_present[1] : 1'b0;

    // Removable (FDD = yes, HDD = no)
    assign lun_removable[0] = 1'b1;
    assign lun_removable[1] = 1'b1;
    assign lun_removable[2] = 1'b0;
    assign lun_removable[3] = 1'b0;

    // Write protection
    assign lun_readonly[0] = fdd_write_prot[0];
    assign lun_readonly[1] = (MAX_FDDS > 1) ? fdd_write_prot[1] : 1'b0;
    assign lun_readonly[2] = hdd_write_prot[0];
    assign lun_readonly[3] = (MAX_HDDS > 1) ? hdd_write_prot[1] : 1'b0;

    // Capacity and block size (selection-based mux)
    // LUN mapping: 0,1 = FDD0,1; 2,3 = HDD0,1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lun_capacity_sel <= 32'd2880;   // Default 1.44MB
            lun_block_size_sel <= 16'd512;
        end else begin
            case (lun_query_sel)
                3'd0: begin // FDD 0
                    lun_capacity_sel <= {16'h0, fdd_capacity_sel};
                    lun_block_size_sel <= fdd_block_size_sel;
                end
                3'd1: begin // FDD 1
                    lun_capacity_sel <= {16'h0, fdd_capacity_sel};
                    lun_block_size_sel <= fdd_block_size_sel;
                end
                3'd2: begin // HDD 0
                    lun_capacity_sel <= hdd_capacity_sel;
                    lun_block_size_sel <= hdd_block_size_sel;
                end
                3'd3: begin // HDD 1
                    lun_capacity_sel <= hdd_capacity_sel;
                    lun_block_size_sel <= hdd_block_size_sel;
                end
                default: begin
                    lun_capacity_sel <= 32'd0;
                    lun_block_size_sel <= 16'd512;
                end
            endcase
        end
    end

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_IDLE       = 3'd0;
    localparam ST_ROUTE      = 3'd1;
    localparam ST_FDD_WAIT   = 3'd2;
    localparam ST_HDD_WAIT   = 3'd3;
    localparam ST_COMPLETE   = 3'd4;
    localparam ST_ERROR      = 3'd5;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            ready <= 1'b1;
            done <= 1'b0;
            error <= 1'b0;

            fdd_select <= 2'b00;
            fdd_lba <= 32'h0;
            fdd_count <= 16'h0;
            fdd_read <= 1'b0;
            fdd_write <= 1'b0;

            hdd_select <= 2'b00;
            hdd_lba <= 32'h0;
            hdd_count <= 16'h0;
            hdd_read <= 1'b0;
            hdd_write <= 1'b0;

            mapper_state <= 8'h0;
            active_lun <= 3'h0;
            is_fdd_op <= 1'b0;
            is_hdd_op <= 1'b0;
        end else begin
            mapper_state <= {5'h0, state};
            done <= 1'b0;
            error <= 1'b0;

            case (state)
                ST_IDLE: begin
                    ready <= 1'b1;
                    fdd_read <= 1'b0;
                    fdd_write <= 1'b0;
                    hdd_read <= 1'b0;
                    hdd_write <= 1'b0;

                    if (read_req || write_req) begin
                        ready <= 1'b0;
                        active_lun <= lun_select;
                        state <= ST_ROUTE;
                    end
                end

                ST_ROUTE: begin
                    if (lun_is_fdd) begin
                        // Route to FDD
                        is_fdd_op <= 1'b1;
                        is_hdd_op <= 1'b0;
                        fdd_select <= fdd_index;
                        fdd_lba <= lba;
                        fdd_count <= sector_count;
                        fdd_read <= read_req;
                        fdd_write <= write_req;
                        state <= ST_FDD_WAIT;
                    end else begin
                        // Route to HDD
                        is_fdd_op <= 1'b0;
                        is_hdd_op <= 1'b1;
                        hdd_select <= hdd_index;
                        hdd_lba <= lba;
                        hdd_count <= sector_count;
                        hdd_read <= read_req;
                        hdd_write <= write_req;
                        state <= ST_HDD_WAIT;
                    end
                end

                ST_FDD_WAIT: begin
                    fdd_read <= 1'b0;
                    fdd_write <= 1'b0;

                    if (fdd_done) begin
                        state <= ST_COMPLETE;
                    end else if (fdd_error) begin
                        state <= ST_ERROR;
                    end
                end

                ST_HDD_WAIT: begin
                    hdd_read <= 1'b0;
                    hdd_write <= 1'b0;

                    if (hdd_done) begin
                        state <= ST_COMPLETE;
                    end else if (hdd_error) begin
                        state <= ST_ERROR;
                    end
                end

                ST_COMPLETE: begin
                    done <= 1'b1;
                    is_fdd_op <= 1'b0;
                    is_hdd_op <= 1'b0;
                    state <= ST_IDLE;
                end

                ST_ERROR: begin
                    error <= 1'b1;
                    is_fdd_op <= 1'b0;
                    is_hdd_op <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
