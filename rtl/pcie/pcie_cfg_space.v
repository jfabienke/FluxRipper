//==============================================================================
// PCIe Configuration Space
//==============================================================================
// File: pcie_cfg_space.v
// Description: PCIe Type 0 configuration space implementation for FluxRipper.
//              Multi-function device with FDC (Function 0) and WD HDD (Function 1).
//
// Configuration:
//   - PCIe 2.0 Gen2 x1
//   - Vendor ID: 0x1234 (placeholder - needs PCISIG registration)
//   - Device ID: 0xFDC0 (FDC), 0xHDD0 (WD HDD)
//   - Class Code: 0x010100 (IDE Controller)
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04 23:40
//==============================================================================

`timescale 1ns / 1ps

module pcie_cfg_space #(
    parameter VENDOR_ID       = 16'h1234,    // Placeholder vendor ID
    parameter FDC_DEVICE_ID   = 16'hFDC0,    // FDC device ID
    parameter WD_DEVICE_ID    = 16'hHDD0,    // WD HDD device ID
    parameter REVISION_ID     = 8'h01,       // Revision 1.0
    parameter SUBSYS_VENDOR   = 16'h1234,    // Subsystem vendor
    parameter SUBSYS_ID       = 16'h0001     // Subsystem ID
)(
    input  wire        clk,
    input  wire        reset_n,

    //=========================================================================
    // Configuration Access Interface
    //=========================================================================
    input  wire [11:0] cfg_addr,         // Config address (Function[2:0], Register[9:2])
    input  wire [31:0] cfg_wdata,        // Config write data
    input  wire [3:0]  cfg_be,           // Byte enables
    input  wire        cfg_write,        // Write strobe
    input  wire        cfg_read,         // Read strobe
    output reg  [31:0] cfg_rdata,        // Config read data
    output reg         cfg_ready,        // Access complete

    //=========================================================================
    // BAR Outputs
    //=========================================================================
    output reg  [31:0] bar0_addr,        // BAR0 base address (FDC)
    output reg  [31:0] bar1_addr,        // BAR1 base address (WD HDD)
    output reg  [31:0] bar2_addr,        // BAR2 base address (DMA buffer)
    output reg         bar0_enabled,     // BAR0 memory space enabled
    output reg         bar1_enabled,     // BAR1 memory space enabled
    output reg         bar2_enabled,     // BAR2 memory space enabled

    //=========================================================================
    // Command/Status
    //=========================================================================
    output reg         bus_master_en,    // Bus master enable
    output reg         mem_space_en,     // Memory space enable
    output reg         io_space_en,      // I/O space enable
    output reg         intx_disable,     // INTx disable (use MSI)
    output reg         serr_enable,      // SERR# enable

    //=========================================================================
    // Interrupt Status
    //=========================================================================
    input  wire        int_status,       // Interrupt pending
    output reg  [7:0]  int_line,         // Interrupt line
    output reg  [7:0]  int_pin,          // Interrupt pin

    //=========================================================================
    // MSI Configuration
    //=========================================================================
    output reg         msi_enable,       // MSI enabled
    output reg  [63:0] msi_addr,         // MSI address
    output reg  [15:0] msi_data,         // MSI data
    output reg  [2:0]  msi_multiple_msg, // Multiple message capable (log2)

    //=========================================================================
    // Power Management
    //=========================================================================
    output reg  [1:0]  power_state,      // D0-D3 power state
    input  wire        pme_status,       // PME status
    output reg         pme_enable        // PME enable
);

    //=========================================================================
    // Function Selection
    //=========================================================================
    wire [2:0] func_num = cfg_addr[11:9];
    wire [7:0] reg_num  = {cfg_addr[8:2], 2'b00};  // DWORD aligned

    wire func0_sel = (func_num == 3'b000);  // FDC
    wire func1_sel = (func_num == 3'b001);  // WD HDD

    //=========================================================================
    // Configuration Registers - Common
    //=========================================================================
    // Command register bits
    reg        cmd_io_space;
    reg        cmd_mem_space;
    reg        cmd_bus_master;
    reg        cmd_special_cycles;
    reg        cmd_mwi_enable;
    reg        cmd_vga_palette;
    reg        cmd_parity_err;
    reg        cmd_serr_enable;
    reg        cmd_fast_b2b;
    reg        cmd_intx_disable;

    // Status register bits (directly connected or read-only)
    wire       stat_intx_status = int_status;
    wire       stat_cap_list = 1'b1;           // Capabilities list present
    wire       stat_66mhz_cap = 1'b0;          // Not 66MHz capable
    wire       stat_fast_b2b_cap = 1'b0;       // No fast B2B
    wire       stat_parity_err = 1'b0;         // No parity error
    wire [1:0] stat_devsel = 2'b00;            // Fast DEVSEL
    wire       stat_sig_tgt_abort = 1'b0;
    wire       stat_rec_tgt_abort = 1'b0;
    wire       stat_rec_mst_abort = 1'b0;
    wire       stat_sig_sys_err = 1'b0;
    wire       stat_det_parity_err = 1'b0;

    //=========================================================================
    // BAR Size Masks (for BAR sizing)
    //=========================================================================
    // BAR0: 4KB memory (0xFFFFF000)
    // BAR1: 4KB memory (0xFFFFF000)
    // BAR2: 64KB memory (0xFFFF0000)
    localparam [31:0] BAR0_MASK = 32'hFFFFF000;
    localparam [31:0] BAR1_MASK = 32'hFFFFF000;
    localparam [31:0] BAR2_MASK = 32'hFFFF0000;

    // BAR type bits (memory, 32-bit, non-prefetchable)
    localparam [3:0] BAR_TYPE_MEM32 = 4'b0000;

    //=========================================================================
    // Capability Pointer
    //=========================================================================
    localparam CAP_PTR = 8'h40;          // First capability at 0x40
    localparam MSI_CAP_OFFSET = 8'h40;   // MSI capability
    localparam PM_CAP_OFFSET  = 8'h50;   // Power Management capability
    localparam PCIE_CAP_OFFSET = 8'h60;  // PCIe capability

    //=========================================================================
    // Configuration Read
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cfg_rdata <= 32'h0;
            cfg_ready <= 1'b0;
        end else begin
            cfg_ready <= cfg_read || cfg_write;

            if (cfg_read) begin
                case (reg_num)
                    //=========================================================
                    // Standard Type 0 Header (0x00-0x3F)
                    //=========================================================

                    // 0x00: Device ID / Vendor ID
                    8'h00: cfg_rdata <= func0_sel ?
                                        {FDC_DEVICE_ID, VENDOR_ID} :
                                        {WD_DEVICE_ID, VENDOR_ID};

                    // 0x04: Status / Command
                    8'h04: cfg_rdata <= {
                        stat_det_parity_err,    // [31]
                        stat_sig_sys_err,       // [30]
                        stat_rec_mst_abort,     // [29]
                        stat_rec_tgt_abort,     // [28]
                        stat_sig_tgt_abort,     // [27]
                        stat_devsel,            // [26:25]
                        stat_parity_err,        // [24]
                        stat_fast_b2b_cap,      // [23]
                        1'b0,                   // [22] Reserved
                        stat_66mhz_cap,         // [21]
                        stat_cap_list,          // [20]
                        stat_intx_status,       // [19]
                        3'b0,                   // [18:16] Reserved
                        6'b0,                   // [15:10] Reserved
                        cmd_intx_disable,       // [10]
                        cmd_fast_b2b,           // [9]
                        cmd_serr_enable,        // [8]
                        1'b0,                   // [7] Reserved
                        cmd_parity_err,         // [6]
                        cmd_vga_palette,        // [5]
                        cmd_mwi_enable,         // [4]
                        cmd_special_cycles,     // [3]
                        cmd_bus_master,         // [2]
                        cmd_mem_space,          // [1]
                        cmd_io_space            // [0]
                    };

                    // 0x08: Class Code / Revision ID
                    8'h08: cfg_rdata <= {
                        8'h01,                  // Base class: Mass Storage
                        8'h01,                  // Sub class: IDE
                        8'h00,                  // Prog IF: ISA Compatibility
                        REVISION_ID             // Revision
                    };

                    // 0x0C: BIST / Header Type / Latency Timer / Cache Line
                    8'h0C: cfg_rdata <= {
                        8'h00,                  // BIST (not supported)
                        8'h80,                  // Header type 0, multi-function
                        8'h00,                  // Latency timer
                        8'h00                   // Cache line size
                    };

                    // 0x10: BAR0 (FDC registers)
                    8'h10: cfg_rdata <= {bar0_addr[31:12], 8'h0, BAR_TYPE_MEM32};

                    // 0x14: BAR1 (WD HDD registers)
                    8'h14: cfg_rdata <= {bar1_addr[31:12], 8'h0, BAR_TYPE_MEM32};

                    // 0x18: BAR2 (DMA buffer)
                    8'h18: cfg_rdata <= {bar2_addr[31:16], 12'h0, BAR_TYPE_MEM32};

                    // 0x1C-0x24: BAR3-5 (not used)
                    8'h1C, 8'h20, 8'h24: cfg_rdata <= 32'h0;

                    // 0x28: Cardbus CIS Pointer (not used)
                    8'h28: cfg_rdata <= 32'h0;

                    // 0x2C: Subsystem ID / Subsystem Vendor ID
                    8'h2C: cfg_rdata <= {SUBSYS_ID, SUBSYS_VENDOR};

                    // 0x30: Expansion ROM (not used)
                    8'h30: cfg_rdata <= 32'h0;

                    // 0x34: Capabilities Pointer
                    8'h34: cfg_rdata <= {24'h0, CAP_PTR};

                    // 0x38: Reserved
                    8'h38: cfg_rdata <= 32'h0;

                    // 0x3C: Max_Lat / Min_Gnt / Int Pin / Int Line
                    8'h3C: cfg_rdata <= {
                        8'h00,                  // Max_Lat
                        8'h00,                  // Min_Gnt
                        int_pin,                // Interrupt Pin
                        int_line                // Interrupt Line
                    };

                    //=========================================================
                    // MSI Capability (0x40-0x4F)
                    //=========================================================

                    // 0x40: MSI Capability Header
                    8'h40: cfg_rdata <= {
                        16'h0000,               // Message Control (filled below)
                        PM_CAP_OFFSET,          // Next capability
                        8'h05                   // MSI Capability ID
                    };

                    // 0x44: MSI Address Low
                    8'h44: cfg_rdata <= msi_addr[31:0];

                    // 0x48: MSI Address High
                    8'h48: cfg_rdata <= msi_addr[63:32];

                    // 0x4C: MSI Data
                    8'h4C: cfg_rdata <= {16'h0, msi_data};

                    //=========================================================
                    // Power Management Capability (0x50-0x57)
                    //=========================================================

                    // 0x50: PM Capability Header
                    8'h50: cfg_rdata <= {
                        16'hC803,               // PMC (D1, D2 support, etc.)
                        PCIE_CAP_OFFSET,        // Next capability
                        8'h01                   // PM Capability ID
                    };

                    // 0x54: PM Control/Status
                    8'h54: cfg_rdata <= {
                        8'h00,                  // Data
                        6'b0,                   // Reserved
                        pme_status,             // PME_Status
                        1'b0,                   // Data_Scale
                        1'b0,                   // Data_Select
                        pme_enable,             // PME_En
                        4'b0,                   // Reserved
                        power_state             // PowerState
                    };

                    //=========================================================
                    // PCIe Capability (0x60-0x7F)
                    //=========================================================

                    // 0x60: PCIe Capability Header
                    8'h60: cfg_rdata <= {
                        16'h0012,               // PCIe Caps (v2, Endpoint)
                        8'h00,                  // Next capability (none)
                        8'h10                   // PCIe Capability ID
                    };

                    // 0x64: Device Capabilities
                    8'h64: cfg_rdata <= {
                        3'b0,                   // Reserved
                        1'b0,                   // FLR capable
                        3'b000,                 // Captured slot power scale
                        8'h00,                  // Captured slot power limit
                        1'b0,                   // Role-based error reporting
                        1'b0,                   // Reserved
                        3'b000,                 // Endpoint L1 latency
                        3'b000,                 // Endpoint L0s latency
                        1'b0,                   // Extended tag
                        2'b00,                  // Phantom functions
                        3'b001                  // Max payload 256 bytes
                    };

                    // 0x68: Device Control / Status
                    8'h68: cfg_rdata <= 32'h0;

                    // 0x6C: Link Capabilities
                    8'h6C: cfg_rdata <= {
                        8'h01,                  // Port number
                        2'b00,                  // Reserved
                        1'b0,                   // ASPM optionality
                        3'b010,                 // L1 exit latency (2-4us)
                        3'b010,                 // L0s exit latency (256-512ns)
                        2'b11,                  // ASPM support (L0s, L1)
                        4'b0001,                // Max link width (x1)
                        4'b0010                 // Max link speed (5 GT/s)
                    };

                    // 0x70: Link Control / Status
                    8'h70: cfg_rdata <= {
                        1'b0,                   // Link autonomous BW status
                        1'b0,                   // Link BW management status
                        1'b0,                   // DLL link active
                        1'b0,                   // Slot clock config
                        1'b1,                   // Link training
                        1'b0,                   // Undefined
                        4'b0001,                // Negotiated link width (x1)
                        4'b0010,                // Link speed (5 GT/s)
                        16'h0                   // Link control
                    };

                    default: cfg_rdata <= 32'h0;
                endcase
            end
        end
    end

    //=========================================================================
    // Configuration Write
    //=========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Command register defaults
            cmd_io_space      <= 1'b0;
            cmd_mem_space     <= 1'b0;
            cmd_bus_master    <= 1'b0;
            cmd_special_cycles <= 1'b0;
            cmd_mwi_enable    <= 1'b0;
            cmd_vga_palette   <= 1'b0;
            cmd_parity_err    <= 1'b0;
            cmd_serr_enable   <= 1'b0;
            cmd_fast_b2b      <= 1'b0;
            cmd_intx_disable  <= 1'b0;

            // BAR defaults
            bar0_addr <= 32'h0;
            bar1_addr <= 32'h0;
            bar2_addr <= 32'h0;

            // Interrupt
            int_line <= 8'h0;
            int_pin  <= 8'h01;  // INTA#

            // MSI
            msi_enable <= 1'b0;
            msi_addr   <= 64'h0;
            msi_data   <= 16'h0;
            msi_multiple_msg <= 3'b000;

            // Power management
            power_state <= 2'b00;  // D0
            pme_enable  <= 1'b0;

        end else if (cfg_write) begin
            case (reg_num)
                // 0x04: Command register
                8'h04: begin
                    if (cfg_be[0]) begin
                        cmd_io_space      <= cfg_wdata[0];
                        cmd_mem_space     <= cfg_wdata[1];
                        cmd_bus_master    <= cfg_wdata[2];
                        cmd_special_cycles <= cfg_wdata[3];
                        cmd_mwi_enable    <= cfg_wdata[4];
                        cmd_vga_palette   <= cfg_wdata[5];
                        cmd_parity_err    <= cfg_wdata[6];
                    end
                    if (cfg_be[1]) begin
                        cmd_serr_enable   <= cfg_wdata[8];
                        cmd_fast_b2b      <= cfg_wdata[9];
                        cmd_intx_disable  <= cfg_wdata[10];
                    end
                end

                // 0x10: BAR0
                8'h10: begin
                    if (cfg_wdata == 32'hFFFFFFFF) begin
                        // BAR sizing - return size mask
                        bar0_addr <= BAR0_MASK;
                    end else begin
                        bar0_addr <= cfg_wdata & BAR0_MASK;
                    end
                end

                // 0x14: BAR1
                8'h14: begin
                    if (cfg_wdata == 32'hFFFFFFFF) begin
                        bar1_addr <= BAR1_MASK;
                    end else begin
                        bar1_addr <= cfg_wdata & BAR1_MASK;
                    end
                end

                // 0x18: BAR2
                8'h18: begin
                    if (cfg_wdata == 32'hFFFFFFFF) begin
                        bar2_addr <= BAR2_MASK;
                    end else begin
                        bar2_addr <= cfg_wdata & BAR2_MASK;
                    end
                end

                // 0x3C: Interrupt Line
                8'h3C: begin
                    if (cfg_be[0]) int_line <= cfg_wdata[7:0];
                end

                // 0x44: MSI Address Low
                8'h44: msi_addr[31:0] <= cfg_wdata;

                // 0x48: MSI Address High
                8'h48: msi_addr[63:32] <= cfg_wdata;

                // 0x4C: MSI Data
                8'h4C: msi_data <= cfg_wdata[15:0];

                // 0x54: PM Control/Status
                8'h54: begin
                    if (cfg_be[0]) power_state <= cfg_wdata[1:0];
                    if (cfg_be[1]) pme_enable <= cfg_wdata[8];
                end

                default: ;  // Ignore writes to other registers
            endcase
        end
    end

    //=========================================================================
    // Output Assignments
    //=========================================================================
    always @(*) begin
        bus_master_en = cmd_bus_master;
        mem_space_en  = cmd_mem_space;
        io_space_en   = cmd_io_space;
        intx_disable  = cmd_intx_disable;
        serr_enable   = cmd_serr_enable;

        bar0_enabled  = cmd_mem_space && (bar0_addr != 32'h0);
        bar1_enabled  = cmd_mem_space && (bar1_addr != 32'h0);
        bar2_enabled  = cmd_mem_space && (bar2_addr != 32'h0);
    end

endmodule
