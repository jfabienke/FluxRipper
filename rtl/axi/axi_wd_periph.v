//==============================================================================
// AXI4-Lite WD Controller Peripheral Interface
//==============================================================================
// File: axi_wd_periph.v
// Description: Bridges the WD1003/WD1006/WD1007 compatible HDD controller
//              registers to MicroBlaze V via AXI4-Lite. Provides memory-mapped
//              access to all WD registers plus extended configuration.
//
// Register Map (32-bit aligned, base 0x80007100):
//   0x00: WD_DATA         (r/w) - Data register (16-bit in lower half)
//   0x04: WD_ERROR_FEAT   (r/w) - Error (R) / Features (W)
//   0x08: WD_SECTOR_COUNT (r/w) - Sector count
//   0x0C: WD_SECTOR_NUM   (r/w) - Sector number
//   0x10: WD_CYL_LOW      (r/w) - Cylinder low byte
//   0x14: WD_CYL_HIGH     (r/w) - Cylinder high byte
//   0x18: WD_SDH          (r/w) - Size/Drive/Head
//   0x1C: WD_STATUS_CMD   (r/w) - Status (R) / Command (W)
//   0x20: WD_ALT_STATUS   (r/o) - Alternate status (no IRQ clear)
//   0x24: WD_CTRL         (r/w) - Control and feature flags
//   0x28: WD_BUFFER_ADDR  (r/w) - Track buffer address
//   0x2C: WD_BUFFER_DATA  (r/w) - Track buffer data access
//   0x30: WD_CONFIG       (r/w) - Variant configuration
//   0x34: WD_GEOMETRY     (r/w) - Drive geometry (C/H/S)
//   0x38: WD_DIAG_STATUS  (r/o) - Diagnostic status
//   0x3C: WD_VERSION      (r/o) - Hardware version
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-04
//==============================================================================

