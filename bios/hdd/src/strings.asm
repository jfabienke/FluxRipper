;==============================================================================
; FluxRipper HDD BIOS - String Constants and Messages
;==============================================================================
; All user-visible strings for the BIOS.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Initialization Messages
;==============================================================================

msg_banner:
    db      0x0D, 0x0A
    db      "FluxRipper HDD BIOS v1.0", 0x0D, 0x0A
%if BUILD_16KB
    db      "ST-506/ESDI Controller (16KB)", 0x0D, 0x0A
%else
    db      "ST-506 Controller (8KB)", 0x0D, 0x0A
%endif
    db      "(c) 2025 FluxRipper Project", 0x0D, 0x0A
    db      0

msg_ready:
    db      "Ready.", 0x0D, 0x0A, 0

msg_error:
    db      "Init failed!", 0x0D, 0x0A, 0

msg_drives_found:
    db      "Drives: ", 0

msg_drives_suffix:
    db      " detected", 0

msg_drive0:
    db      "  HD0: ", 0

msg_drive1:
    db      "  HD1: ", 0

;==============================================================================
; Interface Type Strings
;==============================================================================

msg_mfm:
    db      " MFM", 0

msg_rll:
    db      " RLL", 0

msg_esdi:
    db      " ESDI", 0

;==============================================================================
; Personality Strings
;==============================================================================

msg_wd1002:
    db      "WD1002 (XT MFM)", 0

msg_wd1003:
    db      "WD1003 (AT MFM)", 0

msg_wd1006:
    db      "WD1006 (AT RLL)", 0

msg_wd1007:
    db      "WD1007 (AT ESDI)", 0

;==============================================================================
; Error Messages
;==============================================================================

msg_err_timeout:
    db      "Timeout", 0

msg_err_not_ready:
    db      "Drive not ready", 0

msg_err_seek:
    db      "Seek error", 0

msg_err_read:
    db      "Read error", 0

msg_err_write:
    db      "Write error", 0

msg_err_crc:
    db      "CRC error", 0

msg_err_controller:
    db      "Controller error", 0

msg_err_no_drive:
    db      "No drive", 0

;==============================================================================
; Discovery Messages
;==============================================================================

msg_discovery_wait:
    db      "Waiting for drive discovery...", 0

msg_discovery_done:
    db      "Discovery complete", 0x0D, 0x0A, 0

msg_discovery_fail:
    db      "Discovery failed", 0x0D, 0x0A, 0

;==============================================================================
; Boot Messages
;==============================================================================

msg_booting:
    db      "Booting from HD", 0

msg_boot_fail:
    db      "Boot failed", 0x0D, 0x0A, 0

msg_no_boot:
    db      "No bootable partition", 0x0D, 0x0A, 0

msg_invalid_mbr:
    db      "Invalid MBR signature", 0x0D, 0x0A, 0

;==============================================================================
; Diagnostic Messages (16KB only)
;==============================================================================

%if BUILD_16KB

msg_diag_menu:
    db      0x0D, 0x0A
    db      "=== FluxRipper Diagnostics ===", 0x0D, 0x0A
    db      " 1. Surface Scan", 0x0D, 0x0A
    db      " 2. Seek Test", 0x0D, 0x0A
    db      " 3. Flux Histogram", 0x0D, 0x0A
    db      " 4. Error Log", 0x0D, 0x0A
    db      " 5. Spindle Test", 0x0D, 0x0A
    db      " 6. ESDI Query", 0x0D, 0x0A
    db      " 7. Export Report", 0x0D, 0x0A
    db      " 0. Exit", 0x0D, 0x0A
    db      "Select: ", 0

msg_press_f3:
    db      "Press F3 for diagnostics", 0x0D, 0x0A, 0

msg_surface_scan:
    db      "Surface Scan - ", 0

msg_seek_test:
    db      "Seek Test - ", 0

msg_flux_hist:
    db      "Flux Histogram", 0x0D, 0x0A, 0

