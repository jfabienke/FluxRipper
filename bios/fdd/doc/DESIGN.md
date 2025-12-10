# FluxRipper FDD BIOS Extension - Detailed Design Document

## 1. Overview

### 1.1 Purpose

Extend Sergey Kiselev's Multi-Floppy BIOS with FluxRipper FPGA integration to provide:
- **Zero-configuration boot** via FPGA auto-detection (replaces manual F2 setup)
- **8-inch drive support** including FM (Single Density) encoding
- **ISA Plug-and-Play** compatibility for modern systems
- **Real-time diagnostics** via FPGA instrumentation (F3 menu)

### 1.2 Design Philosophy

- **Extend, don't replace**: Use Sergey's battle-tested FDC code as the base
- **Graceful fallback**: If no FluxRipper FPGA detected, behave as standard Sergey BIOS
- **Minimal footprint**: Keep 8KB build viable for XT systems
- **Full features in 16KB**: PnP, diagnostics, 8" support in larger build

### 1.3 References

- [Sergey's Multi-Floppy BIOS](https://github.com/skiselev/floppy_bios) - Base code
- [8FORMAT byAzarien](https://boginjr.com/it/sw/dev/8format/) - 8" drive reference
- Intel 82077AA Datasheet - FDC register definitions
- ISA PnP BIOS Specification 1.0a - PnP header format
- FluxRipper HDD BIOS (bios/hdd/) - Instrumentation patterns

---

## 2. Architecture

### 2.1 Build Configurations

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Build Configurations                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  8KB Build (XT-Compatible)                                                  │
│  ─────────────────────────                                                  │
│  • Sergey's core FDC code                                                   │
│  • FluxRipper auto-detection                                                │
│  • Basic drive type support (360K-2.88M)                                    │
│  • Compact boot messages                                                    │
│  • No PnP header                                                            │
│  • No F3 diagnostics                                                        │
│  • No 8" support                                                            │
│                                                                             │
│  16KB Build (AT Full-Featured)                                              │
│  ─────────────────────────────                                              │
│  • Everything in 8KB build, plus:                                           │
│  • ISA PnP header with BEV                                                  │
│  • 8" drive support (SD/DD, FM/MFM)                                         │
│  • F3 diagnostics menu                                                      │
│  • Flux histogram display                                                   │
│  • Signal quality metrics                                                   │
│  • Verbose boot messages                                                    │
│  • F2 manual override (optional)                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Memory Map

#### 8KB ROM (0x0000 - 0x1FFF)

```
Offset    Size    Description
──────────────────────────────────────────────────────────
0x0000    3       ROM header (55 AA 10)
0x0003    2       JMP to init
0x0005    27      Reserved / padding
0x0020    ~2KB    Sergey's core code (modified)
0x0820    ~1KB    FluxRipper detection routines
0x0C20    ~512    Drive type tables
0x0E20    ~256    Strings (compact)
0x0F20    ~224    Drive config data
0x1000    ~3.5KB  INT 13h handlers (Sergey's)
0x1E00    ~480    Reserved
0x1FFF    1       Checksum byte
```

#### 16KB ROM (0x0000 - 0x3FFF)

```
Offset    Size    Description
──────────────────────────────────────────────────────────
0x0000    3       ROM header (55 AA 20)
0x0003    2       JMP to init
0x0005    21      Reserved
0x001A    32      PnP header ($PnP)
0x003A    ~70     PnP strings
0x0080    ~2.5KB  Sergey's core code (modified)
0x0AC0    ~1.5KB  FluxRipper detection routines
0x1080    ~512    8" drive support
0x1280    ~512    FM encoding support
0x1480    ~1KB    Drive type tables (extended)
0x1880    ~512    Strings (verbose)
0x1A80    ~1KB    F3 diagnostics menu
0x1E80    ~1KB    Flux histogram display
0x2280    ~512    Signal quality display
0x2480    ~3KB    INT 13h handlers (Sergey's + 8")
0x3080    ~3KB    Instrumentation access
0x3C80    ~768    Reserved / config data
0x3FFF    1       Checksum byte
```

### 2.3 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FluxRipper FDD BIOS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     ROM Entry (entry.asm)                            │   │
│  │  • ROM header (55 AA)                                                │   │
│  │  • PnP header [16KB]                                                 │   │
│  │  • Init entry point                                                  │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                          │
│                                  ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                  Initialization (init.asm)                           │   │
│  │  • Detect FluxRipper FPGA                                            │   │
│  │  • Auto-detect drives OR fall back to F2 config                      │   │
│  │  • Hook INT 13h, INT 1Eh                                             │   │
│  │  • Display boot messages                                             │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                          │
│         ┌────────────────────────┼────────────────────────┐                │
│         │                        │                        │                │
│         ▼                        ▼                        ▼                │
│  ┌─────────────┐    ┌───────────────────────┐    ┌─────────────────┐      │
│  │  Detection  │    │    Sergey's Core      │    │   Diagnostics   │      │
│  │  (fr_*.asm) │    │   (floppy*.inc)       │    │   [16KB only]   │      │
│  ├─────────────┤    ├───────────────────────┤    ├─────────────────┤      │
│  │ fr_detect   │    │ INT 13h dispatcher    │    │ F3 menu         │      │
│  │ fr_profile  │    │ Read/Write/Verify     │    │ Histogram       │      │
│  │ fr_8inch    │    │ Format track          │    │ Signal quality  │      │
│  │ fr_fm       │    │ Seek/Recalibrate      │    │ Error log       │      │
│  │ fr_instr    │    │ Get parameters        │    │                 │      │
│  └──────┬──────┘    └───────────┬───────────┘    └────────┬────────┘      │
│         │                       │                         │                │
│         └───────────────────────┴─────────────────────────┘                │
│                                 │                                          │
│                                 ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      FPGA Interface                                  │   │
│  │  • FDC registers (3F0h-3F7h)                                        │   │
│  │  • Discovery registers (3F0h + 68h/74h)                             │   │
│  │  • Instrumentation registers (3F0h + C0h)                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Structures

### 3.1 Drive Configuration Table (Sergey's Format - Preserved)

```asm
;==============================================================================
; Drive Configuration Table
;==============================================================================
; 8 entries x 4 bytes = 32 bytes
; This is Sergey's format - we preserve it for compatibility
;
; Offset  Size  Description
; ──────────────────────────────────────
;   +0     1    Drive type (CMOS type code)
;   +1     1    FDC number (0=primary, 1=secondary)
;   +2     1    Physical drive number on FDC (0-3)
;   +3     1    Flags (FluxRipper extension)
;
; Flag bits (byte 3) - FluxRipper extension:
;   Bit 0: Auto-detected (1) vs manual (0)
;   Bit 1: 8" drive
;   Bit 2: FM encoding (vs MFM)
;   Bit 3: Double-step required
;   Bit 4: Write protected
;   Bit 5-7: Reserved

drive_config:
.drive0     db  type_1440, 0, 0, 0      ; Drive A:
.drive1     db  type_none, 0, 1, 0      ; Drive B:
.drive2     db  type_none, 0, 2, 0      ; Drive C:
.drive3     db  type_none, 0, 3, 0      ; Drive D:
.drive4     db  type_none, 1, 0, 0      ; Drive E: (secondary FDC)
.drive5     db  type_none, 1, 1, 0      ; Drive F:
.drive6     db  type_none, 1, 2, 0      ; Drive G:
.drive7     db  type_none, 1, 3, 0      ; Drive H:
```

### 3.2 Extended Drive Type Codes

```asm
;==============================================================================
; Drive Type Codes
;==============================================================================
; Standard types (compatible with Sergey/CMOS):
type_none       equ     00h             ; No drive installed
type_360        equ     01h             ; 5.25" 360K DD (40T, 9spt)
type_1200       equ     02h             ; 5.25" 1.2M HD (80T, 15spt)
type_720        equ     03h             ; 3.5" 720K DD (80T, 9spt)
type_1440       equ     04h             ; 3.5" 1.44M HD (80T, 18spt)
type_2880       equ     06h             ; 3.5" 2.88M ED (80T, 36spt)

; FluxRipper extended types (8" drives):
type_8_sd       equ     07h             ; 8" SD 250K FM (77T, 26spt, 128B)
type_8_dd       equ     08h             ; 8" DD 1.2M MFM (77T, 8spt, 1024B)
type_8_pc       equ     09h             ; 8" PC-compat MFM (77T, 15spt, 512B)
type_8_cpm      equ     0Ah             ; 8" CP/M MFM (77T, 26spt, 256B)

; Aliases
type_8_max      equ     0Ah             ; Highest valid type code
```

### 3.3 Drive Geometry Table

```asm
;==============================================================================
; Drive Geometry Table
;==============================================================================
; One entry per drive type, 8 bytes each
;
; Offset  Size  Description
; ──────────────────────────────────────
;   +0     2    Cylinders (tracks per side)
;   +2     1    Heads (sides)
;   +3     1    Sectors per track
;   +4     1    Sector size code (0=128, 1=256, 2=512, 3=1024)
;   +5     1    Data rate code (0=500K, 1=300K, 2=250K, 3=1M)
;   +6     1    GAP3 length (read/write)
;   +7     1    GAP3 length (format)

geometry_table:
; Type 00h: None
    dw  0, 0, 0, 0

; Type 01h: 360K (5.25" DD)
    dw  40                      ; Cylinders
    db  2                       ; Heads
    db  9                       ; Sectors/track
    db  2                       ; 512 bytes/sector
    db  RATE_250K               ; 250 Kbps
    db  2Ah                     ; GAP3 R/W
    db  50h                     ; GAP3 format

; Type 02h: 1.2M (5.25" HD)
    dw  80
    db  2
    db  15
    db  2
    db  RATE_500K
    db  1Bh
    db  54h

; Type 03h: 720K (3.5" DD)
    dw  80
    db  2
    db  9
    db  2
    db  RATE_250K
    db  2Ah
    db  50h

; Type 04h: 1.44M (3.5" HD)
    dw  80
    db  2
    db  18
    db  2
    db  RATE_500K
    db  1Bh
    db  6Ch

; Type 05h: Reserved (was 2.88M on some systems)
    dw  0, 0, 0, 0

; Type 06h: 2.88M (3.5" ED)
    dw  80
    db  2
    db  36
    db  2
    db  RATE_1M
    db  1Bh
    db  53h

; Type 07h: 8" SD (FM, 128-byte sectors)
    dw  77
    db  2
    db  26
    db  0                       ; 128 bytes/sector
    db  RATE_250K               ; Actually FM at 250K effective
    db  07h                     ; GAP3 for FM
    db  1Bh

; Type 08h: 8" DD (MFM, 1024-byte sectors)
    dw  77
    db  2
    db  8
    db  3                       ; 1024 bytes/sector
    db  RATE_500K
    db  35h
    db  74h

; Type 09h: 8" PC-compatible (MFM, 512-byte sectors)
    dw  77
    db  2
    db  15
    db  2                       ; 512 bytes/sector
    db  RATE_500K
    db  1Bh
    db  54h

; Type 0Ah: 8" CP/M (MFM, 256-byte sectors)
    dw  77
    db  2
    db  26
    db  1                       ; 256 bytes/sector
    db  RATE_500K
    db  0Eh
    db  36h
```

### 3.4 FPGA DRIVE_PROFILE Register Format

```asm
;==============================================================================
; DRIVE_PROFILE Register (32-bit, read from FPGA)
;==============================================================================
; Address: FDC_BASE + 68h (drive 0), FDC_BASE + 74h (drive 1)
;
; Bit layout:
;
;  31      24 23      16 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
; ┌─────────┬──────────┬──┬──┬──┬──┬──┬─────┬────────┬─────┬─────┬─────┐
; │ Quality │  RPM/10  │PV│PL│WP│HS│DS│SecSz│Encoding│Track│Dens │Form │
; └─────────┴──────────┴──┴──┴──┴──┴──┴─────┴────────┴─────┴─────┴─────┘
;
; Bits [1:0]   Form Factor
;              00 = Unknown
;              01 = 3.5"
;              10 = 5.25"
;              11 = 8"
;
; Bits [3:2]   Density Capability
;              00 = SD (Single Density / FM)
;              01 = DD (Double Density / MFM)
;              10 = HD (High Density)
;              11 = ED (Extended Density)
;
; Bits [5:4]   Track Density
;              00 = 40 tracks (48 TPI, 5.25" DD)
;              01 = 80 tracks (96 TPI)
;              10 = 77 tracks (8")
;              11 = Unknown / detecting
;
; Bits [8:6]   Encoding Type
;              000 = MFM
;              001 = FM
;              010 = GCR-Apple
;              011 = GCR-CBM (Commodore)
;              100 = M2FM
;              101 = Reserved
;              110 = Reserved
;              111 = Unknown
;
; Bits [10:9]  Sector Size Code
;              00 = 128 bytes (N=0)
;              01 = 256 bytes (N=1)
;              10 = 512 bytes (N=2)
;              11 = 1024 bytes (N=3)
;
; Bit [11]     Double-Step Required
;              0 = Normal stepping
;              1 = Double-step (40T media in 80T drive)
;
; Bit [12]     Hard-Sectored Disk
;              0 = Soft-sectored
;              1 = Hard-sectored (multiple index holes)
;
; Bit [13]     Write-Protected
;              0 = Writable
;              1 = Write-protected (via WP sensor)
;
; Bit [14]     Profile Locked
;              0 = Detection still in progress
;              1 = High-confidence detection complete
;
; Bit [15]     Profile Valid
;              0 = No drive or detection failed
;              1 = Valid profile available
;
; Bits [23:16] RPM / 10
;              Example: 30 = 300 RPM, 36 = 360 RPM
;
; Bits [31:24] Quality Score (0-255)
;              0-63:   Poor (marginal media/signal)
;              64-127: Fair
;              128-191: Good
;              192-255: Excellent

; Bit masks and shifts
PROFILE_FORM_MASK       equ     0003h
PROFILE_FORM_SHIFT      equ     0
PROFILE_DENS_MASK       equ     000Ch
PROFILE_DENS_SHIFT      equ     2
PROFILE_TRACK_MASK      equ     0030h
PROFILE_TRACK_SHIFT     equ     4
PROFILE_ENC_MASK        equ     01C0h
PROFILE_ENC_SHIFT       equ     6
PROFILE_SECSZ_MASK      equ     0600h
PROFILE_SECSZ_SHIFT     equ     9
PROFILE_DBLSTEP         equ     0800h
PROFILE_HARDSEC         equ     1000h
PROFILE_WRPROT          equ     2000h
PROFILE_LOCKED          equ     4000h
PROFILE_VALID           equ     8000h

; Form factor values
FORM_UNKNOWN            equ     0
FORM_35                 equ     1
FORM_525                equ     2
FORM_8                  equ     3

; Density values
DENS_SD                 equ     0       ; Single Density (FM)
DENS_DD                 equ     1       ; Double Density
DENS_HD                 equ     2       ; High Density
DENS_ED                 equ     3       ; Extended Density

; Track density values
TRACK_40                equ     0
TRACK_80                equ     1
TRACK_77                equ     2
TRACK_UNKNOWN           equ     3

; Encoding values
ENC_MFM                 equ     0
ENC_FM                  equ     1
ENC_GCR_APPLE           equ     2
ENC_GCR_CBM             equ     3
ENC_M2FM                equ     4
```

### 3.5 FDC Configuration Table (Sergey's Format - Preserved)

```asm
;==============================================================================
; FDC Configuration Table
;==============================================================================
; 2 entries x 4 bytes = 8 bytes

fdc_config:
.fdc0:
    dw      03F0h               ; Primary FDC base address
    db      06h                 ; IRQ 6
    db      02h                 ; DMA channel 2

.fdc1:
    dw      0370h               ; Secondary FDC base address (0=disabled)
    db      07h                 ; IRQ 7
    db      03h                 ; DMA channel 3
```

---

## 4. FPGA Register Interface

### 4.1 Discovery Registers

```asm
;==============================================================================
; FluxRipper Discovery Registers
;==============================================================================
; Base: FDC_BASE (03F0h or 0370h)
;
; These registers are provided by the FluxRipper FPGA for auto-detection.
; They are read-only and updated by the FPGA detection state machine.

DISC_REG_BASE           equ     60h     ; Offset from FDC base

; Register offsets from DISC_REG_BASE
DISC_MAGIC              equ     00h     ; R: Magic number (FBh or FDh)
DISC_VERSION            equ     01h     ; R: Discovery protocol version
DISC_STATUS             equ     02h     ; R: Detection FSM state
DISC_FLAGS              equ     03h     ; R: Detection flags

DISC_PROFILE_A          equ     08h     ; R: Drive 0 profile (32-bit)
DISC_PROFILE_B          equ     0Ch     ; R: Drive 1 profile (32-bit)

DISC_RPM_A              equ     10h     ; R: Drive 0 RPM * 10 (16-bit)
DISC_RPM_B              equ     12h     ; R: Drive 1 RPM * 10

DISC_QUALITY_A          equ     14h     ; R: Drive 0 quality (8-bit)
DISC_QUALITY_B          equ     15h     ; R: Drive 1 quality

; Detection status values
DISC_STATE_IDLE         equ     00h
DISC_STATE_MOTOR        equ     01h     ; Waiting for motor spin-up
DISC_STATE_INDEX        equ     02h     ; Measuring index frequency
DISC_STATE_RATE         equ     03h     ; Probing data rates
DISC_STATE_ENCODING     equ     04h     ; Detecting encoding
DISC_STATE_GEOMETRY     equ     05h     ; Detecting geometry
DISC_STATE_DONE         equ     0Fh     ; Detection complete

; Magic values
DISC_MAGIC_BASE         equ     0FBh    ; FluxRipper Base
DISC_MAGIC_DISC         equ     0FDh    ; FluxRipper Discovery
```

### 4.2 Instrumentation Registers

```asm
;==============================================================================
; FluxRipper FDD Instrumentation Registers
;==============================================================================
; Base: FDC_BASE + C0h
;
; Access method:
;   1. Write 10-bit address to INSTR_ADDR_LO/HI
;   2. Read 32-bit data from INSTR_DATA_0..3

INSTR_REG_BASE          equ     0C0h

; I/O port offsets
INSTR_ADDR_LO           equ     00h     ; W: Address bits [7:0]
INSTR_ADDR_HI           equ     01h     ; W: Address bits [9:8]
INSTR_DATA_0            equ     02h     ; R: Data bits [7:0]
INSTR_DATA_1            equ     03h     ; R: Data bits [15:8]
INSTR_DATA_2            equ     04h     ; R: Data bits [23:16]
INSTR_DATA_3            equ     05h     ; R: Data bits [31:24]
INSTR_CTRL              equ     06h     ; W: Control register

;------------------------------------------------------------------------------
; Instrumentation Address Map (FDD-Specific)
;------------------------------------------------------------------------------

; System Information (0x000-0x00F)
INSTR_MAGIC             equ     000h    ; Magic (0xFD010001)
INSTR_VERSION           equ     004h    ; Version
INSTR_CAPS              equ     008h    ; Capabilities
INSTR_STATUS            equ     00Ch    ; Status

; Timing (0x010-0x02F)
INSTR_UPTIME            equ     010h    ; Uptime (seconds)
INSTR_INDEX_PERIOD      equ     014h    ; Index period (us)
INSTR_RPM               equ     018h    ; RPM * 10
INSTR_DATA_RATE         equ     01Ch    ; Data rate (bits/sec)
INSTR_BIT_CELL          equ     020h    ; Bit cell period (ns)

; Command Statistics (0x030-0x04F)
INSTR_CMD_COUNT         equ     030h    ; Total commands
INSTR_READ_COUNT        equ     034h    ; Reads
INSTR_WRITE_COUNT       equ     038h    ; Writes
INSTR_SEEK_COUNT        equ     03Ch    ; Seeks
INSTR_FORMAT_COUNT      equ     040h    ; Formats
INSTR_VERIFY_COUNT      equ     044h    ; Verifies

; Error Counters (0x050-0x07F)
INSTR_ERR_TOTAL         equ     050h    ; Total errors
INSTR_ERR_CRC           equ     054h    ; CRC errors
INSTR_ERR_SEEK          equ     058h    ; Seek errors
INSTR_ERR_ID_NF         equ     05Ch    ; ID not found
INSTR_ERR_DAM_NF        equ     060h    ; Data AM not found
INSTR_ERR_OVERRUN       equ     064h    ; Overruns
INSTR_ERR_WRITE_PROT    equ     068h    ; Write protect hits

; Sector Statistics (0x080-0x09F)
INSTR_SECTORS_READ      equ     080h    ; Sectors read
INSTR_SECTORS_WRITE     equ     084h    ; Sectors written
INSTR_BYTES_XFER_LO     equ     088h    ; Bytes transferred [31:0]
INSTR_BYTES_XFER_HI     equ     08Ch    ; Bytes transferred [63:32]

; Signal Quality (0x0C0-0x0DF)
INSTR_SIG_AMPLITUDE     equ     0C0h    ; Signal amplitude (mV)
INSTR_SIG_SNR           equ     0C4h    ; SNR (dB * 10)
INSTR_SIG_JITTER        equ     0C8h    ; Jitter (ns)
INSTR_PLL_LOCK_PCT      equ     0CCh    ; PLL lock percentage
INSTR_PLL_PHASE_ERR     equ     0D0h    ; Phase error (ns)
INSTR_PLL_FREQ_ERR      equ     0D4h    ; Frequency error (ppm)

; Flux Analysis (0x0E0-0x0FF)
INSTR_FLUX_PERIOD_AVG   equ     0E0h    ; Avg flux period (ns)
INSTR_FLUX_PERIOD_MIN   equ     0E4h    ; Min flux period
INSTR_FLUX_PERIOD_MAX   equ     0E8h    ; Max flux period
INSTR_FLUX_TOTAL        equ     0ECh    ; Total transitions

; Encoding Detection (0x100-0x11F)
INSTR_ENCODING          equ     100h    ; Detected encoding
INSTR_ENC_CONFIDENCE    equ     104h    ; Confidence (0-255)
INSTR_SYNC_PATTERN      equ     108h    ; Last sync seen
INSTR_FM_CLOCK_BITS     equ     10Ch    ; FM clock bit count

; Health (0x120-0x13F)
INSTR_HEALTH_SCORE      equ     120h    ; Overall health (0-100)
INSTR_MEDIA_SCORE       equ     124h    ; Media quality
INSTR_HEAD_SCORE        equ     128h    ; Head condition
INSTR_MOTOR_SCORE       equ     12Ch    ; Motor health

; Flux Histogram (0x200-0x2FF)
INSTR_HIST_BASE         equ     200h    ; 64 x 32-bit bins
INSTR_HIST_BINS         equ     64
```

---

## 5. Boot Sequence

### 5.1 Initialization Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FluxRipper FDD BIOS Boot Sequence                   │
└─────────────────────────────────────────────────────────────────────────────┘

System BIOS POST
       │
       ▼
┌──────────────────┐
│ Scan for Option  │
│ ROMs (C000-EFFF) │
└────────┬─────────┘
         │ Found 55 AA at our ROM address
         ▼
┌──────────────────┐
│ FAR CALL CS:0003 │◄─────── Entry point
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    rom_init:     │
│  Save registers  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     No      ┌──────────────────┐
│ Detect FluxRipper├────────────►│ Fall back to     │
│ FPGA present?    │             │ Sergey's F2 menu │
└────────┬─────────┘             └────────┬─────────┘
         │ Yes                            │
         ▼                                │
┌──────────────────┐                      │
│  Print banner:   │                      │
│ "FluxRipper FDD" │                      │
└────────┬─────────┘                      │
         │                                │
         ▼                                │
┌──────────────────┐                      │
│ For each FDC:    │                      │
│  Wait for FPGA   │                      │
│  detection done  │                      │
└────────┬─────────┘                      │
         │                                │
         ▼                                │
┌──────────────────┐                      │
│ Read DRIVE_      │                      │
│ PROFILE registers│                      │
└────────┬─────────┘                      │
         │                                │
         ▼                                │
┌──────────────────┐                      │
│ Map profiles to  │                      │
│ drive type codes │                      │
└────────┬─────────┘                      │
         │                                │
         ▼                                │
┌──────────────────┐                      │
│ Populate         │                      │
│ drive_config[]   │                      │
└────────┬─────────┘                      │
         │                                │
         ▼                                │
┌──────────────────┐                      │
│ Display detected │                      │
│ drives           │                      │
└────────┬─────────┘                      │
         │                                │
         │◄────────────────────────────────┘
         ▼
┌──────────────────┐
│ set_interrupts:  │
│ • Hook INT 13h   │
│ • Hook INT 1Eh   │
│ • Set equipment  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Print "Ready"    │
│ [F3 for diag]    │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Restore regs     │
│ RETF             │
└──────────────────┘
         │
         ▼
    System BIOS
    continues POST
```

### 5.2 Auto-Detection Algorithm

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FPGA Auto-Detection Algorithm                            │
└─────────────────────────────────────────────────────────────────────────────┘

For each drive (0-3 per FDC):
│
├──► Phase 1: Motor Spin-Up
│    ├── Turn on motor
│    ├── Wait up to 2 seconds
│    └── Check for stable INDEX pulses
│        ├── No INDEX → No drive, skip
│        └── INDEX present → Continue
│
├──► Phase 2: RPM Measurement
│    ├── Measure INDEX period over 4 revolutions
│    ├── Calculate RPM = 60,000,000 / period_us
│    └── Classify:
│        ├── 295-305 RPM → 3.5" or 5.25" DD
│        ├── 355-365 RPM → 5.25" HD or 8"
│        └── Other → Unknown, use default
│
├──► Phase 3: Track Count Detection
│    ├── Seek to track 0 (recalibrate)
│    ├── Seek to track 79
│    │   ├── Success → 80-track drive
│    │   └── Fail (track 77) → Could be 8" (77T)
│    │       └── Seek to track 76
│    │           ├── Success → 8" confirmed (77T)
│    │           └── Fail → Try 40-track
│    └── Seek to track 39
│        ├── Success at 39, fail at 40 → 40-track drive
│        └── Other → Unknown
│
├──► Phase 4: Data Rate Detection
│    ├── For each rate (500K, 300K, 250K, 1M):
│    │   ├── Set CCR to rate
│    │   ├── Try READ_ID command
│    │   └── Check for valid sector ID
│    │       ├── Success → Rate found
│    │       └── Fail → Try next rate
│    └── Determine max rate = drive capability
│
├──► Phase 5: Encoding Detection
│    ├── Read raw flux from FPGA
│    ├── Analyze flux histogram
│    │   ├── Peaks at 2/3/4 µs → MFM
│    │   ├── Peaks at 4/8 µs → FM
│    │   └── Other patterns → GCR/M2FM
│    └── Confirm with sync pattern search
│        ├── A1 A1 A1 → MFM
│        ├── C7 / FC → FM
│        └── Other → Non-standard
│
├──► Phase 6: Sector Size Detection
│    ├── Issue READ_ID command
│    ├── Extract N field from sector header
│    │   ├── N=0 → 128 bytes
│    │   ├── N=1 → 256 bytes
│    │   ├── N=2 → 512 bytes
│    │   └── N=3 → 1024 bytes
│    └── Count sectors per track from IDs
│
└──► Phase 7: Build Profile
     ├── Combine all detected parameters
     ├── Set PROFILE_VALID bit
     ├── Calculate quality score
     └── Write to DRIVE_PROFILE register
```

### 5.3 Profile to Type Mapping

```asm
;==============================================================================
; Profile to Drive Type Mapping
;==============================================================================
; Input:  32-bit profile from FPGA
; Output: BIOS drive type code (type_none through type_8_cpm)

profile_to_type:
    ; Check if profile valid
    test    ax, PROFILE_VALID
    jz      .no_drive

    ; Extract form factor
    mov     bl, al
    and     bl, PROFILE_FORM_MASK

    cmp     bl, FORM_35
    je      .form_35
    cmp     bl, FORM_525
    je      .form_525
    cmp     bl, FORM_8
    je      .form_8
    jmp     .unknown

.form_35:
    ; 3.5" - check density
    mov     bl, al
    and     bl, PROFILE_DENS_MASK
    shr     bl, PROFILE_DENS_SHIFT

    cmp     bl, DENS_DD
    je      .type_720
    cmp     bl, DENS_HD
    je      .type_1440
    cmp     bl, DENS_ED
    je      .type_2880
    jmp     .type_1440              ; Default for 3.5"

.type_720:
    mov     al, type_720
    ret
.type_1440:
    mov     al, type_1440
    ret
.type_2880:
    mov     al, type_2880
    ret

.form_525:
    ; 5.25" - check density and tracks
    mov     bl, al
    and     bl, PROFILE_DENS_MASK
    shr     bl, PROFILE_DENS_SHIFT

    cmp     bl, DENS_HD
    je      .type_1200
    ; DD - check track count
    mov     bl, al
    and     bl, PROFILE_TRACK_MASK
    shr     bl, PROFILE_TRACK_SHIFT
    cmp     bl, TRACK_40
    je      .type_360
    jmp     .type_360               ; Default for 5.25" DD

.type_360:
    mov     al, type_360
    ret
.type_1200:
    mov     al, type_1200
    ret

.form_8:
    ; 8" - check encoding and sector size
    mov     bl, al
    and     bl, PROFILE_ENC_MASK
    shr     bl, PROFILE_ENC_SHIFT

    cmp     bl, ENC_FM
    je      .type_8_sd              ; FM = Single Density

    ; MFM - check sector size
    mov     bx, ax
    and     bx, PROFILE_SECSZ_MASK
    shr     bx, PROFILE_SECSZ_SHIFT

    cmp     bl, 0                   ; 128 bytes
    je      .type_8_sd              ; Unusual, treat as SD
    cmp     bl, 1                   ; 256 bytes
    je      .type_8_cpm
    cmp     bl, 2                   ; 512 bytes
    je      .type_8_pc
    ; 1024 bytes
    mov     al, type_8_dd
    ret

.type_8_sd:
    mov     al, type_8_sd
    ret
.type_8_cpm:
    mov     al, type_8_cpm
    ret
.type_8_pc:
    mov     al, type_8_pc
    ret

.unknown:
.no_drive:
    mov     al, type_none
    ret
```

---

## 6. ISA Plug-and-Play Support

### 6.1 PnP Header Structure

```asm
;==============================================================================
; ISA PnP Expansion Header
;==============================================================================
; Located at ROM offset 1Ah (paragraph-aligned)
; Per ISA PnP BIOS Specification 1.0a

%if ENABLE_PNP

    times (1Ah - ($ - $$)) db 0     ; Pad to offset 1Ah

pnp_header:
    db      '$PnP'                  ; +00: Signature (4 bytes)
    db      01h                     ; +04: Structure revision
    db      02h                     ; +05: Length / 16
    dw      0000h                   ; +06: Offset to next header
    db      00h                     ; +08: Reserved
    db      00h                     ; +09: Checksum (patched by tool)
    dd      PNP_DEVICE_ID           ; +0A: Device identifier
    dw      pnp_mfg_str             ; +0E: Manufacturer string
    dw      pnp_prod_str            ; +10: Product string
    db      01h                     ; +12: Base class (Mass Storage)
    db      02h                     ; +13: Sub class (Floppy)
    db      00h                     ; +14: Interface (generic)
    db      00h                     ; +15: Device indicators (low)
    db      00h                     ; +16: Device indicators (high)
    dw      0000h                   ; +17: Boot connection vector
    dw      0000h                   ; +19: Disconnect vector
    dw      pnp_bev                 ; +1B: Bootstrap entry vector
    dw      0000h                   ; +1D: Reserved
    dw      0000h                   ; +1F: Static resource info

; Device ID: FLX0200
; EISA format: 3-letter vendor ID + 4-hex product
PNP_DEVICE_ID   equ     0200584Ch   ; 'LX' + 00 + 02 (little-endian tricks)
                                    ; Actually encoded per EISA spec

pnp_mfg_str:
    db      "FluxRipper Project", 0

pnp_prod_str:
    db      "FluxRipper FDD BIOS v1.0", 0

;------------------------------------------------------------------------------
; Bootstrap Entry Vector (BEV)
;------------------------------------------------------------------------------
; Called by PnP BIOS for INT 19h boot from floppy
; Must attempt to boot from floppy, chain if failed

pnp_bev:
    ; Try to boot from floppy drive A:
    push    ds
    push    es
    push    bx
    push    dx

    ; Reset disk system
    xor     ax, ax
    xor     dx, dx                  ; Drive A:
    int     13h

    ; Read boot sector
    mov     ax, 0201h               ; AH=02 (read), AL=01 (1 sector)
    xor     dx, dx                  ; DH=0 (head), DL=0 (drive A:)
    mov     cx, 0001h               ; CH=0 (cyl), CL=1 (sector 1)
    xor     bx, bx
    mov     es, bx
    mov     bx, 7C00h               ; ES:BX = 0000:7C00
    int     13h
    jc      .boot_failed

    ; Verify boot signature
    cmp     word [es:7DFEh], 0AA55h
    jne     .boot_failed

    ; Jump to boot sector
    pop     dx
    pop     bx
    pop     es
    pop     ds
    jmp     0000h:7C00h

.boot_failed:
    pop     dx
    pop     bx
    pop     es
    pop     ds
    ; Chain to original INT 19h
    jmp     far [cs:old_int19]

%endif ; ENABLE_PNP
```

### 6.2 Device Type Classification

```
ISA PnP Device Classification for FluxRipper FDD BIOS:

Base Class:     01h = Mass Storage Controller
Sub Class:      02h = Floppy Disk Controller
Interface:      00h = Generic

Device ID:      FLX0200
                ├── FLX = FluxRipper (vendor)
                └── 0200 = FDD BIOS (product)
                    (vs 0100 for HDD BIOS)

Comparison with HDD BIOS:
┌─────────────┬───────────┬───────────┐
│ Field       │ FDD BIOS  │ HDD BIOS  │
├─────────────┼───────────┼───────────┤
│ Device ID   │ FLX0200   │ FLX0100   │
│ Base Class  │ 01h       │ 01h       │
│ Sub Class   │ 02h       │ 00h       │
│ Interface   │ 00h       │ 00h       │
│ BEV Target  │ Drive 00h │ Drive 80h │
└─────────────┴───────────┴───────────┘
```

---

## 7. INT 13h Extensions

### 7.1 Function Dispatch Table

```asm
;==============================================================================
; INT 13h Floppy Disk Services
;==============================================================================
; We intercept INT 13h for drives 00h-07h (floppies)
; Chain to previous handler for drives 80h+ (hard disks)

int_13_dispatch:
    ; Check if floppy drive
    cmp     dl, 08h
    jae     .chain                  ; Not our drive, chain

    ; Dispatch based on function
    cmp     ah, 00h
    je      int_13_fn_00            ; Reset
    cmp     ah, 01h
    je      int_13_fn_01            ; Get status
    cmp     ah, 02h
    je      int_13_fn_02            ; Read sectors
    cmp     ah, 03h
    je      int_13_fn_03            ; Write sectors
    cmp     ah, 04h
    je      int_13_fn_04            ; Verify sectors
    cmp     ah, 05h
    je      int_13_fn_05            ; Format track
    cmp     ah, 08h
    je      int_13_fn_08            ; Get parameters
    cmp     ah, 15h
    je      int_13_fn_15            ; Get disk type
    cmp     ah, 16h
    je      int_13_fn_16            ; Detect change
    cmp     ah, 17h
    je      int_13_fn_17            ; Set disk type
    cmp     ah, 18h
    je      int_13_fn_18            ; Set media type

    ; Unknown function
    mov     ah, 01h                 ; Invalid command
    stc
    retf    2

.chain:
    jmp     far [cs:old_int13]
```

### 7.2 Extended Function 08h (Get Parameters) for 8" Drives

```asm
;==============================================================================
; INT 13h Function 08h - Get Drive Parameters
;==============================================================================
; Extended to support 8" drive types
;
; Input:
;   AH = 08h
;   DL = Drive number
;
; Output:
;   AH = 00h (success) or error code
;   BL = Drive type (CMOS type)
;   CH = Maximum cylinder number (low 8 bits)
;   CL = Maximum sector number (bits 0-5) | max cyl high (bits 6-7)
;   DH = Maximum head number
;   DL = Number of drives
;   ES:DI = Pointer to drive parameter table
;   CF = 0 on success

int_13_fn_08:
    push    bx
    push    si

    ; Get drive type from config
    call    get_drive_type
    jc      .error

    ; BL = drive type for return
    mov     bl, al

    ; Look up geometry
    call    get_drive_geometry      ; Returns SI = geometry entry

    ; Build CX (cylinder/sector)
    mov     ax, [cs:si+0]           ; Cylinders
    dec     ax                      ; Max = count - 1
    mov     ch, al                  ; Low 8 bits of max cyl
    mov     cl, [cs:si+3]           ; Sectors per track
    and     cl, 3Fh                 ; Ensure 6 bits
    mov     al, ah
    and     al, 03h                 ; High 2 bits of cyl
    shl     al, 6
    or      cl, al                  ; Combine into CL

    ; DH = max head
    mov     dh, [cs:si+2]           ; Heads
    dec     dh                      ; Max = count - 1

    ; DL = number of drives
    mov     dl, [cs:num_drives]

    ; ES:DI = drive parameter table
    ; Point to appropriate DPT based on type
    call    get_dpt_pointer         ; Returns ES:DI

    ; Success
    xor     ah, ah
    clc
    pop     si
    pop     bx
    retf    2

.error:
    mov     ah, 07h                 ; Drive parameter error
    stc
    pop     si
    pop     bx
    retf    2
```

### 7.3 FM Encoding Support for Read/Write

```asm
;==============================================================================
; FM Encoding Support
;==============================================================================
; The FluxRipper FPGA handles FM encoding/decoding transparently.
; The BIOS just needs to:
;   1. Detect FM media (via encoding detector)
;   2. Use correct sector size (128 bytes for 8" SD)
;   3. Use FM-specific GAP lengths
;
; The FDC commands are the same - FPGA translates FM data.

; Check if current drive uses FM encoding
check_fm_encoding:
    push    ax
    push    dx

    ; Read encoding from instrumentation
    mov     ax, INSTR_ENCODING
    call    instr_read

    cmp     al, ENC_FM
    jne     .not_fm

    stc                             ; CF=1: FM encoding
    pop     dx
    pop     ax
    ret

.not_fm:
    clc                             ; CF=0: Not FM
    pop     dx
    pop     ax
    ret

; Get correct GAP3 for current encoding/format
get_gap3_length:
    ; Input: AL = operation (0=read/write, 1=format)
    ;        BL = drive type
    ; Output: AL = GAP3 length

    push    bx
    push    si

    ; Look up in geometry table
    xor     bh, bh
    shl     bx, 3                   ; 8 bytes per entry
    add     bx, geometry_table

    test    al, al
    jz      .rw_gap
    mov     al, [cs:bx+7]           ; Format GAP3
    jmp     .done
.rw_gap:
    mov     al, [cs:bx+6]           ; R/W GAP3

.done:
    pop     si
    pop     bx
    ret
```

---

## 8. F3 Diagnostics Menu

### 8.1 Menu Structure

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              F3 Menu Hierarchy                              │
└─────────────────────────────────────────────────────────────────────────────┘

Main Menu (F3)
│
├── [A] Drive A Status
│   ├── Type, geometry, quality
│   ├── RPM, data rate
│   ├── Error counters
│   └── [H] Flux Histogram
│       ├── 64-bin display
│       ├── Peak detection
│       └── Encoding analysis
│
├── [B] Drive B Status
│   └── (same as Drive A)
│
├── [C] Drive C Status (if present)
│   └── (same as Drive A)
│
├── [D] Drive D Status (if present)
│   └── (same as Drive A)
│
├── [R] Read Test
│   ├── Select drive
│   ├── Read track 0-N
│   └── Display errors/timing
│
├── [S] Signal Quality
│   ├── Amplitude
│   ├── SNR
│   ├── Jitter
│   └── PLL statistics
│
├── [E] Error Log
│   ├── Last 16 errors
│   ├── Timestamp
│   └── Location (C/H/S)
│
└── [ESC] Exit
```

### 8.2 Display Layouts

```asm
;==============================================================================
; F3 Diagnostics Display Layouts
;==============================================================================

; Main status screen layout (80x25)
;
; Row  Content
; ───  ─────────────────────────────────────────────────────
;  0   ╔══════════════════════════════════════════════════════════════════════╗
;  1   ║                      FluxRipper FDD Diagnostics                      ║
;  2   ╠══════════════════════════════════════════════════════════════════════╣
;  3   ║                                                                      ║
;  4   ║  Drive A: 3.5" 1.44M HD                                              ║
;  5   ║  ────────────────────────────────────────────────────────────────    ║
;  6   ║  Status: Ready              RPM: 300.1        Data Rate: 500 Kbps   ║
;  7   ║  Encoding: MFM              Tracks: 80        Sectors/Track: 18     ║
;  8   ║  Quality: ████████████████░░░░ 82%            PLL Lock: 99.2%       ║
;  9   ║                                                                      ║
; 10   ║  Statistics:                                                         ║
; 11   ║    Reads: 1,247             Writes: 89        Seeks: 342            ║
; 12   ║    CRC Errors: 0            ID Errors: 0      Timeouts: 0           ║
; 13   ║                                                                      ║
; 14   ║  Signal:                                                             ║
; 15   ║    Amplitude: 342 mV        Jitter: 12 ns     SNR: 28.4 dB          ║
; 16   ║                                                                      ║
; 17   ╠══════════════════════════════════════════════════════════════════════╣
; 18   ║  [A-D] Select Drive   [H] Histogram   [T] Read Test   [ESC] Exit    ║
; 19   ╚══════════════════════════════════════════════════════════════════════╝

diag_main_template:
    db  0, 0, 0C9h                  ; Top-left corner
    db  0, 1, 0CDh, 78              ; Top border (repeat 78x)
    db  0, 79, 0BBh                 ; Top-right corner
    ; ... etc

; Quality bar characters
QUAL_BAR_FULL   equ     0DBh        ; █
QUAL_BAR_EMPTY  equ     0B0h        ; ░
QUAL_BAR_WIDTH  equ     20          ; 20 characters wide

; Draw quality bar
; Input: AL = quality percentage (0-100)
draw_quality_bar:
    push    ax
    push    bx
    push    cx

    ; Calculate filled portion
    mov     bl, QUAL_BAR_WIDTH
    mul     bl
    mov     cl, 100
    div     cl                      ; AL = filled chars
    mov     cl, al
    mov     ch, QUAL_BAR_WIDTH
    sub     ch, cl                  ; CH = empty chars

    ; Draw filled portion
    mov     al, QUAL_BAR_FULL
.filled_loop:
    test    cl, cl
    jz      .empty
    call    putchar
    dec     cl
    jmp     .filled_loop

.empty:
    mov     al, QUAL_BAR_EMPTY
.empty_loop:
    test    ch, ch
    jz      .done
    call    putchar
    dec     ch
    jmp     .empty_loop

.done:
    pop     cx
    pop     bx
    pop     ax
    ret
```

### 8.3 Flux Histogram Display

```asm
;==============================================================================
; Flux Histogram Display
;==============================================================================
; 64-bin histogram displayed as ASCII bar chart
; Each bin = 50ns of flux period

HIST_ROWS       equ     10          ; Height of chart
HIST_COLS       equ     64          ; Number of bins
HIST_ORIGIN_X   equ     8           ; Left margin
HIST_ORIGIN_Y   equ     5           ; Top of chart

; Draw histogram
draw_histogram:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; Find max bin value for scaling
    xor     dx, dx                  ; Max value
    mov     cx, HIST_COLS
    mov     ax, INSTR_HIST_BASE
.find_max:
    push    cx
    call    instr_read              ; Read bin value
    cmp     ax, dx
    jbe     .not_max
    mov     dx, ax
.not_max:
    add     ax, 4                   ; Next bin address
    pop     cx
    loop    .find_max

    ; DX = max value, use for scaling
    test    dx, dx
    jz      .done                   ; Empty histogram

    ; Draw each column
    mov     cx, HIST_COLS
    mov     di, 0                   ; Column index
    mov     ax, INSTR_HIST_BASE

.draw_column:
    push    cx
    push    ax

    call    instr_read              ; Get bin value

    ; Scale to HIST_ROWS
    mov     bx, HIST_ROWS
    mul     bx
    div     dx                      ; AX = scaled height (0-HIST_ROWS)
    mov     bx, ax                  ; BX = bar height

    ; Draw column from bottom up
    mov     dh, HIST_ORIGIN_Y + HIST_ROWS - 1
    mov     dl, HIST_ORIGIN_X
    add     dl, di

    mov     cx, HIST_ROWS
.draw_cell:
    call    set_cursor

    cmp     cx, bx
    ja      .empty_cell
    mov     al, 0DBh                ; █ filled
    jmp     .put_cell
.empty_cell:
    mov     al, ' '                 ; Empty
.put_cell:
    call    putchar
    dec     dh
    loop    .draw_cell

    pop     ax
    add     ax, 4                   ; Next bin
    inc     di
    pop     cx
    loop    .draw_column

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
```

---

## 9. File Organization

### 9.1 Directory Structure

```
bios/fdd/
├── doc/
│   └── DESIGN.md                   # This document
│
├── include/
│   ├── config.inc                  # Build configuration
│   ├── fdc_regs.inc               # FDC register definitions
│   ├── profile.inc                # DRIVE_PROFILE format
│   ├── instr_fdd.inc              # Instrumentation registers
│   ├── types.inc                  # Drive type codes
│   ├── geometry.inc               # Geometry tables
│   ├── pnp.inc                    # PnP definitions
│   └── diag.inc                   # Diagnostics constants
│
├── src/
│   ├── entry.asm                  # ROM header, entry point
│   ├── init.asm                   # Initialization
│   ├── detect.asm                 # FluxRipper FPGA detection
│   ├── profile.asm                # Profile reading/mapping
│   ├── int13h.asm                 # INT 13h dispatcher
│   ├── disk_io.asm                # Read/write/verify/format
│   ├── seek.asm                   # Seek/recalibrate
│   ├── params.asm                 # Get/set parameters
│   ├── fm.asm                     # FM encoding support [16KB]
│   ├── 8inch.asm                  # 8" drive support [16KB]
│   ├── pnp.asm                    # PnP header/BEV [16KB]
│   ├── instr.asm                  # Instrumentation access [16KB]
│   ├── diag.asm                   # F3 diagnostics [16KB]
│   ├── histogram.asm              # Flux histogram [16KB]
│   ├── video.asm                  # Screen output [16KB]
│   ├── strings.asm                # Message strings
│   └── data.asm                   # Tables, config data
│
├── sergey/
│   ├── floppy_bios.asm            # Original Sergey source (reference)
│   ├── floppy1.inc                # Core FDC routines (modified)
│   ├── floppy2.inc                # Secondary FDC (modified)
│   ├── config.inc                 # Config routines (modified)
│   └── messages.inc               # Messages (extended)
│
├── tools/
│   ├── romsum.py                  # Checksum calculator
│   ├── pnpsum.py                  # PnP header checksum
│   └── rominfo.py                 # ROM info display
│
├── build/
│   ├── fluxripper_fdd_8k.rom      # 8KB build output
│   └── fluxripper_fdd_16k.rom     # 16KB build output
│
└── Makefile
```

### 9.2 Build Configuration (config.inc)

```asm
;==============================================================================
; Build Configuration
;==============================================================================

; ROM size selection (define one)
%ifdef BUILD_8KB
    ROM_SIZE        equ     8192
    ROM_BLOCKS      equ     16          ; 8KB / 512
    ENABLE_PNP      equ     0
    ENABLE_8INCH    equ     0
    ENABLE_FM       equ     0
    ENABLE_DIAG     equ     0
    ENABLE_F2       equ     0           ; No manual config
    VERBOSE_BOOT    equ     0
%else
    %define BUILD_16KB
    ROM_SIZE        equ     16384
    ROM_BLOCKS      equ     32          ; 16KB / 512
    ENABLE_PNP      equ     1
    ENABLE_8INCH    equ     1
    ENABLE_FM       equ     1
    ENABLE_DIAG     equ     1
    ENABLE_F2       equ     1           ; Optional manual override
    VERBOSE_BOOT    equ     1
%endif

; FDC addresses
FDC0_BASE       equ     03F0h           ; Primary FDC
FDC1_BASE       equ     0370h           ; Secondary FDC

; FluxRipper register offsets
FR_DISC_BASE    equ     60h             ; Discovery registers
FR_INSTR_BASE   equ     0C0h            ; Instrumentation

; Timeouts (timer ticks, ~18.2/sec)
MOTOR_TIMEOUT   equ     37              ; ~2 seconds
DETECT_TIMEOUT  equ     91              ; ~5 seconds
SEEK_TIMEOUT    equ     37              ; ~2 seconds

; Maximum drives
MAX_DRIVES      equ     8               ; 4 per FDC x 2 FDCs

; Version
VERSION_MAJOR   equ     1
VERSION_MINOR   equ     0
```

---

## 10. Testing Plan

### 10.1 Unit Tests

| Test | Description | Pass Criteria |
|------|-------------|---------------|
| ROM Signature | Verify 55 AA header | Bytes 0-1 = 55 AA |
| ROM Checksum | Sum all bytes | Sum mod 256 = 0 |
| PnP Header | Verify $PnP structure | Signature, checksum valid |
| Profile Parse | Map known profiles | Correct type codes |
| Geometry Lookup | Verify all 11 types | Correct C/H/S values |

### 10.2 Integration Tests

| Test | System | Drives | Expected |
|------|--------|--------|----------|
| Auto-detect 1.44M | AT | 3.5" HD | Type 04h detected |
| Auto-detect 1.2M | AT | 5.25" HD | Type 02h detected |
| Auto-detect 360K | XT | 5.25" DD | Type 01h detected |
| Auto-detect 8" SD | AT | 8" Shugart | Type 07h, FM encoding |
| Mixed drives | AT | 3.5" + 5.25" | Both detected |
| Dual FDC | AT | 4 drives | All 4 detected |
| PnP boot | AT PnP | 1.44M | Boots from floppy |
| F3 diagnostics | AT | Any | Menu displays |
| Read test | Any | Any | Sectors read OK |
| Format test | AT | 1.44M | Track formatted |

### 10.3 Hardware Targets

- IBM PC 5150 (XT) with 360K drive
- IBM PC/AT 5170 with 1.2M drive
- Generic 486 with 1.44M drive
- System with Monster FDC (4+ drives)
- System with 8" external drive

---

## 11. Implementation Phases

### Phase 1: Core Structure
- [ ] Create directory structure
- [ ] Port config.inc, fdc_regs.inc from HDD BIOS
- [ ] Create entry.asm with ROM header
- [ ] Create minimal init.asm
- [ ] Build 8KB ROM skeleton

### Phase 2: FluxRipper Detection
- [ ] Implement FPGA detection
- [ ] Implement profile reading
- [ ] Implement profile-to-type mapping
- [ ] Test with FPGA hardware

### Phase 3: Sergey Integration
- [ ] Merge Sergey's floppy1.inc, floppy2.inc
- [ ] Modify get_drive_type for auto-detect
- [ ] Modify init for auto-detect path
- [ ] Test basic INT 13h functions

### Phase 4: 8" Drive Support (16KB)
- [ ] Add 8" type codes and geometry
- [ ] Add FM encoding support
- [ ] Test with real 8" drive
- [ ] Verify sector read/write

### Phase 5: PnP Support (16KB)
- [ ] Add PnP header
- [ ] Implement BEV
- [ ] Test on PnP-aware systems
- [ ] Verify boot priority

### Phase 6: Diagnostics (16KB)
- [ ] Implement F3 menu framework
- [ ] Add drive status display
- [ ] Add histogram display
- [ ] Add signal quality display
- [ ] Add error log

### Phase 7: Polish
- [ ] Optimize code size
- [ ] Add verbose/compact boot modes
- [ ] Test on variety of hardware
- [ ] Documentation

---

## 12. Appendix

### A. Reference: Sergey's BIOS Source Files

| File | Size | Functions |
|------|------|-----------|
| floppy_bios.asm | ~2500 lines | Main entry, init, config |
| floppy1.inc | ~1500 lines | INT 13h handlers |
| floppy2.inc | ~500 lines | Secondary FDC support |
| config.inc | ~300 lines | F2 config utility |
| flash.inc | ~200 lines | EEPROM save |
| messages.inc | ~100 lines | UI strings |

### B. Reference: HDD BIOS Patterns to Reuse

| Pattern | HDD BIOS File | FDD Usage |
|---------|---------------|-----------|
| ROM header | entry.asm | Same structure |
| PnP header | entry.asm | Modify device ID/type |
| Instr access | instr.inc | Same macros |
| Discovery wait | discovery.asm | Adapt for FDC |
| Video output | video.asm | Reuse directly |
| Diagnostics menu | diag.asm | Adapt for FDD |

### C. 8" Drive Technical Specs

| Parameter | SD (FM) | DD (MFM) |
|-----------|---------|----------|
| RPM | 360 | 360 |
| Data rate | 250 Kbps (125K effective) | 500 Kbps |
| Tracks | 77 | 77 |
| Sectors/track | 26 | 8 |
| Bytes/sector | 128 | 1024 |
| Capacity | ~250 KB | ~1.2 MB |
| Encoding | FM | MFM |
| Bit cell | 4 µs | 2 µs |
