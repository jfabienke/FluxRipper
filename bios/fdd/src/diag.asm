;==============================================================================
; FluxRipper FDD BIOS - Diagnostics Menu (16KB only)
;==============================================================================
; F3 diagnostic overlay for viewing drive profiles, FPGA instrumentation,
; and signal quality metrics.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%if BUILD_16KB && ENABLE_DIAG

;==============================================================================
; Diagnostics Entry Point
;==============================================================================
; Called when F3 is pressed during operation.
;==============================================================================
diag_menu:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    ds
    push    es

    push    cs
    pop     ds

    ; Display diagnostics header
    mov     si, diag_header
    call    print_string

    ; Show profile for each drive
    mov     cl, [num_drives]
    test    cl, cl
    jz      .no_drives

    xor     dl, dl                  ; Drive number
.drive_loop:
    push    cx

    ; Print drive number
    mov     si, msg_drive_prefix
    call    print_string
    mov     al, dl
    add     al, '0'
    mov     ah, 0x0E
    mov     bx, 0x0007
    int     0x10
    mov     al, ':'
    int     0x10
    mov     al, ' '
    int     0x10

    ; Get and display profile
    call    diag_show_profile

    ; Newline
    mov     si, msg_crlf
    call    print_string

    ; Show FPGA instrumentation for this drive
    call    diag_show_instrumentation

    pop     cx
    inc     dl
    loop    .drive_loop
    jmp     .wait_key

.no_drives:
    mov     si, msg_no_drives
    call    print_string

.wait_key:
    ; Show drive mapping
    call    diag_show_mapping

    ; Wait for keypress with menu options
    mov     si, diag_footer_menu
    call    print_string

.key_loop:
    xor     ah, ah
    int     0x16                    ; Wait for key

    ; Check for 'S' or 's' - swap A: and B:
    cmp     al, 'S'
    je      .do_swap
    cmp     al, 's'
    je      .do_swap

    ; Check for 'R' or 'r' - reset to default
    cmp     al, 'R'
    je      .do_reset
    cmp     al, 'r'
    je      .do_reset

    ; Check for 'C' or 'c' - controller config
    cmp     al, 'C'
    je      .do_config
    cmp     al, 'c'
    je      .do_config

    ; Check for ESC - exit
    cmp     al, 0x1B
    je      .exit

    ; Any other key also exits
    jmp     .exit

.do_swap:
    ; Swap A: and B: drive mapping
    call    swap_drive_ab
    ; Redisplay mapping
    call    diag_show_mapping
    jmp     .key_loop

.do_reset:
    ; Reset to default mapping
    call    setup_default_mapping
    ; Redisplay mapping
    call    diag_show_mapping
    jmp     .key_loop

.do_config:
    ; Show controller configuration menu
    call    diag_config_menu
    ; Redisplay main menu
    mov     si, diag_footer_menu
    call    print_string
    jmp     .key_loop

.exit:
    pop     es
    pop     ds
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Show Drive Profile
;==============================================================================
; Displays detailed profile information for a drive.
;
; Input:  DL = drive number
;==============================================================================
diag_show_profile:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Get profile
    call    get_drive_profile
    jc      .no_profile

    ; Display form factor
    mov     bl, 0                   ; Field: form factor
    call    get_profile_field
    mov     si, msg_form_35
    cmp     al, FORM_35
    je      .print_form
    mov     si, msg_form_525
    cmp     al, FORM_525
    je      .print_form
    mov     si, msg_form_8
    cmp     al, FORM_8
    je      .print_form
    mov     si, msg_form_unknown
.print_form:
    call    print_string
    mov     al, ' '
    mov     ah, 0x0E
    int     0x10

    ; Display density
    mov     bl, 1
    call    get_profile_field
    mov     si, msg_dens_dd
    cmp     al, DENS_DD
    je      .print_dens
    mov     si, msg_dens_hd
    cmp     al, DENS_HD
    je      .print_dens
    mov     si, msg_dens_ed
    cmp     al, DENS_ED
    je      .print_dens
    mov     si, msg_form_unknown
.print_dens:
    call    print_string
    mov     al, ' '
    mov     ah, 0x0E
    int     0x10

    ; Display track count
    mov     bl, 2
    call    get_profile_field
    mov     si, msg_track_40
    cmp     al, TRACK_40
    je      .print_track
    mov     si, msg_track_80
    cmp     al, TRACK_80
    je      .print_track
    mov     si, msg_track_77
    cmp     al, TRACK_77
    je      .print_track
    mov     si, msg_form_unknown
.print_track:
    call    print_string
    mov     al, 'T'
    mov     ah, 0x0E
    int     0x10
    mov     al, ' '
    int     0x10

    ; Display encoding
    mov     bl, 3
    call    get_profile_field
    mov     si, msg_enc_mfm
    cmp     al, ENC_MFM
    je      .print_enc
    mov     si, msg_enc_fm
    cmp     al, ENC_FM
    je      .print_enc
    mov     si, msg_enc_gcr_cbm
    cmp     al, ENC_GCR_CBM
    je      .print_enc
    mov     si, msg_enc_gcr_apple
    cmp     al, ENC_GCR_APPLE
    je      .print_enc
    mov     si, msg_form_unknown
.print_enc:
    call    print_string

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.no_profile:
    mov     si, msg_form_unknown
    call    print_string
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Show FPGA Instrumentation
;==============================================================================
; Displays detailed FPGA instrumentation data for a drive.
;
; Input:  DL = drive number
;==============================================================================
diag_show_instrumentation:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; Determine FDC base address based on drive number
    mov     bx, FDC_PRIMARY
    cmp     dl, 2
    jb      .got_base
    mov     bx, FDC_SECONDARY
.got_base:

    ; Display signal quality section
    mov     si, msg_instr_header
    call    print_string

    ; PLL Lock Status
    mov     si, msg_pll_lock
    call    print_string
    mov     dx, bx
    add     dx, INSTR_PLL_LOCK
    in      al, dx
    test    al, 0x01
    jz      .pll_unlocked
    mov     si, msg_locked
    call    print_string
    jmp     .show_signal_q
.pll_unlocked:
    mov     si, msg_unlocked
    call    print_string

.show_signal_q:
    ; Signal Quality Score
    mov     si, msg_signal_q
    call    print_string
    mov     dx, bx
    add     dx, INSTR_SIGNAL_Q
    in      al, dx
    call    print_dec_byte
    mov     si, msg_percent
    call    print_string

    ; Error Count
    mov     si, msg_err_count
    call    print_string
    mov     dx, bx
    add     dx, INSTR_ERR_COUNT
    in      al, dx
    mov     cl, al
    inc     dx
    in      al, dx
    mov     ch, al
    mov     ax, cx
    call    print_dec_word

    ; Sync Pattern Count
    mov     si, msg_crlf
    call    print_string
    mov     si, msg_indent
    call    print_string
    mov     si, msg_sync_cnt
    call    print_string
    mov     dx, bx
    add     dx, INSTR_SYNC_CNT
    in      al, dx
    mov     cl, al
    inc     dx
    in      al, dx
    mov     ch, al
    mov     ax, cx
    call    print_dec_word

    ; Flux Timing Analysis
    mov     si, msg_crlf
    call    print_string
    mov     si, msg_indent
    call    print_string
    mov     si, msg_flux_stats
    call    print_string

    ; Min flux interval
    mov     si, msg_flux_min
    call    print_string
    mov     dx, bx
    add     dx, INSTR_FLUX_MIN
    in      al, dx
    mov     cl, al
    inc     dx
    in      al, dx
    mov     ch, al
    mov     ax, cx
    call    print_dec_word
    mov     si, msg_ns
    call    print_string

    ; Max flux interval
    mov     si, msg_flux_max
    call    print_string
    mov     dx, bx
    add     dx, INSTR_FLUX_MAX
    in      al, dx
    mov     cl, al
    inc     dx
    in      al, dx
    mov     ch, al
    mov     ax, cx
    call    print_dec_word
    mov     si, msg_ns
    call    print_string

    ; Average flux interval
    mov     si, msg_crlf
    call    print_string
    mov     si, msg_indent
    call    print_string
    mov     si, msg_flux_avg
    call    print_string
    mov     dx, bx
    add     dx, INSTR_FLUX_AVG
    in      al, dx
    mov     cl, al
    inc     dx
    in      al, dx
    mov     ch, al
    mov     ax, cx
    call    print_dec_word
    mov     si, msg_ns
    call    print_string

    ; Jitter
    mov     si, msg_flux_jitt
    call    print_string
    mov     dx, bx
    add     dx, INSTR_FLUX_JITT
    in      al, dx
    call    print_dec_byte
    mov     si, msg_ns
    call    print_string

    ; RPM
    mov     si, msg_crlf
    call    print_string
    mov     si, msg_indent
    call    print_string
    mov     si, msg_rpm_disp
    call    print_string
    mov     dx, bx
    add     dx, INSTR_RPM
    in      al, dx
    mov     cl, al
    inc     dx
    in      al, dx
    mov     ch, al
    mov     ax, cx
    call    print_dec_word
    mov     si, msg_rpm_unit
    call    print_string

    ; Final newline
    mov     si, msg_crlf
    call    print_string

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Show Drive Mapping
;==============================================================================
; Displays current DOS drive letter to physical drive mapping.
;==============================================================================
diag_show_mapping:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; Header
    mov     si, msg_mapping_header
    call    print_string

    ; Show mapping for A: and B: (most relevant)
    xor     cx, cx                  ; CL = logical drive (0=A:, 1=B:)
