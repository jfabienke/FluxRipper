# FluxRipper HDD BIOS Design

**Date:** 2025-12-07
**Status:** Design Specification
**Inspired by:** XTIDE Universal BIOS, IBM AT BIOS
**License:** GPL v3 (for compatibility with Multi-Floppy BIOS)

---

## Overview

The FluxRipper HDD BIOS is an Option ROM providing INT 13h services for ST-506 (MFM/RLL) and ESDI hard drives connected via the FluxRipper hardware. Unlike XTIDE (which targets IDE/CF), this BIOS directly controls the WD1002/1003/1006/1007-compatible register interface emulated by the FluxRipper FPGA.

### Key Design Principles

1. **Leverage Hardware Auto-Detection** — Geometry, encoding, and interface type are auto-detected by FPGA
2. **Universal Compatibility** — Works in both 8-bit XT and 16-bit AT slots
3. **Modern Architecture** — Modular design inspired by XTIDE Universal BIOS
4. **IBM AT Compatible** — Register sequences match original IBM AT BIOS for maximum compatibility
5. **Minimal Footprint** — Target 8KB ROM (fits 28C64 EEPROM) with optional 16KB extended build

---

## Feature Summary

### Core Features (8KB Build)

| Feature | Description |
|---------|-------------|
| **Auto-Detection Integration** | Reads geometry from FluxRipper discovery registers |
| **All WD Personalities** | WD1002 (XT MFM), WD1003 (AT MFM), WD1006 (AT RLL), WD1007 (AT ESDI) |
| **8-bit/16-bit Mode** | Automatic adaptation based on ISA slot width |
| **INT 13h (Standard)** | Functions 00h-11h, 15h (original PC AT set) |
| **CHS Addressing** | Full CHS support up to 1024/255/63 (8.4GB) |
| **Two Drive Support** | Drive 80h and 81h (primary and secondary) |
| **DPT Integration** | Proper Drive Parameter Table in low memory |
| **Error Recovery** | Automatic retry with recalibrate on errors |

### Extended Features (16KB Build)

| Feature | Description |
|---------|-------------|
| **INT 13h Extensions** | AH=41h-48h (LBA, extended read/write, get params) |
| **Boot Menu** | F12 hotkey for drive selection |
| **Setup Utility** | Configuration menu during POST (F2 key) |
| **Real-Time Monitor** | F3 hotkey for live drive/signal statistics |
| **Drive Diagnostics** | Surface scan, seek test, spindle test, head test |
| **Signal Analysis** | Flux timing histogram, quality metrics, PLL status |
| **Error Logging** | Lifetime error counters, per-track error mapping |
| **ESDI Query** | GET_DEV_CONFIG dump for ESDI drives |
| **Geometry Override** | Manual CHS entry for non-standard drives |
| **Report Export** | Save diagnostics to floppy or serial port |
| **Serial Console** | Debug output to COM port (optional) |

---

## Hardware Integration

### FluxRipper Discovery Registers

The BIOS reads auto-detected parameters from FPGA registers rather than probing the drive itself:

```
FluxRipper HDD Register Block (Base + 0x80):
┌─────────┬────────┬──────────────────────────────────────────────┐
│ Offset  │ R/W    │ Description                                  │
├─────────┼────────┼──────────────────────────────────────────────┤
│ 0x80    │ R/W    │ Discovery Control (bit 0=start, bit 1=abort) │
│ 0x84    │ R      │ Discovery Status (stage, progress)           │
│ 0x88    │ R      │ PHY Result (differential flag)               │
│ 0x8C    │ R      │ Rate Result (data rate code)                 │
│ 0x90    │ R      │ Encoding Result (MFM/RLL/ESDI) + flags       │
│ 0x94    │ R      │ Geometry A: [31:16]=cylinders, [3:0]=heads   │
│ 0x98    │ R      │ Geometry B: [23:16]=skew, [15:8]=interleave, │
│         │        │             [7:0]=sectors per track          │
│ 0x9C    │ R      │ Quality Score (0-255)                        │
│ 0xA0    │ R      │ Profile Low (packed geometry, 32 bits)       │
│ 0xA4    │ R      │ Profile High (packed geometry, 32 bits)      │
└─────────┴────────┴──────────────────────────────────────────────┘
```

### Personality-Specific Behavior

The BIOS adapts its behavior based on the detected WD personality:

| Personality | Slot | Data Rate | Sector Size | Max CHS |
|-------------|------|-----------|-------------|---------|
| WD1002-WX1 | 8-bit XT | 5 Mbps | 512 | 1024/8/17 |
| WD1003-WAH | 16-bit AT | 5 Mbps | 512 | 1024/16/17 |
| WD1006-WAH | 16-bit AT | 7.5 Mbps | 512 | 1024/16/26 |
| WD1007-WAH | 16-bit AT | 10-15 Mbps | 512 | 1024/16/36+ |

### I/O Port Mapping

```
8-bit XT Mode (WD1002):
  Primary:   320h-327h (XT standard)
  No secondary support

16-bit AT Mode (WD1003/1006/1007):
  Primary:   1F0h-1F7h, 3F6h-3F7h (AT standard)
  Secondary: 170h-177h, 376h-377h (optional)
```

---

## INT 13h Function Support

### Standard Functions (8KB Build)

