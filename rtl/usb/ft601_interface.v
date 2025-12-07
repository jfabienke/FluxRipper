//-----------------------------------------------------------------------------
// ft601_interface.v
// FT601 USB 3.0 to 32-bit FIFO Bridge Interface Controller
//
// Created: 2025-12-05 07:55
// Updated: 2025-12-05 18:30 - Added personality mux integration support
//
// This module interfaces with the FTDI FT601Q-B USB 3.0 FIFO bridge chip,
// providing clock domain crossing and endpoint routing for the FluxRipper
// USB personality system.
//
// FT601 operates at 100 MHz with a 32-bit synchronous FIFO interface.
// This module handles:
//   - FIFO read/write state machine
//   - Clock domain crossing to system clock
//   - Endpoint channel demultiplexing
//   - Flow control and buffering
//   - USB composite device interface tracking (MSC + Raw Mode)
//-----------------------------------------------------------------------------

module ft601_interface #(
    parameter SYS_CLK_FREQ   = 100_000_000,  // System clock frequency
    parameter FIFO_DEPTH     = 512,           // CDC FIFO depth (words)
    parameter NUM_ENDPOINTS  = 4              // Number of endpoints (1-4)
)(
    // System clock domain
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // FT601 FIFO interface (active low, directly to chip)
    input  wire        ft_clk,               // 100 MHz from FT601
    inout  wire [31:0] ft_data,              // Bidirectional data bus
    inout  wire [3:0]  ft_be,                // Byte enables
    input  wire        ft_rxf_n,             // RX FIFO not empty (data available)
    input  wire        ft_txe_n,             // TX FIFO not full (can write)
    output reg         ft_rd_n,              // Read strobe (active low)
    output reg         ft_wr_n,              // Write strobe (active low)
    output reg         ft_oe_n,              // Output enable (active low)
    output wire        ft_siwu_n,            // Send immediate / wake up
    input  wire        ft_wakeup_n,          // Wakeup signal from FT601

    // Endpoint 0 - Control (bidirectional)
    output wire [31:0] ep0_rx_data,
    output wire        ep0_rx_valid,
    input  wire        ep0_rx_ready,
    input  wire [31:0] ep0_tx_data,
    input  wire        ep0_tx_valid,
    output wire        ep0_tx_ready,

    // Endpoint 1 - Bulk OUT (commands from host)
    output wire [31:0] ep1_rx_data,
    output wire        ep1_rx_valid,
    input  wire        ep1_rx_ready,

    // Endpoint 2 - Bulk IN (flux data to host)
    input  wire [31:0] ep2_tx_data,
    input  wire        ep2_tx_valid,
    output wire        ep2_tx_ready,

    // Endpoint 3 - Bulk IN (status/auxiliary)
    input  wire [31:0] ep3_tx_data,
    input  wire        ep3_tx_valid,
    output wire        ep3_tx_ready,

    // Status
    output wire        usb_connected,
    output wire        usb_suspended,
    output reg  [1:0]  active_endpoint,
    output reg  [31:0] rx_count,
    output reg  [31:0] tx_count,

    // Composite Device Interface Tracking (for MSC + Raw Mode)
    output reg  [1:0]  usb_interface_num,    // Current USB interface (0=MSC, 1=Raw)
    output reg         usb_interface_valid,  // Interface number is valid
    output wire [8:0]  rx_fifo_level,        // RX FIFO fill level
    output wire [8:0]  tx_fifo_level,        // TX FIFO fill level

    // Personality Mux Integration
    // These simplified data buses route through usb_personality_mux.v
    // to the appropriate protocol handler (GW, HxC, KF, Native, MSC)
    input  wire [2:0]  personality_sel,      // Current personality selection
    input  wire        personality_valid,    // Personality is active

    // Unified RX path (from host) - mirrors EP1
    output wire [31:0] unified_rx_data,
    output wire        unified_rx_valid,
    input  wire        unified_rx_ready,

    // Unified TX path (to host) - priority muxed into EP2
    input  wire [31:0] unified_tx_data,
    input  wire        unified_tx_valid,
    output wire        unified_tx_ready
);

    //=========================================================================
    // FT601 Channel Encoding
    //=========================================================================
    // FT601 uses the upper bits of ft_be to indicate endpoint/channel
    // Channel encoding in BE[3:2]:
    //   00 = Channel 0 (EP0 Control)
    //   01 = Channel 1 (EP1 Bulk OUT)
    //   10 = Channel 2 (EP2 Bulk IN)
    //   11 = Channel 3 (EP3 Bulk IN)

    localparam CH_EP0 = 2'b00;
    localparam CH_EP1 = 2'b01;
    localparam CH_EP2 = 2'b10;
    localparam CH_EP3 = 2'b11;

    //=========================================================================
    // FT601 Clock Domain Signals
    //=========================================================================

    // FIFO state machine
    localparam FSM_IDLE      = 3'd0;
    localparam FSM_RX_OE     = 3'd1;
    localparam FSM_RX_READ   = 3'd2;
    localparam FSM_RX_WAIT   = 3'd3;
    localparam FSM_TX_SETUP  = 3'd4;
    localparam FSM_TX_WRITE  = 3'd5;
    localparam FSM_TX_WAIT   = 3'd6;

    reg [2:0]  ft_state;
    reg [2:0]  ft_state_next;

    // Data direction control
    reg        ft_data_oe;           // 1 = output (TX), 0 = input (RX)
    reg [31:0] ft_data_out;
    reg [3:0]  ft_be_out;
    wire [31:0] ft_data_in;
    wire [3:0]  ft_be_in;

    // Tristate control
    assign ft_data = ft_data_oe ? ft_data_out : 32'bz;
    assign ft_be   = ft_data_oe ? ft_be_out   : 4'bz;
    assign ft_data_in = ft_data;
    assign ft_be_in   = ft_be;

    // Wake-up control (active low, normally high)
    assign ft_siwu_n = 1'b1;  // Not using send-immediate for now

    // Status from FT601
    assign usb_connected = ~ft_wakeup_n;  // Wakeup low = USB connected
    assign usb_suspended = 1'b0;          // TODO: Detect suspend state

    //=========================================================================
    // CDC FIFOs (FT601 clock domain -> System clock domain)
    //=========================================================================

    // RX CDC FIFO (FT601 -> System)
    wire        rx_fifo_wr_en;
    wire [35:0] rx_fifo_wr_data;  // [35:34] = channel, [33:32] = BE, [31:0] = data
    wire        rx_fifo_full;
    wire        rx_fifo_rd_en;
    wire [35:0] rx_fifo_rd_data;
    wire        rx_fifo_empty;
    wire        rx_fifo_valid;

    // TX CDC FIFO (System -> FT601)
    wire        tx_fifo_wr_en;
    wire [35:0] tx_fifo_wr_data;
    wire        tx_fifo_full;
    wire        tx_fifo_rd_en;
    wire [35:0] tx_fifo_rd_data;
    wire        tx_fifo_empty;

    // RX FIFO write (FT601 clock domain)
    reg         rx_fifo_wr_en_r;
    reg  [35:0] rx_fifo_wr_data_r;
    assign rx_fifo_wr_en   = rx_fifo_wr_en_r;
    assign rx_fifo_wr_data = rx_fifo_wr_data_r;

    // Asynchronous CDC FIFO for RX path
    async_fifo #(
        .DATA_WIDTH(36),
        .ADDR_WIDTH($clog2(FIFO_DEPTH))
    ) u_rx_cdc_fifo (
        // Write side (FT601 clock)
        .wr_clk   (ft_clk),
        .wr_rst_n (sys_rst_n),
        .wr_en    (rx_fifo_wr_en),
        .wr_data  (rx_fifo_wr_data),
        .wr_full  (rx_fifo_full),
        // Read side (System clock)
        .rd_clk   (sys_clk),
        .rd_rst_n (sys_rst_n),
        .rd_en    (rx_fifo_rd_en),
        .rd_data  (rx_fifo_rd_data),
        .rd_empty (rx_fifo_empty),
        .rd_valid (rx_fifo_valid)
    );

    // Asynchronous CDC FIFO for TX path
    async_fifo #(
        .DATA_WIDTH(36),
        .ADDR_WIDTH($clog2(FIFO_DEPTH))
    ) u_tx_cdc_fifo (
        // Write side (System clock)
        .wr_clk   (sys_clk),
        .wr_rst_n (sys_rst_n),
        .wr_en    (tx_fifo_wr_en),
        .wr_data  (tx_fifo_wr_data),
        .wr_full  (tx_fifo_full),
        // Read side (FT601 clock)
        .rd_clk   (ft_clk),
        .rd_rst_n (sys_rst_n),
        .rd_en    (tx_fifo_rd_en),
        .rd_data  (tx_fifo_rd_data),
        .rd_empty (tx_fifo_empty),
        .rd_valid ()  // Not used
    );

    //=========================================================================
    // FT601 Clock Domain State Machine
    //=========================================================================

    // Synchronize reset to FT601 clock domain
    reg [2:0] ft_rst_sync;
    wire      ft_rst_n = ft_rst_sync[2];

    always @(posedge ft_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            ft_rst_sync <= 3'b000;
        else
            ft_rst_sync <= {ft_rst_sync[1:0], 1'b1};
    end

    // RX has priority over TX (can always receive data from host)
    wire rx_available = ~ft_rxf_n && ~rx_fifo_full;
    wire tx_available = ~ft_txe_n && ~tx_fifo_empty;

    // State machine
    always @(posedge ft_clk or negedge ft_rst_n) begin
        if (!ft_rst_n)
            ft_state <= FSM_IDLE;
        else
            ft_state <= ft_state_next;
    end

    always @(*) begin
        ft_state_next = ft_state;

        case (ft_state)
            FSM_IDLE: begin
                if (rx_available)
                    ft_state_next = FSM_RX_OE;
                else if (tx_available)
                    ft_state_next = FSM_TX_SETUP;
            end

            FSM_RX_OE: begin
                // Assert OE, wait one cycle for turnaround
                ft_state_next = FSM_RX_READ;
            end

            FSM_RX_READ: begin
                // Reading data
                if (ft_rxf_n || rx_fifo_full)
                    ft_state_next = FSM_RX_WAIT;
            end

            FSM_RX_WAIT: begin
                // Deassert OE, turnaround
                ft_state_next = FSM_IDLE;
            end

            FSM_TX_SETUP: begin
                // Setup data on bus
                ft_state_next = FSM_TX_WRITE;
            end

            FSM_TX_WRITE: begin
                // Writing data
                if (ft_txe_n || tx_fifo_empty)
                    ft_state_next = FSM_TX_WAIT;
            end

            FSM_TX_WAIT: begin
                // Complete write cycle
                ft_state_next = FSM_IDLE;
            end

            default: ft_state_next = FSM_IDLE;
        endcase
    end

    // Control signals
    always @(posedge ft_clk or negedge ft_rst_n) begin
        if (!ft_rst_n) begin
            ft_rd_n      <= 1'b1;
            ft_wr_n      <= 1'b1;
            ft_oe_n      <= 1'b1;
            ft_data_oe   <= 1'b0;
            ft_data_out  <= 32'h0;
            ft_be_out    <= 4'h0;
            rx_fifo_wr_en_r   <= 1'b0;
            rx_fifo_wr_data_r <= 36'h0;
        end else begin
            // Default
            rx_fifo_wr_en_r <= 1'b0;

            case (ft_state)
                FSM_IDLE: begin
                    ft_rd_n    <= 1'b1;
                    ft_wr_n    <= 1'b1;
                    ft_oe_n    <= 1'b1;
                    ft_data_oe <= 1'b0;
                end

                FSM_RX_OE: begin
                    ft_oe_n    <= 1'b0;  // Enable FT601 output drivers
                    ft_data_oe <= 1'b0;  // FPGA inputs
                end

                FSM_RX_READ: begin
                    ft_rd_n <= 1'b0;     // Assert read strobe

                    // Capture data into RX FIFO
                    if (~ft_rxf_n && ~rx_fifo_full) begin
                        rx_fifo_wr_en_r   <= 1'b1;
                        rx_fifo_wr_data_r <= {ft_be_in[3:2], ft_be_in[1:0], ft_data_in};
                    end
                end

                FSM_RX_WAIT: begin
                    ft_rd_n <= 1'b1;
                    ft_oe_n <= 1'b1;
                end

                FSM_TX_SETUP: begin
                    ft_data_oe  <= 1'b1;  // FPGA drives bus
                    ft_data_out <= tx_fifo_rd_data[31:0];
                    ft_be_out   <= {tx_fifo_rd_data[35:34], tx_fifo_rd_data[33:32]};
                end

                FSM_TX_WRITE: begin
                    ft_wr_n <= 1'b0;      // Assert write strobe

                    // Update data for next word
                    if (~ft_txe_n && ~tx_fifo_empty) begin
                        ft_data_out <= tx_fifo_rd_data[31:0];
                        ft_be_out   <= {tx_fifo_rd_data[35:34], tx_fifo_rd_data[33:32]};
                    end
                end

                FSM_TX_WAIT: begin
                    ft_wr_n    <= 1'b1;
                    ft_data_oe <= 1'b0;
                end
            endcase
        end
    end

    // TX FIFO read enable (consume data when writing)
    assign tx_fifo_rd_en = (ft_state == FSM_TX_WRITE) && ~ft_txe_n && ~tx_fifo_empty;

    //=========================================================================
    // System Clock Domain - Endpoint Demultiplexing
    //=========================================================================

    // RX FIFO read and demux
    wire [1:0]  rx_channel = rx_fifo_rd_data[35:34];
    wire [1:0]  rx_be      = rx_fifo_rd_data[33:32];
    wire [31:0] rx_data    = rx_fifo_rd_data[31:0];

    // Per-endpoint ready signals (active when endpoint can accept data)
    wire ep0_can_accept = ep0_rx_ready;
    wire ep1_can_accept = ep1_rx_ready;

    // Read from RX FIFO when target endpoint is ready
    wire rx_ep0_sel = (rx_channel == CH_EP0) && ep0_can_accept;
    wire rx_ep1_sel = (rx_channel == CH_EP1) && ep1_can_accept;

    assign rx_fifo_rd_en = ~rx_fifo_empty && (rx_ep0_sel || rx_ep1_sel);

    // Output to endpoints
    assign ep0_rx_data  = rx_data;
    assign ep0_rx_valid = rx_fifo_valid && (rx_channel == CH_EP0);

    assign ep1_rx_data  = rx_data;
    assign ep1_rx_valid = rx_fifo_valid && (rx_channel == CH_EP1);

    //=========================================================================
    // System Clock Domain - TX Endpoint Multiplexing
    //=========================================================================

    // Round-robin or priority-based TX multiplexer
    reg [1:0] tx_endpoint_sel;
    reg [1:0] tx_endpoint_sel_next;

    // TX data selection
    reg [31:0] tx_mux_data;
    reg [1:0]  tx_mux_channel;
    reg        tx_mux_valid;

    // Priority: EP0 > EP2 > EP3 (EP0 for control, EP2 for flux data)
    always @(*) begin
        tx_mux_valid   = 1'b0;
        tx_mux_data    = 32'h0;
        tx_mux_channel = CH_EP0;

        if (ep0_tx_valid && ~tx_fifo_full) begin
            tx_mux_valid   = 1'b1;
            tx_mux_data    = ep0_tx_data;
            tx_mux_channel = CH_EP0;
        end else if (ep2_tx_valid && ~tx_fifo_full) begin
            tx_mux_valid   = 1'b1;
            tx_mux_data    = ep2_tx_data;
            tx_mux_channel = CH_EP2;
        end else if (ep3_tx_valid && ~tx_fifo_full) begin
            tx_mux_valid   = 1'b1;
            tx_mux_data    = ep3_tx_data;
            tx_mux_channel = CH_EP3;
        end
    end

    // TX FIFO write
    assign tx_fifo_wr_en   = tx_mux_valid;
    assign tx_fifo_wr_data = {tx_mux_channel, 2'b11, tx_mux_data};  // BE = all bytes valid

    // Ready signals back to endpoints
    assign ep0_tx_ready = ~tx_fifo_full && (tx_mux_channel == CH_EP0 || ~ep0_tx_valid);
    assign ep2_tx_ready = ~tx_fifo_full && (tx_mux_channel == CH_EP2 || (~ep0_tx_valid && ~ep2_tx_valid));
    assign ep3_tx_ready = ~tx_fifo_full && (tx_mux_channel == CH_EP3 || (~ep0_tx_valid && ~ep2_tx_valid && ~ep3_tx_valid));

    //=========================================================================
    // Statistics Counters (System Clock Domain)
    //=========================================================================

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_count <= 32'h0;
            tx_count <= 32'h0;
            active_endpoint <= 2'b00;
        end else begin
            // Count received words
            if (rx_fifo_rd_en)
                rx_count <= rx_count + 1'b1;

            // Count transmitted words
            if (tx_fifo_wr_en)
                tx_count <= tx_count + 1'b1;

            // Track active endpoint
            if (rx_fifo_valid)
                active_endpoint <= rx_channel;
            else if (tx_mux_valid)
                active_endpoint <= tx_mux_channel;
        end
    end

    //=========================================================================
    // FIFO Level Tracking (for flow control visibility)
    //=========================================================================

    // FIFO level counters (approximate due to CDC, but useful for monitoring)
    reg [8:0] rx_level_count;
    reg [8:0] tx_level_count;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_level_count <= 9'h0;
            tx_level_count <= 9'h0;
        end else begin
            // RX level (increments lag due to CDC, but useful approximation)
            if (rx_fifo_rd_en && !rx_fifo_empty)
                rx_level_count <= (rx_level_count > 0) ? rx_level_count - 1'b1 : 9'h0;

            // TX level
            if (tx_fifo_wr_en && !tx_fifo_full)
                tx_level_count <= tx_level_count + 1'b1;
            else if (tx_fifo_rd_en && tx_level_count > 0)
                tx_level_count <= tx_level_count - 1'b1;
        end
    end

    assign rx_fifo_level = rx_level_count;
    assign tx_fifo_level = tx_level_count;

    //=========================================================================
    // USB Composite Device Interface Tracking
    //=========================================================================
    // Track which USB interface is currently active based on endpoint usage.
    // For composite device:
    //   Interface 0 (MSC):  Uses EP1 OUT for CBW, EP2 IN for CSW/data
    //   Interface 1 (Raw):  Uses EP1 OUT for commands, EP3 IN for flux/diag
    //
    // The interface is determined by which IN endpoint receives data:
    //   EP2 activity -> Interface 0 (MSC)
    //   EP3 activity -> Interface 1 (Raw)

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            usb_interface_num <= 2'b00;
            usb_interface_valid <= 1'b0;
        end else begin
            // Determine interface from TX endpoint usage
            if (ep2_tx_valid && ep2_tx_ready) begin
                usb_interface_num <= 2'b00;   // MSC uses EP2
                usb_interface_valid <= 1'b1;
            end else if (ep3_tx_valid && ep3_tx_ready) begin
                usb_interface_num <= 2'b01;   // Raw uses EP3
                usb_interface_valid <= 1'b1;
            end
            // Interface remains valid until USB disconnect
            if (!usb_connected)
                usb_interface_valid <= 1'b0;
        end
    end

    //=========================================================================
    // Unified Data Paths for Personality Mux Integration
    //=========================================================================
    // The unified paths provide a simplified interface for the personality mux.
    // RX: Commands from host arrive on EP1, routed to active personality
    // TX: Data to host from active personality, sent via EP2

    // Unified RX mirrors EP1 (with flow control from personality mux)
    assign unified_rx_data  = ep1_rx_data;
    assign unified_rx_valid = ep1_rx_valid && personality_valid;

    // Unified TX feeds into EP2 path
    // When personality_valid, unified_tx overrides direct ep2 connection
    assign unified_tx_ready = ep2_tx_ready && personality_valid;

    // Note: The actual connection to ep2_tx_data/valid is handled in usb_top.v
    // which instantiates both ft601_interface and usb_personality_mux and
    // wires the unified_tx signals to ep2 when personality mode is active.

endmodule

//=============================================================================
// Asynchronous CDC FIFO
//=============================================================================

module async_fifo #(
    parameter DATA_WIDTH = 36,
    parameter ADDR_WIDTH = 9     // 512 depth
)(
    // Write clock domain
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_full,

    // Read clock domain
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_empty,
    output reg                   rd_valid
);

    // Memory
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // Gray-coded pointers
    reg [ADDR_WIDTH:0] wr_ptr_gray;
    reg [ADDR_WIDTH:0] rd_ptr_gray;
    reg [ADDR_WIDTH:0] wr_ptr_bin;
    reg [ADDR_WIDTH:0] rd_ptr_bin;

    // Synchronized pointers
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // Binary to Gray conversion
    function [ADDR_WIDTH:0] bin2gray;
        input [ADDR_WIDTH:0] bin;
        bin2gray = bin ^ (bin >> 1);
    endfunction

    // Gray to Binary conversion
    function [ADDR_WIDTH:0] gray2bin;
        input [ADDR_WIDTH:0] gray;
        integer i;
        begin
            gray2bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
            for (i = ADDR_WIDTH-1; i >= 0; i = i - 1)
                gray2bin[i] = gray2bin[i+1] ^ gray[i];
        end
    endfunction

    //-------------------------------------------------------------------------
    // Write Clock Domain
    //-------------------------------------------------------------------------

    // Synchronize read pointer to write domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Write pointer
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else if (wr_en && !wr_full) begin
            wr_ptr_bin  <= wr_ptr_bin + 1;
            wr_ptr_gray <= bin2gray(wr_ptr_bin + 1);
        end
    end

    // Write to memory
    always @(posedge wr_clk) begin
        if (wr_en && !wr_full)
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // Full flag
    wire [ADDR_WIDTH:0] wr_ptr_gray_next = bin2gray(wr_ptr_bin + 1);
    assign wr_full = (wr_ptr_gray_next == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
                                            rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});

    //-------------------------------------------------------------------------
    // Read Clock Domain
    //-------------------------------------------------------------------------

    // Synchronize write pointer to read domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // Read pointer
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
        end else if (rd_en && !rd_empty) begin
            rd_ptr_bin  <= rd_ptr_bin + 1;
            rd_ptr_gray <= bin2gray(rd_ptr_bin + 1);
        end
    end

    // Read from memory
    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

    // Empty flag
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

    // Valid flag (one cycle after read)
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            rd_valid <= 1'b0;
        else
            rd_valid <= rd_en && !rd_empty;
    end

endmodule
