//-----------------------------------------------------------------------------
// FDC Register Interface for FluxRipper
// Intel 82077AA-compatible register map
//
// Based on CAPSImg LibIPF/CapsFDC.h register definitions
//
// Extended for Macintosh variable-speed GCR support:
//   CCR bit [4] = mac_zone_enable (enables automatic zone-based data rate)
//
// Extended for QIC-117 tape drive support:
//   TDR bit [7]   = tape_mode_en (enables tape mode, reinterprets FDC signals)
//   TDR bits[2:0] = tape_select (tape drive select 1-3, 0=none)
//
// Updated: 2025-12-10
//-----------------------------------------------------------------------------

module fdc_registers (
    input  wire        clk,
    input  wire        reset,

    // CPU interface
    input  wire [2:0]  addr,            // A0-A2 address lines
    input  wire        cs_n,            // Chip select (active low)
    input  wire        rd_n,            // Read strobe (active low)
    input  wire        wr_n,            // Write strobe (active low)
    input  wire [7:0]  data_in,         // Data from CPU
    output reg  [7:0]  data_out,        // Data to CPU
    output wire        data_oe,         // Data output enable

    // Configuration outputs
    output reg  [1:0]  data_rate,       // 00=500K, 01=300K, 10=250K, 11=1M
    output reg  [3:0]  motor_on,        // Motor enable per drive
    output reg  [1:0]  drive_sel,       // Selected drive (0-3)
    output reg         dma_enable,      // DMA mode enable
    output reg         reset_out,       // Software reset output
    output reg  [3:0]  precomp_delay,   // Write precompensation delay
    output reg         mac_zone_enable, // Macintosh variable-speed zone mode

    // QIC-117 Tape Mode outputs
    output wire        tape_mode_en,    // Tape mode enable (TDR bit 7)
    output wire [2:0]  tape_select,     // Tape drive select (TDR bits 2:0)

    // Status inputs
    input  wire [3:0]  drive_ready,     // Drive ready status
    input  wire        busy,            // FDC busy (command in progress)
    input  wire        ndma,            // Non-DMA mode active
    input  wire [3:0]  dio,             // Data I/O direction
    input  wire        rqm,             // Request for master

    // FIFO interface
    output reg  [7:0]  fifo_data_out,   // Data to FIFO
    output reg         fifo_write,      // Write to FIFO
    input  wire [7:0]  fifo_data_in,    // Data from FIFO
    output reg         fifo_read,       // Read from FIFO
    input  wire        fifo_empty,
    input  wire        fifo_full,

    // Interrupt
    output reg         int_out,         // Interrupt output
    input  wire        int_ack          // Interrupt acknowledged
);

    //-------------------------------------------------------------------------
    // Register addresses (82077AA compatible)
    //-------------------------------------------------------------------------
    localparam ADDR_SRA    = 3'b000;  // Status Register A (read only)
    localparam ADDR_SRB    = 3'b001;  // Status Register B (read only)
    localparam ADDR_DOR    = 3'b010;  // Digital Output Register
    localparam ADDR_TDR    = 3'b011;  // Tape Drive Register
    localparam ADDR_MSR    = 3'b100;  // Main Status Register (read) / DSR (write)
    localparam ADDR_DATA   = 3'b101;  // Data Register (FIFO)
    localparam ADDR_RSVD   = 3'b110;  // Reserved
    localparam ADDR_DIR    = 3'b111;  // Digital Input Register (read) / CCR (write)

    //-------------------------------------------------------------------------
    // Internal registers
    //-------------------------------------------------------------------------

    // DOR - Digital Output Register
    reg [7:0] dor_reg;
    // Bits: [7:4] = motor enable 3-0, [3] = DMA enable, [2] = reset, [1:0] = drive sel

    // DSR - Data Rate Select Register
    reg [7:0] dsr_reg;
    // Bits: [7] = SW reset, [6:5] = power down, [4:2] = precomp, [1:0] = data rate

    // CCR - Configuration Control Register
    reg [7:0] ccr_reg;
    // Bits: [7:5] = reserved, [4] = mac_zone_enable, [3:2] = reserved, [1:0] = data rate

    // TDR - Tape Drive Register
    // Bit [7]   = tape_mode_en (1=tape mode, 0=floppy mode)
    // Bits[6:3] = reserved
    // Bits[2:0] = tape_select (tape drive 1-3, 0=none)
    reg [7:0] tdr_reg;

    // TDR output assignments for QIC-117 controller
    assign tape_mode_en = tdr_reg[7];
    assign tape_select  = tdr_reg[2:0];

    //-------------------------------------------------------------------------
    // Read/Write control
    //-------------------------------------------------------------------------

    wire reg_read  = !cs_n && !rd_n;
    wire reg_write = !cs_n && !wr_n;

    assign data_oe = reg_read;

    //-------------------------------------------------------------------------
    // Register Read Logic
    //-------------------------------------------------------------------------

    // Status Register A (SRA) - 82077AA specific
    wire [7:0] sra_value = {
        1'b0,              // INT pending
        1'b0,              // DRQ
        1'b1,              // STEP
        drive_ready[0],    // Track 0
        1'b1,              // Head 1 select
        1'b0,              // Index
        1'b0,              // Write protect
        1'b1               // Direction
    };

    // Status Register B (SRB) - 82077AA specific
    wire [7:0] srb_value = {
        1'b1,              // Drive 1 data
        1'b1,              // Drive 0 data
        1'b1,              // Write data
        1'b0,              // Read data
        1'b1,              // Write enable
        motor_on[1],       // Motor 1
        motor_on[0],       // Motor 0
        1'b1               // Drive select 0
    };

    // Main Status Register (MSR)
    wire [7:0] msr_value = {
        rqm,               // Request for master
        dio[0],            // Data I/O direction (1=read, 0=write)
        ndma,              // Non-DMA execution
        busy,              // Command busy
        drive_ready        // Drive busy bits (3:0)
    };

    // Digital Input Register (DIR)
    wire [7:0] dir_value = {
        1'b0,              // Disk change (active high)
        7'b0000000
    };

    always @(*) begin
        case (addr)
            ADDR_SRA:  data_out = sra_value;
            ADDR_SRB:  data_out = srb_value;
            ADDR_DOR:  data_out = dor_reg;
            ADDR_TDR:  data_out = tdr_reg;
            ADDR_MSR:  data_out = msr_value;
            ADDR_DATA: data_out = fifo_data_in;
            ADDR_DIR:  data_out = dir_value;
            default:   data_out = 8'hFF;
        endcase
    end

    //-------------------------------------------------------------------------
    // Register Write Logic
    //-------------------------------------------------------------------------

    reg reg_write_prev;
    wire reg_write_edge = reg_write && !reg_write_prev;

    always @(posedge clk) begin
        if (reset) begin
            dor_reg <= 8'h00;
            dsr_reg <= 8'h00;
            ccr_reg <= 8'h00;
            tdr_reg <= 8'h00;
            motor_on <= 4'b0000;
            drive_sel <= 2'b00;
            dma_enable <= 1'b0;
            reset_out <= 1'b1;  // Start in reset
            data_rate <= 2'b00;
            precomp_delay <= 4'h0;
            mac_zone_enable <= 1'b0;  // Standard mode by default
            fifo_write <= 1'b0;
            fifo_read <= 1'b0;
            fifo_data_out <= 8'h00;
            int_out <= 1'b0;
            reg_write_prev <= 1'b0;
        end else begin
            reg_write_prev <= reg_write;
            fifo_write <= 1'b0;
            fifo_read <= 1'b0;

            // FIFO read on data register access
            if (reg_read && addr == ADDR_DATA) begin
                fifo_read <= 1'b1;
            end

            if (reg_write_edge) begin
                case (addr)
                    ADDR_DOR: begin
                        dor_reg <= data_in;
                        motor_on <= data_in[7:4];
                        dma_enable <= data_in[3];
                        reset_out <= ~data_in[2];  // Active low in DOR
                        drive_sel <= data_in[1:0];
                    end

                    ADDR_TDR: begin
                        tdr_reg <= data_in;
                    end

                    ADDR_MSR: begin  // DSR write
                        dsr_reg <= data_in;
                        if (data_in[7]) begin
                            reset_out <= 1'b1;  // Software reset
                        end
                        precomp_delay <= {1'b0, data_in[4:2]};
                        data_rate <= data_in[1:0];
                    end

                    ADDR_DATA: begin
                        fifo_data_out <= data_in;
                        fifo_write <= 1'b1;
                    end

                    ADDR_DIR: begin  // CCR write
                        ccr_reg <= data_in;
                        data_rate <= data_in[1:0];
                        mac_zone_enable <= data_in[4];  // Mac variable-speed mode
                    end
                endcase
            end

            // Clear reset after one cycle
            if (reset_out && !reg_write) begin
                reset_out <= 1'b0;
            end

            // Interrupt handling
            if (int_ack) begin
                int_out <= 1'b0;
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// 16-Byte Data FIFO for 82077AA compatibility
//-----------------------------------------------------------------------------
module fdc_fifo (
    input  wire        clk,
    input  wire        reset,

    // Write port
    input  wire [7:0]  data_in,
    input  wire        write_en,

    // Read port
    output wire [7:0]  data_out,
    input  wire        read_en,

    // Status
    output wire        empty,
    output wire        full,
    output wire [4:0]  count,

    // Threshold (standard is 1 for DRQ assertion)
    input  wire [3:0]  threshold,
    output wire        threshold_reached
);

    // 16-byte FIFO
    reg [7:0] fifo_mem [0:15];
    reg [4:0] rd_ptr;
    reg [4:0] wr_ptr;
    reg [4:0] fifo_count;

    assign data_out = fifo_mem[rd_ptr[3:0]];
    assign empty = (fifo_count == 5'd0);
    assign full = (fifo_count == 5'd16);
    assign count = fifo_count;
    assign threshold_reached = (fifo_count >= {1'b0, threshold});

    always @(posedge clk) begin
        if (reset) begin
            rd_ptr <= 5'd0;
            wr_ptr <= 5'd0;
            fifo_count <= 5'd0;
        end else begin
            // Write
            if (write_en && !full) begin
                fifo_mem[wr_ptr[3:0]] <= data_in;
                wr_ptr <= wr_ptr + 1'b1;
                fifo_count <= fifo_count + 1'b1;
            end

            // Read
            if (read_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
                fifo_count <= fifo_count - 1'b1;
            end

            // Simultaneous read/write
            if (write_en && read_en && !empty && !full) begin
                // Count stays same
                fifo_count <= fifo_count;
            end
        end
    end

endmodule

//-----------------------------------------------------------------------------
// Status Register Logic
// Generates ST0, ST1, ST2, ST3 status bytes
//-----------------------------------------------------------------------------
module fdc_status (
    input  wire        clk,
    input  wire        reset,

    // Command result inputs
    input  wire [1:0]  int_code,        // Interrupt code for ST0
    input  wire        seek_end,        // Seek end
    input  wire        equipment_check, // Drive not ready
    input  wire        not_ready,       // Drive not ready
    input  wire [1:0]  head_addr,       // Head address
    input  wire [1:0]  drive_sel,       // Drive select

    // Error flags for ST1
    input  wire        end_of_cylinder, // End of track
    input  wire        data_error,      // CRC error in data field
    input  wire        overrun,         // Overrun/underrun
    input  wire        no_data,         // Sector not found
    input  wire        not_writable,    // Write protect
    input  wire        missing_am,      // Missing address mark

    // Error flags for ST2
    input  wire        control_mark,    // Deleted data
    input  wire        data_error_dd,   // CRC error in data
    input  wire        wrong_cyl,       // Wrong cylinder
    input  wire        scan_equal,      // Scan equal hit
    input  wire        scan_not_sat,    // Scan not satisfied
    input  wire        bad_cyl,         // Bad cylinder
    input  wire        missing_dam,     // Missing data AM

    // Current position
    input  wire [7:0]  current_cyl,
    input  wire [7:0]  current_head,
    input  wire [7:0]  current_sector,
    input  wire [7:0]  sector_size,

    // Status outputs
    output wire [7:0]  st0,
    output wire [7:0]  st1,
    output wire [7:0]  st2,
    output wire [7:0]  st3,
    output wire [7:0]  c_out,           // Cylinder
    output wire [7:0]  h_out,           // Head
    output wire [7:0]  r_out,           // Record (sector)
    output wire [7:0]  n_out            // Number (size)
);

    // ST0: Status Register 0
    // [7:6] = Interrupt code, [5] = Seek end, [4] = Equipment check
    // [3] = Not ready, [2] = Head, [1:0] = Drive select
    assign st0 = {int_code, seek_end, equipment_check,
                  not_ready, head_addr[0], drive_sel};

    // ST1: Status Register 1
    // [7] = End of cylinder, [6] = 0, [5] = Data error, [4] = Overrun
    // [3] = 0, [2] = No data, [1] = Not writable, [0] = Missing AM
    assign st1 = {end_of_cylinder, 1'b0, data_error, overrun,
                  1'b0, no_data, not_writable, missing_am};

    // ST2: Status Register 2
    // [7] = 0, [6] = Control mark, [5] = Data error, [4] = Wrong cylinder
    // [3] = Scan equal, [2] = Scan not satisfied, [1] = Bad cylinder, [0] = Missing DAM
    assign st2 = {1'b0, control_mark, data_error_dd, wrong_cyl,
                  scan_equal, scan_not_sat, bad_cyl, missing_dam};

    // ST3: Status Register 3 (Drive status)
    // [7] = Fault, [6] = Write protect, [5] = Ready, [4] = Track 0
    // [3] = Two side, [2] = Head, [1:0] = Drive
    assign st3 = {1'b0, not_writable, ~not_ready, (current_cyl == 8'd0),
                  1'b1, head_addr[0], drive_sel};

    // Result bytes
    assign c_out = current_cyl;
    assign h_out = current_head;
    assign r_out = current_sector;
    assign n_out = sector_size;

endmodule
