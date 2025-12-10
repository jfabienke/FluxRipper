;==============================================================================
; FluxRipper HDD BIOS - INT 13h Function Code Definitions
;==============================================================================
; Defines function codes and register conventions for INT 13h disk services.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%ifndef INT13H_INC
%define INT13H_INC

;------------------------------------------------------------------------------
; INT 13h Basic Functions (00h-08h)
;------------------------------------------------------------------------------
; These are supported by all builds (8KB and 16KB)

%define FN_RESET            0x00    ; Reset disk system
%define FN_GET_STATUS       0x01    ; Get status of last operation
%define FN_READ_SECTORS     0x02    ; Read sectors into memory
%define FN_WRITE_SECTORS    0x03    ; Write sectors from memory
%define FN_VERIFY_SECTORS   0x04    ; Verify sectors (compare CRC)
%define FN_FORMAT_TRACK     0x05    ; Format track
%define FN_FORMAT_BAD       0x06    ; Format track with bad sectors (XT only)
%define FN_FORMAT_DRIVE     0x07    ; Format entire drive (XT only)
%define FN_GET_PARAMETERS   0x08    ; Get drive parameters

;------------------------------------------------------------------------------
; INT 13h Extended Functions (09h-15h)
;------------------------------------------------------------------------------
; These are supported by 16KB build only

%define FN_INIT_DRIVE       0x09    ; Initialize drive parameters
%define FN_READ_LONG        0x0A    ; Read sectors with ECC
%define FN_WRITE_LONG       0x0B    ; Write sectors with ECC
%define FN_SEEK             0x0C    ; Seek to cylinder
%define FN_RESET_ALTERNATE  0x0D    ; Alternate disk reset
%define FN_READ_BUFFER      0x0E    ; Read sector buffer (diagnostics)
%define FN_WRITE_BUFFER     0x0F    ; Write sector buffer (diagnostics)
%define FN_TEST_READY       0x10    ; Test drive ready
%define FN_RECALIBRATE      0x11    ; Recalibrate drive
%define FN_RAM_DIAGNOSTIC   0x12    ; Controller RAM diagnostic
%define FN_DRIVE_DIAGNOSTIC 0x13    ; Drive diagnostic
%define FN_CTRL_DIAGNOSTIC  0x14    ; Controller diagnostic
%define FN_GET_DISK_TYPE    0x15    ; Get disk type

;------------------------------------------------------------------------------
; INT 13h LBA Extensions (41h-48h)
;------------------------------------------------------------------------------
; IBM/Microsoft Extended INT 13h - 16KB build only

%define FN_CHECK_EXTENSIONS 0x41    ; Installation check
%define FN_EXT_READ         0x42    ; Extended read
%define FN_EXT_WRITE        0x43    ; Extended write
%define FN_EXT_VERIFY       0x44    ; Extended verify
%define FN_LOCK_UNLOCK      0x45    ; Lock/unlock media
%define FN_EJECT            0x46    ; Eject media
%define FN_EXT_SEEK         0x47    ; Extended seek
%define FN_GET_EXT_PARAMS   0x48    ; Get extended drive parameters

;------------------------------------------------------------------------------
; Register Conventions for INT 13h Calls
;------------------------------------------------------------------------------
; Input (for sector operations):
;   AH    = Function number
;   AL    = Sector count
;   CH    = Cylinder low 8 bits
;   CL    = Sector (bits 0-5) + Cylinder high (bits 6-7)
;   DH    = Head number
;   DL    = Drive number (80h = first HD, 81h = second HD)
;   ES:BX = Buffer address (for read/write)
;
; Output:
;   AH    = Status code (0 = success)
;   AL    = Sectors transferred (for read/write/verify)
;   CF    = 0 if success, 1 if error
;
; Note: CHS is encoded as follows:
;   Cylinder = (CL >> 6) | CH  (10 bits, 0-1023)
;   Head     = DH              (8 bits, 0-255)
;   Sector   = CL & 0x3F       (6 bits, 1-63)

;------------------------------------------------------------------------------
; Status Codes (returned in AH)
;------------------------------------------------------------------------------
; These are stored in BDA at 0040:0074

