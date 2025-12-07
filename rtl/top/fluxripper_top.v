// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// fluxripper_top.v - FluxRipper Top-Level Module
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 22:45
// Updated: 2025-12-07 23:35 - Added synthesis attributes for FPGA
//
// Description:
//   Top-level integration of all FluxRipper subsystems.
//   Connects JTAG debug, clock/reset, bus fabric, and peripherals.
//
//-----------------------------------------------------------------------------

module fluxripper_top (
    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    input           clk_25m,        // 25 MHz reference clock
    input           rst_n,          // External reset (active low)

    //-------------------------------------------------------------------------
    // JTAG Interface
    //-------------------------------------------------------------------------
    input           tck,            // JTAG test clock
    input           tms,            // JTAG test mode select
    input           tdi,            // JTAG test data in
    output          tdo,            // JTAG test data out
    input           trst_n,         // JTAG reset (active low)

    //-------------------------------------------------------------------------
    // Disk Interface
    //-------------------------------------------------------------------------
    input           flux_in,        // Flux transition input
    input           index_in,       // Index pulse input
    output          motor_on,       // Motor enable
    output          head_sel,       // Head select
    output          dir,            // Step direction
    output          step,           // Step pulse

    //-------------------------------------------------------------------------
    // USB Interface (directly exposed for PHY)
    //-------------------------------------------------------------------------
    output          usb_connected,
    output          usb_configured,

    //-------------------------------------------------------------------------
    // Debug Signals
    //-------------------------------------------------------------------------
    output          pll_locked,     // PLL lock status
    output          sys_rst_n       // System reset status
);

    //=========================================================================
    // Internal Signals
    //=========================================================================

    // Clocks from clock manager
    wire            clk_sys;        // 100 MHz system clock
    wire            clk_usb;        // 48 MHz USB clock
    wire            clk_disk;       // 50 MHz disk clock
    wire            sys_rst_n_int;
    wire            pll_locked_int;

    // TAP internal signals
    wire [4:0]      ir_value;
    wire            dr_capture, dr_shift, dr_update;
    wire            tap_tdo, dtm_tdo;

    // DMI interface (DTM <-> Debug Module)
    (* MARK_DEBUG = "true" *) wire [6:0]      dmi_addr;
    (* MARK_DEBUG = "true" *) wire [31:0]     dmi_wdata;
    (* MARK_DEBUG = "true" *) wire [1:0]      dmi_op;
    (* MARK_DEBUG = "true" *) wire            dmi_req;
    (* MARK_DEBUG = "true" *) wire [31:0]     dmi_rdata;
    (* MARK_DEBUG = "true" *) wire [1:0]      dmi_resp;
    (* MARK_DEBUG = "true" *) wire            dmi_ack;

    // System bus master (Debug Module <-> Bus)
    (* MARK_DEBUG = "true" *) wire [31:0]     sb_addr;
    (* MARK_DEBUG = "true" *) wire [31:0]     sb_wdata;
    (* MARK_DEBUG = "true" *) wire [31:0]     sb_rdata;
    (* MARK_DEBUG = "true" *) wire [2:0]      sb_size;
    (* MARK_DEBUG = "true" *) wire            sb_read;
    (* MARK_DEBUG = "true" *) wire            sb_write;
    (* MARK_DEBUG = "true" *) wire            sb_busy;
    (* MARK_DEBUG = "true" *) wire            sb_error;

    // Slave interfaces
    wire [15:0]     rom_addr;
    wire            rom_read;
    wire [31:0]     rom_rdata;
    wire            rom_ready;

    wire [27:0]     ram_addr;
    wire [31:0]     ram_wdata;
    wire            ram_read;
    wire            ram_write;
    wire [31:0]     ram_rdata;
    wire            ram_ready;

    wire [7:0]      sysctrl_addr;
    wire [31:0]     sysctrl_wdata;
    wire            sysctrl_read;
    wire            sysctrl_write;
    wire [31:0]     sysctrl_rdata;
    wire            sysctrl_ready;

    wire [7:0]      disk_addr;
    wire [31:0]     disk_wdata;
    wire            disk_read;
    wire            disk_write;
    wire [31:0]     disk_rdata;
    wire            disk_ready;

    wire [7:0]      usb_addr;
    wire [31:0]     usb_wdata;
    wire            usb_read;
    wire            usb_write;
    wire [31:0]     usb_rdata;
    wire            usb_ready;

    wire [7:0]      sigtap_addr;
    wire [31:0]     sigtap_wdata;
    wire            sigtap_read;
    wire            sigtap_write;
    wire [31:0]     sigtap_rdata;
    wire            sigtap_ready;

    // DMA signals (disk controller)
    wire [31:0]     dma_addr;
    wire [31:0]     dma_wdata;
    wire            dma_write;

    // Signal Tap probe signals
    wire [31:0]     probes;

    //=========================================================================
    // TDO Multiplexing
    //=========================================================================
    assign tdo = (ir_value == 5'h10 || ir_value == 5'h11) ? dtm_tdo : tap_tdo;

    //=========================================================================
    // Output assignments
    //=========================================================================
    assign pll_locked = pll_locked_int;
    assign sys_rst_n = sys_rst_n_int;

    //=========================================================================
    // Signal Tap Probes
    //=========================================================================
    assign probes = {
        8'h00,                  // [31:24] Reserved
        motor_on, head_sel, dir, step,  // [23:20] Disk control
        flux_in, index_in, 2'b0,        // [19:16] Disk inputs
        usb_connected, usb_configured, 2'b0,  // [15:12] USB status
        pll_locked_int, sys_rst_n_int, 2'b0,  // [11:8] Clock/reset
        ir_value[4:0], 3'b0             // [7:0] JTAG state
    };

    //=========================================================================
    // Clock and Reset Manager
    //=========================================================================
    clock_reset_mgr u_clk_rst (
        .clk_ref        (clk_25m),
        .rst_ext_n      (rst_n),
        .clk_sys        (clk_sys),
        .clk_usb        (clk_usb),
        .clk_disk       (clk_disk),
        .pll_locked     (pll_locked_int),
        .rst_sys_n      (sys_rst_n_int),
        .rst_usb_n      (),
        .rst_disk_n     (),
        .rst_debug_n    (trst_n),
        .rst_dbg_sync_n (),
        .wdt_kick       (1'b1),         // Keep watchdog happy
        .wdt_reset      ()
    );

    //=========================================================================
    // JTAG TAP Controller
    //=========================================================================
    jtag_tap_controller #(
        .IDCODE(32'hFB010001),
        .IR_LENGTH(5)
    ) u_tap (
        .tck            (tck),
        .tms            (tms),
        .tdi            (tdi),
        .tdo            (tap_tdo),
        .trst_n         (trst_n),
        .ir_value       (ir_value),
        .dr_capture     (dr_capture),
        .dr_shift       (dr_shift),
        .dr_update      (dr_update)
    );

    //=========================================================================
    // Debug Transport Module
    //=========================================================================
    jtag_dtm u_dtm (
        .tck            (tck),
        .trst_n         (trst_n),
        .ir_value       (ir_value),
        .dr_capture     (dr_capture),
        .dr_shift       (dr_shift),
        .dr_update      (dr_update),
        .tdi            (tdi),
        .tdo            (dtm_tdo),
        .dmi_addr       (dmi_addr),
        .dmi_wdata      (dmi_wdata),
        .dmi_op         (dmi_op),
        .dmi_req        (dmi_req),
        .dmi_rdata      (dmi_rdata),
        .dmi_resp       (dmi_resp),
        .dmi_ack        (dmi_ack)
    );

    //=========================================================================
    // Debug Module
    //=========================================================================
    debug_module u_dm (
        .clk            (clk_sys),
        .rst_n          (sys_rst_n_int),
        .dmi_addr       (dmi_addr),
        .dmi_wdata      (dmi_wdata),
        .dmi_op         (dmi_op),
        .dmi_req        (dmi_req),
        .dmi_rdata      (dmi_rdata),
        .dmi_resp       (dmi_resp),
        .dmi_ack        (dmi_ack),
        .sbaddr         (sb_addr),
        .sbdata_o       (sb_wdata),
        .sbdata_i       (sb_rdata),
        .sbsize         (sb_size),
        .sbread         (sb_read),
        .sbwrite        (sb_write),
        .sbbusy         (sb_busy),
        .sberror        (sb_error)
    );

    //=========================================================================
    // System Bus Fabric
    //=========================================================================
    system_bus u_bus (
        .clk            (clk_sys),
        .rst_n          (sys_rst_n_int),
        // Master interface
        .m_addr         (sb_addr),
        .m_wdata        (sb_wdata),
        .m_rdata        (sb_rdata),
        .m_size         (sb_size),
        .m_read         (sb_read),
        .m_write        (sb_write),
        .m_busy         (sb_busy),
        .m_error        (sb_error),
        // ROM (slave 0)
        .s0_addr        (rom_addr),
        .s0_read        (rom_read),
        .s0_rdata       (rom_rdata),
        .s0_ready       (rom_ready),
        // RAM (slave 1)
        .s1_addr        (ram_addr),
        .s1_wdata       (ram_wdata),
        .s1_read        (ram_read),
        .s1_write       (ram_write),
        .s1_rdata       (ram_rdata),
        .s1_ready       (ram_ready),
        // System Control (slave 2)
        .s2_addr        (sysctrl_addr),
        .s2_wdata       (sysctrl_wdata),
        .s2_read        (sysctrl_read),
        .s2_write       (sysctrl_write),
        .s2_rdata       (sysctrl_rdata),
        .s2_ready       (sysctrl_ready),
        // Disk Controller (slave 3)
        .s3_addr        (disk_addr),
        .s3_wdata       (disk_wdata),
        .s3_read        (disk_read),
        .s3_write       (disk_write),
        .s3_rdata       (disk_rdata),
        .s3_ready       (disk_ready),
        // USB Controller (slave 4)
        .s4_addr        (usb_addr),
        .s4_wdata       (usb_wdata),
        .s4_read        (usb_read),
        .s4_write       (usb_write),
        .s4_rdata       (usb_rdata),
        .s4_ready       (usb_ready),
        // Signal Tap (slave 5)
        .s5_addr        (sigtap_addr),
        .s5_wdata       (sigtap_wdata),
        .s5_read        (sigtap_read),
        .s5_write       (sigtap_write),
        .s5_rdata       (sigtap_rdata),
        .s5_ready       (sigtap_ready)
    );

    //=========================================================================
    // System Control (simple ID register)
    //=========================================================================
    reg [31:0] sysctrl_id_reg;
    initial sysctrl_id_reg = 32'hFB010100;  // FluxRipper v1.0

    assign sysctrl_rdata = (sysctrl_addr == 8'h00) ? sysctrl_id_reg : 32'h0;
    assign sysctrl_ready = 1'b1;

    //=========================================================================
    // Boot ROM (BRAM for synthesis, behavioral for simulation)
    //=========================================================================
    // Use distributed RAM for low-latency debug access
    // For larger production ROM, would use external flash
    (* ram_style = "distributed" *) reg [31:0] rom_mem [0:16383];  // 64KB

    integer rom_i;
    initial begin
        for (rom_i = 0; rom_i < 16384; rom_i = rom_i + 1)
            rom_mem[rom_i] = 32'hB0070000 + rom_i;
        rom_mem[0] = 32'h13000000;  // NOP at reset vector
    end

    // Combinational read for zero-latency debug access
    assign rom_rdata = rom_mem[rom_addr[15:2]];
    assign rom_ready = 1'b1;

    //=========================================================================
    // Main RAM (BRAM for synthesis, behavioral for simulation)
    //=========================================================================
    // Use distributed RAM for low-latency debug access
    // For larger production RAM, would use external DDR/SRAM
    (* ram_style = "distributed" *) reg [31:0] ram_mem [0:16383];  // 64KB

    integer ram_i;
    initial begin
        for (ram_i = 0; ram_i < 16384; ram_i = ram_i + 1)
            ram_mem[ram_i] = 32'h5A000000 + ram_i;
    end

    // Combinational read for zero-latency debug access, registered write
    assign ram_rdata = ram_mem[ram_addr[15:2]];
    assign ram_ready = 1'b1;

    always @(posedge clk_sys) begin
        if (ram_write)
            ram_mem[ram_addr[15:2]] <= ram_wdata;
    end

    //=========================================================================
    // Disk Controller
    //=========================================================================
    disk_controller u_disk (
        .clk            (clk_sys),
        .rst_n          (sys_rst_n_int),
        .addr           (disk_addr),
        .wdata          (disk_wdata),
        .read           (disk_read),
        .write          (disk_write),
        .rdata          (disk_rdata),
        .ready          (disk_ready),
        .dma_addr       (dma_addr),
        .dma_wdata      (dma_wdata),
        .dma_write      (dma_write),
        .dma_ready      (1'b1),
        .flux_in        (flux_in),
        .index_in       (index_in),
        .motor_on       (motor_on),
        .head_sel       (head_sel),
        .dir            (dir),
        .step           (step)
    );

    //=========================================================================
    // USB Controller
    //=========================================================================
    usb_controller u_usb (
        .clk            (clk_sys),
        .rst_n          (sys_rst_n_int),
        .addr           (usb_addr),
        .wdata          (usb_wdata),
        .read           (usb_read),
        .write          (usb_write),
        .rdata          (usb_rdata),
        .ready          (usb_ready),
        .usb_connected  (usb_connected),
        .usb_configured (usb_configured)
    );

    //=========================================================================
    // Signal Tap
    //=========================================================================
    signal_tap #(
        .BUFFER_DEPTH(256),
        .PROBE_WIDTH(32)
    ) u_sigtap (
        .clk            (clk_sys),
        .rst_n          (sys_rst_n_int),
        .addr           (sigtap_addr),
        .wdata          (sigtap_wdata),
        .read           (sigtap_read),
        .write          (sigtap_write),
        .rdata          (sigtap_rdata),
        .ready          (sigtap_ready),
        .probes         (probes)
    );

endmodule