`timescale 1ns / 1ps

module axi_wd_periph #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6,     // 64 bytes address space
    parameter VERSION_MAJOR      = 1,
    parameter VERSION_MINOR      = 0,
    parameter VERSION_PATCH      = 0
)(
    //-------------------------------------------------------------------------
    // AXI4-Lite Slave Interface
    //-------------------------------------------------------------------------
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,

    // Write address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,

    // Write data channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0]   s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,

    // Write response channel
    output wire [1:0]                        s_axi_bresp,
    output wire                              s_axi_bvalid,
    input  wire                              s_axi_bready,

    // Read address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,

    // Read data channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                        s_axi_rresp,
    output wire                              s_axi_rvalid,
    input  wire                              s_axi_rready,

    //-------------------------------------------------------------------------
    // WD Register Interface (to wd_registers module)
    //-------------------------------------------------------------------------
    output reg  [2:0]  wd_reg_addr,       // Register address (0-7)
    output reg  [7:0]  wd_reg_wdata,      // Write data
    output reg         wd_reg_write,      // Write strobe
    output reg         wd_reg_read,       // Read strobe
    input  wire [7:0]  wd_reg_rdata,      // Read data

    //-------------------------------------------------------------------------
    // Status from WD Register File
    //-------------------------------------------------------------------------
    input  wire [7:0]  wd_status,         // Status register value
    input  wire [7:0]  wd_error,          // Error register value
    input  wire [15:0] wd_cylinder,       // Current cylinder
    input  wire [3:0]  wd_head,           // Current head
    input  wire [7:0]  wd_sector_num,     // Current sector
    input  wire [7:0]  wd_sector_count,   // Remaining sectors

    //-------------------------------------------------------------------------
    // Track Buffer Interface
    //-------------------------------------------------------------------------
    output reg  [13:0] buf_addr,          // Buffer address (0-8703 for 17 sectors)
    output reg  [7:0]  buf_wdata,         // Buffer write data
    output reg         buf_write,         // Buffer write enable
    input  wire [7:0]  buf_rdata,         // Buffer read data

    //-------------------------------------------------------------------------
    // Configuration Outputs
    //-------------------------------------------------------------------------
    output reg  [2:0]  wd_variant,        // 0=WD1003, 1=WD1006, 2=WD1007
    output reg  [31:0] wd_features,       // Feature flags (from wd_generic.h)
    output reg  [15:0] wd_cylinders,      // Max cylinders
    output reg  [3:0]  wd_heads,          // Max heads
    output reg  [7:0]  wd_spt,            // Sectors per track

    //-------------------------------------------------------------------------
    // Interrupt Interface
    //-------------------------------------------------------------------------
    input  wire        wd_irq_in,         // IRQ from WD register file
    output reg         irq_enable,        // IRQ enable
    output wire        irq                // Interrupt to CPU
);

    //-------------------------------------------------------------------------
    // Register Address Offsets (within 64-byte space)
    //-------------------------------------------------------------------------
    localparam ADDR_DATA         = 6'h00;
    localparam ADDR_ERROR_FEAT   = 6'h04;
    localparam ADDR_SECTOR_COUNT = 6'h08;
    localparam ADDR_SECTOR_NUM   = 6'h0C;
    localparam ADDR_CYL_LOW      = 6'h10;
    localparam ADDR_CYL_HIGH     = 6'h14;
    localparam ADDR_SDH          = 6'h18;
    localparam ADDR_STATUS_CMD   = 6'h1C;
    localparam ADDR_ALT_STATUS   = 6'h20;
    localparam ADDR_CTRL         = 6'h24;
    localparam ADDR_BUFFER_ADDR  = 6'h28;
    localparam ADDR_BUFFER_DATA  = 6'h2C;
    localparam ADDR_CONFIG       = 6'h30;
    localparam ADDR_GEOMETRY     = 6'h34;
    localparam ADDR_DIAG_STATUS  = 6'h38;
    localparam ADDR_VERSION      = 6'h3C;

    //-------------------------------------------------------------------------
    // AXI4-Lite State Machine
    //-------------------------------------------------------------------------
    reg [1:0] axi_state;
    localparam AXI_IDLE  = 2'b00;
    localparam AXI_WRITE = 2'b01;
    localparam AXI_READ  = 2'b10;
    localparam AXI_RESP  = 2'b11;

    //-------------------------------------------------------------------------
    // Internal Registers
    //-------------------------------------------------------------------------
    reg [C_S_AXI_ADDR_WIDTH-1:0] latched_addr;
    reg [C_S_AXI_DATA_WIDTH-1:0] read_data;
    reg                          axi_awready_r;
    reg                          axi_wready_r;
    reg                          axi_bvalid_r;
    reg                          axi_arready_r;
    reg                          axi_rvalid_r;

    // Extended registers (not in wd_registers)
    reg [13:0] r_buffer_addr;
    reg [31:0] r_diag_status;

    //-------------------------------------------------------------------------
    // AXI Output Assignments
    //-------------------------------------------------------------------------
    assign s_axi_awready = axi_awready_r;
    assign s_axi_wready  = axi_wready_r;
    assign s_axi_bresp   = 2'b00;  // OKAY response
    assign s_axi_bvalid  = axi_bvalid_r;
    assign s_axi_arready = axi_arready_r;
    assign s_axi_rdata   = read_data;
    assign s_axi_rresp   = 2'b00;  // OKAY response
    assign s_axi_rvalid  = axi_rvalid_r;

    // Interrupt output
    assign irq = wd_irq_in && irq_enable;

    //-------------------------------------------------------------------------
    // Version Register
    //-------------------------------------------------------------------------
    wire [31:0] version_reg = {8'h00, VERSION_MAJOR[7:0], VERSION_MINOR[7:0], VERSION_PATCH[7:0]};

    //-------------------------------------------------------------------------
    // AXI4-Lite State Machine
    //-------------------------------------------------------------------------
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            axi_state      <= AXI_IDLE;
            axi_awready_r  <= 1'b0;
            axi_wready_r   <= 1'b0;
            axi_bvalid_r   <= 1'b0;
            axi_arready_r  <= 1'b0;
            axi_rvalid_r   <= 1'b0;
            latched_addr   <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            read_data      <= 32'h00000000;
            wd_reg_addr    <= 3'b000;
            wd_reg_wdata   <= 8'h00;
            wd_reg_write   <= 1'b0;
            wd_reg_read    <= 1'b0;
            buf_addr       <= 14'h0000;
            buf_wdata      <= 8'h00;
            buf_write      <= 1'b0;
            r_buffer_addr  <= 14'h0000;
            wd_variant     <= 3'b000;     // WD1003 default
            wd_features    <= 32'h00000000;
            wd_cylinders   <= 16'd615;    // ST-225 default
            wd_heads       <= 4'd4;
            wd_spt         <= 8'd17;
            irq_enable     <= 1'b0;
            r_diag_status  <= 32'h00000000;
        end else begin
            // Default: clear single-cycle signals
            wd_reg_write <= 1'b0;
            wd_reg_read  <= 1'b0;
            buf_write    <= 1'b0;

            case (axi_state)
                AXI_IDLE: begin
                    axi_bvalid_r <= 1'b0;
                    axi_rvalid_r <= 1'b0;

                    // Check for write transaction
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        latched_addr  <= s_axi_awaddr;
                        axi_awready_r <= 1'b1;
                        axi_wready_r  <= 1'b1;
                        axi_state     <= AXI_WRITE;
                    end
                    // Check for read transaction
                    else if (s_axi_arvalid) begin
                        latched_addr  <= s_axi_araddr;
                        axi_arready_r <= 1'b1;
                        axi_state     <= AXI_READ;
                    end
                end

                AXI_WRITE: begin
                    axi_awready_r <= 1'b0;
                    axi_wready_r  <= 1'b0;

                    // Decode write address and perform write
                    case (latched_addr[5:0])
                        ADDR_DATA: begin
                            wd_reg_addr  <= 3'h0;  // DATA register
                            wd_reg_wdata <= s_axi_wdata[7:0];
                            wd_reg_write <= 1'b1;
                        end

                        ADDR_ERROR_FEAT: begin
                            wd_reg_addr  <= 3'h1;  // FEATURES register
                            wd_reg_wdata <= s_axi_wdata[7:0];
                            wd_reg_write <= 1'b1;
                        end

                        ADDR_SECTOR_COUNT: begin
                            wd_reg_addr  <= 3'h2;
                            wd_reg_wdata <= s_axi_wdata[7:0];
                            wd_reg_write <= 1'b1;
                        end

                        ADDR_SECTOR_NUM: begin
                            wd_reg_addr  <= 3'h3;
                            wd_reg_wdata <= s_axi_wdata[7:0];
                            wd_reg_write <= 1'b1;
                        end

                        ADDR_CYL_LOW: begin
                            wd_reg_addr  <= 3'h4;
                            wd_reg_wdata <= s_axi_wdata[7:0];
                            wd_reg_write <= 1'b1;
                        end

                        ADDR_CYL_HIGH: begin
                            wd_reg_addr  <= 3'h5;
                            wd_reg_wdata <= s_axi_wdata[7:0];
                            wd_reg_write <= 1'b1;
                        end

                        ADDR_SDH: begin
                            wd_reg_addr  <= 3'h6;
                            wd_reg_wdata <= s_axi_wdata[7:0];
                            wd_reg_write <= 1'b1;
                        end

                        ADDR_STATUS_CMD: begin
                            wd_reg_addr  <= 3'h7;  // Command register
                            wd_reg_wdata <= s_axi_wdata[7:0];
                            wd_reg_write <= 1'b1;
                        end

                        ADDR_CTRL: begin
                            irq_enable <= s_axi_wdata[0];
                            // Additional control bits can be added here
                        end

                        ADDR_BUFFER_ADDR: begin
                            r_buffer_addr <= s_axi_wdata[13:0];
                            buf_addr      <= s_axi_wdata[13:0];
                        end

                        ADDR_BUFFER_DATA: begin
                            buf_wdata <= s_axi_wdata[7:0];
                            buf_write <= 1'b1;
                            // Auto-increment buffer address
                            r_buffer_addr <= r_buffer_addr + 1'b1;
                            buf_addr      <= r_buffer_addr + 1'b1;
                        end

                        ADDR_CONFIG: begin
                            wd_variant  <= s_axi_wdata[2:0];
                            wd_features <= s_axi_wdata;
                        end

                        ADDR_GEOMETRY: begin
                            wd_cylinders <= s_axi_wdata[15:0];
                            wd_heads     <= s_axi_wdata[19:16];
                            wd_spt       <= s_axi_wdata[27:20];
                        end

                        default: ;  // Ignore writes to read-only registers
                    endcase

                    axi_bvalid_r <= 1'b1;
                    axi_state    <= AXI_RESP;
                end

                AXI_READ: begin
                    axi_arready_r <= 1'b0;

                    // Decode read address and return data
                    case (latched_addr[5:0])
                        ADDR_DATA: begin
                            wd_reg_addr <= 3'h0;
                            wd_reg_read <= 1'b1;
                            read_data   <= {24'h000000, wd_reg_rdata};
                        end

                        ADDR_ERROR_FEAT: begin
                            read_data <= {24'h000000, wd_error};
                        end

                        ADDR_SECTOR_COUNT: begin
                            read_data <= {24'h000000, wd_sector_count};
                        end

                        ADDR_SECTOR_NUM: begin
                            read_data <= {24'h000000, wd_sector_num};
                        end

                        ADDR_CYL_LOW: begin
                            read_data <= {24'h000000, wd_cylinder[7:0]};
                        end

                        ADDR_CYL_HIGH: begin
                            read_data <= {24'h000000, wd_cylinder[15:8]};
                        end

                        ADDR_SDH: begin
                            wd_reg_addr <= 3'h6;
                            wd_reg_read <= 1'b1;
                            read_data   <= {24'h000000, wd_reg_rdata};
                        end

                        ADDR_STATUS_CMD: begin
                            read_data <= {24'h000000, wd_status};
                            // Note: Reading status clears IRQ (handled in wd_registers)
                        end

                        ADDR_ALT_STATUS: begin
                            // Alternate status - doesn't clear IRQ
                            read_data <= {24'h000000, wd_status};
                        end

                        ADDR_CTRL: begin
                            read_data <= {31'h00000000, irq_enable};
                        end

                        ADDR_BUFFER_ADDR: begin
                            read_data <= {18'h00000, r_buffer_addr};
                        end

                        ADDR_BUFFER_DATA: begin
                            read_data <= {24'h000000, buf_rdata};
                            // Auto-increment buffer address
                            r_buffer_addr <= r_buffer_addr + 1'b1;
                            buf_addr      <= r_buffer_addr + 1'b1;
                        end

                        ADDR_CONFIG: begin
                            read_data <= wd_features;
                        end

                        ADDR_GEOMETRY: begin
                            read_data <= {4'h0, wd_spt, wd_heads, wd_cylinders};
                        end

                        ADDR_DIAG_STATUS: begin
                            read_data <= r_diag_status;
                        end

                        ADDR_VERSION: begin
                            read_data <= version_reg;
                        end

                        default: begin
                            read_data <= 32'h00000000;
                        end
                    endcase

                    axi_rvalid_r <= 1'b1;
                    axi_state    <= AXI_RESP;
                end

                AXI_RESP: begin
                    // Wait for master to accept response
                    if ((axi_bvalid_r && s_axi_bready) || (axi_rvalid_r && s_axi_rready)) begin
                        axi_bvalid_r <= 1'b0;
                        axi_rvalid_r <= 1'b0;
                        axi_state    <= AXI_IDLE;
                    end
                end

                default: begin
                    axi_state <= AXI_IDLE;
                end
            endcase
        end
    end

endmodule
