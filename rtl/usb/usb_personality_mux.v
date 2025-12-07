//-----------------------------------------------------------------------------
// usb_personality_mux.v
// USB Personality Multiplexer and Router
//
// Created: 2025-12-05 18:15
//
// Routes USB traffic to the appropriate protocol handler based on the
// selected USB personality. Supports hot-switching between personalities.
//
// Personalities:
//   0: Greaseweazle (GW)    - Compatible with gw tool, FluxEngine
//   1: HxC                  - Compatible with HxC Floppy Emulator
//   2: KryoFlux (KF)        - Compatible with DTC/KryoFlux software
//   3: Native FluxRipper    - Native 32-bit timestamped flux format
//   4: MSC + Raw            - USB Mass Storage + Vendor Raw Mode
//
// The multiplexer handles:
//   - Endpoint routing based on personality
//   - Safe personality switching (drain buffers, reset state)
//   - Protocol-specific endpoint configuration
//   - Status aggregation from all personalities
//-----------------------------------------------------------------------------

module usb_personality_mux #(
    parameter NUM_PERSONALITIES = 5,
    parameter DEFAULT_PERSONALITY = 4    // MSC + Raw as default
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // Personality Selection
    //=========================================================================

    input  wire [2:0]  personality_sel,    // Selected personality (0-4)
    input  wire        personality_switch, // Request personality switch
    output reg         switch_complete,    // Switch completed
    output reg  [2:0]  active_personality, // Currently active personality

    //=========================================================================
    // FT601 Interface (from ft601_interface.v)
    //=========================================================================

    // Receive path (from host)
    input  wire [31:0] usb_rx_data,
    input  wire        usb_rx_valid,
    output wire        usb_rx_ready,

    // Transmit path (to host)
    output reg  [31:0] usb_tx_data,
    output reg         usb_tx_valid,
    input  wire        usb_tx_ready,

    //=========================================================================
    // Greaseweazle Protocol Interface (Personality 0)
    //=========================================================================

    output wire [31:0] gw_rx_data,
    output wire        gw_rx_valid,
    input  wire        gw_rx_ready,

    input  wire [31:0] gw_tx_data,
    input  wire        gw_tx_valid,
    output wire        gw_tx_ready,

    input  wire [7:0]  gw_state,

    //=========================================================================
    // HxC Protocol Interface (Personality 1)
    //=========================================================================

    output wire [31:0] hfe_rx_data,
    output wire        hfe_rx_valid,
    input  wire        hfe_rx_ready,

    input  wire [31:0] hfe_tx_data,
    input  wire        hfe_tx_valid,
    output wire        hfe_tx_ready,

    input  wire [7:0]  hfe_state,

    //=========================================================================
    // KryoFlux Protocol Interface (Personality 2)
    //=========================================================================

    output wire [31:0] kf_rx_data,
    output wire        kf_rx_valid,
    input  wire        kf_rx_ready,

    input  wire [31:0] kf_tx_data,
    input  wire        kf_tx_valid,
    output wire        kf_tx_ready,

    input  wire [7:0]  kf_state,

    //=========================================================================
    // Native FluxRipper Protocol Interface (Personality 3)
    //=========================================================================

    output wire [31:0] native_rx_data,
    output wire        native_rx_valid,
    input  wire        native_rx_ready,

    input  wire [31:0] native_tx_data,
    input  wire        native_tx_valid,
    output wire        native_tx_ready,

    input  wire [7:0]  native_state,

    //=========================================================================
    // MSC + Raw Protocol Interface (Personality 4)
    //=========================================================================

    output wire [31:0] msc_rx_data,
    output wire        msc_rx_valid,
    input  wire        msc_rx_ready,

    input  wire [31:0] msc_tx_data,
    input  wire        msc_tx_valid,
    output wire        msc_tx_ready,

    input  wire [7:0]  msc_state,

    //=========================================================================
    // Status
    //=========================================================================

    output reg  [7:0]  mux_state,
    output reg         personality_valid,
    output wire [7:0]  active_protocol_state
);

    //=========================================================================
    // Personality Constants
    //=========================================================================

    localparam [2:0]
        PERS_GREASEWEAZLE = 3'd0,
        PERS_HXC          = 3'd1,
        PERS_KRYOFLUX     = 3'd2,
        PERS_NATIVE       = 3'd3,
        PERS_MSC_RAW      = 3'd4;

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam [2:0]
        ST_IDLE           = 3'd0,
        ST_DRAIN_TX       = 3'd1,
        ST_DRAIN_RX       = 3'd2,
        ST_RESET_PROTOCOL = 3'd3,
        ST_SWITCH         = 3'd4,
        ST_ACTIVE         = 3'd5;

    reg [2:0] state;
    reg [7:0] drain_timeout;
    reg [2:0] pending_personality;

    //=========================================================================
    // RX Ready Mux
    //=========================================================================

    reg rx_ready_mux;

    always @(*) begin
        case (active_personality)
            PERS_GREASEWEAZLE: rx_ready_mux = gw_rx_ready;
            PERS_HXC:          rx_ready_mux = hfe_rx_ready;
            PERS_KRYOFLUX:     rx_ready_mux = kf_rx_ready;
            PERS_NATIVE:       rx_ready_mux = native_rx_ready;
            PERS_MSC_RAW:      rx_ready_mux = msc_rx_ready;
            default:           rx_ready_mux = 1'b0;
        endcase
    end

    assign usb_rx_ready = rx_ready_mux && (state == ST_ACTIVE);

    //=========================================================================
    // RX Data Distribution
    //=========================================================================

    wire rx_active = (state == ST_ACTIVE);

    assign gw_rx_data     = usb_rx_data;
    assign gw_rx_valid    = usb_rx_valid && rx_active && (active_personality == PERS_GREASEWEAZLE);

    assign hfe_rx_data    = usb_rx_data;
    assign hfe_rx_valid   = usb_rx_valid && rx_active && (active_personality == PERS_HXC);

    assign kf_rx_data     = usb_rx_data;
    assign kf_rx_valid    = usb_rx_valid && rx_active && (active_personality == PERS_KRYOFLUX);

    assign native_rx_data = usb_rx_data;
    assign native_rx_valid= usb_rx_valid && rx_active && (active_personality == PERS_NATIVE);

    assign msc_rx_data    = usb_rx_data;
    assign msc_rx_valid   = usb_rx_valid && rx_active && (active_personality == PERS_MSC_RAW);

    //=========================================================================
    // TX Ready Distribution
    //=========================================================================

    assign gw_tx_ready     = usb_tx_ready && (state == ST_ACTIVE) && (active_personality == PERS_GREASEWEAZLE);
    assign hfe_tx_ready    = usb_tx_ready && (state == ST_ACTIVE) && (active_personality == PERS_HXC);
    assign kf_tx_ready     = usb_tx_ready && (state == ST_ACTIVE) && (active_personality == PERS_KRYOFLUX);
    assign native_tx_ready = usb_tx_ready && (state == ST_ACTIVE) && (active_personality == PERS_NATIVE);
    assign msc_tx_ready    = usb_tx_ready && (state == ST_ACTIVE) && (active_personality == PERS_MSC_RAW);

    //=========================================================================
    // TX Data Mux
    //=========================================================================

    always @(*) begin
        case (active_personality)
            PERS_GREASEWEAZLE: begin
                usb_tx_data  = gw_tx_data;
                usb_tx_valid = gw_tx_valid && (state == ST_ACTIVE);
            end
            PERS_HXC: begin
                usb_tx_data  = hfe_tx_data;
                usb_tx_valid = hfe_tx_valid && (state == ST_ACTIVE);
            end
            PERS_KRYOFLUX: begin
                usb_tx_data  = kf_tx_data;
                usb_tx_valid = kf_tx_valid && (state == ST_ACTIVE);
            end
            PERS_NATIVE: begin
                usb_tx_data  = native_tx_data;
                usb_tx_valid = native_tx_valid && (state == ST_ACTIVE);
            end
            PERS_MSC_RAW: begin
                usb_tx_data  = msc_tx_data;
                usb_tx_valid = msc_tx_valid && (state == ST_ACTIVE);
            end
            default: begin
                usb_tx_data  = 32'h0;
                usb_tx_valid = 1'b0;
            end
        endcase
    end

    //=========================================================================
    // Active Protocol State
    //=========================================================================

    assign active_protocol_state =
        (active_personality == PERS_GREASEWEAZLE) ? gw_state :
        (active_personality == PERS_HXC)          ? hfe_state :
        (active_personality == PERS_KRYOFLUX)     ? kf_state :
        (active_personality == PERS_NATIVE)       ? native_state :
        (active_personality == PERS_MSC_RAW)      ? msc_state :
        8'h00;

    //=========================================================================
    // Personality Switching State Machine
    //=========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            active_personality <= DEFAULT_PERSONALITY[2:0];
            pending_personality <= DEFAULT_PERSONALITY[2:0];
            switch_complete <= 1'b0;
            personality_valid <= 1'b0;
            drain_timeout <= 8'h0;
            mux_state <= 8'h0;
        end else begin
            mux_state <= {5'h0, state};
            switch_complete <= 1'b0;

            case (state)
                //-------------------------------------------------------------
                // IDLE - Initialize to default personality
                //-------------------------------------------------------------
                ST_IDLE: begin
                    active_personality <= DEFAULT_PERSONALITY[2:0];
                    personality_valid <= 1'b1;
                    state <= ST_ACTIVE;
                end

                //-------------------------------------------------------------
                // ACTIVE - Normal operation
                //-------------------------------------------------------------
                ST_ACTIVE: begin
                    if (personality_switch && (personality_sel != active_personality)) begin
                        if (personality_sel < NUM_PERSONALITIES) begin
                            pending_personality <= personality_sel;
                            drain_timeout <= 8'hFF;
                            state <= ST_DRAIN_TX;
                        end
                    end
                end

                //-------------------------------------------------------------
                // DRAIN_TX - Wait for TX buffer to empty
                //-------------------------------------------------------------
                ST_DRAIN_TX: begin
                    if (!usb_tx_valid || drain_timeout == 0) begin
                        drain_timeout <= 8'hFF;
                        state <= ST_DRAIN_RX;
                    end else begin
                        drain_timeout <= drain_timeout - 1'b1;
                    end
                end

                //-------------------------------------------------------------
                // DRAIN_RX - Wait for RX processing to complete
                //-------------------------------------------------------------
                ST_DRAIN_RX: begin
                    if (!usb_rx_valid || drain_timeout == 0) begin
                        state <= ST_RESET_PROTOCOL;
                    end else begin
                        drain_timeout <= drain_timeout - 1'b1;
                    end
                end

                //-------------------------------------------------------------
                // RESET_PROTOCOL - Allow protocols to reset state
                //-------------------------------------------------------------
                ST_RESET_PROTOCOL: begin
                    personality_valid <= 1'b0;
                    state <= ST_SWITCH;
                end

                //-------------------------------------------------------------
                // SWITCH - Perform the personality switch
                //-------------------------------------------------------------
                ST_SWITCH: begin
                    active_personality <= pending_personality;
                    personality_valid <= 1'b1;
                    switch_complete <= 1'b1;
                    state <= ST_ACTIVE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
