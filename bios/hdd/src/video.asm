;==============================================================================
; FluxRipper HDD BIOS - Video Output Routines
;==============================================================================
; Enhanced video routines for diagnostics display.
;
; Features:
;   - Direct video memory access (faster than BIOS)
;   - Box drawing with single/double lines
;   - Progress bars
;   - Color attributes
;   - Cursor positioning
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%if BUILD_16KB

;==============================================================================
; Video Constants
;==============================================================================
%define VIDEO_SEG       0xB800      ; Color text mode segment
%define VIDEO_MONO_SEG  0xB000      ; Monochrome segment
%define SCREEN_WIDTH    80
%define SCREEN_HEIGHT   25

; Color attributes
%define ATTR_NORMAL     0x07        ; Light gray on black
%define ATTR_BRIGHT     0x0F        ; White on black
%define ATTR_INVERSE    0x70        ; Black on light gray
%define ATTR_TITLE      0x1F        ; White on blue
%define ATTR_ERROR      0x4F        ; White on red
%define ATTR_SUCCESS    0x2F        ; White on green
%define ATTR_HIGHLIGHT  0x0E        ; Yellow on black
%define ATTR_DIM        0x08        ; Dark gray on black

; Box drawing characters (code page 437)
%define BOX_TL          0xC9        ; Top-left double
%define BOX_TR          0xBB        ; Top-right double
%define BOX_BL          0xC8        ; Bottom-left double
%define BOX_BR          0xBC        ; Bottom-right double
%define BOX_H           0xCD        ; Horizontal double
%define BOX_V           0xBA        ; Vertical double
%define BOX_TL_S        0xDA        ; Top-left single
%define BOX_TR_S        0xBF        ; Top-right single
%define BOX_BL_S        0xC0        ; Bottom-left single
%define BOX_BR_S        0xD9        ; Bottom-right single
%define BOX_H_S         0xC4        ; Horizontal single
%define BOX_V_S         0xB3        ; Vertical single

; Progress bar characters
%define PROG_FULL       0xDB        ; Full block
%define PROG_HALF       0xDD        ; Right half block
%define PROG_EMPTY      0xB0        ; Light shade

;==============================================================================
; Video State
;==============================================================================
video_seg:      dw VIDEO_SEG        ; Current video segment
cursor_row:     db 0                ; Saved cursor row
cursor_col:     db 0                ; Saved cursor column
current_attr:   db ATTR_NORMAL      ; Current attribute

;==============================================================================
; Initialize Video
;==============================================================================
; Detects video type and sets up segment.
;
; Output: video_seg set to appropriate segment
; Destroys: AX
;==============================================================================
video_init:
    push    es
    push    di

    ; Check for color or mono adapter
    mov     ax, 0x0040
    mov     es, ax
    mov     al, [es:0x0049]         ; Current video mode

    cmp     al, 7                   ; Mode 7 = mono
    je      .mono

    mov     word [video_seg], VIDEO_SEG
    jmp     .done

.mono:
    mov     word [video_seg], VIDEO_MONO_SEG

.done:
    pop     di
    pop     es
    ret

;==============================================================================
; Set Cursor Position
;==============================================================================
; Input:  DH = row (0-24)
;         DL = column (0-79)
; Destroys: AX, BX
;==============================================================================
video_set_cursor:
    push    ax
    push    bx

    mov     ah, 0x02                ; Set cursor position
    xor     bh, bh                  ; Page 0
    int     0x10

    pop     bx
    pop     ax
    ret

;==============================================================================
; Get Cursor Position
;==============================================================================
; Output: DH = row, DL = column
; Destroys: AX, BX, CX
;==============================================================================
video_get_cursor:
    push    ax
    push    bx
    push    cx

    mov     ah, 0x03
    xor     bh, bh
    int     0x10

    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Save Cursor
;==============================================================================
video_save_cursor:
    push    dx
    call    video_get_cursor
    mov     [cursor_row], dh
    mov     [cursor_col], dl
    pop     dx
    ret