| AH | Function | Implementation Notes |
|----|----------|---------------------|
| 00h | Reset Disk System | Issue RECALIBRATE command |
| 01h | Get Disk Status | Return last error code |
| 02h | Read Sectors | CHS read via WD task file |
| 03h | Write Sectors | CHS write via WD task file |
| 04h | Verify Sectors | Read without data transfer |
| 05h | Format Track | WD FORMAT TRACK command |
| 08h | Get Drive Parameters | Return discovered geometry |
| 09h | Initialize DPT | Copy DPT to 41h/46h vectors |
| 0Ah | Read Long | Read with ECC bytes |
| 0Bh | Write Long | Write with ECC bytes |
| 0Ch | Seek | Seek to cylinder |
| 0Dh | Alternate Disk Reset | Same as 00h |
| 10h | Test Drive Ready | Check status register |
| 11h | Recalibrate | Issue RECALIBRATE command |
| 15h | Get Disk Type | Return drive type and size |

### Extended Functions (16KB Build)

| AH | Function | Implementation Notes |
|----|----------|---------------------|
| 41h | Check Extensions Present | Return version 1.x |
| 42h | Extended Read | LBA-based read |
| 43h | Extended Write | LBA-based write |
| 44h | Extended Verify | LBA-based verify |
| 47h | Extended Seek | LBA-based seek |
| 48h | Get Extended Parameters | Return enhanced DPT |

---

## Memory Layout

### 8KB ROM Layout

```
┌──────────────────────────────────────────────────────────────┐
│ 0x0000  ROM Header (55 AA 10 JMP init)                       │
│ 0x0003  Entry Point Jump                                     │
│ 0x0018  PnP Header Pointer                                   │
├──────────────────────────────────────────────────────────────┤
│ 0x0040  $PnP Header (if ISA PnP enabled)                     │
├──────────────────────────────────────────────────────────────┤
│ 0x0100  Initialization Code                                  │
│         - Detect FluxRipper hardware                         │
│         - Read discovered geometry                           │
│         - Set up DPT in low memory                           │
│         - Hook INT 13h                                       │
│         - Display banner                                     │
├──────────────────────────────────────────────────────────────┤
│ 0x0400  INT 13h Dispatcher                                   │
│         - Function routing table                             │
│         - Parameter validation                               │
├──────────────────────────────────────────────────────────────┤
│ 0x0500  INT 13h Function Handlers                            │
│         - Reset (00h, 0Dh)                                   │
│         - Status (01h)                                       │
│         - Read/Write (02h, 03h)                              │
│         - Verify (04h)                                       │
│         - Format (05h)                                       │
│         - Get Params (08h)                                   │
│         - Seek/Recal (0Ch, 11h)                              │
│         - etc.                                               │
├──────────────────────────────────────────────────────────────┤
│ 0x1400  WD Controller Interface                              │
│         - Command issue routines                             │
│         - Status polling                                     │
│         - Data transfer (8-bit and 16-bit)                   │
│         - Error handling                                     │
├──────────────────────────────────────────────────────────────┤
│ 0x1900  Drive Parameter Tables                               │
│         - Default geometries for common drives               │
│         - Auto-detected geometry storage                     │
├──────────────────────────────────────────────────────────────┤
│ 0x1E00  Strings and Messages                                 │
├──────────────────────────────────────────────────────────────┤
│ 0x1FFE  Padding                                              │
│ 0x1FFF  Checksum byte                                        │
└──────────────────────────────────────────────────────────────┘
```

### 16KB ROM Layout (Extended)

Additional sections in extended build:

```
┌──────────────────────────────────────────────────────────────┐
│ 0x2000  INT 13h Extensions (41h-48h)                         │
├──────────────────────────────────────────────────────────────┤
│ 0x2800  Boot Menu Module                                     │
│         - F12 key detection during POST                      │
│         - Drive list display                                 │
│         - Boot selection handler                             │
├──────────────────────────────────────────────────────────────┤
│ 0x3000  Setup Utility Module                                 │
│         - F2 key detection during POST                       │
│         - Menu system                                        │
│         - Geometry editor                                    │
│         - Diagnostics                                        │
├──────────────────────────────────────────────────────────────┤
│ 0x3C00  Extended DPT and strings                             │
├──────────────────────────────────────────────────────────────┤
│ 0x3FFE  Padding                                              │
│ 0x3FFF  Checksum byte                                        │
└──────────────────────────────────────────────────────────────┘
```

---

## Initialization Sequence

### POST Initialization Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    BIOS CALLS ROM INIT                      │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. Detect FluxRipper Hardware                               │
│    - Check for signature at WD base port                    │
│    - Read FluxRipper ID register                            │
│    - Determine 8-bit or 16-bit mode                         │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Wait for Discovery Complete                              │
│    - Poll discovery status register                         │
│    - Timeout after 5 seconds                                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Read Discovered Geometry                                 │
│    - Cylinders, heads, sectors per track                    │
│    - Encoding type (MFM/RLL/ESDI)                           │
│    - Data rate and interface type                           │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Build Drive Parameter Table                              │
│    - Allocate DPT in EBDA or top of conventional memory     │
│    - Fill in geometry parameters                            │
│    - Set INT 41h/46h vectors to point to DPT                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Hook INT 13h                                             │
│    - Save original INT 13h vector                           │
│    - Install FluxRipper INT 13h handler                     │
│    - Update BIOS Data Area drive count                      │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Display Banner (Optional Hotkey Check)                   │
│    - "FluxRipper HDD BIOS v1.0"                             │
│    - "Drive 80h: XXX MB (CHS)"                              │
│    - "Press F2 for Setup, F12 for Boot Menu"                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. RETF to BIOS                                             │
└─────────────────────────────────────────────────────────────┘
```

### Geometry Auto-Detection Integration

```asm
;==============================================================================
; Read Discovered Geometry from FluxRipper FPGA
;==============================================================================
; The FPGA auto-detection runs at power-on and discovers:
;   - Interface type (single-ended/differential)
;   - Data rate (5/7.5/10/15 Mbps)
;   - Encoding (MFM/RLL/ESDI)
;   - Geometry (cylinders, heads, sectors per track)
;   - For ESDI: Uses GET_DEV_CONFIG command if available
;
; This BIOS simply reads the results from FluxRipper registers.
;==============================================================================

