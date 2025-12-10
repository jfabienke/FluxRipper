;==============================================================================
; FluxRipper FDD BIOS - Drive Profile Definitions
;==============================================================================
; FPGA DRIVE_PROFILE register bit definitions for auto-detection.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;------------------------------------------------------------------------------
; DRIVE_PROFILE Register Layout (32-bit)
;------------------------------------------------------------------------------
; Bits [1:0]   - Form Factor
; Bits [3:2]   - Density Capability
; Bits [5:4]   - Track Density
; Bits [8:6]   - Encoding Type
; Bits [13:9]  - Reserved
; Bit  [14]    - Profile Locked (high-confidence)
; Bit  [15]    - Profile Valid (detection complete)
; Bits [23:16] - RPM / 10 (30=300 RPM, 36=360 RPM)
; Bits [31:24] - Quality Score (0-255)

;------------------------------------------------------------------------------
; Form Factor (bits 1:0)
;------------------------------------------------------------------------------
%define FORM_UNKNOWN    0x00            ; Unknown form factor
%define FORM_35         0x01            ; 3.5" drive
%define FORM_525        0x02            ; 5.25" drive
%define FORM_8          0x03            ; 8" drive

%define FORM_MASK       0x03
%define FORM_SHIFT      0

;------------------------------------------------------------------------------
; Density Capability (bits 3:2)
;------------------------------------------------------------------------------
%define DENS_SD         0x00            ; Single Density (FM encoding)
%define DENS_DD         0x01            ; Double Density (MFM encoding)
%define DENS_HD         0x02            ; High Density (MFM encoding)
%define DENS_ED         0x03            ; Extended Density (perpendicular MFM)

%define DENS_MASK       0x0C
%define DENS_SHIFT      2

;------------------------------------------------------------------------------
; Track Density (bits 5:4)
;------------------------------------------------------------------------------
%define TRACK_40        0x00            ; 40 tracks (DD 5.25")
%define TRACK_80        0x01            ; 80 tracks (HD, 3.5")
%define TRACK_77        0x02            ; 77 tracks (8")
%define TRACK_UNKNOWN   0x03            ; Unknown

%define TRACK_MASK      0x30
%define TRACK_SHIFT     4

;------------------------------------------------------------------------------
; Encoding Type (bits 8:6)
;------------------------------------------------------------------------------
%define ENC_MFM         0x00            ; MFM (PC standard)
%define ENC_FM          0x01            ; FM (single density)
%define ENC_GCR_CBM     0x02            ; GCR (Commodore)
%define ENC_GCR_APPLE   0x03            ; GCR (Apple II)
%define ENC_M2FM        0x04            ; M2FM (older systems)
%define ENC_UNKNOWN     0x07            ; Unknown

%define ENC_MASK        0x1C0
%define ENC_SHIFT       6

;------------------------------------------------------------------------------
; Status Flags (bits 15:14)
;------------------------------------------------------------------------------
%define PROFILE_LOCKED  0x4000          ; Bit 14: High-confidence detection
%define PROFILE_VALID   0x8000          ; Bit 15: Detection complete

;------------------------------------------------------------------------------
; RPM (bits 23:16) - value is RPM/10
;------------------------------------------------------------------------------
%define RPM_MASK        0x00FF0000
%define RPM_SHIFT       16
%define RPM_300         30              ; 300 RPM (3.5", 5.25" DD)
%define RPM_360         36              ; 360 RPM (5.25" HD, 8")

;------------------------------------------------------------------------------
; Quality Score (bits 31:24)
;------------------------------------------------------------------------------
%define QUAL_MASK       0xFF000000
%define QUAL_SHIFT      24
%define QUAL_THRESHOLD  128             ; Minimum acceptable quality

;------------------------------------------------------------------------------
; BIOS Drive Type Codes (returned by INT 13h AH=08h)
;------------------------------------------------------------------------------
; Standard BIOS drive type codes (01h-06h)
%define DTYPE_NONE      0x00            ; No drive
%define DTYPE_360K      0x01            ; 5.25" 360K DD (40T, 9spt, 512B)
%define DTYPE_1200K     0x02            ; 5.25" 1.2M HD (80T, 15spt, 512B)
%define DTYPE_720K      0x03            ; 3.5" 720K DD (80T, 9spt, 512B)
%define DTYPE_1440K     0x04            ; 3.5" 1.44M HD (80T, 18spt, 512B)
%define DTYPE_2880K     0x06            ; 3.5" 2.88M ED (80T, 36spt, 512B)

; FluxRipper Extended Type Codes (07h-0Fh) for 8" drives
%define DTYPE_8_SD      0x07            ; 8" SD FM  250K (77T, 26spt, 128B, 1 head)
%define DTYPE_8_DD      0x08            ; 8" DD MFM 1.2M (77T, 8spt, 1024B, 2 heads)
%define DTYPE_8_PC      0x09            ; 8" PC-compat MFM (77T, 15spt, 512B, 2 heads)
%define DTYPE_8_CPM     0x0A            ; 8" CP/M MFM (77T, 26spt, 256B, 1 head)

; Legacy aliases for compatibility
%define DTYPE_8_250K    DTYPE_8_SD      ; Alias: 8" 250K = 8" SD
%define DTYPE_8_500K    DTYPE_8_DD      ; Alias: 8" 500K = 8" DD

;------------------------------------------------------------------------------
; Sector Size Codes (for FDC commands and profile bits 10:9)
;------------------------------------------------------------------------------
%define SECSIZE_128     0x00            ; 128 bytes per sector (8" SD)
%define SECSIZE_256     0x01            ; 256 bytes per sector (CP/M)
%define SECSIZE_512     0x02            ; 512 bytes per sector (PC standard)
%define SECSIZE_1024    0x03            ; 1024 bytes per sector (8" DD)

%define SECSIZE_MASK    0x0600          ; Bits 10:9
%define SECSIZE_SHIFT   9

;------------------------------------------------------------------------------
; Drive Parameter Table Offsets
;------------------------------------------------------------------------------
; Each drive type has a parameter block for INT 13h AH=08h
%define DPT_SPECIFY1    0               ; Specify byte 1 (SRT/HUT)
%define DPT_SPECIFY2    1               ; Specify byte 2 (HLT/ND)
%define DPT_MOTOR_OFF   2               ; Motor off timeout (ticks)
%define DPT_SEC_SIZE    3               ; Sector size code (0=128, 1=256, 2=512, 3=1024)
%define DPT_EOT         4               ; End of track (sectors/track)
%define DPT_GAP_RW      5               ; Gap length for R/W
%define DPT_DTL         6               ; Data length (if sec size=0)
%define DPT_GAP_FMT     7               ; Gap length for format
%define DPT_FILL_BYTE   8               ; Format fill byte
%define DPT_HEAD_SETTLE 9               ; Head settle time (ms)
%define DPT_MOTOR_START 10              ; Motor start time (1/8 sec)
%define DPT_SIZE        11              ; Size of DPT
