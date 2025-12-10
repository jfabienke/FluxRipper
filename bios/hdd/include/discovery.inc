;==============================================================================
; FluxRipper HDD BIOS - FPGA Discovery Register Definitions
;==============================================================================
; Defines the register map for reading FPGA auto-detection results.
;
; The FPGA automatically detects connected drives during power-up and
; populates these registers with discovered geometry and capabilities.
; The BIOS reads these registers instead of probing the drive directly.
;
; Register Base: WD_BASE + 0x80 (e.g., 0x1F0 + 0x80 = 0x270)
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%ifndef DISCOVERY_INC
%define DISCOVERY_INC

;------------------------------------------------------------------------------
; Discovery Register Offsets (from DISC_REG_BASE = WD_BASE + 0x80)
;------------------------------------------------------------------------------
%define DISC_SIGNATURE      0x00    ; R: Signature byte (0xFB = FluxRipper)
%define DISC_VERSION        0x01    ; R: FPGA version (major.minor)
%define DISC_STATUS         0x02    ; R: Discovery status
%define DISC_FLAGS          0x03    ; R: Detection flags

; Drive 0 Geometry (primary)
%define DISC_D0_CYL_LO      0x04    ; R: Cylinders [7:0]
%define DISC_D0_CYL_HI      0x05    ; R: Cylinders [15:8]
%define DISC_D0_HEADS       0x06    ; R: Heads (1-255)
%define DISC_D0_SECTORS     0x07    ; R: Sectors per track (1-63)
%define DISC_D0_CAP_0       0x08    ; R: Total sectors [7:0]
%define DISC_D0_CAP_1       0x09    ; R: Total sectors [15:8]
%define DISC_D0_CAP_2       0x0A    ; R: Total sectors [23:16]
%define DISC_D0_CAP_3       0x0B    ; R: Total sectors [31:24]
%define DISC_D0_FLAGS       0x0C    ; R: Drive 0 feature flags
%define DISC_D0_RATE        0x0D    ; R: Data rate code
%define DISC_D0_RESERVED    0x0E    ; Reserved

; Drive 1 Geometry (secondary)
%define DISC_D1_CYL_LO      0x10    ; R: Cylinders [7:0]
%define DISC_D1_CYL_HI      0x11    ; R: Cylinders [15:8]
%define DISC_D1_HEADS       0x12    ; R: Heads
%define DISC_D1_SECTORS     0x13    ; R: Sectors per track
%define DISC_D1_CAP_0       0x14    ; R: Total sectors [7:0]
%define DISC_D1_CAP_1       0x15    ; R: Total sectors [15:8]
%define DISC_D1_CAP_2       0x16    ; R: Total sectors [23:16]
%define DISC_D1_CAP_3       0x17    ; R: Total sectors [31:24]
%define DISC_D1_FLAGS       0x18    ; R: Drive 1 feature flags
%define DISC_D1_RATE        0x19    ; R: Data rate code
%define DISC_D1_RESERVED    0x1A    ; Reserved

; Drive Model String (32 bytes, null-terminated)
%define DISC_MODEL_BASE     0x20    ; R: Drive model string (32 bytes)
%define DISC_MODEL_LEN      32

; Personality Detection
%define DISC_PERSONALITY    0x40    ; R: Detected personality (0=WD1002, 1=WD1003, 2=WD1006, 3=WD1007)
%define DISC_SLOT_TYPE      0x41    ; R: Slot type (0=8-bit XT, 1=16-bit AT)
%define DISC_PNP_ACTIVE     0x42    ; R: PnP mode active (0=legacy, 1=PnP)

;------------------------------------------------------------------------------
; DISC_STATUS Bits
;------------------------------------------------------------------------------
%define DISC_STS_BUSY       0x80    ; Discovery in progress
%define DISC_STS_DONE       0x40    ; Discovery complete
%define DISC_STS_ERROR      0x20    ; Discovery error occurred
%define DISC_STS_D0_PRESENT 0x01    ; Drive 0 detected
%define DISC_STS_D1_PRESENT 0x02    ; Drive 1 detected

;------------------------------------------------------------------------------
; DISC_FLAGS Bits (global)
;------------------------------------------------------------------------------
%define DISC_FLG_ESDI       0x01    ; ESDI interface detected
%define DISC_FLG_RLL        0x02    ; RLL encoding detected
%define DISC_FLG_MFM        0x04    ; MFM encoding detected
%define DISC_FLG_XT_MODE    0x10    ; Operating in XT mode
%define DISC_FLG_AT_MODE    0x20    ; Operating in AT mode
%define DISC_FLG_PNP        0x40    ; PnP BIOS detected

;------------------------------------------------------------------------------
; Per-Drive Flags (DISC_Dx_FLAGS)
;------------------------------------------------------------------------------
%define DDRV_FLG_PRESENT    0x01    ; Drive is present
%define DDRV_FLG_ESDI       0x02    ; ESDI interface
%define DDRV_FLG_RLL        0x04    ; RLL encoding
%define DDRV_FLG_MFM        0x08    ; MFM encoding
%define DDRV_FLG_LBA        0x10    ; LBA capable
%define DDRV_FLG_ECC        0x20    ; ECC supported
%define DDRV_FLG_MULTI      0x40    ; Multi-sector transfers
%define DDRV_FLG_READY      0x80    ; Drive ready

;------------------------------------------------------------------------------
; Data Rate Codes (DISC_Dx_RATE)
;------------------------------------------------------------------------------
%define RATE_5MBPS          0x00    ; 5 Mbps (MFM ST-506)
%define RATE_7_5MBPS        0x01    ; 7.5 Mbps (RLL ST-506)
%define RATE_10MBPS         0x02    ; 10 Mbps (ESDI)
%define RATE_15MBPS         0x03    ; 15 Mbps (ESDI high-speed)
%define RATE_20MBPS         0x04    ; 20 Mbps (ESDI max)

;------------------------------------------------------------------------------
; Personality Codes
;------------------------------------------------------------------------------
%define PERS_WD1002         0x00    ; WD1002-WX1: 8-bit XT, MFM, ST-506
%define PERS_WD1003         0x01    ; WD1003-WAH: 16-bit AT, MFM, ST-506
%define PERS_WD1006         0x02    ; WD1006-WAH: 16-bit AT, RLL, ST-506
%define PERS_WD1007         0x03    ; WD1007-WAH: 16-bit AT, ESDI

;------------------------------------------------------------------------------
; Discovery Timeout (in milliseconds)
;------------------------------------------------------------------------------
%define DISC_TIMEOUT_MS     5000    ; 5 second timeout for discovery

;------------------------------------------------------------------------------
; Macros for Reading Discovery Registers
;------------------------------------------------------------------------------

; Read discovery byte register
; Input: AL = register offset (from DISC_REG_BASE)
; Output: AL = register value
; Destroys: DX
%macro DISC_READ_BYTE 1
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + %1
    in      al, dx
%endmacro

; Read discovery word register (little-endian)
; Input: first param = low byte offset
; Output: AX = 16-bit value
; Destroys: DX
%macro DISC_READ_WORD 1
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + %1
    in      al, dx                  ; Read low byte
    mov     ah, al
    inc     dx
    in      al, dx                  ; Read high byte
    xchg    al, ah                  ; Swap to correct order
%endmacro

%endif ; DISCOVERY_INC
