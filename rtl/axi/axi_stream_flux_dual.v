//-----------------------------------------------------------------------------
// Dual AXI-Stream Flux Capture Interface
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Provides two independent AXI-Stream master interfaces for parallel flux
// capture from dual Shugart interfaces. Supports concurrent disk imaging.
//
// Data Format (32-bit per flux transition):
//   Bit 31:    Index flag (1 = index pulse detected since last word)
//   Bit 30:    Overflow warning (FIFO overrun occurred)
//   Bit 29:    Sector flag (1 = hard-sector pulse detected since last word)
//   Bits 28:27: Drive ID (0-3, identifies which drive)
//   Bits 26:0:  Timestamp (5ns resolution at 200MHz, ~670ms range)
//
// Hard-Sector Support:
//   For NorthStar, Vector Graphics, and S-100 hard-sectored drives, the
//   /SECTOR input captures sector hole pulses. Each flux word that spans
//   a sector hole gets bit 29 = 1 using "pulse detected since last word"
//   semantics.
//
// Target: AMD Spartan UltraScale+ (SCU35)
// Updated: 2025-12-03 21:00
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module axi_stream_flux_dual #(
    parameter FIFO_DEPTH     = 256,     // Internal FIFO depth per interface (power of 2)
    parameter FIFO_ADDR_BITS = 8,       // log2(FIFO_DEPTH)
    parameter CLK_DIV        = 56       // Clock divisor for timestamp (200MHz/56 = ~3.5MHz)
)(
    //-------------------------------------------------------------------------
    // Clock/Reset (AXI domain - 100MHz)
    //-------------------------------------------------------------------------
    input  wire        aclk,
    input  wire        aresetn,

    //-------------------------------------------------------------------------
    // Flux Engine Interface A (drives 0/1 from FDC core A)
    //-------------------------------------------------------------------------
    input  wire        flux_valid_a,      // Flux transition detected
    input  wire [31:0] flux_timestamp_a,  // Timestamp from FDC core
    input  wire        flux_index_a,      // Index pulse marker
    input  wire        flux_sector_a,     // Hard-sector pulse (NorthStar/S-100)
    input  wire        drive_sel_a,       // Active drive (0 or 1)

    //-------------------------------------------------------------------------
    // Flux Engine Interface B (drives 2/3 from FDC core B)
    //-------------------------------------------------------------------------
    input  wire        flux_valid_b,      // Flux transition detected
    input  wire [31:0] flux_timestamp_b,  // Timestamp from FDC core
    input  wire        flux_index_b,      // Index pulse marker
    input  wire        flux_sector_b,     // Hard-sector pulse (NorthStar/S-100)
    input  wire        drive_sel_b,       // Active drive (0 or 1, maps to 2/3)

    //-------------------------------------------------------------------------
    // AXI-Stream Master Interface A (to DMA channel 0)
    //-------------------------------------------------------------------------
    output wire [31:0] m_axis_a_tdata,    // Flux data + flags
    output wire        m_axis_a_tvalid,   // Data valid
    input  wire        m_axis_a_tready,   // DMA ready
    output wire        m_axis_a_tlast,    // End of track (index)
    output wire [3:0]  m_axis_a_tkeep,    // Byte enables (all 1s)

    //-------------------------------------------------------------------------
    // AXI-Stream Master Interface B (to DMA channel 1)
    //-------------------------------------------------------------------------
    output wire [31:0] m_axis_b_tdata,    // Flux data + flags
    output wire        m_axis_b_tvalid,   // Data valid
    input  wire        m_axis_b_tready,   // DMA ready
    output wire        m_axis_b_tlast,    // End of track (index)
    output wire [3:0]  m_axis_b_tkeep,    // Byte enables (all 1s)

    //-------------------------------------------------------------------------
    // Control Interface A
    //-------------------------------------------------------------------------
    input  wire        capture_enable_a,  // Start/stop capture
    input  wire        soft_reset_a,      // Soft reset (clears FIFO)
    input  wire [1:0]  capture_mode_a,    // 00=continuous, 01=one track, 10=one rev

    //-------------------------------------------------------------------------
    // Control Interface B
    //-------------------------------------------------------------------------
    input  wire        capture_enable_b,  // Start/stop capture
    input  wire        soft_reset_b,      // Soft reset (clears FIFO)
    input  wire [1:0]  capture_mode_b,    // 00=continuous, 01=one track, 10=one rev

    //-------------------------------------------------------------------------
    // Status Interface A
    //-------------------------------------------------------------------------
    output reg  [31:0] capture_count_a,   // Flux transitions captured
    output reg  [15:0] index_count_a,     // Index pulses seen
    output wire        overflow_a,        // FIFO overflow flag
    output wire        capturing_a,       // Capture in progress
    output wire        fifo_empty_a,      // FIFO empty status
    output wire [FIFO_ADDR_BITS:0] fifo_level_a,  // Current FIFO fill level

    //-------------------------------------------------------------------------
    // Status Interface B
    //-------------------------------------------------------------------------
    output reg  [31:0] capture_count_b,   // Flux transitions captured
    output reg  [15:0] index_count_b,     // Index pulses seen
    output wire        overflow_b,        // FIFO overflow flag
    output wire        capturing_b,       // Capture in progress
    output wire        fifo_empty_b,      // FIFO empty status
    output wire [FIFO_ADDR_BITS:0] fifo_level_b   // Current FIFO fill level
);

    //-------------------------------------------------------------------------
    // Capture modes
    //-------------------------------------------------------------------------
    localparam MODE_CONTINUOUS = 2'b00;
    localparam MODE_ONE_TRACK  = 2'b01;
    localparam MODE_ONE_REV    = 2'b10;

    //-------------------------------------------------------------------------
    // State machine states
    //-------------------------------------------------------------------------
    localparam S_IDLE       = 3'd0;
    localparam S_ARMED      = 3'd1;
    localparam S_CAPTURING  = 3'd2;
    localparam S_INDEX_WAIT = 3'd3;
    localparam S_DONE       = 3'd4;

    //=========================================================================
    // Interface A - Flux Capture Logic
    //=========================================================================

    // FIFO A signals
    reg  [31:0] fifo_a_mem [0:FIFO_DEPTH-1];
    reg  [FIFO_ADDR_BITS-1:0] wr_ptr_a;
    reg  [FIFO_ADDR_BITS-1:0] rd_ptr_a;
    reg  [FIFO_ADDR_BITS:0]   fifo_count_a;
    wire        fifo_full_a;
    reg         fifo_wr_en_a;
    reg  [31:0] fifo_wr_data_a;
    reg  [31:0] fifo_rd_data_a;

    // State A
    reg  [2:0]  state_a;
    reg         capture_active_a;
    reg         overflow_flag_a;
    reg         index_seen_a;
    reg         second_index_a;
    reg         last_was_index_a;
    reg         sector_pending_a;    // Sector pulse detected since last write

    // Synchronization for index (flux comes from FDC domain)
    reg  [2:0]  index_sync_a;
    wire        index_edge_a;

    // Synchronization for sector pulse (hard-sectored disks)
    reg  [2:0]  sector_sync_a;
    wire        sector_edge_a;

    // Synchronize flux inputs from FDC domain
    reg  [2:0]  flux_valid_sync_a;
    reg  [31:0] flux_timestamp_reg_a;
    wire        flux_edge_a;

    // Index edge detection
    always @(posedge aclk) begin
        if (!aresetn) begin
            index_sync_a <= 3'b000;
        end else begin
            index_sync_a <= {index_sync_a[1:0], flux_index_a};
        end
    end
    assign index_edge_a = (index_sync_a[2:1] == 2'b01);

    // Sector pulse edge detection (for hard-sectored disks)
    always @(posedge aclk) begin
        if (!aresetn) begin
            sector_sync_a <= 3'b000;
        end else begin
            sector_sync_a <= {sector_sync_a[1:0], flux_sector_a};
        end
    end
    assign sector_edge_a = (sector_sync_a[2:1] == 2'b01);

    // Flux valid edge detection and timestamp capture
    always @(posedge aclk) begin
        if (!aresetn) begin
            flux_valid_sync_a   <= 3'b000;
            flux_timestamp_reg_a <= 32'd0;
        end else begin
            flux_valid_sync_a <= {flux_valid_sync_a[1:0], flux_valid_a};
            if (flux_valid_a)
                flux_timestamp_reg_a <= flux_timestamp_a;
        end
    end
    assign flux_edge_a = (flux_valid_sync_a[2:1] == 2'b01);

    // FIFO A Write
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_a) begin
            wr_ptr_a     <= {FIFO_ADDR_BITS{1'b0}};
        end else begin
            if (fifo_wr_en_a && !fifo_full_a) begin
                fifo_a_mem[wr_ptr_a] <= fifo_wr_data_a;
                wr_ptr_a <= wr_ptr_a + 1'b1;
            end
        end
    end

    // FIFO A Read
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_a) begin
            rd_ptr_a       <= {FIFO_ADDR_BITS{1'b0}};
            fifo_rd_data_a <= 32'd0;
        end else begin
            fifo_rd_data_a <= fifo_a_mem[rd_ptr_a];
            if (m_axis_a_tvalid && m_axis_a_tready && !fifo_empty_a) begin
                rd_ptr_a <= rd_ptr_a + 1'b1;
            end
        end
    end

    // FIFO A Count
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_a) begin
            fifo_count_a <= {(FIFO_ADDR_BITS+1){1'b0}};
        end else begin
            case ({fifo_wr_en_a && !fifo_full_a, m_axis_a_tvalid && m_axis_a_tready && !fifo_empty_a})
                2'b10: fifo_count_a <= fifo_count_a + 1'b1;
                2'b01: fifo_count_a <= fifo_count_a - 1'b1;
                default: fifo_count_a <= fifo_count_a;
            endcase
        end
    end

    assign fifo_full_a  = (fifo_count_a == FIFO_DEPTH);
    assign fifo_empty_a = (fifo_count_a == 0);
    assign fifo_level_a = fifo_count_a;

    // Capture State Machine A
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_a) begin
            state_a          <= S_IDLE;
            capture_active_a <= 1'b0;
            overflow_flag_a  <= 1'b0;
            index_seen_a     <= 1'b0;
            second_index_a   <= 1'b0;
            capture_count_a  <= 32'd0;
            index_count_a    <= 16'd0;
            last_was_index_a <= 1'b0;
            sector_pending_a <= 1'b0;
            fifo_wr_en_a     <= 1'b0;
            fifo_wr_data_a   <= 32'd0;
        end else begin
            fifo_wr_en_a <= 1'b0;

            // Track sector pulses (set on edge, cleared when data written)
            if (sector_edge_a) begin
                sector_pending_a <= 1'b1;
            end

            case (state_a)
                S_IDLE: begin
                    if (capture_enable_a) begin
                        capture_count_a  <= 32'd0;
                        index_count_a    <= 16'd0;
                        overflow_flag_a  <= 1'b0;
                        index_seen_a     <= 1'b0;
                        second_index_a   <= 1'b0;
                        last_was_index_a <= 1'b0;

                        if (capture_mode_a == MODE_CONTINUOUS) begin
                            state_a          <= S_CAPTURING;
                            capture_active_a <= 1'b1;
                        end else begin
                            state_a          <= S_ARMED;
                            capture_active_a <= 1'b0;
                        end
                    end
                end

                S_ARMED: begin
                    if (!capture_enable_a) begin
                        state_a <= S_IDLE;
                    end else if (index_edge_a) begin
                        state_a          <= S_CAPTURING;
                        capture_active_a <= 1'b1;
                        index_seen_a     <= 1'b1;
                        index_count_a    <= index_count_a + 1'b1;

                        // Write index marker: [31]=INDEX, [30]=OVF, [29]=SECTOR, [28:27]=DRV_ID, [26:0]=TS
                        fifo_wr_en_a     <= 1'b1;
                        fifo_wr_data_a   <= {1'b1, overflow_flag_a, sector_pending_a, 1'b0, drive_sel_a, flux_timestamp_reg_a[26:0]};
                        last_was_index_a <= 1'b1;
                        sector_pending_a <= 1'b0;  // Clear sector flag after write
                    end
                end

                S_CAPTURING: begin
                    if (!capture_enable_a) begin
                        state_a          <= S_DONE;
                        capture_active_a <= 1'b0;
                    end else if (fifo_full_a) begin
                        overflow_flag_a <= 1'b1;
                    end else if (index_edge_a) begin
                        index_count_a <= index_count_a + 1'b1;

                        if (index_seen_a) begin
                            second_index_a <= 1'b1;

                            if (capture_mode_a == MODE_ONE_REV) begin
                                state_a          <= S_DONE;
                                capture_active_a <= 1'b0;
                            end else if (capture_mode_a == MODE_ONE_TRACK && second_index_a) begin
                                state_a          <= S_DONE;
                                capture_active_a <= 1'b0;
                            end
                        end else begin
                            index_seen_a <= 1'b1;
                        end

                        if (!fifo_full_a) begin
                            // [31]=INDEX, [30]=OVF, [29]=SECTOR, [28:27]=DRV_ID, [26:0]=TS
                            fifo_wr_en_a     <= 1'b1;
                            fifo_wr_data_a   <= {1'b1, overflow_flag_a, sector_pending_a, 1'b0, drive_sel_a, flux_timestamp_reg_a[26:0]};
                            last_was_index_a <= 1'b1;
                            sector_pending_a <= 1'b0;  // Clear sector flag after write
                        end
                    end else if (flux_edge_a) begin
                        capture_count_a <= capture_count_a + 1'b1;

                        if (!fifo_full_a) begin
                            // [31]=INDEX, [30]=OVF, [29]=SECTOR, [28:27]=DRV_ID, [26:0]=TS
                            fifo_wr_en_a     <= 1'b1;
                            fifo_wr_data_a   <= {1'b0, overflow_flag_a, sector_pending_a, 1'b0, drive_sel_a, flux_timestamp_reg_a[26:0]};
                            last_was_index_a <= 1'b0;
                            overflow_flag_a  <= 1'b0;
                            sector_pending_a <= 1'b0;  // Clear sector flag after write
                        end
                    end
                end

                S_DONE: begin
                    capture_active_a <= 1'b0;
                    if (fifo_empty_a && !capture_enable_a) begin
                        state_a <= S_IDLE;
                    end else if (capture_enable_a) begin
                        state_a <= S_IDLE;
                    end
                end

                default: state_a <= S_IDLE;
            endcase
        end
    end

    // AXI-Stream A outputs
    assign m_axis_a_tdata  = fifo_rd_data_a;
    assign m_axis_a_tvalid = !fifo_empty_a;
    assign m_axis_a_tlast  = fifo_rd_data_a[31];
    assign m_axis_a_tkeep  = 4'b1111;

    assign overflow_a  = overflow_flag_a;
    assign capturing_a = capture_active_a;

    //=========================================================================
    // Interface B - Flux Capture Logic
    //=========================================================================

    // FIFO B signals
    reg  [31:0] fifo_b_mem [0:FIFO_DEPTH-1];
    reg  [FIFO_ADDR_BITS-1:0] wr_ptr_b;
    reg  [FIFO_ADDR_BITS-1:0] rd_ptr_b;
    reg  [FIFO_ADDR_BITS:0]   fifo_count_b;
    wire        fifo_full_b;
    reg         fifo_wr_en_b;
    reg  [31:0] fifo_wr_data_b;
    reg  [31:0] fifo_rd_data_b;

    // State B
    reg  [2:0]  state_b;
    reg         capture_active_b;
    reg         overflow_flag_b;
    reg         index_seen_b;
    reg         second_index_b;
    reg         last_was_index_b;
    reg         sector_pending_b;    // Sector pulse detected since last write

    // Synchronization for index
    reg  [2:0]  index_sync_b;
    wire        index_edge_b;

    // Synchronization for sector pulse (hard-sectored disks)
    reg  [2:0]  sector_sync_b;
    wire        sector_edge_b;

    // Synchronize flux inputs from FDC domain
    reg  [2:0]  flux_valid_sync_b;
    reg  [31:0] flux_timestamp_reg_b;
    wire        flux_edge_b;

    // Index edge detection
    always @(posedge aclk) begin
        if (!aresetn) begin
            index_sync_b <= 3'b000;
        end else begin
            index_sync_b <= {index_sync_b[1:0], flux_index_b};
        end
    end
    assign index_edge_b = (index_sync_b[2:1] == 2'b01);

    // Sector pulse edge detection (for hard-sectored disks)
    always @(posedge aclk) begin
        if (!aresetn) begin
            sector_sync_b <= 3'b000;
        end else begin
            sector_sync_b <= {sector_sync_b[1:0], flux_sector_b};
        end
    end
    assign sector_edge_b = (sector_sync_b[2:1] == 2'b01);

    // Flux valid edge detection and timestamp capture
    always @(posedge aclk) begin
        if (!aresetn) begin
            flux_valid_sync_b    <= 3'b000;
            flux_timestamp_reg_b <= 32'd0;
        end else begin
            flux_valid_sync_b <= {flux_valid_sync_b[1:0], flux_valid_b};
            if (flux_valid_b)
                flux_timestamp_reg_b <= flux_timestamp_b;
        end
    end
    assign flux_edge_b = (flux_valid_sync_b[2:1] == 2'b01);

    // FIFO B Write
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_b) begin
            wr_ptr_b     <= {FIFO_ADDR_BITS{1'b0}};
        end else begin
            if (fifo_wr_en_b && !fifo_full_b) begin
                fifo_b_mem[wr_ptr_b] <= fifo_wr_data_b;
                wr_ptr_b <= wr_ptr_b + 1'b1;
            end
        end
    end

    // FIFO B Read
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_b) begin
            rd_ptr_b       <= {FIFO_ADDR_BITS{1'b0}};
            fifo_rd_data_b <= 32'd0;
        end else begin
            fifo_rd_data_b <= fifo_b_mem[rd_ptr_b];
            if (m_axis_b_tvalid && m_axis_b_tready && !fifo_empty_b) begin
                rd_ptr_b <= rd_ptr_b + 1'b1;
            end
        end
    end

    // FIFO B Count
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_b) begin
            fifo_count_b <= {(FIFO_ADDR_BITS+1){1'b0}};
        end else begin
            case ({fifo_wr_en_b && !fifo_full_b, m_axis_b_tvalid && m_axis_b_tready && !fifo_empty_b})
                2'b10: fifo_count_b <= fifo_count_b + 1'b1;
                2'b01: fifo_count_b <= fifo_count_b - 1'b1;
                default: fifo_count_b <= fifo_count_b;
            endcase
        end
    end

    assign fifo_full_b  = (fifo_count_b == FIFO_DEPTH);
    assign fifo_empty_b = (fifo_count_b == 0);
    assign fifo_level_b = fifo_count_b;

    // Capture State Machine B
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_b) begin
            state_b          <= S_IDLE;
            capture_active_b <= 1'b0;
            overflow_flag_b  <= 1'b0;
            index_seen_b     <= 1'b0;
            second_index_b   <= 1'b0;
            capture_count_b  <= 32'd0;
            index_count_b    <= 16'd0;
            last_was_index_b <= 1'b0;
            sector_pending_b <= 1'b0;
            fifo_wr_en_b     <= 1'b0;
            fifo_wr_data_b   <= 32'd0;
        end else begin
            fifo_wr_en_b <= 1'b0;

            // Track sector pulses (set on edge, cleared when data written)
            if (sector_edge_b) begin
                sector_pending_b <= 1'b1;
            end

            case (state_b)
                S_IDLE: begin
                    if (capture_enable_b) begin
                        capture_count_b  <= 32'd0;
                        index_count_b    <= 16'd0;
                        overflow_flag_b  <= 1'b0;
                        index_seen_b     <= 1'b0;
                        second_index_b   <= 1'b0;
                        last_was_index_b <= 1'b0;

                        if (capture_mode_b == MODE_CONTINUOUS) begin
                            state_b          <= S_CAPTURING;
                            capture_active_b <= 1'b1;
                        end else begin
                            state_b          <= S_ARMED;
                            capture_active_b <= 1'b0;
                        end
                    end
                end

                S_ARMED: begin
                    if (!capture_enable_b) begin
                        state_b <= S_IDLE;
                    end else if (index_edge_b) begin
                        state_b          <= S_CAPTURING;
                        capture_active_b <= 1'b1;
                        index_seen_b     <= 1'b1;
                        index_count_b    <= index_count_b + 1'b1;

                        // Write index marker: [31]=INDEX, [30]=OVF, [29]=SECTOR, [28:27]=DRV_ID, [26:0]=TS
                        fifo_wr_en_b     <= 1'b1;
                        fifo_wr_data_b   <= {1'b1, overflow_flag_b, sector_pending_b, 1'b1, drive_sel_b, flux_timestamp_reg_b[26:0]};
                        last_was_index_b <= 1'b1;
                        sector_pending_b <= 1'b0;  // Clear sector flag after write
                    end
                end

                S_CAPTURING: begin
                    if (!capture_enable_b) begin
                        state_b          <= S_DONE;
                        capture_active_b <= 1'b0;
                    end else if (fifo_full_b) begin
                        overflow_flag_b <= 1'b1;
                    end else if (index_edge_b) begin
                        index_count_b <= index_count_b + 1'b1;

                        if (index_seen_b) begin
                            second_index_b <= 1'b1;

                            if (capture_mode_b == MODE_ONE_REV) begin
                                state_b          <= S_DONE;
                                capture_active_b <= 1'b0;
                            end else if (capture_mode_b == MODE_ONE_TRACK && second_index_b) begin
                                state_b          <= S_DONE;
                                capture_active_b <= 1'b0;
                            end
                        end else begin
                            index_seen_b <= 1'b1;
                        end

                        if (!fifo_full_b) begin
                            // [31]=INDEX, [30]=OVF, [29]=SECTOR, [28:27]=DRV_ID, [26:0]=TS
                            fifo_wr_en_b     <= 1'b1;
                            fifo_wr_data_b   <= {1'b1, overflow_flag_b, sector_pending_b, 1'b1, drive_sel_b, flux_timestamp_reg_b[26:0]};
                            last_was_index_b <= 1'b1;
                            sector_pending_b <= 1'b0;  // Clear sector flag after write
                        end
                    end else if (flux_edge_b) begin
                        capture_count_b <= capture_count_b + 1'b1;

                        if (!fifo_full_b) begin
                            // [31]=INDEX, [30]=OVF, [29]=SECTOR, [28:27]=DRV_ID, [26:0]=TS
                            fifo_wr_en_b     <= 1'b1;
                            fifo_wr_data_b   <= {1'b0, overflow_flag_b, sector_pending_b, 1'b1, drive_sel_b, flux_timestamp_reg_b[26:0]};
                            last_was_index_b <= 1'b0;
                            overflow_flag_b  <= 1'b0;
                            sector_pending_b <= 1'b0;  // Clear sector flag after write
                        end
                    end
                end

                S_DONE: begin
                    capture_active_b <= 1'b0;
                    if (fifo_empty_b && !capture_enable_b) begin
                        state_b <= S_IDLE;
                    end else if (capture_enable_b) begin
                        state_b <= S_IDLE;
                    end
                end

                default: state_b <= S_IDLE;
            endcase
        end
    end

    // AXI-Stream B outputs
    assign m_axis_b_tdata  = fifo_rd_data_b;
    assign m_axis_b_tvalid = !fifo_empty_b;
    assign m_axis_b_tlast  = fifo_rd_data_b[31];
    assign m_axis_b_tkeep  = 4'b1111;

    assign overflow_b  = overflow_flag_b;
    assign capturing_b = capture_active_b;

endmodule


//-----------------------------------------------------------------------------
// Testbench for Dual AXI-Stream Flux
//-----------------------------------------------------------------------------
`ifdef SIMULATION

module tb_axi_stream_flux_dual;

    // Clock and reset
    reg         aclk;
    reg         aresetn;

    // Interface A flux inputs
    reg         flux_valid_a;
    reg  [31:0] flux_timestamp_a;
    reg         flux_index_a;
    reg         flux_sector_a;
    reg         drive_sel_a;

    // Interface B flux inputs
    reg         flux_valid_b;
    reg  [31:0] flux_timestamp_b;
    reg         flux_index_b;
    reg         flux_sector_b;
    reg         drive_sel_b;

    // AXI-Stream A
    wire [31:0] m_axis_a_tdata;
    wire        m_axis_a_tvalid;
    reg         m_axis_a_tready;
    wire        m_axis_a_tlast;
    wire [3:0]  m_axis_a_tkeep;

    // AXI-Stream B
    wire [31:0] m_axis_b_tdata;
    wire        m_axis_b_tvalid;
    reg         m_axis_b_tready;
    wire        m_axis_b_tlast;
    wire [3:0]  m_axis_b_tkeep;

    // Control A
    reg         capture_enable_a;
    reg         soft_reset_a;
    reg  [1:0]  capture_mode_a;

    // Control B
    reg         capture_enable_b;
    reg         soft_reset_b;
    reg  [1:0]  capture_mode_b;

    // Status A
    wire [31:0] capture_count_a;
    wire [15:0] index_count_a;
    wire        overflow_a;
    wire        capturing_a;
    wire        fifo_empty_a;
    wire [8:0]  fifo_level_a;

    // Status B
    wire [31:0] capture_count_b;
    wire [15:0] index_count_b;
    wire        overflow_b;
    wire        capturing_b;
    wire        fifo_empty_b;
    wire [8:0]  fifo_level_b;

    // DUT
    axi_stream_flux_dual #(
        .FIFO_DEPTH(256),
        .FIFO_ADDR_BITS(8),
        .CLK_DIV(4)  // Faster for simulation
    ) u_dut (
        .aclk(aclk),
        .aresetn(aresetn),
        // Interface A
        .flux_valid_a(flux_valid_a),
        .flux_timestamp_a(flux_timestamp_a),
        .flux_index_a(flux_index_a),
        .flux_sector_a(flux_sector_a),
        .drive_sel_a(drive_sel_a),
        // Interface B
        .flux_valid_b(flux_valid_b),
        .flux_timestamp_b(flux_timestamp_b),
        .flux_index_b(flux_index_b),
        .flux_sector_b(flux_sector_b),
        .drive_sel_b(drive_sel_b),
        // AXI-Stream A
        .m_axis_a_tdata(m_axis_a_tdata),
        .m_axis_a_tvalid(m_axis_a_tvalid),
        .m_axis_a_tready(m_axis_a_tready),
        .m_axis_a_tlast(m_axis_a_tlast),
        .m_axis_a_tkeep(m_axis_a_tkeep),
        // AXI-Stream B
        .m_axis_b_tdata(m_axis_b_tdata),
        .m_axis_b_tvalid(m_axis_b_tvalid),
        .m_axis_b_tready(m_axis_b_tready),
        .m_axis_b_tlast(m_axis_b_tlast),
        .m_axis_b_tkeep(m_axis_b_tkeep),
        // Control A
        .capture_enable_a(capture_enable_a),
        .soft_reset_a(soft_reset_a),
        .capture_mode_a(capture_mode_a),
        // Control B
        .capture_enable_b(capture_enable_b),
        .soft_reset_b(soft_reset_b),
        .capture_mode_b(capture_mode_b),
        // Status A
        .capture_count_a(capture_count_a),
        .index_count_a(index_count_a),
        .overflow_a(overflow_a),
        .capturing_a(capturing_a),
        .fifo_empty_a(fifo_empty_a),
        .fifo_level_a(fifo_level_a),
        // Status B
        .capture_count_b(capture_count_b),
        .index_count_b(index_count_b),
        .overflow_b(overflow_b),
        .capturing_b(capturing_b),
        .fifo_empty_b(fifo_empty_b),
        .fifo_level_b(fifo_level_b)
    );

    // Clock generation (100 MHz AXI clock)
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end

    // Timestamp counters (simulating FDC domain)
    reg [31:0] ts_counter_a;
    reg [31:0] ts_counter_b;

    always @(posedge aclk) begin
        if (!aresetn) begin
            ts_counter_a <= 32'd0;
            ts_counter_b <= 32'd0;
        end else begin
            ts_counter_a <= ts_counter_a + 1;
            ts_counter_b <= ts_counter_b + 1;
        end
    end

    // Task to generate flux pulse on interface A
    task generate_flux_a;
        begin
            flux_timestamp_a = ts_counter_a;
            flux_valid_a = 1;
            @(posedge aclk);
            flux_valid_a = 0;
            @(posedge aclk);
        end
    endtask

    // Task to generate flux pulse on interface B
    task generate_flux_b;
        begin
            flux_timestamp_b = ts_counter_b;
            flux_valid_b = 1;
            @(posedge aclk);
            flux_valid_b = 0;
            @(posedge aclk);
        end
    endtask

    // Task to generate index on interface A
    task generate_index_a;
        begin
            flux_index_a = 1;
            @(posedge aclk);
            @(posedge aclk);
            flux_index_a = 0;
            @(posedge aclk);
        end
    endtask

    // Task to generate index on interface B
    task generate_index_b;
        begin
            flux_index_b = 1;
            @(posedge aclk);
            @(posedge aclk);
            flux_index_b = 0;
            @(posedge aclk);
        end
    endtask

    // Task to generate sector pulse on interface A (hard-sectored disk)
    task generate_sector_a;
        begin
            flux_sector_a = 1;
            @(posedge aclk);
            @(posedge aclk);
            flux_sector_a = 0;
            @(posedge aclk);
        end
    endtask

    // Task to generate sector pulse on interface B (hard-sectored disk)
    task generate_sector_b;
        begin
            flux_sector_b = 1;
            @(posedge aclk);
            @(posedge aclk);
            flux_sector_b = 0;
            @(posedge aclk);
        end
    endtask

    // Test stimulus
    initial begin
        $display("===========================================");
        $display("Dual AXI-Stream Flux Testbench");
        $display("===========================================");

        // Initialize
        aresetn          = 0;
        flux_valid_a     = 0;
        flux_timestamp_a = 0;
        flux_index_a     = 0;
        flux_sector_a    = 0;
        drive_sel_a      = 0;
        flux_valid_b     = 0;
        flux_timestamp_b = 0;
        flux_index_b     = 0;
        flux_sector_b    = 0;
        drive_sel_b      = 0;
        m_axis_a_tready  = 1;
        m_axis_b_tready  = 1;
        capture_enable_a = 0;
        soft_reset_a     = 0;
        capture_mode_a   = 2'b00;  // Continuous
        capture_enable_b = 0;
        soft_reset_b     = 0;
        capture_mode_b   = 2'b00;  // Continuous

        // Reset
        #100;
        aresetn = 1;
        #100;

        $display("\n--- Test 1: Parallel Continuous Capture ---");
        capture_enable_a = 1;
        capture_enable_b = 1;
        #50;

        // Generate concurrent flux on both interfaces
        fork
            begin
                repeat(5) begin
                    #100;
                    generate_flux_a;
                end
            end
            begin
                repeat(5) begin
                    #150;  // Slightly different timing
                    generate_flux_b;
                end
            end
        join

        #200;
        $display("  Interface A: %d flux captured", capture_count_a);
        $display("  Interface B: %d flux captured", capture_count_b);

        // Stop capture
        capture_enable_a = 0;
        capture_enable_b = 0;
        #500;

        $display("\n--- Test 2: One-Track Mode with Index ---");
        soft_reset_a     = 1;
        soft_reset_b     = 1;
        #20;
        soft_reset_a     = 0;
        soft_reset_b     = 0;
        #50;

        capture_mode_a   = 2'b01;  // One track
        capture_mode_b   = 2'b10;  // One revolution
        capture_enable_a = 1;
        capture_enable_b = 1;
        #50;

        // Generate indices and flux
        generate_index_a;
        generate_index_b;
        #100;

        repeat(8) begin
            #80;
            generate_flux_a;
            generate_flux_b;
        end

        #200;
        generate_index_a;
        generate_index_b;  // B should stop (one rev)
        #100;

        repeat(4) begin
            #80;
            generate_flux_a;
        end

        #200;
        generate_index_a;  // A should stop (one track = 2 index)

        #500;
        $display("  Interface A: %d flux, %d index (mode=one_track)", capture_count_a, index_count_a);
        $display("  Interface B: %d flux, %d index (mode=one_rev)", capture_count_b, index_count_b);
        $display("  Interface A capturing: %b", capturing_a);
        $display("  Interface B capturing: %b", capturing_b);

        #500;

        $display("\n--- Test 3: Hard-Sectored Disk Capture ---");
        capture_enable_a = 0;
        soft_reset_a     = 1;
        #20;
        soft_reset_a     = 0;
        #50;

        capture_mode_a   = 2'b00;  // Continuous
        capture_enable_a = 1;
        #50;

        // Generate sector pulses with flux data
        generate_index_a;  // Start of track
        #100;

        // Sector 0
        generate_sector_a;
        repeat(3) begin
            #80;
            generate_flux_a;
        end

        // Sector 1
        generate_sector_a;
        repeat(3) begin
            #80;
            generate_flux_a;
        end

        // Sector 2
        generate_sector_a;
        repeat(3) begin
            #80;
            generate_flux_a;
        end

        #200;
        capture_enable_a = 0;
        $display("  Hard-sector test: captured %d flux, sector pulses should appear in stream", capture_count_a);

        #500;
        $display("\n===========================================");
        $display("Dual AXI-Stream Flux Test Complete");
        $display("===========================================");
        $finish;
    end

    // Monitor AXI-Stream A transactions
    // Data format: [31]=INDEX, [30]=OVF, [29]=SECTOR, [28:27]=DRV_ID, [26:0]=TS
    always @(posedge aclk) begin
        if (m_axis_a_tvalid && m_axis_a_tready) begin
            if (m_axis_a_tdata[31])
                $display("[%0t] STREAM_A INDEX: drv=%d sec=%b ts=%d", $time, m_axis_a_tdata[28:27], m_axis_a_tdata[29], m_axis_a_tdata[26:0]);
            else
                $display("[%0t] STREAM_A FLUX:  drv=%d sec=%b ts=%d", $time, m_axis_a_tdata[28:27], m_axis_a_tdata[29], m_axis_a_tdata[26:0]);
        end
    end

    // Monitor AXI-Stream B transactions
    // Data format: [31]=INDEX, [30]=OVF, [29]=SECTOR, [28:27]=DRV_ID, [26:0]=TS
    always @(posedge aclk) begin
        if (m_axis_b_tvalid && m_axis_b_tready) begin
            if (m_axis_b_tdata[31])
                $display("[%0t] STREAM_B INDEX: drv=%d sec=%b ts=%d", $time, m_axis_b_tdata[28:27], m_axis_b_tdata[29], m_axis_b_tdata[26:0]);
            else
                $display("[%0t] STREAM_B FLUX:  drv=%d sec=%b ts=%d", $time, m_axis_b_tdata[28:27], m_axis_b_tdata[29], m_axis_b_tdata[26:0]);
        end
    end

    // Timeout
    initial begin
        #100000;
        $display("Simulation timeout");
        $finish;
    end

endmodule

`endif
