// SPDX-License-Identifier: BSD-3-Clause
//
// ulpi_wrapper_v2.v - UTMI+ to ULPI Interface Wrapper
//
// Part of FluxRipper - Open-source KryoFlux-compatible floppy disk reader
// Copyright (c) 2025 John Fabienke
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Description:
//   Converts UTMI+ interface signals to ULPI reduced pin count interface.
//   Designed for USB3300/USB3320 PHY in USB device mode.
//
//   Features:
//   - UTMI transmit/receive data conversion
//   - PHY register writes for mode control (Function Control, OTG Control)
//   - Bus turnaround handling
//   - RX_CMD status decoding (linestate, rxactive, rxerror)
//   - TX buffering to decouple UTMI timing from ULPI
//
//   Timing:
//   - All signals synchronous to 60 MHz ulpi_clk
//   - No internal clock domain crossing
//
// Created: 2025-12-06 20:45:00
//
//-----------------------------------------------------------------------------

module ulpi_wrapper_v2 (
    // ULPI PHY Interface (directly to USB3300/USB3320 pins)
    input  wire        ulpi_clk60_i,       // 60 MHz clock from PHY
    input  wire        ulpi_rst_i,         // Reset (active high)
    input  wire [7:0]  ulpi_data_out_i,    // Data from PHY (directly from pad)
    input  wire        ulpi_dir_i,         // Direction: 1=PHY driving, 0=FPGA driving
    input  wire        ulpi_nxt_i,         // Next: PHY ready for next byte / data valid
    output wire [7:0]  ulpi_data_in_o,     // Data to PHY (directly to pad)
    output wire        ulpi_stp_o,         // Stop: FPGA terminates transfer

    // UTMI+ Interface (to USB device core)
    input  wire [7:0]  utmi_data_out_i,    // TX data from device core
    input  wire        utmi_txvalid_i,     // TX data valid
    output wire        utmi_txready_o,     // TX ready to accept data
    output wire [7:0]  utmi_data_in_o,     // RX data to device core
    output wire        utmi_rxvalid_o,     // RX data valid
    output wire        utmi_rxactive_o,    // RX packet in progress
    output wire        utmi_rxerror_o,     // RX error detected
    output wire [1:0]  utmi_linestate_o,   // USB line state (D+/D-)

    // UTMI+ Control (from device core)
    input  wire [1:0]  utmi_op_mode_i,     // Operating mode
    input  wire [1:0]  utmi_xcvrselect_i,  // Transceiver select
    input  wire        utmi_termselect_i,  // Termination select
    input  wire        utmi_dppulldown_i,  // D+ pulldown enable
    input  wire        utmi_dmpulldown_i   // D- pulldown enable
);

    //=========================================================================
    // ULPI Command Bytes
    //=========================================================================
    localparam [7:0] CMD_TX_DATA      = 8'h40;  // Transmit command + PID[3:0]
    localparam [7:0] CMD_REG_WRITE    = 8'h80;  // Register write command
    localparam [7:0] CMD_REG_READ     = 8'hC0;  // Register read command

    // ULPI Register Addresses (for immediate write: CMD | ADDR)
    localparam [5:0] REG_FUNC_CTRL    = 6'h04;  // Function Control register
    localparam [5:0] REG_OTG_CTRL     = 6'h0A;  // OTG Control register

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [2:0] ST_IDLE      = 3'd0;  // Waiting for work
    localparam [2:0] ST_TX_CMD    = 3'd1;  // Sending TX command byte
    localparam [2:0] ST_TX_DATA   = 3'd2;  // Sending TX data bytes
    localparam [2:0] ST_REG_CMD   = 3'd3;  // Sending register write command
    localparam [2:0] ST_REG_DATA  = 3'd4;  // Sending register write data

    reg [2:0] state_q;

    //=========================================================================
    // Direction Tracking (for turnaround detection)
    //=========================================================================
    reg dir_prev_q;

    always @(posedge ulpi_clk60_i or posedge ulpi_rst_i) begin
        if (ulpi_rst_i)
            dir_prev_q <= 1'b0;
        else
            dir_prev_q <= ulpi_dir_i;
    end

    wire turnaround = (dir_prev_q != ulpi_dir_i);

    //=========================================================================
    // TX Buffer (2-entry FIFO to decouple UTMI from ULPI timing)
    //=========================================================================
    reg [7:0] tx_buf_data [0:1];
    reg [1:0] tx_buf_valid;
    reg       tx_wr_ptr;
    reg       tx_rd_ptr;

    wire tx_buf_empty = ~tx_buf_valid[tx_rd_ptr];
    wire tx_buf_full  = tx_buf_valid[tx_wr_ptr];
    wire [7:0] tx_buf_out = tx_buf_data[tx_rd_ptr];

    // TX buffer write (from UTMI)
    always @(posedge ulpi_clk60_i or posedge ulpi_rst_i) begin
        if (ulpi_rst_i) begin
            tx_buf_data[0] <= 8'd0;
            tx_buf_data[1] <= 8'd0;
            tx_buf_valid   <= 2'b00;
            tx_wr_ptr      <= 1'b0;
        end else begin
            // Write to buffer when UTMI has valid data and we're ready
            if (utmi_txvalid_i && utmi_txready_o) begin
                tx_buf_data[tx_wr_ptr] <= utmi_data_out_i;
                tx_buf_valid[tx_wr_ptr] <= 1'b1;
                tx_wr_ptr <= ~tx_wr_ptr;
            end

            // Read from buffer when ULPI accepts data
            if (tx_pop) begin
                tx_buf_valid[tx_rd_ptr] <= 1'b0;
                tx_rd_ptr <= ~tx_rd_ptr;
            end
        end
    end

    // TX ready when buffer has space and we're not receiving
    wire tx_ready_internal = ~tx_buf_full && ~ulpi_dir_i && (tx_delay_cnt == 3'd0);
    assign utmi_txready_o = tx_ready_internal;

    // TX pop signal - set when data is consumed by ULPI
    reg tx_pop;

    //=========================================================================
    // TX Delay Counter (wait after RX before allowing TX)
    //=========================================================================
    reg [2:0] tx_delay_cnt;

    always @(posedge ulpi_clk60_i or posedge ulpi_rst_i) begin
        if (ulpi_rst_i)
            tx_delay_cnt <= 3'd0;
        else if (utmi_rxactive_q)
            tx_delay_cnt <= 3'd7;  // Reset delay when receiving
        else if (tx_delay_cnt != 3'd0)
            tx_delay_cnt <= tx_delay_cnt - 3'd1;
    end

    //=========================================================================
    // Mode Control Register Tracking
    //=========================================================================
    reg [1:0] xcvr_q, opmode_q;
    reg       term_q;
    reg       mode_pending;
    reg       phy_reset_q;

    always @(posedge ulpi_clk60_i or posedge ulpi_rst_i) begin
        if (ulpi_rst_i) begin
            xcvr_q       <= 2'b00;
            opmode_q     <= 2'b11;  // Non-driving
            term_q       <= 1'b0;
            mode_pending <= 1'b0;
            phy_reset_q  <= 1'b1;   // Start with PHY reset
        end else begin
            // Track current settings
            xcvr_q   <= utmi_xcvrselect_i;
            opmode_q <= utmi_op_mode_i;
            term_q   <= utmi_termselect_i;

            // Detect changes requiring register update
            if ((xcvr_q != utmi_xcvrselect_i) ||
                (opmode_q != utmi_op_mode_i) ||
                (term_q != utmi_termselect_i)) begin
                mode_pending <= 1'b1;
            end else if (mode_write_done) begin
                mode_pending <= 1'b0;
                phy_reset_q  <= 1'b0;
            end
        end
    end

    wire mode_write_done;

    //=========================================================================
    // OTG Control Register Tracking
    //=========================================================================
    reg dppd_q, dmpd_q;
    reg otg_pending;

    always @(posedge ulpi_clk60_i or posedge ulpi_rst_i) begin
        if (ulpi_rst_i) begin
            dppd_q      <= 1'b1;  // Default pulldowns enabled
            dmpd_q      <= 1'b1;
            otg_pending <= 1'b0;
        end else begin
            dppd_q <= utmi_dppulldown_i;
            dmpd_q <= utmi_dmpulldown_i;

            if ((dppd_q != utmi_dppulldown_i) ||
                (dmpd_q != utmi_dmpulldown_i)) begin
                otg_pending <= 1'b1;
            end else if (otg_write_done) begin
                otg_pending <= 1'b0;
            end
        end
    end

    wire otg_write_done;

    //=========================================================================
    // ULPI Output Registers (directly drive pads)
    //=========================================================================
    reg [7:0] ulpi_data_q;
    reg       ulpi_stp_q;

    assign ulpi_data_in_o = ulpi_data_q;
    assign ulpi_stp_o     = ulpi_stp_q;

    //=========================================================================
    // UTMI RX Status Registers
    //=========================================================================
    reg [7:0] utmi_data_q;
    reg       utmi_rxvalid_q;
    reg       utmi_rxactive_q;
    reg       utmi_rxerror_q;
    reg [1:0] utmi_linestate_q;

    assign utmi_data_in_o   = utmi_data_q;
    assign utmi_rxvalid_o   = utmi_rxvalid_q;
    assign utmi_rxactive_o  = utmi_rxactive_q;
    assign utmi_rxerror_o   = utmi_rxerror_q;
    assign utmi_linestate_o = utmi_linestate_q;

    //=========================================================================
    // Register Write Completion Signals
    //=========================================================================
    reg mode_writing, otg_writing;

    assign mode_write_done = mode_writing && (state_q == ST_REG_DATA) &&
                             ulpi_nxt_i && !ulpi_dir_i;
    assign otg_write_done  = otg_writing && (state_q == ST_REG_DATA) &&
                             ulpi_nxt_i && !ulpi_dir_i;

    //=========================================================================
    // Main State Machine
    //=========================================================================
    // Function Control register value
    wire [7:0] func_ctrl_val = {
        1'b0,           // Reserved
        1'b1,           // SuspendM = 1 (not suspended)
        phy_reset_q,    // Reset
        opmode_q,       // OpMode[1:0]
        term_q,         // TermSelect
        xcvr_q          // XcvrSelect[1:0]
    };

    // OTG Control register value
    wire [7:0] otg_ctrl_val = {
        5'b00000,       // Reserved bits
        dmpd_q,         // DmPulldown
        dppd_q,         // DpPulldown
        1'b0            // IdPullup = 0
    };

    always @(posedge ulpi_clk60_i or posedge ulpi_rst_i) begin
        if (ulpi_rst_i) begin
            state_q         <= ST_IDLE;
            ulpi_data_q     <= 8'd0;
            ulpi_stp_q      <= 1'b0;
            utmi_data_q     <= 8'd0;
            utmi_rxvalid_q  <= 1'b0;
            utmi_rxactive_q <= 1'b0;
            utmi_rxerror_q  <= 1'b0;
            utmi_linestate_q <= 2'b00;
            mode_writing    <= 1'b0;
            otg_writing     <= 1'b0;
            tx_pop          <= 1'b0;
        end else begin
            // Defaults
            ulpi_stp_q     <= 1'b0;
            utmi_rxvalid_q <= 1'b0;
            tx_pop         <= 1'b0;

            //=================================================================
            // Turnaround: PHY taking bus
            //=================================================================
            if (turnaround && ulpi_dir_i) begin
                // PHY is taking control
                ulpi_data_q <= 8'd0;  // Release bus

                if (ulpi_nxt_i) begin
                    // RX starting
                    utmi_rxactive_q <= 1'b1;
                end

                // Abort any pending register write
                if (state_q == ST_REG_CMD || state_q == ST_REG_DATA) begin
                    state_q      <= ST_IDLE;
                    mode_writing <= 1'b0;
                    otg_writing  <= 1'b0;
                end
            end
            //=================================================================
            // Turnaround: PHY releasing bus
            //=================================================================
            else if (turnaround && !ulpi_dir_i) begin
                utmi_rxactive_q <= 1'b0;

                // Return to idle if we were interrupted
                if (state_q == ST_REG_CMD || state_q == ST_REG_DATA) begin
                    state_q      <= ST_IDLE;
                    mode_writing <= 1'b0;
                    otg_writing  <= 1'b0;
                end
            end
            //=================================================================
            // Non-turnaround cycles
            //=================================================================
            else if (!turnaround) begin
                //-------------------------------------------------------------
                // PHY driving bus (receiving)
                //-------------------------------------------------------------
                if (ulpi_dir_i) begin
                    if (!ulpi_nxt_i) begin
                        // RX_CMD byte - decode status
                        utmi_linestate_q <= ulpi_data_out_i[1:0];

                        case (ulpi_data_out_i[5:4])
                            2'b00: begin  // RxActive = 0
                                utmi_rxactive_q <= 1'b0;
                                utmi_rxerror_q  <= 1'b0;
                            end
                            2'b01: begin  // RxActive = 1, no error
                                utmi_rxactive_q <= 1'b1;
                                utmi_rxerror_q  <= 1'b0;
                            end
                            2'b11: begin  // RxActive = 1, error
                                utmi_rxactive_q <= 1'b1;
                                utmi_rxerror_q  <= 1'b1;
                            end
                            default: ;    // Host disconnect - ignore
                        endcase
                    end else begin
                        // RX data byte
                        utmi_data_q    <= ulpi_data_out_i;
                        utmi_rxvalid_q <= 1'b1;
                    end
                end
                //-------------------------------------------------------------
                // FPGA driving bus (transmitting / register writes)
                //-------------------------------------------------------------
                else begin
                    case (state_q)
                        ST_IDLE: begin
                            // Priority: Mode update > OTG update > TX data
                            if (mode_pending) begin
                                // Start Function Control register write
                                ulpi_data_q  <= CMD_REG_WRITE | REG_FUNC_CTRL;
                                state_q      <= ST_REG_CMD;
                                mode_writing <= 1'b1;
                                otg_writing  <= 1'b0;
                            end else if (otg_pending) begin
                                // Start OTG Control register write
                                ulpi_data_q  <= CMD_REG_WRITE | REG_OTG_CTRL;
                                state_q      <= ST_REG_CMD;
                                mode_writing <= 1'b0;
                                otg_writing  <= 1'b1;
                            end else if (!tx_buf_empty) begin
                                // Start TX: send TX_CMD with PID in lower nibble
                                ulpi_data_q <= CMD_TX_DATA | tx_buf_out[3:0];
                                state_q     <= ST_TX_CMD;
                            end else begin
                                // Nothing to do - drive IDLE (0x00)
                                ulpi_data_q <= 8'd0;
                            end
                        end

                        ST_REG_CMD: begin
                            if (ulpi_nxt_i) begin
                                // PHY accepted command, send data
                                if (mode_writing)
                                    ulpi_data_q <= func_ctrl_val;
                                else
                                    ulpi_data_q <= otg_ctrl_val;
                                state_q <= ST_REG_DATA;
                            end
                        end

                        ST_REG_DATA: begin
                            if (ulpi_nxt_i) begin
                                // PHY accepted data, terminate with STP
                                ulpi_stp_q   <= 1'b1;
                                ulpi_data_q  <= 8'd0;
                                state_q      <= ST_IDLE;
                                mode_writing <= 1'b0;
                                otg_writing  <= 1'b0;
                            end
                        end

                        ST_TX_CMD: begin
                            if (ulpi_nxt_i) begin
                                // PHY accepted TX command, pop first byte and continue
                                tx_pop <= 1'b1;

                                if (tx_buf_valid[~tx_rd_ptr]) begin
                                    // More data in buffer
                                    ulpi_data_q <= tx_buf_data[~tx_rd_ptr];
                                    state_q     <= ST_TX_DATA;
                                end else begin
                                    // No more data - end packet
                                    ulpi_stp_q  <= 1'b1;
                                    ulpi_data_q <= 8'd0;
                                    state_q     <= ST_IDLE;
                                end
                            end
                        end

                        ST_TX_DATA: begin
                            if (ulpi_nxt_i) begin
                                tx_pop <= 1'b1;

                                if (!tx_buf_empty && tx_buf_valid[~tx_rd_ptr]) begin
                                    // More data available
                                    ulpi_data_q <= tx_buf_data[~tx_rd_ptr];
                                end else begin
                                    // End of packet
                                    ulpi_stp_q  <= 1'b1;
                                    ulpi_data_q <= 8'd0;
                                    state_q     <= ST_IDLE;
                                end
                            end
                        end

                        default: begin
                            state_q     <= ST_IDLE;
                            ulpi_data_q <= 8'd0;
                        end
                    endcase
                end
            end
        end
    end

endmodule