read_discovered_geometry:
    push    es
    push    di

    ; Get FluxRipper discovery register base (WD_BASE + 0x80)
    mov     dx, [cs:wd_io_base]
    add     dx, 80h

    ; Check if discovery is complete
    in      al, dx                  ; REG_DISCOVER_CTRL
    test    al, 04h                 ; Bit 2 = result_valid
    jz      .no_discovery

    ; Read geometry register A (cylinders, heads)
    add     dx, 14h                 ; REG_GEOMETRY_A (0x94)
    in      ax, dx                  ; Low word
    mov     [cs:discovered_heads], al
    add     dx, 2
    in      ax, dx                  ; High word (cylinders)
    mov     [cs:discovered_cylinders], ax

    ; Read geometry register B (SPT, interleave, skew)
    mov     dx, [cs:wd_io_base]
    add     dx, 98h                 ; REG_GEOMETRY_B
    in      al, dx
    mov     [cs:discovered_spt], al

    ; Read encoding type
    mov     dx, [cs:wd_io_base]
    add     dx, 90h                 ; REG_ENCODE_RESULT
    in      al, dx
    and     al, 07h                 ; Bits 2:0 = encoding
    mov     [cs:discovered_encoding], al

    ; Check if ESDI config was used (authoritative geometry)
    test    al, 80h                 ; Bit 7 = ESDI config used
    jnz     .esdi_authoritative

    ; Standard MFM/RLL - geometry from probing
    clc
    jmp     .done

.esdi_authoritative:
    ; ESDI drives report their own geometry - most accurate
    clc
    jmp     .done

.no_discovery:
    ; Discovery not complete or failed - use defaults
    mov     word [cs:discovered_cylinders], 615
    mov     byte [cs:discovered_heads], 4
    mov     byte [cs:discovered_spt], 17
    mov     byte [cs:discovered_encoding], 1  ; MFM
    stc

.done:
    pop     di
    pop     es
    ret
```

---

## 8-bit vs 16-bit Mode

### Slot Width Detection

The FluxRipper hardware detects slot width via the C18 pin. The BIOS reads this from the auto-config status:

```asm
detect_slot_width:
    ; Read auto-config status register
    mov     dx, [cs:autoconfig_base]
    in      al, dx

    test    al, 01h             ; Bit 0 = slot_is_8bit
    jnz     .xt_mode

    ; 16-bit AT mode
    mov     byte [cs:slot_width], 16
    mov     word [cs:wd_io_base], 1F0h
    ret

.xt_mode:
    ; 8-bit XT mode
    mov     byte [cs:slot_width], 8
    mov     word [cs:wd_io_base], 320h
    ret
```

### Data Transfer Adaptation

```asm
;==============================================================================
; Sector Read - Adapts to 8-bit or 16-bit mode
;==============================================================================
read_sector_data:
    ; ES:BX = destination buffer
    ; CX = word count (256 for 512-byte sector)

    mov     dx, [cs:wd_io_base]     ; Data register

    cmp     byte [cs:slot_width], 16
    je      .read_16bit

.read_8bit:
    ; 8-bit XT mode - byte-by-byte transfer
    shl     cx, 1                   ; Convert words to bytes
.read_8bit_loop:
    in      al, dx
    stosb
    loop    .read_8bit_loop
    ret

.read_16bit:
    ; 16-bit AT mode - word transfer
    rep     insw
    ret
```

---

## Error Handling

### Error Codes (AH Return Values)

| Code | Description | Recovery Action |
|------|-------------|-----------------|
| 00h | No error | None |
| 01h | Invalid command | None (software error) |
| 02h | Address mark not found | Retry with recalibrate |
| 04h | Sector not found | Retry with recalibrate |
| 05h | Reset failed | Report to user |
| 07h | Drive not initialized | Call init routine |
| 09h | DMA boundary error | Adjust buffer |
| 0Ah | Bad sector flag | Skip or retry |
| 0Bh | Bad track flag | Use alternate track |
| 10h | ECC error (corrected) | Data OK, warn user |
| 11h | ECC error (uncorrectable) | Retry or fail |
| 20h | Controller failure | Report to user |
| 40h | Seek failure | Recalibrate and retry |
| 80h | Timeout | Reset and retry |
| AAh | Drive not ready | Wait and retry |
| BBh | Undefined error | Report to user |
| CCh | Write fault | Check write protect |
| E0h | Status error | Reset controller |
| FFh | Sense operation failed | Report to user |

### Automatic Retry Logic

```asm
;==============================================================================
; Execute Command with Retry
;==============================================================================
; Input: Command already set up in task file registers
; Output: CF=0 success, CF=1 failure (AH=error code)
;==============================================================================
execute_with_retry:
    mov     byte [cs:retry_count], 3

.retry_loop:
    call    execute_command
    jnc     .success

    ; Check if retryable error
    cmp     ah, 02h             ; Address mark not found
    je      .do_retry
    cmp     ah, 04h             ; Sector not found
    je      .do_retry
    cmp     ah, 40h             ; Seek failure
    je      .do_retry_recal
    cmp     ah, 80h             ; Timeout
    je      .do_retry_reset

    ; Non-retryable error
    stc
    ret

