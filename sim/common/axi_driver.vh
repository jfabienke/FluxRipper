//-----------------------------------------------------------------------------
// FluxRipper AXI Driver - Reusable Test Infrastructure
// Created: 2025-12-07
//
// Provides AXI4-Lite and AXI-Stream transaction tasks for testbenches.
//
// Usage:
//   `include "axi_driver.vh"
//   // Then call tasks like: axi_write(addr, data), axi_read(addr, data), etc.
//
// Prerequisites:
//   - Define AXI signals in your testbench before including this file
//   - AXI4-Lite signals: awaddr, awvalid, awready, wdata, wstrb, wvalid, wready,
//                        bresp, bvalid, bready, araddr, arvalid, arready,
//                        rdata, rresp, rvalid, rready
//   - AXI-Stream signals: tdata, tvalid, tready, tlast, tkeep
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// AXI4-Lite Response Codes
//-----------------------------------------------------------------------------
localparam [1:0]
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11;

//-----------------------------------------------------------------------------
// AXI4-Lite Write Transaction
// Performs a complete write: address phase + data phase + response phase
//-----------------------------------------------------------------------------
task axi_lite_write;
    input  [31:0] addr;
    input  [31:0] data;
    input  [3:0]  strb;
    output [1:0]  resp;
    begin
        // Address and data phases can happen simultaneously
        fork
            // Write Address Channel
            begin
                s_axi_awaddr = addr;
                s_axi_awvalid = 1'b1;
                @(posedge aclk);
                while (!s_axi_awready) @(posedge aclk);
                s_axi_awvalid = 1'b0;
            end
            // Write Data Channel
            begin
                s_axi_wdata = data;
                s_axi_wstrb = strb;
                s_axi_wvalid = 1'b1;
                @(posedge aclk);
                while (!s_axi_wready) @(posedge aclk);
                s_axi_wvalid = 1'b0;
            end
        join

        // Write Response Channel
        s_axi_bready = 1'b1;
        @(posedge aclk);
        while (!s_axi_bvalid) @(posedge aclk);
        resp = s_axi_bresp;
        s_axi_bready = 1'b0;
        @(posedge aclk);
    end
endtask

