;==============================================================================
; FluxRipper HDD BIOS - Diagnostics Menu
;==============================================================================
; Main diagnostics interface accessible via F3 during POST.
;
; Features:
;   - Drive status display
;   - Surface scan
;   - Seek test
;   - Flux histogram
;   - Error log viewer
;   - ESDI query (if applicable)
;   - Real-time monitor
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%if BUILD_16KB

;==============================================================================
; Diagnostics Entry Point
;==============================================================================
; Called when F3 is detected during POST.
;
; Preserves: All registers
;==============================================================================
diag_enter:
    pushad
    push    ds
    push    es

    ; Set up segments
    push    cs
    pop     ds

    ; Initialize video
    call    video_init
    call    video_clear_screen

    ; Draw main screen
    call    diag_draw_main

    ; Main menu loop
    call    diag_main_menu

    ; Restore screen and return
    call    video_clear_screen

    pop     es
    pop     ds
    popad
    ret

;==============================================================================
; Draw Main Diagnostics Screen
;==============================================================================
diag_draw_main:
    push    ax
    push    dx
    push    si

    ; Draw title bar
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_title
    call    video_puts_centered

    ; Draw box around menu area
    mov     dh, 2                   ; Top row
    mov     dl, 5                   ; Left column
    mov     ch, 22                  ; Bottom row
    mov     cl, 74                  ; Right column
    mov     ah, ATTR_NORMAL
    call    video_draw_box

    ; Draw drive info header
    mov     dh, 3
    mov     dl, 7
    mov     ah, ATTR_HIGHLIGHT
    mov     si, diag_drive_hdr
    call    video_puts_at

    ; Display drive 0 info
    mov     dl, 0x80
    call    diag_show_drive_info

    ; Display drive 1 info if present
    mov     dl, 0x81
    call    diag_show_drive_info

    ; Draw menu options
    call    diag_draw_menu_options

    ; Draw status bar
    mov     dh, 24
    mov     ah, ATTR_INVERSE
    mov     si, diag_status_bar
    call    video_puts_centered

    pop     si
    pop     dx
    pop     ax
    ret

;==============================================================================
; Show Drive Information
;==============================================================================
; Input: DL = drive number (0x80 or 0x81)
;==============================================================================
diag_show_drive_info:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; Calculate row (drive 0 = row 5, drive 1 = row 7)
    mov     dh, 5
    cmp     dl, 0x81
    jne     .got_row
    mov     dh, 7
.got_row:
    mov     [.drive_row], dh
    mov     [.drive_num], dl

    ; Check if drive present
    push    dx
    call    get_drive_params
    pop     dx
    jc      .not_present

    ; Drive number
    mov     dl, 7
    mov     dh, [.drive_row]
    mov     ah, ATTR_NORMAL
    mov     si, diag_drive_prefix
    call    video_puts_at

    ; Drive number digit
    mov     al, [.drive_num]
    sub     al, 0x80
    add     al, '0'
    add     dl, 6
    call    video_putc_at

    ; Cylinders
    add     dl, 4
    mov     ax, [si + 0]            ; Cylinders from FDPT
    call    diag_print_dec16

    ; Heads
    add     dl, 8
    xor     ah, ah
    mov     al, [si + 2]
    call    diag_print_dec16

    ; Sectors
    add     dl, 6
    xor     ah, ah
    mov     al, [si + 3]
    call    diag_print_dec16

    ; Calculate and show capacity in MB
    add     dl, 6
    call    diag_calc_capacity
    call    diag_print_dec16
    mov     si, diag_mb_suffix
    call    video_puts_at

    jmp     .done

.not_present:
    mov     dl, 7
    mov     dh, [.drive_row]
    mov     ah, ATTR_DIM
    mov     si, diag_drive_prefix
    call    video_puts_at
    mov     al, [.drive_num]
    sub     al, 0x80
    add     al, '0'
    add     dl, 6
    call    video_putc_at
    add     dl, 4
    mov     si, diag_not_present
    call    video_puts_at

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.drive_row: db 0
.drive_num: db 0

;==============================================================================
; Draw Menu Options
;==============================================================================
diag_draw_menu_options:
    push    ax
    push    dx
    push    si

    mov     dh, 10                  ; Starting row
    mov     dl, 10                  ; Column

    ; Option 1: Surface Scan
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '1'
    call    video_putc_at
    mov     ah, ATTR_NORMAL
    add     dl, 2
    mov     si, diag_opt_surface
    call    video_puts_at

    ; Option 2: Seek Test
    add     dh, 2
    mov     dl, 10
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '2'
    call    video_putc_at
    add     dl, 2
    mov     ah, ATTR_NORMAL
    mov     si, diag_opt_seek
    call    video_puts_at

    ; Option 3: Flux Histogram
    add     dh, 2
    mov     dl, 10
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '3'
    call    video_putc_at
    add     dl, 2
    mov     ah, ATTR_NORMAL
    mov     si, diag_opt_flux
    call    video_puts_at

    ; Option 4: Error Log
    add     dh, 2
    mov     dl, 10
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '4'
    call    video_putc_at
    add     dl, 2
    mov     ah, ATTR_NORMAL
    mov     si, diag_opt_errors
    call    video_puts_at

    ; Option 5: Health Monitor
    add     dh, 2
    mov     dl, 10
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '5'
    call    video_putc_at
    add     dl, 2
    mov     ah, ATTR_NORMAL
    mov     si, diag_opt_health
    call    video_puts_at

    ; Option 6: Signal Quality
    add     dh, 2
    mov     dl, 10
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '6'
    call    video_putc_at
    add     dl, 2
    mov     ah, ATTR_NORMAL
    mov     si, diag_opt_signal
    call    video_puts_at

    ; Option 7: Controller Config
    add     dh, 2
    mov     dl, 10
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '7'
    call    video_putc_at
    add     dl, 2
    mov     ah, ATTR_NORMAL
    mov     si, diag_opt_config
    call    video_puts_at

    ; Option 8: Interleave
    add     dh, 2
    mov     dl, 10
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '8'
    call    video_putc_at
    add     dl, 2
    mov     ah, ATTR_NORMAL
    mov     si, diag_opt_interleave
    call    video_puts_at

    ; Option 9: Interleave Benchmark
    add     dh, 2
    mov     dl, 10
    mov     ah, ATTR_HIGHLIGHT
    mov     al, '9'
    call    video_putc_at
    add     dl, 2
    mov     ah, ATTR_NORMAL
    mov     si, diag_opt_benchmark
    call    video_puts_at

    ; ESC to exit
    add     dh, 3
    mov     dl, 10
    mov     ah, ATTR_DIM
    mov     si, diag_opt_exit
    call    video_puts_at

    pop     si
    pop     dx
    pop     ax
    ret

;==============================================================================
; Main Menu Handler
;==============================================================================
diag_main_menu:
    push    ax
    push    bx

.menu_loop:
    call    kbd_get

    ; Check for ESC
    cmp     ah, KEY_ESC
    je      .exit

    ; Check for digit keys
    cmp     al, '1'
    je      .surface_scan
    cmp     al, '2'
    je      .seek_test
    cmp     al, '3'
    je      .flux_hist
    cmp     al, '4'
    je      .error_log
    cmp     al, '5'
    je      .health_mon
    cmp     al, '6'
    je      .signal_qual
    cmp     al, '7'
    je      .controller_config
    cmp     al, '8'
    je      .interleave_config
    cmp     al, '9'
    je      .interleave_benchmark

    ; Invalid key
    jmp     .menu_loop

.surface_scan:
    call    diag_surface_scan
    call    diag_draw_main
    jmp     .menu_loop

.seek_test:
    call    diag_seek_test
    call    diag_draw_main
    jmp     .menu_loop

.flux_hist:
    call    diag_flux_histogram
    call    diag_draw_main
    jmp     .menu_loop

.error_log:
    call    diag_error_log
    call    diag_draw_main
    jmp     .menu_loop

.health_mon:
    call    diag_health_monitor
    call    diag_draw_main
    jmp     .menu_loop

.signal_qual:
    call    diag_signal_quality
    call    diag_draw_main
    jmp     .menu_loop

.controller_config:
    call    diag_controller_config
    call    diag_draw_main
    jmp     .menu_loop

.interleave_config:
    call    diag_interleave_config
    call    diag_draw_main
    jmp     .menu_loop

.interleave_benchmark:
    call    diag_interleave_benchmark
    call    diag_draw_main
    jmp     .menu_loop

