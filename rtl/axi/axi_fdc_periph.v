//-----------------------------------------------------------------------------
// AXI4-Lite FDC Peripheral Interface
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Bridges the 82077AA-compatible FDC registers to MicroBlaze V via AXI4-Lite.
// Provides memory-mapped access to all FDC registers plus extended diagnostics.
//
// Register Map (32-bit aligned):
//   0x00: SRA/SRB (read-only) - Status Register A/B packed
//   0x04: DOR     (r/w)       - Digital Output Register
//   0x08: TDR     (r/w)       - Tape Drive Register [7]=tape_mode, [2:0]=tape_sel
//   0x0C: MSR/DSR (r/w)       - Main Status / Data Rate Select
//   0x10: DATA    (r/w)       - FIFO Data Register
//   0x14: DIR/CCR (r/w)       - Digital Input / Config Control
//   0x18: FLUX_CTRL (r/w)     - Flux capture control (extended)
//   0x1C: FLUX_STATUS (r/o)   - Flux capture status (extended)
//   0x20: CAPTURE_CNT (r/o)   - Flux transition count
//   0x24: INDEX_CNT (r/o)     - Index pulse count
//   0x28: QUALITY (r/o)       - Signal quality metrics
//   0x2C: VERSION (r/o)       - Hardware version ID
//   0x30: TAPE_STATUS (r/o)   - QIC-117 tape status register
//   0x34: TAPE_POSITION (r/o) - Tape segment/track position
//   0x38: TAPE_COMMAND (r/w)  - Direct command issue / last command
//   0x3C: TAPE_DETECT_CTRL (r/w) - Drive detection control
//   0x40: TAPE_DETECT_STATUS (r/o) - Detection status and flags
//   0x44: TAPE_VENDOR_MODEL (r/o) - Detected vendor and model IDs
//   0x48: TAPE_DRIVE_INFO (r/o) - Drive type, tracks, data rates
//
// Target: AMD Spartan UltraScale+ (SCU35)
// Updated: 2025-12-10
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module axi_fdc_periph #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 7,     // 128 bytes address space (expanded for tape)
    parameter VERSION_MAJOR      = 1,
    parameter VERSION_MINOR      = 1,     // Minor version bump for tape support
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
    // FDC Register Interface (directly or to fdc_registers module)
    //-------------------------------------------------------------------------
    // Configuration outputs
    output reg  [1:0]  data_rate,           // 00=500K, 01=300K, 10=250K, 11=1M
    output reg  [3:0]  motor_on,            // Motor enable per drive
    output reg  [1:0]  drive_sel,           // Selected drive (0-3)
    output reg         dma_enable,          // DMA mode enable
    output reg         fdc_reset,           // FDC reset output
    output reg  [3:0]  precomp_delay,       // Write precompensation

    // Status inputs (directly from FDC or drive interface)
    input  wire [3:0]  drive_ready,         // Drive ready status
    input  wire        busy,                // FDC busy
    input  wire        ndma,                // Non-DMA mode
    input  wire        rqm,                 // Request for master
    input  wire        dio,                 // Data direction

    // FIFO interface
    output reg  [7:0]  fifo_data_out,       // Data to FIFO
    output reg         fifo_write,          // Write to FIFO
    input  wire [7:0]  fifo_data_in,        // Data from FIFO
    output reg         fifo_read,           // Read from FIFO
    input  wire        fifo_empty,
    input  wire        fifo_full,

    // Drive signals
    input  wire        disk_change,         // Disk change detect
    input  wire        write_protect,       // Write protect status
    input  wire        track_0,             // Track 0 detect
    input  wire        index_pulse,         // Index pulse

    // Interrupt
    output reg         irq,                 // Interrupt to CPU

    //-------------------------------------------------------------------------
    // Flux Capture Control Interface
    //-------------------------------------------------------------------------
    output reg         flux_capture_enable, // Enable flux capture
    output reg         flux_soft_reset,     // Soft reset for flux capture
    output reg  [1:0]  flux_capture_mode,   // Capture mode

    // Flux Capture Status (from axi_stream_flux)
    input  wire [31:0] flux_capture_count,  // Transitions captured
    input  wire [15:0] flux_index_count,    // Index pulses seen
    input  wire        flux_overflow,       // FIFO overflow
    input  wire        flux_capturing,      // Capture in progress
    input  wire [9:0]  flux_fifo_level,     // FIFO fill level

    //-------------------------------------------------------------------------
    // Signal Quality Inputs (from signal_quality_monitor)
    //-------------------------------------------------------------------------
    input  wire [7:0]  signal_quality,      // Overall quality 0-255
    input  wire [7:0]  signal_stability,    // Stability metric
    input  wire [7:0]  signal_consistency,  // Consistency metric
    input  wire        signal_degraded,     // Degraded warning
    input  wire        signal_critical,     // Critical warning

    //-------------------------------------------------------------------------
    // QIC-117 Tape Interface (from qic117_controller)
    //-------------------------------------------------------------------------
    output wire        tape_mode_en,        // Tape mode enable (TDR[7])
    output wire [2:0]  tape_select,         // Tape drive select (TDR[2:0])

    // Tape status inputs
    input  wire [7:0]  tape_status,         // Tape status byte
    input  wire [15:0] tape_segment,        // Current segment position
    input  wire [4:0]  tape_track,          // Current track position
    input  wire [5:0]  tape_last_command,   // Last decoded command
    input  wire        tape_command_active, // Command in progress
    input  wire        tape_ready,          // Tape drive ready
    input  wire        tape_error,          // Tape error condition

    // Direct command interface
    output reg  [5:0]  tape_direct_cmd,     // Direct command to issue
    output reg         tape_direct_strobe,  // Strobe to issue command

    //-------------------------------------------------------------------------
    // QIC-117 Drive Detection Interface
    //-------------------------------------------------------------------------
    // Detection control
    output reg         tape_start_detect,   // Start auto-detection
    output reg         tape_abort_detect,   // Abort detection

    // Detection status (from qic117_controller)
    input  wire        tape_detect_complete,    // Detection finished
    input  wire        tape_detect_error,       // Detection failed
    input  wire        tape_detect_in_progress, // Detection running
    input  wire        tape_drive_detected,     // Drive present and responding
    input  wire [7:0]  tape_detected_vendor,    // Vendor ID (0=unknown)
    input  wire [7:0]  tape_detected_model,     // Model ID
    input  wire [7:0]  tape_detected_config,    // Drive configuration byte
    input  wire [3:0]  tape_detected_type,      // Drive type enum
    input  wire [4:0]  tape_detected_max_tracks,// Max tracks supported
    input  wire [1:0]  tape_detected_rates      // Supported data rates bitmap
);

    //-------------------------------------------------------------------------
    // Register Address Offsets
    //-------------------------------------------------------------------------
    localparam ADDR_SRA_SRB      = 7'h00;   // [15:8]=SRB, [7:0]=SRA
    localparam ADDR_DOR          = 7'h04;
    localparam ADDR_TDR          = 7'h08;
    localparam ADDR_MSR_DSR      = 7'h0C;
    localparam ADDR_DATA         = 7'h10;
    localparam ADDR_DIR_CCR      = 7'h14;
    localparam ADDR_FLUX_CTRL    = 7'h18;
    localparam ADDR_FLUX_STATUS  = 7'h1C;
    localparam ADDR_CAPTURE_CNT  = 7'h20;
    localparam ADDR_INDEX_CNT    = 7'h24;
    localparam ADDR_QUALITY      = 7'h28;
    localparam ADDR_VERSION      = 7'h2C;
    // QIC-117 Tape Registers
    localparam ADDR_TAPE_STATUS  = 7'h30;   // Tape status register
    localparam ADDR_TAPE_POS     = 7'h34;   // Segment/track position
    localparam ADDR_TAPE_CMD     = 7'h38;   // Direct command / last command
    localparam ADDR_TAPE_DETECT_CTRL   = 7'h3C;   // Detection control
    localparam ADDR_TAPE_DETECT_STATUS = 7'h40;   // Detection status/flags
    localparam ADDR_TAPE_VENDOR_MODEL  = 7'h44;   // Vendor and model IDs
    localparam ADDR_TAPE_DRIVE_INFO    = 7'h48;   // Drive type, tracks, rates

    //-------------------------------------------------------------------------
    // AXI4-Lite State Machine
    //-------------------------------------------------------------------------
    reg [1:0] axi_state;
    localparam AXI_IDLE  = 2'b00;
    localparam AXI_WRITE = 2'b01;
    localparam AXI_READ  = 2'b10;
    localparam AXI_RESP  = 2'b11;

    reg                              axi_awready_r;
    reg                              axi_wready_r;
    reg                              axi_bvalid_r;
    reg [1:0]                        axi_bresp_r;
    reg                              axi_arready_r;
    reg                              axi_rvalid_r;
    reg [C_S_AXI_DATA_WIDTH-1:0]     axi_rdata_r;
    reg [1:0]                        axi_rresp_r;

    reg [C_S_AXI_ADDR_WIDTH-1:0]     axi_awaddr_r;
    reg [C_S_AXI_ADDR_WIDTH-1:0]     axi_araddr_r;

    //-------------------------------------------------------------------------
    // Internal Registers
    //-------------------------------------------------------------------------
    reg [7:0] dor_reg;           // Digital Output Register
    reg [7:0] dsr_reg;           // Data Rate Select Register
    reg [7:0] ccr_reg;           // Configuration Control Register
    reg [7:0] tdr_reg;           // Tape Drive Register

    //-------------------------------------------------------------------------
    // Status Register Construction
    //-------------------------------------------------------------------------

    // SRA - Status Register A
    wire [7:0] sra_value = {
        irq,                    // INT pending
        ~fifo_empty,            // DRQ
        1'b1,                   // STEP (high = not stepping)
        track_0,                // Track 0
        1'b0,                   // Head 1 select
        index_pulse,            // Index
        write_protect,          // Write protect
        1'b1                    // Direction (1 = out)
    };

    // SRB - Status Register B
    wire [7:0] srb_value = {
        1'b1,                   // Drive 1 data toggle
        1'b1,                   // Drive 0 data toggle
        1'b0,                   // Write data
        1'b0,                   // Read data
        ~write_protect,         // Write enable
        motor_on[1],            // Motor 1
        motor_on[0],            // Motor 0
        ~drive_sel[0]           // Drive select 0
    };

    // MSR - Main Status Register
    wire [7:0] msr_value = {
        rqm,                    // Request for master
        dio,                    // Data I/O direction
        ndma,                   // Non-DMA execution
        busy,                   // Command busy
        drive_ready             // Drive busy bits [3:0]
    };

    // DIR - Digital Input Register
    wire [7:0] dir_value = {
        disk_change,            // Disk change (active high)
        7'b0000000
    };

    // Version register (read-only)
    wire [31:0] version_value = {
        8'hFD,                              // FluxRipper ID
        VERSION_MAJOR[7:0],
        VERSION_MINOR[7:0],
        VERSION_PATCH[7:0]
    };

    // Flux status register (read-only)
    wire [31:0] flux_status_value = {
        signal_critical,                    // [31]
        signal_degraded,                    // [30]
        flux_overflow,                      // [29]
        flux_capturing,                     // [28]
        2'b00,                              // [27:26] reserved
        flux_fifo_level,                    // [25:16]
        flux_index_count                    // [15:0]
    };

    // Quality register (read-only)
    wire [31:0] quality_value = {
        8'd0,                               // Reserved
        signal_consistency,                 // [23:16]
        signal_stability,                   // [15:8]
        signal_quality                      // [7:0]
    };

    // QIC-117 Tape Status register (read-only)
    // [31:24] = reserved
    // [23:16] = last command
    // [15:8]  = flags (ready, error, active, etc.)
    // [7:0]   = tape_status byte from controller
    wire [31:0] tape_status_value = {
        2'd0,                               // [31:30] reserved
        tape_last_command,                  // [29:24] last command
        tape_error,                         // [23] error
        tape_ready,                         // [22] ready
        tape_command_active,                // [21] command active
        5'd0,                               // [20:16] reserved
        tape_status                         // [15:8] status byte from controller
                                            // Note: shifted up to leave room
    };

    // Tape position register (read-only)
    // [31:21] = reserved
    // [20:16] = track number
    // [15:0]  = segment number
    wire [31:0] tape_position_value = {
        11'd0,                              // [31:21] reserved
        tape_track,                         // [20:16] track
        tape_segment                        // [15:0] segment
    };

    // Drive detection status register (read-only)
    // [31:4] = reserved
    // [3]    = drive detected
    // [2]    = detection error
    // [1]    = detection complete
    // [0]    = detection in progress
    wire [31:0] tape_detect_status_value = {
        28'd0,                              // [31:4] reserved
        tape_drive_detected,                // [3] drive found
        tape_detect_error,                  // [2] error occurred
        tape_detect_complete,               // [1] detection done
        tape_detect_in_progress             // [0] detection running
    };

    // Vendor/model register (read-only)
    // [31:24] = drive configuration byte
    // [23:16] = reserved
    // [15:8]  = model ID
    // [7:0]   = vendor ID
    wire [31:0] tape_vendor_model_value = {
        tape_detected_config,               // [31:24] config
        8'd0,                               // [23:16] reserved
        tape_detected_model,                // [15:8] model
        tape_detected_vendor                // [7:0] vendor
    };

    // Drive info register (read-only)
    // [31:16] = reserved
    // [15:12] = reserved
    // [11:8]  = drive type enum
    // [7:5]   = reserved
    // [4:0]   = max tracks
    // Plus supported rates in upper bits
    wire [31:0] tape_drive_info_value = {
        14'd0,                              // [31:18] reserved
        tape_detected_rates,                // [17:16] data rates (bit 0=500K, bit 1=1M)
        4'd0,                               // [15:12] reserved
        tape_detected_type,                 // [11:8] drive type enum
        3'd0,                               // [7:5] reserved
        tape_detected_max_tracks            // [4:0] max tracks
    };

    // TDR output assignments for tape mode
    assign tape_mode_en = tdr_reg[7];
    assign tape_select  = tdr_reg[2:0];

    //-------------------------------------------------------------------------
    // AXI Write Logic
    //-------------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_awready_r <= 1'b0;
            axi_wready_r  <= 1'b0;
            axi_bvalid_r  <= 1'b0;
            axi_bresp_r   <= 2'b00;
            axi_awaddr_r  <= {C_S_AXI_ADDR_WIDTH{1'b0}};

            // Reset internal registers
            dor_reg       <= 8'h00;
            dsr_reg       <= 8'h00;
            ccr_reg       <= 8'h00;
            tdr_reg       <= 8'h00;
            motor_on      <= 4'b0000;
            drive_sel     <= 2'b00;
            dma_enable    <= 1'b0;
            fdc_reset     <= 1'b1;
            data_rate     <= 2'b00;
            precomp_delay <= 4'h0;
            fifo_write    <= 1'b0;
            fifo_data_out <= 8'h00;
            irq           <= 1'b0;

            flux_capture_enable <= 1'b0;
            flux_soft_reset     <= 1'b0;
            flux_capture_mode   <= 2'b00;

            // Tape registers
            tape_direct_cmd     <= 6'd0;
            tape_direct_strobe  <= 1'b0;

            // Detection control
            tape_start_detect   <= 1'b0;
            tape_abort_detect   <= 1'b0;
        end
        else begin
            // Default: deassert one-shot signals
            fifo_write         <= 1'b0;
            flux_soft_reset    <= 1'b0;
            tape_direct_strobe <= 1'b0;
            tape_start_detect  <= 1'b0;
            tape_abort_detect  <= 1'b0;

            // Clear fdc_reset after one cycle
            if (fdc_reset) begin
                fdc_reset <= 1'b0;
            end

            // AXI Write Address Ready
            if (!axi_awready_r && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready_r <= 1'b1;
                axi_awaddr_r  <= s_axi_awaddr;
            end
            else begin
                axi_awready_r <= 1'b0;
            end

            // AXI Write Data Ready
            if (!axi_wready_r && s_axi_awvalid && s_axi_wvalid) begin
                axi_wready_r <= 1'b1;
            end
            else begin
                axi_wready_r <= 1'b0;
            end

            // Handle Write Transaction
            if (axi_awready_r && s_axi_awvalid && axi_wready_r && s_axi_wvalid) begin
                case (axi_awaddr_r[6:2])  // Word-aligned address
                    ADDR_DOR[6:2]: begin
                        if (s_axi_wstrb[0]) begin
                            dor_reg    <= s_axi_wdata[7:0];
                            motor_on   <= s_axi_wdata[7:4];
                            dma_enable <= s_axi_wdata[3];
                            fdc_reset  <= ~s_axi_wdata[2];  // Active low in DOR
                            drive_sel  <= s_axi_wdata[1:0];
                        end
                    end

                    ADDR_TDR[6:2]: begin
                        if (s_axi_wstrb[0]) begin
                            tdr_reg <= s_axi_wdata[7:0];
                        end
                    end

                    ADDR_MSR_DSR[6:2]: begin
                        if (s_axi_wstrb[0]) begin
                            dsr_reg <= s_axi_wdata[7:0];
                            if (s_axi_wdata[7]) begin
                                fdc_reset <= 1'b1;  // Software reset
                            end
                            precomp_delay <= {1'b0, s_axi_wdata[4:2]};
                            data_rate     <= s_axi_wdata[1:0];
                        end
                    end

                    ADDR_DATA[6:2]: begin
                        if (s_axi_wstrb[0]) begin
                            fifo_data_out <= s_axi_wdata[7:0];
                            fifo_write    <= 1'b1;
                        end
                    end

                    ADDR_DIR_CCR[6:2]: begin
                        if (s_axi_wstrb[0]) begin
                            ccr_reg   <= s_axi_wdata[7:0];
                            data_rate <= s_axi_wdata[1:0];
                        end
                    end

                    ADDR_FLUX_CTRL[6:2]: begin
                        if (s_axi_wstrb[0]) begin
                            flux_capture_enable <= s_axi_wdata[0];
                            flux_soft_reset     <= s_axi_wdata[1];
                            flux_capture_mode   <= s_axi_wdata[3:2];
                        end
                    end

                    ADDR_TAPE_CMD[6:2]: begin
                        // Direct command interface - write command code to issue it
                        if (s_axi_wstrb[0]) begin
                            tape_direct_cmd    <= s_axi_wdata[5:0];
                            tape_direct_strobe <= 1'b1;
                        end
                    end

                    ADDR_TAPE_DETECT_CTRL[6:2]: begin
                        // Detection control - write to start/abort detection
                        // Bit 0: start detection (pulse)
                        // Bit 1: abort detection (pulse)
                        if (s_axi_wstrb[0]) begin
                            tape_start_detect <= s_axi_wdata[0];
                            tape_abort_detect <= s_axi_wdata[1];
                        end
                    end

                    default: begin
                        // Read-only or invalid address - ignore write
                    end
                endcase
            end

            // Write Response
            if (axi_awready_r && s_axi_awvalid && axi_wready_r && s_axi_wvalid && !axi_bvalid_r) begin
                axi_bvalid_r <= 1'b1;
                axi_bresp_r  <= 2'b00;  // OKAY
            end
            else if (s_axi_bready && axi_bvalid_r) begin
                axi_bvalid_r <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // AXI Read Logic
    //-------------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_arready_r <= 1'b0;
            axi_rvalid_r  <= 1'b0;
            axi_rdata_r   <= {C_S_AXI_DATA_WIDTH{1'b0}};
            axi_rresp_r   <= 2'b00;
            axi_araddr_r  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            fifo_read     <= 1'b0;
        end
        else begin
            fifo_read <= 1'b0;

            // AXI Read Address Ready
            if (!axi_arready_r && s_axi_arvalid) begin
                axi_arready_r <= 1'b1;
                axi_araddr_r  <= s_axi_araddr;
            end
            else begin
                axi_arready_r <= 1'b0;
            end

            // Handle Read Transaction
            if (axi_arready_r && s_axi_arvalid && !axi_rvalid_r) begin
                axi_rvalid_r <= 1'b1;
                axi_rresp_r  <= 2'b00;  // OKAY

                case (axi_araddr_r[6:2])  // Word-aligned address
                    ADDR_SRA_SRB[6:2]:
                        axi_rdata_r <= {16'd0, srb_value, sra_value};

                    ADDR_DOR[6:2]:
                        axi_rdata_r <= {24'd0, dor_reg};

                    ADDR_TDR[6:2]:
                        axi_rdata_r <= {24'd0, tdr_reg};

                    ADDR_MSR_DSR[6:2]:
                        axi_rdata_r <= {24'd0, msr_value};

                    ADDR_DATA[6:2]: begin
                        axi_rdata_r <= {24'd0, fifo_data_in};
                        fifo_read   <= 1'b1;
                    end

                    ADDR_DIR_CCR[6:2]:
                        axi_rdata_r <= {24'd0, dir_value};

                    ADDR_FLUX_CTRL[6:2]:
                        axi_rdata_r <= {28'd0, flux_capture_mode, 1'b0, flux_capture_enable};

                    ADDR_FLUX_STATUS[6:2]:
                        axi_rdata_r <= flux_status_value;

                    ADDR_CAPTURE_CNT[6:2]:
                        axi_rdata_r <= flux_capture_count;

                    ADDR_INDEX_CNT[6:2]:
                        axi_rdata_r <= {16'd0, flux_index_count};

                    ADDR_QUALITY[6:2]:
                        axi_rdata_r <= quality_value;

                    ADDR_VERSION[6:2]:
                        axi_rdata_r <= version_value;

                    // QIC-117 Tape Registers
                    ADDR_TAPE_STATUS[6:2]:
                        axi_rdata_r <= tape_status_value;

                    ADDR_TAPE_POS[6:2]:
                        axi_rdata_r <= tape_position_value;

                    ADDR_TAPE_CMD[6:2]:
                        axi_rdata_r <= {26'd0, tape_last_command};

                    ADDR_TAPE_DETECT_CTRL[6:2]:
                        // Read back shows detection status (same as status reg for convenience)
                        axi_rdata_r <= tape_detect_status_value;

                    ADDR_TAPE_DETECT_STATUS[6:2]:
                        axi_rdata_r <= tape_detect_status_value;

                    ADDR_TAPE_VENDOR_MODEL[6:2]:
                        axi_rdata_r <= tape_vendor_model_value;

                    ADDR_TAPE_DRIVE_INFO[6:2]:
                        axi_rdata_r <= tape_drive_info_value;

                    default:
                        axi_rdata_r <= 32'hDEADBEEF;
                endcase
            end
            else if (axi_rvalid_r && s_axi_rready) begin
                axi_rvalid_r <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // AXI Output Assignments
    //-------------------------------------------------------------------------
    assign s_axi_awready = axi_awready_r;
    assign s_axi_wready  = axi_wready_r;
    assign s_axi_bresp   = axi_bresp_r;
    assign s_axi_bvalid  = axi_bvalid_r;
    assign s_axi_arready = axi_arready_r;
    assign s_axi_rdata   = axi_rdata_r;
    assign s_axi_rresp   = axi_rresp_r;
    assign s_axi_rvalid  = axi_rvalid_r;

endmodule


//-----------------------------------------------------------------------------
// Testbench for AXI4-Lite FDC Peripheral
//-----------------------------------------------------------------------------
`ifdef SIMULATION

module tb_axi_fdc_periph;

    // Clock and reset
    reg         aclk;
    reg         aresetn;

    // AXI4-Lite signals
    reg  [6:0]  awaddr;
    reg  [2:0]  awprot;
    reg         awvalid;
    wire        awready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg  [6:0]  araddr;
    reg  [2:0]  arprot;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    // FDC signals
    wire [1:0]  data_rate;
    wire [3:0]  motor_on;
    wire [1:0]  drive_sel;
    wire        dma_enable;
    wire        fdc_reset;
    wire [3:0]  precomp_delay;

    reg  [3:0]  drive_ready;
    reg         busy;
    reg         ndma;
    reg         rqm;
    reg         dio;

    wire [7:0]  fifo_data_out;
    wire        fifo_write;
    reg  [7:0]  fifo_data_in;
    wire        fifo_read;
    reg         fifo_empty;
    reg         fifo_full;

    reg         disk_change;
    reg         write_protect;
    reg         track_0;
    reg         index_pulse;

    wire        irq;

    wire        flux_capture_enable;
    wire        flux_soft_reset;
    wire [1:0]  flux_capture_mode;

    // Tape signals
    wire        tape_mode_en;
    wire [2:0]  tape_select;
    wire [5:0]  tape_direct_cmd;
    wire        tape_direct_strobe;

    // Detection signals
    wire        tape_start_detect;
    wire        tape_abort_detect;

    // DUT
    axi_fdc_periph #(
        .VERSION_MAJOR(1),
        .VERSION_MINOR(1),
        .VERSION_PATCH(0)
    ) u_dut (
        .s_axi_aclk(aclk),
        .s_axi_aresetn(aresetn),
        .s_axi_awaddr(awaddr),
        .s_axi_awprot(awprot),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arprot(arprot),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .data_rate(data_rate),
        .motor_on(motor_on),
        .drive_sel(drive_sel),
        .dma_enable(dma_enable),
        .fdc_reset(fdc_reset),
        .precomp_delay(precomp_delay),
        .drive_ready(drive_ready),
        .busy(busy),
        .ndma(ndma),
        .rqm(rqm),
        .dio(dio),
        .fifo_data_out(fifo_data_out),
        .fifo_write(fifo_write),
        .fifo_data_in(fifo_data_in),
        .fifo_read(fifo_read),
        .fifo_empty(fifo_empty),
        .fifo_full(fifo_full),
        .disk_change(disk_change),
        .write_protect(write_protect),
        .track_0(track_0),
        .index_pulse(index_pulse),
        .irq(irq),
        .flux_capture_enable(flux_capture_enable),
        .flux_soft_reset(flux_soft_reset),
        .flux_capture_mode(flux_capture_mode),
        .flux_capture_count(32'd12345),
        .flux_index_count(16'd5),
        .flux_overflow(1'b0),
        .flux_capturing(1'b1),
        .flux_fifo_level(10'd256),
        .signal_quality(8'd200),
        .signal_stability(8'd180),
        .signal_consistency(8'd220),
        .signal_degraded(1'b0),
        .signal_critical(1'b0),
        // Tape interface
        .tape_mode_en(tape_mode_en),
        .tape_select(tape_select),
        .tape_status(8'hA5),           // Test status byte
        .tape_segment(16'd1234),       // Test segment
        .tape_track(5'd7),             // Test track
        .tape_last_command(6'd8),      // Last command (SEEK_BOT)
        .tape_command_active(1'b0),
        .tape_ready(1'b1),
        .tape_error(1'b0),
        .tape_direct_cmd(tape_direct_cmd),
        .tape_direct_strobe(tape_direct_strobe),
        // Detection interface
        .tape_start_detect(tape_start_detect),
        .tape_abort_detect(tape_abort_detect),
        .tape_detect_complete(1'b1),         // Detection done
        .tape_detect_error(1'b0),            // No error
        .tape_detect_in_progress(1'b0),      // Not detecting
        .tape_drive_detected(1'b1),          // Drive found
        .tape_detected_vendor(8'h05),        // Wangtek
        .tape_detected_model(8'h20),         // Model code
        .tape_detected_config(8'h42),        // Config byte
        .tape_detected_type(4'd2),           // QIC-80
        .tape_detected_max_tracks(5'd28),    // 28 tracks
        .tape_detected_rates(2'b01)          // 500K only
    );

    // Clock generation
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end

    // AXI Write task
    task axi_write;
        input [6:0] addr;
        input [31:0] data;
        begin
            @(posedge aclk);
            awaddr  = addr;
            awprot  = 3'b000;
            awvalid = 1;
            wdata   = data;
            wstrb   = 4'b1111;
            wvalid  = 1;
            bready  = 1;

            wait(awready && wready);
            @(posedge aclk);
            awvalid = 0;
            wvalid  = 0;

            wait(bvalid);
            @(posedge aclk);
            bready = 0;
        end
    endtask

    // AXI Read task
    task axi_read;
        input [6:0] addr;
        output [31:0] data;
        begin
            @(posedge aclk);
            araddr  = addr;
            arprot  = 3'b000;
            arvalid = 1;
            rready  = 1;

            wait(arready);
            @(posedge aclk);
            arvalid = 0;

            wait(rvalid);
            data = rdata;
            @(posedge aclk);
            rready = 0;
        end
    endtask

    // Test stimulus
    reg [31:0] read_data;

    initial begin
        $display("===========================================");
        $display("AXI4-Lite FDC Peripheral Testbench");
        $display("===========================================");

        // Initialize
        aresetn       = 0;
        awaddr        = 0;
        awprot        = 0;
        awvalid       = 0;
        wdata         = 0;
        wstrb         = 0;
        wvalid        = 0;
        bready        = 0;
        araddr        = 0;
        arprot        = 0;
        arvalid       = 0;
        rready        = 0;

        drive_ready   = 4'b0001;
        busy          = 0;
        ndma          = 0;
        rqm           = 1;
        dio           = 0;
        fifo_data_in  = 8'hA5;
        fifo_empty    = 0;
        fifo_full     = 0;
        disk_change   = 0;
        write_protect = 0;
        track_0       = 1;
        index_pulse   = 0;

        // Reset
        #100;
        aresetn = 1;
        #50;

        // Test 1: Read Version
        $display("\nTest 1: Read VERSION register");
        axi_read(7'h2C, read_data);
        $display("  VERSION = 0x%08X (expected 0xFD010100)", read_data);

        // Test 2: Write/Read DOR
        $display("\nTest 2: Write/Read DOR register");
        axi_write(7'h04, 32'h0000001C);  // Motor A on, DMA enable, drive 0
        axi_read(7'h04, read_data);
        $display("  DOR = 0x%02X (expected 0x1C)", read_data[7:0]);
        $display("  motor_on = %b, drive_sel = %d", motor_on, drive_sel);

        // Test 3: Read MSR
        $display("\nTest 3: Read MSR register");
        axi_read(7'h0C, read_data);
        $display("  MSR = 0x%02X (RQM=%b, DIO=%b)", read_data[7:0], read_data[7], read_data[6]);

        // Test 4: Enable flux capture
        $display("\nTest 4: Enable flux capture");
        axi_write(7'h18, 32'h00000005);  // Enable, one-track mode
        $display("  flux_capture_enable = %b", flux_capture_enable);
        $display("  flux_capture_mode = %d", flux_capture_mode);

        // Test 5: Read flux status
        $display("\nTest 5: Read flux status");
        axi_read(7'h1C, read_data);
        $display("  FLUX_STATUS = 0x%08X", read_data);

        // Test 6: Read capture count
        axi_read(7'h20, read_data);
        $display("  CAPTURE_CNT = %d", read_data);

        // Test 7: Read quality
        axi_read(7'h28, read_data);
        $display("  QUALITY = 0x%08X (qual=%d, stab=%d, cons=%d)",
                 read_data, read_data[7:0], read_data[15:8], read_data[23:16]);

        // Test 8: Enable tape mode
        $display("\nTest 8: Enable tape mode via TDR");
        axi_write(7'h08, 32'h00000081);  // tape_mode_en=1, tape_select=1
        axi_read(7'h08, read_data);
        $display("  TDR = 0x%02X (expected 0x81)", read_data[7:0]);
        $display("  tape_mode_en = %b, tape_select = %d", tape_mode_en, tape_select);

        // Test 9: Read tape status
        $display("\nTest 9: Read tape status");
        axi_read(7'h30, read_data);
        $display("  TAPE_STATUS = 0x%08X", read_data);

        // Test 10: Read tape position
        $display("\nTest 10: Read tape position");
        axi_read(7'h34, read_data);
        $display("  TAPE_POS = 0x%08X (track=%d, segment=%d)",
                 read_data, read_data[20:16], read_data[15:0]);

        // Test 11: Issue direct tape command
        $display("\nTest 11: Issue direct tape command (SEEK_BOT=8)");
        axi_write(7'h38, 32'h00000008);  // Issue SEEK_BOT command
        $display("  tape_direct_cmd = %d, tape_direct_strobe = %b",
                 tape_direct_cmd, tape_direct_strobe);

        // Test 12: Read detection status
        $display("\nTest 12: Read detection status");
        axi_read(7'h40, read_data);
        $display("  DETECT_STATUS = 0x%08X", read_data);
        $display("  in_progress=%b, complete=%b, error=%b, detected=%b",
                 read_data[0], read_data[1], read_data[2], read_data[3]);

        // Test 13: Read vendor/model
        $display("\nTest 13: Read vendor/model");
        axi_read(7'h44, read_data);
        $display("  VENDOR_MODEL = 0x%08X", read_data);
        $display("  vendor=0x%02X, model=0x%02X, config=0x%02X",
                 read_data[7:0], read_data[15:8], read_data[31:24]);

        // Test 14: Read drive info
        $display("\nTest 14: Read drive info");
        axi_read(7'h48, read_data);
        $display("  DRIVE_INFO = 0x%08X", read_data);
        $display("  max_tracks=%d, type=%d, rates=%b",
                 read_data[4:0], read_data[11:8], read_data[17:16]);

        // Test 15: Start detection
        $display("\nTest 15: Start detection (pulse)");
        axi_write(7'h3C, 32'h00000001);  // Start detection
        $display("  tape_start_detect = %b", tape_start_detect);
        #20;
        $display("  tape_start_detect after 2 clocks = %b (should be 0)", tape_start_detect);

        #200;
        $display("\n===========================================");
        $display("All tests completed");
        $display("===========================================");
        $finish;
    end

    // Timeout
    initial begin
        #50000;
        $display("Simulation timeout");
        $finish;
    end

endmodule

`endif
