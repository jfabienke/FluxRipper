;==============================================================================
; FluxRipper HDD BIOS - Setup Utility
;==============================================================================
; Interactive setup for configuring drive parameters.
;
; Features:
;   - Drive type override
;   - Geometry override
;   - Translation mode selection
;   - Save to flash
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%if BUILD_16KB && ENABLE_SETUP

;==============================================================================
; Setup Entry Point
;==============================================================================
setup_enter:
    pushad
    push    ds
    push    es

    push    cs
    pop     ds

    call    video_clear_screen

    ; Title
    mov     ah, ATTR_TITLE
    mov     dh, 0
    mov     si, setup_title
    call    video_puts_centered

    ; Instructions
    mov     dh, 2
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, setup_info
    call    video_puts_at

    ; Show current settings
    call    setup_show_current

    ; Main menu
    call    setup_menu

    pop     es
    pop     ds
    popad
    ret

;==============================================================================
; Show Current Settings
;==============================================================================
setup_show_current:
    push    ax
    push    dx
    push    si

    mov     dh, 5
    mov     dl, 5
    mov     ah, ATTR_HIGHLIGHT
    mov     si, setup_current_hdr
    call    video_puts_at

    ; Drive 0 settings
    mov     dh, 7
    mov     dl, 5
    mov     ah, ATTR_NORMAL
    mov     si, setup_drive0
    call    video_puts_at

    ; Show auto-detected geometry
    add     dl, 12
    mov     ax, [drive0_params + 0]  ; Cylinders
    call    setup_print_dec16
    mov     al, '/'
    call    video_putc_at
    inc     dl
    xor     ah, ah
    mov     al, [drive0_params + 2]  ; Heads
    call    setup_print_dec16
    mov     al, '/'
    call    video_putc_at
    inc     dl
    xor     ah, ah
    mov     al, [drive0_params + 3]  ; Sectors
    call    setup_print_dec16

    pop     si
    pop     dx
    pop     ax
    ret

;==============================================================================
; Setup Menu
;==============================================================================
setup_menu:
    push    ax
    push    bx

.menu_loop:
    call    kbd_get

    cmp     ah, KEY_ESC
    je      .exit

    ; Menu options would be handled here
    jmp     .menu_loop

.exit:
    pop     bx
    pop     ax
    ret

;==============================================================================
; Print 16-bit Decimal
;==============================================================================
setup_print_dec16:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    mov     bx, ax
    mov     si, .buffer + 5
    mov     byte [si], 0

    mov     ax, bx
    mov     cx, 10
.convert:
    dec     si
    xor     dx, dx
    div     cx
    add     dl, '0'
    mov     [si], dl
    test    ax, ax
    jnz     .convert

    pop     dx
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
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.buffer: times 6 db 0

;==============================================================================
; Setup Strings
;==============================================================================
setup_title:        db " FluxRipper Setup Utility ", 0
setup_info:         db "Configure drive parameters and translation mode.", 0
setup_current_hdr:  db "Current Settings:", 0
setup_drive0:       db "Drive 0 C/H/S:", 0

%endif ; BUILD_16KB && ENABLE_SETUP
