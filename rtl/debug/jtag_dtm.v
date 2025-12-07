// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// jtag_dtm.v - Debug Transport Module (RISC-V Debug Spec)
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 20:40
//
// Description:
//   Bridges JTAG TAP interface to Debug Module Interface (DMI).
//   Implements DTMCS and DMI registers per RISC-V Debug Spec 0.13.
//
//-----------------------------------------------------------------------------

module jtag_dtm #(
    parameter ABITS = 7,           // DMI address bits
    parameter IDLE_CYCLES = 1      // Required idle cycles
)(
    input               tck,
    input               trst_n,

    // TAP interface
    input  [4:0]        ir_value,
    input               dr_capture,
    input               dr_shift,
    input               dr_update,
    input               tdi,
    output reg          tdo,

    // DMI interface
    output reg [ABITS-1:0] dmi_addr,
    output reg [31:0]      dmi_wdata,
    output reg [1:0]       dmi_op,
    output reg             dmi_req,
    input      [31:0]      dmi_rdata,
    input      [1:0]       dmi_resp,
    input                  dmi_ack
);

    localparam [4:0] IR_DTMCS = 5'h10, IR_DMI = 5'h11;

    // DTMCS: [14:12]=idle, [11:10]=status, [9:4]=abits, [3:0]=version
    reg [31:0] dtmcs_shift;
    reg [40:0] dmi_shift;
    reg [1:0]  dmi_status;

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            dtmcs_shift <= 0;
            dmi_shift <= 0;
            dmi_status <= 0;
        end else if (dr_capture) begin
            case (ir_value)
                IR_DTMCS: dtmcs_shift <= {17'h0, 3'd1, dmi_status, 6'd7, 4'd1};
                IR_DMI:   dmi_shift <= {7'h0, dmi_rdata, dmi_status};
            endcase
        end else if (dr_shift) begin
            case (ir_value)
                IR_DTMCS: dtmcs_shift <= {tdi, dtmcs_shift[31:1]};
                IR_DMI:   dmi_shift <= {tdi, dmi_shift[40:1]};
            endcase
        end
    end

    always @(negedge tck) begin
        case (ir_value)
            IR_DTMCS: tdo <= dtmcs_shift[0];
            IR_DMI:   tdo <= dmi_shift[0];
            default:  tdo <= 0;
        endcase
    end

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            dmi_addr <= 0; dmi_wdata <= 0; dmi_op <= 0; dmi_req <= 0;
        end else begin
            dmi_req <= 0;
            if (dr_update && ir_value == IR_DMI && dmi_shift[1:0] != 0) begin
                dmi_addr <= dmi_shift[40:34];
                dmi_wdata <= dmi_shift[33:2];
                dmi_op <= dmi_shift[1:0];
                dmi_req <= 1;
            end
            if (dr_update && ir_value == IR_DTMCS && dtmcs_shift[17:16])
                dmi_status <= 0;
        end
    end

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) dmi_status <= 0;
        else if (dmi_ack && dmi_resp != 0 && dmi_status == 0)
            dmi_status <= dmi_resp;
    end
endmodule
