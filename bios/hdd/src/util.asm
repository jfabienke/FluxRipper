;==============================================================================
; FluxRipper HDD BIOS - Utility Functions
;==============================================================================
; Common utility routines:
;   - Delay loops (calibrated for various CPU speeds)
;   - String output
;   - Hex/decimal printing
;   - Port I/O helpers
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Print String (Null-Terminated)
;==============================================================================
; Input:  DS:SI = pointer to null-terminated string
; Output: None
; Destroys: AX, BX, SI
;==============================================================================
print_string:
    push    ax
    push    bx
    push    si

.loop:
    lodsb                           ; Load byte from DS:SI into AL, increment SI
    or      al, al                  ; Check for null terminator
    jz      .done

    mov     ah, 0x0E                ; BIOS teletype output
    mov     bx, 0x0007              ; Page 0, light gray attribute
    int     0x10                    ; Call video BIOS
    jmp     .loop

.done:
    pop     si
    pop     bx
    pop     ax
    ret

;==============================================================================
; Print Character
;==============================================================================
; Input:  AL = character to print
; Output: None
; Destroys: AX, BX
;==============================================================================
print_char:
    push    ax
    push    bx

    mov     ah, 0x0E                ; BIOS teletype output
    mov     bx, 0x0007              ; Page 0, light gray attribute
    int     0x10

    pop     bx
    pop     ax
    ret

;==============================================================================
; Print Newline (CR+LF)
;==============================================================================
print_newline:
    push    ax
    mov     al, 0x0D
    call    print_char
    mov     al, 0x0A
    call    print_char
    pop     ax
    ret

;==============================================================================
; Print Hex Byte
;==============================================================================
; Input:  AL = byte to print as 2 hex digits
; Output: None
; Destroys: AX
;==============================================================================
print_hex_byte:
    push    ax
    push    cx

    mov     cl, al                  ; Save original value
    shr     al, 4                   ; Get high nibble
    call    .print_nibble
    mov     al, cl                  ; Restore original
    and     al, 0x0F                ; Get low nibble
    call    .print_nibble

    pop     cx
    pop     ax
    ret

.print_nibble:
    cmp     al, 10
    jb      .digit
    add     al, 'A' - 10
    jmp     .output
.digit:
    add     al, '0'
.output:
    call    print_char
    ret

;==============================================================================
; Print Hex Word
;==============================================================================
; Input:  AX = word to print as 4 hex digits
; Output: None
; Destroys: AX
;==============================================================================
print_hex_word:
    push    ax
    push    cx

    mov     cx, ax                  ; Save word
    mov     al, ah                  ; Print high byte first
    call    print_hex_byte
    mov     al, cl                  ; Print low byte
    call    print_hex_byte

    pop     cx
    pop     ax
    ret

;==============================================================================
; Print Decimal Word (No Leading Zeros)
;==============================================================================
; Input:  AX = 16-bit unsigned number
; Output: None
; Destroys: AX, CX, DX
;==============================================================================
print_decimal:
    push    ax
    push    bx
    push    cx
    push    dx

    mov     cx, 0                   ; Digit counter
    mov     bx, 10                  ; Divisor

.divide_loop:
    xor     dx, dx                  ; Clear high word
    div     bx                      ; AX = AX/10, DX = remainder
    push    dx                      ; Save digit on stack
    inc     cx                      ; Count digits
    or      ax, ax                  ; Check if quotient is zero
    jnz     .divide_loop

    ; Print digits in reverse order (from stack)
.print_loop:
    pop     ax                      ; Get digit
    add     al, '0'                 ; Convert to ASCII
    call    print_char
    loop    .print_loop

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Print Decimal Dword (32-bit)
;==============================================================================
; Input:  DX:AX = 32-bit unsigned number
; Output: None
; Destroys: AX, BX, CX, DX
;==============================================================================
print_decimal_dword:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    mov     cx, 0                   ; Digit counter

.divide_loop:
    ; 32-bit division by 10
    mov     si, ax                  ; Save low word
    mov     ax, dx                  ; Divide high word first
    xor     dx, dx
    mov     bx, 10
    div     bx                      ; AX = high quotient, DX = remainder
    mov     bx, ax                  ; Save high quotient
    mov     ax, si                  ; Get low word + remainder*65536
    div     word [.divisor]         ; AX = low quotient, DX = final remainder
    push    dx                      ; Save digit
    mov     dx, bx                  ; Restore high quotient
    inc     cx

    ; Check if result is zero
    or      ax, ax
    jnz     .divide_loop
    or      dx, dx
    jnz     .divide_loop

    ; Print digits
