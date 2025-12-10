//-----------------------------------------------------------------------------
// ulpi_phy.v
// ULPI PHY Interface for USB 2.0 High-Speed
//
// Created: 2025-12-06 10:59
//
// Interfaces with USB3320 ULPI PHY chip for USB 2.0 HS/FS operation.
// Handles ULPI bus protocol, register access, and packet TX/RX.
//
// ULPI Specification: https://www.ulpi.org/
//
// Clocking: All logic runs on 60 MHz clock provided by PHY (ulpi_clk)
//-----------------------------------------------------------------------------

module ulpi_phy (
    // ULPI PHY signals
    input  wire        ulpi_clk,       // 60 MHz from PHY
    input  wire        ulpi_dir,       // PHY driving bus when high
    input  wire        ulpi_nxt,       // PHY ready for next byte
    output reg         ulpi_stp,       // Link stop signal
    inout  wire [7:0]  ulpi_data,      // Bidirectional data bus
    output reg         ulpi_rst_n,     // PHY reset (directly driven)

    // System
    input  wire        rst_n,          // System reset

    // PHY Status
    output reg         phy_ready,      // PHY initialized and ready
    output reg  [1:0]  line_state,     // USB line state (SE0, J, K, SE1)
    output reg         vbus_valid,     // VBUS detected
    output reg         session_valid,  // Session valid (connected)
    output reg         rx_active,      // Receiving packet
    output reg         rx_error,       // Receive error detected

    // TX Interface (to PHY)
    input  wire [7:0]  tx_data,        // TX data byte
    input  wire        tx_valid,       // TX data valid
    output reg         tx_ready,       // Ready for TX data
    input  wire        tx_last,        // Last byte of packet

    // RX Interface (from PHY)
    output reg  [7:0]  rx_data,        // RX data byte
    output reg         rx_valid,       // RX data valid
    output reg         rx_last,        // Last byte of packet (EOP)

    // USB Events
    output reg         sof_pulse,      // Start of Frame received
    output reg  [10:0] frame_number,   // Current USB frame number

    // Register Interface
    input  wire [5:0]  reg_addr,       // Register address
    input  wire [7:0]  reg_wdata,      // Register write data
    input  wire        reg_write,      // Write strobe
    input  wire        reg_read,       // Read strobe
    output reg  [7:0]  reg_rdata,      // Register read data
    output reg         reg_done        // Register operation complete
);

    //=========================================================================
    // ULPI Command Codes
    //=========================================================================

    // Transmit commands (FPGA to PHY, when DIR=0)
    localparam CMD_TX_NOOP       = 8'b00000000;  // Idle/NOP
    localparam CMD_TX_DATA       = 8'b01XXXXXX;  // TX data (6-bit PID in lower)
    localparam CMD_REG_WRITE     = 8'b10XXXXXX;  // Register write (6-bit addr)
    localparam CMD_REG_READ      = 8'b11XXXXXX;  // Register read (6-bit addr)

    // RX command codes (PHY to FPGA, when DIR=1)
    localparam RXCMD_LINE_STATE  = 2'b00;        // Line state in [1:0]
    localparam RXCMD_VBUS_STATE  = 2'b01;        // VBUS/session in [1:0]
    localparam RXCMD_RX_ACTIVE   = 2'b01;        // RX active (with specific bits)
    localparam RXCMD_RX_ERROR    = 2'b11;        // RX error

    //=========================================================================
    // ULPI Register Addresses (USB3320)
    //=========================================================================

    localparam REG_VID_LOW       = 6'h00;
    localparam REG_VID_HIGH      = 6'h01;
    localparam REG_PID_LOW       = 6'h02;
    localparam REG_PID_HIGH      = 6'h03;
    localparam REG_FUNC_CTRL     = 6'h04;
    localparam REG_IFACE_CTRL    = 6'h07;
    localparam REG_OTG_CTRL      = 6'h0A;
    localparam REG_USB_INT_EN    = 6'h0D;
    localparam REG_USB_INT_STAT  = 6'h13;
    localparam REG_SCRATCH       = 6'h16;

    // Function Control bits
    localparam FUNC_RESET        = 8'h20;  // Reset PHY
    localparam FUNC_SUSPENDM     = 8'h40;  // Not suspended
    localparam FUNC_OPMODE_HS    = 8'h00;  // High-speed operation
    localparam FUNC_OPMODE_FS    = 8'h08;  // Full-speed operation
    localparam FUNC_TERMSEL_HS   = 8'h00;  // HS termination
    localparam FUNC_TERMSEL_FS   = 8'h04;  // FS termination
    localparam FUNC_XCVR_HS      = 8'h00;  // HS transceiver
    localparam FUNC_XCVR_FS      = 8'h01;  // FS transceiver

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam ST_RESET          = 4'd0;
    localparam ST_WAIT_PHY       = 4'd1;
    localparam ST_INIT_FUNC      = 4'd2;
    localparam ST_INIT_WAIT      = 4'd3;
    localparam ST_IDLE           = 4'd4;
    localparam ST_REG_WRITE_CMD  = 4'd5;
    localparam ST_REG_WRITE_DATA = 4'd6;
    localparam ST_REG_WRITE_STP  = 4'd7;
    localparam ST_REG_READ_CMD   = 4'd8;
    localparam ST_REG_READ_TURN  = 4'd9;
    localparam ST_REG_READ_DATA  = 4'd10;
    localparam ST_TX_CMD         = 4'd11;
    localparam ST_TX_DATA        = 4'd12;
    localparam ST_TX_STOP        = 4'd13;
    localparam ST_RX_DATA        = 4'd14;

    reg [3:0] state;
    reg [3:0] next_state;

    //=========================================================================
    // ULPI Data Bus Control
    //=========================================================================

    reg  [7:0] data_out;
    reg        data_out_en;
    wire [7:0] data_in;

    // Bidirectional data bus
    assign ulpi_data = data_out_en ? data_out : 8'bz;
    assign data_in   = ulpi_data;

    //=========================================================================
    // Internal Registers
    //=========================================================================

    reg [15:0] reset_counter;
    reg [7:0]  rxcmd_reg;
    reg        dir_prev;
    reg [5:0]  pending_reg_addr;
    reg [7:0]  pending_reg_wdata;
    reg        pending_reg_write;
    reg        pending_reg_read;
    reg [7:0]  tx_pid;
    reg        in_rx_packet;

    //=========================================================================
    // PHY Reset Sequence
    //=========================================================================

    always @(posedge ulpi_clk or negedge rst_n) begin
        if (!rst_n) begin
            ulpi_rst_n    <= 1'b0;
            reset_counter <= 16'd0;
        end else begin
            if (reset_counter < 16'd6000) begin  // 100us at 60MHz
                ulpi_rst_n    <= 1'b0;
                reset_counter <= reset_counter + 1'b1;
            end else begin
                ulpi_rst_n <= 1'b1;
            end
        end
    end

    //=========================================================================
    // RX Command Decoder
    //=========================================================================

    // Capture RXCMD when DIR transitions high
    always @(posedge ulpi_clk or negedge rst_n) begin
        if (!rst_n) begin
            dir_prev      <= 1'b0;
            rxcmd_reg     <= 8'h00;
            line_state    <= 2'b00;
            vbus_valid    <= 1'b0;
            session_valid <= 1'b0;
            rx_active     <= 1'b0;
            rx_error      <= 1'b0;
        end else begin
            dir_prev <= ulpi_dir;

            // DIR went high - PHY is sending RXCMD
            if (ulpi_dir && !dir_prev) begin
                rxcmd_reg <= data_in;

                // Decode RXCMD
                case (data_in[5:4])
                    2'b00: begin
                        // Line state update
                        line_state <= data_in[1:0];
                        rx_active  <= data_in[2];
                    end
                    2'b01: begin
                        // VBUS state update
                        vbus_valid    <= data_in[0];
                        session_valid <= data_in[1];
                    end
                    2'b10: begin
                        // RX active with ID
                        rx_active <= 1'b1;
                    end
                    2'b11: begin
                        // RX error or host disconnect
                        if (data_in[1:0] == 2'b11)
                            rx_error <= 1'b1;
                        else
                            rx_error <= 1'b0;
                    end
                endcase
            end

            // Clear rx_active when DIR goes low (end of RX)
            if (!ulpi_dir && dir_prev) begin
                rx_active <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Main State Machine
    //=========================================================================

    always @(posedge ulpi_clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_RESET;
            phy_ready         <= 1'b0;
            data_out          <= 8'h00;
            data_out_en       <= 1'b0;
            ulpi_stp          <= 1'b0;
            tx_ready          <= 1'b0;
            rx_data           <= 8'h00;
            rx_valid          <= 1'b0;
            rx_last           <= 1'b0;
            reg_rdata         <= 8'h00;
            reg_done          <= 1'b0;
            pending_reg_addr  <= 6'h00;
            pending_reg_wdata <= 8'h00;
            pending_reg_write <= 1'b0;
            pending_reg_read  <= 1'b0;
            in_rx_packet      <= 1'b0;
            sof_pulse         <= 1'b0;
            frame_number      <= 11'd0;
        end else begin
            // Default outputs
            ulpi_stp  <= 1'b0;
            rx_valid  <= 1'b0;
            rx_last   <= 1'b0;
            reg_done  <= 1'b0;
            sof_pulse <= 1'b0;

            // Latch pending register operations
            if (reg_write && state == ST_IDLE) begin
                pending_reg_addr  <= reg_addr;
                pending_reg_wdata <= reg_wdata;
                pending_reg_write <= 1'b1;
            end
            if (reg_read && state == ST_IDLE) begin
                pending_reg_addr <= reg_addr;
                pending_reg_read <= 1'b1;
            end

            case (state)
                //-------------------------------------------------------------
                // Initialization
                //-------------------------------------------------------------
                ST_RESET: begin
                    data_out_en <= 1'b0;
                    phy_ready   <= 1'b0;
                    if (ulpi_rst_n)
                        state <= ST_WAIT_PHY;
                end

                ST_WAIT_PHY: begin
                    // Wait for PHY to be ready (DIR should be stable)
                    if (!ulpi_dir && reset_counter >= 16'd6000) begin
                        state <= ST_INIT_FUNC;
                    end
                end

                ST_INIT_FUNC: begin
                    // Write Function Control register for HS operation
                    data_out_en <= 1'b1;
                    data_out    <= {2'b10, REG_FUNC_CTRL};  // REG_WRITE command
                    if (ulpi_nxt)
                        state <= ST_INIT_WAIT;
                end

                ST_INIT_WAIT: begin
                    // Write data: HS mode, not suspended
                    data_out <= FUNC_SUSPENDM | FUNC_OPMODE_HS | FUNC_XCVR_HS;
                    if (ulpi_nxt) begin
                        ulpi_stp    <= 1'b1;
                        data_out_en <= 1'b0;
                        state       <= ST_IDLE;
                        phy_ready   <= 1'b1;
                    end
                end

                //-------------------------------------------------------------
                // Idle - Wait for commands or incoming data
                //-------------------------------------------------------------
                ST_IDLE: begin
                    data_out_en <= 1'b0;
                    tx_ready    <= 1'b1;

                    // PHY taking control of bus (incoming packet)
                    if (ulpi_dir) begin
                        state        <= ST_RX_DATA;
                        tx_ready     <= 1'b0;
                        in_rx_packet <= 1'b1;
                    end
                    // Register write request
                    else if (pending_reg_write) begin
                        state            <= ST_REG_WRITE_CMD;
                        tx_ready         <= 1'b0;
                        pending_reg_write <= 1'b0;
                    end
                    // Register read request
                    else if (pending_reg_read) begin
                        state           <= ST_REG_READ_CMD;
                        tx_ready        <= 1'b0;
                        pending_reg_read <= 1'b0;
                    end
                    // TX data request
                    else if (tx_valid) begin
                        state    <= ST_TX_CMD;
                        tx_ready <= 1'b0;
                        tx_pid   <= tx_data;
                    end
                end

                //-------------------------------------------------------------
                // Register Write
                //-------------------------------------------------------------
                ST_REG_WRITE_CMD: begin
                    data_out_en <= 1'b1;
                    data_out    <= {2'b10, pending_reg_addr};  // REG_WRITE | addr
                    if (ulpi_nxt)
                        state <= ST_REG_WRITE_DATA;
                end

                ST_REG_WRITE_DATA: begin
                    data_out <= pending_reg_wdata;
                    if (ulpi_nxt) begin
                        state <= ST_REG_WRITE_STP;
                    end
                end

                ST_REG_WRITE_STP: begin
                    ulpi_stp    <= 1'b1;
                    data_out_en <= 1'b0;
                    reg_done    <= 1'b1;
                    state       <= ST_IDLE;
                end

                //-------------------------------------------------------------
                // Register Read
                //-------------------------------------------------------------
                ST_REG_READ_CMD: begin
                    data_out_en <= 1'b1;
                    data_out    <= {2'b11, pending_reg_addr};  // REG_READ | addr
                    if (ulpi_nxt)
                        state <= ST_REG_READ_TURN;
                end

                ST_REG_READ_TURN: begin
                    // Turnaround cycle - release bus
                    data_out_en <= 1'b0;
                    if (ulpi_dir)
                        state <= ST_REG_READ_DATA;
                end

                ST_REG_READ_DATA: begin
                    if (ulpi_nxt) begin
                        reg_rdata <= data_in;
                        reg_done  <= 1'b1;
                        state     <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                // TX Data
                //-------------------------------------------------------------
                ST_TX_CMD: begin
                    data_out_en <= 1'b1;
                    // TXCMD with PID
                    data_out <= {2'b01, tx_pid[5:0]};
                    if (ulpi_nxt) begin
                        state    <= ST_TX_DATA;
                        tx_ready <= 1'b1;
                    end
                end

                ST_TX_DATA: begin
                    if (ulpi_dir) begin
                        // PHY needs to send (abort TX)
                        data_out_en <= 1'b0;
                        state       <= ST_RX_DATA;
                        tx_ready    <= 1'b0;
                    end else if (tx_valid && ulpi_nxt) begin
                        data_out <= tx_data;
                        if (tx_last) begin
                            state    <= ST_TX_STOP;
                            tx_ready <= 1'b0;
                        end
                    end
                end

                ST_TX_STOP: begin
                    ulpi_stp    <= 1'b1;
                    data_out_en <= 1'b0;
                    state       <= ST_IDLE;
                end

                //-------------------------------------------------------------
                // RX Data
                //-------------------------------------------------------------
                ST_RX_DATA: begin
                    data_out_en <= 1'b0;

                    if (ulpi_dir) begin
                        if (ulpi_nxt) begin
                            // Valid RX data byte
                            rx_data  <= data_in;
                            rx_valid <= 1'b1;

                            // Check for SOF token (PID = 0x05, or 0xA5 with check)
                            if (in_rx_packet && data_in[3:0] == 4'b0101) begin
                                // This might be SOF - next bytes are frame number
                            end
                        end
                    end else begin
                        // DIR low = end of packet
                        rx_last      <= 1'b1;
                        in_rx_packet <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end

                default: state <= ST_RESET;
            endcase
        end
    end

endmodule
