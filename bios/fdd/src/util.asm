;==============================================================================
; FluxRipper FDD BIOS - Utility Functions
;==============================================================================
; Common helper routines used throughout the FDD BIOS.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Print String (Teletype)
;==============================================================================
; Prints a null-terminated string using BIOS INT 10h.
; Input:  DS:SI = pointer to null-terminated string
; Output: None (SI advanced past string)
;==============================================================================
print_string:
    push    ax
    push    bx
    push    si

    mov     bx, 0x0007              ; Page 0, attribute 7 (white)
.loop:
    lodsb
    test    al, al
    jz      .done
    mov     ah, 0x0E                ; Teletype output
    int     0x10
    jmp     .loop

.done:
    pop     si
    pop     bx
    pop     ax
    ret

;==============================================================================
; Print Hexadecimal Byte
;==============================================================================
; Prints a byte in hexadecimal format.
; Input:  AL = byte to print
; Output: None
;==============================================================================
print_hex_byte:
    push    ax
    push    bx
    push    cx

    mov     cl, al                  ; Save byte
    mov     bx, 0x0007              ; Page 0, attribute 7

    ; High nibble
    mov     al, cl
    shr     al, 4
    call    .print_nibble

    ; Low nibble
    mov     al, cl
    and     al, 0x0F
    call    .print_nibble

    pop     cx
    pop     bx
    pop     ax
    ret

.print_nibble:
    cmp     al, 10
    jb      .decimal
    add     al, 'A' - 10
    jmp     .output
.decimal:
    add     al, '0'
.output:
    mov     ah, 0x0E
    int     0x10
    ret

;==============================================================================
; Print Decimal Word
;==============================================================================
; Prints a 16-bit value in decimal format.
; Input:  AX = value to print
; Output: None
;==============================================================================
print_dec_word:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    mov     bx, 0x0007              ; Page 0, attribute 7
    mov     si, .buffer + 5
    mov     byte [si], 0            ; Null terminator

    mov     cx, 10
.convert:
    dec     si
    xor     dx, dx
    div     cx
    add     dl, '0'
    mov     [si], dl
    test    ax, ax
    jnz     .convert

    ; Print the string
.print:
    lodsb
    test    al, al
    jz      .done
    mov     ah, 0x0E
    int     0x10
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
; Delay Milliseconds
;==============================================================================
; Delays for approximately the specified number of milliseconds.
; Uses BIOS timer tick (about 55ms per tick) for longer delays.
; Input:  CX = milliseconds to delay
; Output: None
;==============================================================================
delay_ms:
    push    ax
    push    cx
    push    dx

    ; For short delays, use loop-based delay
    ; For longer delays, use timer ticks
    cmp     cx, 55
    jb      .short_delay

    ; Convert to timer ticks (round up)
    mov     ax, cx
    mov     dx, 0
    mov     cx, 55
    div     cx
    inc     ax                      ; Round up
    mov     cx, ax
    call    delay_ticks
    jmp     .done

.short_delay:
    ; Loop-based delay (approximately 1ms per iteration at 4.77MHz)
    ; Adjust multiplier for different CPU speeds
.outer:
    mov     ax, 200                 ; ~1ms at 4.77MHz
.inner:
    dec     ax
    jnz     .inner
    loop    .outer

.done:
    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; Delay Timer Ticks
;==============================================================================
; Delays for the specified number of timer ticks (~55ms each).
; Input:  CX = number of ticks to delay
; Output: None
;==============================================================================
delay_ticks:
    push    ax
    push    cx
    push    dx
    push    es

    xor     ax, ax
    mov     es, ax

    ; Get current tick count
    mov     dx, [es:0x046C]         ; Low word of tick count
    add     dx, cx                  ; Target tick

.wait:
    mov     ax, [es:0x046C]
    cmp     ax, dx
    jb      .wait

    pop     es
    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; Wait for FDC Interrupt
;==============================================================================
; Waits for the FDC interrupt flag to be set.
; Input:  CX = timeout in ticks
; Output: CF=0 if interrupt received, CF=1 if timeout
;==============================================================================
wait_fdc_int:
    push    ax
    push    bx
    push    dx
    push    es

    xor     ax, ax
    mov     es, ax

    ; Get current tick count
    mov     dx, [es:0x046C]
    add     dx, cx                  ; Target tick

.wait:
    ; Check interrupt flag in BDA
    test    byte [es:BDA_SEG*16 + BDA_DISK_INT_FLAG], 0x80
    jnz     .got_int

    ; Check timeout
    mov     ax, [es:0x046C]
    cmp     ax, dx
    jb      .wait

    ; Timeout
    stc
    jmp     .done

.got_int:
    ; Clear interrupt flag
    and     byte [es:BDA_SEG*16 + BDA_DISK_INT_FLAG], 0x7F
    clc

.done:
    pop     es
    pop     dx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Set BIOS Diskette Status
;==============================================================================
; Sets the diskette status byte in the BDA.
; Input:  AL = status code
; Output: None
;==============================================================================
set_disk_status:
    push    ds
    push    bx

    mov     bx, BDA_SEG
    mov     ds, bx
    mov     [BDA_FLOPPY_STATUS], al

    pop     bx
    pop     ds
    ret

;==============================================================================
; Get BIOS Diskette Status
;==============================================================================
; Gets the diskette status byte from the BDA.
; Input:  None
; Output: AL = status code
;==============================================================================
get_disk_status:
    push    ds
    push    bx

    mov     bx, BDA_SEG
    mov     ds, bx
    mov     al, [BDA_FLOPPY_STATUS]

    pop     bx
    pop     ds
    ret
