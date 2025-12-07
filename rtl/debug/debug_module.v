// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// debug_module.v - RISC-V Debug Module Implementation
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 21:30
//
// Description:
//   Implements RISC-V Debug Module Specification 0.13.
//   Provides system bus access for memory read/write via JTAG.
//   Simplified implementation focused on system bus access (no hart control).
//
//-----------------------------------------------------------------------------

module debug_module (
    input         clk,
    input         rst_n,

    // DMI interface (from DTM)
    input  [6:0]  dmi_addr,
    input  [31:0] dmi_wdata,
    input  [1:0]  dmi_op,       // 0=nop, 1=read, 2=write
    input         dmi_req,
    output reg [31:0] dmi_rdata,
    output reg [1:0]  dmi_resp,  // 0=ok, 2=busy, 3=error
    output reg        dmi_ack,

    // System bus master interface
    output reg [31:0] sbaddr,
    output reg [31:0] sbdata_o,
    input      [31:0] sbdata_i,
    output reg [2:0]  sbsize,    // 0=byte, 1=half, 2=word
    output reg        sbread,
    output reg        sbwrite,
    input             sbbusy,
    input             sberror
);

    //=========================================================================
    // DMI Register Addresses (RISC-V Debug Spec 0.13)
    //=========================================================================
    localparam [6:0]
        DMI_DMCONTROL   = 7'h10,   // Debug Module Control
        DMI_DMSTATUS    = 7'h11,   // Debug Module Status
        DMI_HARTINFO    = 7'h12,   // Hart Info
        DMI_ABSTRACTCS  = 7'h16,   // Abstract Command Control/Status
        DMI_SBCS        = 7'h38,   // System Bus Control/Status
        DMI_SBADDRESS0  = 7'h39,   // System Bus Address [31:0]
        DMI_SBDATA0     = 7'h3C;   // System Bus Data [31:0]

    //=========================================================================
    // Internal Registers
    //=========================================================================

    // dmcontrol register fields
    reg        dmactive;           // Debug module active
    reg        ndmreset;           // Non-debug module reset
    reg        haltreq;            // Hart halt request

    // sbcs register fields
    reg [2:0]  sbaccess;           // Access size (0=8, 1=16, 2=32)
    reg        sbautoincrement;    // Auto-increment address
    reg        sbreadonaddr;       // Read on address write
    reg        sbreadondata;       // Read on data read
    reg [2:0]  sberror_reg;        // Stored error status

    // System bus state machine
    reg [1:0]  sb_state;
    localparam [1:0]
        SB_IDLE    = 2'b00,
        SB_READ    = 2'b01,
        SB_WRITE   = 2'b10,
        SB_WAIT    = 2'b11;

    reg        sb_read_pending;
    reg [31:0] sb_rdata_latch;

    //=========================================================================
    // Combinational DMI Read
    //=========================================================================
    always @(*) begin
        case (dmi_addr)
            DMI_DMSTATUS: begin
                // dmstatus: version=2, authenticated=1, allhalted/anyhalted=0
                // [3:0]=version, [7]=authenticated, [9]=anyhalted, [10]=allhalted
                // [11]=anyrunning, [12]=allrunning, [17]=impebreak, [22]=hasresethaltreq
                dmi_rdata = {9'b0,            // [31:23] reserved
                             1'b0,            // [22] hasresethaltreq
                             4'b0,            // [21:18] reserved
                             1'b0,            // [17] impebreak
                             4'b0,            // [16:13] reserved
                             1'b1,            // [12] allrunning
                             1'b1,            // [11] anyrunning
                             1'b0,            // [10] allhalted
                             1'b0,            // [9] anyhalted
                             1'b0,            // [8] reserved
                             1'b1,            // [7] authenticated
                             3'b0,            // [6:4] reserved
                             4'd2};           // [3:0] version = 2
            end

            DMI_DMCONTROL: begin
                dmi_rdata = {1'b0,            // [31] haltreq (W)
                             1'b0,            // [30] resumereq (W)
                             1'b0,            // [29] hartreset
                             1'b0,            // [28] ackhavereset
                             1'b0,            // [27] reserved
                             1'b0,            // [26] hasel
                             10'b0,           // [25:16] hartsello
                             4'b0,            // [15:12] reserved
                             1'b0,            // [11] reserved
                             1'b0,            // [10] reserved
                             ndmreset,        // [1] ndmreset
                             dmactive};       // [0] dmactive
            end

            DMI_HARTINFO: begin
                // No data registers, minimal implementation
                dmi_rdata = 32'h0;
            end

            DMI_ABSTRACTCS: begin
                // progbufsize=0, busy=0, cmderr=0, datacount=0
                dmi_rdata = 32'h0;
            end

            DMI_SBCS: begin
                // RISC-V Debug Spec 0.13 sbcs layout:
                // [31:29] sbversion, [28:22] sbasize, [21] reserved, [20] sbbusyerror
                // [19] sbbusy, [18] sbreadonaddr, [17] sbreadondata, [16] sberror[2]
                // [15:14] sberror[1:0], [13:12] sbasize, [11:9] sbaccess
                // ... simplified for our needs
                dmi_rdata = 32'h0;
                dmi_rdata[31:29] = 3'd1;          // sbversion = 1
                dmi_rdata[28:22] = 7'd32;         // sbasize = 32 (32-bit addresses)
                dmi_rdata[19]    = (sb_state != SB_IDLE); // sbbusy
                dmi_rdata[17]    = 1'b1;          // sbaccess32 supported
                dmi_rdata[16]    = 1'b1;          // sbaccess16 supported
                dmi_rdata[15]    = 1'b1;          // sbaccess8 supported
                dmi_rdata[14:12] = sberror_reg;   // sberror
                dmi_rdata[11]    = sbreadondata;  // sbreadondata
                dmi_rdata[10]    = sbreadonaddr;  // sbreadonaddr
                dmi_rdata[5]     = sbautoincrement; // sbautoincrement
                dmi_rdata[4:2]   = sbaccess;      // sbaccess (size)
            end

            DMI_SBADDRESS0: begin
                dmi_rdata = sbaddr;
            end

            DMI_SBDATA0: begin
                dmi_rdata = sb_rdata_latch;
            end

            default: begin
                dmi_rdata = 32'h0;
            end
        endcase
    end

    //=========================================================================
    // DMI Interface Handling
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmi_ack <= 0;
            dmi_resp <= 2'b00;
        end else begin
            dmi_ack <= 0;
            if (dmi_req && !dmi_ack) begin
                dmi_ack <= 1;
                dmi_resp <= 2'b00;  // OK
            end
        end
    end

    //=========================================================================
    // Register Writes
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmactive <= 0;
            ndmreset <= 0;
            haltreq <= 0;
            sbaccess <= 3'd2;       // Default to 32-bit
            sbautoincrement <= 0;
            sbreadonaddr <= 0;
            sbreadondata <= 0;
            sberror_reg <= 0;
            sbaddr <= 0;
        end else if (dmi_req && dmi_op == 2'b10) begin  // Write
            case (dmi_addr)
                DMI_DMCONTROL: begin
                    dmactive <= dmi_wdata[0];
                    ndmreset <= dmi_wdata[1];
                    haltreq <= dmi_wdata[31];
                end

                DMI_SBCS: begin
                    sbaccess <= dmi_wdata[3:1];
                    sbautoincrement <= dmi_wdata[5];
                    sbreadonaddr <= dmi_wdata[10];
                    sbreadondata <= dmi_wdata[11];
                    // Clear error bits when written with 1
                    if (dmi_wdata[14:12] != 0)
                        sberror_reg <= 0;
                end

                DMI_SBADDRESS0: begin
                    sbaddr <= dmi_wdata;
                end

                DMI_SBDATA0: begin
                    // Write to sbdata triggers system bus write
                    // Handled in state machine below
                end
            endcase
        end
    end

    //=========================================================================
    // System Bus State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sb_state <= SB_IDLE;
            sbread <= 0;
            sbwrite <= 0;
            sbdata_o <= 0;
            sbsize <= 3'd2;
            sb_read_pending <= 0;
            sb_rdata_latch <= 0;
        end else begin
            // Default: clear single-cycle signals
            sbread <= 0;
            sbwrite <= 0;

            case (sb_state)
                SB_IDLE: begin
                    if (dmi_req && dmi_op == 2'b10) begin  // DMI Write
                        if (dmi_addr == DMI_SBDATA0) begin
                            // Write to sbdata0 triggers system bus write
                            sbdata_o <= dmi_wdata;
                            sbsize <= sbaccess;
                            sbwrite <= 1;
                            sb_state <= SB_WRITE;
                        end else if (dmi_addr == DMI_SBADDRESS0 && sbreadonaddr) begin
                            // Write to sbaddress0 with sbreadonaddr triggers read
                            sb_read_pending <= 1;
                        end
                    end else if (dmi_req && dmi_op == 2'b01) begin  // DMI Read
                        if (dmi_addr == DMI_SBDATA0 && sbreadondata) begin
                            // Read of sbdata0 with sbreadondata triggers new read
                            sb_read_pending <= 1;
                        end
                    end

                    // Execute pending read
                    if (sb_read_pending && sb_state == SB_IDLE) begin
                        sbsize <= sbaccess;
                        sbread <= 1;
                        sb_state <= SB_READ;
                        sb_read_pending <= 0;
                    end
                end

                SB_READ: begin
                    if (!sbbusy) begin
                        sb_rdata_latch <= sbdata_i;
                        if (sberror)
                            sberror_reg <= 3'd2;  // Bus error
                        if (sbautoincrement)
                            sbaddr <= sbaddr + (1 << sbaccess);
                        sb_state <= SB_IDLE;
                    end
                end

                SB_WRITE: begin
                    if (!sbbusy) begin
                        if (sberror)
                            sberror_reg <= 3'd2;  // Bus error
                        if (sbautoincrement)
                            sbaddr <= sbaddr + (1 << sbaccess);
                        sb_state <= SB_IDLE;
                    end
                end

                default: sb_state <= SB_IDLE;
            endcase
        end
    end

endmodule
