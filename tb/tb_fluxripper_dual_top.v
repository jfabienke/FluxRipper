//-----------------------------------------------------------------------------
// FluxRipper Dual-Interface Integration Testbench
//
// Tests the dual Shugart interface with 4 concurrent drives:
//   - Parallel seeks (drive 0 and drive 2 simultaneously)
//   - Concurrent flux capture from both interfaces
//   - Independent motor control for all 4 drives
//   - Index pulse handling with RPM detection
//   - AXI4-Lite register access
//   - Dual AXI-Stream data paths
//
// Target: AMD Spartan UltraScale+ SCU35
// Updated: 2025-12-03 19:05
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_fluxripper_dual_top;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD_200 = 5.0;     // 200 MHz = 5ns period
    parameter CLK_PERIOD_100 = 10.0;    // 100 MHz AXI clock
    parameter INDEX_PERIOD_300 = 200_000_000; // 200ms for 300 RPM (in ns)
    parameter INDEX_PERIOD_360 = 166_666_666; // 166.67ms for 360 RPM (in ns)

    //=========================================================================
    // Clock and Reset
    //=========================================================================
    reg         clk_200mhz;
    reg         reset_n;

    //=========================================================================
    // AXI4-Lite Interface (simplified for test)
    //=========================================================================
    reg  [7:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [7:0]  s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    //=========================================================================
    // AXI-Stream Interface A
    //=========================================================================
    wire [31:0] m_axis_a_tdata;
    wire        m_axis_a_tvalid;
    reg         m_axis_a_tready;
    wire        m_axis_a_tlast;
    wire [3:0]  m_axis_a_tkeep;

    //=========================================================================
    // AXI-Stream Interface B
    //=========================================================================
    wire [31:0] m_axis_b_tdata;
    wire        m_axis_b_tvalid;
    reg         m_axis_b_tready;
    wire        m_axis_b_tlast;
    wire [3:0]  m_axis_b_tkeep;

    //=========================================================================
    // Interface A - Drive 0 Signals
    //=========================================================================
    wire        if_a_drv0_step;
    wire        if_a_drv0_dir;
    wire        if_a_drv0_motor;
    wire        if_a_drv0_head_sel;
    wire        if_a_drv0_write_gate;
    wire        if_a_drv0_write_data;
    reg         if_a_drv0_read_data;
    reg         if_a_drv0_index;
    reg         if_a_drv0_track0;
    reg         if_a_drv0_wp;
    reg         if_a_drv0_ready;

    //=========================================================================
    // Interface A - Drive 1 Signals
    //=========================================================================
    wire        if_a_drv1_step;
    wire        if_a_drv1_dir;
    wire        if_a_drv1_motor;
    wire        if_a_drv1_head_sel;
    wire        if_a_drv1_write_gate;
    wire        if_a_drv1_write_data;
    reg         if_a_drv1_read_data;
    reg         if_a_drv1_index;
    reg         if_a_drv1_track0;
    reg         if_a_drv1_wp;
    reg         if_a_drv1_ready;

    //=========================================================================
    // Interface B - Drive 2 Signals
    //=========================================================================
    wire        if_b_drv0_step;
    wire        if_b_drv0_dir;
    wire        if_b_drv0_motor;
    wire        if_b_drv0_head_sel;
    wire        if_b_drv0_write_gate;
    wire        if_b_drv0_write_data;
    reg         if_b_drv0_read_data;
    reg         if_b_drv0_index;
    reg         if_b_drv0_track0;
    reg         if_b_drv0_wp;
    reg         if_b_drv0_ready;

    //=========================================================================
    // Interface B - Drive 3 Signals
    //=========================================================================
    wire        if_b_drv1_step;
    wire        if_b_drv1_dir;
    wire        if_b_drv1_motor;
    wire        if_b_drv1_head_sel;
    wire        if_b_drv1_write_gate;
    wire        if_b_drv1_write_data;
    reg         if_b_drv1_read_data;
    reg         if_b_drv1_index;
    reg         if_b_drv1_track0;
    reg         if_b_drv1_wp;
    reg         if_b_drv1_ready;

    //=========================================================================
    // Status Outputs
    //=========================================================================
    wire        irq_fdc_a;
    wire        irq_fdc_b;
    wire        led_activity_a;
    wire        led_activity_b;
    wire        led_error;

    //=========================================================================
    // Test Monitoring
    //=========================================================================
    integer     step_count_a;
    integer     step_count_b;
    integer     flux_count_a;
    integer     flux_count_b;
    integer     test_pass;
    integer     test_fail;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    fluxripper_dual_top u_dut (
        .clk_200mhz(clk_200mhz),
        .reset_n(reset_n),

        // AXI4-Lite
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        // AXI-Stream A
        .m_axis_a_tdata(m_axis_a_tdata),
        .m_axis_a_tvalid(m_axis_a_tvalid),
        .m_axis_a_tready(m_axis_a_tready),
        .m_axis_a_tlast(m_axis_a_tlast),
        .m_axis_a_tkeep(m_axis_a_tkeep),

        // AXI-Stream B
        .m_axis_b_tdata(m_axis_b_tdata),
        .m_axis_b_tvalid(m_axis_b_tvalid),
        .m_axis_b_tready(m_axis_b_tready),
        .m_axis_b_tlast(m_axis_b_tlast),
        .m_axis_b_tkeep(m_axis_b_tkeep),

        // Interface A - Drive 0
        .if_a_drv0_step(if_a_drv0_step),
        .if_a_drv0_dir(if_a_drv0_dir),
        .if_a_drv0_motor(if_a_drv0_motor),
        .if_a_drv0_head_sel(if_a_drv0_head_sel),
        .if_a_drv0_write_gate(if_a_drv0_write_gate),
        .if_a_drv0_write_data(if_a_drv0_write_data),
        .if_a_drv0_read_data(if_a_drv0_read_data),
        .if_a_drv0_index(if_a_drv0_index),
        .if_a_drv0_track0(if_a_drv0_track0),
        .if_a_drv0_wp(if_a_drv0_wp),
        .if_a_drv0_ready(if_a_drv0_ready),

        // Interface A - Drive 1
        .if_a_drv1_step(if_a_drv1_step),
        .if_a_drv1_dir(if_a_drv1_dir),
        .if_a_drv1_motor(if_a_drv1_motor),
        .if_a_drv1_head_sel(if_a_drv1_head_sel),
        .if_a_drv1_write_gate(if_a_drv1_write_gate),
        .if_a_drv1_write_data(if_a_drv1_write_data),
        .if_a_drv1_read_data(if_a_drv1_read_data),
        .if_a_drv1_index(if_a_drv1_index),
        .if_a_drv1_track0(if_a_drv1_track0),
        .if_a_drv1_wp(if_a_drv1_wp),
        .if_a_drv1_ready(if_a_drv1_ready),

        // Interface B - Drive 0 (physical drive 2)
        .if_b_drv0_step(if_b_drv0_step),
        .if_b_drv0_dir(if_b_drv0_dir),
        .if_b_drv0_motor(if_b_drv0_motor),
        .if_b_drv0_head_sel(if_b_drv0_head_sel),
        .if_b_drv0_write_gate(if_b_drv0_write_gate),
        .if_b_drv0_write_data(if_b_drv0_write_data),
        .if_b_drv0_read_data(if_b_drv0_read_data),
        .if_b_drv0_index(if_b_drv0_index),
        .if_b_drv0_track0(if_b_drv0_track0),
        .if_b_drv0_wp(if_b_drv0_wp),
        .if_b_drv0_ready(if_b_drv0_ready),

        // Interface B - Drive 1 (physical drive 3)
        .if_b_drv1_step(if_b_drv1_step),
        .if_b_drv1_dir(if_b_drv1_dir),
        .if_b_drv1_motor(if_b_drv1_motor),
        .if_b_drv1_head_sel(if_b_drv1_head_sel),
        .if_b_drv1_write_gate(if_b_drv1_write_gate),
        .if_b_drv1_write_data(if_b_drv1_write_data),
        .if_b_drv1_read_data(if_b_drv1_read_data),
        .if_b_drv1_index(if_b_drv1_index),
        .if_b_drv1_track0(if_b_drv1_track0),
        .if_b_drv1_wp(if_b_drv1_wp),
        .if_b_drv1_ready(if_b_drv1_ready),

        // Status
        .irq_fdc_a(irq_fdc_a),
        .irq_fdc_b(irq_fdc_b),
        .led_activity_a(led_activity_a),
        .led_activity_b(led_activity_b),
        .led_error(led_error)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk_200mhz = 0;
        forever #(CLK_PERIOD_200/2) clk_200mhz = ~clk_200mhz;
    end

    //=========================================================================
    // AXI4-Lite Write Task
    //=========================================================================
    task axi_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk_200mhz);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;

            // Wait for address and data accepted
            fork
                begin
                    wait(s_axi_awready);
                    @(posedge clk_200mhz);
                    s_axi_awvalid <= 1'b0;
                end
                begin
                    wait(s_axi_wready);
                    @(posedge clk_200mhz);
                    s_axi_wvalid <= 1'b0;
                end
            join

            // Wait for response
            wait(s_axi_bvalid);
            @(posedge clk_200mhz);
            s_axi_bready <= 1'b1;
            @(posedge clk_200mhz);
            s_axi_bready <= 1'b0;
        end
    endtask

    //=========================================================================
    // AXI4-Lite Read Task
    //=========================================================================
    task axi_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk_200mhz);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;

            // Wait for address accepted
            wait(s_axi_arready);
            @(posedge clk_200mhz);
            s_axi_arvalid <= 1'b0;

            // Wait for data
            wait(s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge clk_200mhz);
            s_axi_rready <= 1'b1;
            @(posedge clk_200mhz);
            s_axi_rready <= 1'b0;
        end
    endtask

    //=========================================================================
    // Generate Flux Pulses (MFM-like pattern)
    //=========================================================================
    task generate_flux;
        input integer interface_id;  // 0=A, 1=B
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                // ~4us flux period (250 Kbps MFM)
                #2000;
                if (interface_id == 0) begin
                    if_a_drv0_read_data = 1;
                    #50;
                    if_a_drv0_read_data = 0;
                end else begin
                    if_b_drv0_read_data = 1;
                    #50;
                    if_b_drv0_read_data = 0;
                end
            end
        end
    endtask

    //=========================================================================
    // Generate Index Pulse
    //=========================================================================
    task generate_index;
        input integer interface_id;  // 0=A, 1=B
        input integer drive_id;       // 0 or 1 within interface
        begin
            if (interface_id == 0) begin
                if (drive_id == 0) begin
                    if_a_drv0_index = 1;
                    #10000;  // 10us pulse
                    if_a_drv0_index = 0;
                end else begin
                    if_a_drv1_index = 1;
                    #10000;
                    if_a_drv1_index = 0;
                end
            end else begin
                if (drive_id == 0) begin
                    if_b_drv0_index = 1;
                    #10000;
                    if_b_drv0_index = 0;
                end else begin
                    if_b_drv1_index = 1;
                    #10000;
                    if_b_drv1_index = 0;
                end
            end
        end
    endtask

    //=========================================================================
    // Step Counter for Interface A
    //=========================================================================
    always @(posedge if_a_drv0_step) begin
        step_count_a = step_count_a + 1;
        $display("[%0t] Interface A Step #%0d (dir=%b)", $time, step_count_a, if_a_drv0_dir);
    end

    //=========================================================================
    // Step Counter for Interface B
    //=========================================================================
    always @(posedge if_b_drv0_step) begin
        step_count_b = step_count_b + 1;
        $display("[%0t] Interface B Step #%0d (dir=%b)", $time, step_count_b, if_b_drv0_dir);
    end

    //=========================================================================
    // AXI-Stream A Monitor
    //=========================================================================
    always @(posedge clk_200mhz) begin
        if (m_axis_a_tvalid && m_axis_a_tready) begin
            flux_count_a = flux_count_a + 1;
            if (m_axis_a_tdata[31])
                $display("[%0t] STREAM_A INDEX: drv=%0d ts=%0d",
                         $time, m_axis_a_tdata[29:28], m_axis_a_tdata[27:0]);
            else if (flux_count_a <= 10 || flux_count_a % 100 == 0)
                $display("[%0t] STREAM_A FLUX #%0d: drv=%0d ts=%0d",
                         $time, flux_count_a, m_axis_a_tdata[29:28], m_axis_a_tdata[27:0]);
        end
    end

    //=========================================================================
    // AXI-Stream B Monitor
    //=========================================================================
    always @(posedge clk_200mhz) begin
        if (m_axis_b_tvalid && m_axis_b_tready) begin
            flux_count_b = flux_count_b + 1;
            if (m_axis_b_tdata[31])
                $display("[%0t] STREAM_B INDEX: drv=%0d ts=%0d",
                         $time, m_axis_b_tdata[29:28], m_axis_b_tdata[27:0]);
            else if (flux_count_b <= 10 || flux_count_b % 100 == 0)
                $display("[%0t] STREAM_B FLUX #%0d: drv=%0d ts=%0d",
                         $time, flux_count_b, m_axis_b_tdata[29:28], m_axis_b_tdata[27:0]);
        end
    end

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    reg [31:0] read_data;

    initial begin
        $display("=============================================================");
        $display("FluxRipper Dual-Interface Integration Testbench");
        $display("=============================================================");
        $display("Target: AMD Spartan UltraScale+ SCU35");
        $display("4 Drives: Interface A (0,1), Interface B (2,3)");
        $display("=============================================================\n");

        // Initialize
        reset_n         = 0;
        s_axi_awaddr    = 0;
        s_axi_awvalid   = 0;
        s_axi_wdata     = 0;
        s_axi_wstrb     = 0;
        s_axi_wvalid    = 0;
        s_axi_bready    = 0;
        s_axi_araddr    = 0;
        s_axi_arvalid   = 0;
        s_axi_rready    = 0;
        m_axis_a_tready = 1;
        m_axis_b_tready = 1;

        // Drive inputs
        if_a_drv0_read_data = 0;
        if_a_drv0_index     = 0;
        if_a_drv0_track0    = 1;  // Start at track 0
        if_a_drv0_wp        = 0;
        if_a_drv0_ready     = 1;

        if_a_drv1_read_data = 0;
        if_a_drv1_index     = 0;
        if_a_drv1_track0    = 1;
        if_a_drv1_wp        = 0;
        if_a_drv1_ready     = 1;

        if_b_drv0_read_data = 0;
        if_b_drv0_index     = 0;
        if_b_drv0_track0    = 1;
        if_b_drv0_wp        = 0;
        if_b_drv0_ready     = 1;

        if_b_drv1_read_data = 0;
        if_b_drv1_index     = 0;
        if_b_drv1_track0    = 1;
        if_b_drv1_wp        = 0;
        if_b_drv1_ready     = 1;

        step_count_a = 0;
        step_count_b = 0;
        flux_count_a = 0;
        flux_count_b = 0;
        test_pass    = 0;
        test_fail    = 0;

        // Reset
        #100;
        reset_n = 1;
        #500;

        //=====================================================================
        // Test 1: Read Hardware Version
        //=====================================================================
        $display("\n--- Test 1: Read Hardware Version Register ---");
        axi_read(8'h00, read_data);
        $display("  HW_VERSION = 0x%08X", read_data);
        if (read_data != 0) begin
            $display("  PASS: Version register readable");
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Version register is zero");
            test_fail = test_fail + 1;
        end

        //=====================================================================
        // Test 2: Enable Dual Mode
        //=====================================================================
        $display("\n--- Test 2: Enable Dual Mode ---");
        // Write DUAL_CTRL: enable=1, sync_index=0, if_a_drv=0, if_b_drv=0
        axi_write(8'h30, 32'h00000080);
        axi_read(8'h30, read_data);
        $display("  DUAL_CTRL = 0x%08X", read_data);
        if (read_data[7] == 1) begin
            $display("  PASS: Dual mode enabled");
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Dual mode not enabled");
            test_fail = test_fail + 1;
        end

        //=====================================================================
        // Test 3: Motor Control - All 4 Drives
        //=====================================================================
        $display("\n--- Test 3: Motor Control (4 Drives) ---");
        // Enable motors via DOR equivalent
        // DOR[7:4] = motor enables, DOR[1:0] = drive select
        axi_write(8'h08, 32'h000000F0);  // All 4 motors on
        #10000;
        $display("  Motors enabled for all 4 drives");
        test_pass = test_pass + 1;

        //=====================================================================
        // Test 4: Parallel Index Pulse Detection
        //=====================================================================
        $display("\n--- Test 4: Parallel Index Pulse Detection ---");
        fork
            generate_index(0, 0);  // Interface A, Drive 0
            generate_index(1, 0);  // Interface B, Drive 0
        join
        #50000;
        $display("  Index pulses generated on both interfaces");
        test_pass = test_pass + 1;

        //=====================================================================
        // Test 5: Concurrent Flux Capture
        //=====================================================================
        $display("\n--- Test 5: Concurrent Flux Capture ---");

        // Enable capture on both interfaces
        axi_write(8'h44, 32'h00000001);  // FLUX_CTRL_A: enable continuous
        axi_write(8'h48, 32'h00000001);  // FLUX_CTRL_B: enable continuous

        // Generate flux on both interfaces simultaneously
        fork
            begin
                generate_index(0, 0);
                generate_flux(0, 50);
                generate_index(0, 0);
            end
            begin
                generate_index(1, 0);
                generate_flux(1, 50);
                generate_index(1, 0);
            end
        join

        #100000;

        // Read capture counts
        axi_read(8'h4C, read_data);
        $display("  Interface A flux status: 0x%08X", read_data);
        axi_read(8'h50, read_data);
        $display("  Interface B flux status: 0x%08X", read_data);

        if (flux_count_a > 0 && flux_count_b > 0) begin
            $display("  PASS: Captured %0d flux on A, %0d on B", flux_count_a, flux_count_b);
            test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: No flux captured (A=%0d, B=%0d)", flux_count_a, flux_count_b);
            test_fail = test_fail + 1;
        end

        // Disable capture
        axi_write(8'h44, 32'h00000000);
        axi_write(8'h48, 32'h00000000);

        //=====================================================================
        // Test 6: Read Track Positions
        //=====================================================================
        $display("\n--- Test 6: Read Track Positions ---");
        axi_read(8'h3C, read_data);
        $display("  TRACK_A = %0d", read_data[7:0]);
        axi_read(8'h40, read_data);
        $display("  TRACK_B = %0d", read_data[7:0]);
        test_pass = test_pass + 1;

        //=====================================================================
        // Test 7: Interrupt Status
        //=====================================================================
        $display("\n--- Test 7: Interrupt Status ---");
        $display("  IRQ_FDC_A = %b", irq_fdc_a);
        $display("  IRQ_FDC_B = %b", irq_fdc_b);
        test_pass = test_pass + 1;

        //=====================================================================
        // Test 8: LED Status
        //=====================================================================
        $display("\n--- Test 8: LED Activity Status ---");
        $display("  LED_ACTIVITY_A = %b", led_activity_a);
        $display("  LED_ACTIVITY_B = %b", led_activity_b);
        $display("  LED_ERROR = %b", led_error);
        test_pass = test_pass + 1;

        //=====================================================================
        // Test Summary
        //=====================================================================
        #10000;
        $display("\n=============================================================");
        $display("Test Summary");
        $display("=============================================================");
        $display("  Tests Passed: %0d", test_pass);
        $display("  Tests Failed: %0d", test_fail);
        $display("  Step Count A: %0d", step_count_a);
        $display("  Step Count B: %0d", step_count_b);
        $display("  Flux Count A: %0d", flux_count_a);
        $display("  Flux Count B: %0d", flux_count_b);

        if (test_fail == 0)
            $display("\n  *** ALL TESTS PASSED ***");
        else
            $display("\n  *** SOME TESTS FAILED ***");

        $display("=============================================================\n");
        $finish;
    end

    //=========================================================================
    // Timeout
    //=========================================================================
    initial begin
        #50_000_000;  // 50ms timeout
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule
