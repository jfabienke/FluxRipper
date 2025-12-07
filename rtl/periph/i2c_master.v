//-----------------------------------------------------------------------------
// AXI-Lite I2C Master Controller
//
// Simple I2C master for accessing power monitoring ICs (INA3221).
// Supports standard mode (100 kHz) and fast mode (400 kHz).
//
// Features:
//   - AXI4-Lite slave interface
//   - 7-bit addressing
//   - Single-byte and multi-byte transfers
//   - Clock stretching support
//   - Repeated start support
//
// Target: AMD Spartan UltraScale+ SCU35
// Created: 2025-12-04 10:30
//-----------------------------------------------------------------------------

module i2c_master (
    input  wire        clk,               // System clock (100 MHz)
    input  wire        reset,

    //-------------------------------------------------------------------------
    // AXI4-Lite Slave Interface
    //-------------------------------------------------------------------------
    input  wire [5:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [5:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    //-------------------------------------------------------------------------
    // I2C Interface
    //-------------------------------------------------------------------------
    inout  wire        i2c_sda,           // Bidirectional data
    inout  wire        i2c_scl,           // Bidirectional clock

    //-------------------------------------------------------------------------
    // Interrupt
    //-------------------------------------------------------------------------
    output reg         irq                // Transfer complete interrupt
);

    //-------------------------------------------------------------------------
    // Register Addresses
    //-------------------------------------------------------------------------
    localparam [5:0]
        REG_CTRL      = 6'h00,    // Control register
        REG_STATUS    = 6'h04,    // Status register
        REG_ADDR      = 6'h08,    // Slave address
        REG_TX_DATA   = 6'h0C,    // Transmit data
        REG_RX_DATA   = 6'h10,    // Receive data
        REG_PRESCALE  = 6'h14,    // Clock prescaler
        REG_CMD       = 6'h18;    // Command register

    //-------------------------------------------------------------------------
    // Control Register Bits
    //-------------------------------------------------------------------------
    localparam
        CTRL_ENABLE    = 0,       // I2C enable
        CTRL_IE        = 1,       // Interrupt enable
        CTRL_FAST_MODE = 2;       // 400 kHz mode

    //-------------------------------------------------------------------------
    // Status Register Bits
    //-------------------------------------------------------------------------
    localparam
        STAT_BUSY      = 0,       // Transfer in progress
        STAT_ACK       = 1,       // Last ACK received
        STAT_ERROR     = 2,       // Error occurred
        STAT_TX_EMPTY  = 3,       // TX buffer empty
        STAT_RX_VALID  = 4,       // RX data valid
        STAT_ARB_LOST  = 5;       // Arbitration lost

    //-------------------------------------------------------------------------
    // Command Register Values
    //-------------------------------------------------------------------------
    localparam [2:0]
        CMD_NOP       = 3'd0,     // No operation
        CMD_START     = 3'd1,     // Generate START
        CMD_STOP      = 3'd2,     // Generate STOP
        CMD_WRITE     = 3'd3,     // Write byte
        CMD_READ_ACK  = 3'd4,     // Read byte, send ACK
        CMD_READ_NACK = 3'd5;     // Read byte, send NACK

    //-------------------------------------------------------------------------
    // Registers
    //-------------------------------------------------------------------------
    reg [7:0]  ctrl_reg;
    reg [7:0]  status_reg;
    reg [6:0]  addr_reg;
    reg [7:0]  tx_data_reg;
    reg [7:0]  rx_data_reg;
    reg [15:0] prescale_reg;
    reg [2:0]  cmd_reg;
    reg        cmd_pending;

    //-------------------------------------------------------------------------
    // I2C State Machine
    //-------------------------------------------------------------------------
    localparam [3:0]
        I2C_IDLE      = 4'd0,
        I2C_START_A   = 4'd1,
        I2C_START_B   = 4'd2,
        I2C_BIT_LOW   = 4'd3,
        I2C_BIT_HIGH  = 4'd4,
        I2C_BIT_SAMPLE= 4'd5,
        I2C_STOP_A    = 4'd6,
        I2C_STOP_B    = 4'd7,
        I2C_STOP_C    = 4'd8;

    reg [3:0]  i2c_state;
    reg [15:0] clk_counter;
    reg [2:0]  bit_counter;
    reg [7:0]  shift_reg;
    reg        sda_out;
    reg        scl_out;
    reg        ack_bit;
    reg        is_read;

    //-------------------------------------------------------------------------
    // I2C Tri-State Control
    //-------------------------------------------------------------------------
    // Open-drain: drive low or release (high-Z)
    assign i2c_sda = sda_out ? 1'bz : 1'b0;
    assign i2c_scl = scl_out ? 1'bz : 1'b0;

    // Input sampling with synchronizer
    reg [2:0] sda_sync;
    reg [2:0] scl_sync;
    wire      sda_in;
    wire      scl_in;

    always @(posedge clk) begin
        sda_sync <= {sda_sync[1:0], i2c_sda};
        scl_sync <= {scl_sync[1:0], i2c_scl};
    end

    assign sda_in = sda_sync[2];
    assign scl_in = scl_sync[2];

    //-------------------------------------------------------------------------
    // Clock Period Calculation
    //-------------------------------------------------------------------------
    // For 100 MHz system clock:
    //   100 kHz I2C: prescale = 100M / (4 * 100K) - 1 = 249
    //   400 kHz I2C: prescale = 100M / (4 * 400K) - 1 = 62
    wire [15:0] clk_period;
    assign clk_period = prescale_reg;

    //-------------------------------------------------------------------------
    // AXI Write Logic
    //-------------------------------------------------------------------------
    reg [5:0] wr_addr;

    always @(posedge clk) begin
        if (reset) begin
            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            ctrl_reg <= 8'd0;
            addr_reg <= 7'd0;
            tx_data_reg <= 8'd0;
            prescale_reg <= 16'd249;  // Default 100 kHz
            cmd_reg <= CMD_NOP;
            cmd_pending <= 1'b0;
        end else begin
            // Default
            s_axi_bvalid <= s_axi_bvalid && !s_axi_bready;

            // Address phase
            if (s_axi_awvalid && s_axi_awready) begin
                wr_addr <= s_axi_awaddr;
                s_axi_awready <= 1'b0;
                s_axi_wready <= 1'b1;
            end

            // Data phase
            if (s_axi_wvalid && s_axi_wready) begin
                s_axi_wready <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;

                case (wr_addr)
                    REG_CTRL:     ctrl_reg <= s_axi_wdata[7:0];
                    REG_ADDR:     addr_reg <= s_axi_wdata[6:0];
                    REG_TX_DATA:  tx_data_reg <= s_axi_wdata[7:0];
                    REG_PRESCALE: prescale_reg <= s_axi_wdata[15:0];
                    REG_CMD: begin
                        cmd_reg <= s_axi_wdata[2:0];
                        cmd_pending <= 1'b1;
                    end
                endcase
            end

            // Clear command pending when I2C starts processing
            if (cmd_pending && i2c_state != I2C_IDLE) begin
                cmd_pending <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // AXI Read Logic
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rresp <= 2'b00;
        end else begin
            s_axi_rvalid <= s_axi_rvalid && !s_axi_rready;

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;

                case (s_axi_araddr)
                    REG_CTRL:     s_axi_rdata <= {24'd0, ctrl_reg};
                    REG_STATUS:   s_axi_rdata <= {24'd0, status_reg};
                    REG_ADDR:     s_axi_rdata <= {25'd0, addr_reg};
                    REG_TX_DATA:  s_axi_rdata <= {24'd0, tx_data_reg};
                    REG_RX_DATA:  s_axi_rdata <= {24'd0, rx_data_reg};
                    REG_PRESCALE: s_axi_rdata <= {16'd0, prescale_reg};
                    REG_CMD:      s_axi_rdata <= {29'd0, cmd_reg};
                    default:      s_axi_rdata <= 32'd0;
                endcase
            end else if (!s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // I2C State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            i2c_state <= I2C_IDLE;
            clk_counter <= 16'd0;
            bit_counter <= 3'd0;
            shift_reg <= 8'd0;
            sda_out <= 1'b1;
            scl_out <= 1'b1;
            ack_bit <= 1'b1;
            is_read <= 1'b0;
            status_reg <= 8'd0;
            rx_data_reg <= 8'd0;
            irq <= 1'b0;
        end else if (ctrl_reg[CTRL_ENABLE]) begin
            irq <= 1'b0;  // Clear interrupt by default

            case (i2c_state)
                //-------------------------------------------------------------
                I2C_IDLE: begin
                    status_reg[STAT_BUSY] <= 1'b0;

                    if (cmd_pending) begin
                        status_reg[STAT_BUSY] <= 1'b1;
                        status_reg[STAT_ERROR] <= 1'b0;

                        case (cmd_reg)
                            CMD_START: begin
                                sda_out <= 1'b1;
                                scl_out <= 1'b1;
                                clk_counter <= clk_period;
                                i2c_state <= I2C_START_A;
                            end

                            CMD_STOP: begin
                                sda_out <= 1'b0;
                                scl_out <= 1'b0;
                                clk_counter <= clk_period;
                                i2c_state <= I2C_STOP_A;
                            end

                            CMD_WRITE: begin
                                shift_reg <= tx_data_reg;
                                bit_counter <= 3'd7;
                                sda_out <= tx_data_reg[7];
                                scl_out <= 1'b0;
                                clk_counter <= clk_period;
                                is_read <= 1'b0;
                                i2c_state <= I2C_BIT_LOW;
                            end

                            CMD_READ_ACK, CMD_READ_NACK: begin
                                shift_reg <= 8'hFF;
                                bit_counter <= 3'd7;
                                sda_out <= 1'b1;  // Release SDA for reading
                                scl_out <= 1'b0;
                                clk_counter <= clk_period;
                                is_read <= 1'b1;
                                ack_bit <= (cmd_reg == CMD_READ_NACK);  // 0=ACK, 1=NACK
                                i2c_state <= I2C_BIT_LOW;
                            end

                            default: begin
                                status_reg[STAT_BUSY] <= 1'b0;
                            end
                        endcase
                    end
                end

                //-------------------------------------------------------------
                // START condition: SDA high→low while SCL high
                I2C_START_A: begin
                    if (clk_counter == 0) begin
                        sda_out <= 1'b0;  // SDA goes low
                        clk_counter <= clk_period;
                        i2c_state <= I2C_START_B;
                    end else begin
                        clk_counter <= clk_counter - 1;
                    end
                end

                I2C_START_B: begin
                    if (clk_counter == 0) begin
                        scl_out <= 1'b0;  // SCL goes low
                        status_reg[STAT_BUSY] <= 1'b0;
                        irq <= ctrl_reg[CTRL_IE];
                        i2c_state <= I2C_IDLE;
                    end else begin
                        clk_counter <= clk_counter - 1;
                    end
                end

                //-------------------------------------------------------------
                // Bit transfer: output bit, raise SCL, sample (if read), lower SCL
                I2C_BIT_LOW: begin
                    // SCL low, prepare data
                    if (clk_counter == 0) begin
                        scl_out <= 1'b1;  // Raise SCL
                        clk_counter <= clk_period;
                        i2c_state <= I2C_BIT_HIGH;
                    end else begin
                        clk_counter <= clk_counter - 1;
                    end
                end

                I2C_BIT_HIGH: begin
                    // SCL high, wait for clock stretching
                    if (!scl_in) begin
                        // Clock stretching - slave holding SCL low
                        // Don't decrement counter
                    end else if (clk_counter == clk_period >> 1) begin
                        // Sample in middle of SCL high
                        if (is_read) begin
                            shift_reg <= {shift_reg[6:0], sda_in};
                        end
                        clk_counter <= clk_counter - 1;
                    end else if (clk_counter == 0) begin
                        scl_out <= 1'b0;  // Lower SCL
                        clk_counter <= clk_period;
                        i2c_state <= I2C_BIT_SAMPLE;
                    end else begin
                        clk_counter <= clk_counter - 1;
                    end
                end

                I2C_BIT_SAMPLE: begin
                    if (clk_counter == 0) begin
                        if (bit_counter == 0) begin
                            // Done with 8 bits, now ACK/NACK
                            if (is_read) begin
                                // We send ACK/NACK
                                rx_data_reg <= shift_reg;
                                status_reg[STAT_RX_VALID] <= 1'b1;
                                sda_out <= ack_bit;  // 0=ACK, 1=NACK
                            end else begin
                                // We receive ACK/NACK
                                sda_out <= 1'b1;  // Release SDA
                            end
                            bit_counter <= 3'd0;  // Use for ACK phase
                            clk_counter <= clk_period;
                            i2c_state <= I2C_BIT_LOW;

                            // This will do one more bit cycle for ACK
                            // Mark we're done after that
                            if (is_read) begin
                                is_read <= 1'b0;  // Signal completion after ACK
                            end else begin
                                // For write, check ACK on next high
                                is_read <= 1'b1;  // Temporarily reuse for ACK sample
                            end
                        end else begin
                            // More bits to transfer
                            bit_counter <= bit_counter - 1;
                            if (!is_read) begin
                                sda_out <= shift_reg[6];  // Next bit
                                shift_reg <= {shift_reg[6:0], 1'b0};
                            end else begin
                                sda_out <= 1'b1;  // Keep released for reading
                            end
                            clk_counter <= clk_period;
                            i2c_state <= I2C_BIT_LOW;
                        end
                    end else begin
                        clk_counter <= clk_counter - 1;
                    end
                end

                //-------------------------------------------------------------
                // STOP condition: SDA low→high while SCL high
                I2C_STOP_A: begin
                    if (clk_counter == 0) begin
                        scl_out <= 1'b1;  // SCL goes high
                        clk_counter <= clk_period;
                        i2c_state <= I2C_STOP_B;
                    end else begin
                        clk_counter <= clk_counter - 1;
                    end
                end

                I2C_STOP_B: begin
                    if (clk_counter == 0) begin
                        sda_out <= 1'b1;  // SDA goes high
                        clk_counter <= clk_period;
                        i2c_state <= I2C_STOP_C;
                    end else begin
                        clk_counter <= clk_counter - 1;
                    end
                end

                I2C_STOP_C: begin
                    if (clk_counter == 0) begin
                        status_reg[STAT_BUSY] <= 1'b0;
                        irq <= ctrl_reg[CTRL_IE];
                        i2c_state <= I2C_IDLE;
                    end else begin
                        clk_counter <= clk_counter - 1;
                    end
                end

                default: i2c_state <= I2C_IDLE;
            endcase
        end else begin
            // I2C disabled - release bus
            sda_out <= 1'b1;
            scl_out <= 1'b1;
            i2c_state <= I2C_IDLE;
        end
    end

endmodule
