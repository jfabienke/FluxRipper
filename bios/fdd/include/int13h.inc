;==============================================================================
; FluxRipper FDD BIOS - INT 13h Function Definitions
;==============================================================================
; BIOS INT 13h diskette function codes and status values.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;------------------------------------------------------------------------------
; INT 13h Function Codes (AH register)
;------------------------------------------------------------------------------
%define FN_RESET            0x00        ; Reset disk system
%define FN_GET_STATUS       0x01        ; Get status of last operation
%define FN_READ_SECTORS     0x02        ; Read sectors
%define FN_WRITE_SECTORS    0x03        ; Write sectors
%define FN_VERIFY_SECTORS   0x04        ; Verify sectors
%define FN_FORMAT_TRACK     0x05        ; Format track
%define FN_GET_PARAMS       0x08        ; Get drive parameters
%define FN_INIT_DPT         0x09        ; Initialize drive pair characteristics
%define FN_READ_LONG        0x0A        ; Read long (sector + ECC)
%define FN_WRITE_LONG       0x0B        ; Write long (sector + ECC)
%define FN_SEEK             0x0C        ; Seek
%define FN_RESET_ALT        0x0D        ; Alternate disk reset
%define FN_READ_BUFFER      0x0E        ; Read sector buffer
%define FN_WRITE_BUFFER     0x0F        ; Write sector buffer
%define FN_TEST_READY       0x10        ; Test drive ready
%define FN_RECALIBRATE      0x11        ; Recalibrate
%define FN_CONTROLLER_RAM   0x12        ; Controller RAM diagnostic
%define FN_DRIVE_DIAG       0x13        ; Drive diagnostic
%define FN_CONTROLLER_DIAG  0x14        ; Controller diagnostic
%define FN_GET_DISK_TYPE    0x15        ; Get disk type
%define FN_DISK_CHANGE      0x16        ; Disk change status
%define FN_SET_DISK_TYPE    0x17        ; Set diskette type
%define FN_SET_MEDIA_TYPE   0x18        ; Set media type for format

;------------------------------------------------------------------------------
; INT 13h Status Codes (returned in AH)
;------------------------------------------------------------------------------
%define STAT_SUCCESS        0x00        ; Success
%define STAT_INVALID_CMD    0x01        ; Invalid command
%define STAT_ADDR_MARK_NF   0x02        ; Address mark not found
%define STAT_WRITE_PROTECT  0x03        ; Disk write protected
%define STAT_SECTOR_NF      0x04        ; Sector not found
%define STAT_RESET_FAIL     0x05        ; Reset failed
%define STAT_DISK_CHANGE    0x06        ; Disk changed
%define STAT_DRV_PARAM_ERR  0x07        ; Drive parameter activity failed
%define STAT_DMA_OVERRUN    0x08        ; DMA overrun
%define STAT_DMA_BOUNDARY   0x09        ; DMA crossed 64KB boundary
%define STAT_BAD_SECTOR     0x0A        ; Bad sector detected
%define STAT_BAD_TRACK      0x0B        ; Bad track detected
%define STAT_MEDIA_TYPE_NF  0x0C        ; Media type not found
%define STAT_INVALID_SEC    0x0D        ; Invalid number of sectors on format
%define STAT_CTRL_DATA_AM   0x0E        ; Control data address mark detected
%define STAT_DMA_ARB_ERR    0x0F        ; DMA arbitration level out of range
%define STAT_CRC_ERROR      0x10        ; Uncorrectable CRC or ECC error
%define STAT_CORRECTED      0x11        ; Data ECC corrected
%define STAT_CTRL_FAILURE   0x20        ; Controller failure
%define STAT_SEEK_FAIL      0x40        ; Seek failed
%define STAT_TIMEOUT        0x80        ; Timeout (not ready)
%define STAT_NOT_READY      0xAA        ; Drive not ready
%define STAT_UNDEFINED      0xBB        ; Undefined error
%define STAT_WRITE_FAULT    0xCC        ; Write fault
%define STAT_STATUS_ERROR   0xE0        ; Status register error
%define STAT_SENSE_FAIL     0xFF        ; Sense operation failed

;------------------------------------------------------------------------------
; BIOS Data Area Addresses (segment 0040h)
;------------------------------------------------------------------------------
%define BDA_SEG             0x0040      ; BIOS Data Area segment

%define BDA_EQUIPMENT       0x10        ; Equipment word (word at 40:10)
%define BDA_FLOPPY_STATUS   0x41        ; Diskette status (byte)
%define BDA_FLOPPY_MOTOR    0x3F        ; Motor status (byte)
%define BDA_MOTOR_COUNT     0x40        ; Motor timeout counter (byte)
%define BDA_FLOPPY_RECAL    0x3E        ; Recalibrate status (byte)
%define BDA_CURR_TRACK      0x94        ; Current track (4 bytes, 1 per drive)
%define BDA_DRIVE_TYPES     0x8F        ; Drive types nibbles (byte)
%define BDA_MEDIA_STATE     0x90        ; Media state (4 bytes)
%define BDA_DISK_INT_FLAG   0x3E        ; Diskette interrupt flag

;------------------------------------------------------------------------------
; INT 13h Drive Number Ranges
;------------------------------------------------------------------------------
%define DRIVE_FDD_FIRST     0x00        ; First floppy drive
%define DRIVE_FDD_LAST      0x03        ; Last floppy drive
%define DRIVE_HDD_FIRST     0x80        ; First hard drive
%define DRIVE_HDD_LAST      0x81        ; Last hard drive

;------------------------------------------------------------------------------
; Media State Bits (BDA 0x90-0x93)
;------------------------------------------------------------------------------
%define MS_DATA_RATE        0x07        ; Data rate mask (bits 0-2)
%define MS_DOUBLE_STEP      0x20        ; Double stepping required
%define MS_MEDIA_KNOWN      0x10        ; Media type known
%define MS_DATA_RATE_0      0x00        ; 500 Kbps
%define MS_DATA_RATE_1      0x40        ; 300 Kbps
%define MS_DATA_RATE_2      0x80        ; 250 Kbps
%define MS_DATA_RATE_3      0xC0        ; 1 Mbps (reserved)

;------------------------------------------------------------------------------
; Disk Change Line
;------------------------------------------------------------------------------
%define DCL_MASK            0x80        ; Disk change line mask