.map_loop:
    cmp     cl, 2
    jae     .map_done               ; Only show A: and B:

    ; Print "  A: → "
    mov     si, msg_mapping_indent
    call    print_string
    mov     al, cl
    add     al, 'A'
    mov     ah, 0x0E
    mov     bx, 0x0007
    int     0x10
    mov     al, ':'
    int     0x10
    mov     al, ' '
    int     0x10

    ; Look up physical drive
    mov     bl, cl
    xor     bh, bh
    mov     al, [drive_map + bx]
    cmp     al, 0xFF
    je      .not_mapped

    ; Print "Drive X (type)"
    mov     si, msg_mapping_drive
    call    print_string
    add     al, '0'
    mov     ah, 0x0E
    int     0x10
    mov     al, ' '
    int     0x10
    mov     al, '('
    int     0x10

    ; Get drive type string
    mov     bl, [drive_map + bx]
    xor     bh, bh
    mov     al, [drive_types + bx]
    call    get_type_string
    call    print_string
    mov     al, ')'
    mov     ah, 0x0E
    int     0x10

    jmp     .next_map

.not_mapped:
    mov     si, msg_mapping_none
    call    print_string

.next_map:
    mov     si, msg_crlf
    call    print_string
    inc     cl
    jmp     .map_loop

.map_done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Swap Drive A: and B:
;==============================================================================
; Exchanges the physical drives mapped to DOS A: and B:.
;==============================================================================
swap_drive_ab:
    push    ax
    push    bx

    ; Get current mappings
    mov     al, [drive_map]         ; A: physical
    mov     ah, [drive_map + 1]     ; B: physical

    ; Swap
    mov     [drive_map], ah
    mov     [drive_map + 1], al

    ; Update reverse mapping if both were valid
    cmp     al, 0xFF
    je      .update_b
    mov     bl, al
    xor     bh, bh
    mov     byte [phys_to_logical + bx], 1   ; Now B:
.update_b:
    cmp     ah, 0xFF
    je      .done
    mov     bl, ah
    xor     bh, bh
    mov     byte [phys_to_logical + bx], 0   ; Now A:

.done:
    pop     bx
    pop     ax
    ret

;==============================================================================
; Print Decimal Byte
;==============================================================================
; Prints an 8-bit value in decimal format.
; Input:  AL = value to print
;==============================================================================
print_dec_byte:
    push    ax
    push    cx
    xor     ah, ah                  ; Zero-extend to 16-bit
    call    print_dec_word
    pop     cx
    pop     ax
    ret

;==============================================================================
; Diagnostics Strings
;==============================================================================
diag_header:
    db      13, 10
    db      "=== FluxRipper FDD Diagnostics ===", 13, 10
    db      13, 10
    db      0

diag_footer_menu:
    db      13, 10
    db      "[S] Swap A:/B:  [R] Reset  [C] Config  [ESC] Exit", 0

; Drive mapping strings
msg_mapping_header:
    db      13, 10
    db      "Drive Mapping:", 13, 10
    db      0
msg_mapping_indent:
    db      "  ", 0
msg_mapping_drive:
    db      "-> Drive ", 0
msg_mapping_none:
    db      "(not mapped)", 0

; Instrumentation strings
msg_instr_header:
    db      "    Signal Analysis:", 13, 10, 0
msg_indent:
    db      "    ", 0
