;==============================================================================
; FluxRipper HDD BIOS - Build Configuration
;==============================================================================
; Defines assembly-time flags for conditional compilation of features.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%ifndef CONFIG_INC
%define CONFIG_INC

;------------------------------------------------------------------------------
; Build Target Selection
;------------------------------------------------------------------------------
; These should be defined on the command line via -D flags:
;   -DBUILD_8KB=1 -DBUILD_16KB=0   for 8KB XT-compatible ROM
;   -DBUILD_8KB=0 -DBUILD_16KB=1   for 16KB AT ROM with diagnostics

%ifndef BUILD_8KB
    %define BUILD_8KB   1       ; Default to 8KB build
%endif

%ifndef BUILD_16KB
    %define BUILD_16KB  0
%endif

;------------------------------------------------------------------------------
; ROM Size Constants
;------------------------------------------------------------------------------
%if BUILD_8KB
    %define ROM_SIZE        8192        ; 8KB ROM
    %define ROM_BLOCKS      16          ; Size in 512-byte blocks
%else
    %define ROM_SIZE        16384       ; 16KB ROM
    %define ROM_BLOCKS      32          ; Size in 512-byte blocks
%endif

;------------------------------------------------------------------------------
; Feature Enables (derived from build target)
;------------------------------------------------------------------------------

; LBA extensions (INT 13h 41h-48h) - 16KB only
%if BUILD_16KB
    %define ENABLE_LBA      1
%else
    %define ENABLE_LBA      0
%endif

; Extended INT 13h functions (09h-15h) - 16KB only
%if BUILD_16KB
    %define ENABLE_EXTENDED 1
%else
    %define ENABLE_EXTENDED 0
%endif

; Diagnostics menu - 16KB only
%if BUILD_16KB
    %define ENABLE_DIAG     1
%else
    %define ENABLE_DIAG     0
%endif

; Setup utility - 16KB only
%if BUILD_16KB
    %define ENABLE_SETUP    1
%else
    %define ENABLE_SETUP    0
%endif

; Real-time monitor (F3) - 16KB only
%if BUILD_16KB
    %define ENABLE_MONITOR  1
%else
    %define ENABLE_MONITOR  0
%endif

; PnP header - 16KB only
%if BUILD_16KB
    %define ENABLE_PNP      1
%else
    %define ENABLE_PNP      0
%endif

;------------------------------------------------------------------------------
; Default I/O Port Addresses
;------------------------------------------------------------------------------
; These match the FPGA auto-config defaults

; WD controller primary base (task file registers 1F0-1F7)
%define WD_BASE_PRIMARY     0x1F0

; WD controller alternate base (3F6-3F7)
%define WD_BASE_ALTERNATE   0x3F6

; WD controller secondary base (170-177) for dual-drive
%define WD_BASE_SECONDARY   0x170

; FDC base (not used by HDD BIOS, but defined for reference)
%define FDC_BASE            0x3F0

;------------------------------------------------------------------------------
; FPGA Discovery Register Offsets (from WD_BASE + 0x80)
;------------------------------------------------------------------------------
%define DISC_REG_BASE       0x80        ; Discovery registers at WD_BASE+0x80

;------------------------------------------------------------------------------
; FPGA Instrumentation Register Offsets (from WD_BASE + 0xC0)
;------------------------------------------------------------------------------
%define INSTR_REG_BASE      0xC0        ; Instrumentation at WD_BASE+0xC0

;------------------------------------------------------------------------------
; Default IRQ Settings
;------------------------------------------------------------------------------
%define WD_IRQ_PRIMARY      14          ; Primary WD IRQ
%define WD_IRQ_SECONDARY    15          ; Secondary WD IRQ

;------------------------------------------------------------------------------
; ROM Base Address
;------------------------------------------------------------------------------
%define ROM_SEGMENT         0xC800      ; Standard Option ROM segment
%define ROM_BASE            0xC8000     ; ROM linear address

;------------------------------------------------------------------------------
; Timing Constants (for delay loops)
;------------------------------------------------------------------------------
; These are conservative and work on 4.77 MHz XT through modern systems
%define DELAY_SHORT         10          ; ~10us on XT
%define DELAY_MEDIUM        100         ; ~100us on XT
%define DELAY_LONG          1000        ; ~1ms on XT
%define DELAY_VERY_LONG     10000       ; ~10ms on XT

;------------------------------------------------------------------------------
; Drive Limits
;------------------------------------------------------------------------------
%define MAX_DRIVES          2           ; Maximum hard drives supported
%define MAX_CYLINDERS       16383       ; Max cylinders (INT 13h limit)
%define MAX_HEADS           255         ; Max heads
%define MAX_SECTORS         63          ; Max sectors per track

