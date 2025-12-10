;==============================================================================
; FluxRipper HDD BIOS - Real-Time Monitor
;==============================================================================
; Displays real-time drive statistics in a compact overlay.
; Accessible via F3 during normal operation (hot-key TSR).
;
; Features:
;   - Live command counter
;   - Error rate display
;   - Current seek position
;   - Data transfer rate
;   - Temperature
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%if BUILD_16KB

;==============================================================================
; Monitor Constants
;==============================================================================
%define MON_ROW         0           ; Top row of display
%define MON_COL         50          ; Right side of screen
%define MON_WIDTH       28          ; Width of monitor box
%define MON_HEIGHT      12          ; Height of monitor box
%define MON_REFRESH     9           ; Refresh every ~0.5 sec (9 ticks)

;==============================================================================
; Monitor State
;==============================================================================
monitor_active:     db 0            ; 1 = monitor visible
monitor_saved:      times 336 db 0  ; Saved screen area (28*12*1 char+attr)
last_tick:          dw 0            ; Last refresh tick

;==============================================================================
; Toggle Monitor Display
;==============================================================================
; Called when F3 is pressed during operation.
;==============================================================================
monitor_toggle:
    push    ax
    push    ds

    push    cs
    pop     ds

    ; Toggle state
    xor     byte [monitor_active], 1
    jz      .hide

    ; Show monitor
    call    monitor_save_screen
    call    monitor_draw
    jmp     .done

.hide:
    call    monitor_restore_screen

.done:
    pop     ds
    pop     ax
    ret

;==============================================================================
; Save Screen Area Under Monitor
;==============================================================================
monitor_save_screen:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    es

    ; Source: video memory
    mov     ax, [video_seg]
    mov     es, ax

    ; Calculate starting offset
    mov     ax, MON_ROW
    mov     bl, SCREEN_WIDTH * 2
    mul     bl
    add     ax, MON_COL * 2
    mov     si, ax

    ; Destination: save buffer
    mov     di, monitor_saved

    ; Copy rows
    mov     cx, MON_HEIGHT
.row_loop:
    push    cx
    push    si

    ; Copy one row
    mov     cx, MON_WIDTH
.col_loop:
    mov     ax, [es:si]             ; Char + attr
    mov     [di], ax
    add     si, 2
    add     di, 2
    loop    .col_loop

    pop     si
    add     si, SCREEN_WIDTH * 2    ; Next row
    pop     cx
    loop    .row_loop

    pop     es
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Restore Screen Area Under Monitor
;==============================================================================
monitor_restore_screen:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    es

    ; Destination: video memory
    mov     ax, [video_seg]
    mov     es, ax

    ; Calculate starting offset
    mov     ax, MON_ROW
    mov     bl, SCREEN_WIDTH * 2
    mul     bl
    add     ax, MON_COL * 2
    mov     di, ax

    ; Source: save buffer
    mov     si, monitor_saved

    ; Copy rows
    mov     cx, MON_HEIGHT
.row_loop:
    push    cx
    push    di

    mov     cx, MON_WIDTH
.col_loop:
    mov     ax, [si]
    mov     [es:di], ax
    add     si, 2
    add     di, 2
    loop    .col_loop

    pop     di
    add     di, SCREEN_WIDTH * 2
    pop     cx
    loop    .row_loop

    pop     es
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Draw Monitor Box
;==============================================================================
monitor_draw:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; Draw box frame
    mov     dh, MON_ROW
    mov     dl, MON_COL
    mov     ch, MON_ROW + MON_HEIGHT - 1
    mov     cl, MON_COL + MON_WIDTH - 1
    mov     ah, ATTR_TITLE
    call    video_draw_box

    ; Fill interior with spaces
    mov     dh, MON_ROW + 1
.fill_loop:
    cmp     dh, MON_ROW + MON_HEIGHT - 1
    jge     .fill_done

    mov     dl, MON_COL + 1
    mov     cx, MON_WIDTH - 2
.space_loop:
    mov     al, ' '
    mov     ah, ATTR_NORMAL
    call    video_putc_at
    inc     dl
    loop    .space_loop

    inc     dh
    jmp     .fill_loop
.fill_done:

    ; Title
    mov     dh, MON_ROW
    mov     dl, MON_COL + 2
    mov     ah, ATTR_TITLE
    mov     si, mon_title
    call    video_puts_at

    ; Update values
    call    monitor_update

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Update Monitor Values
;==============================================================================
monitor_update:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; Commands executed
    mov     ax, INSTR_CMD_COUNT
    INSTR_SET_ADDR
    INSTR_READ_DATA                 ; DX:AX = command count

    mov     dh, MON_ROW + 2
    mov     dl, MON_COL + 2
    mov     ah, ATTR_NORMAL
    mov     si, mon_commands
    call    video_puts_at
    add     dl, 10
    call    mon_print_dec32

    ; Read count
    mov     ax, INSTR_READ_COUNT
    INSTR_SET_ADDR
    INSTR_READ_DATA

    mov     dh, MON_ROW + 3
    mov     dl, MON_COL + 2
    mov     si, mon_reads
    call    video_puts_at
    add     dl, 10
    call    mon_print_dec32

    ; Write count
    mov     ax, INSTR_WRITE_COUNT
    INSTR_SET_ADDR
    INSTR_READ_DATA

    mov     dh, MON_ROW + 4
    mov     dl, MON_COL + 2
    mov     si, mon_writes
    call    video_puts_at
    add     dl, 10
    call    mon_print_dec32

    ; Error total
    mov     ax, INSTR_ERR_TOTAL
    INSTR_SET_ADDR
    INSTR_READ_DATA
    push    dx
    push    ax

    mov     dh, MON_ROW + 5
    mov     dl, MON_COL + 2
    mov     si, mon_errors
    call    video_puts_at
    add     dl, 10

    pop     ax
    pop     dx
    ; Color code errors
    test    dx, dx
    jnz     .err_red
    test    ax, ax
    jz      .err_green