.exit:
    pop     bx
    pop     ax
    ret

;==============================================================================
; Surface Scan Test
;==============================================================================
diag_surface_scan:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    call    video_clear_screen

    ; Title
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_surface_title
    call    video_puts_centered

    ; Select drive
    mov     dh, 3
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_select_drive
    call    video_puts_at

    call    kbd_get_digit
    jc      .cancelled
    cmp     al, 1
    ja      .cancelled
    add     al, 0x80
    mov     [.scan_drive], al

    ; Get drive parameters
    mov     dl, [.scan_drive]
    call    get_drive_params
    jc      .no_drive

    ; Store geometry
    mov     ax, [si + 0]
    mov     [.max_cyl], ax
    mov     al, [si + 2]
    mov     [.max_head], al
    mov     al, [si + 3]
    mov     [.max_sect], al

    ; Show progress
    mov     dh, 5
    mov     dl, 5
    mov     si, diag_scanning
    call    video_puts_at

    ; Initialize counters
    xor     word [.error_count], ax
    mov     word [.current_cyl], 0

.scan_loop:
    ; Update progress bar
    mov     dh, 7
    mov     dl, 5
    mov     cl, 60                  ; Width
    mov     ax, [.current_cyl]
    mov     bx, [.max_cyl]
    xor     dx, dx
    push    dx
    mov     dx, 100
    mul     dx                      ; AX = cyl * 100
    div     bx                      ; AL = percentage
    pop     dx
    mov     ah, ATTR_NORMAL
    call    video_progress_bar

    ; Display cylinder number
    mov     dh, 9
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_cylinder
    call    video_puts_at
    add     dl, 10
    mov     ax, [.current_cyl]
    call    diag_print_dec16

    ; Read each head/sector on this cylinder
    xor     byte [.current_head], 0
.head_loop:
    mov     byte [.current_sect], 1
.sect_loop:
    ; Set up read parameters
    mov     ah, 0x02                ; Read sectors
    mov     al, 1                   ; One sector
    mov     ch, [.current_cyl]      ; Cylinder low
    mov     cl, [.current_sect]     ; Sector
    mov     al, [.current_cyl + 1]
    shl     al, 6
    or      cl, al                  ; Cylinder high bits
    mov     dh, [.current_head]
    mov     dl, [.scan_drive]
    mov     bx, scratch_buffer
    push    es
    push    cs
    pop     es
    int     0x13
    pop     es

    jnc     .read_ok

    ; Error - increment counter
    inc     word [.error_count]

    ; Display error location
    push    dx
    mov     dh, 11
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_error_at
    call    video_puts_at
    add     dl, 10
    mov     ax, [.current_cyl]
    call    diag_print_dec16
    mov     al, '/'
    call    video_putc_at
    inc     dl
    xor     ah, ah
    mov     al, [.current_head]
    call    diag_print_dec16
    mov     al, '/'
    call    video_putc_at
    inc     dl
    xor     ah, ah
    mov     al, [.current_sect]
    call    diag_print_dec16
    pop     dx

.read_ok:
    ; Check for ESC
    mov     ah, 0x01
    int     0x16
    jz      .no_key
    mov     ah, 0x00
    int     0x16
    cmp     ah, KEY_ESC
    je      .scan_done
.no_key:

    ; Next sector
    inc     byte [.current_sect]
    mov     al, [.current_sect]
    cmp     al, [.max_sect]
    jbe     .sect_loop

    ; Next head
    inc     byte [.current_head]
    mov     al, [.current_head]
    cmp     al, [.max_head]
    jb      .head_loop

    ; Next cylinder
    inc     word [.current_cyl]
    mov     ax, [.current_cyl]
    cmp     ax, [.max_cyl]
    jb      .scan_loop

.scan_done:
    ; Show results
    mov     dh, 14
    mov     dl, 5
    mov     ah, ATTR_BRIGHT
    mov     si, diag_scan_complete
    call    video_puts_at

    mov     dh, 16
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_errors_found
    call    video_puts_at
    add     dl, 15
    mov     ax, [.error_count]
    call    diag_print_dec16

    jmp     .wait_key

.no_drive:
    mov     dh, 5
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_no_drive
    call    video_puts_at
    jmp     .wait_key

.cancelled:
.wait_key:
    call    kbd_wait_any

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.scan_drive:    db 0
.max_cyl:       dw 0
.max_head:      db 0
.max_sect:      db 0
.current_cyl:   dw 0
.current_head:  db 0
.current_sect:  db 0
.error_count:   dw 0

;==============================================================================
; Seek Test
;==============================================================================
diag_seek_test:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    call    video_clear_screen

    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_seek_title
    call    video_puts_centered

    ; Select drive
    mov     dh, 3
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_select_drive
    call    video_puts_at

    call    kbd_get_digit
    jc      .done
    cmp     al, 1
    ja      .done
    add     al, 0x80
    mov     [.test_drive], al

    ; Get drive parameters
    mov     dl, [.test_drive]
    call    get_drive_params
    jc      .done

    mov     ax, [si + 0]
    mov     [.max_cyl], ax

    ; Perform seeks
    mov     dh, 5
    mov     dl, 5
    mov     si, diag_seek_running
    call    video_puts_at

    mov     word [.seek_count], 0
    mov     word [.error_count], 0

    ; Test pattern: 0, max, 0, max/2, max, 0...
    mov     cx, 100                 ; Number of seeks

.seek_loop:
    push    cx

    ; Alternate seek targets
    mov     ax, [.seek_count]
    and     ax, 3
    cmp     ax, 0
    je      .seek_0
    cmp     ax, 1
    je      .seek_max
    cmp     ax, 2
    je      .seek_mid
    jmp     .seek_0

.seek_0:
    xor     cx, cx
    jmp     .do_seek

.seek_max:
    mov     cx, [.max_cyl]
    dec     cx
    jmp     .do_seek

.seek_mid:
    mov     cx, [.max_cyl]
    shr     cx, 1

.do_seek:
    ; Issue seek (INT 13h function 0Ch)
    mov     ah, 0x0C
    mov     ch, cl                  ; Cylinder low
    shr     cx, 2
    and     cl, 0xC0                ; Cylinder high
    mov     dh, 0                   ; Head 0
    mov     dl, [.test_drive]
    int     0x13
    jnc     .seek_ok

    inc     word [.error_count]

.seek_ok:
    inc     word [.seek_count]

    ; Update display
    mov     dh, 7
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_seeks_done
    call    video_puts_at
    add     dl, 13
    mov     ax, [.seek_count]
    call    diag_print_dec16

    ; Check ESC
    mov     ah, 0x01
    int     0x16
    jz      .no_esc
    mov     ah, 0x00
    int     0x16
    cmp     ah, KEY_ESC
    je      .seek_done
.no_esc:

    pop     cx
    loop    .seek_loop
    push    cx

.seek_done:
    pop     cx

    ; Show results
    mov     dh, 10
    mov     dl, 5
    mov     ah, ATTR_BRIGHT
    mov     si, diag_seek_complete
    call    video_puts_at

    mov     dh, 12
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_errors_found
    call    video_puts_at
    add     dl, 15
    mov     ax, [.error_count]
    call    diag_print_dec16

.done:
    call    kbd_wait_any

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.test_drive:    db 0
.max_cyl:       dw 0
.seek_count:    dw 0
.error_count:   dw 0

;==============================================================================
; Flux Histogram Display
;==============================================================================
diag_flux_histogram:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    call    video_clear_screen

    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_flux_title
    call    video_puts_centered

    ; Read histogram data from FPGA
    mov     di, 0                   ; Bin index
    mov     word [.max_value], 0

    ; First pass: find maximum value for scaling
.find_max:
    mov     ax, INSTR_HIST_BASE
    add     ax, di
    add     ax, di
    add     ax, di
    add     ax, di                  ; AX = base + bin*4
    INSTR_SET_ADDR
    INSTR_READ_DATA                 ; DX:AX = 32-bit value

    ; Store in buffer (just low 16 bits for display)
    mov     bx, di
    shl     bx, 1
    mov     [histogram_buf + bx], ax

    ; Update max
    cmp     ax, [.max_value]
    jbe     .not_max
    mov     [.max_value], ax
.not_max:

    inc     di
    cmp     di, 32                  ; Only show 32 bins (fit on screen)
    jb      .find_max

    ; Draw histogram bars
    mov     di, 0                   ; Bin index
    mov     dl, 10                  ; Starting column