;==============================================================================
; Restore Cursor
;==============================================================================
video_restore_cursor:
    push    dx
    mov     dh, [cursor_row]
    mov     dl, [cursor_col]
    call    video_set_cursor
    pop     dx
    ret

;==============================================================================
; Clear Screen
;==============================================================================
; Clears screen with current attribute.
;
; Destroys: AX, BX, CX, DX
;==============================================================================
video_clear_screen:
    mov     ah, 0x06                ; Scroll up
    xor     al, al                  ; Clear entire window
    mov     bh, [current_attr]      ; Attribute for blank
    xor     cx, cx                  ; Upper left (0,0)
    mov     dx, 0x184F              ; Lower right (24,79)
    int     0x10

    ; Home cursor
    xor     dx, dx
    call    video_set_cursor
    ret

;==============================================================================
; Clear Line
;==============================================================================
; Clears current line from cursor to end.
;
; Destroys: AX, BX, CX, DX
;==============================================================================
video_clear_line:
    push    dx
    call    video_get_cursor
    push    dx                      ; Save cursor

    ; Clear from cursor to end of line
    mov     ah, 0x09                ; Write char with attr
    mov     al, ' '
    mov     bh, 0                   ; Page 0
    mov     bl, [current_attr]
    mov     cx, SCREEN_WIDTH
    sub     cl, dl                  ; Remaining columns
    int     0x10

    pop     dx
    call    video_set_cursor
    pop     dx
    ret

;==============================================================================
; Print Character at Position
;==============================================================================
; Input:  AL = character
;         DH = row
;         DL = column
;         AH = attribute (or 0 to use current)
; Destroys: BX, ES
;==============================================================================
video_putc_at:
    push    ax
    push    di
    push    es

    ; Calculate offset: (row * 80 + col) * 2
    push    ax
    mov     al, dh
    mov     bl, SCREEN_WIDTH
    mul     bl                      ; AX = row * 80
    xor     bh, bh
    mov     bl, dl
    add     ax, bx                  ; AX = row * 80 + col
    shl     ax, 1                   ; AX = offset in video memory
    mov     di, ax
    pop     ax

    ; Get video segment
    mov     es, [video_seg]

    ; Write character
    mov     [es:di], al

    ; Write attribute
    test    ah, ah
    jz      .use_current
    mov     [es:di + 1], ah
    jmp     .done

.use_current:
    mov     al, [current_attr]
    mov     [es:di + 1], al

.done:
    pop     es
    pop     di
    pop     ax
    ret

;==============================================================================
; Print String at Position
;==============================================================================
; Input:  DS:SI = null-terminated string
;         DH = starting row
;         DL = starting column
;         AH = attribute (or 0 for current)
; Destroys: AL, SI
;==============================================================================
video_puts_at:
    push    ax
    push    dx

    mov     bl, ah                  ; Save attribute

.loop:
    lodsb
    test    al, al
    jz      .done

    mov     ah, bl
    call    video_putc_at
    inc     dl                      ; Next column
    cmp     dl, SCREEN_WIDTH
    jb      .loop
    ; Wrap to next line
    xor     dl, dl
    inc     dh
    jmp     .loop

.done:
    pop     dx
    pop     ax
    ret

;==============================================================================
; Draw Box
;==============================================================================
; Draws a box with double-line border.
;
; Input:  DH = top row
;         DL = left column
;         CH = bottom row
;         CL = right column
;         AH = attribute
; Destroys: AL, BX
;==============================================================================
video_draw_box:
    push    cx
    push    dx
    push    si

    mov     bl, ah                  ; Save attribute

    ; Draw top-left corner
    mov     al, BOX_TL
    mov     ah, bl
    call    video_putc_at

    ; Draw top line
    push    dx
    inc     dl
.top_loop:
    cmp     dl, cl
    jge     .top_done
    mov     al, BOX_H
    mov     ah, bl
    call    video_putc_at
    inc     dl
    jmp     .top_loop
