//-----------------------------------------------------------------------------
// MFM Encoder Module for FluxRipper
// Ported from CAPSImg Codec/DiskEncoding.cpp InitMFM()
//
// MFM (Modified Frequency Modulation) encoding rules:
// - Data bit 1 is encoded as 01
// - Data bit 0 is encoded as 10 if previous bit was 0
// - Data bit 0 is encoded as 00 if previous bit was 1
//
// Updated: 2025-12-02 16:30
//-----------------------------------------------------------------------------

module mfm_encoder (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,          // Process byte when high
    input  wire [7:0]  data_in,         // Input byte to encode
    input  wire        prev_bit,        // Previous output bit (for clock insertion)
    output reg  [15:0] encoded_out,     // MFM encoded output (16 bits)
    output reg         last_bit,        // Last data bit for chaining
    output reg         done             // Encoding complete
);

    // State machine
    localparam IDLE = 2'b00;
    localparam ENCODE = 2'b01;
    localparam DONE = 2'b10;

    reg [1:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] data_reg;
    reg       prev_data_bit;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            encoded_out <= 16'h0000;
            last_bit <= 1'b0;
            done <= 1'b0;
            bit_cnt <= 3'd0;
            data_reg <= 8'h00;
            prev_data_bit <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (enable) begin
                        data_reg <= data_in;
                        prev_data_bit <= prev_bit;
                        bit_cnt <= 3'd0;
                        encoded_out <= 16'h0000;
                        state <= ENCODE;
                    end
                end

                ENCODE: begin
                    // Process one data bit per clock
                    // MFM: data bit goes to odd positions, clock to even
                    if (data_reg[7]) begin
                        // Data bit is 1: encode as 01
                        encoded_out[15 - (bit_cnt << 1)] <= 1'b0;     // Clock = 0
                        encoded_out[14 - (bit_cnt << 1)] <= 1'b1;     // Data = 1
                    end else begin
                        // Data bit is 0
                        if (prev_data_bit) begin
                            // Previous was 1: encode as 00
                            encoded_out[15 - (bit_cnt << 1)] <= 1'b0; // Clock = 0
                            encoded_out[14 - (bit_cnt << 1)] <= 1'b0; // Data = 0
                        end else begin
                            // Previous was 0: encode as 10
                            encoded_out[15 - (bit_cnt << 1)] <= 1'b1; // Clock = 1
                            encoded_out[14 - (bit_cnt << 1)] <= 1'b0; // Data = 0
                        end
                    end

                    prev_data_bit <= data_reg[7];
                    data_reg <= {data_reg[6:0], 1'b0};

                    if (bit_cnt == 3'd7) begin
                        last_bit <= data_reg[7];
                        state <= DONE;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                DONE: begin
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

//-----------------------------------------------------------------------------
// MFM Encoder with Lookup Table (combinational)
// For high-speed encoding without state machine
//-----------------------------------------------------------------------------
module mfm_encoder_lut (
    input  wire [7:0]  data_in,         // Input byte
    input  wire        prev_bit,        // Previous data bit
    output wire [15:0] encoded_out      // MFM encoded output
);

    // Encode each bit pair based on MFM rules
    wire [1:0] enc_bit7, enc_bit6, enc_bit5, enc_bit4;
    wire [1:0] enc_bit3, enc_bit2, enc_bit1, enc_bit0;

    // MFM encoding function: returns {clock, data}
    // Data 1 -> 01
    // Data 0 after 1 -> 00
    // Data 0 after 0 -> 10
    function [1:0] mfm_encode;
        input data_bit;
        input prev_bit;
        begin
            if (data_bit)
                mfm_encode = 2'b01;
            else if (prev_bit)
                mfm_encode = 2'b00;
            else
                mfm_encode = 2'b10;
        end
    endfunction

    assign enc_bit7 = mfm_encode(data_in[7], prev_bit);
    assign enc_bit6 = mfm_encode(data_in[6], data_in[7]);
    assign enc_bit5 = mfm_encode(data_in[5], data_in[6]);
    assign enc_bit4 = mfm_encode(data_in[4], data_in[5]);
    assign enc_bit3 = mfm_encode(data_in[3], data_in[4]);
    assign enc_bit2 = mfm_encode(data_in[2], data_in[3]);
    assign enc_bit1 = mfm_encode(data_in[1], data_in[2]);
    assign enc_bit0 = mfm_encode(data_in[0], data_in[1]);

    assign encoded_out = {enc_bit7, enc_bit6, enc_bit5, enc_bit4,
                          enc_bit3, enc_bit2, enc_bit1, enc_bit0};

endmodule

//-----------------------------------------------------------------------------
// MFM Encoder with Special Sync Pattern Support
// Generates A1 (0x4489) and C2 (0x5224) sync marks with missing clocks
//-----------------------------------------------------------------------------
module mfm_encoder_sync (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [7:0]  data_in,
    input  wire        prev_bit,
    input  wire        gen_a1_sync,     // Generate A1 sync mark (missing clock)
    input  wire        gen_c2_sync,     // Generate C2 sync mark (missing clock)
    output reg  [15:0] encoded_out,
    output reg         last_bit,
    output reg         done
);

    // A1 sync mark: 0x4489 (standard MFM would be 0x44A9, missing clock at bit 5)
    // C2 sync mark: 0x5224 (missing clock pattern)
    localparam [15:0] SYNC_A1 = 16'h4489;
    localparam [15:0] SYNC_C2 = 16'h5224;

    wire [15:0] normal_encoded;

    // Instantiate normal encoder
    mfm_encoder_lut normal_enc (
        .data_in(data_in),
        .prev_bit(prev_bit),
        .encoded_out(normal_encoded)
    );

    always @(posedge clk) begin
        if (reset) begin
            encoded_out <= 16'h0000;
            last_bit <= 1'b0;
            done <= 1'b0;
        end else if (enable) begin
            if (gen_a1_sync && data_in == 8'hA1) begin
                encoded_out <= SYNC_A1;
            end else if (gen_c2_sync && data_in == 8'hC2) begin
                encoded_out <= SYNC_C2;
            end else begin
                encoded_out <= normal_encoded;
            end
            last_bit <= data_in[0];
            done <= 1'b1;
        end else begin
            done <= 1'b0;
        end
    end

endmodule

//-----------------------------------------------------------------------------
// MFM Serial Encoder for Flux Stream Output
// Converts parallel bytes to serial MFM-encoded flux transitions
//
// Interface matches other serial encoders (fm_encoder_serial, etc.)
// for use with encoding_mux.v
//
// MFM encoding rules:
// - Data bit 1 -> 01 (flux transition on data position)
// - Data bit 0 after 1 -> 00 (no transitions)
// - Data bit 0 after 0 -> 10 (flux transition on clock position)
//
// Created: 2025-12-07
//-----------------------------------------------------------------------------
module mfm_encoder_serial (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        bit_clk,        // Bit clock (2x data rate for MFM)
    input  wire [7:0]  data_in,        // Byte to encode
    input  wire        data_valid,     // New byte available
    output reg         flux_out,       // Serial MFM encoded output
    output reg         flux_valid,     // Output bit valid
    output reg         byte_complete,  // Byte fully transmitted
    output reg         ready           // Ready for new byte
);

    //-------------------------------------------------------------------------
    // Internal State
    //-------------------------------------------------------------------------
    reg [7:0]  shift_reg;
    reg [3:0]  bit_counter;   // Counts 0-15 (8 data bits * 2 = 16 MFM bits)
    reg        clock_phase;   // 0=clock bit position, 1=data bit position
    reg        active;
    reg        prev_data_bit; // Previous data bit for MFM encoding rule

    //-------------------------------------------------------------------------
    // MFM Encoding Logic
    //-------------------------------------------------------------------------
    // For current data bit and previous data bit, determine output:
    // - Clock position: 1 if both prev and current data are 0, else 0
    // - Data position: same as data bit

    wire current_data_bit;
    wire mfm_clock_bit;
    wire mfm_data_bit;

    assign current_data_bit = shift_reg[7];
    assign mfm_clock_bit = (!prev_data_bit && !current_data_bit) ? 1'b1 : 1'b0;
    assign mfm_data_bit = current_data_bit;

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            shift_reg     <= 8'h00;
            bit_counter   <= 4'd0;
            clock_phase   <= 1'b0;
            active        <= 1'b0;
            prev_data_bit <= 1'b0;
            flux_out      <= 1'b0;
            flux_valid    <= 1'b0;
            byte_complete <= 1'b0;
            ready         <= 1'b1;
        end
        else if (enable) begin
            flux_valid    <= 1'b0;
            byte_complete <= 1'b0;

            if (data_valid && ready) begin
                // Load new byte
                shift_reg   <= data_in;
                bit_counter <= 4'd0;
                clock_phase <= 1'b0;
                active      <= 1'b1;
                ready       <= 1'b0;
            end
            else if (active && bit_clk) begin
                if (!clock_phase) begin
                    // Output clock bit position
                    // MFM: clock pulse only if both prev and current data bits are 0
                    flux_out    <= mfm_clock_bit;
                    flux_valid  <= 1'b1;
                    clock_phase <= 1'b1;
                end
                else begin
                    // Output data bit position (MSB first)
                    flux_out    <= mfm_data_bit;
                    flux_valid  <= 1'b1;
                    clock_phase <= 1'b0;

                    // Save current data bit as previous for next iteration
                    prev_data_bit <= current_data_bit;

                    // Shift to next data bit
                    shift_reg <= {shift_reg[6:0], 1'b0};
                    bit_counter <= bit_counter + 1'b1;

                    // Check if byte complete (8 data bits = 16 MFM bits)
                    if (bit_counter == 4'd7) begin
                        byte_complete <= 1'b1;
                        active        <= 1'b0;
                        ready         <= 1'b1;
                    end
                end
            end
        end
        else begin
            // Disabled - maintain ready state
            ready <= 1'b1;
            active <= 1'b0;
        end
    end

endmodule
