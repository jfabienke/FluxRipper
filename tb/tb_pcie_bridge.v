//==============================================================================
// PCIe Bridge Testbench
//==============================================================================
// File: tb_pcie_bridge.v
// Description: Testbench for PCIe to AXI bridge and supporting modules.
//              Tests configuration space, BAR access, MSI, and DMA.
//
// Author: Claude Code (FluxRipper Project)
// Date: 2025-12-05 00:00
//==============================================================================

`timescale 1ns / 1ps

module tb_pcie_bridge;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD_PCIE = 4;    // 250 MHz PCIe clock
    parameter CLK_PERIOD_AXI  = 10;   // 100 MHz AXI clock

    //=========================================================================
    // Signals
    //=========================================================================
    reg         pcie_clk;
    reg         pcie_rst_n;
    reg         axi_clk;
    reg         axi_rst_n;

    // Configuration interface
    reg  [15:0] cfg_command;
    reg  [15:0] cfg_status;
    reg  [7:0]  cfg_bus_number;
    reg  [4:0]  cfg_device_number;
    reg  [2:0]  cfg_function_number;
    reg         cfg_wr_en;
    reg  [9:0]  cfg_wr_addr;
    reg  [31:0] cfg_wr_data;
    reg  [3:0]  cfg_wr_be;
    reg         cfg_rd_en;
    reg  [9:0]  cfg_rd_addr;
    wire [31:0] cfg_rd_data;
    reg  [6:0]  cfg_bar_hit;

    // AXI-Stream TX
    wire [63:0] m_axis_tx_tdata;
    wire [7:0]  m_axis_tx_tkeep;
    wire        m_axis_tx_tlast;
    wire        m_axis_tx_tvalid;
    reg         m_axis_tx_tready;

    // AXI-Stream RX
    reg  [63:0] s_axis_rx_tdata;
    reg  [7:0]  s_axis_rx_tkeep;
    reg         s_axis_rx_tlast;
    reg         s_axis_rx_tvalid;
    wire        s_axis_rx_tready;
    reg  [21:0] s_axis_rx_tuser;

    // Interrupt
    wire        cfg_interrupt;
    reg         cfg_interrupt_rdy;
    wire [7:0]  cfg_interrupt_di;
    reg         cfg_interrupt_sent;
    wire        cfg_interrupt_msi_enable;

    // AXI FDC interface
    wire [31:0] m_axi_fdc_awaddr;
    wire        m_axi_fdc_awvalid;
    reg         m_axi_fdc_awready;
    wire [31:0] m_axi_fdc_wdata;
    wire [3:0]  m_axi_fdc_wstrb;
    wire        m_axi_fdc_wvalid;
    reg         m_axi_fdc_wready;
    reg  [1:0]  m_axi_fdc_bresp;
    reg         m_axi_fdc_bvalid;
    wire        m_axi_fdc_bready;
    wire [31:0] m_axi_fdc_araddr;
    wire        m_axi_fdc_arvalid;
    reg         m_axi_fdc_arready;
    reg  [31:0] m_axi_fdc_rdata;
    reg  [1:0]  m_axi_fdc_rresp;
    reg         m_axi_fdc_rvalid;
    wire        m_axi_fdc_rready;

    // AXI WD interface
    wire [31:0] m_axi_wd_awaddr;
    wire        m_axi_wd_awvalid;
    reg         m_axi_wd_awready;
    wire [31:0] m_axi_wd_wdata;
    wire [3:0]  m_axi_wd_wstrb;
    wire        m_axi_wd_wvalid;
    reg         m_axi_wd_wready;
    reg  [1:0]  m_axi_wd_bresp;
    reg         m_axi_wd_bvalid;
    wire        m_axi_wd_bready;
    wire [31:0] m_axi_wd_araddr;
    wire        m_axi_wd_arvalid;
    reg         m_axi_wd_arready;
    reg  [31:0] m_axi_wd_rdata;
    reg  [1:0]  m_axi_wd_rresp;
    reg         m_axi_wd_rvalid;
    wire        m_axi_wd_rready;

    // Interrupts
    reg         fdc_irq;
    reg         wd_irq;
    reg         fdc_dma_done;
    reg         wd_dma_done;

    // DMA buffers
    wire [15:0] fdc_buf_addr;
    wire [63:0] fdc_buf_wdata;
    wire        fdc_buf_write;
    reg  [63:0] fdc_buf_rdata;
    wire        fdc_buf_read;
    wire [15:0] wd_buf_addr;
    wire [63:0] wd_buf_wdata;
    wire        wd_buf_write;
    reg  [63:0] wd_buf_rdata;
    wire        wd_buf_read;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    pcie_axi_bridge #(
        .VENDOR_ID(16'h1234),
        .FDC_DEVICE_ID(16'hFDC0),
        .WD_DEVICE_ID(16'hHDD0)
    ) dut (
        .pcie_clk(pcie_clk),
        .pcie_rst_n(pcie_rst_n),
        .axi_clk(axi_clk),
        .axi_rst_n(axi_rst_n),

        .cfg_command(cfg_command),
        .cfg_status(cfg_status),
        .cfg_bus_number(cfg_bus_number),
        .cfg_device_number(cfg_device_number),
        .cfg_function_number(cfg_function_number),
        .cfg_wr_en(cfg_wr_en),
        .cfg_wr_addr(cfg_wr_addr),
        .cfg_wr_data(cfg_wr_data),
        .cfg_wr_be(cfg_wr_be),
        .cfg_rd_en(cfg_rd_en),
        .cfg_rd_addr(cfg_rd_addr),
        .cfg_rd_data(cfg_rd_data),
        .cfg_bar_hit(cfg_bar_hit),

        .m_axis_tx_tdata(m_axis_tx_tdata),
        .m_axis_tx_tkeep(m_axis_tx_tkeep),
        .m_axis_tx_tlast(m_axis_tx_tlast),
        .m_axis_tx_tvalid(m_axis_tx_tvalid),
        .m_axis_tx_tready(m_axis_tx_tready),

        .s_axis_rx_tdata(s_axis_rx_tdata),
        .s_axis_rx_tkeep(s_axis_rx_tkeep),
        .s_axis_rx_tlast(s_axis_rx_tlast),
        .s_axis_rx_tvalid(s_axis_rx_tvalid),
        .s_axis_rx_tready(s_axis_rx_tready),
        .s_axis_rx_tuser(s_axis_rx_tuser),

        .cfg_interrupt(cfg_interrupt),
        .cfg_interrupt_rdy(cfg_interrupt_rdy),
        .cfg_interrupt_di(cfg_interrupt_di),
        .cfg_interrupt_sent(cfg_interrupt_sent),
        .cfg_interrupt_msi_enable(cfg_interrupt_msi_enable),

        .m_axi_fdc_awaddr(m_axi_fdc_awaddr),
        .m_axi_fdc_awvalid(m_axi_fdc_awvalid),
        .m_axi_fdc_awready(m_axi_fdc_awready),
        .m_axi_fdc_wdata(m_axi_fdc_wdata),
        .m_axi_fdc_wstrb(m_axi_fdc_wstrb),
        .m_axi_fdc_wvalid(m_axi_fdc_wvalid),
        .m_axi_fdc_wready(m_axi_fdc_wready),
        .m_axi_fdc_bresp(m_axi_fdc_bresp),
        .m_axi_fdc_bvalid(m_axi_fdc_bvalid),
        .m_axi_fdc_bready(m_axi_fdc_bready),
        .m_axi_fdc_araddr(m_axi_fdc_araddr),
        .m_axi_fdc_arvalid(m_axi_fdc_arvalid),
        .m_axi_fdc_arready(m_axi_fdc_arready),
        .m_axi_fdc_rdata(m_axi_fdc_rdata),
        .m_axi_fdc_rresp(m_axi_fdc_rresp),
        .m_axi_fdc_rvalid(m_axi_fdc_rvalid),
        .m_axi_fdc_rready(m_axi_fdc_rready),

        .m_axi_wd_awaddr(m_axi_wd_awaddr),
        .m_axi_wd_awvalid(m_axi_wd_awvalid),
        .m_axi_wd_awready(m_axi_wd_awready),
        .m_axi_wd_wdata(m_axi_wd_wdata),
        .m_axi_wd_wstrb(m_axi_wd_wstrb),
        .m_axi_wd_wvalid(m_axi_wd_wvalid),
        .m_axi_wd_wready(m_axi_wd_wready),
        .m_axi_wd_bresp(m_axi_wd_bresp),
        .m_axi_wd_bvalid(m_axi_wd_bvalid),
        .m_axi_wd_bready(m_axi_wd_bready),
        .m_axi_wd_araddr(m_axi_wd_araddr),
        .m_axi_wd_arvalid(m_axi_wd_arvalid),
        .m_axi_wd_arready(m_axi_wd_arready),
        .m_axi_wd_rdata(m_axi_wd_rdata),
        .m_axi_wd_rresp(m_axi_wd_rresp),
        .m_axi_wd_rvalid(m_axi_wd_rvalid),
        .m_axi_wd_rready(m_axi_wd_rready),

        .fdc_irq(fdc_irq),
        .wd_irq(wd_irq),
        .fdc_dma_done(fdc_dma_done),
        .wd_dma_done(wd_dma_done),

        .fdc_buf_addr(fdc_buf_addr),
        .fdc_buf_wdata(fdc_buf_wdata),
        .fdc_buf_write(fdc_buf_write),
        .fdc_buf_rdata(fdc_buf_rdata),
        .fdc_buf_read(fdc_buf_read),

        .wd_buf_addr(wd_buf_addr),
        .wd_buf_wdata(wd_buf_wdata),
        .wd_buf_write(wd_buf_write),
        .wd_buf_rdata(wd_buf_rdata),
        .wd_buf_read(wd_buf_read)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        pcie_clk = 0;
        forever #(CLK_PERIOD_PCIE/2) pcie_clk = ~pcie_clk;
    end

    initial begin
        axi_clk = 0;
        forever #(CLK_PERIOD_AXI/2) axi_clk = ~axi_clk;
    end

    //=========================================================================
    // Test Counters
    //=========================================================================
    integer tests_passed = 0;
    integer tests_failed = 0;

    //=========================================================================
    // Test Tasks
    //=========================================================================

    // Configuration space read
    task cfg_read;
        input [9:0] addr;
        output [31:0] data;
        begin
            @(posedge pcie_clk);
            cfg_rd_addr <= addr;
            cfg_rd_en <= 1'b1;
            @(posedge pcie_clk);
            cfg_rd_en <= 1'b0;
            @(posedge pcie_clk);
            data = cfg_rd_data;
        end
    endtask

    // Configuration space write
    task cfg_write;
        input [9:0] addr;
        input [31:0] data;
        input [3:0] be;
        begin
            @(posedge pcie_clk);
            cfg_wr_addr <= addr;
            cfg_wr_data <= data;
            cfg_wr_be <= be;
            cfg_wr_en <= 1'b1;
            @(posedge pcie_clk);
            cfg_wr_en <= 1'b0;
            @(posedge pcie_clk);
        end
    endtask

    // Send memory read TLP
    task send_mrd_tlp;
        input [63:0] addr;
        input [9:0] length;
        input [7:0] tag;
        input [2:0] bar;
        begin
            @(posedge pcie_clk);
            // TLP Header
            s_axis_rx_tdata <= {
                16'h0100,           // Requester ID
                tag,                // Tag
                8'h0F,              // BE
                8'h00,              // Type (MRd32)
                4'h0,
                4'h0,
                2'b00,
                2'b00,
                length              // Length
            };
            s_axis_rx_tuser <= {15'h0, bar, 4'h0};
            s_axis_rx_tkeep <= 8'hFF;
            s_axis_rx_tlast <= 1'b0;
            s_axis_rx_tvalid <= 1'b1;

            @(posedge pcie_clk);
            while (!s_axis_rx_tready) @(posedge pcie_clk);

            // Address
            s_axis_rx_tdata <= {32'h0, addr[31:0]};
            s_axis_rx_tlast <= 1'b1;

            @(posedge pcie_clk);
            while (!s_axis_rx_tready) @(posedge pcie_clk);

            s_axis_rx_tvalid <= 1'b0;
            @(posedge pcie_clk);
        end
    endtask

    // Send memory write TLP
    task send_mwr_tlp;
        input [63:0] addr;
        input [31:0] data;
        input [7:0] tag;
        input [2:0] bar;
        begin
            @(posedge pcie_clk);
            // TLP Header
            s_axis_rx_tdata <= {
                16'h0100,           // Requester ID
                tag,                // Tag
                8'h0F,              // BE
                8'h40,              // Type (MWr32)
                4'h0,
                4'h0,
                2'b00,
                2'b00,
                10'd1               // Length
            };
            s_axis_rx_tuser <= {15'h0, bar, 4'h0};
            s_axis_rx_tkeep <= 8'hFF;
            s_axis_rx_tlast <= 1'b0;
            s_axis_rx_tvalid <= 1'b1;

            @(posedge pcie_clk);
            while (!s_axis_rx_tready) @(posedge pcie_clk);

            // Address + Data
            s_axis_rx_tdata <= {addr[31:0], data};
            s_axis_rx_tlast <= 1'b1;

            @(posedge pcie_clk);
            while (!s_axis_rx_tready) @(posedge pcie_clk);

            s_axis_rx_tvalid <= 1'b0;
            @(posedge pcie_clk);
        end
    endtask

    // Wait for completion TLP
    task wait_completion;
        output [31:0] data;
        begin
            while (!m_axis_tx_tvalid) @(posedge pcie_clk);
            @(posedge pcie_clk);  // Header
            while (!m_axis_tx_tvalid || !m_axis_tx_tlast) @(posedge pcie_clk);
            data = m_axis_tx_tdata[31:0];
            @(posedge pcie_clk);
        end
    endtask

    //=========================================================================
    // AXI Slave Model (simple responder)
    //=========================================================================
    reg [31:0] fdc_reg_mem [0:255];
    reg [31:0] wd_reg_mem [0:255];

    // FDC AXI slave
    always @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            m_axi_fdc_awready <= 1'b1;
            m_axi_fdc_wready  <= 1'b1;
            m_axi_fdc_bvalid  <= 1'b0;
            m_axi_fdc_bresp   <= 2'b00;
            m_axi_fdc_arready <= 1'b1;
            m_axi_fdc_rvalid  <= 1'b0;
            m_axi_fdc_rresp   <= 2'b00;
        end else begin
            // Write handling
            if (m_axi_fdc_awvalid && m_axi_fdc_wvalid) begin
                fdc_reg_mem[m_axi_fdc_awaddr[9:2]] <= m_axi_fdc_wdata;
                m_axi_fdc_bvalid <= 1'b1;
            end
            if (m_axi_fdc_bvalid && m_axi_fdc_bready) begin
                m_axi_fdc_bvalid <= 1'b0;
            end

            // Read handling
            if (m_axi_fdc_arvalid) begin
                m_axi_fdc_rdata <= fdc_reg_mem[m_axi_fdc_araddr[9:2]];
                m_axi_fdc_rvalid <= 1'b1;
            end
            if (m_axi_fdc_rvalid && m_axi_fdc_rready) begin
                m_axi_fdc_rvalid <= 1'b0;
            end
        end
    end

    // WD AXI slave
    always @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            m_axi_wd_awready <= 1'b1;
            m_axi_wd_wready  <= 1'b1;
            m_axi_wd_bvalid  <= 1'b0;
            m_axi_wd_bresp   <= 2'b00;
            m_axi_wd_arready <= 1'b1;
            m_axi_wd_rvalid  <= 1'b0;
            m_axi_wd_rresp   <= 2'b00;
        end else begin
            // Write handling
            if (m_axi_wd_awvalid && m_axi_wd_wvalid) begin
                wd_reg_mem[m_axi_wd_awaddr[9:2]] <= m_axi_wd_wdata;
                m_axi_wd_bvalid <= 1'b1;
            end
            if (m_axi_wd_bvalid && m_axi_wd_bready) begin
                m_axi_wd_bvalid <= 1'b0;
            end

            // Read handling
            if (m_axi_wd_arvalid) begin
                m_axi_wd_rdata <= wd_reg_mem[m_axi_wd_araddr[9:2]];
                m_axi_wd_rvalid <= 1'b1;
            end
            if (m_axi_wd_rvalid && m_axi_wd_rready) begin
                m_axi_wd_rvalid <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    reg [31:0] read_data;

    initial begin
        $display("========================================");
        $display("PCIe Bridge Testbench Starting");
        $display("========================================");

        // Initialize signals
        pcie_rst_n = 0;
        axi_rst_n = 0;
        cfg_command = 16'h0;
        cfg_status = 16'h0;
        cfg_bus_number = 8'h01;
        cfg_device_number = 5'h00;
        cfg_function_number = 3'b000;
        cfg_wr_en = 0;
        cfg_wr_addr = 0;
        cfg_wr_data = 0;
        cfg_wr_be = 0;
        cfg_rd_en = 0;
        cfg_rd_addr = 0;
        cfg_bar_hit = 0;
        m_axis_tx_tready = 1;
        s_axis_rx_tdata = 0;
        s_axis_rx_tkeep = 0;
        s_axis_rx_tlast = 0;
        s_axis_rx_tvalid = 0;
        s_axis_rx_tuser = 0;
        cfg_interrupt_rdy = 1;
        cfg_interrupt_sent = 0;
        fdc_irq = 0;
        wd_irq = 0;
        fdc_dma_done = 0;
        wd_dma_done = 0;
        fdc_buf_rdata = 0;
        wd_buf_rdata = 0;

        // Initialize register memories
        begin : init_mem
            integer i;
            for (i = 0; i < 256; i = i + 1) begin
                fdc_reg_mem[i] = 32'hDEAD0000 + i;
                wd_reg_mem[i] = 32'hBEEF0000 + i;
            end
        end

        // Release reset
        #100;
        pcie_rst_n = 1;
        axi_rst_n = 1;
        #100;

        //=====================================================================
        // Test 1: Configuration Space - Vendor/Device ID
        //=====================================================================
        $display("\n[Test 1] Config Space - Vendor/Device ID");
        cfg_function_number = 3'b000;  // Function 0 (FDC)
        cfg_read(10'h000, read_data);

        if (read_data == 32'hFDC01234) begin
            $display("  PASS: FDC VID/DID = 0x%08X", read_data);
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: Expected 0xFDC01234, got 0x%08X", read_data);
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Test 2: Configuration Space - Class Code
        //=====================================================================
        $display("\n[Test 2] Config Space - Class Code");
        cfg_read(10'h008, read_data);

        if (read_data[31:8] == 24'h010100) begin
            $display("  PASS: Class Code = 0x%06X (IDE Controller)", read_data[31:8]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: Expected 0x010100, got 0x%06X", read_data[31:8]);
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Test 3: BAR0 Sizing
        //=====================================================================
        $display("\n[Test 3] BAR0 Sizing");
        cfg_write(10'h010, 32'hFFFFFFFF, 4'hF);
        cfg_read(10'h010, read_data);

        if ((read_data & 32'hFFFFF000) == 32'hFFFFF000) begin
            $display("  PASS: BAR0 size mask = 0x%08X (4KB)", read_data);
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: BAR0 sizing failed, got 0x%08X", read_data);
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Test 4: BAR0 Configuration
        //=====================================================================
        $display("\n[Test 4] BAR0 Configuration");
        cfg_write(10'h010, 32'hFEDC0000, 4'hF);
        cfg_read(10'h010, read_data);

        if ((read_data & 32'hFFFFF000) == 32'hFEDC0000) begin
            $display("  PASS: BAR0 base = 0x%08X", read_data);
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: Expected 0xFEDC0000, got 0x%08X", read_data);
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Test 5: Enable Memory Space
        //=====================================================================
        $display("\n[Test 5] Enable Memory Space");
        cfg_write(10'h004, 32'h00000006, 4'h1);  // Memory + Bus Master
        cfg_read(10'h004, read_data);

        if (read_data[1] == 1'b1) begin
            $display("  PASS: Memory space enabled");
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: Memory space not enabled");
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Test 6: MSI Capability
        //=====================================================================
        $display("\n[Test 6] MSI Capability");
        cfg_read(10'h040, read_data);

        if (read_data[7:0] == 8'h05) begin
            $display("  PASS: MSI capability ID = 0x%02X", read_data[7:0]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: Expected MSI ID 0x05, got 0x%02X", read_data[7:0]);
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Test 7: PCIe Capability
        //=====================================================================
        $display("\n[Test 7] PCIe Capability");
        cfg_read(10'h060, read_data);

        if (read_data[7:0] == 8'h10) begin
            $display("  PASS: PCIe capability ID = 0x%02X", read_data[7:0]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: Expected PCIe ID 0x10, got 0x%02X", read_data[7:0]);
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Test 8: Link Capabilities
        //=====================================================================
        $display("\n[Test 8] Link Capabilities");
        cfg_read(10'h06C, read_data);

        if (read_data[3:0] == 4'b0010) begin
            $display("  PASS: Max Link Speed = Gen2 (5 GT/s)");
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: Unexpected link speed: %b", read_data[3:0]);
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Test 9: Function 1 (WD HDD) Device ID
        //=====================================================================
        $display("\n[Test 9] Function 1 - WD HDD Device ID");
        cfg_function_number = 3'b001;  // Function 1 (WD)
        cfg_read(10'h000, read_data);

        if (read_data == 32'hHDD01234) begin
            $display("  PASS: WD VID/DID = 0x%08X", read_data);
            tests_passed = tests_passed + 1;
        end else begin
            $display("  FAIL: Expected 0xHDD01234, got 0x%08X", read_data);
            tests_failed = tests_failed + 1;
        end

        //=====================================================================
        // Summary
        //=====================================================================
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Passed: %0d", tests_passed);
        $display("Failed: %0d", tests_failed);
        $display("========================================");

        if (tests_failed == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end

        #100;
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #50000;
        $display("\nTIMEOUT: Test did not complete in time");
        $finish;
    end

    //=========================================================================
    // VCD Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_pcie_bridge.vcd");
        $dumpvars(0, tb_pcie_bridge);
    end

endmodule