%define ST_SUCCESS          0x00    ; No error
%define ST_BAD_COMMAND      0x01    ; Invalid function
%define ST_ADDR_MARK        0x02    ; Address mark not found
%define ST_WRITE_PROTECT    0x03    ; Write protected
%define ST_SECTOR_NOT_FOUND 0x04    ; Sector not found
%define ST_RESET_FAILED     0x05    ; Reset failed
%define ST_MEDIA_CHANGED    0x06    ; Media changed
%define ST_INIT_FAILED      0x07    ; Parameter activity failed
%define ST_DMA_OVERRUN      0x08    ; DMA overrun
%define ST_DMA_BOUNDARY     0x09    ; DMA crossed 64K boundary
%define ST_BAD_SECTOR       0x0A    ; Bad sector flag
%define ST_BAD_TRACK        0x0B    ; Bad track flag
%define ST_MEDIA_TYPE       0x0C    ; Media type not found
%define ST_INVALID_SECTORS  0x0D    ; Invalid number of sectors
%define ST_CONTROL_DATA     0x0E    ; Control data address mark
%define ST_DMA_ERROR        0x0F    ; DMA arbitration error
%define ST_CRC_ERROR        0x10    ; CRC/ECC error (uncorrectable)
%define ST_ECC_CORRECTED    0x11    ; ECC corrected data
%define ST_CONTROLLER       0x20    ; Controller failure
%define ST_SEEK_ERROR       0x40    ; Seek failure
%define ST_TIMEOUT          0x80    ; Timeout
%define ST_NOT_READY        0xAA    ; Drive not ready
%define ST_UNDEFINED        0xBB    ; Undefined error
%define ST_WRITE_FAULT      0xCC    ; Write fault
%define ST_STATUS_ERROR     0xE0    ; Status error
%define ST_SENSE_FAILED     0xFF    ; Sense operation failed

;------------------------------------------------------------------------------
; Extended INT 13h Installation Check (Function 41h)
;------------------------------------------------------------------------------
; Input:
;   AH = 41h
;   BX = 55AAh (signature)
;   DL = drive number
;
; Output:
;   CF = 0 if extensions supported
;   AH = version (21h = 1.x, 30h = 2.x/EDD-1.1, etc.)
;   BX = AA55h (inverted signature)
;   CX = extension support bitmap

%define EXT_VER_1X          0x01    ; Version 1.x
%define EXT_VER_2X          0x20    ; Version 2.0
%define EXT_VER_21          0x21    ; Version 2.1
%define EXT_VER_30          0x30    ; Version 3.0 (EDD)

; CX extension bits
%define EXT_DAP             0x0001  ; Device Access Packet (read/write)
%define EXT_LOCK            0x0002  ; Lock/Unlock and Eject
%define EXT_EDD             0x0004  ; Enhanced Disk Drive support

;------------------------------------------------------------------------------
; Device Address Packet (DAP) Structure
;------------------------------------------------------------------------------
; Used by extended read/write functions (42h/43h)
;
; Offset  Size  Description
;   00h    1    Packet size (10h or 18h)
;   01h    1    Reserved (0)
;   02h    2    Sector count
;   04h    4    Buffer address (segment:offset)
;   08h    8    Starting LBA (64-bit)
;   10h    8    Flat address (if packet size = 18h)

%define DAP_SIZE_BASIC      0x10    ; 16-byte DAP
%define DAP_SIZE_EXTENDED   0x18    ; 24-byte DAP with flat address

struc DAP
    .size       resb 1
    .reserved   resb 1
    .count      resw 1
    .buffer     resd 1
    .lba        resq 1
    .flat_addr  resq 1              ; Only if size = 18h
endstruc

;------------------------------------------------------------------------------
; Extended Drive Parameters (Function 48h)
;------------------------------------------------------------------------------
; Offset  Size  Description
;   00h    2    Buffer size (1Ah minimum, 1Eh with EDD, 42h with path)
;   02h    2    Flags
;   04h    4    Physical cylinders
;   08h    4    Physical heads
;   0Ch    4    Physical sectors per track
;   10h    8    Total sectors (64-bit)
;   18h    2    Bytes per sector

struc EXT_PARAMS
    .size           resw 1
    .flags          resw 1
    .cylinders      resd 1
    .heads          resd 1
    .sectors        resd 1
    .total_sectors  resq 1
    .bytes_sector   resw 1
endstruc

;------------------------------------------------------------------------------
; Macros for INT 13h Handler
;------------------------------------------------------------------------------

; Save all registers for INT handler
%macro INT13_SAVE_REGS 0
    push    ds
    push    es
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp
%endmacro

; Restore all registers for INT handler
%macro INT13_RESTORE_REGS 0
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     es
    pop     ds
%endmacro

; Return from INT 13h with status
; Input: AL = status code
%macro INT13_RETURN 0
    mov     [bp + 8], ax            ; Store AH (status) in saved AX on stack
    ; Update BDA status
    push    es
    push    bx
    mov     bx, BDA_SEG
    mov     es, bx
    mov     [es:BDA_HDD_STATUS], ah
    pop     bx
    pop     es
    INT13_RESTORE_REGS
    ; Set/clear carry based on status
    or      ah, ah
    jz      %%no_error
    stc                             ; Set carry = error
    retf    2                       ; Return, discard flags
%%no_error:
    clc                             ; Clear carry = success
    retf    2
%endmacro

%endif ; INT13H_INC
