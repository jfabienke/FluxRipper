;==============================================================================
; FluxRipper FDD BIOS - FDC Register Definitions
;==============================================================================
; Intel 82077AA / NEC uPD765 compatible FDC register definitions.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;------------------------------------------------------------------------------
; FDC Register Offsets (from FDC base address)
;------------------------------------------------------------------------------
%define FDC_SRA         0x00            ; Status Register A (read)
%define FDC_SRB         0x01            ; Status Register B (read)
%define FDC_DOR         0x02            ; Digital Output Register (read/write)
%define FDC_TDR         0x03            ; Tape Drive Register (read/write)
%define FDC_MSR         0x04            ; Main Status Register (read)
%define FDC_DSR         0x04            ; Data Rate Select Register (write)
%define FDC_FIFO        0x05            ; Data FIFO (read/write)
%define FDC_DIR         0x07            ; Digital Input Register (read)
%define FDC_CCR         0x07            ; Configuration Control Register (write)

;------------------------------------------------------------------------------
; Digital Output Register (DOR) Bits
;------------------------------------------------------------------------------
%define DOR_DRIVE_SEL   0x03            ; Drive select mask (bits 0-1)
%define DOR_RESET       0x04            ; Reset (0=reset, 1=normal)
%define DOR_DMA_EN      0x08            ; DMA/IRQ enable
%define DOR_MOTOR_A     0x10            ; Motor A enable
%define DOR_MOTOR_B     0x20            ; Motor B enable
%define DOR_MOTOR_C     0x40            ; Motor C enable
%define DOR_MOTOR_D     0x80            ; Motor D enable

;------------------------------------------------------------------------------
; Main Status Register (MSR) Bits
;------------------------------------------------------------------------------
%define MSR_DRV0_BUSY   0x01            ; Drive 0 busy
%define MSR_DRV1_BUSY   0x02            ; Drive 1 busy
%define MSR_DRV2_BUSY   0x04            ; Drive 2 busy
%define MSR_DRV3_BUSY   0x08            ; Drive 3 busy
%define MSR_CMD_BUSY    0x10            ; Command busy
%define MSR_NON_DMA     0x20            ; Non-DMA mode
%define MSR_DIO         0x40            ; Data direction (1=read, 0=write)
%define MSR_RQM         0x80            ; Request for Master

;------------------------------------------------------------------------------
; Digital Input Register (DIR) Bits
;------------------------------------------------------------------------------
%define DIR_DSKCHG      0x80            ; Disk change (1=changed)

;------------------------------------------------------------------------------
; Data Rate Select Register (DSR) / CCR Values
;------------------------------------------------------------------------------
%define RATE_500K       0x00            ; 500 Kbps (HD 3.5", HD 5.25")
%define RATE_300K       0x01            ; 300 Kbps (DD 5.25" in HD drive)
%define RATE_250K       0x02            ; 250 Kbps (DD 3.5", DD 5.25")
%define RATE_1M         0x03            ; 1 Mbps (ED 3.5")

;------------------------------------------------------------------------------
; FDC Commands
;------------------------------------------------------------------------------
%define CMD_READ_DATA       0xE6        ; Read Data (MT, MF, SK)
%define CMD_READ_DEL_DATA   0xEC        ; Read Deleted Data (MT, MF, SK)
%define CMD_WRITE_DATA      0xC5        ; Write Data (MT, MF)
%define CMD_WRITE_DEL_DATA  0xC9        ; Write Deleted Data (MT, MF)
%define CMD_READ_TRACK      0x42        ; Read Track (MF)
%define CMD_VERIFY          0xF6        ; Verify (MT, MF, SK)
%define CMD_VERSION         0x10        ; Version
%define CMD_FORMAT_TRACK    0x4D        ; Format Track (MF)
%define CMD_SCAN_EQUAL      0xF1        ; Scan Equal (MT, MF, SK)
%define CMD_SCAN_LO_EQ      0xF9        ; Scan Low or Equal (MT, MF, SK)
%define CMD_SCAN_HI_EQ      0xFD        ; Scan High or Equal (MT, MF, SK)
%define CMD_RECALIBRATE     0x07        ; Recalibrate
%define CMD_SENSE_INT       0x08        ; Sense Interrupt Status
%define CMD_SPECIFY         0x03        ; Specify
%define CMD_SENSE_DRV       0x04        ; Sense Drive Status
%define CMD_SEEK            0x0F        ; Seek
%define CMD_CONFIGURE       0x13        ; Configure
%define CMD_RELATIVE_SEEK   0x8F        ; Relative Seek
%define CMD_DUMPREG         0x0E        ; Dump Registers
%define CMD_READ_ID         0x4A        ; Read ID (MF)
%define CMD_PERPENDICULAR   0x12        ; Perpendicular Mode
%define CMD_LOCK            0x94        ; Lock

;------------------------------------------------------------------------------
; FDC Command Option Bits
;------------------------------------------------------------------------------
%define OPT_MT          0x80            ; Multi-Track
%define OPT_MF          0x40            ; MFM mode (vs FM)
%define OPT_SK          0x20            ; Skip deleted data

;------------------------------------------------------------------------------
; Status Register 0 (ST0) Bits
;------------------------------------------------------------------------------
%define ST0_US          0x03            ; Unit Select mask
%define ST0_HD          0x04            ; Head Address
%define ST0_NR          0x08            ; Not Ready
%define ST0_EC          0x10            ; Equipment Check
%define ST0_SE          0x20            ; Seek End
%define ST0_IC          0xC0            ; Interrupt Code mask
%define ST0_IC_NORMAL   0x00            ; Normal termination
%define ST0_IC_ABNORMAL 0x40            ; Abnormal termination
%define ST0_IC_INVALID  0x80            ; Invalid command
%define ST0_IC_READY    0xC0            ; Ready changed

;------------------------------------------------------------------------------
; Status Register 1 (ST1) Bits
;------------------------------------------------------------------------------
%define ST1_MA          0x01            ; Missing Address Mark
%define ST1_NW          0x02            ; Not Writable
%define ST1_ND          0x04            ; No Data
%define ST1_OR          0x10            ; Overrun
%define ST1_DE          0x20            ; Data Error (CRC)
%define ST1_EN          0x80            ; End of Cylinder

;------------------------------------------------------------------------------
; Status Register 2 (ST2) Bits
;------------------------------------------------------------------------------
%define ST2_MD          0x01            ; Missing Address Mark in Data
%define ST2_BC          0x02            ; Bad Cylinder
%define ST2_SN          0x04            ; Scan Not Satisfied
%define ST2_SH          0x08            ; Scan Equal Hit
%define ST2_WC          0x10            ; Wrong Cylinder
%define ST2_DD          0x20            ; Data Error in Data Field
%define ST2_CM          0x40            ; Control Mark

;------------------------------------------------------------------------------
; Status Register 3 (ST3) Bits
;------------------------------------------------------------------------------
%define ST3_US          0x03            ; Unit Select
%define ST3_HD          0x04            ; Head Address
%define ST3_TS          0x08            ; Two Side
%define ST3_T0          0x10            ; Track 0
%define ST3_RY          0x20            ; Ready
%define ST3_WP          0x40            ; Write Protected
%define ST3_FT          0x80            ; Fault
