//-----------------------------------------------------------------------------
// Auto-Detection Testbench
// FluxRipper - FPGA-based Floppy Disk Controller
//
// Tests the auto-detection features:
//   - RPM detection (300 vs 360 RPM)
//   - Data rate detection (250K/300K/500K/1M)
//   - Encoding auto-selection
//   - Track density detection (40 vs 80 track)
//   - Drive profile detection (form factor, density capability)
//
// Target: Simulation (Vivado/Icarus Verilog)
// Updated: 2025-12-04 11:55
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_auto_detect;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    localparam CLK_PERIOD = 5;        // 200 MHz = 5ns period
    localparam CLK_FREQ = 200_000_000;

    // Revolution times in clocks (at 200 MHz)
    localparam REV_TIME_300RPM = 40_000_000;  // 200ms
    localparam REV_TIME_360RPM = 33_333_333;  // 166.67ms

    // Bit cell times for different data rates (in clocks)
    localparam BIT_CELL_250K = 800;   // 4.0 µs
    localparam BIT_CELL_300K = 667;   // 3.33 µs
    localparam BIT_CELL_500K = 400;   // 2.0 µs
    localparam BIT_CELL_1M   = 200;   // 1.0 µs

    //-------------------------------------------------------------------------
    // Signals
    //-------------------------------------------------------------------------
    reg         clk;
    reg         reset;

    // Index handler signals
    reg         index_0, index_1, index_2, index_3;
    wire [3:0]  index_pulse;
    wire [31:0] revolution_time_0, revolution_time_1, revolution_time_2, revolution_time_3;
    wire [3:0]  rpm_300, rpm_360, rpm_valid;

    // Flux analyzer signals
    reg         flux_enable;
    reg         flux_transition;
    wire [15:0] avg_interval;
    wire [15:0] min_interval;
    wire [15:0] max_interval;
    wire [1:0]  detected_rate;
    wire        rate_valid;
    wire        rate_locked;

    // Encoding detector signals
    reg         enc_enable;
    reg         bit_in, bit_valid;
    reg         mfm_sync, fm_sync, m2fm_sync;
    reg         gcr_cbm_sync, gcr_apple_sync, tandy_sync;
    wire [2:0]  detected_encoding;
    wire        encoding_valid;
    wire        encoding_locked;

    // Track width analyzer signals
    reg         track_enable;
    reg  [7:0]  id_cylinder;
    reg         id_valid;
    reg  [7:0]  physical_track;
    wire        double_step_recommended;
    wire        analysis_complete;
    wire [7:0]  detected_tracks;

    // Drive profile detector signals
    reg         profile_enable;
    reg         profile_rpm_valid;
    reg         profile_rpm_300, profile_rpm_360;
    reg         profile_track_density_valid;
    reg         profile_detected_40_track;
    reg         profile_data_rate_valid;
    reg  [1:0]  profile_detected_data_rate;
    reg         profile_data_rate_locked;
    reg         profile_encoding_valid;
    reg  [2:0]  profile_detected_encoding;
    reg         profile_encoding_locked;
    reg  [7:0]  profile_lock_quality;
    reg         profile_pll_locked;
    reg         profile_drive_ready;
    reg         profile_disk_present;
    reg         profile_write_protect;
    reg         profile_head_load_active;
    reg         profile_sector_pulse_detected;
    reg  [3:0]  profile_sector_count;
    reg  [7:0]  profile_current_track;

    wire [31:0] profile_drive_profile;
    wire        profile_valid;
    wire        profile_locked;
    wire [1:0]  profile_form_factor;
    wire [1:0]  profile_density_cap;
    wire [1:0]  profile_track_density;
    wire [7:0]  profile_quality_score;
    wire        profile_is_hard_sectored;
    wire        profile_is_variable_speed;
    wire        profile_needs_head_load;

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // DUT Instantiation - Index Handler
    //-------------------------------------------------------------------------
    index_handler_dual u_index_handler (
        .clk(clk),
        .reset(reset),
        .clk_freq(CLK_FREQ),
        .index_0(index_0),
        .index_1(index_1),
        .index_2(index_2),
        .index_3(index_3),
        .index_pulse(index_pulse),
        .revolution_time_0(revolution_time_0),
        .revolution_time_1(revolution_time_1),
        .revolution_time_2(revolution_time_2),
        .revolution_time_3(revolution_time_3),
        .rpm_300(rpm_300),
        .rpm_360(rpm_360),
        .rpm_valid(rpm_valid),
        .revolution_count_0(),
        .revolution_count_1(),
        .revolution_count_2(),
        .revolution_count_3()
    );

    //-------------------------------------------------------------------------
    // DUT Instantiation - Flux Analyzer
    //-------------------------------------------------------------------------
    flux_analyzer u_flux_analyzer (
        .clk(clk),
        .reset(reset),
        .enable(flux_enable),
        .flux_transition(flux_transition),
        .avg_interval(avg_interval),
        .min_interval(min_interval),
        .max_interval(max_interval),
        .detected_rate(detected_rate),
        .rate_valid(rate_valid),
        .rate_locked(rate_locked)
    );

    //-------------------------------------------------------------------------
    // DUT Instantiation - Encoding Detector
    //-------------------------------------------------------------------------
    encoding_detector u_enc_detector (
        .clk(clk),
        .reset(reset),
        .enable(enc_enable),
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        .mfm_sync(mfm_sync),
        .fm_sync(fm_sync),
        .m2fm_sync(m2fm_sync),
        .gcr_cbm_sync(gcr_cbm_sync),
        .gcr_apple_sync(gcr_apple_sync),
        .tandy_sync(tandy_sync),
        .detected_encoding(detected_encoding),
        .encoding_valid(encoding_valid),
        .encoding_locked(encoding_locked),
        .match_count(),
        .sync_history()
    );

    //-------------------------------------------------------------------------
    // DUT Instantiation - Track Width Analyzer
    //-------------------------------------------------------------------------
    track_width_analyzer u_track_analyzer (
        .clk(clk),
        .reset(reset),
        .enable(track_enable),
        .id_cylinder(id_cylinder),
        .id_valid(id_valid),
        .physical_track(physical_track),
        .double_step_recommended(double_step_recommended),
        .analysis_complete(analysis_complete),
        .detected_tracks(detected_tracks)
    );

    //-------------------------------------------------------------------------
    // DUT Instantiation - Drive Profile Detector
    //-------------------------------------------------------------------------
    drive_profile_detector u_profile_detector (
        .clk(clk),
        .reset(reset),
        .enable(profile_enable),

        // RPM detection inputs
        .rpm_valid(profile_rpm_valid),
        .rpm_300(profile_rpm_300),
        .rpm_360(profile_rpm_360),

        // Track density inputs
        .track_density_valid(profile_track_density_valid),
        .detected_40_track(profile_detected_40_track),

        // Data rate inputs
        .data_rate_valid(profile_data_rate_valid),
        .detected_data_rate(profile_detected_data_rate),
        .data_rate_locked(profile_data_rate_locked),

        // Encoding inputs
        .encoding_valid(profile_encoding_valid),
        .detected_encoding(profile_detected_encoding),
        .encoding_locked(profile_encoding_locked),

        // PLL quality
        .lock_quality(profile_lock_quality),
        .pll_locked(profile_pll_locked),

        // Drive status
        .drive_ready(profile_drive_ready),
        .disk_present(profile_disk_present),
        .write_protect(profile_write_protect),
        .head_load_active(profile_head_load_active),

        // Hard-sector detection
        .sector_pulse_detected(profile_sector_pulse_detected),
        .sector_count(profile_sector_count),

        // Track position
        .current_track(profile_current_track),

        // Probe interface - stub
        .probe_request(),
        .probe_data_rate(),
        .probe_complete(1'b0),
        .probe_success(1'b0),

        // Profile outputs
        .drive_profile(profile_drive_profile),
        .profile_valid(profile_valid),
        .profile_locked(profile_locked),
        .form_factor(profile_form_factor),
        .density_cap(profile_density_cap),
        .track_density(profile_track_density),
        .quality_score(profile_quality_score),
        .is_hard_sectored(profile_is_hard_sectored),
        .is_variable_speed(profile_is_variable_speed),
        .needs_head_load(profile_needs_head_load)
    );

    //-------------------------------------------------------------------------
    // Test Tasks
    //-------------------------------------------------------------------------

    // Generate index pulses at specified RPM
    task generate_index_pulse;
        input integer drive;
        input integer revolution_time;
        begin
            case (drive)
                0: begin
                    #(revolution_time * CLK_PERIOD);
                    index_0 = 1'b1;
                    #(CLK_PERIOD * 100);  // 100 clock pulse width
                    index_0 = 1'b0;
                end
                1: begin
                    #(revolution_time * CLK_PERIOD);
                    index_1 = 1'b1;
                    #(CLK_PERIOD * 100);
                    index_1 = 1'b0;
                end
                2: begin
                    #(revolution_time * CLK_PERIOD);
                    index_2 = 1'b1;
                    #(CLK_PERIOD * 100);
                    index_2 = 1'b0;
                end
                3: begin
                    #(revolution_time * CLK_PERIOD);
                    index_3 = 1'b1;
                    #(CLK_PERIOD * 100);
                    index_3 = 1'b0;
                end
            endcase
        end
    endtask

    // Generate flux transitions at specified interval
    task generate_flux_transitions;
        input integer interval;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                #(interval * CLK_PERIOD);
                flux_transition = 1'b1;
                #CLK_PERIOD;
                flux_transition = 1'b0;
            end
        end
    endtask

    // Generate sync pulses for encoding detection
    task generate_sync_pulses;
        input integer encoding;  // 0=MFM, 1=FM, 2=CBM, 3=Apple, 4=M2FM, 5=Tandy
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                #(CLK_PERIOD * 1000);  // Some gap between syncs
                case (encoding)
                    0: begin mfm_sync = 1'b1; #CLK_PERIOD; mfm_sync = 1'b0; end
                    1: begin fm_sync = 1'b1; #CLK_PERIOD; fm_sync = 1'b0; end
                    2: begin gcr_cbm_sync = 1'b1; #CLK_PERIOD; gcr_cbm_sync = 1'b0; end
                    3: begin gcr_apple_sync = 1'b1; #CLK_PERIOD; gcr_apple_sync = 1'b0; end
                    4: begin m2fm_sync = 1'b1; #CLK_PERIOD; m2fm_sync = 1'b0; end
                    5: begin tandy_sync = 1'b1; #CLK_PERIOD; tandy_sync = 1'b0; end
                endcase
            end
        end
    endtask

    // Simulate ID field read (cylinder from sector header)
    // For 40-track disk in 80-track drive: logical cylinder = physical_track / 2
    task simulate_id_field;
        input [7:0] cylinder;
        input [7:0] phys_track;
        begin
            id_cylinder = cylinder;
            physical_track = phys_track;
            #CLK_PERIOD;
            id_valid = 1'b1;
            #CLK_PERIOD;
            id_valid = 1'b0;
            #(CLK_PERIOD * 100);  // Gap between ID reads
        end
    endtask

    //-------------------------------------------------------------------------
    // Test Sequence
    //-------------------------------------------------------------------------
    integer test_pass;
    integer test_fail;

    initial begin
        $display("===========================================");
        $display("FluxRipper Auto-Detection Testbench");
        $display("===========================================");

        test_pass = 0;
        test_fail = 0;

        // Initialize signals
        reset = 1;
        index_0 = 0; index_1 = 0; index_2 = 0; index_3 = 0;
        flux_enable = 0;
        flux_transition = 0;
        enc_enable = 0;
        bit_in = 0; bit_valid = 0;
        mfm_sync = 0; fm_sync = 0; m2fm_sync = 0;
        gcr_cbm_sync = 0; gcr_apple_sync = 0; tandy_sync = 0;
        track_enable = 0;
        id_cylinder = 0;
        id_valid = 0;
        physical_track = 0;

        // Profile detector initialization
        profile_enable = 0;
        profile_rpm_valid = 0;
        profile_rpm_300 = 0; profile_rpm_360 = 0;
        profile_track_density_valid = 0;
        profile_detected_40_track = 0;
        profile_data_rate_valid = 0;
        profile_detected_data_rate = 2'b10;  // 500K default
        profile_data_rate_locked = 0;
        profile_encoding_valid = 0;
        profile_detected_encoding = 3'b000;  // MFM default
        profile_encoding_locked = 0;
        profile_lock_quality = 8'd200;
        profile_pll_locked = 0;
        profile_drive_ready = 0;
        profile_disk_present = 0;
        profile_write_protect = 0;
        profile_head_load_active = 0;
        profile_sector_pulse_detected = 0;
        profile_sector_count = 4'd0;
        profile_current_track = 8'd0;

        #(CLK_PERIOD * 100);
        reset = 0;
        #(CLK_PERIOD * 100);

        //---------------------------------------------------------------------
        // Test 1: RPM Detection - 300 RPM
        //---------------------------------------------------------------------
        $display("\n--- Test 1: RPM Detection (300 RPM) ---");

        // Generate 3 index pulses at 300 RPM for drive 0
        fork
            begin
                generate_index_pulse(0, REV_TIME_300RPM);
                generate_index_pulse(0, REV_TIME_300RPM);
                generate_index_pulse(0, REV_TIME_300RPM);
            end
        join

        #(CLK_PERIOD * 1000);

        if (rpm_valid[0] && rpm_300[0] && !rpm_360[0]) begin
            $display("  PASS: Drive 0 detected as 300 RPM");
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Drive 0 RPM detection incorrect");
            $display("        rpm_valid=%b, rpm_300=%b, rpm_360=%b",
                     rpm_valid[0], rpm_300[0], rpm_360[0]);
            test_fail = test_fail + 1;
        end

        //---------------------------------------------------------------------
        // Test 2: RPM Detection - 360 RPM
        //---------------------------------------------------------------------
        $display("\n--- Test 2: RPM Detection (360 RPM) ---");

        // Generate 3 index pulses at 360 RPM for drive 1
        fork
            begin
                generate_index_pulse(1, REV_TIME_360RPM);
                generate_index_pulse(1, REV_TIME_360RPM);
                generate_index_pulse(1, REV_TIME_360RPM);
            end
        join

        #(CLK_PERIOD * 1000);

        if (rpm_valid[1] && !rpm_300[1] && rpm_360[1]) begin
            $display("  PASS: Drive 1 detected as 360 RPM");
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Drive 1 RPM detection incorrect");
            $display("        rpm_valid=%b, rpm_300=%b, rpm_360=%b",
                     rpm_valid[1], rpm_300[1], rpm_360[1]);
            test_fail = test_fail + 1;
        end

        //---------------------------------------------------------------------
        // Test 3: Data Rate Detection - 500 Kbps
        //---------------------------------------------------------------------
        $display("\n--- Test 3: Data Rate Detection (500 Kbps) ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        flux_enable = 1;

        // Generate flux transitions at 500K rate (~200 clocks average)
        generate_flux_transitions(200, 200);

        #(CLK_PERIOD * 1000);

        if (rate_valid && detected_rate == 2'b00) begin
            $display("  PASS: Data rate detected as 500 Kbps");
            $display("        avg_interval=%d", avg_interval);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Data rate detection incorrect");
            $display("        rate_valid=%b, detected_rate=%b, avg_interval=%d",
                     rate_valid, detected_rate, avg_interval);
            test_fail = test_fail + 1;
        end

        flux_enable = 0;

        //---------------------------------------------------------------------
        // Test 4: Data Rate Detection - 250 Kbps
        //---------------------------------------------------------------------
        $display("\n--- Test 4: Data Rate Detection (250 Kbps) ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        flux_enable = 1;

        // Generate flux transitions at 250K rate (~400 clocks average)
        generate_flux_transitions(400, 200);

        #(CLK_PERIOD * 1000);

        if (rate_valid && detected_rate == 2'b10) begin
            $display("  PASS: Data rate detected as 250 Kbps");
            $display("        avg_interval=%d", avg_interval);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Data rate detection incorrect");
            $display("        rate_valid=%b, detected_rate=%b, avg_interval=%d",
                     rate_valid, detected_rate, avg_interval);
            test_fail = test_fail + 1;
        end

        flux_enable = 0;

        //---------------------------------------------------------------------
        // Test 5: Encoding Detection - MFM
        //---------------------------------------------------------------------
        $display("\n--- Test 5: Encoding Detection (MFM) ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        enc_enable = 1;

        // Generate MFM sync pulses
        generate_sync_pulses(0, 10);

        #(CLK_PERIOD * 5000);

        if (encoding_valid && detected_encoding == 3'b000) begin
            $display("  PASS: Encoding detected as MFM");
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Encoding detection incorrect");
            $display("        encoding_valid=%b, detected_encoding=%b",
                     encoding_valid, detected_encoding);
            test_fail = test_fail + 1;
        end

        //---------------------------------------------------------------------
        // Test 6: Encoding Detection - Apple GCR
        //---------------------------------------------------------------------
        $display("\n--- Test 6: Encoding Detection (Apple GCR) ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        enc_enable = 1;

        // Generate Apple GCR sync pulses
        generate_sync_pulses(3, 10);

        #(CLK_PERIOD * 5000);

        if (encoding_valid && detected_encoding == 3'b011) begin
            $display("  PASS: Encoding detected as Apple GCR");
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Encoding detection incorrect");
            $display("        encoding_valid=%b, detected_encoding=%b",
                     encoding_valid, detected_encoding);
            test_fail = test_fail + 1;
        end

        enc_enable = 0;

        //---------------------------------------------------------------------
        // Test 7: Encoding Lock Stability
        //---------------------------------------------------------------------
        $display("\n--- Test 7: Encoding Lock Stability ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        enc_enable = 1;

        // Generate multiple M2FM sync pulses to achieve lock
        generate_sync_pulses(4, 10);

        #(CLK_PERIOD * 5000);

        if (encoding_locked) begin
            $display("  PASS: Encoding locked after consistent syncs");
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Encoding failed to lock");
            test_fail = test_fail + 1;
        end

        enc_enable = 0;

        //---------------------------------------------------------------------
        // Test 8: 40-Track Disk Detection
        //---------------------------------------------------------------------
        $display("\n--- Test 8: 40-Track Disk Detection ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        track_enable = 1;

        // Simulate 40-track disk in 80-track drive
        // Physical track 0,2,4,6... maps to logical cylinder 0,1,2,3...
        simulate_id_field(8'd0, 8'd0);   // Cyl 0 at track 0 - match
        simulate_id_field(8'd1, 8'd2);   // Cyl 1 at track 2 - mismatch!
        simulate_id_field(8'd2, 8'd4);   // Cyl 2 at track 4 - mismatch!
        simulate_id_field(8'd3, 8'd6);   // Cyl 3 at track 6 - mismatch!
        simulate_id_field(8'd4, 8'd8);   // Cyl 4 at track 8 - mismatch!
        simulate_id_field(8'd5, 8'd10);  // Cyl 5 at track 10 - mismatch!
        simulate_id_field(8'd6, 8'd12);  // Cyl 6 at track 12 - mismatch!
        simulate_id_field(8'd7, 8'd14);  // Cyl 7 at track 14 - mismatch!
        simulate_id_field(8'd8, 8'd16);  // Cyl 8 at track 16 - mismatch!

        #(CLK_PERIOD * 1000);

        if (analysis_complete && double_step_recommended && detected_tracks == 8'd40) begin
            $display("  PASS: 40-track disk detected correctly");
            $display("        double_step_recommended=%b, detected_tracks=%d",
                     double_step_recommended, detected_tracks);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: 40-track detection incorrect");
            $display("        analysis_complete=%b, double_step_recommended=%b, detected_tracks=%d",
                     analysis_complete, double_step_recommended, detected_tracks);
            test_fail = test_fail + 1;
        end

        track_enable = 0;

        //---------------------------------------------------------------------
        // Test 9: 80-Track Disk Detection
        //---------------------------------------------------------------------
        $display("\n--- Test 9: 80-Track Disk Detection ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        track_enable = 1;

        // Simulate 80-track disk - logical cylinder matches physical track
        simulate_id_field(8'd0,  8'd0);   // Cyl 0 at track 0 - match
        simulate_id_field(8'd1,  8'd1);   // Cyl 1 at track 1 - match
        simulate_id_field(8'd2,  8'd2);   // Cyl 2 at track 2 - match
        simulate_id_field(8'd3,  8'd3);   // Cyl 3 at track 3 - match
        simulate_id_field(8'd10, 8'd10);  // Cyl 10 at track 10 - match
        simulate_id_field(8'd20, 8'd20);  // Cyl 20 at track 20 - match
        simulate_id_field(8'd40, 8'd40);  // Cyl 40 at track 40 - match
        simulate_id_field(8'd60, 8'd60);  // Cyl 60 at track 60 - match
        simulate_id_field(8'd79, 8'd79);  // Cyl 79 at track 79 - match

        #(CLK_PERIOD * 1000);

        if (analysis_complete && !double_step_recommended && detected_tracks == 8'd80) begin
            $display("  PASS: 80-track disk detected correctly");
            $display("        double_step_recommended=%b, detected_tracks=%d",
                     double_step_recommended, detected_tracks);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: 80-track detection incorrect");
            $display("        analysis_complete=%b, double_step_recommended=%b, detected_tracks=%d",
                     analysis_complete, double_step_recommended, detected_tracks);
            test_fail = test_fail + 1;
        end

        track_enable = 0;

        //---------------------------------------------------------------------
        // Test 10: Drive Profile - 3.5" HD Drive (300 RPM, 500K)
        //---------------------------------------------------------------------
        $display("\n--- Test 10: Drive Profile (3.5\" HD) ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        profile_enable = 1;

        // Simulate a 3.5" HD drive
        profile_drive_ready = 1;
        profile_disk_present = 1;
        profile_rpm_valid = 1;
        profile_rpm_300 = 1;
        profile_rpm_360 = 0;
        profile_pll_locked = 1;
        profile_lock_quality = 8'd200;
        profile_encoding_valid = 1;
        profile_detected_encoding = 3'b000;  // MFM
        profile_encoding_locked = 1;
        profile_track_density_valid = 1;
        profile_detected_40_track = 0;  // 80-track

        #(CLK_PERIOD * 10000);

        // Check form factor = 3.5" (01), density = HD (01)
        if (profile_valid && profile_form_factor == 2'b01) begin
            $display("  PASS: Form factor correctly identified as 3.5\"");
            $display("        profile_word=0x%08x", profile_drive_profile);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Form factor detection incorrect");
            $display("        profile_valid=%b, form_factor=%b",
                     profile_valid, profile_form_factor);
            test_fail = test_fail + 1;
        end

        profile_enable = 0;

        //---------------------------------------------------------------------
        // Test 11: Drive Profile - 8" Drive (360 RPM + HEAD_LOAD)
        //---------------------------------------------------------------------
        $display("\n--- Test 11: Drive Profile (8\") ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        profile_enable = 1;

        // Simulate an 8" drive
        profile_drive_ready = 1;
        profile_disk_present = 1;
        profile_rpm_valid = 1;
        profile_rpm_300 = 0;
        profile_rpm_360 = 1;          // 360 RPM
        profile_head_load_active = 1;  // HEAD_LOAD required
        profile_pll_locked = 1;
        profile_lock_quality = 8'd180;
        profile_encoding_valid = 1;
        profile_detected_encoding = 3'b001;  // FM
        profile_encoding_locked = 1;
        profile_track_density_valid = 0;

        #(CLK_PERIOD * 10000);

        // Check form factor = 8" (11)
        if (profile_valid && profile_form_factor == 2'b11 && profile_needs_head_load) begin
            $display("  PASS: Form factor correctly identified as 8\" with HEAD_LOAD");
            $display("        profile_word=0x%08x", profile_drive_profile);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: 8\" drive detection incorrect");
            $display("        profile_valid=%b, form_factor=%b, needs_head_load=%b",
                     profile_valid, profile_form_factor, profile_needs_head_load);
            test_fail = test_fail + 1;
        end

        profile_enable = 0;

        //---------------------------------------------------------------------
        // Test 12: Drive Profile - 5.25" HD (360 RPM, no HEAD_LOAD)
        //---------------------------------------------------------------------
        $display("\n--- Test 12: Drive Profile (5.25\" HD) ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        profile_enable = 1;

        // Simulate a 5.25" HD drive
        profile_drive_ready = 1;
        profile_disk_present = 1;
        profile_rpm_valid = 1;
        profile_rpm_300 = 0;
        profile_rpm_360 = 1;           // 360 RPM
        profile_head_load_active = 0;  // No HEAD_LOAD (not 8")
        profile_pll_locked = 1;
        profile_lock_quality = 8'd190;
        profile_encoding_valid = 1;
        profile_detected_encoding = 3'b000;  // MFM
        profile_encoding_locked = 1;
        profile_track_density_valid = 1;
        profile_detected_40_track = 0;

        #(CLK_PERIOD * 10000);

        // Check form factor = 5.25" (10)
        if (profile_valid && profile_form_factor == 2'b10) begin
            $display("  PASS: Form factor correctly identified as 5.25\"");
            $display("        profile_word=0x%08x", profile_drive_profile);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: 5.25\" drive detection incorrect");
            $display("        profile_valid=%b, form_factor=%b",
                     profile_valid, profile_form_factor);
            test_fail = test_fail + 1;
        end

        profile_enable = 0;

        //---------------------------------------------------------------------
        // Test 13: Drive Profile - Apple II (300 RPM + Apple GCR)
        //---------------------------------------------------------------------
        $display("\n--- Test 13: Drive Profile (Apple II 5.25\") ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        profile_enable = 1;

        // Simulate Apple II drive
        profile_drive_ready = 1;
        profile_disk_present = 1;
        profile_rpm_valid = 1;
        profile_rpm_300 = 1;
        profile_rpm_360 = 0;
        profile_pll_locked = 1;
        profile_lock_quality = 8'd185;
        profile_encoding_valid = 1;
        profile_detected_encoding = 3'b011;  // Apple GCR 6&2
        profile_encoding_locked = 1;
        profile_track_density_valid = 0;

        #(CLK_PERIOD * 10000);

        // Check form factor = 5.25" (10) due to Apple GCR encoding
        if (profile_valid && profile_form_factor == 2'b10) begin
            $display("  PASS: Apple II drive correctly identified as 5.25\"");
            $display("        profile_word=0x%08x", profile_drive_profile);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Apple II detection incorrect");
            $display("        profile_valid=%b, form_factor=%b",
                     profile_valid, profile_form_factor);
            test_fail = test_fail + 1;
        end

        profile_enable = 0;

        //---------------------------------------------------------------------
        // Test 14: Drive Profile - Hard-sectored disk
        //---------------------------------------------------------------------
        $display("\n--- Test 14: Drive Profile (Hard-sectored) ---");

        reset = 1; #(CLK_PERIOD * 10); reset = 0;
        profile_enable = 1;

        // Simulate hard-sectored drive (NorthStar style)
        profile_drive_ready = 1;
        profile_disk_present = 1;
        profile_rpm_valid = 1;
        profile_rpm_300 = 1;
        profile_rpm_360 = 0;
        profile_pll_locked = 1;
        profile_lock_quality = 8'd175;
        profile_encoding_valid = 1;
        profile_detected_encoding = 3'b001;  // FM
        profile_encoding_locked = 1;
        profile_sector_pulse_detected = 1;
        profile_sector_count = 4'd10;  // 10 hard sectors

        #(CLK_PERIOD * 10000);

        if (profile_valid && profile_is_hard_sectored) begin
            $display("  PASS: Hard-sectored media detected");
            $display("        profile_word=0x%08x", profile_drive_profile);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Hard-sector detection incorrect");
            $display("        profile_valid=%b, is_hard_sectored=%b",
                     profile_valid, profile_is_hard_sectored);
            test_fail = test_fail + 1;
        end

        profile_enable = 0;

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("\n===========================================");
        $display("Test Summary");
        $display("===========================================");
        $display("  Passed: %0d", test_pass);
        $display("  Failed: %0d", test_fail);
        $display("===========================================\n");

        if (test_fail == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end

        #(CLK_PERIOD * 100);
        $finish;
    end

    //-------------------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------------------
    initial begin
        #(CLK_PERIOD * 500_000_000);  // 2.5 seconds at 200 MHz
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    //-------------------------------------------------------------------------
    // Optional: VCD Dump for Waveform Viewing
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_auto_detect.vcd");
        $dumpvars(0, tb_auto_detect);
    end

endmodule