// Simplified write with full byte strobe
task axi_write;
    input  [31:0] addr;
    input  [31:0] data;
    reg [1:0] resp;
    begin
        axi_lite_write(addr, data, 4'b1111, resp);
        if (resp != AXI_RESP_OKAY) begin
            $display("  [WARN] AXI write to 0x%08X returned response %0d", addr, resp);
        end
    end
endtask

//-----------------------------------------------------------------------------
// AXI4-Lite Read Transaction
// Performs a complete read: address phase + data phase
//-----------------------------------------------------------------------------
task axi_lite_read;
    input  [31:0] addr;
    output [31:0] data;
    output [1:0]  resp;
    begin
        // Read Address Channel
        s_axi_araddr = addr;
        s_axi_arvalid = 1'b1;
        @(posedge aclk);
        while (!s_axi_arready) @(posedge aclk);
        s_axi_arvalid = 1'b0;

        // Read Data Channel
        s_axi_rready = 1'b1;
        @(posedge aclk);
        while (!s_axi_rvalid) @(posedge aclk);
        data = s_axi_rdata;
        resp = s_axi_rresp;
        s_axi_rready = 1'b0;
        @(posedge aclk);
    end
endtask

// Simplified read
task axi_read;
    input  [31:0] addr;
    output [31:0] data;
    reg [1:0] resp;
    begin
        axi_lite_read(addr, data, resp);
        if (resp != AXI_RESP_OKAY) begin
            $display("  [WARN] AXI read from 0x%08X returned response %0d", addr, resp);
        end
    end
endtask

//-----------------------------------------------------------------------------
// AXI4-Lite Write and Verify
// Writes a value and reads it back to verify
//-----------------------------------------------------------------------------
task axi_write_verify;
    input  [31:0] addr;
    input  [31:0] data;
    output        match;
    reg [31:0] readback;
    begin
        axi_write(addr, data);
        axi_read(addr, readback);
        match = (readback == data);
        if (!match) begin
            $display("  [FAIL] Write verify: wrote 0x%08X, read 0x%08X", data, readback);
        end
    end
endtask

//-----------------------------------------------------------------------------
// AXI4-Lite Register Polling
// Polls a register until a condition is met or timeout
//-----------------------------------------------------------------------------
task axi_poll_until;
    input  [31:0] addr;
    input  [31:0] mask;
    input  [31:0] expected;
    input  [31:0] max_attempts;
    output        success;
    reg [31:0] data;
    integer attempts;
    begin
        success = 0;
        attempts = 0;
        while (attempts < max_attempts) begin
            axi_read(addr, data);
            if ((data & mask) == expected) begin
                success = 1;
                attempts = max_attempts;  // Exit loop
            end else begin
                attempts = attempts + 1;
                repeat(10) @(posedge aclk);  // Small delay between polls
            end
        end
        if (!success) begin
            $display("  [WARN] Poll timeout: addr=0x%08X, mask=0x%08X, expected=0x%08X, got=0x%08X",
                     addr, mask, expected, data & mask);
        end
    end
endtask

//-----------------------------------------------------------------------------
// AXI-Stream Source (Master) - Send single beat
//-----------------------------------------------------------------------------
task axis_send;
    input [31:0] data;
    input        last;
    begin
        m_axis_tdata = data;
        m_axis_tlast = last;
        m_axis_tkeep = 4'b1111;
        m_axis_tvalid = 1'b1;
        @(posedge aclk);
        while (!m_axis_tready) @(posedge aclk);
        m_axis_tvalid = 1'b0;
        m_axis_tlast = 1'b0;
    end
endtask

//-----------------------------------------------------------------------------
// AXI-Stream Source - Send burst of data
//-----------------------------------------------------------------------------
task axis_send_burst;
    input [31:0] data_array [0:255];  // Up to 256 words
    input integer count;
    integer i;
    begin
        for (i = 0; i < count; i = i + 1) begin
            axis_send(data_array[i], (i == count - 1));
        end
    end
endtask

//-----------------------------------------------------------------------------
// AXI-Stream Sink (Slave) - Receive single beat
//-----------------------------------------------------------------------------
task axis_receive;
    output [31:0] data;
    output        last;
    begin
        s_axis_tready = 1'b1;
        @(posedge aclk);
        while (!s_axis_tvalid) @(posedge aclk);
        data = s_axis_tdata;
        last = s_axis_tlast;
        s_axis_tready = 1'b0;
        @(posedge aclk);
    end
endtask

//-----------------------------------------------------------------------------
// AXI-Stream Sink - Receive burst of data
//-----------------------------------------------------------------------------
task axis_receive_burst;
    output [31:0] data_array [0:255];
    output integer count;
    reg [31:0] data;
    reg last;
    begin
        count = 0;
        last = 0;
        while (!last && count < 256) begin
            axis_receive(data, last);
            data_array[count] = data;
            count = count + 1;
        end
    end
endtask

//-----------------------------------------------------------------------------
// AXI-Stream Check - Compare received data to expected
//-----------------------------------------------------------------------------
task axis_check;
    input [31:0] expected;
    input [31:0] actual;
    input integer index;
    begin
        if (expected !== actual) begin
            $display("  [FAIL] AXI-Stream data[%0d]: expected 0x%08X, got 0x%08X",
                     index, expected, actual);
        end
    end
endtask

//-----------------------------------------------------------------------------
// AXI4-Lite Initialization
// Call at start of test to initialize all signals
//-----------------------------------------------------------------------------
task axi_lite_init;
    begin
        s_axi_awaddr = 32'h0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata = 32'h0;
        s_axi_wstrb = 4'h0;
        s_axi_wvalid = 1'b0;
        s_axi_bready = 1'b0;
        s_axi_araddr = 32'h0;
        s_axi_arvalid = 1'b0;
        s_axi_rready = 1'b0;
    end
endtask

//-----------------------------------------------------------------------------
// AXI-Stream Initialization
//-----------------------------------------------------------------------------
task axis_init;
    begin
        m_axis_tdata = 32'h0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast = 1'b0;
        m_axis_tkeep = 4'h0;
        s_axis_tready = 1'b0;
    end
endtask
