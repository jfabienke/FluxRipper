# FluxRipper ISA Option ROM Design

**Date:** 2025-12-07 14:30
**Updated:** 2025-12-07
**Status:** Design Specification
**Target:** Universal Card (ISA + USB 2.0 HS)

---

## Overview

FluxRipper uses **two Option ROMs** to provide complete BIOS-level support for vintage PCs:

1. **FDC ROM: Sergey's Multi-Floppy BIOS** — Enhanced floppy support
2. **HDD ROM: FluxRipper HDD BIOS** — ST-506/ESDI hard drive support

When inserted into an ISA slot, the host BIOS automatically discovers and initializes both ROMs during POST.

---

## Dual ROM Architecture

### Why Two ROMs?

| ROM | INT Hook | Purpose |
|-----|----------|---------|
| **Multi-Floppy BIOS** | INT 13h (FDD) | Replace motherboard floppy logic |
| **HDD BIOS** | INT 13h (HDD) | Add ST-506/ESDI hard drive support |

The PC BIOS uses INT 13h for both floppy and hard drives, distinguished by drive number:
- Drives 00h-7Fh: Floppy drives (A:, B:, etc.)
- Drives 80h-FFh: Hard drives (C:, D:, etc.)

### ROM Memory Map

```
┌─────────────────────────────────────────────────────────────────┐
│ C8000h - CBFFFh (16KB)  │  Multi-Floppy BIOS (FDC)              │
├─────────────────────────────────────────────────────────────────┤
│ CC000h - CFFFFh (16KB)  │  FluxRipper HDD BIOS                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. Multi-Floppy BIOS (Sergey's BIOS)

### Source & License

- **Author:** Sergey Kiselev
- **Used by:** TexElec Quad-Flop, other retro projects
- **Repository:** https://github.com/skiselev/floppy_bios
- **License:** GPL v3

### What It Does

The Multi-Floppy BIOS **replaces the motherboard's native floppy logic**, enabling:

| Feature | Standard BIOS | Multi-Floppy BIOS |
|---------|---------------|-------------------|
| Max drives | 2 (A:, B:) | **4** (A:, B:, C:, D:) |
| 360KB 5.25" | Yes | Yes |
| 720KB 3.5" | Some | **Yes** |
| 1.2MB 5.25" | AT only | **Yes (including XT!)** |
| 1.44MB 3.5" | AT only | **Yes (including XT!)** |
| 2.88MB 3.5" | Rare | **Yes** |
| Boot from HD floppy on XT | No | **Yes** |

### The Magic: HD Floppy on IBM PC 5150

The original IBM PC 5150 BIOS only understands 360KB drives. Multi-Floppy BIOS:

1. Hooks INT 13h before the motherboard BIOS
2. Intercepts all floppy requests (drives 00h-03h)
3. Handles the request using its own FDC driver
4. Supports 500kbps data rate (HD) even on XT FDC hardware
5. Returns results in standard INT 13h format

This allows an unmodified IBM PC 5150 to **boot from a 1.44MB floppy**.

### FluxRipper Integration

FluxRipper's FDC emulation provides the hardware interface, while Multi-Floppy BIOS provides the software:

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST PC                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                    INT 13h Call                         │   │
│   │                    (Drive 00h-03h)                      │   │
│   └────────────────────────┬────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              Multi-Floppy BIOS (ROM)                    │   │
│   │  • Hooks INT 13h                                        │   │
│   │  • Manages 4 drives                                     │   │
│   │  • All floppy formats                                   │   │
│   └────────────────────────┬────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              I/O Ports 0x3F0-0x3F7                      │   │
│   └────────────────────────┬────────────────────────────────┘   │
└────────────────────────────┼────────────────────────────────────┘
                             │ ISA Bus
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FLUXRIPPER FPGA                            │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                  FDC Emulation                          │   │
│   │  • 82077AA-compatible registers                         │   │
│   │  • All data rates (250/300/500/1000 kbps)               │   │
│   └────────────────────────┬────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              Physical Floppy Interface                  │   │
│   │              (34-pin Shugart J3)                        │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Options

Multi-Floppy BIOS typically supports configuration via:
- DIP switches (on ISA card)
- EEPROM settings
- Jumpers

For FluxRipper, we'll expose these via:
- USB configuration tool (saved to SPI flash)
- Optional onboard DIP switch

| Setting | Options |
|---------|---------|
| Drive 0 Type | 360K, 720K, 1.2M, 1.44M, 2.88M |
| Drive 1 Type | 360K, 720K, 1.2M, 1.44M, 2.88M |
| Drive 2 Type | None, 360K, 720K, 1.2M, 1.44M, 2.88M |
| Drive 3 Type | None, 360K, 720K, 1.2M, 1.44M, 2.88M |
| Boot Drive | A:, B:, C:, D: |

---

## 2. FluxRipper HDD BIOS

The HDD BIOS provides INT 13h services for ST-506 (MFM/RLL) and ESDI hard drives. See **[HDD_BIOS_DESIGN.md](HDD_BIOS_DESIGN.md)** for complete design specification.

### Design Philosophy

Inspired by [XTIDE Universal BIOS](https://www.xtideuniversalbios.org/) modern architecture, but targeting ST-506/ESDI interfaces (not IDE):

- **Leverage FPGA Auto-Detection** — Geometry read from FluxRipper discovery registers
- **IBM AT Compatible** — Register sequences match original AT BIOS for compatibility
- **Universal Slot Support** — Automatic 8-bit/16-bit adaptation

### Key Features

| Feature | 8KB Build | 16KB Build |
|---------|:---------:|:----------:|
| INT 13h Standard (00h-15h) | ✓ | ✓ |
| Auto-detected geometry | ✓ | ✓ |
| All WD personalities | ✓ | ✓ |
| 8-bit XT / 16-bit AT mode | ✓ | ✓ |
| INT 13h Extensions (LBA) | - | ✓ |
| Boot menu (F12) | - | ✓ |
| Setup utility (F2) | - | ✓ |
| Diagnostics | - | ✓ |

### Supported Controller Personalities

| Personality | Slot | Interface | Encoding | Max SPT |
|-------------|------|-----------|----------|---------|
| WD1002-WX1 | 8-bit XT | ST-506 | MFM | 17 |
| WD1003-WAH | 16-bit AT | ST-506 | MFM | 17 |
| WD1006-WAH | 16-bit AT | ST-506 | RLL 2,7 | 26 |
| WD1007-WAH | 16-bit AT | ESDI | MFM/RLL | 36+ |

### Auto-Detection Integration

The FluxRipper FPGA performs drive discovery at power-on:

```
FPGA Discovery Pipeline:
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ PHY Probe    │ → │ Rate Detect  │ → │ Decode Test  │ → │ Geometry     │
│ (SE vs Diff) │   │ (5-15 Mbps)  │   │ (MFM vs RLL) │   │ Scan         │
└──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
                                                                │
                           ┌────────────────────────────────────┘
                           ▼
                   ┌──────────────────────────────────────────────────┐
                   │ HDD BIOS reads results from discovery registers: │
                   │   - Cylinders, heads, sectors per track          │
                   │   - Encoding type (MFM/RLL/ESDI)                 │
                   │   - For ESDI: geometry from GET_DEV_CONFIG       │
                   └──────────────────────────────────────────────────┘
