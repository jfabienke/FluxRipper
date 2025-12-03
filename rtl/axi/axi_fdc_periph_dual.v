//-----------------------------------------------------------------------------
// AXI4-Lite FDC Peripheral - Dual Interface Version
// Provides memory-mapped access to dual FDC registers for MicroBlaze V
//
// Register Map:
//   0x00-0x2C: Standard 82077AA + FluxRipper registers (Interface A)
//   0x30-0x58: Dual interface extension registers
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-04 11:46
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
    input  wire        drive_profile_locked_b    // Profile stable for B
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
    localparam ADDR_DRIVE_PROFILE_B = 8'h74;  // Drive profile B

    // FDC B register mirrors (offset for spacing)
    localparam ADDR_B_MSR_DSR    = 8'h78;  // FDC B Main Status / Data Rate
    localparam ADDR_B_DATA       = 8'h7C;  // FDC B FIFO Data Register

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
        end else begin
            // Clear one-shot signals
            fdc_a_cmd_valid <= 1'b0;
            fdc_b_cmd_valid <= 1'b0;
            sw_reset <= 1'b0;
            copy_start <= 1'b0;
            copy_stop <= 1'b0;
            eject_cmd_a <= 1'b0;
            eject_cmd_b <= 1'b0;

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
                            s_axi_rdata <= {24'd0, 8'h00};  // TODO: Connect dskchg
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

endmodule