.draw_bar:
    mov     bx, di
    shl     bx, 1
    mov     ax, [histogram_buf + bx]

    ; Scale to 0-16 (bar height)
    mov     bx, [.max_value]
    test    bx, bx
    jz      .zero_bar

    mov     cx, 16
    mul     cx
    div     bx                      ; AL = scaled height (0-16)
    jmp     .got_height

.zero_bar:
    xor     al, al

.got_height:
    ; Draw vertical bar from bottom up
    mov     cl, al                  ; Height
    mov     dh, 20                  ; Bottom row

.bar_loop:
    test    cl, cl
    jz      .bar_done

    mov     al, PROG_FULL
    mov     ah, ATTR_SUCCESS
    call    video_putc_at
    dec     dh
    dec     cl
    jmp     .bar_loop

.bar_done:
    ; Next bin
    inc     dl
    inc     dl                      ; 2 columns per bar
    inc     di
    cmp     di, 32
    jb      .draw_bar

    ; Draw axis labels
    mov     dh, 22
    mov     dl, 10
    mov     ah, ATTR_DIM
    mov     si, diag_flux_axis
    call    video_puts_at

    call    kbd_wait_any

    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.max_value:     dw 0

;==============================================================================
; Error Log Viewer
;==============================================================================
diag_error_log:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    call    video_clear_screen

    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_errlog_title
    call    video_puts_centered

    ; Header
    mov     dh, 2
    mov     dl, 3
    mov     ah, ATTR_HIGHLIGHT
    mov     si, diag_errlog_hdr
    call    video_puts_at

    ; Read and display error log entries
    mov     cx, 0                   ; Entry index
    mov     dh, 4                   ; Starting row

.log_loop:
    push    cx
    push    dx

    ; Calculate entry address
    mov     ax, INSTR_LOG_BASE
    mov     bx, cx
    shl     bx, 4                   ; *16 bytes per entry
    add     ax, bx

    ; Read timestamp
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.timestamp], ax

    ; Skip if timestamp is 0 (empty entry)
    test    ax, ax
    jz      .skip_entry

    ; Read CHS
    pop     dx
    push    dx
    mov     dl, 3
    mov     ah, ATTR_NORMAL

    ; Entry number
    pop     bx
    push    bx
    mov     ax, bx
    call    diag_print_dec16

    add     dl, 4

    ; Timestamp
    mov     ax, [.timestamp]
    call    diag_print_dec16

    ; (Would read more fields here - simplified for brevity)
    jmp     .next_entry

.skip_entry:
.next_entry:
    pop     dx
    pop     cx
    inc     dh
    inc     cx
    cmp     cx, INSTR_LOG_ENTRIES
    jb      .log_loop

    call    kbd_wait_any

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.timestamp:     dw 0

;==============================================================================
; Health Monitor
;==============================================================================
diag_health_monitor:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    call    video_clear_screen

    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_health_title
    call    video_puts_centered

    ; Read health scores from FPGA
    mov     ax, INSTR_HEALTH_SCORE
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.overall], ax

    mov     ax, INSTR_MEDIA_SCORE
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.media], ax

    mov     ax, INSTR_HEAD_SCORE
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.head], ax

    mov     ax, INSTR_SPINDLE_SCORE
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.spindle], ax

    ; Display scores with progress bars
    mov     dh, 4
    mov     dl, 5
    mov     si, diag_health_overall
    call    video_puts_at

    mov     dh, 4
    mov     dl, 25
    mov     cl, 40                  ; Bar width
    mov     al, [.overall]
    mov     ah, ATTR_SUCCESS
    cmp     al, 50
    jae     .overall_color_ok
    mov     ah, ATTR_ERROR
.overall_color_ok:
    call    video_progress_bar

    ; Media score
    mov     dh, 6
    mov     dl, 5
    mov     si, diag_health_media
    call    video_puts_at
    mov     dh, 6
    mov     dl, 25
    mov     al, [.media]
    mov     ah, ATTR_NORMAL
    call    video_progress_bar

    ; Head score
    mov     dh, 8
    mov     dl, 5
    mov     si, diag_health_head
    call    video_puts_at
    mov     dh, 8
    mov     dl, 25
    mov     al, [.head]
    call    video_progress_bar

    ; Spindle score
    mov     dh, 10
    mov     dl, 5
    mov     si, diag_health_spindle
    call    video_puts_at
    mov     dh, 10
    mov     dl, 25
    mov     al, [.spindle]
    call    video_progress_bar

    ; Temperature
    mov     ax, INSTR_TEMP_DRIVE
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.temp], ax

    mov     dh, 13
    mov     dl, 5
    mov     si, diag_health_temp
    call    video_puts_at
    add     dl, 18
    mov     ax, [.temp]
    mov     bl, 10
    div     bl                      ; AL = degrees, AH = decimal
    push    ax
    xor     ah, ah
    call    diag_print_dec16
    mov     al, '.'
    call    video_putc_at
    inc     dl
    pop     ax
    mov     al, ah
    xor     ah, ah
    call    diag_print_dec16
    mov     si, diag_celsius
    call    video_puts_at

    call    kbd_wait_any

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.overall:   dw 0
.media:     dw 0
.head:      dw 0
.spindle:   dw 0
.temp:      dw 0

;==============================================================================
; Signal Quality Display
;==============================================================================
diag_signal_quality:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    call    video_clear_screen

    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_signal_title
    call    video_puts_centered

    ; Read signal quality from FPGA
    mov     ax, INSTR_SIG_AMPLITUDE
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.amplitude], ax

    mov     ax, INSTR_SIG_SNR
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.snr], ax

    mov     ax, INSTR_SIG_JITTER
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.jitter], ax

    mov     ax, INSTR_PLL_LOCK
    INSTR_SET_ADDR
    INSTR_READ_DATA
    mov     [.pll_lock], ax

    ; Display values
    mov     dh, 4
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_sig_amplitude
    call    video_puts_at
    add     dl, 20
    mov     ax, [.amplitude]
    call    diag_print_dec16
    mov     si, diag_mv_suffix
    call    video_puts_at

    mov     dh, 6
    mov     dl, 5
    mov     si, diag_sig_snr
    call    video_puts_at
    add     dl, 20
    mov     ax, [.snr]
    mov     bl, 10
    div     bl
    push    ax
    xor     ah, ah
    call    diag_print_dec16
    mov     al, '.'
    call    video_putc_at
    inc     dl
    pop     ax
    mov     al, ah
    xor     ah, ah
    call    diag_print_dec16
    mov     si, diag_db_suffix
    call    video_puts_at

    mov     dh, 8
    mov     dl, 5
    mov     si, diag_sig_jitter
    call    video_puts_at
    add     dl, 20
    mov     ax, [.jitter]
    call    diag_print_dec16
    mov     si, diag_ns_suffix
    call    video_puts_at

    mov     dh, 10
    mov     dl, 5
    mov     si, diag_sig_pll
    call    video_puts_at
    add     dl, 20
    mov     ax, [.pll_lock]
    test    ax, ax
    jz      .pll_unlocked
    mov     si, diag_locked
    mov     ah, ATTR_SUCCESS
    jmp     .show_pll
.pll_unlocked:
    mov     si, diag_unlocked
    mov     ah, ATTR_ERROR
.show_pll:
    call    video_puts_at

    call    kbd_wait_any

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.amplitude: dw 0
.snr:       dw 0
.jitter:    dw 0
.pll_lock:  dw 0

;==============================================================================
; Calculate Capacity in MB
;==============================================================================
; Input: SI = pointer to FDPT
; Output: AX = capacity in MB
;==============================================================================
diag_calc_capacity:
    push    bx
    push    cx
    push    dx

    ; Total = cyl * heads * sectors * 512 / 1048576
    ; Simplified: (cyl * heads * sectors) / 2048

    mov     ax, [si + 0]            ; Cylinders
    xor     bh, bh
    mov     bl, [si + 2]            ; Heads
    mul     bx
    mov     cx, ax                  ; CX = cyl * heads (low)
    mov     bx, dx                  ; BX = high word

    xor     ah, ah
    mov     al, [si + 3]            ; Sectors
    mul     cx                      ; DX:AX = total sectors (approximate)

    ; Divide by 2048 (shift right 11)
    mov     cx, 11
.shift_loop:
    shr     dx, 1
    rcr     ax, 1
    loop    .shift_loop

    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Print 16-bit Decimal Number
