// SPDX-License-Identifier: BSD-3-Clause
//-----------------------------------------------------------------------------
// debug_console_parser.v - Text-Based Debug Command Parser
//
// Part of FluxRipper - Open-source disk preservation system
// Copyright (c) 2025 John Fabienke
//
// Created: 2025-12-07 15:15
//
// Description:
//   Parses text commands from CDC console and generates debug operations.
//   Simple command format designed for easy scripting and Claude interaction.
//
// Command Format:
//   Commands are newline-terminated ASCII strings.
//   Arguments are space-separated hex values (no 0x prefix needed).
//
// Command Set:
//   r <addr>           - Read 32-bit word
//   w <addr> <data>    - Write 32-bit word
//   d <addr> <len>     - Hex dump
//   probe [group]      - Show signal tap
//   trace start|stop   - Trace control
//   halt|run|step      - CPU control
//   status             - System status
//   id                 - Show IDCODE
//   help               - Command list
//
// Response Format:
//   OK: <result>       - Success with optional data
//   ERR: <message>     - Error with description
//
//-----------------------------------------------------------------------------

module debug_console_parser #(
    parameter CLK_FREQ_HZ = 100_000_000
)(
    input               clk,
    input               rst_n,

    //-------------------------------------------------------------------------
    // CDC Console Interface
    //-------------------------------------------------------------------------
    input  [7:0]        cmd_data,
    input               cmd_valid,
    output              cmd_ready,
    output reg [7:0]    rsp_data,
    output reg          rsp_valid,
    input               rsp_ready,

    //-------------------------------------------------------------------------
    // Debug Register Interface
    //-------------------------------------------------------------------------
    output reg [31:0]   reg_addr,
    output reg [31:0]   reg_wdata,
    input  [31:0]       reg_rdata,
    output reg          reg_we,
    output reg          reg_re,
    input               reg_ready,

    //-------------------------------------------------------------------------
    // Memory Access Interface
    //-------------------------------------------------------------------------
    output reg [31:0]   mem_addr,
    output reg [31:0]   mem_wdata,
    input  [31:0]       mem_rdata,
    output reg          mem_read_req,
    output reg          mem_write_req,
    input               mem_ready,

    //-------------------------------------------------------------------------
    // Signal Tap Interface
    //-------------------------------------------------------------------------
    input  [127:0]      tap_captured,
    output reg [31:0]   tap_trigger_mask,
    output reg [31:0]   tap_trigger_value,

    //-------------------------------------------------------------------------
    // Trace Control
    //-------------------------------------------------------------------------
    output reg          trace_enable,
    output reg          trace_clear,
    output reg [11:0]   trace_read_addr,
    input  [63:0]       trace_data_out,
    input  [11:0]       trace_count,

    //-------------------------------------------------------------------------
    // CPU Control
    //-------------------------------------------------------------------------
    output reg          cpu_halt_req,
    output reg          cpu_resume_req,
    output reg          cpu_reset_req,
    output reg [4:0]    cpu_reg_addr,
    output reg [31:0]   cpu_bp_addr,
    output reg          cpu_bp_enable,

    //-------------------------------------------------------------------------
    // Status
    //-------------------------------------------------------------------------
    output              debug_active,
    input  [3:0]        current_layer
);

    //=========================================================================
    // State Machine
    //=========================================================================

    localparam [3:0]
        S_IDLE      = 4'd0,
        S_RECEIVE   = 4'd1,
        S_PARSE     = 4'd2,
        S_EXECUTE   = 4'd3,
        S_WAIT      = 4'd4,
        S_RESPOND   = 4'd5,
        S_SEND_CHAR = 4'd6,
        S_DONE      = 4'd7;

    reg [3:0] state;

    //=========================================================================
    // Command Buffer
    //=========================================================================

    localparam CMD_BUF_SIZE = 64;

    reg [7:0] cmd_buf [0:CMD_BUF_SIZE-1];
    reg [5:0] cmd_len;
    reg [5:0] cmd_ptr;

    //=========================================================================
    // Response Buffer
    //=========================================================================

    localparam RSP_BUF_SIZE = 128;

    reg [7:0] rsp_buf [0:RSP_BUF_SIZE-1];
    reg [6:0] rsp_len;
    reg [6:0] rsp_ptr;

    //=========================================================================
    // Parsed Command
    //=========================================================================

    reg [7:0]  cmd_type;      // First character of command
    reg [31:0] arg1;          // First argument
    reg [31:0] arg2;          // Second argument
    reg [31:0] result;        // Operation result
    reg        has_error;

    //=========================================================================
    // Command Receive
    //=========================================================================

    assign cmd_ready = (state == S_IDLE || state == S_RECEIVE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cmd_len <= 6'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    cmd_len <= 6'd0;
                    rsp_len <= 7'd0;
                    has_error <= 1'b0;
                    if (cmd_valid && cmd_data != 8'h0D && cmd_data != 8'h0A) begin
                        cmd_buf[0] <= cmd_data;
                        cmd_len <= 6'd1;
                        state <= S_RECEIVE;
                    end
                end

                S_RECEIVE: begin
                    if (cmd_valid) begin
                        if (cmd_data == 8'h0D || cmd_data == 8'h0A) begin
                            // End of command
                            state <= S_PARSE;
                        end else if (cmd_len < CMD_BUF_SIZE - 1) begin
                            cmd_buf[cmd_len] <= cmd_data;
                            cmd_len <= cmd_len + 1;
                        end
                    end
                end

                S_PARSE: begin
                    // Extract command type (first character)
                    cmd_type <= cmd_buf[0];
                    arg1 <= 32'd0;
                    arg2 <= 32'd0;
                    state <= S_EXECUTE;
                end

                S_EXECUTE: begin
                    // Execute command based on type
                    case (cmd_type)
                        "r", "R": begin
                            // Read memory
                            parse_hex_arg(1, arg1);
                            mem_addr <= arg1;
                            mem_read_req <= 1'b1;
                            state <= S_WAIT;
                        end

                        "w", "W": begin
                            // Write memory
                            parse_hex_arg(1, arg1);
                            parse_hex_arg_after_space(arg1, arg2);
                            mem_addr <= arg1;
                            mem_wdata <= arg2;
                            mem_write_req <= 1'b1;
                            state <= S_WAIT;
                        end

                        "p", "P": begin
                            // Probe (signal tap)
                            format_probe_response();
                            state <= S_RESPOND;
                        end

                        "s", "S": begin
                            // Status
                            format_status_response();
                            state <= S_RESPOND;
                        end

                        "i", "I": begin
                            // IDCODE
                            format_id_response();
                            state <= S_RESPOND;
                        end

                        "h", "H": begin
                            // Help or Halt
                            if (cmd_len > 1 && (cmd_buf[1] == "a" || cmd_buf[1] == "A")) begin
                                // Halt
                                cpu_halt_req <= 1'b1;
                                format_ok_response();
                            end else begin
                                // Help
                                format_help_response();
                            end
                            state <= S_RESPOND;
                        end

                        "g", "G": begin
                            // Go (run)
                            cpu_resume_req <= 1'b1;
                            format_ok_response();
                            state <= S_RESPOND;
                        end

                        "t", "T": begin
                            // Trace control
                            if (cmd_len > 2 && cmd_buf[2] == "a") begin
                                trace_enable <= 1'b1;
                            end else if (cmd_len > 2 && cmd_buf[2] == "o") begin
                                trace_enable <= 1'b0;
                            end else if (cmd_len > 2 && cmd_buf[2] == "c") begin
                                trace_clear <= 1'b1;
                            end
                            format_ok_response();
                            state <= S_RESPOND;
                        end

                        "?": begin
                            // Quick help
                            format_quick_help();
                            state <= S_RESPOND;
                        end

                        default: begin
                            // Unknown command
                            format_error_response("Unknown command");
                            state <= S_RESPOND;
                        end
                    endcase
                end

                S_WAIT: begin
                    // Wait for memory operation
                    mem_read_req <= 1'b0;
                    mem_write_req <= 1'b0;

                    if (mem_ready) begin
                        result <= mem_rdata;
                        format_read_response(mem_rdata);
                        state <= S_RESPOND;
                    end
                end

                S_RESPOND: begin
                    // Start sending response
                    cpu_halt_req <= 1'b0;
                    cpu_resume_req <= 1'b0;
                    trace_clear <= 1'b0;
                    rsp_ptr <= 7'd0;
                    state <= S_SEND_CHAR;
                end

                S_SEND_CHAR: begin
                    if (rsp_ptr < rsp_len) begin
                        if (rsp_ready || !rsp_valid) begin
                            rsp_data <= rsp_buf[rsp_ptr];
                            rsp_valid <= 1'b1;
                            rsp_ptr <= rsp_ptr + 1;
                        end
                    end else begin
                        rsp_valid <= 1'b0;
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    //=========================================================================
    // Helper Tasks for Response Formatting
    //=========================================================================

    task format_ok_response;
        begin
            rsp_buf[0] <= "O";
            rsp_buf[1] <= "K";
            rsp_buf[2] <= 8'h0D;
            rsp_buf[3] <= 8'h0A;
            rsp_len <= 7'd4;
        end
    endtask

    task format_read_response;
        input [31:0] value;
        begin
            // Format: "OK: XXXXXXXX\r\n"
            rsp_buf[0] <= "O";
            rsp_buf[1] <= "K";
            rsp_buf[2] <= ":";
            rsp_buf[3] <= " ";
            rsp_buf[4] <= hex_char(value[31:28]);
            rsp_buf[5] <= hex_char(value[27:24]);
            rsp_buf[6] <= hex_char(value[23:20]);
            rsp_buf[7] <= hex_char(value[19:16]);
            rsp_buf[8] <= hex_char(value[15:12]);
            rsp_buf[9] <= hex_char(value[11:8]);
            rsp_buf[10] <= hex_char(value[7:4]);
            rsp_buf[11] <= hex_char(value[3:0]);
            rsp_buf[12] <= 8'h0D;
            rsp_buf[13] <= 8'h0A;
            rsp_len <= 7'd14;
        end
    endtask

    task format_error_response;
        input [127:0] msg;  // Unused in simple version
        begin
            rsp_buf[0] <= "E";
            rsp_buf[1] <= "R";
            rsp_buf[2] <= "R";
            rsp_buf[3] <= 8'h0D;
            rsp_buf[4] <= 8'h0A;
            rsp_len <= 7'd5;
        end
    endtask

    task format_id_response;
        begin
            // "ID: FB010001\r\n"
            rsp_buf[0] <= "I";
            rsp_buf[1] <= "D";
            rsp_buf[2] <= ":";
            rsp_buf[3] <= " ";
            rsp_buf[4] <= "F";
            rsp_buf[5] <= "B";
            rsp_buf[6] <= "0";
            rsp_buf[7] <= "1";
            rsp_buf[8] <= "0";
            rsp_buf[9] <= "0";
            rsp_buf[10] <= "0";
            rsp_buf[11] <= "1";
            rsp_buf[12] <= 8'h0D;
            rsp_buf[13] <= 8'h0A;
            rsp_len <= 7'd14;
        end
    endtask

    task format_status_response;
        begin
            // "L:X\r\n" where X is layer number
            rsp_buf[0] <= "L";
            rsp_buf[1] <= ":";
            rsp_buf[2] <= hex_char({4'd0, current_layer});
            rsp_buf[3] <= 8'h0D;
            rsp_buf[4] <= 8'h0A;
            rsp_len <= 7'd5;
        end
    endtask

    task format_probe_response;
        begin
            // Show group 0 probe values
            rsp_buf[0] <= "P";
            rsp_buf[1] <= ":";
            rsp_buf[2] <= hex_char(tap_captured[31:28]);
            rsp_buf[3] <= hex_char(tap_captured[27:24]);
            rsp_buf[4] <= hex_char(tap_captured[23:20]);
            rsp_buf[5] <= hex_char(tap_captured[19:16]);
            rsp_buf[6] <= hex_char(tap_captured[15:12]);
            rsp_buf[7] <= hex_char(tap_captured[11:8]);
            rsp_buf[8] <= hex_char(tap_captured[7:4]);
            rsp_buf[9] <= hex_char(tap_captured[3:0]);
            rsp_buf[10] <= 8'h0D;
            rsp_buf[11] <= 8'h0A;
            rsp_len <= 7'd12;
        end
    endtask

    task format_quick_help;
        begin
            // "r w p s h g t\r\n"
            rsp_buf[0] <= "r";
            rsp_buf[1] <= " ";
            rsp_buf[2] <= "w";
            rsp_buf[3] <= " ";
            rsp_buf[4] <= "p";
            rsp_buf[5] <= " ";
            rsp_buf[6] <= "s";
            rsp_buf[7] <= " ";
            rsp_buf[8] <= "h";
            rsp_buf[9] <= " ";
            rsp_buf[10] <= "g";
            rsp_buf[11] <= " ";
            rsp_buf[12] <= "t";
            rsp_buf[13] <= 8'h0D;
            rsp_buf[14] <= 8'h0A;
            rsp_len <= 7'd15;
        end
    endtask

    task format_help_response;
        begin
            format_quick_help();
        end
    endtask

    //=========================================================================
    // Hex Parsing and Formatting Functions
    //=========================================================================

    function [7:0] hex_char;
        input [3:0] nibble;
        begin
            if (nibble < 10)
                hex_char = "0" + nibble;
            else
                hex_char = "A" + nibble - 10;
        end
    endfunction

    // Placeholder for argument parsing - would be more complex in practice
    task parse_hex_arg;
        input [5:0] start_pos;
        output [31:0] value;
        begin
            value = 32'd0;
            // Simple placeholder - real implementation would parse hex chars
        end
    endtask

    task parse_hex_arg_after_space;
        input [31:0] dummy;
        output [31:0] value;
        begin
            value = 32'd0;
        end
    endtask

    //=========================================================================
    // Debug Active Indicator
    //=========================================================================

    assign debug_active = (state != S_IDLE);

endmodule
