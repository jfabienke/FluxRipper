//==============================================================================
// PCIe to AXI Bridge
//==============================================================================
// File: pcie_axi_bridge.v
// Description: Top-level PCIe endpoint bridge connecting to internal AXI fabric.
//              Integrates config space, BAR decode, MSI, and DMA engine.
//
// Features:
//   - PCIe 2.0 Gen2 x1 (5 GT/s, 500 MB/s)
//   - AXI4-Lite master for register access
//   - AXI4 streaming for DMA transfers
//   - Multi-function: FDC (func 0), WD HDD (func 1)
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 23:55
//==============================================================================

`timescale 1ns / 1ps

module pcie_axi_bridge #(
    parameter VENDOR_ID     = 16'h1234,
    parameter FDC_DEVICE_ID = 16'hFDC0,
    parameter WD_DEVICE_ID  = 16'hHDD0
)(
    //=========================================================================
    // Clock and Reset
    //=========================================================================
    input  wire        pcie_clk,         // PCIe clock (250 MHz for Gen2)
    input  wire        pcie_rst_n,       // PCIe reset (active low)
    input  wire        axi_clk,          // AXI clock (100 MHz)
    input  wire        axi_rst_n,        // AXI reset (active low)

    //=========================================================================
    // PCIe PHY Interface (to Xilinx PCIe IP)
    //=========================================================================
    // Configuration Interface
    input  wire [15:0] cfg_command,
    input  wire [15:0] cfg_status,
    input  wire [7:0]  cfg_bus_number,
    input  wire [4:0]  cfg_device_number,
    input  wire [2:0]  cfg_function_number,

    // Configuration Write Interface
    input  wire        cfg_wr_en,
    input  wire [9:0]  cfg_wr_addr,
    input  wire [31:0] cfg_wr_data,
    input  wire [3:0]  cfg_wr_be,

    // Configuration Read Interface
    input  wire        cfg_rd_en,
    input  wire [9:0]  cfg_rd_addr,
    output wire [31:0] cfg_rd_data,

    // BAR Hit
    input  wire [6:0]  cfg_bar_hit,

    // AXI-Stream TX (to PCIe Core - Completions and Writes)
    output wire [63:0] m_axis_tx_tdata,
    output wire [7:0]  m_axis_tx_tkeep,
    output wire        m_axis_tx_tlast,
    output wire        m_axis_tx_tvalid,
    input  wire        m_axis_tx_tready,

    // AXI-Stream RX (from PCIe Core - Requests)
    input  wire [63:0] s_axis_rx_tdata,
    input  wire [7:0]  s_axis_rx_tkeep,
    input  wire        s_axis_rx_tlast,
    input  wire        s_axis_rx_tvalid,
    output wire        s_axis_rx_tready,
    input  wire [21:0] s_axis_rx_tuser,   // {bar_hit, etc.}

    // Interrupt
    output wire        cfg_interrupt,
    input  wire        cfg_interrupt_rdy,
    output wire [7:0]  cfg_interrupt_di,
    input  wire        cfg_interrupt_sent,
    output wire        cfg_interrupt_msi_enable,

    //=========================================================================
    // AXI4-Lite Master Interface (to FDC registers)
    //=========================================================================
    output reg  [31:0] m_axi_fdc_awaddr,
    output reg         m_axi_fdc_awvalid,
    input  wire        m_axi_fdc_awready,
    output reg  [31:0] m_axi_fdc_wdata,
    output reg  [3:0]  m_axi_fdc_wstrb,
    output reg         m_axi_fdc_wvalid,
    input  wire        m_axi_fdc_wready,
    input  wire [1:0]  m_axi_fdc_bresp,
    input  wire        m_axi_fdc_bvalid,
    output reg         m_axi_fdc_bready,
    output reg  [31:0] m_axi_fdc_araddr,
    output reg         m_axi_fdc_arvalid,
    input  wire        m_axi_fdc_arready,
    input  wire [31:0] m_axi_fdc_rdata,
    input  wire [1:0]  m_axi_fdc_rresp,
    input  wire        m_axi_fdc_rvalid,
    output reg         m_axi_fdc_rready,

    //=========================================================================
    // AXI4-Lite Master Interface (to WD HDD registers)
    //=========================================================================
    output reg  [31:0] m_axi_wd_awaddr,
    output reg         m_axi_wd_awvalid,
    input  wire        m_axi_wd_awready,
    output reg  [31:0] m_axi_wd_wdata,
    output reg  [3:0]  m_axi_wd_wstrb,
    output reg         m_axi_wd_wvalid,
    input  wire        m_axi_wd_wready,
    input  wire [1:0]  m_axi_wd_bresp,
    input  wire        m_axi_wd_bvalid,
    output reg         m_axi_wd_bready,
    output reg  [31:0] m_axi_wd_araddr,
    output reg         m_axi_wd_arvalid,
    input  wire        m_axi_wd_arready,
    input  wire [31:0] m_axi_wd_rdata,
    input  wire [1:0]  m_axi_wd_rresp,
    input  wire        m_axi_wd_rvalid,
    output reg         m_axi_wd_rready,

    //=========================================================================
    // Interrupt Inputs
    //=========================================================================
    input  wire        fdc_irq,          // FDC interrupt
    input  wire        wd_irq,           // WD HDD interrupt
    input  wire        fdc_dma_done,     // FDC DMA complete
    input  wire        wd_dma_done,      // WD DMA complete

    //=========================================================================
    // DMA Buffer Interfaces
    //=========================================================================
    output wire [15:0] fdc_buf_addr,
    output wire [63:0] fdc_buf_wdata,
    output wire        fdc_buf_write,
    input  wire [63:0] fdc_buf_rdata,
    output wire        fdc_buf_read,

    output wire [15:0] wd_buf_addr,
    output wire [63:0] wd_buf_wdata,
    output wire        wd_buf_write,
    input  wire [63:0] wd_buf_rdata,
    output wire        wd_buf_read
);

    //=========================================================================
    // Internal Signals
    //=========================================================================

    // Config space
    wire [31:0] bar0_addr, bar1_addr, bar2_addr;
    wire        bar0_enabled, bar1_enabled, bar2_enabled;
    wire        bus_master_en, mem_space_en;
    wire        msi_enable;
    wire [63:0] msi_addr;
    wire [15:0] msi_data_base;
    wire [2:0]  msi_multiple_msg;

    // BAR decode
    wire        fdc_sel, wd_sel, dma_sel;
    wire [11:0] fdc_addr, wd_addr;
    wire [15:0] dma_addr;
    wire [31:0] fdc_wdata, wd_wdata, dma_wdata;
    wire [3:0]  fdc_be, wd_be, dma_be;
    wire        fdc_write, fdc_read;
    wire        wd_write, wd_read;
    wire        dma_write, dma_read;

    // MSI
    wire        msi_req;
    wire [63:0] msi_req_addr;
    wire [31:0] msi_req_data;
    reg         msi_ack;

    // DMA
    wire        dma_done_irq, dma_error_irq;

    //=========================================================================
    // TLP Parser
    //=========================================================================
    // Parse incoming TLPs from PCIe core

    localparam [7:0] TLP_MRD32    = 8'b00000000;  // Memory Read 32-bit
    localparam [7:0] TLP_MRD64    = 8'b00100000;  // Memory Read 64-bit
    localparam [7:0] TLP_MWR32    = 8'b01000000;  // Memory Write 32-bit
    localparam [7:0] TLP_MWR64    = 8'b01100000;  // Memory Write 64-bit
    localparam [7:0] TLP_CPL      = 8'b01001010;  // Completion
    localparam [7:0] TLP_CPLD     = 8'b01001010;  // Completion with Data

    reg [63:0] rx_tlp_header;
    reg [63:0] rx_tlp_addr;
    reg [31:0] rx_tlp_data;
    reg [9:0]  rx_tlp_length;
    reg [7:0]  rx_tlp_type;
    reg [7:0]  rx_tlp_tag;
    reg [15:0] rx_tlp_reqid;
    reg        rx_tlp_valid;
    reg        rx_tlp_is_write;
    reg [2:0]  rx_bar_hit;

    // RX state machine
    localparam [1:0] RX_IDLE   = 2'd0;
    localparam [1:0] RX_HEADER = 2'd1;
    localparam [1:0] RX_ADDR   = 2'd2;
    localparam [1:0] RX_DATA   = 2'd3;

    reg [1:0] rx_state;
    reg       rx_64bit_addr;

    assign s_axis_rx_tready = (rx_state == RX_IDLE) || (rx_state == RX_DATA);

    always @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            rx_state      <= RX_IDLE;
            rx_tlp_valid  <= 1'b0;
            rx_tlp_header <= 64'h0;
            rx_tlp_addr   <= 64'h0;
            rx_tlp_data   <= 32'h0;
            rx_tlp_length <= 10'h0;
            rx_tlp_type   <= 8'h0;
            rx_tlp_tag    <= 8'h0;
            rx_tlp_reqid  <= 16'h0;
            rx_tlp_is_write <= 1'b0;
            rx_64bit_addr <= 1'b0;
            rx_bar_hit    <= 3'b0;
        end else begin
            rx_tlp_valid <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (s_axis_rx_tvalid) begin
                        rx_tlp_header <= s_axis_rx_tdata;
                        rx_tlp_type   <= s_axis_rx_tdata[31:24];
                        rx_tlp_length <= s_axis_rx_tdata[9:0];
                        rx_tlp_reqid  <= s_axis_rx_tdata[63:48];
                        rx_tlp_tag    <= s_axis_rx_tdata[47:40];
                        rx_bar_hit    <= s_axis_rx_tuser[6:4];

                        // Check if 64-bit addressing
                        rx_64bit_addr <= s_axis_rx_tdata[29];

                        // Check if write
                        rx_tlp_is_write <= s_axis_rx_tdata[30];

                        rx_state <= RX_ADDR;
                    end
                end

                RX_ADDR: begin
                    if (s_axis_rx_tvalid) begin
                        if (rx_64bit_addr) begin
                            rx_tlp_addr <= s_axis_rx_tdata;
                        end else begin
                            rx_tlp_addr <= {32'h0, s_axis_rx_tdata[63:32]};
                            rx_tlp_data <= s_axis_rx_tdata[31:0];
                        end

                        if (rx_tlp_is_write) begin
                            if (rx_64bit_addr) begin
                                rx_state <= RX_DATA;
                            end else begin
                                // 32-bit write - data already captured
                                rx_tlp_valid <= 1'b1;
                                rx_state <= s_axis_rx_tlast ? RX_IDLE : RX_DATA;
                            end
                        end else begin
                            // Read request - issue immediately
                            rx_tlp_valid <= 1'b1;
                            rx_state <= RX_IDLE;
                        end
                    end
                end

                RX_DATA: begin
                    if (s_axis_rx_tvalid) begin
                        rx_tlp_data  <= s_axis_rx_tdata[31:0];
                        rx_tlp_valid <= 1'b1;

                        if (s_axis_rx_tlast) begin
                            rx_state <= RX_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    //=========================================================================
    // Configuration Space Instance
    //=========================================================================
    wire [31:0] cfg_rdata_internal;
    wire        cfg_ready;

    pcie_cfg_space #(
        .VENDOR_ID(VENDOR_ID),
        .FDC_DEVICE_ID(FDC_DEVICE_ID),
        .WD_DEVICE_ID(WD_DEVICE_ID)
    ) u_cfg_space (
        .clk(pcie_clk),
        .reset_n(pcie_rst_n),

        .cfg_addr({cfg_function_number, cfg_rd_addr[8:0]}),
        .cfg_wdata(cfg_wr_data),
        .cfg_be(cfg_wr_be),
        .cfg_write(cfg_wr_en),
        .cfg_read(cfg_rd_en),
        .cfg_rdata(cfg_rdata_internal),
        .cfg_ready(cfg_ready),

        .bar0_addr(bar0_addr),
        .bar1_addr(bar1_addr),
        .bar2_addr(bar2_addr),
        .bar0_enabled(bar0_enabled),
        .bar1_enabled(bar1_enabled),
        .bar2_enabled(bar2_enabled),

        .bus_master_en(bus_master_en),
        .mem_space_en(mem_space_en),
        .io_space_en(),
        .intx_disable(),
        .serr_enable(),

        .int_status(fdc_irq || wd_irq),
        .int_line(),
        .int_pin(),

        .msi_enable(msi_enable),
        .msi_addr(msi_addr),
        .msi_data(msi_data_base),
        .msi_multiple_msg(msi_multiple_msg),

        .power_state(),
        .pme_status(1'b0),
        .pme_enable()
    );

    assign cfg_rd_data = cfg_rdata_internal;

    //=========================================================================
    // BAR Decoder Instance
    //=========================================================================
    pcie_bar_decode u_bar_decode (
        .clk(pcie_clk),
        .reset_n(pcie_rst_n),

        .tlp_addr(rx_tlp_addr),
        .tlp_bar_hit(rx_bar_hit),
        .tlp_valid(rx_tlp_valid),
        .tlp_is_write(rx_tlp_is_write),
        .tlp_data(rx_tlp_data),
        .tlp_be(4'hF),

        .bar0_base(bar0_addr),
        .bar1_base(bar1_addr),
        .bar2_base(bar2_addr),

        .fdc_sel(fdc_sel),
        .fdc_addr(fdc_addr),
        .fdc_wdata(fdc_wdata),
        .fdc_be(fdc_be),
        .fdc_write(fdc_write),
        .fdc_read(fdc_read),

        .wd_sel(wd_sel),
        .wd_addr(wd_addr),
        .wd_wdata(wd_wdata),
        .wd_be(wd_be),
        .wd_write(wd_write),
        .wd_read(wd_read),

        .dma_sel(dma_sel),
        .dma_addr(dma_addr),
        .dma_wdata(dma_wdata),
        .dma_be(dma_be),
        .dma_write(dma_write),
        .dma_read(dma_read),

        .any_hit(),
        .active_bar()
    );

    //=========================================================================
    // MSI Controller Instance
    //=========================================================================
    wire [7:0] int_pending;

    pcie_msi_ctrl u_msi_ctrl (
        .clk(pcie_clk),
        .reset_n(pcie_rst_n),

        .msi_enable(msi_enable),
        .msi_addr(msi_addr),
        .msi_data(msi_data_base),
        .msi_multiple_msg(msi_multiple_msg),
        .msi_64bit(1'b1),
        .msi_per_vector(1'b0),

        .fdc_cmd_complete(fdc_irq),
        .fdc_dma_complete(fdc_dma_done),
        .fdc_error(1'b0),

        .wd_cmd_complete(wd_irq),
        .wd_dma_complete(wd_dma_done),
        .wd_error(1'b0),

        .buf_threshold(1'b0),

        .int_mask(8'h00),
        .int_pending(int_pending),

        .intx_assert(),

        .msi_req(msi_req),
        .msi_req_addr(msi_req_addr),
        .msi_req_data(msi_req_data),
        .msi_ack(msi_ack),

        .any_pending(),
        .last_vector()
    );

    //=========================================================================
    // DMA Engine Instance
    //=========================================================================
    // DMA control registers (directly from BAR2)
    reg [31:0] dma_ctrl_reg;
    reg [63:0] dma_host_addr_reg;
    reg [31:0] dma_local_addr_reg;
    reg [23:0] dma_length_reg;
    reg [63:0] dma_sg_addr_reg;
    reg        dma_start_reg;
    wire [31:0] dma_status;
    wire [23:0] dma_bytes_done;

    pcie_dma_engine u_dma (
        .clk(pcie_clk),
        .reset_n(pcie_rst_n),

        .dma_ctrl(dma_ctrl_reg),
        .dma_host_addr(dma_host_addr_reg),
        .dma_local_addr(dma_local_addr_reg),
        .dma_length(dma_length_reg),
        .dma_sg_addr(dma_sg_addr_reg),
        .dma_status(dma_status),
        .dma_bytes_done(dma_bytes_done),

        .ch_sel(dma_ctrl_reg[16]),
        .dma_start(dma_start_reg),
        .dma_abort(1'b0),
        .dma_direction(dma_ctrl_reg[17]),
        .sg_enable(dma_ctrl_reg[2]),

        .pcie_rd_req(),
        .pcie_wr_req(),
        .pcie_addr(),
        .pcie_len(),
        .pcie_tag(),
        .pcie_req_grant(1'b1),

        .pcie_cpl_valid(1'b0),
        .pcie_cpl_data(64'h0),
        .pcie_cpl_tag(8'h0),
        .pcie_cpl_last(1'b0),
        .pcie_cpl_ready(),

        .fdc_buf_addr(fdc_buf_addr),
        .fdc_buf_wdata(fdc_buf_wdata),
        .fdc_buf_write(fdc_buf_write),
        .fdc_buf_rdata(fdc_buf_rdata),
        .fdc_buf_read(fdc_buf_read),

        .wd_buf_addr(wd_buf_addr),
        .wd_buf_wdata(wd_buf_wdata),
        .wd_buf_write(wd_buf_write),
        .wd_buf_rdata(wd_buf_rdata),
        .wd_buf_read(wd_buf_read),

        .dma_done_irq(dma_done_irq),
        .dma_error_irq(dma_error_irq)
    );

    //=========================================================================
    // AXI Master FSM - FDC
    //=========================================================================
    localparam [1:0] AXI_IDLE   = 2'd0;
    localparam [1:0] AXI_WRITE  = 2'd1;
    localparam [1:0] AXI_READ   = 2'd2;
    localparam [1:0] AXI_RESP   = 2'd3;

    reg [1:0] fdc_axi_state;
    reg [31:0] fdc_read_data;

    always @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            fdc_axi_state     <= AXI_IDLE;
            m_axi_fdc_awvalid <= 1'b0;
            m_axi_fdc_wvalid  <= 1'b0;
            m_axi_fdc_bready  <= 1'b0;
            m_axi_fdc_arvalid <= 1'b0;
            m_axi_fdc_rready  <= 1'b0;
            m_axi_fdc_awaddr  <= 32'h0;
            m_axi_fdc_wdata   <= 32'h0;
            m_axi_fdc_wstrb   <= 4'h0;
            m_axi_fdc_araddr  <= 32'h0;
            fdc_read_data     <= 32'h0;
        end else begin
            case (fdc_axi_state)
                AXI_IDLE: begin
                    m_axi_fdc_bready <= 1'b0;
                    m_axi_fdc_rready <= 1'b0;

                    if (fdc_write) begin
                        m_axi_fdc_awaddr  <= {20'h0, fdc_addr};
                        m_axi_fdc_awvalid <= 1'b1;
                        m_axi_fdc_wdata   <= fdc_wdata;
                        m_axi_fdc_wstrb   <= fdc_be;
                        m_axi_fdc_wvalid  <= 1'b1;
                        fdc_axi_state     <= AXI_WRITE;
                    end else if (fdc_read) begin
                        m_axi_fdc_araddr  <= {20'h0, fdc_addr};
                        m_axi_fdc_arvalid <= 1'b1;
                        fdc_axi_state     <= AXI_READ;
                    end
                end

                AXI_WRITE: begin
                    if (m_axi_fdc_awready) m_axi_fdc_awvalid <= 1'b0;
                    if (m_axi_fdc_wready)  m_axi_fdc_wvalid  <= 1'b0;

                    if (!m_axi_fdc_awvalid && !m_axi_fdc_wvalid) begin
                        m_axi_fdc_bready <= 1'b1;
                        fdc_axi_state <= AXI_RESP;
                    end
                end

                AXI_READ: begin
                    if (m_axi_fdc_arready) begin
                        m_axi_fdc_arvalid <= 1'b0;
                        m_axi_fdc_rready  <= 1'b1;
                        fdc_axi_state <= AXI_RESP;
                    end
                end

                AXI_RESP: begin
                    if (m_axi_fdc_bvalid) begin
                        m_axi_fdc_bready <= 1'b0;
                        fdc_axi_state <= AXI_IDLE;
                    end
                    if (m_axi_fdc_rvalid) begin
                        fdc_read_data <= m_axi_fdc_rdata;
                        m_axi_fdc_rready <= 1'b0;
                        fdc_axi_state <= AXI_IDLE;
                    end
                end
            endcase
        end
    end

    //=========================================================================
    // AXI Master FSM - WD HDD (similar to FDC)
    //=========================================================================
    reg [1:0] wd_axi_state;
    reg [31:0] wd_read_data;

    always @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            wd_axi_state     <= AXI_IDLE;
            m_axi_wd_awvalid <= 1'b0;
            m_axi_wd_wvalid  <= 1'b0;
            m_axi_wd_bready  <= 1'b0;
            m_axi_wd_arvalid <= 1'b0;
            m_axi_wd_rready  <= 1'b0;
            m_axi_wd_awaddr  <= 32'h0;
            m_axi_wd_wdata   <= 32'h0;
            m_axi_wd_wstrb   <= 4'h0;
            m_axi_wd_araddr  <= 32'h0;
            wd_read_data     <= 32'h0;
        end else begin
            case (wd_axi_state)
                AXI_IDLE: begin
                    m_axi_wd_bready <= 1'b0;
                    m_axi_wd_rready <= 1'b0;

                    if (wd_write) begin
                        m_axi_wd_awaddr  <= {20'h0, wd_addr};
                        m_axi_wd_awvalid <= 1'b1;
                        m_axi_wd_wdata   <= wd_wdata;
                        m_axi_wd_wstrb   <= wd_be;
                        m_axi_wd_wvalid  <= 1'b1;
                        wd_axi_state     <= AXI_WRITE;
                    end else if (wd_read) begin
                        m_axi_wd_araddr  <= {20'h0, wd_addr};
                        m_axi_wd_arvalid <= 1'b1;
                        wd_axi_state     <= AXI_READ;
                    end
                end

                AXI_WRITE: begin
                    if (m_axi_wd_awready) m_axi_wd_awvalid <= 1'b0;
                    if (m_axi_wd_wready)  m_axi_wd_wvalid  <= 1'b0;

                    if (!m_axi_wd_awvalid && !m_axi_wd_wvalid) begin
                        m_axi_wd_bready <= 1'b1;
                        wd_axi_state <= AXI_RESP;
                    end
                end

                AXI_READ: begin
                    if (m_axi_wd_arready) begin
                        m_axi_wd_arvalid <= 1'b0;
                        m_axi_wd_rready  <= 1'b1;
                        wd_axi_state <= AXI_RESP;
                    end
                end

                AXI_RESP: begin
                    if (m_axi_wd_bvalid) begin
                        m_axi_wd_bready <= 1'b0;
                        wd_axi_state <= AXI_IDLE;
                    end
                    if (m_axi_wd_rvalid) begin
                        wd_read_data <= m_axi_wd_rdata;
                        m_axi_wd_rready <= 1'b0;
                        wd_axi_state <= AXI_IDLE;
                    end
                end
            endcase
        end
    end

    //=========================================================================
    // TX TLP Generator (Completions)
    //=========================================================================
    // Simplified - full implementation would handle all TLP types

    reg [63:0] tx_data;
    reg        tx_valid;
    reg        tx_last;
    reg [7:0]  tx_keep;

    assign m_axis_tx_tdata  = tx_data;
    assign m_axis_tx_tkeep  = tx_keep;
    assign m_axis_tx_tlast  = tx_last;
    assign m_axis_tx_tvalid = tx_valid;

    // TX state machine for completions
    localparam [1:0] TX_IDLE    = 2'd0;
    localparam [1:0] TX_CPL_HDR = 2'd1;
    localparam [1:0] TX_CPL_DAT = 2'd2;
    localparam [1:0] TX_MSI     = 2'd3;

    reg [1:0] tx_state;
    reg [15:0] cpl_reqid;
    reg [7:0]  cpl_tag;
    reg [31:0] cpl_data;
    reg        cpl_pending;

    always @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            tx_state    <= TX_IDLE;
            tx_data     <= 64'h0;
            tx_valid    <= 1'b0;
            tx_last     <= 1'b0;
            tx_keep     <= 8'h0;
            cpl_pending <= 1'b0;
            msi_ack     <= 1'b0;
        end else begin
            msi_ack <= 1'b0;

            case (tx_state)
                TX_IDLE: begin
                    tx_valid <= 1'b0;

                    // Check for MSI request (higher priority)
                    if (msi_req && !msi_ack) begin
                        tx_state <= TX_MSI;
                    end
                    // Check for pending completion
                    else if (cpl_pending) begin
                        tx_state <= TX_CPL_HDR;
                    end
                end

                TX_CPL_HDR: begin
                    // Build completion TLP header
                    tx_data <= {
                        cpl_reqid,              // Requester ID
                        cpl_tag,                // Tag
                        8'h00,                  // Reserved
                        3'b000,                 // Completion status (successful)
                        1'b0,                   // BCM
                        12'd4,                  // Byte count
                        {cfg_bus_number, cfg_device_number, cfg_function_number},
                        3'b010,                 // Completion with data
                        1'b0,                   // Reserved
                        3'b000,                 // TC
                        4'h0,                   // Reserved
                        1'b0,                   // TD
                        1'b0,                   // EP
                        2'b00,                  // Attr
                        2'b00,                  // Reserved
                        10'd1                   // Length (1 DW)
                    };
                    tx_valid <= 1'b1;
                    tx_last  <= 1'b0;
                    tx_keep  <= 8'hFF;

                    if (m_axis_tx_tready) begin
                        tx_state <= TX_CPL_DAT;
                    end
                end

                TX_CPL_DAT: begin
                    tx_data <= {32'h0, cpl_data};
                    tx_last <= 1'b1;
                    tx_keep <= 8'h0F;

                    if (m_axis_tx_tready) begin
                        tx_valid <= 1'b0;
                        cpl_pending <= 1'b0;
                        tx_state <= TX_IDLE;
                    end
                end

                TX_MSI: begin
                    // Build MSI write TLP (memory write to MSI address)
                    tx_data <= {
                        msi_req_addr[31:0],     // Address
                        16'h0,                  // Requester ID
                        8'h00,                  // Tag
                        4'hF,                   // Last/First BE
                        3'b010,                 // Memory write
                        1'b0,
                        3'b000,
                        4'h0,
                        1'b0,
                        1'b0,
                        2'b00,
                        2'b00,
                        10'd1
                    };
                    tx_valid <= 1'b1;
                    tx_last  <= 1'b0;
                    tx_keep  <= 8'hFF;

                    if (m_axis_tx_tready) begin
                        // Next: send data
                        tx_data <= {32'h0, msi_req_data};
                        tx_last <= 1'b1;
                        tx_keep <= 8'h0F;
                        msi_ack <= 1'b1;
                        tx_state <= TX_IDLE;
                    end
                end
            endcase

            // Capture completion data when read completes
            if (fdc_axi_state == AXI_RESP && m_axi_fdc_rvalid) begin
                cpl_data    <= m_axi_fdc_rdata;
                cpl_reqid   <= rx_tlp_reqid;
                cpl_tag     <= rx_tlp_tag;
                cpl_pending <= 1'b1;
            end
            if (wd_axi_state == AXI_RESP && m_axi_wd_rvalid) begin
                cpl_data    <= m_axi_wd_rdata;
                cpl_reqid   <= rx_tlp_reqid;
                cpl_tag     <= rx_tlp_tag;
                cpl_pending <= 1'b1;
            end
        end
    end

    //=========================================================================
    // Legacy Interrupt (if MSI disabled)
    //=========================================================================
    assign cfg_interrupt = !msi_enable && (fdc_irq || wd_irq);
    assign cfg_interrupt_di = 8'h0;
    assign cfg_interrupt_msi_enable = msi_enable;

endmodule
