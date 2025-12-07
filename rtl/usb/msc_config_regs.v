//-----------------------------------------------------------------------------
// msc_config_regs.v
// MSC Configuration Register Block
//
// Created: 2025-12-05 21:50
// Updated: 2025-12-06 00:17 - Added media change interrupt support
//
// Provides AXI-Lite accessible registers for USB Mass Storage configuration.
// Firmware writes drive geometry after profile detection; RTL reads for
// SCSI READ_CAPACITY responses.
//
// Register Map (active bits only):
//   0x00  CTRL           - [0]=config_valid, [1]=force_update
//   0x04  STATUS         - [3:0]=present, [7:4]=changed, [15:8]=state
//   0x08  INT_CTRL       - [3:0]=int_enable, [7:4]=int_pending (read-only), [8]=global_int_en
//   0x10  FDD0_GEOMETRY  - [15:0]=sectors, [23:16]=tracks, [27:24]=heads, [31:28]=spt
//   0x14  FDD1_GEOMETRY  - [15:0]=sectors, [23:16]=tracks, [27:24]=heads, [31:28]=spt
//   0x20  HDD0_CAP_LO    - [31:0]=sectors[31:0]
//   0x24  HDD0_CAP_HI    - [31:0]=sectors[63:32]
//   0x28  HDD1_CAP_LO    - [31:0]=sectors[31:0]
//   0x2C  HDD1_CAP_HI    - [31:0]=sectors[63:32]
//   0x30  DRIVE_STATUS   - [3:0]=ready, [7:4]=changed, [11:8]=wp
//-----------------------------------------------------------------------------