.do_retry_reset:
    call    reset_controller

.do_retry_recal:
    call    recalibrate_drive

.do_retry:
    dec     byte [cs:retry_count]
    jnz     .retry_loop

    ; All retries exhausted
    stc
    ret

.success:
    clc
    ret
```

---

## Boot Menu (Extended Build)

### Hotkey Detection

During the banner display, the BIOS monitors for F12:

```asm
check_boot_hotkey:
    ; Set short timeout for key check
    mov     cx, 18              ; ~1 second (18.2 ticks)

.check_loop:
    mov     ah, 01h
    int     16h                 ; Check keyboard buffer
    jz      .no_key

    mov     ah, 00h
    int     16h                 ; Get key
    cmp     ax, 8600h           ; F12 scan code
    je      .boot_menu

.no_key:
    ; Wait one tick
    push    cx
    mov     ah, 86h
    mov     cx, 0
    mov     dx, 54925           ; ~55ms
    int     15h
    pop     cx
    loop    .check_loop
    ret

.boot_menu:
    call    display_boot_menu
    ret
```

### Boot Menu Display

```
┌────────────────────────────────────────────┐
│         FluxRipper Boot Menu               │
├────────────────────────────────────────────┤
│                                            │
│  1. Floppy Drive A:                        │
│  2. Floppy Drive B:                        │
│  3. FluxRipper HDD (Drive 80h)             │
│     Seagate ST-225 20MB                    │
│     CHS: 615/4/17  MFM                     │
│  4. FluxRipper HDD (Drive 81h)             │
│     [Not detected]                         │
│                                            │
│  Enter selection (1-4): _                  │
│                                            │
│  ESC to continue normal boot               │
└────────────────────────────────────────────┘
```

---

## Setup Utility (Extended Build)

### Setup Menu Structure

```
┌──────────────────────────────────────────────────────────────┐
│                 FluxRipper HDD Setup v1.0                    │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Drive 0 Configuration                                       │
│  ─────────────────────                                       │
│    Status:     Connected (MFM, Single-ended)                 │
│    Detected:   Seagate ST-225                                │
│    Geometry:   615 cyl / 4 heads / 17 spt                    │
│    Capacity:   20 MB                                         │
│    Quality:    98%                                           │
│                                                              │
│  [Auto]  [Manual]  [Diagnostics]  [Low-Level Format]         │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  Drive 1 Configuration                                       │
│  ─────────────────────                                       │
│    Status:     Not detected                                  │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  F10=Save  ESC=Exit  ↑↓=Select  Enter=Edit                   │
└──────────────────────────────────────────────────────────────┘
```

### Manual Geometry Override

```
┌──────────────────────────────────────────────────────────────┐
│              Manual Geometry Entry - Drive 0                 │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│    Cylinders:        [615  ] (1-4096)                        │
│    Heads:            [4    ] (1-16)                          │
│    Sectors/Track:    [17   ] (1-63)                          │
│    Write Precomp:    [615  ] (0-4096)                        │
│    Landing Zone:     [615  ] (0-4096)                        │
│                                                              │
│    Calculated capacity: 20 MB                                │
│                                                              │
│  ─────────────────────────────────────────────────────────── │
│  Common Drives:                                              │
│    [1] ST-225  (20MB)   [4] ST-4096  (80MB ESDI)             │
│    [2] ST-251  (40MB)   [5] Custom                           │
│    [3] ST-4053 (44MB)                                        │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  Enter=Accept  ESC=Cancel  1-5=Quick Select                  │
└──────────────────────────────────────────────────────────────┘
```

---

## Advanced Monitoring & Diagnostics (16KB Build)

The 16KB build includes comprehensive monitoring and diagnostic features that leverage the FluxRipper FPGA's extensive instrumentation hardware. These tools provide visibility into drive health, signal quality, and system performance that was never available with original WD controllers.

### FPGA Instrumentation Register Map

The BIOS accesses these read-only instrumentation registers (base address configurable):

```
FluxRipper Instrumentation Registers:
┌──────────┬────────┬────────────────────────────────────────────────────┐
│ Offset   │ Size   │ Description                                        │
├──────────┼────────┼────────────────────────────────────────────────────┤
│ 0x000    │ 4      │ Version (0x00010000 = v1.0.0)                      │
│ 0x004    │ 4      │ Control (write to reset counters)                  │
│ 0x008    │ 4      │ Status (trace enabled, trigger fired)              │
│ 0x00C    │ 4      │ Uptime seconds                                     │
│ 0x010    │ 4      │ Uptime milliseconds                                │
├──────────┼────────┼────────────────────────────────────────────────────┤
│ 0x0C0    │ 4      │ RX FIFO high-water mark                            │
│ 0x0C4    │ 4      │ TX FIFO high-water mark                            │
│ 0x0C8    │ 4      │ Flux FIFO high-water mark                          │
│ 0x0CC    │ 4      │ Sector FIFO high-water mark                        │
│ 0x0D0    │ 4      │ FIFO overflow count                                │
├──────────┼────────┼────────────────────────────────────────────────────┤
│ 0x100    │ 4      │ Command latency minimum (clocks)                   │
│ 0x104    │ 4      │ Command latency maximum (clocks)                   │
│ 0x108    │ 4      │ Command latency average (clocks)                   │
│ 0x10C    │ 4      │ Command latency last (clocks)                      │
├──────────┼────────┼────────────────────────────────────────────────────┤
│ 0x140    │ 4      │ Signal amplitude minimum                           │
│ 0x144    │ 4      │ Signal amplitude maximum                           │
│ 0x148    │ 4      │ Signal amplitude average                           │
│ 0x14C    │ 4      │ Flux transition count                              │
│ 0x150    │ 4      │ Index pulse count                                  │
│ 0x154    │ 4      │ Weak flux count                                    │
├──────────┼────────┼────────────────────────────────────────────────────┤
│ 0x180    │ 4      │ PLL status (locked flags)                          │
│ 0x184    │ 4      │ PLL lock count (re-locks)                          │
│ 0x188    │ 4      │ Index period (clocks)                              │
│ 0x18C    │ 4      │ Index period minimum                               │
│ 0x190    │ 4      │ Index period maximum                               │
│ 0x194    │ 4      │ RPM measured (RPM × 10)                            │
├──────────┼────────┼────────────────────────────────────────────────────┤
│ 0x1C0    │ 4      │ FDD error count                                    │
│ 0x1C4    │ 4      │ HDD error count                                    │
│ 0x1C8    │ 4      │ CRC error count                                    │
│ 0x1CC    │ 4      │ Timeout error count                                │
│ 0x1D0    │ 4      │ Total error count                                  │
├──────────┼────────┼────────────────────────────────────────────────────┤
│ 0x200    │ 4      │ Histogram control (bin select)                     │
│ 0x204    │ 4      │ Histogram bin value (64 bins)                      │
└──────────┴────────┴────────────────────────────────────────────────────┘
```

### Real-Time Status Display (F3)

Press F3 during operation for live drive statistics:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    FluxRipper Real-Time Monitor                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Drive Status                    │  Signal Quality                       │
│  ─────────────────────           │  ───────────────                      │
│  RPM:      3598 (±0.2%)          │  Amplitude: 847 mV (min/avg/max)      │
│  Index:    16.67 ms period       │  Signal:    ████████████░░░░ 78%      │
│  Ready:    YES                   │  Weak bits: 142 (0.01%)               │
│  Fault:    NO                    │  PLL:       LOCKED (3 re-locks)       │
│                                  │                                       │
├──────────────────────────────────┴───────────────────────────────────────┤
│  Error Counters (since reset)         │  Performance                     │
│  ─────────────────────────────        │  ───────────                     │
│  CRC Data:     0     Seek:       0    │  Cmd latency: 45 µs avg          │
│  CRC Addr:     0     Timeout:    0    │  Seek time:   18 ms avg          │
│  Missing AM:   2     Write Fault: 0   │  Throughput:  312 KB/s           │
│  Missing DAM:  0     TOTAL:      2    │  Operations:  1,247              │
│                                       │                                  │
├───────────────────────────────────────┴──────────────────────────────────┤
│  Seek Histogram (by distance)                                            │
│  ─────────────────────────────                                           │
│  0-1:   ████████████████████████████████████████████  412  (33%)         │
│  2-10:  ██████████████████████████                    287  (23%)         │
│  11-25: ████████████████                              198  (16%)         │
│  26-50: ████████████                                  156  (12%)         │
│  51+:   ████████████                                  194  (16%)         │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Press any key to exit  │  R=Reset counters  │  Uptime: 00:15:42         │
└──────────────────────────────────────────────────────────────────────────┘
```

