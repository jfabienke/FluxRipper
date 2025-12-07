// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// debug_mem_port.v - Debug Memory Access Port
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 14:55
//
// Description:
//   Provides debug access to the full system memory map via AXI-Lite.
//   Supports single-word reads/writes and burst operations for efficiency.
//   Used by both JTAG debug and CDC console commands.
//
// Features:
//   - 32-bit address, 32-bit data
//   - AXI-Lite master interface
//   - Transaction timeout detection
//   - Error capture and reporting
//   - Byte/half/word access modes
//
//-----------------------------------------------------------------------------

module debug_mem_port #(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter TIMEOUT_CYCLES = 1000  // Bus timeout
)(
    input                       clk,
    input                       rst_n,

    //-------------------------------------------------------------------------
    // Command Interface
    //-------------------------------------------------------------------------
    input  [ADDR_WIDTH-1:0]     addr,
    input  [DATA_WIDTH-1:0]     wdata,
    output [DATA_WIDTH-1:0]     rdata,
    input                       read_req,
    input                       write_req,
    input  [1:0]                size,       // 0=byte, 1=half, 2=word
    output                      ready,
    output                      error,
    output [1:0]                error_type, // 0=ok, 1=timeout, 2=slave_err, 3=decode_err

    //-------------------------------------------------------------------------
    // AXI-Lite Master Interface
    //-------------------------------------------------------------------------
    output reg [ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg                  m_axi_awvalid,
    input                       m_axi_awready,
    output reg [DATA_WIDTH-1:0] m_axi_wdata,
    output reg [3:0]            m_axi_wstrb,
    output reg                  m_axi_wvalid,
    input                       m_axi_wready,
    input  [1:0]                m_axi_bresp,
    input                       m_axi_bvalid,
    output reg                  m_axi_bready,
    output reg [ADDR_WIDTH-1:0] m_axi_araddr,
    output reg                  m_axi_arvalid,
    input                       m_axi_arready,
    input  [DATA_WIDTH-1:0]     m_axi_rdata,
    input  [1:0]                m_axi_rresp,
    input                       m_axi_rvalid,
    output reg                  m_axi_rready
);

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam [2:0]
        IDLE        = 3'd0,
        READ_ADDR   = 3'd1,
        READ_DATA   = 3'd2,
        WRITE_ADDR  = 3'd3,
        WRITE_DATA  = 3'd4,
        WRITE_RESP  = 3'd5,
        DONE        = 3'd6,
        ERROR_STATE = 3'd7;

    reg [2:0] state;
    reg [2:0] next_state;

    //=========================================================================
    // Registers
    //=========================================================================

    reg [DATA_WIDTH-1:0] rdata_reg;
    reg [15:0]           timeout_cnt;
    reg                  error_reg;
    reg [1:0]            error_type_reg;
    reg                  ready_reg;

    //=========================================================================
    // Write Strobe Generation
    //=========================================================================

    reg [3:0] wstrb_calc;

    always @(*) begin
        case (size)
            2'b00: begin // Byte
                case (addr[1:0])
                    2'b00: wstrb_calc = 4'b0001;
                    2'b01: wstrb_calc = 4'b0010;
                    2'b10: wstrb_calc = 4'b0100;
                    2'b11: wstrb_calc = 4'b1000;
                endcase
            end
            2'b01: begin // Halfword
                wstrb_calc = addr[1] ? 4'b1100 : 4'b0011;
            end
            default: begin // Word
                wstrb_calc = 4'b1111;
            end
        endcase
    end

    //=========================================================================
    // State Machine Logic
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (read_req)
                    next_state = READ_ADDR;
                else if (write_req)
                    next_state = WRITE_ADDR;
            end

            READ_ADDR: begin
                if (m_axi_arready)
                    next_state = READ_DATA;
                else if (timeout_cnt == 0)
                    next_state = ERROR_STATE;
            end

            READ_DATA: begin
                if (m_axi_rvalid)
                    next_state = DONE;
                else if (timeout_cnt == 0)
                    next_state = ERROR_STATE;
            end

            WRITE_ADDR: begin
                if (m_axi_awready)
                    next_state = WRITE_DATA;
                else if (timeout_cnt == 0)
                    next_state = ERROR_STATE;
            end

            WRITE_DATA: begin
                if (m_axi_wready)
                    next_state = WRITE_RESP;
                else if (timeout_cnt == 0)
                    next_state = ERROR_STATE;
            end

            WRITE_RESP: begin
                if (m_axi_bvalid)
                    next_state = DONE;
                else if (timeout_cnt == 0)
                    next_state = ERROR_STATE;
            end

            DONE: begin
                next_state = IDLE;
            end

            ERROR_STATE: begin
                next_state = IDLE;
            end
        endcase
    end

    //=========================================================================
    // AXI-Lite Signal Control
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= {DATA_WIDTH{1'b0}};
            m_axi_wstrb   <= 4'b0000;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            rdata_reg     <= {DATA_WIDTH{1'b0}};
            timeout_cnt   <= TIMEOUT_CYCLES[15:0];
            error_reg     <= 1'b0;
            error_type_reg <= 2'b00;
            ready_reg     <= 1'b0;
        end else begin
            // Default de-assertions
            ready_reg <= 1'b0;
            error_reg <= 1'b0;

            case (state)
                IDLE: begin
                    timeout_cnt <= TIMEOUT_CYCLES[15:0];
                    error_type_reg <= 2'b00;

                    if (read_req) begin
                        m_axi_araddr  <= addr;
                        m_axi_arvalid <= 1'b1;
                        m_axi_rready  <= 1'b1;
                    end else if (write_req) begin
                        m_axi_awaddr  <= addr;
                        m_axi_awvalid <= 1'b1;
                        m_axi_wdata   <= wdata;
                        m_axi_wstrb   <= wstrb_calc;
                        m_axi_wvalid  <= 1'b1;
                        m_axi_bready  <= 1'b1;
                    end
                end

                READ_ADDR: begin
                    timeout_cnt <= timeout_cnt - 1;
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                    end
                end

                READ_DATA: begin
                    timeout_cnt <= timeout_cnt - 1;
                    if (m_axi_rvalid) begin
                        rdata_reg <= m_axi_rdata;
                        m_axi_rready <= 1'b0;

                        // Check for errors
                        if (m_axi_rresp != 2'b00) begin
                            error_type_reg <= m_axi_rresp;
                        end
                    end
                end

                WRITE_ADDR: begin
                    timeout_cnt <= timeout_cnt - 1;
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                    end
                end

                WRITE_DATA: begin
                    timeout_cnt <= timeout_cnt - 1;
                    if (m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                    end
                end

                WRITE_RESP: begin
                    timeout_cnt <= timeout_cnt - 1;
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;

                        // Check for errors
                        if (m_axi_bresp != 2'b00) begin
                            error_type_reg <= m_axi_bresp;
                        end
                    end
                end

                DONE: begin
                    ready_reg <= 1'b1;
                    error_reg <= (error_type_reg != 2'b00);
                end

                ERROR_STATE: begin
                    // Timeout - clean up
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    error_type_reg <= 2'b01;  // Timeout
                    error_reg <= 1'b1;
                    ready_reg <= 1'b1;
                end
            endcase
        end
    end

    //=========================================================================
    // Output Assignments
    //=========================================================================

    assign rdata      = rdata_reg;
    assign ready      = ready_reg;
    assign error      = error_reg;
    assign error_type = error_type_reg;

endmodule