msg_pll_lock:
    db      "    PLL: ", 0
msg_locked:
    db      "LOCKED  ", 0
msg_unlocked:
    db      "UNLOCKED", 0
msg_signal_q:
    db      "  Quality: ", 0
msg_percent:
    db      "%", 0
msg_err_count:
    db      "  Errors: ", 0
msg_sync_cnt:
    db      "Sync patterns: ", 0
msg_flux_stats:
    db      "Flux timing:", 0
msg_flux_min:
    db      " Min=", 0
msg_flux_max:
    db      " Max=", 0
msg_flux_avg:
    db      "Avg=", 0
msg_flux_jitt:
    db      " Jitter=", 0
msg_ns:
    db      "ns", 0
msg_rpm_disp:
    db      "RPM: ", 0
msg_rpm_unit:
    db      " RPM", 0

;==============================================================================
; Controller Configuration Menu
;==============================================================================
; Allows user to enable/disable FDC and WD HDD controllers.
;
; Edge cases handled:
;   - Cannot disable FDC from FDD BIOS (chicken-and-egg prevention)
;   - Config lock detection and unlock option
;   - Flash timeout detection with proper error reporting
;   - Busy check before changes (checks FDC motor status)
;   - Shows which controller hosts config registers
;==============================================================================
diag_config_menu:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; Clear area and show config header
    mov     si, msg_config_header
    call    print_string

    ; Check if FluxRipper config registers are present
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_MAGIC
    in      al, dx
    cmp     al, CFG_MAGIC_VALUE
    jne     .no_config

    ; Check if config was loaded from flash or using defaults
    ; (scratch register is 0 on fresh boot, set to 0xAA after flash load)
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_SCRATCH
    in      al, dx
    cmp     al, 0xAA
    je      .show_status
    ; First access - check if flash had valid data
    ; Set scratch to mark we've been here
    mov     al, 0xAA
    out     dx, al

.show_status:
    ; Read current configuration
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_CTRL
    in      al, dx
    mov     bl, al                      ; Save config in BL
    mov     [.saved_ctrl], al           ; Also save for later

    ; Check if config is locked
    test    bl, CFG_CTRL_LOCKED
    jz      .not_locked
    mov     si, msg_cfg_locked_warn
    call    print_string
