;==============================================================================
; FluxRipper HDD BIOS - WD Controller Register Definitions
;==============================================================================
; Defines task file registers for WD1002/1003/1006/1007 compatible controllers.
;
; Register Map (AT-compatible, offset from base 0x1F0):
;   +0x0: DATA        - Data register (R/W)
;   +0x1: ERROR       - Error register (R) / Features (W)
;   +0x2: SECCNT      - Sector count (R/W)
;   +0x3: SECNUM      - Sector number / LBA [7:0] (R/W)
;   +0x4: CYL_LO      - Cylinder low / LBA [15:8] (R/W)
;   +0x5: CYL_HI      - Cylinder high / LBA [23:16] (R/W)
;   +0x6: SDH         - Size/Drive/Head / LBA [27:24] (R/W)
;   +0x7: STATUS      - Status register (R) / Command (W)
;
; Alternate registers (offset from 0x3F6):
;   +0x0: ALT_STATUS  - Alternate status (R) / Device Control (W)
;   +0x1: DRV_ADDR    - Drive address (R)
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%ifndef WD_REGS_INC
%define WD_REGS_INC

;------------------------------------------------------------------------------
; Task File Register Offsets (from WD_BASE)
;------------------------------------------------------------------------------
%define WD_DATA         0x00        ; Data register
%define WD_ERROR        0x01        ; Error register (read)
%define WD_FEATURES     0x01        ; Features register (write)
%define WD_SECCNT       0x02        ; Sector count
%define WD_SECNUM       0x03        ; Sector number (CHS) or LBA[7:0]
%define WD_CYL_LO       0x04        ; Cylinder low (CHS) or LBA[15:8]
%define WD_CYL_HI       0x05        ; Cylinder high (CHS) or LBA[23:16]
%define WD_SDH          0x06        ; Size/Drive/Head
%define WD_STATUS       0x07        ; Status register (read)
%define WD_COMMAND      0x07        ; Command register (write)

;------------------------------------------------------------------------------
; Alternate Register Offsets (from ALT_BASE = 0x3F6)
;------------------------------------------------------------------------------
%define WD_ALT_STATUS   0x00        ; Alternate status (read, no IRQ clear)
%define WD_DEV_CTRL     0x00        ; Device control (write)
%define WD_DRV_ADDR     0x01        ; Drive address (read)

;------------------------------------------------------------------------------
; Status Register Bits (WD_STATUS)
;------------------------------------------------------------------------------
%define STS_BSY         0x80        ; Busy - controller executing
%define STS_DRDY        0x40        ; Drive ready
%define STS_DWF         0x20        ; Drive write fault
%define STS_DSC         0x10        ; Drive seek complete
%define STS_DRQ         0x08        ; Data request
%define STS_CORR        0x04        ; Corrected data (ECC)
%define STS_IDX         0x02        ; Index pulse
%define STS_ERR         0x01        ; Error occurred

;------------------------------------------------------------------------------
; Error Register Bits (WD_ERROR)
;------------------------------------------------------------------------------
%define ERR_BBK         0x80        ; Bad block detected
%define ERR_UNC         0x40        ; Uncorrectable data error
%define ERR_MC          0x20        ; Media changed
%define ERR_IDNF        0x10        ; ID not found
%define ERR_MCR         0x08        ; Media change requested
%define ERR_ABRT        0x04        ; Aborted command
%define ERR_TK0NF       0x02        ; Track 0 not found
%define ERR_AMNF        0x01        ; Address mark not found

;------------------------------------------------------------------------------
; Device Control Register Bits (WD_DEV_CTRL)
;------------------------------------------------------------------------------
%define CTRL_HOB        0x80        ; High order byte (48-bit LBA)
%define CTRL_SRST       0x04        ; Software reset
%define CTRL_NIEN       0x02        ; Disable interrupts

;------------------------------------------------------------------------------
; SDH Register Format
;------------------------------------------------------------------------------
; Bit 7:5 = Size (sector size encoding, 010 = 512 bytes)
; Bit 4   = DRV (drive select: 0 = master, 1 = slave)
; Bit 3:0 = HEAD (head number 0-15)
;
; For LBA mode (drive must support it):
; Bit 7   = 1 (always)
; Bit 6   = LBA (1 = LBA mode)
; Bit 5   = 1 (always)
; Bit 4   = DRV
; Bit 3:0 = LBA[27:24]

