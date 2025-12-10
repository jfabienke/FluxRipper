;==============================================================================
; FluxRipper FDD BIOS - Build Configuration
;==============================================================================
; Assembly-time configuration flags for FDD BIOS builds.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;------------------------------------------------------------------------------
; ROM Size Configuration
;------------------------------------------------------------------------------
; Only one of these should be set to 1

%ifndef BUILD_8KB
%define BUILD_8KB       0               ; 8KB minimal build (XT-compatible)
%endif

%ifndef BUILD_16KB
%define BUILD_16KB      1               ; 16KB full build (default)
%endif

; Calculate ROM size in 512-byte blocks
%if BUILD_16KB
%define ROM_SIZE        16384
%define ROM_BLOCKS      32              ; 16KB / 512 = 32 blocks
%else
%define ROM_SIZE        8192
%define ROM_BLOCKS      16              ; 8KB / 512 = 16 blocks
%endif

;------------------------------------------------------------------------------
; Feature Flags
;------------------------------------------------------------------------------

; PnP (Plug and Play) support - 16KB only
%if BUILD_16KB
%define ENABLE_PNP      1
%else
%define ENABLE_PNP      0
%endif

; F3 diagnostics/override menu - 16KB only
%if BUILD_16KB
%define ENABLE_DIAG     1
%else
%define ENABLE_DIAG     0
%endif

; Extended formats (8", GCR, etc.) - 16KB only
%if BUILD_16KB
%define ENABLE_EXTENDED 1
%else
%define ENABLE_EXTENDED 0
%endif

;------------------------------------------------------------------------------
; FDC I/O Base Addresses
;------------------------------------------------------------------------------
%define FDC_PRIMARY     0x3F0           ; Primary FDC base
%define FDC_SECONDARY   0x370           ; Secondary FDC base

;------------------------------------------------------------------------------
; FluxRipper FPGA Discovery Registers
;------------------------------------------------------------------------------
; These are offsets from the FDC base address
%define DISC_PROFILE_A  0x68            ; Drive 0 profile (32-bit)
%define DISC_PROFILE_B  0x74            ; Drive 1 profile (32-bit)

;------------------------------------------------------------------------------
; FluxRipper FPGA Instrumentation Registers (16KB build only)
;------------------------------------------------------------------------------
; These registers provide detailed diagnostics from the FPGA
%define INSTR_BASE      0x80            ; Instrumentation register base

; Signal Quality Registers
%define INSTR_PLL_LOCK  0x80            ; PLL lock status (8-bit)
%define INSTR_SIGNAL_Q  0x81            ; Signal quality score (8-bit, 0-255)
%define INSTR_ERR_COUNT 0x82            ; Error counter (16-bit)
%define INSTR_SYNC_CNT  0x84            ; Sync pattern count (16-bit)

; Flux Analysis Registers
%define INSTR_FLUX_MIN  0x86            ; Minimum flux interval (16-bit, ns)
%define INSTR_FLUX_MAX  0x88            ; Maximum flux interval (16-bit, ns)
%define INSTR_FLUX_AVG  0x8A            ; Average flux interval (16-bit, ns)
%define INSTR_FLUX_JITT 0x8C            ; Flux jitter (8-bit, ns)

; Encoding Detection Registers
%define INSTR_ENC_TYPE  0x8D            ; Detected encoding type (8-bit)
%define INSTR_DATA_RATE 0x8E            ; Detected data rate (8-bit)
%define INSTR_INDEX_PER 0x8F            ; Index period (16-bit, ms*10)

; RPM and Timing
%define INSTR_RPM       0x91            ; Measured RPM (16-bit)
%define INSTR_INDEX_CNT 0x93            ; Index pulse count (8-bit)

;------------------------------------------------------------------------------
; DMA Configuration
;------------------------------------------------------------------------------
%define DMA_CHANNEL     2               ; FDC DMA channel (0-3)
%define DMA_PAGE_REG    0x81            ; Page register for channel 2
%define DMA_ADDR_REG    0x04            ; Address register for channel 2
%define DMA_COUNT_REG   0x05            ; Count register for channel 2
%define DMA_MASK_REG    0x0A            ; Single mask register
%define DMA_MODE_REG    0x0B            ; Mode register
%define DMA_FLIP_FLOP   0x0C            ; Clear byte pointer flip-flop

;------------------------------------------------------------------------------
; IRQ Configuration
;------------------------------------------------------------------------------
%define FDC_IRQ         6               ; FDC IRQ line

;------------------------------------------------------------------------------
; Timeouts (in timer ticks, ~18.2 ticks/second)
;------------------------------------------------------------------------------
%define MOTOR_TIMEOUT   36              ; Motor spin-up timeout (~2 sec)
%define SEEK_TIMEOUT    36              ; Seek timeout (~2 sec)
%define READ_TIMEOUT    36              ; Read timeout (~2 sec)
%define DISC_TIMEOUT    91              ; Discovery timeout (~5 sec)

;------------------------------------------------------------------------------
; Video Attributes (for 16KB diagnostic display)
;------------------------------------------------------------------------------
%define ATTR_NORMAL     0x07            ; White on black
%define ATTR_HIGHLIGHT  0x0F            ; Bright white on black
%define ATTR_TITLE      0x1F            ; Bright white on blue
%define ATTR_ERROR      0x4F            ; Bright white on red
%define ATTR_SUCCESS    0x2F            ; Bright white on green
%define ATTR_BOX        0x70            ; Black on white

;------------------------------------------------------------------------------
; Screen Dimensions
;------------------------------------------------------------------------------
%define SCREEN_WIDTH    80
%define SCREEN_HEIGHT   25

;------------------------------------------------------------------------------
; FPGA Configuration Registers (accessible from BIOS)
;------------------------------------------------------------------------------
; Base offset from FDC_PRIMARY (0x3F0 + 0xD0 = 0x4C0)
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
%define CFG_SAVE        0x0E            ; Write 0x5A to save to flash
%define CFG_RESTORE     0x0F            ; Write 0xA5 to restore defaults

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