### Diagnostics Menu (F2 → Diagnostics)

The Setup utility includes a comprehensive diagnostics submenu:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      FluxRipper Diagnostics Menu                         │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   [1] Surface Scan           Full media verification with error mapping  │
│   [2] Read Test              Sequential read performance test            │
│   [3] Seek Test              Seek accuracy and timing measurement        │
│   [4] Signal Analysis        Flux timing histogram and quality metrics   │
│   [5] Spindle Test           RPM stability and jitter measurement        │
│   [6] Head Test              Multi-head read verification                │
│   [7] ESDI Query             ESDI drive configuration dump (ESDI only)   │
│   [8] Error Log              View lifetime error counters                │
│   [9] Flux Histogram         Detailed flux timing distribution           │
│                                                                          │
│   [R] Reset All Counters     Clear all statistics                        │
│   [E] Export Report          Save diagnostics to floppy (if available)   │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  ESC=Back  1-9=Select Test  R=Reset  E=Export                            │
└──────────────────────────────────────────────────────────────────────────┘
```

### Surface Scan (F2 → 1)

Full drive verification with per-track error mapping:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Surface Scan - Drive 0                           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Progress: [████████████████████████████████████░░░░░░░░░░] 72%          │
│  Cylinder: 443/615    Head: 2/4    Sector: 12/17                         │
│                                                                          │
│  Status: Reading cylinder 443, head 2...                                 │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Results So Far:                                                         │
│  ─────────────────                                                       │
│  Sectors tested:   60,724  /  83,640                                     │
│  Good sectors:     60,706  (99.97%)                                      │
│  Recoverable:      14      (ECC corrected)                               │
│  Bad sectors:      4       (unrecoverable)                               │
│                                                                          │
│  Bad Sector Map:                                                         │
│    Cyl 127, Head 1, Sector 5  - CRC error                                │
│    Cyl 127, Head 1, Sector 6  - CRC error                                │
│    Cyl 312, Head 0, Sector 11 - Missing address mark                     │
│    Cyl 540, Head 3, Sector 2  - CRC error                                │
│                                                                          │
│  Weak Tracks Detected:                                                   │
│    Track 127 (14 retries)                                                │
│    Track 540 (8 retries)                                                 │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  ESC=Abort  SPACE=Pause/Resume    Estimated time: 3:42 remaining         │
└──────────────────────────────────────────────────────────────────────────┘
```