msg_error_log:
    db      "Error Log:", 0x0D, 0x0A, 0

msg_spindle:
    db      "Spindle RPM: ", 0

msg_esdi_query:
    db      "ESDI Drive Query:", 0x0D, 0x0A, 0

msg_cylinder:
    db      "Cyl: ", 0

msg_head:
    db      " Hd: ", 0

msg_sector:
    db      " Sec: ", 0

msg_pass:
    db      " PASS", 0x0D, 0x0A, 0

msg_fail:
    db      " FAIL", 0x0D, 0x0A, 0

msg_testing:
    db      "Testing...", 0

msg_complete:
    db      "Complete", 0x0D, 0x0A, 0

msg_rpm:
    db      " RPM", 0

msg_percent:
    db      "%", 0

%endif

;==============================================================================
; Setup Utility Messages (16KB only)
;==============================================================================

%if BUILD_16KB

msg_setup_banner:
    db      0x0D, 0x0A
    db      "=== FluxRipper Setup ===", 0x0D, 0x0A, 0

msg_setup_drive:
    db      "Drive Configuration:", 0x0D, 0x0A, 0

msg_setup_type:
    db      "  Type: ", 0

msg_setup_cyls:
    db      "  Cylinders: ", 0

msg_setup_heads:
    db      "  Heads: ", 0

msg_setup_spt:
    db      "  Sectors/Track: ", 0

msg_setup_capacity:
    db      "  Capacity: ", 0

msg_setup_mb:
    db      " MB", 0

msg_setup_save:
    db      0x0D, 0x0A, "Save changes? (Y/N): ", 0

msg_setup_saved:
    db      "Configuration saved.", 0x0D, 0x0A, 0

msg_setup_cancelled:
    db      "Cancelled.", 0x0D, 0x0A, 0

%endif

;==============================================================================
; Numeric Formatting
;==============================================================================

msg_slash:
    db      "/", 0

msg_colon:
    db      ": ", 0

msg_space:
    db      " ", 0

msg_crlf:
    db      0x0D, 0x0A, 0

;==============================================================================
; Print Personality String
;==============================================================================
; Prints the name of the detected WD personality.
;
; Input:  AL = personality code (0-3)
; Destroys: SI
;==============================================================================
print_personality:
    push    ax

    cmp     al, PERSONALITY_WD1002
    jne     .check_1003
    mov     si, msg_wd1002
    jmp     .print

.check_1003:
    cmp     al, PERSONALITY_WD1003
    jne     .check_1006
    mov     si, msg_wd1003
    jmp     .print

.check_1006:
    cmp     al, PERSONALITY_WD1006
    jne     .check_1007
    mov     si, msg_wd1006
    jmp     .print

.check_1007:
    mov     si, msg_wd1007

.print:
    call    print_string

    pop     ax
    ret

;==============================================================================
; Print Error Message
;==============================================================================
; Prints error description based on INT 13h status code.
;
; Input:  AH = status code
; Destroys: SI
;==============================================================================
print_error_msg:
    push    ax

    cmp     ah, ST_TIMEOUT
    jne     .check_not_ready
    mov     si, msg_err_timeout
    jmp     .print

.check_not_ready:
    cmp     ah, ST_NOT_READY
    jne     .check_seek
    mov     si, msg_err_not_ready
    jmp     .print

.check_seek:
    cmp     ah, ST_SEEK_ERROR
    jne     .check_crc
    mov     si, msg_err_seek
    jmp     .print

.check_crc:
    cmp     ah, ST_CRC_ERROR
    jne     .check_controller
    mov     si, msg_err_crc
    jmp     .print

.check_controller:
    cmp     ah, ST_CONTROLLER
    jne     .default
    mov     si, msg_err_controller
    jmp     .print

.default:
    ; Print hex code for unknown errors
    mov     al, ah
    call    print_hex_byte
    jmp     .done

.print:
    call    print_string

.done:
    pop     ax
    ret
