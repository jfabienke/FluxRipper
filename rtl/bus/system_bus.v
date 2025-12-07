// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// system_bus.v - FluxRipper System Bus Fabric
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 21:20
//
// Description:
//   Simple address-decoded bus fabric connecting debug module to peripherals.
//   Single master (debug), multiple slaves. No arbitration needed.
//
// Address Map:
//   0x0000_0000 - 0x0000_FFFF : Boot ROM (64KB)
//   0x1000_0000 - 0x1FFF_FFFF : Main Memory (256MB window)
//   0x4000_0000 - 0x4000_00FF : System Control
//   0x4001_0000 - 0x4001_00FF : Disk Controller
//   0x4002_0000 - 0x4002_00FF : USB Controller
//   0x4003_0000 - 0x4003_00FF : Signal Tap
//
//-----------------------------------------------------------------------------

module system_bus (
    input         clk,
    input         rst_n,

    // Master interface (from Debug Module)
    input  [31:0] m_addr,
    input  [31:0] m_wdata,
    output [31:0] m_rdata,
    input  [2:0]  m_size,       // 0=byte, 1=half, 2=word
    input         m_read,
    input         m_write,
    output        m_busy,
    output        m_error,

    // Slave 0: Boot ROM
    output [15:0] s0_addr,
    output        s0_read,
    input  [31:0] s0_rdata,
    input         s0_ready,

    // Slave 1: Main Memory
    output [27:0] s1_addr,
    output [31:0] s1_wdata,
    output        s1_read,
    output        s1_write,
    input  [31:0] s1_rdata,
    input         s1_ready,

    // Slave 2: System Control
    output [7:0]  s2_addr,
    output [31:0] s2_wdata,
    output        s2_read,
    output        s2_write,
    input  [31:0] s2_rdata,
    input         s2_ready,

    // Slave 3: Disk Controller
    output [7:0]  s3_addr,
    output [31:0] s3_wdata,
    output        s3_read,
    output        s3_write,
    input  [31:0] s3_rdata,
    input         s3_ready,

    // Slave 4: USB Controller
    output [7:0]  s4_addr,
    output [31:0] s4_wdata,
    output        s4_read,
    output        s4_write,
    input  [31:0] s4_rdata,
    input         s4_ready,

    // Slave 5: Signal Tap
    output [7:0]  s5_addr,
    output [31:0] s5_wdata,
    output        s5_read,
    output        s5_write,
    input  [31:0] s5_rdata,
    input         s5_ready
);

    //=========================================================================
    // Address Decode
    //=========================================================================
    localparam [3:0]
        SEL_NONE    = 4'd0,
        SEL_ROM     = 4'd1,
        SEL_RAM     = 4'd2,
        SEL_SYSCTRL = 4'd3,
        SEL_DISK    = 4'd4,
        SEL_USB     = 4'd5,
        SEL_SIGTAP  = 4'd6;

    reg [3:0] slave_sel;

    always @(*) begin
        casez (m_addr[31:16])
            16'h0000: slave_sel = SEL_ROM;      // 0x0000_xxxx
            16'h1???: slave_sel = SEL_RAM;      // 0x1xxx_xxxx
            16'h4000: slave_sel = SEL_SYSCTRL;  // 0x4000_xxxx
            16'h4001: slave_sel = SEL_DISK;     // 0x4001_xxxx
            16'h4002: slave_sel = SEL_USB;      // 0x4002_xxxx
            16'h4003: slave_sel = SEL_SIGTAP;   // 0x4003_xxxx
            default:  slave_sel = SEL_NONE;
        endcase
    end

    //=========================================================================
    // Address Routing
    //=========================================================================
    assign s0_addr  = m_addr[15:0];
    assign s1_addr  = m_addr[27:0];
    assign s2_addr  = m_addr[7:0];
    assign s3_addr  = m_addr[7:0];
    assign s4_addr  = m_addr[7:0];
    assign s5_addr  = m_addr[7:0];

    // Write data broadcast to all slaves
    assign s1_wdata = m_wdata;
    assign s2_wdata = m_wdata;
    assign s3_wdata = m_wdata;
    assign s4_wdata = m_wdata;
    assign s5_wdata = m_wdata;

    //=========================================================================
    // Read/Write Strobes (active only for selected slave)
    //=========================================================================
    assign s0_read  = m_read  && (slave_sel == SEL_ROM);
    assign s1_read  = m_read  && (slave_sel == SEL_RAM);
    assign s1_write = m_write && (slave_sel == SEL_RAM);
    assign s2_read  = m_read  && (slave_sel == SEL_SYSCTRL);
    assign s2_write = m_write && (slave_sel == SEL_SYSCTRL);
    assign s3_read  = m_read  && (slave_sel == SEL_DISK);
    assign s3_write = m_write && (slave_sel == SEL_DISK);
    assign s4_read  = m_read  && (slave_sel == SEL_USB);
    assign s4_write = m_write && (slave_sel == SEL_USB);
    assign s5_read  = m_read  && (slave_sel == SEL_SIGTAP);
    assign s5_write = m_write && (slave_sel == SEL_SIGTAP);

    //=========================================================================
    // Read Data Mux
    //=========================================================================
    reg [31:0] rdata_mux;

    always @(*) begin
        case (slave_sel)
            SEL_ROM:     rdata_mux = s0_rdata;
            SEL_RAM:     rdata_mux = s1_rdata;
            SEL_SYSCTRL: rdata_mux = s2_rdata;
            SEL_DISK:    rdata_mux = s3_rdata;
            SEL_USB:     rdata_mux = s4_rdata;
            SEL_SIGTAP:  rdata_mux = s5_rdata;
            default:     rdata_mux = 32'hDEADBEEF;  // Invalid address
        endcase
    end

    assign m_rdata = rdata_mux;

    //=========================================================================
    // Ready/Busy Logic
    //=========================================================================
    reg ready_mux;

    always @(*) begin
        case (slave_sel)
            SEL_ROM:     ready_mux = s0_ready;
            SEL_RAM:     ready_mux = s1_ready;
            SEL_SYSCTRL: ready_mux = s2_ready;
            SEL_DISK:    ready_mux = s3_ready;
            SEL_USB:     ready_mux = s4_ready;
            SEL_SIGTAP:  ready_mux = s5_ready;
            default:     ready_mux = 1'b1;  // Invalid = instant complete
        endcase
    end

    // Busy when access in progress and slave not ready
    assign m_busy = (m_read || m_write) && !ready_mux;

    // Error on invalid address access
    assign m_error = (m_read || m_write) && (slave_sel == SEL_NONE);

endmodule
