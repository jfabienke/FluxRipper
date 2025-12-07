//-----------------------------------------------------------------------------
// msc_sector_buffer.v
// USB Mass Storage Class - Sector Buffer
//
// Created: 2025-12-05 15:15
//
// Double-buffered sector FIFO for USB Mass Storage data transfers.
// Provides streaming interface between USB and drive HAL.
//
// Features:
//   - Double-buffered to allow continuous streaming
//   - 512-byte sector size (configurable)
//   - Supports both read (drive->host) and write (host->drive) paths
//   - Word-aligned (32-bit) interface to USB
//   - Byte-aligned interface to HAL for sector data
//-----------------------------------------------------------------------------

module msc_sector_buffer #(
    parameter SECTOR_SIZE  = 512,         // Bytes per sector
    parameter BUFFER_COUNT = 2,           // Double buffering
    parameter WORD_WIDTH   = 32           // USB interface width
)(
    input  wire        clk,
    input  wire        rst_n,

    //=========================================================================
    // USB Side Interface (32-bit words)
    //=========================================================================

    // Write path (data from host for WRITE commands)
    input  wire [31:0] usb_wr_data,
    input  wire        usb_wr_valid,
    output wire        usb_wr_ready,

    // Read path (data to host for READ commands)
    output wire [31:0] usb_rd_data,
    output wire        usb_rd_valid,
    input  wire        usb_rd_ready,

    //=========================================================================
    // HAL/Drive Side Interface (byte-oriented via 32-bit words)
    //=========================================================================

    // Read from buffer (for WRITE commands - data goes to drive)
    output wire [31:0] hal_rd_data,
    output wire        hal_rd_valid,
    input  wire        hal_rd_ready,
    output wire        hal_sector_ready,  // Full sector available

    // Write to buffer (for READ commands - data from drive)
    input  wire [31:0] hal_wr_data,
    input  wire        hal_wr_valid,
    output wire        hal_wr_ready,

    //=========================================================================
    // Control
    //=========================================================================

    input  wire        transfer_start,    // Start new transfer
    input  wire        transfer_dir,      // 0=WRITE(host->drive), 1=READ(drive->host)
    input  wire [15:0] sector_count,      // Number of sectors to transfer
    output wire        transfer_done,     // All sectors transferred
    output reg  [15:0] sectors_completed, // Sectors transferred so far

    //=========================================================================
    // Status
    //=========================================================================

    output wire [8:0]  usb_fifo_level,    // Words in USB-side FIFO
    output wire [8:0]  hal_fifo_level,    // Words in HAL-side FIFO
    output wire        buffer_empty,
    output wire        buffer_full
);

    //=========================================================================
    // Local Parameters
    //=========================================================================

    localparam WORDS_PER_SECTOR = SECTOR_SIZE / (WORD_WIDTH / 8);  // 128 words
    localparam FIFO_DEPTH = WORDS_PER_SECTOR * BUFFER_COUNT;       // 256 words
    localparam FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH);               // 8 bits

    //=========================================================================
    // FIFO Memory
    //=========================================================================

    reg [WORD_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];

    // FIFO pointers
    reg [FIFO_ADDR_WIDTH:0] wr_ptr;
    reg [FIFO_ADDR_WIDTH:0] rd_ptr;

    // FIFO status
    wire [FIFO_ADDR_WIDTH:0] fifo_count = wr_ptr - rd_ptr;
    wire fifo_empty = (wr_ptr == rd_ptr);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    //=========================================================================
    // Transfer State Machine
    //=========================================================================

    localparam ST_IDLE      = 2'd0;
    localparam ST_WRITE     = 2'd1;  // Host -> Drive (WRITE command)
    localparam ST_READ      = 2'd2;  // Drive -> Host (READ command)

    reg [1:0] state;
    reg [15:0] target_sectors;
    reg [15:0] usb_word_count;    // Words received/sent on USB side
    reg [15:0] hal_word_count;    // Words read/written on HAL side

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            target_sectors <= 16'h0;
            sectors_completed <= 16'h0;
            usb_word_count <= 16'h0;
            hal_word_count <= 16'h0;
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (transfer_start) begin
                        target_sectors <= sector_count;
                        sectors_completed <= 16'h0;
                        usb_word_count <= 16'h0;
                        hal_word_count <= 16'h0;
                        wr_ptr <= 0;
                        rd_ptr <= 0;

                        if (transfer_dir)
                            state <= ST_READ;   // Drive -> Host
                        else
                            state <= ST_WRITE;  // Host -> Drive
                    end
                end

                ST_WRITE: begin
                    // Host -> Drive: USB writes, HAL reads

                    // USB write
                    if (usb_wr_valid && usb_wr_ready_int) begin
                        fifo_mem[wr_ptr[FIFO_ADDR_WIDTH-1:0]] <= usb_wr_data;
                        wr_ptr <= wr_ptr + 1'b1;
                        usb_word_count <= usb_word_count + 1'b1;
                    end

                    // HAL read
                    if (hal_rd_valid_int && hal_rd_ready) begin
                        rd_ptr <= rd_ptr + 1'b1;
                        hal_word_count <= hal_word_count + 1'b1;

                        // Check for sector completion
                        if (hal_word_count[6:0] == (WORDS_PER_SECTOR - 1)) begin
                            sectors_completed <= sectors_completed + 1'b1;
                        end
                    end

                    // Check for transfer completion
                    if (sectors_completed == target_sectors)
                        state <= ST_IDLE;
                end

                ST_READ: begin
                    // Drive -> Host: HAL writes, USB reads

                    // HAL write
                    if (hal_wr_valid && hal_wr_ready_int) begin
                        fifo_mem[wr_ptr[FIFO_ADDR_WIDTH-1:0]] <= hal_wr_data;
                        wr_ptr <= wr_ptr + 1'b1;
                        hal_word_count <= hal_word_count + 1'b1;
                    end

                    // USB read
                    if (usb_rd_valid_int && usb_rd_ready) begin
                        rd_ptr <= rd_ptr + 1'b1;
                        usb_word_count <= usb_word_count + 1'b1;

                        // Check for sector completion
                        if (usb_word_count[6:0] == (WORDS_PER_SECTOR - 1)) begin
                            sectors_completed <= sectors_completed + 1'b1;
                        end
                    end

                    // Check for transfer completion
                    if (sectors_completed == target_sectors)
                        state <= ST_IDLE;
                end
            endcase
        end
    end

    //=========================================================================
    // Data Path Multiplexing
    //=========================================================================

    // Internal ready/valid signals
    wire usb_wr_ready_int = !fifo_full && (state == ST_WRITE);
    wire usb_rd_valid_int = !fifo_empty && (state == ST_READ);
    wire hal_rd_valid_int = !fifo_empty && (state == ST_WRITE);
    wire hal_wr_ready_int = !fifo_full && (state == ST_READ);

    // USB interface
    assign usb_wr_ready = usb_wr_ready_int;
    assign usb_rd_data  = fifo_mem[rd_ptr[FIFO_ADDR_WIDTH-1:0]];
    assign usb_rd_valid = usb_rd_valid_int;

    // HAL interface
    assign hal_rd_data  = fifo_mem[rd_ptr[FIFO_ADDR_WIDTH-1:0]];
    assign hal_rd_valid = hal_rd_valid_int;
    assign hal_wr_ready = hal_wr_ready_int;

    // Sector ready - at least one full sector available for HAL
    assign hal_sector_ready = (fifo_count >= WORDS_PER_SECTOR) && (state == ST_WRITE);

    //=========================================================================
    // Status Outputs
    //=========================================================================

    assign usb_fifo_level = (state == ST_WRITE) ? fifo_count[8:0] :
                            (state == ST_READ)  ? fifo_count[8:0] : 9'h0;
    assign hal_fifo_level = fifo_count[8:0];

    assign buffer_empty = fifo_empty;
    assign buffer_full  = fifo_full;

    assign transfer_done = (state == ST_IDLE) && (sectors_completed == target_sectors) && (target_sectors > 0);

endmodule
