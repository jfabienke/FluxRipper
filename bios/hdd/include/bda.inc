;==============================================================================
; FluxRipper HDD BIOS - BIOS Data Area Definitions
;==============================================================================
; Defines offsets within the BIOS Data Area (BDA) at segment 0040h.
; Includes fixed disk parameter tables and drive status locations.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%ifndef BDA_INC
%define BDA_INC

;------------------------------------------------------------------------------
; BDA Segment
;------------------------------------------------------------------------------
%define BDA_SEG             0x0040      ; BIOS Data Area segment

;------------------------------------------------------------------------------
; Floppy/Hard Disk Status and Count
;------------------------------------------------------------------------------
%define BDA_DISKETTE_STATUS 0x0041      ; Diskette status byte
%define BDA_DISKETTE_MOTOR  0x003F      ; Diskette motor status
%define BDA_DISKETTE_TIMER  0x0040      ; Diskette motor timeout

%define BDA_HDD_STATUS      0x0074      ; Hard disk last operation status
%define BDA_HDD_COUNT       0x0075      ; Number of hard drives

;------------------------------------------------------------------------------
; Fixed Disk Parameter Tables
;------------------------------------------------------------------------------
; INT 41h vector points to drive 0 parameter table
; INT 46h vector points to drive 1 parameter table
;
; Each table is 16 bytes with the following format:
;   Offset  Size  Description
;   0x00    2     Maximum cylinders
;   0x02    1     Maximum heads
;   0x03    2     Reserved (was reduced write current cyl)
;   0x05    2     Write precompensation cylinder
;   0x07    1     Reserved (was max ECC burst length)
;   0x08    1     Control byte (step rate, etc.)
;   0x09    1     Standard timeout
;   0x0A    1     Format timeout
;   0x0B    1     Check timeout
;   0x0C    2     Landing zone cylinder
;   0x0E    1     Sectors per track
;   0x0F    1     Reserved

%define FDPT_MAX_CYL        0x00        ; Max cylinders (word)
%define FDPT_MAX_HEAD       0x02        ; Max heads (byte)
%define FDPT_RESERVED1      0x03        ; Reserved (word)
%define FDPT_WR_PRECOMP     0x05        ; Write precomp cyl (word)
%define FDPT_RESERVED2      0x07        ; Reserved (byte)
%define FDPT_CONTROL        0x08        ; Control byte
%define FDPT_STD_TIMEOUT    0x09        ; Standard timeout
%define FDPT_FMT_TIMEOUT    0x0A        ; Format timeout
%define FDPT_CHK_TIMEOUT    0x0B        ; Check timeout
%define FDPT_LANDING        0x0C        ; Landing zone (word)
%define FDPT_SECTORS        0x0E        ; Sectors per track
%define FDPT_RESERVED3      0x0F        ; Reserved

%define FDPT_SIZE           16          ; Parameter table size

;------------------------------------------------------------------------------
; FDPT Control Byte Bits
;------------------------------------------------------------------------------
%define FDPT_CTL_DISABLE_RETRY  0x80    ; Disable ECC retry
%define FDPT_CTL_MORE_8_HEADS   0x08    ; More than 8 heads

;------------------------------------------------------------------------------
; Interrupt Vectors (in segment 0000h)
;------------------------------------------------------------------------------
%define IVT_SEG             0x0000      ; Interrupt Vector Table segment

; Hard disk vectors
%define INT_13_VECTOR       0x004C      ; INT 13h vector (13h * 4)
%define INT_40_VECTOR       0x0100      ; INT 40h vector (old INT 13h for floppy)
%define INT_41_VECTOR       0x0104      ; INT 41h vector (HD0 FDPT pointer)
%define INT_46_VECTOR       0x0118      ; INT 46h vector (HD1 FDPT pointer)
%define INT_19_VECTOR       0x0064      ; INT 19h vector (bootstrap)

;------------------------------------------------------------------------------
; Extended BDA (EBDA) for LBA Support
;------------------------------------------------------------------------------
; Some systems have an Extended BIOS Data Area starting at the top of
; conventional memory. LBA parameter tables may be stored there.
; The EBDA segment is stored at 40:0E.

%define BDA_EBDA_SEG        0x000E      ; EBDA segment pointer (word at 40:0E)

