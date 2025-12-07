//-----------------------------------------------------------------------------
// usb_composite_mux.v
// USB Composite Device Interface Multiplexer
//
// Created: 2025-12-05 14:45
//
// Routes USB traffic between Mass Storage Class (MSC) and Raw Mode interfaces
// based on the active USB interface context or packet signatures.
//
// Interface 0: Mass Storage Class (SCSI over BBB)
// Interface 1: Vendor Raw Mode (Flux capture + diagnostics)
//
// Endpoint allocation:
//   EP0: Control (handled by FT601 directly)
//   EP1 OUT: Shared - CBW (MSC) or Raw commands
//   EP2 IN:  MSC - CSW + sector data
//   EP3 IN:  Raw - Flux data + diagnostics
//-----------------------------------------------------------------------------

module usb_composite_mux #(
    parameter CBW_SIGNATURE = 32'h43425355,  // "USBC" - CBW signature
    parameter RAW_SIGNATURE = 32'h46525751   // "FRWQ" - FluxRipper Raw Query
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // FT601 Interface (from ft601_interface.v)
    //=========================================================================

    // EP1 OUT - Commands from host (shared between MSC and Raw)
    input  wire [31:0] ep1_rx_data,
    input  wire        ep1_rx_valid,
    output wire        ep1_rx_ready,

    // EP2 IN - MSC data to host (CSW + sectors)
    output wire [31:0] ep2_tx_data,
    output wire        ep2_tx_valid,
    input  wire        ep2_tx_ready,

    // EP3 IN - Raw data to host (flux + diagnostics)
    output wire [31:0] ep3_tx_data,
    output wire        ep3_tx_valid,
    input  wire        ep3_tx_ready,

    //=========================================================================
    // Interface Selection
    //=========================================================================

    // Software-controlled interface selection (from configuration register)
    input  wire [1:0]  sw_interface_sel,     // 0=auto, 1=force MSC, 2=force Raw
    input  wire        sw_interface_valid,   // Selection is valid

    // Active interface output
    output reg  [1:0]  active_interface,     // 0=MSC, 1=Raw, 2=idle
    output reg         interface_locked,     // Interface determined for current transfer

    //=========================================================================
    // MSC Protocol Interface
    //=========================================================================

    // Commands to MSC
    output wire [31:0] msc_cmd_data,
    output wire        msc_cmd_valid,
    input  wire        msc_cmd_ready,

    // Responses from MSC (CSW + data)
    input  wire [31:0] msc_resp_data,
    input  wire        msc_resp_valid,
    output wire        msc_resp_ready,

    // MSC status
    input  wire        msc_transfer_active,  // MSC is processing a transfer
    input  wire        msc_transfer_done,    // MSC transfer complete

    //=========================================================================
    // Raw Mode Interface
    //=========================================================================

    // Commands to Raw
    output wire [31:0] raw_cmd_data,
    output wire        raw_cmd_valid,
    input  wire        raw_cmd_ready,

    // Responses from Raw (flux + diagnostics)
    input  wire [31:0] raw_resp_data,
    input  wire        raw_resp_valid,
    output wire        raw_resp_ready,

    // Raw status
    input  wire        raw_transfer_active,  // Raw mode is active
    input  wire        raw_transfer_done,    // Raw transfer complete

    //=========================================================================
    // Status
    //=========================================================================

    output reg  [7:0]  mux_state,
    output reg  [31:0] msc_packet_count,
    output reg  [31:0] raw_packet_count,
    output reg  [7:0]  last_signature_type   // 0=unknown, 1=CBW, 2=Raw
);

    //=========================================================================
    // Local Parameters
    //=========================================================================

    localparam IF_IDLE = 2'd0;
    localparam IF_MSC  = 2'd1;
    localparam IF_RAW  = 2'd2;

    // State machine states
    localparam ST_IDLE           = 4'd0;
    localparam ST_READ_HEADER    = 4'd1;
    localparam ST_DECODE         = 4'd2;
    localparam ST_ROUTE_MSC      = 4'd3;
    localparam ST_ROUTE_RAW      = 4'd4;
    localparam ST_WAIT_MSC_DONE  = 4'd5;
    localparam ST_WAIT_RAW_DONE  = 4'd6;
    localparam ST_FORWARD_MSC    = 4'd7;
    localparam ST_FORWARD_RAW    = 4'd8;

    //=========================================================================
    // Registers
    //=========================================================================

    reg [3:0]  state;
    reg [3:0]  state_next;

    // Header capture
    reg [31:0] header_word;
    reg        header_valid;

    // Interface determination
    reg [1:0]  detected_interface;

    // Packet forwarding
    reg        forward_to_msc;
    reg        forward_to_raw;

    //=========================================================================
    // Signature Detection
    //=========================================================================

    // Check first word for signature
    wire is_cbw_signature = (ep1_rx_data == CBW_SIGNATURE);
    wire is_raw_signature = (ep1_rx_data == RAW_SIGNATURE);

    // Determine interface from signature or software selection
    always @(*) begin
        if (sw_interface_valid && sw_interface_sel != 2'd0) begin
            // Software override
            detected_interface = sw_interface_sel;
        end else if (is_cbw_signature) begin
            detected_interface = IF_MSC;
        end else if (is_raw_signature) begin
            detected_interface = IF_RAW;
        end else begin
            // Unknown signature - default to MSC for compatibility
            detected_interface = IF_MSC;
        end
    end

    //=========================================================================
    // State Machine
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= state_next;
        end
    end

    always @(*) begin
        state_next = state;

        case (state)
            ST_IDLE: begin
                // Wait for first word of packet
                if (ep1_rx_valid) begin
                    state_next = ST_DECODE;
                end
            end

            ST_DECODE: begin
                // Route based on detected interface
                if (detected_interface == IF_MSC) begin
                    state_next = ST_ROUTE_MSC;
                end else begin
                    state_next = ST_ROUTE_RAW;
                end
            end

            ST_ROUTE_MSC: begin
                // Forward to MSC, wait for acceptance
                if (msc_cmd_ready) begin
                    state_next = ST_FORWARD_MSC;
                end
            end

            ST_FORWARD_MSC: begin
                // Continue forwarding until transfer done or no more data
                if (msc_transfer_done || !ep1_rx_valid) begin
                    state_next = ST_WAIT_MSC_DONE;
                end
            end

            ST_WAIT_MSC_DONE: begin
                // Wait for MSC to complete processing
                if (!msc_transfer_active) begin
                    state_next = ST_IDLE;
                end
            end

            ST_ROUTE_RAW: begin
                // Forward to Raw, wait for acceptance
                if (raw_cmd_ready) begin
                    state_next = ST_FORWARD_RAW;
                end
            end

            ST_FORWARD_RAW: begin
                // Continue forwarding until transfer done or no more data
                if (raw_transfer_done || !ep1_rx_valid) begin
                    state_next = ST_WAIT_RAW_DONE;
                end
            end

            ST_WAIT_RAW_DONE: begin
                // Wait for Raw to complete processing
                if (!raw_transfer_active) begin
                    state_next = ST_IDLE;
                end
            end

            default: state_next = ST_IDLE;
        endcase
    end

    //=========================================================================
    // Control Signals
    //=========================================================================

    // Active interface tracking
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_interface <= IF_IDLE;
            interface_locked <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    active_interface <= IF_IDLE;
                    interface_locked <= 1'b0;
                end

                ST_DECODE: begin
                    active_interface <= detected_interface;
                    interface_locked <= 1'b1;
                end

                ST_ROUTE_MSC, ST_FORWARD_MSC, ST_WAIT_MSC_DONE: begin
                    active_interface <= IF_MSC;
                    interface_locked <= 1'b1;
                end

                ST_ROUTE_RAW, ST_FORWARD_RAW, ST_WAIT_RAW_DONE: begin
                    active_interface <= IF_RAW;
                    interface_locked <= 1'b1;
                end
            endcase
        end
    end

    //=========================================================================
    // Data Path Routing
    //=========================================================================

    // MSC command path - active during MSC states
    wire msc_active = (state == ST_ROUTE_MSC) || (state == ST_FORWARD_MSC);
    assign msc_cmd_data  = ep1_rx_data;
    assign msc_cmd_valid = ep1_rx_valid && msc_active;

    // Raw command path - active during Raw states
    wire raw_active = (state == ST_ROUTE_RAW) || (state == ST_FORWARD_RAW);
    assign raw_cmd_data  = ep1_rx_data;
    assign raw_cmd_valid = ep1_rx_valid && raw_active;

    // EP1 ready - accept data when target interface is ready
    assign ep1_rx_ready = (msc_active && msc_cmd_ready) ||
                          (raw_active && raw_cmd_ready) ||
                          (state == ST_IDLE) ||
                          (state == ST_DECODE);

    // EP2 TX - MSC response path
    assign ep2_tx_data  = msc_resp_data;
    assign ep2_tx_valid = msc_resp_valid;
    assign msc_resp_ready = ep2_tx_ready;

    // EP3 TX - Raw response path
    assign ep3_tx_data  = raw_resp_data;
    assign ep3_tx_valid = raw_resp_valid;
    assign raw_resp_ready = ep3_tx_ready;

    //=========================================================================
    // Statistics Counters
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msc_packet_count <= 32'h0;
            raw_packet_count <= 32'h0;
            last_signature_type <= 8'h0;
            mux_state <= 8'h0;
        end else begin
            mux_state <= {4'h0, state};

            // Count packets when entering route state
            if (state == ST_IDLE && state_next == ST_DECODE) begin
                if (is_cbw_signature) begin
                    msc_packet_count <= msc_packet_count + 1'b1;
                    last_signature_type <= 8'd1;
                end else if (is_raw_signature) begin
                    raw_packet_count <= raw_packet_count + 1'b1;
                    last_signature_type <= 8'd2;
                end else begin
                    last_signature_type <= 8'd0;
                end
            end
        end
    end

endmodule
