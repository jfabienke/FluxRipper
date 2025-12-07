//==============================================================================
// PCIe MSI Controller
//==============================================================================
// File: pcie_msi_ctrl.v
// Description: Message Signaled Interrupt controller for PCIe endpoint.
//              Supports multiple interrupt vectors for FDC and WD HDD events.
//
// MSI Vector Assignment:
//   Vector 0: FDC command complete
//   Vector 1: FDC DMA complete
//   Vector 2: FDC error
//   Vector 3: WD command complete
//   Vector 4: WD DMA complete
//   Vector 5: WD error
//   Vector 6: Buffer threshold (shared)
//   Vector 7: Reserved
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 23:45
//==============================================================================

`timescale 1ns / 1ps

module pcie_msi_ctrl #(
    parameter NUM_VECTORS = 8            // Number of MSI vectors (1, 2, 4, 8, 16, 32)
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // MSI Configuration (from config space)
    //=========================================================================
    input  wire        msi_enable,       // MSI enabled
    input  wire [63:0] msi_addr,         // MSI address
    input  wire [15:0] msi_data,         // MSI data base
    input  wire [2:0]  msi_multiple_msg, // log2(allocated vectors)
    input  wire        msi_64bit,        // 64-bit addressing capable
    input  wire        msi_per_vector,   // Per-vector masking capable

    //=========================================================================
    // Interrupt Sources - FDC
    //=========================================================================
    input  wire        fdc_cmd_complete, // FDC command completed
    input  wire        fdc_dma_complete, // FDC DMA transfer complete
    input  wire        fdc_error,        // FDC error occurred

    //=========================================================================
    // Interrupt Sources - WD HDD
    //=========================================================================
    input  wire        wd_cmd_complete,  // WD command completed
    input  wire        wd_dma_complete,  // WD DMA transfer complete
    input  wire        wd_error,         // WD error occurred

    //=========================================================================
    // Interrupt Sources - Shared
    //=========================================================================
    input  wire        buf_threshold,    // Buffer threshold reached

    //=========================================================================
    // Interrupt Masking
    //=========================================================================
    input  wire [7:0]  int_mask,         // Per-vector interrupt mask
    output reg  [7:0]  int_pending,      // Pending interrupts (status)

    //=========================================================================
    // Legacy INTx (fallback)
    //=========================================================================
    output reg         intx_assert,      // Assert INTx (active low on bus)

    //=========================================================================
    // MSI TLP Generation Interface
    //=========================================================================
    output reg         msi_req,          // Request to send MSI
    output reg  [63:0] msi_req_addr,     // MSI write address
    output reg  [31:0] msi_req_data,     // MSI write data
    input  wire        msi_ack,          // MSI request acknowledged

    //=========================================================================
    // Status
    //=========================================================================
    output wire        any_pending,      // Any interrupt pending
    output reg  [2:0]  last_vector       // Last vector sent
);

    //=========================================================================
    // Interrupt Vector Encoding
    //=========================================================================
    localparam [2:0] VEC_FDC_CMD    = 3'd0;
    localparam [2:0] VEC_FDC_DMA    = 3'd1;
    localparam [2:0] VEC_FDC_ERR    = 3'd2;
    localparam [2:0] VEC_WD_CMD     = 3'd3;
    localparam [2:0] VEC_WD_DMA     = 3'd4;
    localparam [2:0] VEC_WD_ERR     = 3'd5;
    localparam [2:0] VEC_BUF_THRESH = 3'd6;
    localparam [2:0] VEC_RESERVED   = 3'd7;

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [1:0] ST_IDLE     = 2'd0;
    localparam [1:0] ST_SELECT   = 2'd1;
    localparam [1:0] ST_SEND_MSI = 2'd2;
    localparam [1:0] ST_WAIT_ACK = 2'd3;

    reg [1:0] state;

    //=========================================================================
    // Edge Detection for Interrupt Sources
    //=========================================================================
    reg fdc_cmd_complete_d, fdc_dma_complete_d, fdc_error_d;
    reg wd_cmd_complete_d, wd_dma_complete_d, wd_error_d;
    reg buf_threshold_d;

    wire fdc_cmd_edge = fdc_cmd_complete && !fdc_cmd_complete_d;
    wire fdc_dma_edge = fdc_dma_complete && !fdc_dma_complete_d;
    wire fdc_err_edge = fdc_error && !fdc_error_d;
    wire wd_cmd_edge  = wd_cmd_complete && !wd_cmd_complete_d;
    wire wd_dma_edge  = wd_dma_complete && !wd_dma_complete_d;
    wire wd_err_edge  = wd_error && !wd_error_d;
    wire buf_thr_edge = buf_threshold && !buf_threshold_d;

    always @(posedge clk) begin
        fdc_cmd_complete_d <= fdc_cmd_complete;
        fdc_dma_complete_d <= fdc_dma_complete;
        fdc_error_d        <= fdc_error;
        wd_cmd_complete_d  <= wd_cmd_complete;
        wd_dma_complete_d  <= wd_dma_complete;
        wd_error_d         <= wd_error;
        buf_threshold_d    <= buf_threshold;
    end

    //=========================================================================
    // Pending Interrupt Register
    //=========================================================================
    // Set on edge, clear when MSI is sent

    reg [7:0] int_set;
    reg [7:0] int_clear;

    always @(*) begin
        int_set = 8'h00;
        int_set[VEC_FDC_CMD]    = fdc_cmd_edge;
        int_set[VEC_FDC_DMA]    = fdc_dma_edge;
        int_set[VEC_FDC_ERR]    = fdc_err_edge;
        int_set[VEC_WD_CMD]     = wd_cmd_edge;
        int_set[VEC_WD_DMA]     = wd_dma_edge;
        int_set[VEC_WD_ERR]     = wd_err_edge;
        int_set[VEC_BUF_THRESH] = buf_thr_edge;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            int_pending <= 8'h00;
        end else begin
            int_pending <= (int_pending | int_set) & ~int_clear;
        end
    end

    // Masked pending (only unmasked interrupts can fire)
    wire [7:0] int_pending_unmasked = int_pending & ~int_mask;
    assign any_pending = |int_pending_unmasked;

    //=========================================================================
    // Vector Allocation
    //=========================================================================
    // Actual number of vectors allocated by system
    wire [4:0] num_allocated = (5'd1 << msi_multiple_msg);

    // Mask for vector number based on allocated count
    wire [4:0] vector_mask = num_allocated - 1;

    //=========================================================================
    // Priority Encoder for Vector Selection
    //=========================================================================
    reg [2:0] selected_vector;
    reg       vector_valid;

    always @(*) begin
        selected_vector = 3'd0;
        vector_valid = 1'b0;

        // Priority: FDC_CMD > FDC_DMA > FDC_ERR > WD_CMD > WD_DMA > WD_ERR > BUF
        casez (int_pending_unmasked)
            8'b???????1: begin selected_vector = VEC_FDC_CMD;    vector_valid = 1'b1; end
            8'b??????10: begin selected_vector = VEC_FDC_DMA;    vector_valid = 1'b1; end
            8'b?????100: begin selected_vector = VEC_FDC_ERR;    vector_valid = 1'b1; end
            8'b????1000: begin selected_vector = VEC_WD_CMD;     vector_valid = 1'b1; end
            8'b???10000: begin selected_vector = VEC_WD_DMA;     vector_valid = 1'b1; end
            8'b??100000: begin selected_vector = VEC_WD_ERR;     vector_valid = 1'b1; end
            8'b?1000000: begin selected_vector = VEC_BUF_THRESH; vector_valid = 1'b1; end
            default:     begin selected_vector = 3'd0;           vector_valid = 1'b0; end
        endcase
    end

    //=========================================================================
    // MSI Data Calculation
    //=========================================================================
    // MSI data = base data + vector number (masked by allocation)
    wire [15:0] msi_data_vector = msi_data + {13'h0, (selected_vector & vector_mask[2:0])};

    //=========================================================================
    // State Machine
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= ST_IDLE;
            msi_req      <= 1'b0;
            msi_req_addr <= 64'h0;
            msi_req_data <= 32'h0;
            int_clear    <= 8'h00;
            last_vector  <= 3'd0;
            intx_assert  <= 1'b0;

        end else begin
            // Default: no clear
            int_clear <= 8'h00;

            case (state)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    msi_req <= 1'b0;

                    if (any_pending) begin
                        if (msi_enable) begin
                            // MSI mode
                            state <= ST_SELECT;
                        end else begin
                            // Legacy INTx mode
                            intx_assert <= 1'b1;
                        end
                    end else begin
                        intx_assert <= 1'b0;
                    end
                end

                //-------------------------------------------------------------
                ST_SELECT: begin
                    // Capture selected vector and build MSI
                    if (vector_valid) begin
                        msi_req_addr <= msi_addr;
                        msi_req_data <= {16'h0, msi_data_vector};
                        last_vector  <= selected_vector;
                        state        <= ST_SEND_MSI;
                    end else begin
                        // No valid vector (shouldn't happen)
                        state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                ST_SEND_MSI: begin
                    // Assert MSI request
                    msi_req <= 1'b1;
                    state   <= ST_WAIT_ACK;
                end

                //-------------------------------------------------------------
                ST_WAIT_ACK: begin
                    if (msi_ack) begin
                        // MSI sent, clear pending bit
                        msi_req <= 1'b0;
                        int_clear[last_vector] <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    //=========================================================================
    // Coalescing Support (Optional)
    //=========================================================================
    // Add interrupt coalescing timer for high-throughput scenarios

    reg [15:0] coalesce_timer;
    reg [7:0]  coalesce_count;
    reg        coalesce_enable;

    // Coalescing parameters (from config)
    reg [15:0] coalesce_timeout;  // Timer threshold
    reg [7:0]  coalesce_max;      // Max interrupts before forced delivery

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            coalesce_timer  <= 16'h0;
            coalesce_count  <= 8'h0;
            coalesce_enable <= 1'b0;
            coalesce_timeout <= 16'h1000;  // Default ~4096 clocks
            coalesce_max    <= 8'h10;      // Default 16 interrupts
        end else begin
            // Timer logic (simplified - full implementation would gate interrupt delivery)
            if (any_pending && !coalesce_enable) begin
                coalesce_timer <= coalesce_timer + 1;
                if (|int_set) coalesce_count <= coalesce_count + 1;
            end else begin
                coalesce_timer <= 16'h0;
                coalesce_count <= 8'h0;
            end
        end
    end

endmodule

//==============================================================================
// MSI-X Controller (Extended)
//==============================================================================
// Optional MSI-X support with per-vector table.
//==============================================================================

module pcie_msix_ctrl #(
    parameter NUM_VECTORS = 8
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // MSI-X Table Access (BAR space)
    //=========================================================================
    input  wire [11:0] table_addr,       // Table address
    input  wire [31:0] table_wdata,      // Table write data
    input  wire        table_write,      // Table write enable
    output reg  [31:0] table_rdata,      // Table read data

    //=========================================================================
    // MSI-X PBA Access (Pending Bit Array)
    //=========================================================================
    input  wire [11:0] pba_addr,
    output reg  [31:0] pba_rdata,

    //=========================================================================
    // MSI-X Control
    //=========================================================================
    input  wire        msix_enable,      // MSI-X enabled
    input  wire        msix_func_mask,   // Function mask

    //=========================================================================
    // Interrupt Vector Request
    //=========================================================================
    input  wire [2:0]  int_vector,       // Vector to fire
    input  wire        int_request,      // Fire request
    output wire        int_busy,         // Controller busy

    //=========================================================================
    // TLP Generation
    //=========================================================================
    output reg         msi_req,
    output reg  [63:0] msi_req_addr,
    output reg  [31:0] msi_req_data,
    input  wire        msi_ack
);

    //=========================================================================
    // MSI-X Table Entry Structure (16 bytes per entry)
    //=========================================================================
    // Offset 0x00: Message Address Low
    // Offset 0x04: Message Address High
    // Offset 0x08: Message Data
    // Offset 0x0C: Vector Control (bit 0 = mask)

    reg [31:0] table_addr_lo  [0:NUM_VECTORS-1];
    reg [31:0] table_addr_hi  [0:NUM_VECTORS-1];
    reg [31:0] table_data     [0:NUM_VECTORS-1];
    reg [31:0] table_ctrl     [0:NUM_VECTORS-1];

    // Pending Bit Array
    reg [NUM_VECTORS-1:0] pending_bits;

    // Entry index and field select
    wire [2:0] entry_idx   = table_addr[6:4];   // Entry (0-7)
    wire [1:0] field_sel   = table_addr[3:2];   // Field (0-3)

    //=========================================================================
    // Table Read/Write
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            integer i;
            for (i = 0; i < NUM_VECTORS; i = i + 1) begin
                table_addr_lo[i] <= 32'h0;
                table_addr_hi[i] <= 32'h0;
                table_data[i]    <= 32'h0;
                table_ctrl[i]    <= 32'h1;  // Masked by default
            end
        end else if (table_write) begin
            case (field_sel)
                2'b00: table_addr_lo[entry_idx] <= table_wdata;
                2'b01: table_addr_hi[entry_idx] <= table_wdata;
                2'b10: table_data[entry_idx]    <= table_wdata;
                2'b11: table_ctrl[entry_idx]    <= table_wdata;
            endcase
        end
    end

    always @(*) begin
        case (field_sel)
            2'b00: table_rdata = table_addr_lo[entry_idx];
            2'b01: table_rdata = table_addr_hi[entry_idx];
            2'b10: table_rdata = table_data[entry_idx];
            2'b11: table_rdata = table_ctrl[entry_idx];
        endcase
    end

    // PBA read
    always @(*) begin
        pba_rdata = {{(32-NUM_VECTORS){1'b0}}, pending_bits};
    end

    //=========================================================================
    // Interrupt Delivery
    //=========================================================================
    reg [1:0] state;
    localparam ST_IDLE = 2'd0;
    localparam ST_SEND = 2'd1;
    localparam ST_WAIT = 2'd2;

    reg [2:0] active_vector;
    wire vector_masked = table_ctrl[int_vector][0] || msix_func_mask;

    assign int_busy = (state != ST_IDLE);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= ST_IDLE;
            msi_req       <= 1'b0;
            msi_req_addr  <= 64'h0;
            msi_req_data  <= 32'h0;
            pending_bits  <= {NUM_VECTORS{1'b0}};
            active_vector <= 3'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    msi_req <= 1'b0;
                    if (int_request && msix_enable) begin
                        if (vector_masked) begin
                            // Set pending bit
                            pending_bits[int_vector] <= 1'b1;
                        end else begin
                            // Send MSI-X
                            active_vector <= int_vector;
                            msi_req_addr  <= {table_addr_hi[int_vector], table_addr_lo[int_vector]};
                            msi_req_data  <= table_data[int_vector];
                            state         <= ST_SEND;
                        end
                    end
                end

                ST_SEND: begin
                    msi_req <= 1'b1;
                    state   <= ST_WAIT;
                end

                ST_WAIT: begin
                    if (msi_ack) begin
                        msi_req <= 1'b0;
                        pending_bits[active_vector] <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
