;==============================================================================
; FluxRipper HDD BIOS - WD Controller I/O Primitives
;==============================================================================
; Low-level routines for WD task file register access.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Write Command to WD Controller
;==============================================================================
; Waits for controller ready, then issues command.
;
; Input:  AL = command code
; Output: CF = 0 if command accepted, CF = 1 if timeout
; Destroys: AX, CX, DX
;==============================================================================
wd_write_command:
    push    ax                      ; Save command

    ; Wait for BSY clear
    call    wait_drive_ready
    jc      .timeout

    ; Issue command
    pop     ax
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    out     dx, al

    clc
    ret

.timeout:
    pop     ax                      ; Clean up stack
    stc
    ret

;==============================================================================
; Read Status Register
;==============================================================================
; Reads the status register without clearing interrupt.
;
; Output: AL = status register value
; Destroys: DX
;==============================================================================
wd_read_status:
    mov     dx, [current_base]
    add     dx, WD_STATUS
    in      al, dx
    ret

;==============================================================================
; Read Alternate Status Register
;==============================================================================
; Reads status without clearing pending interrupt.
;
; Output: AL = status register value
; Destroys: DX
;==============================================================================
wd_read_alt_status:
    mov     dx, [current_base]
    add     dx, WD_ALT_STATUS - WD_BASE_PRIMARY + WD_BASE_ALTERNATE
    in      al, dx
    ret

;==============================================================================
; Read Error Register
;==============================================================================
; Reads the error register (valid after STS_ERR is set).
;
; Output: AL = error register value
; Destroys: DX
;==============================================================================
wd_read_error:
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    ret

;==============================================================================
; Set Up Task File
;==============================================================================
; Writes C/H/S address and sector count to task file.
;
; Input:  AL = sector count
;         BL = sector number (1-63)
;         CX = cylinder (0-65535)
;         DH = head (0-255)
;         DL = drive (80h or 81h)
; Output: None
; Destroys: AX, DX
;==============================================================================
wd_setup_taskfile:
    push    bx
    push    cx

    ; Write sector count
    mov     dx, [current_base]
    add     dx, WD_SECCNT
    out     dx, al

    ; Write sector number
    mov     al, bl
    inc     dx                      ; WD_SECNUM
    out     dx, al

    ; Write cylinder low
    mov     al, cl
    inc     dx                      ; WD_CYL_LO
    out     dx, al

    ; Write cylinder high
    mov     al, ch
    inc     dx                      ; WD_CYL_HI
    out     dx, al

    ; Write SDH (head and drive select)
    pop     cx
    mov     al, dh                  ; Head
    and     al, 0x0F
    or      al, SDH_SIZE_512        ; 512-byte sectors
    cmp     dl, 0x81                ; Drive 1?
    jne     .drive0
    or      al, SDH_DRV1
.drive0:
    inc     dx                      ; WD_SDH
    out     dx, al

    pop     bx
    ret

;==============================================================================
; Read Sector Data
;==============================================================================
; Reads 512 bytes from data register to memory.
;
; Input:  ES:DI = destination buffer
; Output: ES:DI updated (DI += 512)
; Destroys: AX, CX, DX, DI
;==============================================================================
wd_read_sector_data:
    mov     dx, [current_base]
    add     dx, WD_DATA
    mov     cx, 256                 ; 256 words = 512 bytes
    rep insw
    ret

;==============================================================================
; Write Sector Data
;==============================================================================
; Writes 512 bytes from memory to data register.
;
; Input:  DS:SI = source buffer
; Output: DS:SI updated (SI += 512)
; Destroys: AX, CX, DX, SI
;==============================================================================
wd_write_sector_data:
    mov     dx, [current_base]
    add     dx, WD_DATA
    mov     cx, 256                 ; 256 words = 512 bytes
    rep outsw
    ret

;==============================================================================
; Soft Reset Controller
;==============================================================================
; Issues a software reset to the controller.
;
; Output: CF = 0 if reset successful, CF = 1 if failed
; Destroys: AX, CX, DX
;==============================================================================
wd_soft_reset:
    ; Assert SRST
    mov     dx, [current_base]
    add     dx, WD_DEV_CTRL - WD_BASE_PRIMARY + WD_BASE_ALTERNATE
    mov     al, CTRL_SRST
    out     dx, al

    ; Wait 5us minimum
    mov     cx, 10
    call    delay_us

    ; Clear SRST
    xor     al, al
    out     dx, al

    ; Wait for BSY to clear (up to 31 seconds per ATA spec, but we use shorter)
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, 0xFFFF

.wait_bsy:
    in      al, dx
    test    al, STS_BSY
    jz      .bsy_clear
    loop    .wait_bsy

    stc                             ; Timeout
    ret

.bsy_clear:
    clc
    ret

;==============================================================================
; Wait for DRQ
;==============================================================================
; Waits for Data Request bit to be set.
;
; Output: CF = 0 if DRQ set, CF = 1 if timeout or error
;         AL = status register value
; Destroys: AX, CX, DX
;==============================================================================
wd_wait_drq:
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_DRQ_SET

.loop:
    in      al, dx
    test    al, STS_ERR             ; Error?
    jnz     .error
    test    al, STS_DRQ             ; DRQ set?
    jnz     .done
    loop    .loop

    stc                             ; Timeout
    ret

.error:
    stc
    ret

.done:
    clc
    ret

;==============================================================================
; Wait for BSY Clear
;==============================================================================
; Waits for Busy bit to clear.
;
; Output: CF = 0 if BSY clear, CF = 1 if timeout
;         AL = status register value
; Destroys: AX, CX, DX
;==============================================================================
wd_wait_not_busy:
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_BSY_CLR

.loop:
    in      al, dx
    test    al, STS_BSY
    jz      .done
    loop    .loop

    stc                             ; Timeout
    ret

.done:
    clc
    ret

;==============================================================================
; Disable Interrupts
;==============================================================================
; Disables interrupt generation from controller.
;
; Destroys: AL, DX
;==============================================================================
wd_disable_irq:
    mov     dx, [current_base]
    add     dx, WD_DEV_CTRL - WD_BASE_PRIMARY + WD_BASE_ALTERNATE
    mov     al, CTRL_NIEN
    out     dx, al
    ret

;==============================================================================
; Enable Interrupts
;==============================================================================
; Enables interrupt generation from controller.
;
; Destroys: AL, DX
;==============================================================================
wd_enable_irq:
    mov     dx, [current_base]
    add     dx, WD_DEV_CTRL - WD_BASE_PRIMARY + WD_BASE_ALTERNATE
    xor     al, al
    out     dx, al
    ret