module msc_config_regs (
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // AXI-Lite Slave Interface
    //=========================================================================
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    //=========================================================================
    // Configuration Outputs (to usb_top)
    //=========================================================================
    output wire        config_valid,
    output wire [15:0] fdd0_sectors,
    output wire [15:0] fdd1_sectors,
    output wire [31:0] hdd0_sectors,
    output wire [31:0] hdd1_sectors,
    output wire [3:0]  drive_ready,       // [0]=FDD0, [1]=FDD1, [2]=HDD0, [3]=HDD1
    output wire [3:0]  drive_wp,          // Write protect per drive

    //=========================================================================
    // Status Inputs (from usb_top / drive interface)
    //=========================================================================
    input  wire [3:0]  drive_present,     // Physical drive presence
    input  wire [3:0]  media_changed_in,  // Media change detection (directly from hardware)

    //=========================================================================
    // Interrupt Output
    //=========================================================================
    output wire        irq_media_change   // Media change interrupt (active high)
);

    //=========================================================================
    // Register Addresses
    //=========================================================================
    localparam ADDR_CTRL          = 8'h00;
    localparam ADDR_STATUS        = 8'h04;
    localparam ADDR_INT_CTRL      = 8'h08;
    localparam ADDR_FDD0_GEOMETRY = 8'h10;
    localparam ADDR_FDD1_GEOMETRY = 8'h14;
    localparam ADDR_HDD0_CAP_LO   = 8'h20;
    localparam ADDR_HDD0_CAP_HI   = 8'h24;
    localparam ADDR_HDD1_CAP_LO   = 8'h28;
    localparam ADDR_HDD1_CAP_HI   = 8'h2C;
    localparam ADDR_DRIVE_STATUS  = 8'h30;

    //=========================================================================
    // Registers
    //=========================================================================
    reg [31:0] reg_ctrl;
    reg [31:0] reg_fdd0_geometry;
    reg [31:0] reg_fdd1_geometry;
    reg [31:0] reg_hdd0_cap_lo;
    reg [31:0] reg_hdd0_cap_hi;
    reg [31:0] reg_hdd1_cap_lo;
    reg [31:0] reg_hdd1_cap_hi;
    reg [31:0] reg_drive_status;

    // Media changed latches (set by hardware, cleared by firmware write)
    reg [3:0]  media_changed_latch;
    reg [3:0]  media_changed_prev;

    // Interrupt control
    reg [3:0]  int_enable;          // Per-drive interrupt enable
    reg        global_int_enable;   // Global interrupt enable

    //=========================================================================
    // AXI Write State Machine
    //=========================================================================
    reg [7:0]  write_addr;
    reg        write_addr_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            write_addr    <= 8'h0;
            write_addr_valid <= 1'b0;

            reg_ctrl          <= 32'h0;
            reg_fdd0_geometry <= 32'h00120B40;  // Default: 2880 sectors, 80 tracks, 2 heads, 18 spt
            reg_fdd1_geometry <= 32'h00120B40;  // Default: 2880 sectors
            reg_hdd0_cap_lo   <= 32'h0;
            reg_hdd0_cap_hi   <= 32'h0;
            reg_hdd1_cap_lo   <= 32'h0;
            reg_hdd1_cap_hi   <= 32'h0;
            reg_drive_status  <= 32'h0;

            media_changed_latch <= 4'b0;
            media_changed_prev  <= 4'b0;

            int_enable          <= 4'b0;
            global_int_enable   <= 1'b0;
        end else begin
            // Default: ready for address
            if (!write_addr_valid)
                s_axi_awready <= 1'b1;

            // Latch write address
            if (s_axi_awvalid && s_axi_awready) begin
                write_addr <= s_axi_awaddr;
                write_addr_valid <= 1'b1;
                s_axi_awready <= 1'b0;
                s_axi_wready <= 1'b1;
            end

            // Process write data
            if (s_axi_wvalid && s_axi_wready && write_addr_valid) begin
                s_axi_wready <= 1'b0;
                write_addr_valid <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;  // OKAY

                case (write_addr)
                    ADDR_CTRL: begin
                        if (s_axi_wstrb[0]) reg_ctrl[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_ctrl[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_ctrl[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_ctrl[31:24] <= s_axi_wdata[31:24];
                    end

                    ADDR_INT_CTRL: begin
                        // [3:0] = per-drive interrupt enable
                        // [7:4] = interrupt pending (read-only, write-1-to-clear)
                        // [8]   = global interrupt enable
                        if (s_axi_wstrb[0]) begin
                            int_enable <= s_axi_wdata[3:0];
                            // Write 1 to [7:4] clears pending bits
                            if (s_axi_wdata[4]) media_changed_latch[0] <= 1'b0;
                            if (s_axi_wdata[5]) media_changed_latch[1] <= 1'b0;
                            if (s_axi_wdata[6]) media_changed_latch[2] <= 1'b0;
                            if (s_axi_wdata[7]) media_changed_latch[3] <= 1'b0;
                        end
                        if (s_axi_wstrb[1]) begin
                            global_int_enable <= s_axi_wdata[8];
                        end
                    end

                    ADDR_FDD0_GEOMETRY: begin
                        if (s_axi_wstrb[0]) reg_fdd0_geometry[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_fdd0_geometry[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_fdd0_geometry[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_fdd0_geometry[31:24] <= s_axi_wdata[31:24];
                    end

                    ADDR_FDD1_GEOMETRY: begin
                        if (s_axi_wstrb[0]) reg_fdd1_geometry[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_fdd1_geometry[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_fdd1_geometry[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_fdd1_geometry[31:24] <= s_axi_wdata[31:24];
                    end

                    ADDR_HDD0_CAP_LO: begin
                        if (s_axi_wstrb[0]) reg_hdd0_cap_lo[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_hdd0_cap_lo[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_hdd0_cap_lo[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_hdd0_cap_lo[31:24] <= s_axi_wdata[31:24];
                    end

                    ADDR_HDD0_CAP_HI: begin
                        if (s_axi_wstrb[0]) reg_hdd0_cap_hi[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_hdd0_cap_hi[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_hdd0_cap_hi[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_hdd0_cap_hi[31:24] <= s_axi_wdata[31:24];
                    end

                    ADDR_HDD1_CAP_LO: begin
                        if (s_axi_wstrb[0]) reg_hdd1_cap_lo[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_hdd1_cap_lo[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_hdd1_cap_lo[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_hdd1_cap_lo[31:24] <= s_axi_wdata[31:24];
                    end

                    ADDR_HDD1_CAP_HI: begin
                        if (s_axi_wstrb[0]) reg_hdd1_cap_hi[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_hdd1_cap_hi[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_hdd1_cap_hi[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_hdd1_cap_hi[31:24] <= s_axi_wdata[31:24];
                    end

                    ADDR_DRIVE_STATUS: begin
                        // Ready and WP bits are writable
                        if (s_axi_wstrb[0]) reg_drive_status[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_drive_status[15:8]  <= s_axi_wdata[15:8];
                        // Clear media_changed bits by writing 1
                        if (s_axi_wstrb[0] && s_axi_wdata[4]) media_changed_latch[0] <= 1'b0;
                        if (s_axi_wstrb[0] && s_axi_wdata[5]) media_changed_latch[1] <= 1'b0;
                        if (s_axi_wstrb[0] && s_axi_wdata[6]) media_changed_latch[2] <= 1'b0;
                        if (s_axi_wstrb[0] && s_axi_wdata[7]) media_changed_latch[3] <= 1'b0;
                    end

                    default: s_axi_bresp <= 2'b10;  // SLVERR for invalid address
                endcase
            end

            // Clear write response when accepted
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
                s_axi_awready <= 1'b1;
            end

            // Media change detection (edge detect)
            media_changed_prev <= media_changed_in;
            if (media_changed_in & ~media_changed_prev) begin
                media_changed_latch <= media_changed_latch | (media_changed_in & ~media_changed_prev);
            end
        end
    end

    //=========================================================================
    // AXI Read State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'h0;
            s_axi_rresp   <= 2'b00;
        end else begin
            // Process read address
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;  // OKAY

                case (s_axi_araddr)
                    ADDR_CTRL:          s_axi_rdata <= reg_ctrl;
                    ADDR_STATUS:        s_axi_rdata <= {16'h0, 4'h0, media_changed_latch, drive_present};
                    ADDR_INT_CTRL:      s_axi_rdata <= {23'h0, global_int_enable, media_changed_latch, int_enable};
                    ADDR_FDD0_GEOMETRY: s_axi_rdata <= reg_fdd0_geometry;
                    ADDR_FDD1_GEOMETRY: s_axi_rdata <= reg_fdd1_geometry;
                    ADDR_HDD0_CAP_LO:   s_axi_rdata <= reg_hdd0_cap_lo;
                    ADDR_HDD0_CAP_HI:   s_axi_rdata <= reg_hdd0_cap_hi;
                    ADDR_HDD1_CAP_LO:   s_axi_rdata <= reg_hdd1_cap_lo;
                    ADDR_HDD1_CAP_HI:   s_axi_rdata <= reg_hdd1_cap_hi;
                    ADDR_DRIVE_STATUS:  s_axi_rdata <= {16'h0, reg_drive_status[11:8],
                                                        media_changed_latch, reg_drive_status[3:0]};
                    default: begin
                        s_axi_rdata <= 32'h0;
                        s_axi_rresp <= 2'b10;  // SLVERR
                    end
                endcase
            end

            // Clear read response when accepted
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

    //=========================================================================
    // Output Assignments
    //=========================================================================
    assign config_valid = reg_ctrl[0];

    // FDD sectors from geometry registers [15:0]
    assign fdd0_sectors = reg_fdd0_geometry[15:0];
    assign fdd1_sectors = reg_fdd1_geometry[15:0];

    // HDD sectors (32-bit only, ignore high word for now)
    assign hdd0_sectors = reg_hdd0_cap_lo;
    assign hdd1_sectors = reg_hdd1_cap_lo;

    // Drive ready from DRIVE_STATUS[3:0]
    assign drive_ready = reg_drive_status[3:0];

    // Write protect from DRIVE_STATUS[11:8]
    assign drive_wp = reg_drive_status[11:8];

    //=========================================================================
    // Interrupt Generation
    //=========================================================================
    // Interrupt fires when:
    // - Global interrupt is enabled AND
    // - Any enabled drive has a pending media change
    assign irq_media_change = global_int_enable && |(media_changed_latch & int_enable);

endmodule
