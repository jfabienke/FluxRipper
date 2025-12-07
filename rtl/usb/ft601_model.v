//-----------------------------------------------------------------------------
// ft601_model.v
// FT601 USB 3.0 FIFO Bridge Behavioral Model for Simulation
//
// Created: 2025-12-05 08:00
//
// This module emulates the FTDI FT601Q-B USB 3.0 FIFO bridge chip for
// simulation purposes. It provides:
//   - 100 MHz FIFO clock generation
//   - TX/RX FIFO emulation with configurable depth
//   - USB host command injection interface
//   - USB device response capture interface
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module ft601_model #(
    parameter FIFO_DEPTH     = 4096,    // Internal FIFO depth
    parameter CLK_PERIOD_NS  = 10,      // 100 MHz = 10ns period
    parameter TURNAROUND_CYC = 2        // Bus turnaround cycles
)(
    // FT601 FIFO interface (directly to FPGA)
    output reg         ft_clk,          // 100 MHz clock
    inout  wire [31:0] ft_data,         // Bidirectional data bus
    inout  wire [3:0]  ft_be,           // Byte enables
    output reg         ft_rxf_n,        // RX FIFO not empty
    output reg         ft_txe_n,        // TX FIFO not full
    input  wire        ft_rd_n,         // Read strobe
    input  wire        ft_wr_n,         // Write strobe
    input  wire        ft_oe_n,         // Output enable
    input  wire        ft_siwu_n,       // Send immediate
    output reg         ft_wakeup_n,     // Wakeup/connected

    // Testbench interface - Host side (to inject/capture USB traffic)
    input  wire        host_clk,
    input  wire        host_rst_n,

    // Host TX path (data FROM host TO device via ft_data)
    input  wire [31:0] host_tx_data,
    input  wire [3:0]  host_tx_be,      // [3:2]=channel, [1:0]=byte enable
    input  wire        host_tx_valid,
    output wire        host_tx_ready,

    // Host RX path (data FROM device TO host)
    output wire [31:0] host_rx_data,
    output wire [3:0]  host_rx_be,
    output wire        host_rx_valid,
    input  wire        host_rx_ready,

    // Control
    input  wire        usb_connect,     // Simulate USB connection
    input  wire        usb_suspend      // Simulate USB suspend
);

    //=========================================================================
    // Clock Generation
    //=========================================================================

    initial begin
        ft_clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) ft_clk = ~ft_clk;
    end

    //=========================================================================
    // Internal FIFOs
    //=========================================================================

    // RX FIFO: Host TX -> Device (FPGA reads via ft_rd_n)
    reg [35:0] rx_fifo [0:FIFO_DEPTH-1];  // [35:32]=BE, [31:0]=data
    reg [$clog2(FIFO_DEPTH):0] rx_wr_ptr;
    reg [$clog2(FIFO_DEPTH):0] rx_rd_ptr;
    wire [$clog2(FIFO_DEPTH):0] rx_count;
    wire rx_empty, rx_full;

    assign rx_count = rx_wr_ptr - rx_rd_ptr;
    assign rx_empty = (rx_wr_ptr == rx_rd_ptr);
    assign rx_full  = (rx_count >= FIFO_DEPTH);

    // TX FIFO: Device -> Host TX (FPGA writes via ft_wr_n)
    reg [35:0] tx_fifo [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH):0] tx_wr_ptr;
    reg [$clog2(FIFO_DEPTH):0] tx_rd_ptr;
    wire [$clog2(FIFO_DEPTH):0] tx_count;
    wire tx_empty, tx_full;

    assign tx_count = tx_wr_ptr - tx_rd_ptr;
    assign tx_empty = (tx_wr_ptr == tx_rd_ptr);
    assign tx_full  = (tx_count >= FIFO_DEPTH);

    //=========================================================================
    // USB Connection State
    //=========================================================================

    always @(posedge host_clk or negedge host_rst_n) begin
        if (!host_rst_n)
            ft_wakeup_n <= 1'b1;  // Disconnected
        else
            ft_wakeup_n <= ~usb_connect;  // Active low when connected
    end

    //=========================================================================
    // Data Bus Tristate Control
    //=========================================================================

    // FT601 drives bus when OE is asserted and we have data
    reg        ft_drive_bus;
    reg [31:0] ft_data_out;
    reg [3:0]  ft_be_out;

    assign ft_data = ft_drive_bus ? ft_data_out : 32'bz;
    assign ft_be   = ft_drive_bus ? ft_be_out   : 4'bz;

    //=========================================================================
    // RX Path: Host TX -> Device FIFO -> FPGA
    //=========================================================================

    // Write to RX FIFO from testbench (host_clk domain)
    assign host_tx_ready = ~rx_full && host_rst_n;

    always @(posedge host_clk or negedge host_rst_n) begin
        if (!host_rst_n) begin
            rx_wr_ptr <= 0;
        end else if (host_tx_valid && host_tx_ready) begin
            rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= {host_tx_be, host_tx_data};
            rx_wr_ptr <= rx_wr_ptr + 1;
        end
    end

    // Read from RX FIFO to FPGA (ft_clk domain)
    reg ft_oe_n_d;
    reg ft_rd_n_d;
    reg [1:0] turnaround_cnt;

    always @(posedge ft_clk or negedge host_rst_n) begin
        if (!host_rst_n) begin
            ft_rxf_n      <= 1'b1;
            ft_drive_bus  <= 1'b0;
            ft_data_out   <= 32'h0;
            ft_be_out     <= 4'h0;
            rx_rd_ptr     <= 0;
            ft_oe_n_d     <= 1'b1;
            ft_rd_n_d     <= 1'b1;
            turnaround_cnt <= 0;
        end else begin
            ft_oe_n_d <= ft_oe_n;
            ft_rd_n_d <= ft_rd_n;

            // RXF# indicates data available (active low)
            ft_rxf_n <= rx_empty || usb_suspend || ~usb_connect;

            // Bus turnaround handling
            if (ft_oe_n && !ft_oe_n_d) begin
                // OE just deasserted - start turnaround
                turnaround_cnt <= TURNAROUND_CYC;
                ft_drive_bus <= 1'b0;
            end else if (turnaround_cnt > 0) begin
                turnaround_cnt <= turnaround_cnt - 1;
            end

            // Drive bus when OE asserted and turnaround complete
            if (!ft_oe_n && !ft_oe_n_d && turnaround_cnt == 0) begin
                ft_drive_bus <= 1'b1;
                // Present data from FIFO
                if (!rx_empty) begin
                    ft_data_out <= rx_fifo[rx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]][31:0];
                    ft_be_out   <= rx_fifo[rx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]][35:32];
                end
            end

            // Advance FIFO on read strobe
            if (!ft_rd_n && !ft_rd_n_d && !rx_empty && ft_drive_bus) begin
                rx_rd_ptr <= rx_rd_ptr + 1;
                // Present next data
                if (rx_rd_ptr + 1 < rx_wr_ptr) begin
                    ft_data_out <= rx_fifo[(rx_rd_ptr + 1)[$clog2(FIFO_DEPTH)-1:0]][31:0];
                    ft_be_out   <= rx_fifo[(rx_rd_ptr + 1)[$clog2(FIFO_DEPTH)-1:0]][35:32];
                end
            end
        end
    end

    //=========================================================================
    // TX Path: FPGA -> Device FIFO -> Host RX
    //=========================================================================

    // Write to TX FIFO from FPGA (ft_clk domain)
    reg ft_wr_n_d;

    always @(posedge ft_clk or negedge host_rst_n) begin
        if (!host_rst_n) begin
            ft_txe_n  <= 1'b1;
            tx_wr_ptr <= 0;
            ft_wr_n_d <= 1'b1;
        end else begin
            ft_wr_n_d <= ft_wr_n;

            // TXE# indicates space available (active low)
            ft_txe_n <= tx_full || usb_suspend || ~usb_connect;

            // Capture data on write strobe falling edge
            if (!ft_wr_n && ft_wr_n_d && !tx_full && !ft_oe_n) begin
                // FPGA is driving bus (OE should be deasserted for writes)
                // Actually FT601 samples on WR rising edge, but we sample on falling
            end

            // Capture data on write strobe rising edge (FT601 behavior)
            if (ft_wr_n && !ft_wr_n_d && !tx_full) begin
                tx_fifo[tx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= {ft_be, ft_data};
                tx_wr_ptr <= tx_wr_ptr + 1;
            end
        end
    end

    // Read from TX FIFO to testbench (host_clk domain)
    reg [$clog2(FIFO_DEPTH):0] tx_rd_ptr_sync1, tx_rd_ptr_sync2;
    reg [$clog2(FIFO_DEPTH):0] tx_rd_ptr_host;

    // Synchronize write pointer to host clock domain
    always @(posedge host_clk or negedge host_rst_n) begin
        if (!host_rst_n) begin
            tx_rd_ptr_sync1 <= 0;
            tx_rd_ptr_sync2 <= 0;
        end else begin
            tx_rd_ptr_sync1 <= tx_wr_ptr;
            tx_rd_ptr_sync2 <= tx_rd_ptr_sync1;
        end
    end

    wire host_tx_fifo_empty = (tx_rd_ptr_host == tx_rd_ptr_sync2);

    assign host_rx_valid = ~host_tx_fifo_empty;
    assign host_rx_data  = tx_fifo[tx_rd_ptr_host[$clog2(FIFO_DEPTH)-1:0]][31:0];
    assign host_rx_be    = tx_fifo[tx_rd_ptr_host[$clog2(FIFO_DEPTH)-1:0]][35:32];

    always @(posedge host_clk or negedge host_rst_n) begin
        if (!host_rst_n) begin
            tx_rd_ptr_host <= 0;
            tx_rd_ptr <= 0;
        end else if (host_rx_valid && host_rx_ready) begin
            tx_rd_ptr_host <= tx_rd_ptr_host + 1;
            tx_rd_ptr <= tx_rd_ptr_host + 1;
        end
    end

    //=========================================================================
    // Debug/Monitoring
    //=========================================================================

    // Useful for waveform viewing
    wire [15:0] dbg_rx_count = rx_count;
    wire [15:0] dbg_tx_count = tx_count;
    wire dbg_usb_connected = ~ft_wakeup_n;

    // Assertions for protocol checking
    `ifdef SIMULATION
    always @(posedge ft_clk) begin
        // Check: OE and WR should not be asserted simultaneously
        if (!ft_oe_n && !ft_wr_n) begin
            $display("ERROR: FT601 protocol violation - OE# and WR# both low");
        end

        // Check: RD should only be asserted when OE is asserted
        if (!ft_rd_n && ft_oe_n) begin
            $display("WARNING: FT601 - RD# asserted without OE#");
        end
    end
    `endif

endmodule