.not_locked:

    ; Show FDC status (with note that it can't be disabled from here)
    ; First check if FDC hardware is present
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_STATUS
    in      al, dx
    mov     [.saved_status], al
    test    al, CFG_STAT_FDC_PRESENT
    jz      .fdc_not_installed

    mov     si, msg_cfg_fdc
    call    print_string
    test    bl, CFG_CTRL_FDC_EN
    jz      .fdc_disabled
    mov     si, msg_enabled
    jmp     .print_fdc
.fdc_disabled:
    mov     si, msg_disabled
.print_fdc:
    call    print_string
    ; Add note about FDC being the config host
    mov     si, msg_cfg_fdc_host
    call    print_string
    jmp     .show_wd

.fdc_not_installed:
    mov     si, msg_cfg_fdc
    call    print_string
    mov     si, msg_not_installed
    call    print_string

.show_wd:
    ; Show WD HDD status - check if WD hardware is present
    mov     al, [.saved_status]
    test    al, CFG_STAT_WD_PRESENT
    jz      .wd_not_installed

    mov     si, msg_cfg_wd
    call    print_string
    test    bl, CFG_CTRL_WD_EN
    jz      .wd_disabled
    mov     si, msg_enabled
    jmp     .print_wd
.wd_disabled:
    mov     si, msg_disabled
.print_wd:
    call    print_string
    jmp     .show_slot

.wd_not_installed:
    mov     si, msg_cfg_wd
    call    print_string
    mov     si, msg_not_installed
    call    print_string

.show_slot:
    ; Show slot type from status register (already have it in .saved_status)
    mov     al, [.saved_status]
    mov     si, msg_cfg_slot
    call    print_string
    test    al, CFG_STAT_16BIT
    jnz     .slot_16bit
    test    al, CFG_STAT_8BIT
    jnz     .slot_8bit
    mov     si, msg_slot_unknown
    jmp     .print_slot
.slot_16bit:
    mov     si, msg_slot_16bit
    jmp     .print_slot
.slot_8bit:
    mov     si, msg_slot_8bit
.print_slot:
    call    print_string

    ; Show PnP status
    mov     al, [.saved_status]
    mov     si, msg_cfg_pnp
    call    print_string
    test    al, CFG_STAT_PNP
    jz      .pnp_inactive
    mov     si, msg_pnp_active
    call    print_string
    ; Warn that PnP may override settings
    mov     si, msg_pnp_override_warn
    call    print_string
    jmp     .show_menu
.pnp_inactive:
    mov     si, msg_pnp_legacy
    call    print_string

.show_menu:
    ; Show config menu (modified - no FDC toggle option)
    mov     si, msg_config_menu
    call    print_string

    ; Show unlock option if locked
    mov     al, [.saved_ctrl]
    test    al, CFG_CTRL_LOCKED
    jz      .config_key_loop
    mov     si, msg_unlock_option
    call    print_string

.config_key_loop:
    xor     ah, ah
    int     0x16

    ; Check for '1' - toggle FDC (BLOCKED - show warning)
    cmp     al, '1'
    je      .block_fdc_toggle

    ; Check for '2' - toggle WD
    cmp     al, '2'
    je      .toggle_wd

    ; Check for 'S' or 's' - save to flash
    cmp     al, 'S'
    je      .save_flash
    cmp     al, 's'
    je      .save_flash

    ; Check for 'D' or 'd' - restore defaults
    cmp     al, 'D'
    je      .restore_defaults
    cmp     al, 'd'
    je      .restore_defaults

    ; Check for 'U' or 'u' - unlock config
    cmp     al, 'U'
    je      .unlock_config
    cmp     al, 'u'
    je      .unlock_config

    ; Check for ESC - exit config menu
    cmp     al, 0x1B
    je      .config_exit

    jmp     .config_key_loop

.block_fdc_toggle:
    ; Cannot disable FDC from FDD BIOS - would lock out config access
    mov     si, msg_cannot_disable_fdc
    call    print_string
    jmp     .config_key_loop

.toggle_wd:
    ; Check if config is locked
    mov     al, [.saved_ctrl]
    test    al, CFG_CTRL_LOCKED
    jnz     .config_locked_error

    ; Check if FDC is busy (motor running = potential I/O in progress)
    call    .check_fdc_busy
    jc      .busy_error

    ; Read current, toggle WD bit, write back
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_CTRL
    in      al, dx
    xor     al, CFG_CTRL_WD_EN
    out     dx, al
    ; Refresh display
    mov     si, msg_crlf
    call    print_string
    jmp     .show_status

.unlock_config:
    ; Write CTRL with lock bit cleared
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_CTRL
    in      al, dx
    and     al, ~CFG_CTRL_LOCKED        ; Clear lock bit
    out     dx, al
    mov     si, msg_unlocked
    call    print_string
    mov     si, msg_crlf
    call    print_string
    jmp     .show_status

.config_locked_error:
    mov     si, msg_locked_error
    call    print_string
    jmp     .config_key_loop

.busy_error:
    mov     si, msg_busy_error
    call    print_string
    jmp     .config_key_loop

.save_flash:
    ; Check if config is locked
    mov     al, [.saved_ctrl]
    test    al, CFG_CTRL_LOCKED
    jnz     .config_locked_error

    ; Check if already busy
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_STATUS
    in      al, dx
    test    al, CFG_STAT_FLASH_BUSY
    jnz     .flash_busy_error

    ; Write magic value to save register
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_SAVE
    mov     al, CFG_SAVE_MAGIC
    out     dx, al

    ; Wait for flash operation (poll status) with timeout tracking
    mov     cx, 1000                    ; Timeout counter
    mov     byte [.flash_timeout], 0    ; Clear timeout flag
.wait_flash:
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_STATUS
    in      al, dx
    test    al, CFG_STAT_FLASH_BUSY
    jz      .flash_check_result
    ; Small delay
    push    cx
    mov     cx, 100
.delay_loop:
    loop    .delay_loop
    pop     cx
    loop    .wait_flash
    ; Timeout occurred
    mov     byte [.flash_timeout], 1

.flash_check_result:
    ; Check if we timed out
    cmp     byte [.flash_timeout], 1
    je      .flash_timeout_error

    ; Verify save succeeded by reading back and checking
    mov     si, msg_saved
    call    print_string
    jmp     .config_key_loop

.flash_timeout_error:
    mov     si, msg_flash_timeout
    call    print_string
    jmp     .config_key_loop

.flash_busy_error:
    mov     si, msg_flash_busy
    call    print_string
    jmp     .config_key_loop

.restore_defaults:
    ; Check if config is locked
    mov     al, [.saved_ctrl]
    test    al, CFG_CTRL_LOCKED
    jnz     .config_locked_error

    ; Write magic value to restore register
    mov     dx, FDC_PRIMARY + CFG_REG_BASE + CFG_RESTORE
    mov     al, CFG_RESTORE_MAGIC
    out     dx, al
    ; Refresh display
    mov     si, msg_restored
    call    print_string
    mov     si, msg_crlf
    call    print_string
    jmp     .show_status

.no_config:
    mov     si, msg_no_config
    call    print_string
    ; Wait for any key
    xor     ah, ah
    int     0x16

.config_exit:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;------------------------------------------------------------------------------
; Check if FDC is busy (motor running indicates potential I/O)
; Returns: CF=1 if busy, CF=0 if idle
;------------------------------------------------------------------------------
.check_fdc_busy:
    push    ax
    push    dx
    ; Check BDA motor status byte at 0040:003F
    push    es
    mov     ax, 0x0040
    mov     es, ax
    mov     al, [es:0x3F]
    pop     es
    test    al, 0x0F                    ; Any motor running?
    jz      .not_busy
    stc                                 ; Set carry - busy
    jmp     .busy_done
.not_busy:
    clc                                 ; Clear carry - idle
.busy_done:
    pop     dx
    pop     ax
    ret

; Local variables
.saved_ctrl:    db 0
.saved_status:  db 0
.flash_timeout: db 0

;==============================================================================
; Configuration Menu Strings
;==============================================================================
msg_config_header:
    db      13, 10
    db      "=== Controller Configuration ===", 13, 10
    db      13, 10, 0

msg_cfg_fdc:
    db      "  FDC (Floppy):   ", 0
msg_cfg_fdc_host:
    db      " (config host)", 13, 10, 0
msg_cfg_wd:
    db      "  WD HDD:         ", 0
msg_cfg_slot:
    db      13, 10
    db      "  Slot Type:      ", 0
msg_cfg_pnp:
    db      13, 10
    db      "  Mode:           ", 0

msg_enabled:
    db      "ENABLED ", 0
msg_disabled:
    db      "DISABLED", 0
msg_not_installed:
    db      "(not installed)", 13, 10, 0
msg_slot_8bit:
    db      "8-bit (XT)", 0
msg_slot_16bit:
    db      "16-bit (AT)", 0
msg_slot_unknown:
    db      "Unknown", 0
msg_pnp_active:
    db      "Plug and Play", 0
msg_pnp_legacy:
    db      "Legacy", 0

msg_pnp_override_warn:
    db      13, 10
    db      "  Note: OS PnP driver may override these settings", 0

msg_cfg_locked_warn:
    db      "  *** Configuration is LOCKED ***", 13, 10, 0

msg_config_menu:
    db      13, 10, 13, 10
    db      "[1] Toggle FDC (see note)  [2] Toggle HDD", 13, 10
    db      "[S] Save to flash  [D] Restore defaults", 13, 10
    db      "[ESC] Back", 0

msg_unlock_option:
    db      13, 10, "[U] Unlock configuration", 0

msg_saved:
    db      13, 10, "Configuration saved to flash.", 0
msg_restored:
    db      13, 10, "Defaults restored.", 0
msg_unlocked:
    db      13, 10, "Configuration unlocked.", 0

msg_no_config:
    db      "  FluxRipper config registers not found.", 13, 10
    db      "  Press any key to continue...", 0

msg_cannot_disable_fdc:
    db      13, 10
    db      "  Cannot disable FDC from FDD BIOS!", 13, 10
    db      "  Use HDD BIOS F3 menu to disable FDC.", 0

msg_locked_error:
    db      13, 10, "  Error: Configuration is locked. Press [U] to unlock.", 0

msg_busy_error:
    db      13, 10, "  Error: FDC is busy. Wait for disk operation to complete.", 0

msg_flash_timeout:
    db      13, 10, "  Error: Flash save timed out! Settings NOT saved.", 0

msg_flash_busy:
    db      13, 10, "  Error: Flash is busy. Try again later.", 0

%endif ; BUILD_16KB && ENABLE_DIAG
