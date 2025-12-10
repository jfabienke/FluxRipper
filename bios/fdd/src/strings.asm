;==============================================================================
; FluxRipper FDD BIOS - String Constants
;==============================================================================
; Messages displayed during initialization and operation.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;------------------------------------------------------------------------------
; Initialization Messages
;------------------------------------------------------------------------------
msg_banner:
    db      13, 10
    db      "FluxRipper FDD BIOS v1.0", 13, 10
    db      "(c) 2025 FluxRipper Project", 13, 10
    db      0

msg_ready:
    db      "Ready.", 13, 10
    db      0

msg_error:
    db      "ERROR: Drive detection failed!", 13, 10
    db      0

msg_drives_header:
    db      "Detected drives:", 13, 10
    db      0

msg_drive_prefix:
    db      "  Drive ", 0

msg_auto_detect:
    db      " (auto)", 0

msg_no_drives:
    db      "  No drives detected.", 13, 10
    db      0

msg_crlf:
    db      13, 10, 0

;------------------------------------------------------------------------------
; Status Messages
;------------------------------------------------------------------------------
msg_reading:
    db      "Reading...", 0

msg_writing:
    db      "Writing...", 0

msg_formatting:
    db      "Formatting...", 0

msg_seeking:
    db      "Seeking...", 0

;------------------------------------------------------------------------------
; Error Messages
;------------------------------------------------------------------------------
msg_err_timeout:
    db      "Timeout", 0

msg_err_crc:
    db      "CRC Error", 0

msg_err_sector:
    db      "Sector Not Found", 0

msg_err_write_prot:
    db      "Write Protected", 0

msg_err_addr_mark:
    db      "Address Mark Not Found", 0

msg_err_dma:
    db      "DMA Error", 0

;------------------------------------------------------------------------------
; Drive Type Names (ASCII)
;------------------------------------------------------------------------------
; Note: The main type strings are in detect.asm
; These are for verbose display

msg_type_360k:
    db      "360K 5.25-inch Double Density", 0

msg_type_1200k:
    db      "1.2M 5.25-inch High Density", 0

msg_type_720k:
    db      "720K 3.5-inch Double Density", 0

msg_type_1440k:
    db      "1.44M 3.5-inch High Density", 0

msg_type_2880k:
    db      "2.88M 3.5-inch Extended Density", 0

msg_type_8_sd:
    db      "250K 8-inch Single Density", 0

msg_type_8_dd:
    db      "500K 8-inch Double Density", 0

;------------------------------------------------------------------------------
; Profile Field Names (for diagnostics)
;------------------------------------------------------------------------------
%if BUILD_16KB && ENABLE_DIAG

msg_form_factor:
    db      "Form: ", 0

msg_density:
    db      "Density: ", 0

msg_tracks:
    db      "Tracks: ", 0

msg_encoding:
    db      "Encoding: ", 0

msg_rpm:
    db      "RPM: ", 0

msg_quality:
    db      "Quality: ", 0

; Form factor values
msg_form_35:
    db      "3.5''", 0
msg_form_525:
    db      "5.25''", 0
msg_form_8:
    db      "8''", 0
msg_form_unknown:
    db      "Unknown", 0

; Density values
msg_dens_dd:
    db      "DD", 0
msg_dens_hd:
    db      "HD", 0
msg_dens_ed:
    db      "ED", 0

; Track counts
msg_track_40:
    db      "40", 0
msg_track_80:
    db      "80", 0
msg_track_77:
    db      "77", 0

; Encoding types
msg_enc_mfm:
    db      "MFM", 0
msg_enc_fm:
    db      "FM", 0
msg_enc_gcr_cbm:
    db      "GCR-CBM", 0
msg_enc_gcr_apple:
    db      "GCR-Apple", 0
msg_enc_m2fm:
    db      "M2FM", 0

%endif ; BUILD_16KB && ENABLE_DIAG