%define SDH_SIZE_512    0xA0        ; 512-byte sectors, default
%define SDH_DRV0        0x00        ; Drive 0 (master)
%define SDH_DRV1        0x10        ; Drive 1 (slave)
%define SDH_LBA         0x40        ; LBA mode bit

;------------------------------------------------------------------------------
; Command Codes
;------------------------------------------------------------------------------
; Basic Commands (all personalities)
%define CMD_RECALIBRATE 0x10        ; Recalibrate (seek to track 0)
%define CMD_READ        0x20        ; Read sectors (with retry)
%define CMD_READ_NR     0x21        ; Read sectors (no retry)
%define CMD_WRITE       0x30        ; Write sectors (with retry)
%define CMD_WRITE_NR    0x31        ; Write sectors (no retry)
%define CMD_VERIFY      0x40        ; Verify sectors (with retry)
%define CMD_VERIFY_NR   0x41        ; Verify sectors (no retry)
%define CMD_FORMAT      0x50        ; Format track
%define CMD_SEEK        0x70        ; Seek to cylinder
%define CMD_DIAG        0x90        ; Execute drive diagnostics
%define CMD_INIT_PARAM  0x91        ; Initialize drive parameters
%define CMD_READ_LONG   0x22        ; Read long (sector + ECC)
%define CMD_WRITE_LONG  0x32        ; Write long (sector + ECC)

; WD1006 (RLL) Additional Commands
%define CMD_READ_BUF    0xE4        ; Read sector buffer
%define CMD_WRITE_BUF   0xE8        ; Write sector buffer

; WD1007 (ESDI) Additional Commands
%define CMD_IDENTIFY    0xEC        ; Identify drive (returns 256 words)
%define CMD_SET_MULTI   0xC6        ; Set multiple mode
%define CMD_READ_MULTI  0xC4        ; Read multiple sectors
%define CMD_WRITE_MULTI 0xC5        ; Write multiple sectors

;------------------------------------------------------------------------------
; Command Timeouts (in loop iterations - calibrate for target CPU)
;------------------------------------------------------------------------------
%define TIMEOUT_BSY_CLR     0xFFFF  ; Wait for BSY clear
%define TIMEOUT_DRQ_SET     0xFFFF  ; Wait for DRQ set
%define TIMEOUT_DRDY        0xFFFF  ; Wait for DRDY
%define TIMEOUT_SEEK        0xFFFF  ; Wait for seek complete
%define TIMEOUT_RESET       0xFFFF  ; Wait for reset complete

;------------------------------------------------------------------------------
; Macros for WD Register Access
;------------------------------------------------------------------------------

; Wait for BSY clear with timeout
; Input: DX = base port, CX = timeout counter
; Output: CF=0 success, CF=1 timeout, AL = final status
%macro WD_WAIT_NOT_BSY 0
    %%loop:
        in      al, dx
        test    al, STS_BSY
        jz      %%done
        loop    %%loop
        stc                         ; Set carry = timeout
        jmp     %%exit
    %%done:
        clc                         ; Clear carry = success
    %%exit:
%endmacro

; Wait for DRQ set with timeout
; Input: DX = base port, CX = timeout counter
; Output: CF=0 success, CF=1 timeout/error, AL = final status
%macro WD_WAIT_DRQ 0
    %%loop:
        in      al, dx
        test    al, STS_ERR
        jnz     %%error
        test    al, STS_DRQ
        jnz     %%done
        loop    %%loop
        stc
        jmp     %%exit
    %%error:
        stc
        jmp     %%exit
    %%done:
        clc
    %%exit:
%endmacro

; Wait for DRDY set with timeout
; Input: DX = base port, CX = timeout counter
; Output: CF=0 success, CF=1 timeout, AL = final status
%macro WD_WAIT_DRDY 0
    %%loop:
        in      al, dx
        test    al, STS_DRDY
        jnz     %%done
        loop    %%loop
        stc
        jmp     %%exit
    %%done:
        clc
    %%exit:
%endmacro

%endif ; WD_REGS_INC