;==============================================================================
; Input: AX = number
;        DH = row
;        DL = column (updated)
;        AH (current_attr) used
;==============================================================================
diag_print_dec16:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    mov     bx, ax                  ; Save number
    mov     si, .buffer + 5         ; End of buffer
    mov     byte [si], 0            ; Null terminate

    ; Convert to decimal
    mov     ax, bx
    mov     cx, 10
.convert:
    dec     si
    xor     dx, dx
    div     cx                      ; AX = quotient, DX = remainder
    add     dl, '0'
    mov     [si], dl
    test    ax, ax
    jnz     .convert

    ; Print string
    pop     dx                      ; Restore position
    push    dx
    mov     ah, [current_attr]
.print:
    lodsb
    test    al, al
    jz      .done
    call    video_putc_at
    inc     dl
    jmp     .print

.done:
    ; Update column in stack
    pop     ax                      ; Original DX
    pop     ax                      ; Original SI
    push    dx                      ; New DL
    push    ax

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.buffer: times 6 db 0

;==============================================================================
; Diagnostics Strings
;==============================================================================
diag_title:         db " FluxRipper HDD Diagnostics ", 0
diag_status_bar:    db " ESC=Exit  1-6=Select Test ", 0
diag_drive_hdr:     db "Drive   Cyl    Hd   Sec   Size", 0
diag_drive_prefix:  db "Drive ", 0
diag_not_present:   db "Not Present", 0
diag_mb_suffix:     db " MB", 0

diag_opt_surface:   db ") Surface Scan - Read all sectors", 0
diag_opt_seek:      db ") Seek Test - Exercise head positioning", 0
diag_opt_flux:      db ") Flux Histogram - Signal analysis", 0
diag_opt_errors:    db ") Error Log - View logged errors", 0
diag_opt_health:    db ") Health Monitor - Drive condition", 0
diag_opt_signal:    db ") Signal Quality - Read channel stats", 0
diag_opt_config:    db ") Controller Config - Enable/disable", 0
diag_opt_exit:      db "ESC) Return to boot", 0

diag_select_drive:  db "Select drive (0 or 1): ", 0
diag_no_drive:      db "Drive not present!", 0

diag_surface_title: db " Surface Scan ", 0
diag_scanning:      db "Scanning...", 0
diag_cylinder:      db "Cylinder: ", 0
diag_error_at:      db "Error at: ", 0
diag_scan_complete: db "Scan Complete", 0
diag_errors_found:  db "Errors found: ", 0

diag_seek_title:    db " Seek Test ", 0
diag_seek_running:  db "Running seek test...", 0
diag_seeks_done:    db "Seeks done: ", 0
diag_seek_complete: db "Seek Test Complete", 0

diag_flux_title:    db " Flux Histogram ", 0
diag_flux_axis:     db "0ns                          1600ns", 0

diag_errlog_title:  db " Error Log ", 0
diag_errlog_hdr:    db "# Time   C/H/S      Type  Cmd  Info", 0

diag_health_title:  db " Drive Health Monitor ", 0
diag_health_overall: db "Overall Health:", 0
diag_health_media:  db "Media Quality: ", 0
diag_health_head:   db "Head Condition:", 0
diag_health_spindle: db "Spindle Health:", 0
diag_health_temp:   db "Drive Temperature:", 0
diag_celsius:       db " C", 0

diag_signal_title:  db " Signal Quality ", 0
diag_sig_amplitude: db "Signal Amplitude:", 0
diag_sig_snr:       db "Signal/Noise Ratio:", 0
diag_sig_jitter:    db "Timing Jitter:   ", 0
diag_sig_pll:       db "PLL Lock Status: ", 0
diag_mv_suffix:     db " mV", 0
diag_db_suffix:     db " dB", 0
diag_ns_suffix:     db " ns", 0
diag_locked:        db "LOCKED", 0
diag_unlocked:      db "UNLOCKED", 0

;==============================================================================
; Controller Configuration
;==============================================================================
; Allows user to enable/disable FDC and WD HDD controllers.
;
; Edge cases handled:
;   - Cannot disable WD from HDD BIOS (chicken-and-egg prevention)
;   - Uses current_base instead of hardcoded WD_BASE_PRIMARY (XT mode fix)
;   - Config lock detection and unlock option
;   - Flash timeout detection with proper error reporting
;   - Busy check before changes (checks WD BSY status)
;   - Shows which controller hosts config registers
;   - PnP override warning
;==============================================================================
diag_controller_config:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    call    video_clear_screen

    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_config_title
    call    video_puts_centered

    ; Get current WD base from runtime variable (handles XT mode at 0x320)
    mov     bx, [cs:current_base]
    mov     [.config_base], bx

    ; Check if FluxRipper config registers are present
    mov     dx, bx
    add     dx, CFG_REG_BASE + CFG_MAGIC
    in      al, dx
    cmp     al, CFG_MAGIC_VALUE
    jne     .no_config

.show_status:
    ; Read current configuration
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_CTRL
    in      al, dx
    mov     bl, al                      ; Save config in BL
    mov     [.saved_ctrl], al

    ; Check if config is locked - show warning
    test    bl, CFG_CTRL_LOCKED
    jz      .not_locked
    mov     dh, 2
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_locked_warn
    call    video_puts_at
.not_locked:

    ; Read status for presence checking
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_STATUS
    in      al, dx
    mov     [.saved_status], al

    ; Show FDC status - check if FDC hardware is present
    mov     dh, 4
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_cfg_fdc
    call    video_puts_at
    add     dl, 20

    mov     al, [.saved_status]
    test    al, CFG_STAT_FDC_PRESENT
    jz      .fdc_not_installed

    test    bl, CFG_CTRL_FDC_EN
    jz      .fdc_disabled
    mov     si, diag_cfg_enabled
    mov     ah, ATTR_SUCCESS
    jmp     .print_fdc
.fdc_disabled:
    mov     si, diag_cfg_disabled
    mov     ah, ATTR_ERROR
.print_fdc:
    call    video_puts_at
    jmp     .show_wd_status

.fdc_not_installed:
    mov     ah, ATTR_DIM
    mov     si, diag_cfg_not_installed
    call    video_puts_at