;------------------------------------------------------------------------------
; WD Controller Personality Codes
;------------------------------------------------------------------------------
%define PERSONALITY_WD1002  0           ; 8-bit XT, MFM, ST-506
%define PERSONALITY_WD1003  1           ; 16-bit AT, MFM, ST-506
%define PERSONALITY_WD1006  2           ; 16-bit AT, RLL 2,7, ST-506
%define PERSONALITY_WD1007  3           ; 16-bit AT, ESDI

;------------------------------------------------------------------------------
; Debug Options
;------------------------------------------------------------------------------
%define DEBUG_VERBOSE       0           ; Enable verbose debug output
%define DEBUG_SERIAL        0           ; Output debug to COM1

;------------------------------------------------------------------------------
; FPGA Configuration Registers (accessible from BIOS)
;------------------------------------------------------------------------------
; Base offset from WD_BASE_PRIMARY (0x1F0 + 0xD0 = 0x2C0)
; These registers allow runtime enable/disable of controllers
%define CFG_REG_BASE    0xD0            ; Config register base offset

; Register offsets from CFG_REG_BASE
%define CFG_CTRL        0x00            ; Global control register
%define CFG_FDC         0x01            ; FDC configuration
%define CFG_WD          0x02            ; WD HDD configuration
%define CFG_DMA         0x03            ; DMA configuration
%define CFG_IRQ         0x04            ; IRQ configuration
%define CFG_STATUS      0x05            ; Status register (read-only)
%define CFG_SCRATCH     0x06            ; Scratch register
%define CFG_MAGIC       0x07            ; Magic number (0xFB)
%define CFG_INTLV_CTRL  0x08            ; Interleave control (0=auto, 1-8=override)
%define CFG_INTLV_STAT  0x09            ; Detected interleave (read-only)
%define CFG_SAVE        0x0E            ; Write 0x5A to save to flash
%define CFG_RESTORE     0x0F            ; Write 0xA5 to restore defaults

;------------------------------------------------------------------------------
; Interleave Configuration Values
;------------------------------------------------------------------------------
%define INTLV_AUTO      0x00            ; Auto-match (preserve existing)
%define INTLV_1_1       0x01            ; 1:1 interleave (no interleave)
%define INTLV_2_1       0x02            ; 2:1 interleave
%define INTLV_3_1       0x03            ; 3:1 interleave
%define INTLV_4_1       0x04            ; 4:1 interleave
%define INTLV_5_1       0x05            ; 5:1 interleave
%define INTLV_6_1       0x06            ; 6:1 interleave
%define INTLV_7_1       0x07            ; 7:1 interleave
%define INTLV_8_1       0x08            ; 8:1 interleave

; CFG_CTRL bit definitions
%define CFG_CTRL_FDC_EN     0x01        ; Bit 0: FDC enabled
%define CFG_CTRL_WD_EN      0x02        ; Bit 1: WD HDD enabled
%define CFG_CTRL_LOCKED     0x10        ; Bit 4: Config write-protected

; CFG_FDC bit definitions
%define CFG_FDC_DMA_EN      0x01        ; Bit 0: FDC DMA enabled
%define CFG_FDC_SEC_EN      0x02        ; Bit 1: Secondary FDC enabled

; CFG_WD bit definitions
%define CFG_WD_DMA_EN       0x01        ; Bit 0: WD DMA enabled (XT)
%define CFG_WD_SEC_EN       0x02        ; Bit 1: Secondary WD enabled
%define CFG_WD_BUF_BYPASS   0x80        ; Bit 7: Track buffer bypass (for benchmark)

; CFG_STATUS bit definitions (read-only)
%define CFG_STAT_8BIT       0x01        ; Bit 0: 8-bit slot detected
%define CFG_STAT_16BIT      0x02        ; Bit 1: 16-bit slot detected
%define CFG_STAT_PNP        0x04        ; Bit 2: PnP mode active
%define CFG_STAT_FLASH_BUSY 0x08        ; Bit 3: Flash operation in progress
; Bits 5:4 = WD Personality (0=WD1002, 1=WD1003, 2=WD1006, 3=WD1007)
%define CFG_STAT_FDC_PRESENT 0x40       ; Bit 6: FDC hardware installed
%define CFG_STAT_WD_PRESENT  0x80       ; Bit 7: WD hardware installed

; Magic values
%define CFG_MAGIC_VALUE     0xFB        ; FluxRipper magic byte
%define CFG_SAVE_MAGIC      0x5A        ; Write to CFG_SAVE to save
%define CFG_RESTORE_MAGIC   0xA5        ; Write to CFG_RESTORE to restore

%endif ; CONFIG_INC