.err_red:
    mov     ah, ATTR_ERROR
    jmp     .show_err
.err_green:
    mov     ah, ATTR_SUCCESS
.show_err:
    mov     [current_attr], ah
    call    mon_print_dec32
    mov     byte [current_attr], ATTR_NORMAL

    ; Data rate
    mov     ax, INSTR_DATA_RATE
    INSTR_SET_ADDR
    INSTR_READ_DATA

    mov     dh, MON_ROW + 7
    mov     dl, MON_COL + 2
    mov     si, mon_datarate
    call    video_puts_at
    add     dl, 12

    ; Convert to KB/s (divide by 1024)
    mov     cx, 10
.rate_shift:
    shr     dx, 1
    rcr     ax, 1
    loop    .rate_shift

    xor     dx, dx                  ; Just show low word
    call    mon_print_dec32
    mov     si, mon_kbs
    call    video_puts_at

    ; Spindle RPM
    mov     ax, INSTR_RPM
    INSTR_SET_ADDR
    INSTR_READ_DATA

    mov     dh, MON_ROW + 8
    mov     dl, MON_COL + 2
    mov     si, mon_rpm
    call    video_puts_at
    add     dl, 12

    ; RPM is *10, so divide
    mov     bx, 10
    div     bx
    xor     dx, dx
    call    mon_print_dec32
    mov     si, mon_rpm_unit
    call    video_puts_at

    ; Temperature
    mov     ax, INSTR_TEMP_DRIVE
    INSTR_SET_ADDR
    INSTR_READ_DATA

    mov     dh, MON_ROW + 9
    mov     dl, MON_COL + 2
    mov     si, mon_temp
    call    video_puts_at
    add     dl, 12

    ; Temp is *10
    mov     bx, 10
    div     bx
    xor     dx, dx
    call    mon_print_dec32
    mov     si, mon_celsius
    call    video_puts_at

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Print 32-bit Decimal
;==============================================================================
; Input: DX:AX = 32-bit value
;        DH = row, DL = column (position)
;==============================================================================
mon_print_dec32:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; Save position
    mov     bx, dx                  ; BH=row, BL=col

    ; Handle 32-bit to decimal conversion
    ; For simplicity, just print low 16 bits if high is 0
    test    dx, dx
    jnz     .full_32

    ; Just 16-bit
    mov     si, .buffer + 10
    mov     byte [si], 0

    mov     cx, 10
.conv16:
    dec     si
    xor     dx, dx
    div     cx
    add     dl, '0'
    mov     [si], dl
    test    ax, ax
    jnz     .conv16
    jmp     .print

.full_32:
    ; Full 32-bit (simplified - just show "99999+")
    mov     si, mon_overflow
    jmp     .print

.print:
    mov     dh, bh
    mov     dl, bl
    mov     ah, [current_attr]
.print_loop:
    lodsb
    test    al, al
    jz      .done
    call    video_putc_at
    inc     dl
    jmp     .print_loop

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.buffer: times 12 db 0

;==============================================================================
; Check for Monitor Refresh
;==============================================================================
; Call this periodically (e.g., from timer hook or INT 13h).
; Updates display if monitor is active and enough time has passed.
;==============================================================================
monitor_check_refresh:
    push    ax
    push    bx
    push    ds
    push    es

    push    cs
    pop     ds

    ; Check if active
    cmp     byte [monitor_active], 0
    je      .done

    ; Check tick count
    xor     ax, ax
    mov     es, ax
    mov     ax, [es:0x046C]         ; BIOS tick counter
    mov     bx, [last_tick]
    sub     ax, bx
    cmp     ax, MON_REFRESH
    jb      .done

    ; Time to refresh
    mov     [last_tick], ax
    call    monitor_update

.done:
    pop     es
    pop     ds
    pop     bx
    pop     ax
    ret

;==============================================================================
; Keyboard Interrupt Hook (for F3 detection)
;==============================================================================
; This would be installed as a hook to INT 9 or INT 16h to detect F3.
; For now, this is called from the INT 13h handler to check for F3.
;==============================================================================
monitor_check_f3:
    push    ax
    push    ds

    push    cs
    pop     ds

    ; Quick keyboard check
    mov     ah, 0x01
    int     0x16
    jz      .no_key

    ; Check if F3
    cmp     ah, KEY_F3
    jne     .no_key

    ; Consume the key
    mov     ah, 0x00
    int     0x16

    ; Toggle monitor
    call    monitor_toggle

.no_key:
    pop     ds
    pop     ax
    ret

;==============================================================================
; Monitor Strings
;==============================================================================
mon_title:      db " FluxRipper ", 0
mon_commands:   db "Commands:", 0
mon_reads:      db "Reads:   ", 0
mon_writes:     db "Writes:  ", 0
mon_errors:     db "Errors:  ", 0
mon_datarate:   db "Data Rate: ", 0
mon_kbs:        db " KB/s", 0
mon_rpm:        db "Spindle:   ", 0
mon_rpm_unit:   db " RPM", 0
mon_temp:       db "Temp:      ", 0
mon_celsius:    db " C", 0
mon_overflow:   db "99999+", 0

%endif ; BUILD_16KB