```

The BIOS does **not** probe the drive directly — it reads pre-computed geometry from FPGA registers.

---

## Option ROM Fundamentals

### ROM Header Format (Mandatory)

Every Option ROM must begin with this header structure:

| Offset | Size | Field | Value/Description |
|--------|------|-------|-------------------|
| 0x00 | 1 | Signature Lo | `0x55` |
| 0x01 | 1 | Signature Hi | `0xAA` |
| 0x02 | 1 | ROM Size | Size in 512-byte blocks (e.g., `0x20` = 16KB) |
| 0x03 | 3 | Entry Point | `JMP` instruction to init routine |
| 0x06-0x17 | 18 | Reserved | Pad with `0x00` |
| 0x18 | 2 | PnP Header Ptr | Offset to `$PnP` structure (little-endian) |
| 0x1A | 2 | PCI Header Ptr | `0x0000` (not PCI) |

**Checksum Requirement:** All bytes in the ROM must sum to `0x00` (mod 256).

### BIOS Scan Process

During POST, the BIOS:

1. Scans memory at **2KB boundaries** from `C0000h` to `EFFFFh`
2. Looks for `55 AA` signature
3. Reads size byte, validates checksum
4. Executes `FAR CALL` to offset `0x03`
5. Init routine hooks interrupts, returns via `RETF`

### Memory Address Options

| Address | Size | Notes |
|---------|------|-------|
| `C8000h` | 16KB | **Recommended** — Standard HDD controller location |
| `CA000h` | 16KB | Alternative if C8000 conflicts |
| `CC000h` | 16KB | Alternative |
| `D0000h` | 16KB | Alternative (UMB region) |

FluxRipper will default to **C8000h** with jumper/software selection for alternatives.

---

## FluxRipper ROM Architecture

### ROM Contents

```
┌──────────────────────────────────────────────────────────────┐
│ 0x0000  55 AA 20  JMP init_entry                             │  ← Header (512 bytes)
│ 0x0003  EA xx xx xx xx  (FAR JMP to init)                    │
│ 0x0018  xx xx  (PnP header pointer)                          │
│ ...                                                          │
│ 0x01FF  xx  (checksum byte)                                  │
├──────────────────────────────────────────────────────────────┤
│ 0x0200  "$PnP" header (if PnP enabled)                       │  ← PnP Header
│ ...                                                          │
├──────────────────────────────────────────────────────────────┤
│ 0x0300  Initialization Code                                  │  ← Init Routine
│         - Detect FluxRipper hardware                         │
│         - Hook INT 13h                                       │
│         - Hook INT 19h (boot)                                │
│         - Display banner                                     │
│         - RETF                                               │
├──────────────────────────────────────────────────────────────┤
│ 0x0800  INT 13h Handler                                      │  ← Interrupt Handlers
│         - AH=00: Reset                                       │
│         - AH=01: Status                                      │
│         - AH=02: Read Sectors                                │
│         - AH=03: Write Sectors                               │
│         - AH=08: Get Parameters                              │
│         - AH=15: Get Disk Type                               │
│         - AH=41-48: INT13 Extensions (LBA)                   │
├──────────────────────────────────────────────────────────────┤
│ 0x1800  Drive Parameter Tables                               │  ← DPT
│         - ST-506/MFM geometries                              │
│         - RLL geometries                                     │
│         - ESDI geometries                                    │
├──────────────────────────────────────────────────────────────┤
│ 0x2000  Setup Utility (optional)                             │  ← Setup Menu
│         - Drive configuration                                │
│         - Low-level format                                   │
│         - Diagnostics                                        │
├──────────────────────────────────────────────────────────────┤
│ 0x3F00  Strings, messages                                    │  ← Data
│ 0x3FFE  00  (pad)                                            │
│ 0x3FFF  xx  (final checksum adjustment byte)                 │
└──────────────────────────────────────────────────────────────┘
```

### ROM Size Options

| Size | Blocks | Use Case |
|------|--------|----------|
| 8KB | 0x10 | Minimal INT 13h only |
| 16KB | 0x20 | **Recommended** — Full INT 13h + basic setup |
| 32KB | 0x40 | Full setup utility + diagnostics |

---

## Hardware Implementation

### Option 1: FPGA Block RAM (Recommended)

Store ROM in FPGA fabric using Block RAM or distributed RAM.

**Advantages:**
- No additional components
- Sub-100ns access time (single ISA cycle)
- ROM contents included in bitstream
- Updateable via FPGA reconfiguration

**Resource Cost:**
- 16KB ROM = 4× RAMB36E2 (18Kb each) or 8× RAMB18E2
- XCSU35P has 1.93Mb BRAM total — 16KB uses <1%

**RTL Module:**

```verilog
module isa_option_rom #(
    parameter ROM_BASE_ADDR = 24'hC8000,  // C8000h default
    parameter ROM_SIZE_KB   = 16          // 16KB
)(
    input  wire        clk,
    input  wire        reset_n,

    // ISA Memory Bus
    input  wire [23:0] isa_addr,          // Full 24-bit address (directly from ISA Address[23:0])
    input  wire        isa_memr_n,        // Memory read strobe (directly from ISA -MEMR)
    input  wire        isa_memw_n,        // Memory write strobe (not used for ROM)
    input  wire        isa_aen,           // Address Enable (high during DMA)
    output wire [7:0]  isa_data_out,      // Data to ISA bus
    output wire        isa_data_oe,       // Output enable
    output wire        isa_iochrdy,       // Ready (directly to ISA I/O CH RDY)

    // ROM Data Input (from BRAM)
    output wire [13:0] rom_addr,          // ROM address (16KB = 14 bits)
    input  wire [7:0]  rom_data           // ROM data from BRAM
);

    // Address decode: Check if access is within ROM range
    localparam ROM_SIZE = ROM_SIZE_KB * 1024;

    wire addr_match = (isa_addr >= ROM_BASE_ADDR) &&
                      (isa_addr < (ROM_BASE_ADDR + ROM_SIZE));

    wire rom_selected = addr_match && !isa_aen && !isa_memr_n;

    // ROM address calculation
    assign rom_addr = isa_addr[13:0];  // Lower 14 bits for 16KB

    // Data output (directly from BRAM - combinatorial for speed)
    assign isa_data_out = rom_data;
    assign isa_data_oe = rom_selected;

    // Always ready (BRAM is fast enough for single-cycle access)
    assign isa_iochrdy = 1'b1;

