//-----------------------------------------------------------------------------
// Command FSM for FluxRipper FDC
// Intel 82077AA compatible command state machine
//
// Based on CAPSImg CapsFDCEmulator.cpp FdcCom() and fdcinit[] table
//
// Updated: 2025-12-03 22:15
//-----------------------------------------------------------------------------

module command_fsm (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Command input
    input  wire [7:0]  command_byte,    // Command/parameter byte
    input  wire        command_valid,   // Byte is valid

    // FIFO interface
    input  wire [7:0]  fifo_data,       // Data from FIFO
    input  wire        fifo_empty,
    output reg         fifo_read,
    output reg  [7:0]  fifo_write_data,
    output reg         fifo_write,

    // Step controller interface
    output reg         seek_start,
    output reg  [7:0]  seek_target,
    output reg         restore,
    input  wire        seek_complete,
    input  wire [7:0]  current_track,
    input  wire        at_track0,

    // Data separator interface
    output reg         read_enable,
    input  wire [7:0]  read_data,
    input  wire        read_ready,
    input  wire        sync_acquired,
    input  wire        a1_detected,

    // Write path interface
    output reg         write_enable,
    output reg  [7:0]  write_data,
    output reg         write_valid,

    // CRC interface
    output reg         crc_reset,
    input  wire        crc_valid,
    input  wire [15:0] crc_value,

    // Drive control
    output reg  [1:0]  head_select,
    input  wire        index_pulse,
    input  wire        write_protect,

    // Status interface
    output reg  [1:0]  int_code,
    output reg         seek_end,
    output reg         equipment_check,
    output reg         end_of_cylinder,
    output reg         data_error,
    output reg         overrun,
    output reg         no_data,
    output reg         missing_am,

    // Control outputs
    output reg         busy,
    output reg         dio,             // Data direction: 1=FDC->CPU, 0=CPU->FDC
    output reg         rqm,             // Request for master
    output reg         ndma,            // Non-DMA mode
    output reg         interrupt,

    // ID field outputs for track density detection
    output wire [7:0]  id_cylinder_out, // Cylinder from last ID field
    output reg         id_field_valid   // Pulse when ID field captured
);

    //-------------------------------------------------------------------------
    // Command definitions (from 82077AA datasheet and CAPSImg)
    //-------------------------------------------------------------------------
    // Type 1 commands (Seek/Restore)
    localparam CMD_RECALIBRATE    = 5'b00111;  // Seek to track 0
    localparam CMD_SEEK           = 5'b01111;  // Seek to specified track
    localparam CMD_RELATIVE_SEEK  = 5'b10000;  // Relative seek (82077AA)

    // Type 2 commands (Read/Write Sector)
    localparam CMD_READ_DATA      = 5'b00110;  // Read sector
    localparam CMD_READ_DEL_DATA  = 5'b01100;  // Read deleted data
    localparam CMD_WRITE_DATA     = 5'b00101;  // Write sector
    localparam CMD_WRITE_DEL_DATA = 5'b01001;  // Write deleted data

    // Type 3 commands (Read/Write Track)
    localparam CMD_READ_TRACK     = 5'b00010;  // Read track
    localparam CMD_READ_ID        = 5'b01010;  // Read ID
    localparam CMD_FORMAT_TRACK   = 5'b01101;  // Format track

    // Type 4 commands (Control)
    localparam CMD_SENSE_INT      = 5'b01000;  // Sense interrupt status
    localparam CMD_SPECIFY        = 5'b00011;  // Specify (timing parameters)
    localparam CMD_SENSE_DRIVE    = 5'b00100;  // Sense drive status
    localparam CMD_CONFIGURE      = 5'b10011;  // Configure (82077AA)
    localparam CMD_VERSION        = 5'b10000;  // Version (82077AA)

    //-------------------------------------------------------------------------
    // State machine states
    //-------------------------------------------------------------------------
    localparam S_IDLE           = 5'd0;
    localparam S_CMD_DECODE     = 5'd1;
    localparam S_GET_PARAMS     = 5'd2;

    // Type 1 states
    localparam S_T1_SEEK_START  = 5'd3;
    localparam S_T1_SEEK_WAIT   = 5'd4;
    localparam S_T1_COMPLETE    = 5'd5;

    // Type 2 Read states
    localparam S_T2R_SPINUP     = 5'd6;
    localparam S_T2R_FIND_SYNC  = 5'd7;
    localparam S_T2R_READ_ID    = 5'd8;
    localparam S_T2R_CHECK_ID   = 5'd9;
    localparam S_T2R_FIND_DAM   = 5'd10;
    localparam S_T2R_READ_DATA  = 5'd11;
    localparam S_T2R_CHECK_CRC  = 5'd12;

    // Type 2 Write states
    localparam S_T2W_SPINUP     = 5'd13;
    localparam S_T2W_FIND_ID    = 5'd14;
    localparam S_T2W_WRITE_GAP  = 5'd15;
    localparam S_T2W_WRITE_DATA = 5'd16;
    localparam S_T2W_WRITE_CRC  = 5'd17;

    // Type 3 states
    localparam S_T3_READ_ID     = 5'd18;
    localparam S_T3_FORMAT      = 5'd19;

    // Result phase
    localparam S_RESULT         = 5'd20;
    localparam S_RESULT_WAIT    = 5'd21;

    reg [4:0] state;
    reg [4:0] next_state;

    //-------------------------------------------------------------------------
    // Command parameters
    //-------------------------------------------------------------------------
    reg [7:0] cmd_reg;          // Current command
    reg [7:0] params [0:8];     // Command parameters
    reg [3:0] param_cnt;        // Parameter count
    reg [3:0] param_expected;   // Expected parameters

    // Parsed parameters
    wire [1:0] drive = params[0][1:0];
    wire [7:0] cylinder = params[1];
    wire [7:0] head = params[2];
    wire [7:0] sector = params[3];
    wire [7:0] sector_size = params[4];
    wire [7:0] eot = params[5];      // End of track
    wire [7:0] gap_length = params[6];
    wire [7:0] data_length = params[7];

    // Multi-track and skip flags
    wire mt_flag = cmd_reg[7];
    wire mf_flag = cmd_reg[6];
    wire sk_flag = cmd_reg[5];

    //-------------------------------------------------------------------------
    // Internal counters and flags
    //-------------------------------------------------------------------------
    reg [15:0] byte_count;
    reg [15:0] sector_bytes;
    reg [7:0]  current_sector;
    reg [7:0]  sectors_read;
    reg [7:0]  index_count;
    reg [7:0]  timeout_count;
    reg        id_found;
    reg [7:0]  found_c, found_h, found_r, found_n;

    // Result bytes
    reg [7:0]  result [0:6];
    reg [2:0]  result_cnt;
    reg [2:0]  result_idx;

    // ID field output for track density detection
    assign id_cylinder_out = found_c;

    //-------------------------------------------------------------------------
    // Index pulse counter
    //-------------------------------------------------------------------------
    reg index_prev;
    wire index_edge = index_pulse && !index_prev;

    always @(posedge clk) begin
        if (reset) begin
            index_prev <= 1'b0;
        end else begin
            index_prev <= index_pulse;
        end
    end

    //-------------------------------------------------------------------------
    // Parameter count lookup
    //-------------------------------------------------------------------------
    always @(*) begin
        case (cmd_reg[4:0])
            CMD_READ_DATA,
            CMD_READ_DEL_DATA,
            CMD_WRITE_DATA,
            CMD_WRITE_DEL_DATA,
            CMD_READ_TRACK:      param_expected = 4'd8;
            CMD_READ_ID:         param_expected = 4'd1;
            CMD_FORMAT_TRACK:    param_expected = 4'd5;
            CMD_RECALIBRATE:     param_expected = 4'd1;
            CMD_SEEK:            param_expected = 4'd2;
            CMD_SENSE_DRIVE:     param_expected = 4'd1;
            CMD_SPECIFY:         param_expected = 4'd2;
            CMD_CONFIGURE:       param_expected = 4'd3;
            CMD_SENSE_INT,
            CMD_VERSION:         param_expected = 4'd0;
            default:             param_expected = 4'd0;
        endcase
    end

    //-------------------------------------------------------------------------
    // Sector size calculation
    //-------------------------------------------------------------------------
    always @(*) begin
        case (sector_size)
            8'd0: sector_bytes = 16'd128;
            8'd1: sector_bytes = 16'd256;
            8'd2: sector_bytes = 16'd512;
            8'd3: sector_bytes = 16'd1024;
            8'd4: sector_bytes = 16'd2048;
            8'd5: sector_bytes = 16'd4096;
            8'd6: sector_bytes = 16'd8192;
            8'd7: sector_bytes = 16'd16384;
            default: sector_bytes = 16'd512;
        endcase
    end

    //-------------------------------------------------------------------------
    // Main state machine
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            cmd_reg <= 8'h00;
            param_cnt <= 4'd0;
            busy <= 1'b0;
            dio <= 1'b0;
            rqm <= 1'b1;
            ndma <= 1'b0;
            interrupt <= 1'b0;
            seek_start <= 1'b0;
            seek_target <= 8'd0;
            restore <= 1'b0;
            read_enable <= 1'b0;
            write_enable <= 1'b0;
            crc_reset <= 1'b0;
            fifo_read <= 1'b0;
            fifo_write <= 1'b0;
            head_select <= 2'b00;

            // Status flags
            int_code <= 2'b00;
            seek_end <= 1'b0;
            equipment_check <= 1'b0;
            end_of_cylinder <= 1'b0;
            data_error <= 1'b0;
            overrun <= 1'b0;
            no_data <= 1'b0;
            missing_am <= 1'b0;

            byte_count <= 16'd0;
            current_sector <= 8'd1;
            index_count <= 8'd0;
            timeout_count <= 8'd0;
            id_found <= 1'b0;
            result_cnt <= 3'd0;
            result_idx <= 3'd0;
            id_field_valid <= 1'b0;
        end else if (enable) begin
            // Default outputs
            seek_start <= 1'b0;
            restore <= 1'b0;
            fifo_read <= 1'b0;
            fifo_write <= 1'b0;
            crc_reset <= 1'b0;
            id_field_valid <= 1'b0;  // Pulse only for one cycle

            case (state)
                //-------------------------------------------------------------
                // IDLE - Wait for command
                //-------------------------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;
                    dio <= 1'b0;  // CPU->FDC
                    rqm <= 1'b1;  // Ready for command

                    if (command_valid) begin
                        cmd_reg <= command_byte;
                        param_cnt <= 4'd0;
                        state <= S_CMD_DECODE;
                    end
                end

                //-------------------------------------------------------------
                // CMD_DECODE - Determine command type and get parameters
                //-------------------------------------------------------------
                S_CMD_DECODE: begin
                    busy <= 1'b1;

                    if (param_expected == 4'd0) begin
                        // No parameters, execute immediately
                        case (cmd_reg[4:0])
                            CMD_SENSE_INT: begin
                                // Return ST0 and cylinder
                                result[0] <= {int_code, seek_end, equipment_check,
                                              1'b0, head_select[0], 2'b00};
                                result[1] <= current_track;
                                result_cnt <= 3'd2;
                                result_idx <= 3'd0;
                                int_code <= 2'b00;
                                seek_end <= 1'b0;
                                state <= S_RESULT;
                            end

                            CMD_VERSION: begin
                                result[0] <= 8'h90;  // 82077AA version
                                result_cnt <= 3'd1;
                                result_idx <= 3'd0;
                                state <= S_RESULT;
                            end

                            default: begin
                                state <= S_IDLE;
                            end
                        endcase
                    end else begin
                        state <= S_GET_PARAMS;
                        rqm <= 1'b1;
                    end
                end

                //-------------------------------------------------------------
                // GET_PARAMS - Collect command parameters
                //-------------------------------------------------------------
                S_GET_PARAMS: begin
                    if (command_valid) begin
                        params[param_cnt] <= command_byte;
                        param_cnt <= param_cnt + 1'b1;

                        if (param_cnt + 1'b1 >= param_expected) begin
                            // All parameters received, execute command
                            rqm <= 1'b0;

                            case (cmd_reg[4:0])
                                CMD_RECALIBRATE: begin
                                    restore <= 1'b1;
                                    state <= S_T1_SEEK_WAIT;
                                end

                                CMD_SEEK: begin
                                    seek_target <= params[1];
                                    seek_start <= 1'b1;
                                    state <= S_T1_SEEK_WAIT;
                                end

                                CMD_READ_DATA,
                                CMD_READ_DEL_DATA: begin
                                    head_select <= params[0][2] ? 2'b01 : 2'b00;
                                    current_sector <= params[3];
                                    index_count <= 8'd0;
                                    state <= S_T2R_SPINUP;
                                end

                                CMD_WRITE_DATA,
                                CMD_WRITE_DEL_DATA: begin
                                    if (write_protect) begin
                                        // Write protected
                                        int_code <= 2'b01;
                                        state <= S_RESULT;
                                    end else begin
                                        head_select <= params[0][2] ? 2'b01 : 2'b00;
                                        current_sector <= params[3];
                                        state <= S_T2W_SPINUP;
                                    end
                                end

                                CMD_READ_ID: begin
                                    head_select <= params[0][2] ? 2'b01 : 2'b00;
                                    state <= S_T3_READ_ID;
                                end

                                CMD_SPECIFY: begin
                                    // Store timing parameters (simplified)
                                    state <= S_IDLE;
                                end

                                CMD_SENSE_DRIVE: begin
                                    result[0] <= {1'b0, write_protect, 1'b1, at_track0,
                                                  1'b1, params[0][2], params[0][1:0]};
                                    result_cnt <= 3'd1;
                                    result_idx <= 3'd0;
                                    state <= S_RESULT;
                                end

                                default: begin
                                    int_code <= 2'b10;  // Invalid command
                                    state <= S_IDLE;
                                end
                            endcase
                        end
                    end
                end

                //-------------------------------------------------------------
                // TYPE 1 - Seek/Recalibrate
                //-------------------------------------------------------------
                S_T1_SEEK_WAIT: begin
                    if (seek_complete) begin
                        seek_end <= 1'b1;
                        int_code <= 2'b00;  // Normal termination
                        interrupt <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                //-------------------------------------------------------------
                // TYPE 2 READ - Read Sector
                //-------------------------------------------------------------
                S_T2R_SPINUP: begin
                    // Wait for motor spinup (simplified)
                    read_enable <= 1'b1;
                    crc_reset <= 1'b1;
                    state <= S_T2R_FIND_SYNC;
                    timeout_count <= 8'd0;
                end

                S_T2R_FIND_SYNC: begin
                    // Wait for sync marks
                    if (sync_acquired) begin
                        state <= S_T2R_READ_ID;
                        byte_count <= 16'd0;
                    end else if (index_edge) begin
                        index_count <= index_count + 1'b1;
                        if (index_count >= 8'd2) begin
                            // Timeout - sector not found
                            no_data <= 1'b1;
                            missing_am <= 1'b1;
                            int_code <= 2'b01;
                            state <= S_RESULT;
                        end
                    end
                end

                S_T2R_READ_ID: begin
                    // Read ID field (C H R N)
                    if (read_ready) begin
                        case (byte_count)
                            16'd0: found_c <= read_data;
                            16'd1: found_h <= read_data;
                            16'd2: found_r <= read_data;
                            16'd3: begin
                                found_n <= read_data;
                                id_field_valid <= 1'b1;  // Pulse: complete ID field captured
                            end
                        endcase
                        byte_count <= byte_count + 1'b1;

                        if (byte_count >= 16'd5) begin  // C H R N + 2 CRC bytes
                            state <= S_T2R_CHECK_ID;
                        end
                    end
                end

                S_T2R_CHECK_ID: begin
                    // Check if this is the sector we want
                    if (found_c == cylinder &&
                        found_h == head &&
                        found_r == current_sector &&
                        crc_valid) begin
                        id_found <= 1'b1;
                        crc_reset <= 1'b1;
                        state <= S_T2R_FIND_DAM;
                    end else if (!crc_valid) begin
                        data_error <= 1'b1;
                        state <= S_T2R_FIND_SYNC;
                    end else begin
                        state <= S_T2R_FIND_SYNC;
                    end
                end

                S_T2R_FIND_DAM: begin
                    // Wait for Data Address Mark
                    if (a1_detected) begin
                        byte_count <= 16'd0;
                        state <= S_T2R_READ_DATA;
                        dio <= 1'b1;  // FDC->CPU
                        rqm <= 1'b1;
                    end
                end

                S_T2R_READ_DATA: begin
                    if (read_ready) begin
                        fifo_write_data <= read_data;
                        fifo_write <= 1'b1;
                        byte_count <= byte_count + 1'b1;

                        if (byte_count >= sector_bytes - 1) begin
                            state <= S_T2R_CHECK_CRC;
                        end
                    end
                end

                S_T2R_CHECK_CRC: begin
                    // Read and verify CRC
                    if (read_ready) begin
                        byte_count <= byte_count + 1'b1;
                        if (byte_count >= sector_bytes + 16'd1) begin
                            if (crc_valid) begin
                                // Success
                                if (current_sector < eot) begin
                                    current_sector <= current_sector + 1'b1;
                                    state <= S_T2R_FIND_SYNC;
                                end else begin
                                    // All sectors read
                                    int_code <= 2'b00;
                                    end_of_cylinder <= 1'b1;
                                    state <= S_RESULT;
                                end
                            end else begin
                                data_error <= 1'b1;
                                int_code <= 2'b01;
                                state <= S_RESULT;
                            end
                        end
                    end
                end

                //-------------------------------------------------------------
                // TYPE 3 - Read ID
                //-------------------------------------------------------------
                S_T3_READ_ID: begin
                    read_enable <= 1'b1;
                    crc_reset <= 1'b1;

                    if (sync_acquired && read_ready) begin
                        // Read ID field
                        case (byte_count)
                            16'd0: found_c <= read_data;
                            16'd1: found_h <= read_data;
                            16'd2: found_r <= read_data;
                            16'd3: begin
                                found_n <= read_data;
                                id_field_valid <= 1'b1;  // Pulse: complete ID field captured
                            end
                        endcase
                        byte_count <= byte_count + 1'b1;

                        if (byte_count >= 16'd5) begin
                            // Build result
                            result[0] <= {int_code, 1'b0, equipment_check,
                                          1'b0, head_select[0], drive};
                            result[1] <= 8'h00;  // ST1
                            result[2] <= 8'h00;  // ST2
                            result[3] <= found_c;
                            result[4] <= found_h;
                            result[5] <= found_r;
                            result[6] <= found_n;
                            result_cnt <= 3'd7;
                            result_idx <= 3'd0;
                            read_enable <= 1'b0;
                            state <= S_RESULT;
                        end
                    end else if (index_edge) begin
                        index_count <= index_count + 1'b1;
                        if (index_count >= 8'd2) begin
                            missing_am <= 1'b1;
                            int_code <= 2'b01;
                            state <= S_RESULT;
                        end
                    end
                end

                //-------------------------------------------------------------
                // RESULT - Return result bytes
                //-------------------------------------------------------------
                S_RESULT: begin
                    read_enable <= 1'b0;
                    write_enable <= 1'b0;
                    dio <= 1'b1;  // FDC->CPU
                    rqm <= 1'b1;

                    if (result_idx < result_cnt) begin
                        fifo_write_data <= result[result_idx];
                        fifo_write <= 1'b1;
                        result_idx <= result_idx + 1'b1;
                    end else begin
                        interrupt <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