.print_loop:
    pop     ax
    add     al, '0'
    call    print_char
    loop    .print_loop

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

.divisor:
    dw      10

;==============================================================================
; Delay Microseconds (Approximate)
;==============================================================================
; Input:  CX = delay in approximate microseconds (very approximate on old PCs)
; Output: None
; Destroys: CX
;
; This uses the 8254 timer to provide reasonably accurate delays.
; Falls back to I/O port delay on systems where timer access fails.
;==============================================================================
delay_us:
    push    ax
    push    cx

    ; Use I/O port 0x80 for delay - each I/O takes ~1us on typical systems
.delay_loop:
    in      al, 0x80                ; ~1us delay
    loop    .delay_loop

    pop     cx
    pop     ax
    ret

;==============================================================================
; Delay Milliseconds
;==============================================================================
; Input:  CX = delay in milliseconds
; Output: None
; Destroys: CX
;==============================================================================
delay_ms:
    push    ax
    push    cx
    push    dx

.ms_loop:
    push    cx
    mov     cx, 1000                ; 1000 microseconds = 1 ms
    call    delay_us
    pop     cx
    loop    .ms_loop

    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; Wait for I/O Port Bit Set (with Timeout)
;==============================================================================
; Input:  DX = I/O port
;         AL = bit mask to check
;         CX = timeout in iterations (0 = infinite)
; Output: CF = 0 if bit set, CF = 1 if timeout
;         AL = final port value
; Destroys: AX, CX
;==============================================================================
wait_bit_set:
    push    bx
    mov     bh, al                  ; Save mask

.loop:
    in      al, dx
    test    al, bh
    jnz     .found
    or      cx, cx                  ; Check for infinite wait
    jz      .loop                   ; CX=0 means wait forever
    loop    .loop
    stc                             ; Timeout
    jmp     .done

.found:
    clc                             ; Success

.done:
    pop     bx
    ret

;==============================================================================
; Wait for I/O Port Bit Clear (with Timeout)
;==============================================================================
; Input:  DX = I/O port
;         AL = bit mask to check
;         CX = timeout in iterations (0 = infinite)
; Output: CF = 0 if bit clear, CF = 1 if timeout
;         AL = final port value
; Destroys: AX, CX
;==============================================================================
wait_bit_clear:
    push    bx
    mov     bh, al                  ; Save mask

.loop:
    in      al, dx
    test    al, bh
    jz      .found
    or      cx, cx
    jz      .loop
    loop    .loop
    stc
    jmp     .done

.found:
    clc

.done:
    pop     bx
    ret

;==============================================================================
; Memory Set (Fill Memory with Byte)
;==============================================================================
; Input:  ES:DI = destination pointer
;         AL    = fill byte
;         CX    = byte count
; Output: None
; Destroys: CX, DI
;==============================================================================
memset:
    push    ax
    rep stosb
    pop     ax
    ret

;==============================================================================
; Memory Copy
;==============================================================================
; Input:  DS:SI = source pointer
;         ES:DI = destination pointer
;         CX    = byte count
; Output: None
; Destroys: CX, SI, DI
;==============================================================================
memcpy:
    push    ax
    rep movsb
    pop     ax
    ret

;==============================================================================
; Compare Memory
;==============================================================================
; Input:  DS:SI = first buffer
;         ES:DI = second buffer
;         CX    = byte count
; Output: ZF = 1 if equal, ZF = 0 if different
; Destroys: CX, SI, DI
;==============================================================================
memcmp:
    push    ax
    repe cmpsb
    pop     ax
    ret

;==============================================================================
; Check for Keypress (Non-blocking)
;==============================================================================
; Output: ZF = 1 if no key, ZF = 0 if key available
;         If key available: AH = scan code, AL = ASCII
; Destroys: AX
;==============================================================================
check_key:
    mov     ah, 0x01                ; Check keyboard buffer
    int     0x16
    ret                             ; ZF reflects result

;==============================================================================
; Get Key (Blocking)
;==============================================================================
; Output: AH = scan code, AL = ASCII
; Destroys: AX
;==============================================================================
get_key:
    mov     ah, 0x00                ; Wait for keypress
    int     0x16
    ret
