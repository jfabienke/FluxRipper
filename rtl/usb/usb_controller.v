// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// usb_controller.v - FluxRipper USB Controller (Stub)
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 21:40
//
// Description:
//   USB 2.0 High-Speed device controller stub for simulation.
//   Full implementation would include ULPI PHY interface and
//   bulk transfer endpoints for data streaming.
//
// Register Map (active addresses within 0x4002_0000 - 0x4002_00FF):
//   0x00: ID        - Device ID (RO)
//   0x04: STATUS    - Status register (RO)
//   0x08: CONTROL   - Control register (RW)
//   0x0C: EP0_DATA  - Endpoint 0 data (RW)
//
//-----------------------------------------------------------------------------

module usb_controller (
    input         clk,
    input         rst_n,

    // Bus slave interface
    input  [7:0]  addr,
    input  [31:0] wdata,
    input         read,
    input         write,
    output reg [31:0] rdata,
    output        ready,

    // USB status (active high)
    output        usb_connected,
    output        usb_configured
);

    //=========================================================================
    // Register Addresses
    //=========================================================================
    localparam [7:0]
        REG_ID      = 8'h00,
        REG_STATUS  = 8'h04,
        REG_CONTROL = 8'h08,
        REG_EP0     = 8'h0C;

    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [31:0] control_reg;
    reg [31:0] ep0_data;
    reg        connected;
    reg        configured;

    //=========================================================================
    // Bus Interface
    //=========================================================================
    assign ready = 1'b1;
    assign usb_connected = connected;
    assign usb_configured = configured;

    //=========================================================================
    // Register Read
    //=========================================================================
    always @(*) begin
        case (addr)
            REG_ID:      rdata = 32'h05B20001;  // USB v2.0 device ID
            REG_STATUS:  rdata = {28'b0, 2'b0, configured, connected};
            REG_CONTROL: rdata = control_reg;
            REG_EP0:     rdata = ep0_data;
            default:     rdata = 32'h0;
        endcase
    end

    //=========================================================================
    // Register Write
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_reg <= 0;
            ep0_data <= 0;
            connected <= 0;
            configured <= 0;
        end else if (write) begin
            case (addr)
                REG_CONTROL: begin
                    control_reg <= wdata;
                    // Bit 0: Enable USB (simulates connection)
                    connected <= wdata[0];
                    // Bit 1: Force configured state (for testing)
                    configured <= wdata[1];
                end
                REG_EP0: ep0_data <= wdata;
            endcase
        end
    end

endmodule