.show_wd_status:
    ; Show WD HDD status (with note that it can't be disabled from here)
    ; Check if WD hardware is present
    mov     dh, 6
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_cfg_wd
    call    video_puts_at
    add     dl, 20

    mov     al, [.saved_status]
    test    al, CFG_STAT_WD_PRESENT
    jz      .wd_not_installed

    test    bl, CFG_CTRL_WD_EN
    jz      .wd_disabled
    mov     si, diag_cfg_enabled
    mov     ah, ATTR_SUCCESS
    jmp     .print_wd
.wd_disabled:
    mov     si, diag_cfg_disabled
    mov     ah, ATTR_ERROR
.print_wd:
    call    video_puts_at
    ; Add note about WD being the config host
    add     dl, 9
    mov     ah, ATTR_DIM
    mov     si, diag_cfg_wd_host
    call    video_puts_at
    jmp     .show_slot_type

.wd_not_installed:
    mov     ah, ATTR_DIM
    mov     si, diag_cfg_not_installed
    call    video_puts_at

.show_slot_type:
    ; Show slot type from status register (already have it in .saved_status)
    mov     al, [.saved_status]
    mov     dh, 8
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_cfg_slot
    call    video_puts_at
    add     dl, 20
    test    al, CFG_STAT_16BIT
    jnz     .slot_16bit
    test    al, CFG_STAT_8BIT
    jnz     .slot_8bit
    mov     si, diag_cfg_unknown
    jmp     .print_slot
.slot_16bit:
    mov     si, diag_cfg_16bit
    jmp     .print_slot
.slot_8bit:
    mov     si, diag_cfg_8bit
.print_slot:
    call    video_puts_at

    ; Show current I/O base (useful for debugging XT vs AT)
    mov     dh, 8
    mov     dl, 45
    mov     ah, ATTR_DIM
    mov     si, diag_cfg_iobase
    call    video_puts_at
    add     dl, 10
    mov     ax, [.config_base]
    call    diag_print_hex16

    ; Show PnP status
    mov     al, [.saved_status]
    mov     dh, 10
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_cfg_mode
    call    video_puts_at
    add     dl, 20
    test    al, CFG_STAT_PNP
    jz      .pnp_inactive
    mov     si, diag_cfg_pnp
    call    video_puts_at
    ; Show PnP override warning
    mov     dh, 10
    mov     dl, 40
    mov     ah, ATTR_DIM
    mov     si, diag_cfg_pnp_warn
    call    video_puts_at
    jmp     .show_personality
.pnp_inactive:
    mov     si, diag_cfg_legacy
    call    video_puts_at

.show_personality:
    ; Show WD personality
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_STATUS
    in      al, dx
    shr     al, 4
    and     al, 0x03
    mov     dh, 12
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_cfg_personality
    call    video_puts_at
    add     dl, 20
    cmp     al, PERSONALITY_WD1002
    je      .pers_1002
    cmp     al, PERSONALITY_WD1003
    je      .pers_1003
    cmp     al, PERSONALITY_WD1006
    je      .pers_1006
    mov     si, diag_pers_1007
    jmp     .print_pers
.pers_1002:
    mov     si, diag_pers_1002
    jmp     .print_pers
.pers_1003:
    mov     si, diag_pers_1003
    jmp     .print_pers
.pers_1006:
    mov     si, diag_pers_1006
.print_pers:
    call    video_puts_at

    ; Show config menu (modified - FDC toggle only, WD shows warning)
    mov     dh, 15
    mov     dl, 5
    mov     ah, ATTR_HIGHLIGHT
    mov     si, diag_cfg_menu1
    call    video_puts_at
    mov     dh, 16
    mov     si, diag_cfg_menu2
    call    video_puts_at
    mov     dh, 17
    mov     si, diag_cfg_menu3
    call    video_puts_at

    ; Show unlock option if locked
    mov     al, [.saved_ctrl]
    test    al, CFG_CTRL_LOCKED
    jz      .config_key_loop
    mov     dh, 18
    mov     si, diag_cfg_unlock
    call    video_puts_at

.config_key_loop:
    call    kbd_get

    ; Check for '1' - toggle FDC
    cmp     al, '1'
    je      .toggle_fdc

    ; Check for '2' - toggle WD (BLOCKED - show warning)
    cmp     al, '2'
    je      .block_wd_toggle

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
    cmp     ah, KEY_ESC
    je      .config_exit

    jmp     .config_key_loop

.toggle_fdc:
    ; Check if config is locked
    mov     al, [.saved_ctrl]
    test    al, CFG_CTRL_LOCKED
    jnz     .config_locked_error

    ; Check if WD controller is busy
    call    .check_wd_busy
    jc      .busy_error

    ; Read current, toggle FDC bit, write back
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_CTRL
    in      al, dx
    xor     al, CFG_CTRL_FDC_EN
    out     dx, al
    ; Refresh display
    call    video_clear_screen
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_config_title
    call    video_puts_centered
    jmp     .show_status

.block_wd_toggle:
    ; Cannot disable WD from HDD BIOS - would lock out config access
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_cannot_wd
    call    video_puts_at
    jmp     .config_key_loop

.unlock_config:
    ; Write CTRL with lock bit cleared
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_CTRL
    in      al, dx
    and     al, ~CFG_CTRL_LOCKED
    out     dx, al
    ; Refresh display
    call    video_clear_screen
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_config_title
    call    video_puts_centered
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_SUCCESS
    mov     si, diag_cfg_unlocked
    call    video_puts_at
    jmp     .show_status

.config_locked_error:
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_locked_err
    call    video_puts_at
    jmp     .config_key_loop

.busy_error:
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_busy_err
    call    video_puts_at
    jmp     .config_key_loop

.save_flash:
    ; Check if config is locked
    mov     al, [.saved_ctrl]
    test    al, CFG_CTRL_LOCKED
    jnz     .config_locked_error

    ; Check if flash already busy
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_STATUS
    in      al, dx
    test    al, CFG_STAT_FLASH_BUSY
    jnz     .flash_busy_error

    ; Write magic value to save register
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_SAVE
    mov     al, CFG_SAVE_MAGIC
    out     dx, al

    ; Wait for flash operation (poll status) with timeout tracking
    mov     cx, 1000                    ; Timeout counter
    mov     byte [.flash_timeout], 0
.wait_flash:
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_STATUS
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
    cmp     byte [.flash_timeout], 1
    je      .flash_timeout_error

    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_SUCCESS
    mov     si, diag_cfg_saved
    call    video_puts_at
    jmp     .config_key_loop

.flash_timeout_error:
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_timeout
    call    video_puts_at
    jmp     .config_key_loop

.flash_busy_error:
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_flash_busy
    call    video_puts_at
    jmp     .config_key_loop

.restore_defaults:
    ; Check if config is locked
    mov     al, [.saved_ctrl]
    test    al, CFG_CTRL_LOCKED
    jnz     .config_locked_error

    ; Write magic value to restore register
    mov     dx, [.config_base]
    add     dx, CFG_REG_BASE + CFG_RESTORE
    mov     al, CFG_RESTORE_MAGIC
    out     dx, al
    ; Refresh display
    call    video_clear_screen
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_config_title
    call    video_puts_centered
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_cfg_restored
    call    video_puts_at
    jmp     .show_status

.no_config:
    mov     dh, 4
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_notfound
    call    video_puts_at
    ; Show the base address we tried
    mov     dh, 6
    mov     dl, 5
    mov     ah, ATTR_DIM
    mov     si, diag_cfg_tried_base
    call    video_puts_at
    add     dl, 15
    mov     ax, [.config_base]
    call    diag_print_hex16
    call    kbd_wait_any

.config_exit:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;------------------------------------------------------------------------------
; Check if WD controller is busy
; Returns: CF=1 if busy, CF=0 if idle
;------------------------------------------------------------------------------
.check_wd_busy:
    push    ax
    push    dx
    ; Read WD status register
    mov     dx, [.config_base]
    add     dx, WD_STATUS
    in      al, dx
    test    al, 0x80                    ; BSY bit
    jz      .wd_not_busy
    stc                                 ; Set carry - busy
    jmp     .wd_busy_done
.wd_not_busy:
    clc                                 ; Clear carry - idle
.wd_busy_done:
    pop     dx
    pop     ax
    ret

;------------------------------------------------------------------------------
; Print 16-bit hex value
; Input: AX = value, DH/DL = position
;------------------------------------------------------------------------------
diag_print_hex16:
    push    ax
    push    bx
    push    cx
    ; Print 0x prefix
    mov     al, '0'
    call    video_putc_at
    inc     dl
    mov     al, 'x'
    call    video_putc_at
    inc     dl
    pop     cx
    push    cx
    ; High byte
    mov     al, ch
    shr     al, 4
    call    .hex_digit
    call    video_putc_at
    inc     dl
    mov     al, ch
    and     al, 0x0F
    call    .hex_digit
    call    video_putc_at
    inc     dl
    ; Low byte
    mov     al, cl
    shr     al, 4
    call    .hex_digit
    call    video_putc_at
    inc     dl
    mov     al, cl
    and     al, 0x0F
    call    .hex_digit
    call    video_putc_at
    inc     dl
    pop     cx
    pop     bx
    pop     ax
    ret
.hex_digit:
    cmp     al, 10
    jb      .decimal
    add     al, 'A' - 10
    ret
.decimal:
    add     al, '0'
    ret

; Local variables
.config_base:   dw 0
.saved_ctrl:    db 0
.saved_status:  db 0
.flash_timeout: db 0

;==============================================================================
; Interleave Configuration Menu
;==============================================================================
; Allows viewing and changing disk interleave settings.
;
; Features:
;   - Shows current detected interleave
;   - Shows override setting (auto or 1-8)
;   - Set interleave override for formatting
;==============================================================================
diag_interleave_config:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    call    video_clear_screen

    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_intlv_title
    call    video_puts_centered

    ; Get current WD base
    mov     bx, [cs:current_base]
    mov     [.intlv_base], bx

    ; Check if FluxRipper config registers are present
    mov     dx, bx
    add     dx, CFG_REG_BASE + CFG_MAGIC
    in      al, dx
    cmp     al, CFG_MAGIC_VALUE
    jne     .intlv_no_config

.intlv_show_status:
    ; Read detected interleave
    mov     dx, [.intlv_base]
    add     dx, CFG_REG_BASE + CFG_INTLV_STAT
    in      al, dx
    and     al, 0x0F
    mov     [.intlv_detected], al

    ; Read current override setting
    mov     dx, [.intlv_base]
    add     dx, CFG_REG_BASE + CFG_INTLV_CTRL
    in      al, dx
    and     al, 0x0F
    mov     [.intlv_override], al

    ; Display detected interleave
    mov     dh, 4
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_intlv_detected
    call    video_puts_at
    add     dl, 22
    mov     al, [.intlv_detected]
    cmp     al, 0
    je      .detected_unknown
    add     al, '0'
    call    video_putc_at
    inc     dl
    mov     si, diag_intlv_ratio
    call    video_puts_at
    jmp     .show_override

.detected_unknown:
    mov     si, diag_intlv_unknown
    call    video_puts_at

.show_override:
    ; Display override setting
    mov     dh, 6
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, diag_intlv_override
    call    video_puts_at
    add     dl, 22
    mov     al, [.intlv_override]
    cmp     al, 0
    je      .override_auto
    ; Show numeric value
    add     al, '0'
    mov     ah, ATTR_HIGHLIGHT
    call    video_putc_at
    inc     dl
    mov     ah, ATTR_NORMAL
    mov     si, diag_intlv_ratio
    call    video_puts_at
    jmp     .show_explanation

.override_auto:
    mov     ah, ATTR_SUCCESS
    mov     si, diag_intlv_auto
    call    video_puts_at

.show_explanation:
    ; Show explanation
    mov     dh, 9
    mov     dl, 5
    mov     ah, ATTR_DIM
    mov     si, diag_intlv_explain1
    call    video_puts_at
    mov     dh, 10
    mov     si, diag_intlv_explain2
    call    video_puts_at
    mov     dh, 11
    mov     si, diag_intlv_explain3
    call    video_puts_at

    ; Show menu options
    mov     dh, 14
    mov     dl, 5
    mov     ah, ATTR_HIGHLIGHT
    mov     si, diag_intlv_menu1
    call    video_puts_at
    mov     dh, 15
    mov     si, diag_intlv_menu2
    call    video_puts_at
    mov     dh, 16
    mov     si, diag_intlv_menu3
    call    video_puts_at
    mov     dh, 18
    mov     ah, ATTR_DIM
    mov     si, diag_intlv_menu_esc
    call    video_puts_at

.intlv_key_loop:
    call    kbd_get

    ; Check for ESC
    cmp     ah, KEY_ESC
    je      .intlv_exit

    ; Check for 'A' or 'a' - set to auto
    cmp     al, 'A'
    je      .set_auto
    cmp     al, 'a'
    je      .set_auto

    ; Check for digits 1-8 - set override
    cmp     al, '1'
    jb      .intlv_key_loop
    cmp     al, '8'
    ja      .intlv_key_loop

    ; Set numeric override
    sub     al, '0'
    mov     dx, [.intlv_base]
    add     dx, CFG_REG_BASE + CFG_INTLV_CTRL
    out     dx, al
    ; Refresh display
    call    video_clear_screen
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_intlv_title
    call    video_puts_centered
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_SUCCESS
    mov     si, diag_intlv_set_msg
    call    video_puts_at
    jmp     .intlv_show_status

.set_auto:
    ; Set interleave to auto (0)
    mov     dx, [.intlv_base]
    add     dx, CFG_REG_BASE + CFG_INTLV_CTRL
    xor     al, al
    out     dx, al
    ; Refresh display
    call    video_clear_screen
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_intlv_title
    call    video_puts_centered
    mov     dh, 20
    mov     dl, 5
    mov     ah, ATTR_SUCCESS
    mov     si, diag_intlv_auto_msg
    call    video_puts_at
    jmp     .intlv_show_status

.intlv_no_config:
    mov     dh, 4
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_notfound
    call    video_puts_at
    call    kbd_wait_any

.intlv_exit:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; Local variables
.intlv_base:     dw 0
.intlv_detected: db 0
.intlv_override: db 0

;==============================================================================
; Interleave Strings
;==============================================================================
diag_intlv_title:    db " Drive Interleave Configuration ", 0
diag_intlv_detected: db "Detected Interleave:", 0
diag_intlv_override: db "Override Setting:", 0
diag_intlv_ratio:    db ":1", 0
diag_intlv_auto:     db "Auto (preserve)", 0
diag_intlv_unknown:  db "(not detected)", 0

diag_intlv_explain1: db "Auto mode preserves the existing disk interleave pattern.", 0
diag_intlv_explain2: db "Override forces a specific interleave for FORMAT operations.", 0
diag_intlv_explain3: db "Common: 1:1 (fast), 2:1 (286), 3:1 (XT), 6:1 (slow XT)", 0

diag_intlv_menu1:    db "[A] Set Auto (preserve existing)", 0
diag_intlv_menu2:    db "[1-8] Set interleave override (1:1 to 8:1)", 0
diag_intlv_menu3:    db "[S] Save to flash", 0
diag_intlv_menu_esc: db "[ESC] Back to main menu", 0

diag_intlv_set_msg:  db "Interleave override set.", 0
diag_intlv_auto_msg: db "Interleave set to Auto (preserve).", 0

diag_opt_interleave: db "Drive Interleave", 0
diag_opt_benchmark:  db "Interleave Benchmark", 0

;==============================================================================
; Interleave Benchmark
;==============================================================================
; SpinRite-style benchmark that tests transfer performance at different
; interleave settings. Shows the effect of interleave on system performance.
;
; Two modes:
;   - FluxRipper mode: Track buffer enabled (all interleaves equal)
;   - Stock Sim mode: Track buffer bypassed (shows actual interleave effects)
;==============================================================================
diag_interleave_benchmark:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp

    call    video_clear_screen

    ; Title
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_bench_title
    call    video_puts_centered

    ; Get current WD base
    mov     bx, [cs:current_base]
    mov     [.bench_base], bx

    ; Check if FluxRipper config registers are present
    mov     dx, bx
    add     dx, CFG_REG_BASE + CFG_MAGIC
    in      al, dx
    cmp     al, CFG_MAGIC_VALUE
    jne     .bench_no_config

    ; Initialize benchmark parameters
    mov     byte [.bench_mode], 0       ; 0 = FluxRipper, 1 = Stock sim
    mov     byte [.bench_drive], 0x80   ; Default drive 0
    mov     word [.bench_cyl], 50       ; Test cylinder (middle-ish)

.bench_run_test:
    ; Show current settings
    call    .bench_show_header

    ; Set bypass mode based on bench_mode
    mov     dx, [.bench_base]
    add     dx, CFG_REG_BASE + CFG_WD
    in      al, dx
    mov     [.saved_wd_cfg], al         ; Save original config
    cmp     byte [.bench_mode], 0
    je      .bench_no_bypass
    or      al, CFG_WD_BUF_BYPASS       ; Enable bypass for stock sim
    jmp     .bench_set_bypass
.bench_no_bypass:
    and     al, ~CFG_WD_BUF_BYPASS      ; Disable bypass for FluxRipper mode
.bench_set_bypass:
    out     dx, al

    ; Save original interleave setting
    mov     dx, [.bench_base]
    add     dx, CFG_REG_BASE + CFG_INTLV_CTRL
    in      al, dx
    mov     [.saved_intlv], al

    ; Test each interleave 1-6
    mov     byte [.current_intlv], 1

.bench_intlv_loop:
    ; Set interleave override
    mov     dx, [.bench_base]
    add     dx, CFG_REG_BASE + CFG_INTLV_CTRL
    mov     al, [.current_intlv]
    out     dx, al

    ; Display "Testing X:1..."
    mov     dh, 5
    add     dh, [.current_intlv]
    mov     dl, 3
    mov     ah, ATTR_NORMAL
    mov     si, diag_bench_testing_short
    call    video_puts_at
    add     dl, 12
    mov     al, [.current_intlv]
    add     al, '0'
    call    video_putc_at

    ; Invalidate cache by seeking to cylinder 0 then back
    mov     ah, 0x0C                    ; Seek
    mov     ch, 0                       ; Cylinder 0
    mov     cl, 0
    mov     dh, 0                       ; Head 0
    mov     dl, [.bench_drive]
    int     0x13

    ; Seek to test cylinder
    mov     ah, 0x0C                    ; Seek
    mov     cx, [.bench_cyl]
    mov     ch, cl                      ; Cylinder low
    mov     cl, 0                       ; Sector 0 (for seek)
    mov     dh, 0                       ; Head 0
    mov     dl, [.bench_drive]
    int     0x13

    ; Get start tick
    xor     ax, ax
    mov     es, ax
    mov     ax, [es:0x046C]
    mov     [.start_tick], ax

    ; Read track 10 times
    mov     byte [.iter_count], 10

.bench_read_loop:
    ; Read all sectors on track (1-17)
    mov     ah, 0x02                    ; Read sectors
    mov     al, 17                      ; 17 sectors (full track)
    mov     cx, [.bench_cyl]
    mov     ch, cl                      ; Cylinder low
    mov     cl, 1                       ; Start at sector 1
    mov     dh, 0                       ; Head 0
    mov     dl, [.bench_drive]
    mov     bx, scratch_buffer
    push    es
    push    cs
    pop     es
    int     0x13
    pop     es
    jc      .bench_read_error

    dec     byte [.iter_count]
    jnz     .bench_read_loop

    ; Get end tick
    xor     ax, ax
    mov     es, ax
    mov     ax, [es:0x046C]
    mov     [.end_tick], ax

    ; Calculate elapsed ticks
    sub     ax, [.start_tick]
    mov     [.elapsed_ticks], ax

    ; Calculate sectors/sec
    ; sectors_read = 17 * 10 = 170
    ; ticks_per_sec = 18.2
    ; sectors_per_sec = 170 * 18.2 / elapsed_ticks = 3094 / elapsed
    mov     ax, 3094                    ; 170 * 18.2 (approx)
    xor     dx, dx
    mov     bx, [.elapsed_ticks]
    cmp     bx, 0
    je      .bench_div_zero
    div     bx                          ; AX = sectors/sec
    jmp     .bench_got_result
.bench_div_zero:
    mov     ax, 9999                    ; Max value if instant
.bench_got_result:

    ; Store result
    mov     bl, [.current_intlv]
    dec     bl
    shl     bl, 1                       ; *2 for word offset
    xor     bh, bh
    mov     [.bench_results + bx], ax

    ; Display result row
    call    .bench_display_row

    ; Next interleave
    inc     byte [.current_intlv]
    cmp     byte [.current_intlv], 7
    jb      .bench_intlv_loop

    ; Restore original interleave setting
    mov     dx, [.bench_base]
    add     dx, CFG_REG_BASE + CFG_INTLV_CTRL
    mov     al, [.saved_intlv]
    out     dx, al

    ; Restore original WD config (bypass mode)
    mov     dx, [.bench_base]
    add     dx, CFG_REG_BASE + CFG_WD
    mov     al, [.saved_wd_cfg]
    out     dx, al

    ; Find best result and show recommendation
    call    .bench_show_recommendation

    ; Show menu
    mov     dh, 20
    mov     dl, 3
    mov     ah, ATTR_HIGHLIGHT
    mov     si, diag_bench_menu
    call    video_puts_at

.bench_key_loop:
    call    kbd_get

    ; ESC - exit
    cmp     ah, KEY_ESC
    je      .bench_exit

    ; M - toggle mode
    cmp     al, 'M'
    je      .bench_toggle_mode
    cmp     al, 'm'
    je      .bench_toggle_mode

    ; R - re-run
    cmp     al, 'R'
    je      .bench_rerun
    cmp     al, 'r'
    je      .bench_rerun

    jmp     .bench_key_loop

.bench_toggle_mode:
    xor     byte [.bench_mode], 1       ; Toggle 0/1
    call    video_clear_screen
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_bench_title
    call    video_puts_centered
    jmp     .bench_run_test

.bench_rerun:
    call    video_clear_screen
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, diag_bench_title
    call    video_puts_centered
    jmp     .bench_run_test

.bench_read_error:
    mov     dh, 22
    mov     dl, 3
    mov     ah, ATTR_ERROR
    mov     si, diag_bench_error
    call    video_puts_at
    jmp     .bench_key_loop

.bench_no_config:
    mov     dh, 4
    mov     dl, 5
    mov     ah, ATTR_ERROR
    mov     si, diag_cfg_notfound
    call    video_puts_at
    call    kbd_wait_any

.bench_exit:
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;------------------------------------------------------------------------------
; Show benchmark header
;------------------------------------------------------------------------------
.bench_show_header:
    push    ax
    push    dx
    push    si

    ; Drive info
    mov     dh, 2
    mov     dl, 3
    mov     ah, ATTR_NORMAL
    mov     si, diag_bench_drive
    call    video_puts_at
    add     dl, 7
    mov     al, [.bench_drive]
    sub     al, 0x80
    add     al, '0'
    call    video_putc_at

    ; Mode
    mov     dh, 2
    mov     dl, 40
    mov     ah, ATTR_NORMAL
    mov     si, diag_bench_mode_lbl
    call    video_puts_at
    add     dl, 6
    cmp     byte [.bench_mode], 0
    jne     .header_stock
    mov     ah, ATTR_SUCCESS
    mov     si, diag_bench_mode_fr
    jmp     .header_mode_print
.header_stock:
    mov     ah, ATTR_ERROR
    mov     si, diag_bench_mode_stk
.header_mode_print:
    call    video_puts_at

    ; Column headers
    mov     dh, 4
    mov     dl, 3
    mov     ah, ATTR_HIGHLIGHT
    mov     si, diag_bench_header
    call    video_puts_at

    ; Divider
    mov     dh, 5
    mov     dl, 3
    mov     ah, ATTR_DIM
    mov     si, diag_bench_divider
    call    video_puts_at

    pop     si
    pop     dx
    pop     ax
    ret

;------------------------------------------------------------------------------
; Display one result row
; Input: [.current_intlv] = interleave being displayed
;------------------------------------------------------------------------------
.bench_display_row:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; Calculate row
    mov     dh, 5
    add     dh, [.current_intlv]
    mov     dl, 3

    ; Interleave value
    mov     ah, ATTR_NORMAL
    mov     al, ' '
    call    video_putc_at
    inc     dl
    inc     dl
    mov     al, [.current_intlv]
    add     al, '0'
    call    video_putc_at
    inc     dl
    mov     si, diag_intlv_ratio
    call    video_puts_at
    add     dl, 8

    ; Get result
    mov     bl, [.current_intlv]
    dec     bl
    shl     bl, 1
    xor     bh, bh
    mov     ax, [.bench_results + bx]

    ; Sectors/sec (right-aligned in 5 chars)
    call    .print_dec16_padded
    add     dl, 8

    ; KB/s = sectors/sec / 2
    shr     ax, 1
    call    .print_dec16_padded
    add     dl, 8

    ; Get result again for rating
    mov     bl, [.current_intlv]
    dec     bl
    shl     bl, 1
    xor     bh, bh
    mov     ax, [.bench_results + bx]

    ; Rating bar (compare to best possible ~289 sectors/sec)
    ; bars = result * 12 / 289
    mov     cx, 12
    mul     cx
    mov     cx, 289
    div     cx                          ; AX = number of bars (0-12)
    cmp     ax, 12
    jbe     .bar_ok
    mov     ax, 12
.bar_ok:
    mov     cx, ax
    mov     ah, ATTR_SUCCESS
    jcxz    .bar_done
.bar_loop:
    mov     al, 0xDB                    ; Full block char
    call    video_putc_at
    inc     dl
    loop    .bar_loop
.bar_done:

    ; Rating text
    inc     dl
    mov     bl, [.current_intlv]
    dec     bl
    shl     bl, 1
    xor     bh, bh
    mov     ax, [.bench_results + bx]

    ; Determine rating based on sectors/sec
    ; 250+ = Optimal, 150-249 = Good, 80-149 = Fair, 30-79 = Slow, <30 = Missed
    cmp     ax, 250
    jae     .rate_optimal
    cmp     ax, 150
    jae     .rate_good
    cmp     ax, 80
    jae     .rate_fair
    cmp     ax, 30
    jae     .rate_slow
    mov     ah, ATTR_ERROR
    mov     si, diag_bench_missed
    jmp     .rate_print
.rate_optimal:
    mov     ah, ATTR_SUCCESS
    mov     si, diag_bench_optimal
    jmp     .rate_print
.rate_good:
    mov     ah, ATTR_NORMAL
    mov     si, diag_bench_good
    jmp     .rate_print
.rate_fair:
    mov     ah, ATTR_DIM
    mov     si, diag_bench_fair
    jmp     .rate_print
.rate_slow:
    mov     ah, ATTR_ERROR
    mov     si, diag_bench_slow
.rate_print:
    call    video_puts_at

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;------------------------------------------------------------------------------
; Print 16-bit decimal, right-padded
; Input: AX = value, DH/DL = position
;------------------------------------------------------------------------------
.print_dec16_padded:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Convert to decimal (max 5 digits)
    mov     bx, 10000
    mov     cx, 5
    mov     byte [.leading], 1          ; Skip leading zeros

.dec_loop:
    xor     dx, dx
    div     bx
    cmp     al, 0
    jne     .dec_nonzero
    cmp     byte [.leading], 1
    je      .dec_space
.dec_nonzero:
    mov     byte [.leading], 0
    add     al, '0'
    jmp     .dec_print
.dec_space:
    mov     al, ' '
.dec_print:
    push    ax
    push    dx
    mov     ah, ATTR_NORMAL
    ; Get position from stack
    mov     dx, [esp+8]                 ; Saved DX
    call    video_putc_at
    inc     byte [esp+8]                ; Increment DL
    pop     dx
    pop     ax

    ; Next digit
    mov     ax, dx
    push    dx
    xor     dx, dx
    push    ax
    mov     ax, bx
    mov     bx, 10
    div     bx
    mov     bx, ax
    pop     ax
    pop     dx

    loop    .dec_loop

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.leading: db 0

;------------------------------------------------------------------------------
; Show recommendation based on results
;------------------------------------------------------------------------------
.bench_show_recommendation:
    push    ax
    push    bx
    push    dx
    push    si

    ; Find best interleave
    mov     cx, 6
    mov     bx, 0                       ; Best value
    mov     al, 1                       ; Best interleave
    mov     ah, 1                       ; Current interleave

.find_best:
    push    ax
    dec     ah
    shl     ah, 1
    xor     al, al
    xchg    al, ah
    mov     si, ax
    mov     ax, [.bench_results + si]
    cmp     ax, bx
    jbe     .not_best
    mov     bx, ax
    pop     ax
    mov     al, ah                      ; This is best
    push    ax
.not_best:
    pop     ax
    inc     ah
    loop    .find_best

    mov     [.best_intlv], al

    ; Show detected interleave
    mov     dh, 14
    mov     dl, 3
    mov     ah, ATTR_NORMAL
    mov     si, diag_bench_detected
    call    video_puts_at
    add     dl, 22
    mov     dx, [.bench_base]
    add     dx, CFG_REG_BASE + CFG_INTLV_STAT
    in      al, dx
    and     al, 0x0F
    cmp     al, 0
    je      .det_unknown
    add     al, '0'
    mov     dh, 14
    mov     dl, 25
    mov     ah, ATTR_HIGHLIGHT
    call    video_putc_at
    inc     dl
    mov     si, diag_intlv_ratio
    call    video_puts_at
    jmp     .show_rec

.det_unknown:
    mov     dh, 14
    mov     dl, 25
    mov     si, diag_intlv_unknown
    call    video_puts_at

.show_rec:
    ; Show recommendation
    mov     dh, 16
    mov     dl, 3
    mov     ah, ATTR_HIGHLIGHT
    mov     si, diag_bench_rec
    call    video_puts_at

    mov     dh, 17
    mov     dl, 3
    cmp     byte [.bench_mode], 0
    jne     .rec_stock
    ; FluxRipper mode - all interleaves work
    mov     ah, ATTR_SUCCESS
    mov     si, diag_bench_any
    call    video_puts_at
    jmp     .rec_done

.rec_stock:
    ; Stock mode - show best interleave
    mov     ah, ATTR_NORMAL
    mov     si, diag_bench_best_is
    call    video_puts_at
    add     dl, 21
    mov     al, [.best_intlv]
    add     al, '0'
    mov     ah, ATTR_HIGHLIGHT
    call    video_putc_at
    inc     dl
    mov     ah, ATTR_NORMAL
    mov     si, diag_intlv_ratio
    call    video_puts_at

.rec_done:
    pop     si
    pop     dx
    pop     bx
    pop     ax
    ret

; Local variables
.bench_base:      dw 0
.bench_mode:      db 0                  ; 0 = FluxRipper, 1 = Stock sim
.bench_drive:     db 0x80
.bench_cyl:       dw 50
.current_intlv:   db 1
.iter_count:      db 0
.start_tick:      dw 0
.end_tick:        dw 0
.elapsed_ticks:   dw 0
.saved_intlv:     db 0
.saved_wd_cfg:    db 0
.best_intlv:      db 1
.bench_results:   times 6 dw 0          ; Results for interleave 1-6

;==============================================================================
; Benchmark Strings
;==============================================================================
diag_bench_title:       db " Interleave Benchmark ", 0
diag_bench_drive:       db "Drive: ", 0
diag_bench_mode_lbl:    db "Mode: ", 0
diag_bench_mode_fr:     db "[FluxRipper]", 0
diag_bench_mode_stk:    db "[Stock Sim] ", 0
diag_bench_header:      db "Intlv  Sect/s   KB/s    Rating", 0
diag_bench_divider:     db "-----  ------  ------  ----------------", 0
diag_bench_testing_short: db "Testing     ", 0
diag_bench_optimal:     db "Optimal", 0
diag_bench_good:        db "Good   ", 0
diag_bench_fair:        db "Fair   ", 0
diag_bench_slow:        db "Slow   ", 0
diag_bench_missed:      db "Missed ", 0
diag_bench_menu:        db "[M] Mode  [R] Re-run  [ESC] Back", 0
diag_bench_rec:         db "Recommendation:", 0
diag_bench_any:         db "Any interleave works with FluxRipper", 0
diag_bench_best_is:     db "Optimal interleave: ", 0
diag_bench_detected:    db "Current disk interleave:", 0
diag_bench_error:       db "Read error during benchmark!", 0

;==============================================================================
; Controller Config Strings
;==============================================================================
diag_config_title:  db " Controller Configuration ", 0
diag_cfg_fdc:       db "FDC (Floppy):", 0
diag_cfg_wd:        db "WD HDD:", 0
diag_cfg_wd_host:   db "(config host)", 0
diag_cfg_slot:      db "Slot Type:", 0
diag_cfg_iobase:   db "I/O Base:", 0
diag_cfg_mode:      db "Mode:", 0
diag_cfg_personality: db "WD Personality:", 0

diag_cfg_enabled:   db "ENABLED ", 0
diag_cfg_disabled:  db "DISABLED", 0
diag_cfg_not_installed: db "(not installed)", 0
diag_cfg_8bit:      db "8-bit (XT)", 0
diag_cfg_16bit:     db "16-bit (AT)", 0
diag_cfg_unknown:   db "Unknown", 0
diag_cfg_pnp:       db "Plug and Play", 0
diag_cfg_legacy:    db "Legacy", 0
diag_cfg_pnp_warn:  db "(OS may override)", 0

diag_cfg_locked_warn: db "*** Configuration is LOCKED ***", 0

diag_pers_1002:     db "WD1002 (XT MFM)", 0
diag_pers_1003:     db "WD1003 (AT MFM)", 0
diag_pers_1006:     db "WD1006 (AT RLL)", 0
diag_pers_1007:     db "WD1007 (ESDI)", 0

diag_cfg_menu1:     db "[1] Toggle FDC    [2] Toggle HDD (see note)", 0
diag_cfg_menu2:     db "[S] Save to flash [D] Restore defaults", 0
diag_cfg_menu3:     db "[ESC] Back to main menu", 0
diag_cfg_unlock:    db "[U] Unlock configuration", 0

diag_cfg_saved:     db "Configuration saved to flash.", 0
diag_cfg_restored:  db "Defaults restored.", 0
diag_cfg_unlocked:  db "Configuration unlocked.", 0
diag_cfg_notfound:  db "FluxRipper config registers not found.", 0
diag_cfg_tried_base: db "Tried I/O base:", 0

diag_cfg_cannot_wd: db "Cannot disable WD from HDD BIOS! Use FDD BIOS.", 0
diag_cfg_locked_err: db "Error: Config locked. Press [U] to unlock.", 0
diag_cfg_busy_err:  db "Error: Controller busy. Wait for I/O to complete.", 0
diag_cfg_timeout:   db "Error: Flash timeout! Settings NOT saved.", 0
diag_cfg_flash_busy: db "Error: Flash busy. Try again later.", 0

;==============================================================================
; Data Buffers
;==============================================================================
histogram_buf:  times 64 dw 0       ; 64 16-bit histogram values
scratch_buffer: times 512 db 0      ; Sector read buffer

%endif ; BUILD_16KB