endmodule
```

**BRAM Initialization:**

```verilog
module option_rom_bram #(
    parameter ROM_FILE = "fluxripper_rom.mem"
)(
    input  wire        clk,
    input  wire [13:0] addr,
    output reg  [7:0]  data
);

    // 16KB ROM
    reg [7:0] rom [0:16383];

    // Initialize from file
    initial begin
        $readmemh(ROM_FILE, rom);
    end

    // Synchronous read (can also be async for faster access)
    always @(posedge clk) begin
        data <= rom[addr];
    end

endmodule
```

### Option 2: External SPI Flash

Use the existing QSPI config flash (W25Q128JVSIQ) to store ROM image.

**Advantages:**
- ROM updateable without FPGA rebuild
- Large capacity (128Mb flash)
- Shares existing flash

**Disadvantages:**
- Requires wait states (SPI latency ~100-200ns)
- More complex controller
- Potential config flash conflicts

**Implementation:**
- Prefetch ROM data into small cache
- Use IOCHRDY to insert 2-3 wait states
- Store ROM at known flash offset (e.g., 0x100000)

### Option 3: Dedicated Parallel Flash

Add dedicated parallel NOR flash for ROM.

**Advantages:**
- Fast access (45-70ns)
- Field-updateable
- No FPGA resources used

**Disadvantages:**
- Additional BOM cost (~$1.50)
- Additional board space
- More signals to route

---

## ISA Bus Interface

### Memory Read Cycle Timing

```
        ┌─────────────────────────────────────────────────────┐
