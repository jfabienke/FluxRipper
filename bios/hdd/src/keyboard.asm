;==============================================================================
; FluxRipper HDD BIOS - Keyboard Input Routines
;==============================================================================
; Enhanced keyboard handling for menus and diagnostics.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%if BUILD_16KB

;==============================================================================
; Keyboard Scan Codes
;==============================================================================
%define KEY_ESC         0x01
%define KEY_ENTER       0x1C
%define KEY_SPACE       0x39
%define KEY_UP          0x48
%define KEY_DOWN        0x50
%define KEY_LEFT        0x4B
%define KEY_RIGHT       0x4D
%define KEY_HOME        0x47
%define KEY_END         0x4F
%define KEY_PGUP        0x49
%define KEY_PGDN        0x51

%define KEY_F1          0x3B
%define KEY_F2          0x3C
%define KEY_F3          0x3D
%define KEY_F4          0x3E
%define KEY_F5          0x3F
%define KEY_F6          0x40
%define KEY_F7          0x41
%define KEY_F8          0x42
%define KEY_F9          0x43
%define KEY_F10         0x44

;==============================================================================
; Check for Keypress
;==============================================================================
; Returns immediately whether a key is available.
;
; Output: ZF = 1 if no key, ZF = 0 if key available
;         If key available: AH = scan code, AL = ASCII
; Destroys: AX
;==============================================================================
kbd_check:
    mov     ah, 0x01
    int     0x16
    ret

;==============================================================================
; Get Key (Blocking)
;==============================================================================
; Waits for and returns a keypress.
;
; Output: AH = scan code
;         AL = ASCII code (0 if extended key)
; Destroys: Nothing else
;==============================================================================
kbd_get:
    mov     ah, 0x00
    int     0x16
    ret

;==============================================================================
; Get Key with Timeout
;==============================================================================
; Waits for key up to specified time.
;
; Input:  CX = timeout in ~55ms ticks (18.2 ticks/sec)
; Output: CF = 0 if key pressed, AH/AL = key
;         CF = 1 if timeout
; Destroys: AX, BX
;==============================================================================
kbd_get_timeout:
    push    dx
    push    es

    ; Get starting tick count
    xor     ax, ax
    mov     es, ax
    mov     bx, [es:0x046C]         ; BIOS tick counter

.wait_loop:
    ; Check for key
    mov     ah, 0x01
    int     0x16
    jnz     .got_key

    ; Check timeout
    mov     dx, [es:0x046C]
    sub     dx, bx
    cmp     dx, cx
    jb      .wait_loop

    ; Timeout
    stc
    jmp     .done

.got_key:
    ; Get the key
    mov     ah, 0x00
    int     0x16
    clc

.done:
    pop     es
    pop     dx
    ret

;==============================================================================
; Flush Keyboard Buffer
;==============================================================================
; Removes all pending keystrokes.
;
; Destroys: AX
;==============================================================================
kbd_flush:
.flush_loop:
    mov     ah, 0x01
    int     0x16
    jz      .done
    mov     ah, 0x00
    int     0x16
    jmp     .flush_loop
.done:
    ret

;==============================================================================
; Get Yes/No Response
;==============================================================================
; Waits for Y or N keypress.
;
; Output: CF = 0 if Yes, CF = 1 if No
; Destroys: AX
;==============================================================================
kbd_yes_no:
.loop:
    call    kbd_get
    or      al, 0x20                ; Convert to lowercase

    cmp     al, 'y'
    je      .yes
    cmp     al, 'n'
    je      .no

    ; Invalid key - beep and retry
    mov     ax, 0x0E07              ; Beep
    int     0x10
    jmp     .loop

.yes:
    clc
    ret

.no:
    stc
    ret

;==============================================================================
; Get Number Input (1 digit)
;==============================================================================
; Waits for a digit key (0-9).
;
; Output: AL = digit value (0-9)
;         CF = 0 if valid, CF = 1 if ESC pressed
; Destroys: AH
;==============================================================================
kbd_get_digit:
.loop:
    call    kbd_get

    ; Check for ESC
    cmp     ah, KEY_ESC
    je      .escape

    ; Check for digit
    cmp     al, '0'
    jb      .invalid
    cmp     al, '9'
    ja      .invalid

    ; Valid digit
    sub     al, '0'
    clc
    ret

.invalid:
    mov     ax, 0x0E07              ; Beep
    int     0x10
    jmp     .loop

.escape:
    stc
    ret

;==============================================================================
; Get Menu Selection
;==============================================================================
; Handles menu navigation with arrow keys.
;
; Input:  AL = current selection (0-based)
;         AH = max selection
; Output: AL = new selection
;         CF = 1 if ESC pressed
;         If ENTER: ZF = 1
; Destroys: AH
;==============================================================================
kbd_menu_select:
    push    bx

    mov     bl, al                  ; Current selection
    mov     bh, ah                  ; Max selection

.loop:
    call    kbd_get

    ; Check ESC
    cmp     ah, KEY_ESC
    je      .escape

    ; Check ENTER
    cmp     ah, KEY_ENTER
    je      .enter

    ; Check UP
    cmp     ah, KEY_UP
    je      .up

    ; Check DOWN
    cmp     ah, KEY_DOWN
    je      .down

    ; Check digit keys
    cmp     al, '0'
    jb      .loop
    cmp     al, '9'
    ja      .loop

    ; Direct selection by number
    sub     al, '0'
    cmp     al, bh
    ja      .loop
    mov     bl, al
    jmp     .enter

.up:
    test    bl, bl
    jz      .wrap_up
    dec     bl
    jmp     .update

.wrap_up:
    mov     bl, bh                  ; Wrap to max
    jmp     .update

.down:
    cmp     bl, bh
    jge     .wrap_down
    inc     bl
    jmp     .update

.wrap_down:
    xor     bl, bl                  ; Wrap to 0
    jmp     .update

.update:
    mov     al, bl
    clc
    or      al, 1                   ; Clear ZF
    jmp     .done

.enter:
    mov     al, bl
    clc
    xor     ah, ah                  ; Set ZF
    jmp     .done

.escape:
    mov     al, bl
    stc

.done:
    pop     bx
    ret

;==============================================================================
; Wait for Any Key
;==============================================================================
; Displays prompt and waits for keypress.
;
; Destroys: AX, SI
;==============================================================================
kbd_wait_any:
    mov     si, msg_press_any_key
    call    print_string
    call    kbd_flush
    call    kbd_get
    ret

msg_press_any_key:
    db      "Press any key...", 0

;==============================================================================
; Check for F3 (Diagnostics Hotkey)
;==============================================================================
; Checks if F3 was pressed during POST.
;
; Output: CF = 1 if F3 pressed
; Destroys: AX
;==============================================================================
kbd_check_f3:
    ; Check keyboard buffer
    mov     ah, 0x01
    int     0x16
    jz      .not_pressed

    ; Key available - check if F3
    cmp     ah, KEY_F3
    jne     .not_f3

    ; Consume the key
    mov     ah, 0x00
    int     0x16
    stc
    ret

.not_f3:
    clc
    ret

.not_pressed:
    clc
    ret

%endif ; BUILD_16KB