### Seek Test (F2 → 3)

Measures seek accuracy and timing across all distances:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Seek Test - Drive 0                             │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Test Pattern: Random seeks (500 iterations)                             │
│  Progress: [████████████████████████████████████████████████] 100%       │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Seek Timing Results:                                                    │
│  ─────────────────────                                                   │
│  Distance     │ Count │ Min      │ Avg      │ Max      │ Errors          │
│  ─────────────┼───────┼──────────┼──────────┼──────────┼────────         │
│  Track-Track  │  127  │   3.1 ms │   3.4 ms │   4.2 ms │   0             │
│  1-10 cyl     │   89  │   5.2 ms │   6.8 ms │   9.1 ms │   0             │
│  11-50 cyl    │  142  │  12.4 ms │  15.3 ms │  21.0 ms │   0             │
│  51-200 cyl   │   98  │  18.2 ms │  24.1 ms │  32.5 ms │   0             │
│  200+ cyl     │   44  │  28.5 ms │  38.7 ms │  52.0 ms │   1             │
│  ─────────────┴───────┴──────────┴──────────┴──────────┴────────         │
│                                                                          │
│  Summary:                                                                │
│    Average seek:     18.4 ms                                             │
│    Seek reliability: 99.8% (499/500 successful)                          │
│    Recalibrates:     2                                                   │
│                                                                          │
│  Assessment: GOOD - Seek times within spec for ST-225                    │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  ENTER=Run Again  ESC=Exit  S=Save Results                               │
└──────────────────────────────────────────────────────────────────────────┘
```

### Flux Histogram (F2 → 9)

Detailed flux timing analysis from FPGA hardware:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     Flux Timing Histogram - Drive 0                      │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Data Rate: MFM 5 Mbps    Bit Cell: 200 ns    Sample: Track 0, Head 0    │
│                                                                          │
│  Expected Peaks: 1T=200ns (4µs), 1.5T=300ns (6µs), 2T=400ns (8µs)        │
│                                                                          │
│      2µs   3µs   4µs   5µs   6µs   7µs   8µs   9µs  10µs                 │
│       │     │     │     │     │     │     │     │     │                  │
│  100% ┤                                                                  │
│       │           ██                                                     │
│   80% ┤           ██                                                     │
│       │           ██         ██                                          │
│   60% ┤           ██         ██         ██                               │
│       │           ██         ██         ██                               │
│   40% ┤           ██         ██         ██                               │
│       │           ██         ██         ██                               │
│   20% ┤          ████       ████       ████                              │
│       │         ██████     ██████     ██████                             │
│    0% ┼─────────██████─────██████─────██████───────────────              │
│       │     │     │     │     │     │     │     │     │                  │
│                                                                          │
│  Peak Analysis:                                                          │
│    1T (200ns): 42,847 samples, σ=12ns  - GOOD                            │
│    1.5T (300ns): 31,204 samples, σ=18ns  - GOOD                          │
│    2T (400ns): 25,122 samples, σ=15ns  - GOOD                            │
│                                                                          │
│  Quality Assessment: EXCELLENT                                           │
│    Peak separation: Clean                                                │
│    Jitter: Low (σ < 20ns)                                                │
│    Anomalies: None detected                                              │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  ←→=Select Track  ↑↓=Select Head  R=Rescan  ESC=Exit                     │
└──────────────────────────────────────────────────────────────────────────┘
```

### Error Log (F2 → 8)

Lifetime error counters from FPGA hardware:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       Lifetime Error Log - Drive 0                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Uptime: 15 hours, 42 minutes      Operations: 847,291                   │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Error Type              │ Count      │ Rate (per 1000) │ Last Occurred  │
│  ────────────────────────┼────────────┼─────────────────┼─────────────── │
│  CRC Data                │         47 │           0.055 │ 00:12:31 ago   │
│  CRC Address             │          3 │           0.004 │ 02:45:18 ago   │
│  Missing Address Mark    │         12 │           0.014 │ 00:05:47 ago   │
│  Missing Data Mark       │          8 │           0.009 │ 01:22:05 ago   │
│  Data Overrun            │          0 │           0.000 │ Never          │
│  Data Underrun           │          0 │           0.000 │ Never          │
│  Seek Error              │          2 │           0.002 │ 08:15:33 ago   │
│  Write Fault             │          0 │           0.000 │ Never          │ 
│  PLL Unlock              │         14 │           0.017 │ 00:00:42 ago   │
│  ────────────────────────┼────────────┼─────────────────┼─────────────── │
│  TOTAL                   │         86 │           0.101 │                │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Per-Track Error Summary (Top 5 worst tracks):                           │
│    Track 127:  23 errors    Track 312:  8 errors                         │
│    Track 540:  12 errors    Track 089:  4 errors                         │
│    Track 441:   7 errors                                                 │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Assessment: FAIR - Error rate slightly elevated                         │
│              Recommend monitoring track 127 (potential weak media)       │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  R=Reset Counters  E=Export  ESC=Exit                                    │
└──────────────────────────────────────────────────────────────────────────┘
```

### Spindle Test (F2 → 5)

RPM stability measurement using index pulse timing:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        Spindle Test - Drive 0                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Collecting 100 rotation samples...                                      │
│  Progress: [████████████████████████████████████████████████] 100%       │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  Results:                                                                │
│  ────────                                                                │
│  Nominal RPM:    3600                                                    │
│  Measured RPM:   3598.4                                                  │
│  Deviation:      -0.04%                                                  │
│                                                                          │
│  Period Statistics:                                                      │
│    Minimum:      16.658 ms  (3603.2 RPM)                                 │
│    Maximum:      16.694 ms  (3595.4 RPM)                                 │
│    Average:      16.674 ms  (3598.4 RPM)                                 │
│    Std Dev:      0.008 ms   (±0.05%)                                     │
│                                                                          │
│  Jitter Graph (last 50 rotations):                                       │
│   +0.1% ┤      ·    ·                    ·     ·                         │
│    0.0% ┤──·─·───·───·──·─·──·─·─·─·─·─────·─·───·─·─·─·─·─·             │
│   -0.1% ┤    ·        ·       ·     ·           ·                        │
│                                                                          │
│  Assessment: EXCELLENT                                                   │
│    Spindle speed is stable and within ±0.5% specification                │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  ENTER=Run Again  ESC=Exit                                               │
└──────────────────────────────────────────────────────────────────────────┘
```