BCLK    │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │
        └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘
              ▲
              │ 125ns (8MHz ISA)

        ┌─────┐                                   ┌─────────────
SA[19:0]      └───────────────────────────────────┘
              │◄──── Address Valid ──────────────►│

        ──────┐                             ┌─────────────────
-MEMR         └─────────────────────────────┘
              │◄───── ~250ns typical ──────►│

              │◄─ 91ns ─►│                  │◄ 11ns ►│
              │  setup   │                  │  hold  │
                         │◄─ Data Valid ───►│
        ────────────────┐                   ┌─────────────────
D[7:0]                  └───────────────────┘
```

**Critical Timing:**
- Address setup to MEMR: 91ns minimum
- Data valid from MEMR: ~200ns typical
- FPGA BRAM can respond in <50ns — plenty of margin

### Address Decoding

The ISA bus provides 24 address lines for memory access:

| Signal | Pins | Description |
|--------|------|-------------|
| SA[19:0] | 20 | System Address (directly from CPU) |
| LA[23:17] | 7 | Latched Address (directly from CPU) |

For Option ROM decode at C8000h:
- LA[23:17] = `0b0000110` (C0000-DFFFF range)
- SA[16:14] = `0b010` (C8000-CBFFF within that range)
- SA[13:0] = ROM offset

```verilog
// Address decode for C8000-CBFFF (16KB)
wire rom_cs = (la[23:17] == 7'b0000110) &&  // C0000-DFFFF
              (sa[16:14] == 3'b010) &&       // C8000-CBFFF
              !isa_aen;                       // Not DMA cycle
```

---

## ROM Software Components

### 1. Initialization Routine

```asm
;==============================================================================
; FluxRipper Option ROM - Initialization
;==============================================================================
; Called by BIOS during POST via FAR CALL to offset 0003h
;==============================================================================

ROM_SEG     equ     0C800h          ; ROM segment (C8000h >> 4)
IO_BASE     equ     01F0h           ; WD controller I/O base

            org     0000h

;------------------------------------------------------------------------------
; ROM Header
;------------------------------------------------------------------------------
rom_header:
            db      055h, 0AAh      ; Signature
            db      020h            ; Size: 32 * 512 = 16KB
            jmp     far ptr init_entry

            times   018h - ($ - rom_header) db 0
            dw      pnp_header      ; Pointer to $PnP header
            dw      0               ; No PCI header

;------------------------------------------------------------------------------
; Initialization Entry Point
;------------------------------------------------------------------------------
init_entry:
            pushf
            push    ax
            push    bx
            push    cx
            push    dx
            push    si
            push    di
            push    ds
            push    es

            ; Set up data segment
            push    cs
            pop     ds

            ; Display banner
            mov     si, offset banner_msg
            call    print_string

            ; Detect FluxRipper hardware
            call    detect_hardware
            jc      init_no_hw

            ; Hook INT 13h
            call    hook_int13

            ; Hook INT 19h for boot
            call    hook_int19

            ; Display ready message
            mov     si, offset ready_msg
            call    print_string
            jmp     init_done

init_no_hw:
            mov     si, offset nohw_msg
            call    print_string

init_done:
            pop     es
            pop     ds
            pop     di
            pop     si
            pop     dx
            pop     cx
            pop     bx
            pop     ax
            popf
            retf                    ; Return to BIOS

;------------------------------------------------------------------------------
; Hardware Detection
;------------------------------------------------------------------------------
detect_hardware:
            ; Read WD status register
            mov     dx, IO_BASE + 7     ; Status register
            in      al, dx

            ; Check for valid response (not FFh)
            cmp     al, 0FFh
            je      detect_fail

            ; Additional signature check
            mov     dx, IO_BASE + 1     ; Error/Features register
            mov     al, 055h
            out     dx, al
            in      al, dx
            cmp     al, 055h
            jne     detect_fail

            clc                         ; Success
            ret

detect_fail:
            stc                         ; Failure
            ret

;------------------------------------------------------------------------------
; Strings
;------------------------------------------------------------------------------
banner_msg  db      0Dh, 0Ah
            db      'FluxRipper BIOS v1.0', 0Dh, 0Ah
            db      '(C) 2025 FluxRipper Project', 0Dh, 0Ah, 0

ready_msg   db      'FluxRipper: Drive 80h ready', 0Dh, 0Ah, 0

nohw_msg    db      'FluxRipper: Hardware not detected', 0Dh, 0Ah, 0
```

### 2. INT 13h Handler

The INT 13h handler provides BIOS disk services:

| AH | Function | FluxRipper Support |
|----|----------|-------------------|
| 00h | Reset Disk | Yes |
| 01h | Get Status | Yes |
| 02h | Read Sectors | Yes |
| 03h | Write Sectors | Yes |
| 04h | Verify Sectors | Yes |
| 05h | Format Track | Yes |
| 08h | Get Drive Parameters | Yes |
| 09h | Init Drive Parameters | Yes |
| 0Ch | Seek | Yes |
| 0Dh | Reset Hard Disk | Yes |
| 10h | Test Drive Ready | Yes |
| 15h | Get Disk Type | Yes |
| 41h-48h | INT13 Extensions (LBA) | Optional |

### 3. Drive Parameter Table (DPT)

Support for common vintage drive geometries:

```asm
;------------------------------------------------------------------------------
; Drive Parameter Table Entries
;------------------------------------------------------------------------------
; Format: Cylinders(W), Heads(B), Sectors(B), WPC(W), LZ(W), Control(B)

dpt_st225:                          ; Seagate ST-225 (20MB MFM)
            dw      615             ; Cylinders
            db      4               ; Heads
            db      17              ; Sectors/track
            dw      615             ; Write precomp cylinder
            dw      615             ; Landing zone
            db      0               ; Control byte

dpt_st251:                          ; Seagate ST-251 (40MB RLL)
            dw      820
            db      6
            db      26              ; RLL: 26 sectors
            dw      820
            dw      820
            db      0

dpt_st4096:                         ; Seagate ST-4096 (80MB ESDI)
            dw      1024
            db      9
            db      36              ; ESDI: 36 sectors
            dw      1024
            dw      1024
            db      8               ; ESDI control
```

---

## Integration with Existing ISA Infrastructure

### Current ISA Modules

FluxRipper already has these ISA modules:

| Module | Function | Integration Point |
|--------|----------|-------------------|
| `isa_bus_bridge.v` | I/O port decode (0x1Fx, 0x3Fx) | Add ROM memory decode |
| `isa_addr_decode.v` | Address comparators | Extend for ROM range |
| `isa_pnp_controller.v` | ISA Plug-and-Play | ROM contains PnP header |
| `isa_pnp_rom.v` | PnP resource descriptors | Integrate with Option ROM |

### Required Changes

1. **Add `isa_option_rom.v`** — New module for ROM decode and data
2. **Extend `isa_bus_bridge.v`** — Add memory bus signals (MEMR, LA[23:17])
3. **Update top-level** — Instantiate ROM module, connect BRAM

### Top-Level Integration

```verilog
// In fluxripper_dual_top.v or similar

// Option ROM BRAM
wire [13:0] rom_addr;
wire [7:0]  rom_data;

option_rom_bram #(
    .ROM_FILE("fluxripper_rom.mem")
) u_rom_bram (
    .clk(clk_sys),
    .addr(rom_addr),
    .data(rom_data)
);

// Option ROM ISA interface
isa_option_rom #(
    .ROM_BASE_ADDR(24'hC8000),
    .ROM_SIZE_KB(16)
) u_option_rom (
    .clk(clk_sys),
    .reset_n(reset_n),
    .isa_addr(isa_addr_full),       // Need full 24-bit address
    .isa_memr_n(isa_memr_n),
    .isa_memw_n(isa_memw_n),
    .isa_aen(isa_aen),
    .isa_data_out(rom_data_out),
    .isa_data_oe(rom_data_oe),
    .isa_iochrdy(rom_iochrdy),
    .rom_addr(rom_addr),
    .rom_data(rom_data)
);

// Merge ROM data with existing ISA data bus
assign isa_data = rom_data_oe ? rom_data_out :
                  io_data_oe  ? io_data_out  : 8'hFF;
```

---

## ISA Edge Connector Signals

Additional signals needed for ROM support:

| Pin | Signal | Direction | Purpose |
|-----|--------|-----------|---------|
| A31 | -MEMR | Input | Memory Read strobe |
| A11 | -MEMW | Input | Memory Write strobe |
| A1-A19 | SA[19:1] | Input | System Address |
| B1-B4 | LA[23:20] | Input | Latched Address (directly from CPU) |
| B5-B7 | LA[19:17] | Input | Latched Address (directly from CPU) |
| B8 | -REFRESH | Input | Refresh cycle (ignore ROM) |
| B10 | I/O CH RDY | Output | Ready signal |

Note: The existing `isa_bus_bridge.v` only handles I/O ports (IOR, IOW). Memory signals must be added.

---

## Build Process

### ROM Image Creation

1. **Assemble source:**
   ```bash
   nasm -f bin -o fluxripper.rom rom_source.asm
   ```

2. **Calculate checksum:**
   ```python
   def fix_checksum(rom_data):
       # Sum all bytes except last
       total = sum(rom_data[:-1]) & 0xFF
       # Set last byte to make sum = 0
       rom_data[-1] = (256 - total) & 0xFF
       return rom_data
   ```

3. **Convert to Verilog mem file:**
   ```bash
   xxd -i fluxripper.rom | sed 's/0x//' > fluxripper_rom.mem
   ```

4. **Or use $readmemh format:**
   ```
   55 AA 20 EA 00 03 00 C8 ...
   ```

### Verification

```bash
# Verify signature
hexdump -C fluxripper.rom | head -1
# Should show: 00000000  55 aa 20 ...

# Verify checksum
python3 -c "print(sum(open('fluxripper.rom','rb').read()) % 256)"
# Should print: 0
```

---

## Testing

### Simulation

1. Create testbench with ISA memory read cycles
2. Verify ROM data output for various addresses
3. Check timing meets ISA specifications
4. Verify address decode boundaries

### Hardware Testing

1. **POST Detection:**
   - ROM should appear during BIOS memory scan
   - Banner message should display

2. **INT 13h Functions:**
   - Use DEBUG.EXE to test interrupt handlers
   - Verify read/write operations

3. **Boot Test:**
   - Create bootable image on FluxRipper-attached drive
   - Verify system boots from FluxRipper

---

## BOM Impact

Using FPGA BRAM for ROM adds no BOM cost. If external flash is preferred:

| Component | Part | Cost |
|-----------|------|------|
| Parallel Flash | SST39SF010A | ~$1.50 |
| Decoupling | 100nF 0402 | ~$0.01 |

**Recommendation:** Use FPGA BRAM — no additional cost, simplest integration.

---

## References

- [Option ROM - Wikipedia](https://en.wikipedia.org/wiki/Option_ROM)
- [BIOS Boot Specification](https://www.scs.stanford.edu/nyu/04fa/lab/specsbbs101.pdf)
- [ISA Bus Technical Reference](http://wearcam.org/ece385/lecture6/isa.htm)
- [Lo-tech ISA ROM Board](https://www.lo-tech.co.uk/wiki/Lo-tech_ISA_ROM_Board)
- [WD1003/WD1004 Technical Manual](https://www.minuszerodegrees.net/manuals/Western%20Digital/)
- [INT 13h Reference](https://stanislavs.org/helppc/int_13.html)

---

## Revision History

| Date | Changes |
|------|---------|
| 2025-12-07 | Initial Option ROM design specification |
