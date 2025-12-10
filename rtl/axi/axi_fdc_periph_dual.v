//-----------------------------------------------------------------------------
// AXI4-Lite FDC Peripheral - Dual Interface Version
// Provides memory-mapped access to dual FDC registers for MicroBlaze V
//
// Register Map:
//   0x00-0x2C: Standard 82077AA + FluxRipper registers (Interface A)
//   0x30-0x74: Dual interface extension registers
//   0x78-0x9C: QIC-117 Tape interface registers
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-10
//-----------------------------------------------------------------------------

module axi_fdc_periph_dual (
    //-------------------------------------------------------------------------
    // AXI4-Lite Slave Interface
    //-------------------------------------------------------------------------
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,

    // Write address channel
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,

    // Write data channel
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,

    // Write response channel
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    // Read address channel
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,

    // Read data channel
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    //-------------------------------------------------------------------------
    // Configuration Outputs
    //-------------------------------------------------------------------------
    output reg         dual_enable,
    output reg         sync_index,
    output reg  [1:0]  if_a_drive_sel,
    output reg  [1:0]  if_b_drive_sel,
    output reg  [1:0]  data_rate,
    output reg  [1:0]  step_rate_sel,
    output reg         double_step,
    output reg         rpm_360,
    output reg  [3:0]  motor_on_cmd,
    output reg         sw_reset,

    // Auto-detection configuration (from CCR register)
    output reg         mac_zone_enable,      // CCR[4]: Macintosh variable-speed zone mode
    output reg         auto_double_step_en,  // CCR[5]: Auto track density → double-step
    output reg         auto_data_rate_en,    // CCR[6]: Auto data rate detection
    output reg         auto_encoding_en,     // CCR[7]: Auto encoding selection

    // Motorized eject commands
    output reg         eject_cmd_a,          // Eject command for Interface A
    output reg         eject_cmd_b,          // Eject command for Interface B

    //-------------------------------------------------------------------------
    // FDC A Command Interface
    //-------------------------------------------------------------------------
    output reg  [7:0]  fdc_a_cmd_byte,
    output reg         fdc_a_cmd_valid,
    output reg  [7:0]  fdc_a_fifo_data_in,
    input  wire        fdc_a_fifo_empty,
    input  wire        fdc_a_fifo_read,
    input  wire [7:0]  fdc_a_fifo_data_out,
    input  wire        fdc_a_fifo_write,

    //-------------------------------------------------------------------------
    // FDC B Command Interface
    //-------------------------------------------------------------------------
    output reg  [7:0]  fdc_b_cmd_byte,
    output reg         fdc_b_cmd_valid,
    output reg  [7:0]  fdc_b_fifo_data_in,
    input  wire        fdc_b_fifo_empty,
    input  wire        fdc_b_fifo_read,
    input  wire [7:0]  fdc_b_fifo_data_out,
    input  wire        fdc_b_fifo_write,

    //-------------------------------------------------------------------------
    // FDC A Status
    //-------------------------------------------------------------------------
    input  wire [7:0]  fdc_a_current_track,
    input  wire        fdc_a_busy,
    input  wire        fdc_a_dio,
    input  wire        fdc_a_rqm,
    input  wire        fdc_a_pll_locked,
    input  wire [7:0]  fdc_a_lock_quality,

    //-------------------------------------------------------------------------
    // FDC B Status
    //-------------------------------------------------------------------------
    input  wire [7:0]  fdc_b_current_track,
    input  wire        fdc_b_busy,
    input  wire        fdc_b_dio,
    input  wire        fdc_b_rqm,
    input  wire        fdc_b_pll_locked,
    input  wire [7:0]  fdc_b_lock_quality,

    //-------------------------------------------------------------------------
    // Flux Capture Control
    //-------------------------------------------------------------------------
    output reg         flux_capture_enable_a,
    output reg         flux_capture_enable_b,
    output reg  [1:0]  flux_capture_mode_a,
    output reg  [1:0]  flux_capture_mode_b,

    //-------------------------------------------------------------------------
    // Motor Status
    //-------------------------------------------------------------------------
    input  wire [3:0]  motor_running,
    input  wire [3:0]  motor_at_speed,

    //-------------------------------------------------------------------------
    // Auto-Detection Status (from detection modules)
    //-------------------------------------------------------------------------
    input  wire [3:0]  rpm_valid,            // RPM detection valid per drive
    input  wire [3:0]  detected_rpm_360,     // Detected 360 RPM per drive
    input  wire [1:0]  detected_data_rate_a, // Detected data rate for FDC A
    input  wire [1:0]  detected_data_rate_b, // Detected data rate for FDC B
    input  wire        data_rate_locked_a,   // Data rate locked for FDC A
    input  wire        data_rate_locked_b,   // Data rate locked for FDC B
    input  wire [2:0]  detected_encoding_a,  // Detected encoding for FDC A
    input  wire [2:0]  detected_encoding_b,  // Detected encoding for FDC B
    input  wire        encoding_locked_a,    // Encoding locked for FDC A
    input  wire        encoding_locked_b,    // Encoding locked for FDC B

    // Track density auto-detection status
    input  wire        detected_40_track_a,       // 1 if 40-track disk detected on A
    input  wire        detected_40_track_b,       // 1 if 40-track disk detected on B
    input  wire        track_density_detected_a,  // Track analysis complete for A
    input  wire        track_density_detected_b,  // Track analysis complete for B

    //-------------------------------------------------------------------------
    // Drive Profile Inputs (from drive_profile_detector)
    //-------------------------------------------------------------------------
    input  wire [31:0] drive_profile_a,          // Packed drive profile for Interface A
    input  wire        drive_profile_valid_a,    // Profile detection complete for A
    input  wire        drive_profile_locked_a,   // Profile stable for A
    input  wire [31:0] drive_profile_b,          // Packed drive profile for Interface B
    input  wire        drive_profile_valid_b,    // Profile detection complete for B
    input  wire        drive_profile_locked_b,   // Profile stable for B

    //-------------------------------------------------------------------------
    // Disk Change Inputs (directly from drive interface)
    //-------------------------------------------------------------------------
    input  wire        dskchg_a_drv0,            // Disk change for Interface A, Drive 0
    input  wire        dskchg_a_drv1,            // Disk change for Interface A, Drive 1
    input  wire        dskchg_b_drv0,            // Disk change for Interface B, Drive 0
    input  wire        dskchg_b_drv1,            // Disk change for Interface B, Drive 1

    //-------------------------------------------------------------------------
    // QIC-117 Tape Interface
    //-------------------------------------------------------------------------
    // Tape mode control
    output wire        tape_mode_en,             // Tape mode enable (TDR[7])
    output wire [2:0]  tape_select,              // Tape drive select (TDR[2:0])

    // Direct command interface
    output reg  [5:0]  tape_direct_cmd,          // Direct command to issue
    output reg         tape_direct_strobe,       // Strobe to issue command

    // Detection control
    output reg         tape_start_detect,        // Start auto-detection
    output reg         tape_abort_detect,        // Abort detection

    // Tape status inputs (from qic117_controller)
    input  wire [7:0]  tape_status,              // Tape status byte
    input  wire [15:0] tape_segment,             // Current segment position
    input  wire [4:0]  tape_track,               // Current track position
    input  wire [5:0]  tape_last_command,        // Last decoded command
    input  wire        tape_command_active,      // Command in progress
    input  wire        tape_ready,               // Tape drive ready
    input  wire        tape_error,               // Tape error condition

    // Detection status inputs (from qic117_controller)
    input  wire        tape_detect_complete,     // Detection finished
    input  wire        tape_detect_error,        // Detection failed
    input  wire        tape_detect_in_progress,  // Detection running
    input  wire        tape_drive_detected,      // Drive present and responding
    input  wire [7:0]  tape_detected_vendor,     // Vendor ID (0=unknown)
    input  wire [7:0]  tape_detected_model,      // Model ID
    input  wire [7:0]  tape_detected_config,     // Drive configuration byte
    input  wire [3:0]  tape_detected_type,       // Drive type enum
    input  wire [4:0]  tape_detected_max_tracks, // Max tracks supported
    input  wire [1:0]  tape_detected_rates,      // Supported data rates bitmap

    // Tape data streaming inputs (from qic117_data_streamer)
    input  wire [7:0]  tape_data_byte,           // Data byte from streamer
    input  wire        tape_data_valid,          // Data byte valid strobe
    input  wire [7:0]  tape_block_header,        // Current block header byte
    input  wire [8:0]  tape_byte_in_block,       // Byte position in block (0-511)
    input  wire [4:0]  tape_block_in_segment,    // Block number in segment (0-31)
    input  wire        tape_block_complete,      // Block complete pulse
    input  wire        tape_segment_complete,    // Segment complete pulse
    input  wire [15:0] tape_segment_count,       // Total segments captured
    input  wire [15:0] tape_good_blocks,         // Good blocks captured
    input  wire [15:0] tape_error_count,         // Error count
    input  wire        tape_is_file_mark,        // Current block is file mark
    input  wire        tape_is_eod,              // Current block is EOD
    input  wire        tape_streaming            // Tape is currently streaming
);

    //-------------------------------------------------------------------------
    // Register Addresses
    //-------------------------------------------------------------------------
    // Standard 82077AA-compatible registers
    localparam ADDR_SRA_SRB      = 8'h00;  // Status Registers A/B (R)
    localparam ADDR_DOR          = 8'h04;  // Digital Output Register (R/W)
    localparam ADDR_TDR          = 8'h08;  // Tape Drive Register (R/W)
    localparam ADDR_MSR_DSR      = 8'h0C;  // Main Status / Data Rate Select
    localparam ADDR_DATA         = 8'h10;  // FIFO Data Register
    localparam ADDR_DIR_CCR      = 8'h14;  // Digital Input / Config Control
    localparam ADDR_FLUX_CTRL    = 8'h18;  // Flux Capture Control (A)
    localparam ADDR_FLUX_STATUS  = 8'h1C;  // Flux Capture Status (A)
    localparam ADDR_CAPTURE_CNT  = 8'h20;  // Capture Count (A)
    localparam ADDR_INDEX_CNT    = 8'h24;  // Index Count (A)
    localparam ADDR_QUALITY      = 8'h28;  // Signal Quality (A)
    localparam ADDR_VERSION      = 8'h2C;  // Hardware Version

    // Dual interface extension registers
    localparam ADDR_DUAL_CTRL    = 8'h30;  // Dual Interface Control
    localparam ADDR_FDC_A_STATUS = 8'h34;  // FDC A Extended Status
    localparam ADDR_FDC_B_STATUS = 8'h38;  // FDC B Extended Status
    localparam ADDR_TRACK_A      = 8'h3C;  // Current Track A
    localparam ADDR_TRACK_B      = 8'h40;  // Current Track B
    localparam ADDR_FLUX_CTRL_A  = 8'h44;  // Flux Control A
    localparam ADDR_FLUX_CTRL_B  = 8'h48;  // Flux Control B
    localparam ADDR_FLUX_STAT_A  = 8'h4C;  // Flux Status A
    localparam ADDR_FLUX_STAT_B  = 8'h50;  // Flux Status B
    localparam ADDR_COPY_CTRL    = 8'h54;  // Disk-to-Disk Copy Control
    localparam ADDR_COPY_STATUS  = 8'h58;  // Copy Operation Status

    // Auto-detection status registers (new)
    localparam ADDR_AUTO_STATUS_A = 8'h5C;  // Auto-detection status A
    localparam ADDR_AUTO_STATUS_B = 8'h60;  // Auto-detection status B
    localparam ADDR_EJECT_CTRL    = 8'h64;  // Motorized eject control

    // Drive profile registers (32-bit packed profile per interface)
    localparam ADDR_DRIVE_PROFILE_A = 8'h68;  // Drive profile A
    localparam ADDR_DRIVE_PROFILE_B = 8'h6C;  // Drive profile B (fixed offset)

    // FDC B register mirrors (offset for spacing)
    localparam ADDR_B_MSR_DSR    = 8'h70;  // FDC B Main Status / Data Rate
    localparam ADDR_B_DATA       = 8'h74;  // FDC B FIFO Data Register

    // QIC-117 Tape Registers (new)
    localparam ADDR_TAPE_STATUS  = 8'h78;  // Tape status register
    localparam ADDR_TAPE_POS     = 8'h7C;  // Segment/track position
    localparam ADDR_TAPE_CMD     = 8'h80;  // Direct command / last command
    localparam ADDR_TAPE_DETECT_CTRL   = 8'h84;  // Detection control
    localparam ADDR_TAPE_DETECT_STATUS = 8'h88;  // Detection status/flags
    localparam ADDR_TAPE_VENDOR_MODEL  = 8'h8C;  // Vendor and model IDs
    localparam ADDR_TAPE_DRIVE_INFO    = 8'h90;  // Drive type, tracks, rates
    localparam ADDR_TAPE_DATA_FIFO     = 8'h94;  // Tape data FIFO read port
    localparam ADDR_TAPE_DATA_STATUS   = 8'h98;  // Tape data streaming status
    localparam ADDR_TAPE_BLOCK_INFO    = 8'h9C;  // Current block info

    //-------------------------------------------------------------------------
    // Version constant
    //-------------------------------------------------------------------------
    localparam [31:0] HW_VERSION = 32'hFD02_0000;  // FluxRipper v2.0.0 (Dual)

    //-------------------------------------------------------------------------
    // Internal registers
    //-------------------------------------------------------------------------
    reg [7:0]  tdr_reg;                   // Tape Drive Register (stub)
    reg [7:0]  dor_reg;                   // Digital Output Register
    reg [7:0]  ccr_reg;                   // Configuration Control Register

    // Copy control registers
    reg        copy_start;
    reg        copy_stop;
    reg        copy_verify;
    reg [1:0]  copy_src_drive;
    reg [1:0]  copy_dst_drive;
    reg [2:0]  copy_state;
    reg [31:0] copy_sectors_done;

    //-------------------------------------------------------------------------
    // TDR Tape Mode Assignments
    //-------------------------------------------------------------------------
    assign tape_mode_en = tdr_reg[7];
    assign tape_select  = tdr_reg[2:0];

    //-------------------------------------------------------------------------
    // Tape Data FIFO (for streaming capture)
    //-------------------------------------------------------------------------
    localparam TAPE_FIFO_DEPTH = 512;
    localparam TAPE_FIFO_BITS  = 9;

    reg  [7:0]  tape_fifo_mem [0:TAPE_FIFO_DEPTH-1];
    reg  [TAPE_FIFO_BITS-1:0] tape_fifo_wr_ptr;
    reg  [TAPE_FIFO_BITS-1:0] tape_fifo_rd_ptr;
    reg  [TAPE_FIFO_BITS:0]   tape_fifo_count;
    wire        tape_fifo_full  = (tape_fifo_count == TAPE_FIFO_DEPTH);
    wire        tape_fifo_empty = (tape_fifo_count == 0);
    reg         tape_fifo_overflow;
    wire [7:0]  tape_fifo_rd_data = tape_fifo_mem[tape_fifo_rd_ptr];

    //-------------------------------------------------------------------------
    // Tape Status Value Constructions
    //-------------------------------------------------------------------------
    // QIC-117 Tape Status register (read-only)
    wire [31:0] tape_status_value = {
        2'd0,                               // [31:30] reserved
        tape_last_command,                  // [29:24] last command
        tape_error,                         // [23] error
        tape_ready,                         // [22] ready
        tape_command_active,                // [21] command active
        5'd0,                               // [20:16] reserved
        tape_status,                        // [15:8] status byte
        8'd0                                // [7:0] reserved
    };

    // Tape position register (read-only)
    wire [31:0] tape_position_value = {
        11'd0,                              // [31:21] reserved
        tape_track,                         // [20:16] track
        tape_segment                        // [15:0] segment
    };

    // Drive detection status register (read-only)
    wire [31:0] tape_detect_status_value = {
        28'd0,                              // [31:4] reserved
        tape_drive_detected,                // [3] drive found
        tape_detect_error,                  // [2] error occurred
        tape_detect_complete,               // [1] detection done
        tape_detect_in_progress             // [0] detection running
    };

    // Vendor/model register (read-only)
    wire [31:0] tape_vendor_model_value = {
        tape_detected_config,               // [31:24] config
        8'd0,                               // [23:16] reserved
        tape_detected_model,                // [15:8] model
        tape_detected_vendor                // [7:0] vendor
    };

    // Drive info register (read-only)
    wire [31:0] tape_drive_info_value = {
        14'd0,                              // [31:18] reserved
        tape_detected_rates,                // [17:16] data rates
        4'd0,                               // [15:12] reserved
        tape_detected_type,                 // [11:8] drive type enum
        3'd0,                               // [7:5] reserved
        tape_detected_max_tracks            // [4:0] max tracks
    };

    // Tape data status register (read-only)
    wire [31:0] tape_data_status_value = {
        tape_streaming,                     // [31] streaming
        tape_fifo_overflow,                 // [30] overflow
        tape_fifo_full,                     // [29] full
        tape_fifo_empty,                    // [28] empty
        tape_is_file_mark,                  // [27] file mark
        tape_is_eod,                        // [26] EOD
        tape_fifo_count[9:0],               // [25:16] FIFO level
        tape_good_blocks                    // [15:0] good blocks
    };

    // Tape block info register (read-only)
    wire [31:0] tape_block_info_value = {
        tape_block_header,                  // [31:24] header
        3'd0,                               // [23:21] reserved
        tape_block_in_segment,              // [20:16] block number
        7'd0,                               // [15:9] reserved
        tape_byte_in_block                  // [8:0] byte position
    };

    // Tape data FIFO register (read-only, reading advances pointer)
    wire [31:0] tape_data_fifo_value = {
        tape_segment_count,                 // [31:16] segments
        tape_error_count[7:0],              // [15:8] errors
        tape_fifo_rd_data                   // [7:0] data byte
    };

    //-------------------------------------------------------------------------
    // AXI State Machine
    //-------------------------------------------------------------------------
    reg [7:0]  write_addr_reg;
    reg [7:0]  read_addr_reg;

    localparam S_IDLE  = 2'd0;
    localparam S_WRITE = 2'd1;
    localparam S_READ  = 2'd2;
    localparam S_RESP  = 2'd3;

    reg [1:0] state;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            state <= S_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rdata <= 32'd0;

            // Initialize registers
            dual_enable <= 1'b0;
            sync_index <= 1'b0;
            if_a_drive_sel <= 2'b00;
            if_b_drive_sel <= 2'b00;
            data_rate <= 2'b10;           // 500 Kbps default
            step_rate_sel <= 2'b10;       // 2ms step rate
            double_step <= 1'b0;
            rpm_360 <= 1'b0;
            motor_on_cmd <= 4'b0000;
            sw_reset <= 1'b0;
            dor_reg <= 8'h00;
            tdr_reg <= 8'h00;
            ccr_reg <= 8'hE0;  // Default: all auto-detect enabled (bits 7:5)

            // Auto-detection defaults (enabled)
            mac_zone_enable <= 1'b0;       // Mac zone mode off by default
            auto_double_step_en <= 1'b1;   // Auto double-step enabled
            auto_data_rate_en <= 1'b1;     // Auto data rate enabled
            auto_encoding_en <= 1'b1;      // Auto encoding enabled

            fdc_a_cmd_byte <= 8'd0;
            fdc_a_cmd_valid <= 1'b0;
            fdc_a_fifo_data_in <= 8'd0;
            fdc_b_cmd_byte <= 8'd0;
            fdc_b_cmd_valid <= 1'b0;
            fdc_b_fifo_data_in <= 8'd0;

            flux_capture_enable_a <= 1'b0;
            flux_capture_enable_b <= 1'b0;
            flux_capture_mode_a <= 2'b00;
            flux_capture_mode_b <= 2'b00;

            copy_start <= 1'b0;
            copy_stop <= 1'b0;
            copy_verify <= 1'b0;
            copy_src_drive <= 2'b00;
            copy_dst_drive <= 2'b01;
            copy_state <= 3'd0;
            copy_sectors_done <= 32'd0;

            // Eject commands (one-shot)
            eject_cmd_a <= 1'b0;
            eject_cmd_b <= 1'b0;

            // Tape registers
            tape_direct_cmd     <= 6'd0;
            tape_direct_strobe  <= 1'b0;
            tape_start_detect   <= 1'b0;
            tape_abort_detect   <= 1'b0;
            tape_fifo_wr_ptr    <= {TAPE_FIFO_BITS{1'b0}};
            tape_fifo_rd_ptr    <= {TAPE_FIFO_BITS{1'b0}};
            tape_fifo_count     <= {(TAPE_FIFO_BITS+1){1'b0}};
            tape_fifo_overflow  <= 1'b0;
        end else begin
            // Clear one-shot signals
            fdc_a_cmd_valid <= 1'b0;
            fdc_b_cmd_valid <= 1'b0;
            sw_reset <= 1'b0;
            copy_start <= 1'b0;
            copy_stop <= 1'b0;
            eject_cmd_a <= 1'b0;
            eject_cmd_b <= 1'b0;
            tape_direct_strobe <= 1'b0;
            tape_start_detect  <= 1'b0;
            tape_abort_detect  <= 1'b0;

            case (state)
                S_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_arready <= 1'b1;

                    if (s_axi_awvalid && s_axi_awready) begin
                        write_addr_reg <= s_axi_awaddr;
                        s_axi_awready <= 1'b0;
                        s_axi_wready <= 1'b1;
                        state <= S_WRITE;
                    end else if (s_axi_arvalid && s_axi_arready) begin
                        read_addr_reg <= s_axi_araddr;
                        s_axi_arready <= 1'b0;
                        state <= S_READ;
                    end
                end

                S_WRITE: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wready <= 1'b0;

                        // Process write
                        case (write_addr_reg)
                            ADDR_DOR: begin
                                dor_reg <= s_axi_wdata[7:0];
                                motor_on_cmd <= s_axi_wdata[7:4];
                                if_a_drive_sel <= s_axi_wdata[1:0];
                                sw_reset <= ~s_axi_wdata[2];  // Active low reset
                            end

                            ADDR_TDR: begin
                                tdr_reg <= s_axi_wdata[7:0];
                            end

                            ADDR_MSR_DSR: begin
                                // Write to DSR
                                data_rate <= s_axi_wdata[1:0];
                                if (s_axi_wdata[7])  // SWRST bit
                                    sw_reset <= 1'b1;
                            end

                            ADDR_DATA: begin
                                // Write to FDC A FIFO
                                fdc_a_cmd_byte <= s_axi_wdata[7:0];
                                fdc_a_cmd_valid <= 1'b1;
                            end

                            ADDR_DIR_CCR: begin
                                // Write to CCR (Configuration Control Register)
                                // [1:0] = data_rate (250K/300K/500K/1M)
                                // [3:2] = reserved
                                // [4]   = mac_zone_enable (Mac variable-speed)
                                // [5]   = auto_double_step_en (auto track density)
                                // [6]   = auto_data_rate_en (auto data rate)
                                // [7]   = auto_encoding_en (auto encoding)
                                ccr_reg <= s_axi_wdata[7:0];
                                data_rate <= s_axi_wdata[1:0];
                                mac_zone_enable <= s_axi_wdata[4];
                                auto_double_step_en <= s_axi_wdata[5];
                                auto_data_rate_en <= s_axi_wdata[6];
                                auto_encoding_en <= s_axi_wdata[7];
                            end

                            ADDR_FLUX_CTRL: begin
                                flux_capture_enable_a <= s_axi_wdata[0];
                                flux_capture_mode_a <= s_axi_wdata[3:2];
                            end

                            ADDR_DUAL_CTRL: begin
                                dual_enable <= s_axi_wdata[7];
                                sync_index <= s_axi_wdata[6];
                                if_b_drive_sel <= s_axi_wdata[3:2];
                                if_a_drive_sel <= s_axi_wdata[1:0];
                            end

                            ADDR_FLUX_CTRL_A: begin
                                flux_capture_enable_a <= s_axi_wdata[0];
                                flux_capture_mode_a <= s_axi_wdata[3:2];
                            end

                            ADDR_FLUX_CTRL_B: begin
                                flux_capture_enable_b <= s_axi_wdata[0];
                                flux_capture_mode_b <= s_axi_wdata[3:2];
                            end

                            ADDR_COPY_CTRL: begin
                                copy_start <= s_axi_wdata[7];
                                copy_stop <= s_axi_wdata[6];
                                copy_verify <= s_axi_wdata[5];
                                copy_dst_drive <= s_axi_wdata[3:2];
                                copy_src_drive <= s_axi_wdata[1:0];
                            end

                            ADDR_EJECT_CTRL: begin
                                // Motorized eject control register
                                // [0] = Eject Interface A (write 1 to eject)
                                // [1] = Eject Interface B (write 1 to eject)
                                eject_cmd_a <= s_axi_wdata[0];
                                eject_cmd_b <= s_axi_wdata[1];
                            end

                            ADDR_B_MSR_DSR: begin
                                // FDC B DSR write (shares data_rate for now)
                                // Could be extended for per-FDC data rate
                            end

                            ADDR_B_DATA: begin
                                // Write to FDC B FIFO
                                fdc_b_cmd_byte <= s_axi_wdata[7:0];
                                fdc_b_cmd_valid <= 1'b1;
                            end

                            ADDR_TAPE_CMD: begin
                                // Direct command interface - write command code to issue it
                                tape_direct_cmd    <= s_axi_wdata[5:0];
                                tape_direct_strobe <= 1'b1;
                            end

                            ADDR_TAPE_DETECT_CTRL: begin
                                // Detection control - write to start/abort detection
                                // Bit 0: start detection (pulse)
                                // Bit 1: abort detection (pulse)
                                tape_start_detect <= s_axi_wdata[0];
                                tape_abort_detect <= s_axi_wdata[1];
                            end
                        endcase

                        s_axi_bresp <= 2'b00;  // OKAY
                        s_axi_bvalid <= 1'b1;
                        state <= S_RESP;
                    end
                end

                S_READ: begin
                    case (read_addr_reg)
                        ADDR_SRA_SRB: begin
                            // Pack SRA and SRB
                            s_axi_rdata <= {16'd0,
                                           motor_running[1], motor_running[0], 6'd0,  // SRB
                                           fdc_a_rqm, fdc_a_dio, 6'd0};               // SRA
                        end

                        ADDR_DOR: begin
                            s_axi_rdata <= {24'd0, dor_reg};
                        end

                        ADDR_TDR: begin
                            s_axi_rdata <= {24'd0, tdr_reg};
                        end

                        ADDR_MSR_DSR: begin
                            // Return MSR on read
                            s_axi_rdata <= {24'd0,
                                           fdc_a_rqm, fdc_a_dio, 1'b0, fdc_a_busy,
                                           motor_running[3:0]};
                        end

                        ADDR_DATA: begin
                            // Read from FDC A FIFO
                            s_axi_rdata <= {24'd0, fdc_a_fifo_data_out};
                        end

                        ADDR_DIR_CCR: begin
                            // Return DIR on read (disk change bit)
                            // DIR: Bit 7 = DSKCHG (disk changed - active high, inverted from pin)
                            // Based on currently selected drive on Interface A
                            s_axi_rdata <= {24'd0,
                                           (if_a_drive_sel[0] ? dskchg_a_drv1 : dskchg_a_drv0), // Bit 7: DSKCHG
                                           7'd0};                                               // Bits 6-0: reserved
                        end

                        ADDR_QUALITY: begin
                            s_axi_rdata <= {8'd0, 8'd128, 8'd128, fdc_a_lock_quality};
                        end

                        ADDR_VERSION: begin
                            s_axi_rdata <= HW_VERSION;
                        end

                        ADDR_DUAL_CTRL: begin
                            s_axi_rdata <= {24'd0,
                                           dual_enable, sync_index, 2'd0,
                                           if_b_drive_sel, if_a_drive_sel};
                        end

                        ADDR_FDC_A_STATUS: begin
                            s_axi_rdata <= {16'd0,
                                           fdc_a_pll_locked, fdc_a_busy, fdc_a_dio, fdc_a_rqm,
                                           motor_at_speed[1:0], motor_running[1:0]};
                        end

                        ADDR_FDC_B_STATUS: begin
                            s_axi_rdata <= {16'd0,
                                           fdc_b_pll_locked, fdc_b_busy, fdc_b_dio, fdc_b_rqm,
                                           motor_at_speed[3:2], motor_running[3:2]};
                        end

                        ADDR_TRACK_A: begin
                            s_axi_rdata <= {24'd0, fdc_a_current_track};
                        end

                        ADDR_TRACK_B: begin
                            s_axi_rdata <= {24'd0, fdc_b_current_track};
                        end

                        ADDR_FLUX_CTRL_A: begin
                            s_axi_rdata <= {28'd0, flux_capture_mode_a, 1'b0, flux_capture_enable_a};
                        end

                        ADDR_FLUX_CTRL_B: begin
                            s_axi_rdata <= {28'd0, flux_capture_mode_b, 1'b0, flux_capture_enable_b};
                        end

                        ADDR_COPY_CTRL: begin
                            s_axi_rdata <= {24'd0,
                                           1'b0, 1'b0, copy_verify, 1'b0,
                                           copy_dst_drive, copy_src_drive};
                        end

                        ADDR_COPY_STATUS: begin
                            s_axi_rdata <= {copy_state, 5'd0, copy_sectors_done[23:0]};
                        end

                        ADDR_AUTO_STATUS_A: begin
                            // Auto-detection status for Interface A
                            // [1:0]  = detected data rate
                            // [4:2]  = detected encoding
                            // [5]    = data rate locked
                            // [6]    = encoding locked
                            // [7]    = drive 0 RPM is 360
                            // [8]    = detected_40_track_a (40-track disk detected)
                            // [9]    = track_density_detected_a (analysis complete)
                            // [11:10] = reserved
                            // [15:12] = rpm_valid for drives 0-3
                            // [19:16] = detected_rpm_360 for drives 0-3
                            s_axi_rdata <= {12'd0,
                                           detected_rpm_360, rpm_valid,
                                           2'd0, track_density_detected_a, detected_40_track_a,
                                           detected_rpm_360[0], encoding_locked_a,
                                           data_rate_locked_a, detected_encoding_a,
                                           detected_data_rate_a};
                        end

                        ADDR_AUTO_STATUS_B: begin
                            // Auto-detection status for Interface B
                            // [1:0]  = detected data rate
                            // [4:2]  = detected encoding
                            // [5]    = data rate locked
                            // [6]    = encoding locked
                            // [7]    = drive 2 RPM is 360
                            // [8]    = detected_40_track_b (40-track disk detected)
                            // [9]    = track_density_detected_b (analysis complete)
                            s_axi_rdata <= {12'd0,
                                           detected_rpm_360, rpm_valid,
                                           2'd0, track_density_detected_b, detected_40_track_b,
                                           detected_rpm_360[2], encoding_locked_b,
                                           data_rate_locked_b, detected_encoding_b,
                                           detected_data_rate_b};
                        end

                        ADDR_DRIVE_PROFILE_A: begin
                            // Drive Profile A - 32-bit packed profile word
                            // [1:0]   = Form factor (00=unk, 01=3.5", 10=5.25", 11=8")
                            // [3:2]   = Density cap (00=DD, 01=HD, 10=ED, 11=unk)
                            // [5:4]   = Track density (00=40T, 01=80T, 10=77T, 11=unk)
                            // [8:6]   = Encoding detected
                            // [9]     = Hard-sectored media
                            // [10]    = Variable-speed zones (Mac GCR)
                            // [11]    = HEAD_LOAD required (8" drive)
                            // [15:12] = Reserved
                            // [23:16] = RPM / 10 (30=300, 36=360)
                            // [31:24] = Quality score (0-255)
                            s_axi_rdata <= drive_profile_a;
                        end

                        ADDR_DRIVE_PROFILE_B: begin
                            // Drive Profile B - Same format as Profile A
                            s_axi_rdata <= drive_profile_b;
                        end

                        ADDR_B_MSR_DSR: begin
                            // FDC B MSR
                            s_axi_rdata <= {24'd0,
                                           fdc_b_rqm, fdc_b_dio, 1'b0, fdc_b_busy,
                                           motor_running[3:0]};
                        end

                        ADDR_B_DATA: begin
                            // Read from FDC B FIFO
                            s_axi_rdata <= {24'd0, fdc_b_fifo_data_out};
                        end

                        // QIC-117 Tape Registers
                        ADDR_TAPE_STATUS: begin
                            s_axi_rdata <= tape_status_value;
                        end

                        ADDR_TAPE_POS: begin
                            s_axi_rdata <= tape_position_value;
                        end

                        ADDR_TAPE_CMD: begin
                            s_axi_rdata <= {26'd0, tape_last_command};
                        end

                        ADDR_TAPE_DETECT_CTRL: begin
                            // Read back shows detection status (same as status reg for convenience)
                            s_axi_rdata <= tape_detect_status_value;
                        end

                        ADDR_TAPE_DETECT_STATUS: begin
                            s_axi_rdata <= tape_detect_status_value;
                        end

                        ADDR_TAPE_VENDOR_MODEL: begin
                            s_axi_rdata <= tape_vendor_model_value;
                        end

                        ADDR_TAPE_DRIVE_INFO: begin
                            s_axi_rdata <= tape_drive_info_value;
                        end

                        ADDR_TAPE_DATA_FIFO: begin
                            s_axi_rdata <= tape_data_fifo_value;
                            // Note: FIFO read pointer advanced in separate always block
                        end

                        ADDR_TAPE_DATA_STATUS: begin
                            s_axi_rdata <= tape_data_status_value;
                        end

                        ADDR_TAPE_BLOCK_INFO: begin
                            s_axi_rdata <= tape_block_info_value;
                        end

                        default: begin
                            s_axi_rdata <= 32'hDEADBEEF;
                        end
                    endcase

                    s_axi_rresp <= 2'b00;  // OKAY
                    s_axi_rvalid <= 1'b1;
                    state <= S_RESP;
                end

                S_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        state <= S_IDLE;
                    end
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Tape FIFO Write Logic
    //-------------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            // Reset handled in main always block
        end else if (tape_data_valid && tape_mode_en) begin
            if (!tape_fifo_full) begin
                tape_fifo_mem[tape_fifo_wr_ptr] <= tape_data_byte;
                tape_fifo_wr_ptr <= tape_fifo_wr_ptr + 1'b1;
            end else begin
                tape_fifo_overflow <= 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Tape FIFO Read Pointer Update (on register read)
    //-------------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            // Reset handled in main always block
        end else begin
            // Advance read pointer when FIFO register is read and FIFO not empty
            if (s_axi_rvalid && s_axi_rready &&
                (read_addr_reg == ADDR_TAPE_DATA_FIFO) && !tape_fifo_empty) begin
                tape_fifo_rd_ptr <= tape_fifo_rd_ptr + 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Tape FIFO Count Management
    //-------------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            // Reset handled in main always block
        end else begin
            // Update FIFO count based on write and read operations
            case ({tape_data_valid && tape_mode_en && !tape_fifo_full,
                   s_axi_rvalid && s_axi_rready && (read_addr_reg == ADDR_TAPE_DATA_FIFO) && !tape_fifo_empty})
                2'b10: tape_fifo_count <= tape_fifo_count + 1'b1;  // Write only
                2'b01: tape_fifo_count <= tape_fifo_count - 1'b1;  // Read only
                default: ; // No change or simultaneous
            endcase
        end
    end

endmodule