;------------------------------------------------------------------------------
; CMOS RTC/NVRAM Ports (for reading drive type)
;------------------------------------------------------------------------------
%define CMOS_ADDR           0x70        ; CMOS address port
%define CMOS_DATA           0x71        ; CMOS data port

; CMOS drive type locations
%define CMOS_HD_TYPE        0x12        ; Hard disk types (high nibble=HD0, low=HD1)
%define CMOS_HD0_EXT_TYPE   0x19        ; HD0 extended type if CMOS_HD_TYPE=0Fh
%define CMOS_HD1_EXT_TYPE   0x1A        ; HD1 extended type if CMOS_HD_TYPE=F0h

;------------------------------------------------------------------------------
; POST/Diagnostic Ports
;------------------------------------------------------------------------------
%define POST_PORT           0x80        ; POST diagnostic port

;------------------------------------------------------------------------------
; Keyboard Controller (for A20 gate)
;------------------------------------------------------------------------------
%define KBC_DATA            0x60        ; Keyboard controller data port
%define KBC_STATUS          0x64        ; Keyboard controller status/command

;------------------------------------------------------------------------------
; INT 13h Status Codes (stored in BDA_HDD_STATUS)
;------------------------------------------------------------------------------
%define HDD_ERR_NONE        0x00        ; No error
%define HDD_ERR_BAD_CMD     0x01        ; Invalid command
%define HDD_ERR_ADDR_MARK   0x02        ; Address mark not found
%define HDD_ERR_WRITE_PROT  0x03        ; Write protected (not used for HD)
%define HDD_ERR_SECT_NOT_FND 0x04       ; Sector not found
%define HDD_ERR_RESET_FAIL  0x05        ; Reset failed
%define HDD_ERR_MEDIA_CHG   0x06        ; Media changed (diskette)
%define HDD_ERR_BAD_PARAM   0x07        ; Invalid parameter
%define HDD_ERR_DMA_OVERRUN 0x08        ; DMA overrun
%define HDD_ERR_DMA_BOUNDARY 0x09       ; DMA boundary error (64KB)
%define HDD_ERR_BAD_SECTOR  0x0A        ; Bad sector flag
%define HDD_ERR_BAD_TRACK   0x0B        ; Bad track flag
%define HDD_ERR_MEDIA_TYPE  0x0C        ; Media type not found
%define HDD_ERR_BAD_CYL     0x0D        ; Invalid number of sectors
%define HDD_ERR_CTRL_DATA   0x0E        ; Control data address mark
%define HDD_ERR_DMA_ARB     0x0F        ; DMA arbitration error
%define HDD_ERR_BAD_CRC     0x10        ; CRC/ECC error
%define HDD_ERR_ECC_CORR    0x11        ; ECC corrected data
%define HDD_ERR_CONTROLLER  0x20        ; Controller failure
%define HDD_ERR_SEEK        0x40        ; Seek failure
%define HDD_ERR_TIMEOUT     0x80        ; Timeout
%define HDD_ERR_NOT_READY   0xAA        ; Drive not ready
%define HDD_ERR_UNDEFINED   0xBB        ; Undefined error
%define HDD_ERR_WRITE_FAULT 0xCC        ; Write fault
%define HDD_ERR_STATUS      0xE0        ; Status error
%define HDD_ERR_SENSE       0xFF        ; Sense operation failed

;------------------------------------------------------------------------------
; Macros for BDA Access
;------------------------------------------------------------------------------

; Read byte from BDA
; Input: offset in BDA
; Output: AL = byte value, segment destroyed
%macro BDA_READ_BYTE 1
    push    es
    mov     ax, BDA_SEG
    mov     es, ax
    mov     al, [es:%1]
    pop     es
%endmacro

; Write byte to BDA
; Input: offset in BDA, value in AL
%macro BDA_WRITE_BYTE 1
    push    es
    push    ax
    mov     ax, BDA_SEG
    mov     es, ax
    pop     ax
    mov     [es:%1], al
    pop     es
%endmacro

; Read word from BDA
; Input: offset in BDA
; Output: AX = word value
%macro BDA_READ_WORD 1
    push    es
    mov     ax, BDA_SEG
    mov     es, ax
    mov     ax, [es:%1]
    pop     es
%endmacro

%endif ; BDA_INC