### ESDI Query (F2 → 7)

For ESDI drives, queries drive configuration:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       ESDI Configuration - Drive 0                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  GET_DEV_CONFIG Response:                                                │
│  ─────────────────────────                                               │
│  Manufacturer:     Maxtor                                                │
│  Model:            XT-4170E                                              │
│  Firmware:         Rev 2.3                                               │
│                                                                          │
│  Physical Geometry:                                                      │
│    Cylinders:      1224                                                  │
│    Heads:          7                                                     │
│    Sectors/Track:  36                                                    │
│    Bytes/Sector:   512                                                   │
│    Capacity:       157 MB                                                │
│                                                                          │
│  Interface:                                                              │
│    Data Rate:      15 Mbps                                               │
│    Encoding:       RLL 2,7                                               │
│    Sector Format:  Soft-sectored                                         │
│                                                                          │
│  Drive Options:                                                          │
│    Write Precomp:  Cylinder 0 (not needed for ESDI)                      │
│    Landing Zone:   Cylinder 1223                                         │
│    Step Rate:      3 ms (buffered seeks)                                 │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  ESC=Exit                                                                │
└──────────────────────────────────────────────────────────────────────────┘
```

### INT 18h Diagnostic Hook (Optional)

The BIOS can optionally hook INT 18h (ROM BASIC / boot failure) to provide emergency diagnostics when the system can't boot:

```asm
;==============================================================================
; INT 18h Emergency Diagnostics
; Called when boot fails - provides last-resort drive diagnostics
;==============================================================================
int18h_handler:
    ; Display emergency diagnostics banner
    call    clear_screen
    mov     si, msg_emergency
    call    print_string

    ; Read and display last error from FPGA
    call    read_fpga_error_log
    call    display_error_summary

    ; Offer limited diagnostics
    mov     si, msg_emergency_menu
    call    print_string

.wait_key:
    xor     ax, ax
    int     16h

    cmp     al, '1'
    je      .run_seek_test
    cmp     al, '2'
    je      .run_spindle_test
    cmp     al, '3'
    je      .chain_original
    jmp     .wait_key

; ... diagnostic routines ...
```

### Export Report Feature

Diagnostics can be exported to floppy disk (if available) or displayed for manual recording:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       Export Diagnostic Report                           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Export destination:                                                     │
│    [1] Floppy Drive A: (360K/720K/1.2M/1.44M)                            │
│    [2] Display on screen (copy manually)                                 │
│    [3] Serial port COM1 (9600 8N1)                                       │
│                                                                          │
│  Report includes:                                                        │
│    ✓ Drive identification and geometry                                   │
│    ✓ Lifetime error counters                                             │
│    ✓ Seek histogram                                                      │
│    ✓ Flux timing histogram (64 bins)                                     │
│    ✓ Per-track error map                                                 │
│    ✓ RPM stability data                                                  │
│    ✓ Signal quality metrics                                              │
│                                                                          │
│  Estimated size: ~8 KB                                                   │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│  1-3=Select  ESC=Cancel                                                  │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Build Configuration

### Assembly-Time Options

```asm
;==============================================================================
; Build Configuration
;==============================================================================

; ROM size: 8 or 16 KB
%define ROM_SIZE_KB         8

; Base I/O address (set by FluxRipper auto-config)
%define DEFAULT_XT_BASE     320h
%define DEFAULT_AT_BASE     1F0h

; ROM base address options
%define ROM_BASE_C8000      0
%define ROM_BASE_CC000      1
%define ROM_BASE_D0000      2

; Feature enables
%define ENABLE_DRIVE_1      1       ; Support second drive (81h)
%define ENABLE_BOOT_MENU    0       ; Boot menu (16KB only)
%define ENABLE_SETUP        0       ; Setup utility (16KB only)
%define ENABLE_DIAGNOSTICS  0       ; Diagnostic routines (16KB only)
%define ENABLE_INT13_EXT    0       ; INT 13h extensions (16KB only)
%define ENABLE_SERIAL_DEBUG 0       ; Serial port debug output

; Advanced monitoring (16KB only)
%define ENABLE_REALTIME_MON 0       ; F3 real-time monitor
%define ENABLE_FLUX_HIST    0       ; Flux timing histogram
%define ENABLE_ERROR_LOG    0       ; Lifetime error logging
%define ENABLE_SEEK_HIST    0       ; Seek distance histogram
%define ENABLE_ESDI_QUERY   0       ; ESDI GET_DEV_CONFIG
%define ENABLE_EXPORT       0       ; Export to floppy/serial
%define ENABLE_INT18_HOOK   0       ; Emergency diagnostics on boot fail