.top_done:
    pop     dx

    ; Draw top-right corner
    push    dx
    mov     dl, cl
    mov     al, BOX_TR
    mov     ah, bl
    call    video_putc_at
    pop     dx

    ; Draw sides
    push    dx
    inc     dh
.side_loop:
    cmp     dh, ch
    jge     .side_done

    ; Left side
    mov     al, BOX_V
    mov     ah, bl
    call    video_putc_at

    ; Right side
    push    dx
    mov     dl, cl
    call    video_putc_at
    pop     dx

    inc     dh
    jmp     .side_loop
.side_done:
    pop     dx

    ; Draw bottom-left corner
    mov     dh, ch
    mov     al, BOX_BL
    mov     ah, bl
    call    video_putc_at

    ; Draw bottom line
    push    dx
    inc     dl
.bottom_loop:
    cmp     dl, cl
    jge     .bottom_done
    mov     al, BOX_H
    mov     ah, bl
    call    video_putc_at
    inc     dl
    jmp     .bottom_loop
.bottom_done:
    pop     dx

    ; Draw bottom-right corner
    mov     dl, cl
    mov     dh, ch
    mov     al, BOX_BR
    mov     ah, bl
    call    video_putc_at

    pop     si
    pop     dx
    pop     cx
    ret

;==============================================================================
; Draw Progress Bar
;==============================================================================
; Draws a progress bar.
;
; Input:  DH = row
;         DL = column
;         CL = width (in characters)
;         AL = percentage (0-100)
;         AH = attribute
; Destroys: BX
;==============================================================================
video_progress_bar:
    push    ax
    push    cx
    push    dx

    mov     bl, ah                  ; Save attribute
    mov     bh, al                  ; Save percentage

    ; Calculate filled width: (percentage * width) / 100
    xor     ah, ah
    mov     al, bh                  ; Percentage
    mul     cl                      ; AX = percentage * width
    mov     ch, 100
    div     ch                      ; AL = filled chars

    mov     ch, al                  ; CH = filled count

    ; Draw filled portion
    xor     cl, cl                  ; Position counter

.fill_loop:
    cmp     cl, ch
    jge     .empty_part
    mov     al, PROG_FULL
    mov     ah, bl
    call    video_putc_at
    inc     dl
    inc     cl
    jmp     .fill_loop

.empty_part:
    ; Draw empty portion
    pop     dx
    push    dx
    add     dl, cl                  ; Current position

    ; Get remaining width
    mov     al, [bp - 6]            ; Original CL (width)
    sub     al, cl                  ; Remaining

.empty_loop:
    test    al, al
    jz      .done
    push    ax
    mov     al, PROG_EMPTY
    mov     ah, bl
    call    video_putc_at
    pop     ax
    inc     dl
    dec     al
    jmp     .empty_loop

.done:
    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; Print Centered String
;==============================================================================
; Input:  DS:SI = string
;         DH = row
;         AH = attribute
; Destroys: AL, CX, DL, SI
;==============================================================================
video_puts_centered:
    push    ax
    push    bx
    push    si

    mov     bl, ah                  ; Save attribute

    ; Calculate string length
    push    si
    xor     cx, cx
.len_loop:
    lodsb
    test    al, al
    jz      .len_done
    inc     cx
    jmp     .len_loop
.len_done:
    pop     si

    ; Calculate starting column
    mov     ax, SCREEN_WIDTH
    sub     ax, cx
    shr     ax, 1                   ; (80 - len) / 2
    mov     dl, al

    ; Print string
    mov     ah, bl
    call    video_puts_at

    pop     si
    pop     bx
    pop     ax
    ret

;==============================================================================
; Set Attribute
;==============================================================================
; Input: AL = new attribute
;==============================================================================
video_set_attr:
    mov     [current_attr], al
    ret

%endif ; BUILD_16KB