; FPGA instrumentation base address (set by hardware)
%define INSTR_BASE          0x300   ; Instrumentation register base

; Display options
%define SHOW_BANNER         1       ; Show banner during POST
%define BANNER_DELAY_TICKS  18      ; ~1 second delay

; Error handling
%define MAX_RETRIES         3       ; Retries before failure
%define ENABLE_ECC          1       ; Use ECC if available

; Debug options
%define DEBUG_VERBOSE       0       ; Extra debug output
```

### Build Targets

```makefile
# 8KB minimal build (fits 28C64)
rom-8k:
    nasm -DROM_SIZE_KB=8 -o fluxripper_hdd_8k.rom hdd_bios.asm
    python3 fix_checksum.py fluxripper_hdd_8k.rom

# 16KB standard build (fits 27C128)
rom-16k:
    nasm -DROM_SIZE_KB=16 -DENABLE_BOOT_MENU=1 -DENABLE_SETUP=1 \
         -DENABLE_INT13_EXT=1 -o fluxripper_hdd_16k.rom hdd_bios.asm
    python3 fix_checksum.py fluxripper_hdd_16k.rom

# 16KB full build with all monitoring features
rom-16k-full:
    nasm -DROM_SIZE_KB=16 \
         -DENABLE_BOOT_MENU=1 -DENABLE_SETUP=1 -DENABLE_INT13_EXT=1 \
         -DENABLE_DIAGNOSTICS=1 -DENABLE_REALTIME_MON=1 \
         -DENABLE_FLUX_HIST=1 -DENABLE_ERROR_LOG=1 -DENABLE_SEEK_HIST=1 \
         -DENABLE_ESDI_QUERY=1 -DENABLE_EXPORT=1 \
         -o fluxripper_hdd_16k_full.rom hdd_bios.asm
    python3 fix_checksum.py fluxripper_hdd_16k_full.rom

# FPGA BRAM image (Verilog $readmemh format)
rom-mem:
    nasm -DROM_SIZE_KB=8 -o fluxripper_hdd.rom hdd_bios.asm
    python3 fix_checksum.py fluxripper_hdd.rom
    python3 rom_to_mem.py fluxripper_hdd.rom fluxripper_hdd.mem

# FPGA BRAM image with full features (for testing)
rom-mem-full:
    nasm -DROM_SIZE_KB=16 \
         -DENABLE_BOOT_MENU=1 -DENABLE_SETUP=1 -DENABLE_INT13_EXT=1 \
         -DENABLE_DIAGNOSTICS=1 -DENABLE_REALTIME_MON=1 \
         -DENABLE_FLUX_HIST=1 -DENABLE_ERROR_LOG=1 \
         -o fluxripper_hdd_full.rom hdd_bios.asm
    python3 fix_checksum.py fluxripper_hdd_full.rom
    python3 rom_to_mem.py fluxripper_hdd_full.rom fluxripper_hdd_full.mem
```

---

## Testing

### Test Matrix

| Test | XT (8-bit) | AT (16-bit) | Description |
|------|------------|-------------|-------------|
| POST Detection | X | X | ROM detected and initialized |
| Banner Display | X | X | Correct info shown |
| INT 13h/00h | X | X | Reset works |
| INT 13h/02h | X | X | Read sectors |
| INT 13h/03h | X | X | Write sectors |
| INT 13h/08h | X | X | Get parameters (auto-detected) |
| Boot from drive | X | X | System boots from FluxRipper HDD |
| DOS FORMAT | X | X | DOS can format drive |
| Multiple drives | - | X | Drive 80h and 81h work |
| Boot menu | - | X | F12 works (16KB build) |
| Setup utility | - | X | F2 works (16KB build) |
| Real-time monitor | - | X | F3 shows live statistics |
| Surface scan | - | X | Full media verification |
| Seek test | - | X | Timing histogram by distance |
| Spindle test | - | X | RPM jitter measurement |
| Flux histogram | - | X | Timing distribution display |
| Error log | - | X | Lifetime counters display |
| ESDI query | - | X | GET_DEV_CONFIG works (ESDI only) |
| Export report | - | X | Floppy/serial export works |

### Compatibility Testing

Target systems for validation:
- IBM PC 5150 (8088, 8-bit)
- IBM PC XT 5160 (8088, 8-bit)
- IBM PC AT 5170 (80286, 16-bit)
- Compaq Portable (8088, 8-bit)
- Tandy 1000 series
- Generic XT clones
- Generic AT clones
- 386/486 systems in legacy mode

---

## References

- [XTIDE Universal BIOS](https://www.xtideuniversalbios.org/) — Modern Option ROM architecture inspiration
- [IBM PC AT Technical Reference](https://www.minuszerodegrees.net/manuals.htm) — Original INT 13h implementation
- [Phoenix EDD Specification](https://www.phoenix.com/resources) — INT 13h extensions
- [WD1003 Technical Manual](https://www.minuszerodegrees.net/manuals/Western%20Digital/) — Controller register reference
- [INT 13h Reference](https://stanislavs.org/helppc/int_13.html) — Function documentation

---

## Revision History

| Date | Changes |
|------|---------|
| 2025-12-07 | Initial design specification |
| 2025-12-07 | Added Advanced Monitoring & Diagnostics section with FPGA instrumentation integration |
