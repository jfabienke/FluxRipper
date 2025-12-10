;==============================================================================
; FluxRipper FDD BIOS - FDC I/O Routines
;==============================================================================
; Low-level routines for communicating with the 82077AA-compatible FDC.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Wait for FDC Ready
;==============================================================================
; Waits for the FDC to be ready to accept a command or data.
;
; Input:  None
; Output: CF=0 if ready, CF=1 if timeout
;         AL = MSR value on success
;==============================================================================
wait_fdc_ready:
    push    cx
    push    dx

    mov     dx, [current_fdc]
    add     dx, FDC_MSR
    mov     cx, 0xFFFF              ; Timeout counter

.wait:
    in      al, dx
    test    al, MSR_RQM             ; Ready for Master?
    jnz     .ready
    loop    .wait

    ; Timeout
    stc
    jmp     .done

.ready:
    clc

.done:
    pop     dx
    pop     cx
    ret

;==============================================================================
; FDC Write Data
;==============================================================================
; Writes a command/data byte to the FDC FIFO.
;
; Input:  AL = byte to write
; Output: CF=0 on success, CF=1 on timeout
;==============================================================================
fdc_write_data:
    push    ax
    push    cx
    push    dx

    ; Save data byte
    mov     ah, al

    ; Wait for RQM and DIO=0 (ready for write)
    mov     dx, [current_fdc]
    add     dx, FDC_MSR
    mov     cx, 0xFFFF

.wait:
    in      al, dx
    test    al, MSR_RQM             ; RQM set?
    jz      .retry
    test    al, MSR_DIO             ; DIO must be 0 for write
    jz      .write
.retry:
    loop    .wait

    ; Timeout
    stc
    jmp     .done

.write:
    ; Write byte to FIFO
    mov     dx, [current_fdc]
    add     dx, FDC_FIFO
    mov     al, ah
    out     dx, al
    clc

.done:
    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; FDC Read Data
;==============================================================================
; Reads a result byte from the FDC FIFO.
;
; Input:  None
; Output: AL = byte read
;         CF=0 on success, CF=1 on timeout
;==============================================================================
fdc_read_data:
    push    cx
    push    dx

    ; Wait for RQM and DIO=1 (ready for read)
    mov     dx, [current_fdc]
    add     dx, FDC_MSR
    mov     cx, 0xFFFF

.wait:
    in      al, dx
    test    al, MSR_RQM             ; RQM set?
    jz      .retry
    test    al, MSR_DIO             ; DIO must be 1 for read
    jnz     .read
.retry:
    loop    .wait

    ; Timeout
    stc
    jmp     .done

.read:
    ; Read byte from FIFO
    mov     dx, [current_fdc]
    add     dx, FDC_FIFO
    in      al, dx
    clc

.done:
    pop     dx
    pop     cx
    ret

;==============================================================================
; Read FDC Results
;==============================================================================
; Reads all result bytes from the FDC after a command.
; Result phase ends when RQM=0 or command busy clears.
;
; Input:  DS:DI = buffer for results
;         CX = maximum bytes to read
; Output: CX = number of bytes read
;         CF=0 on success, CF=1 on error
;==============================================================================
fdc_read_results:
    push    ax
    push    bx
    push    dx
    push    di

    xor     bx, bx                  ; Byte counter
    mov     dx, [current_fdc]
    add     dx, FDC_MSR

.read_loop:
    ; Check if more results available
    in      al, dx
    test    al, MSR_CMD_BUSY        ; Command still busy?
    jz      .done_ok                ; No, we're done
    test    al, MSR_RQM             ; Ready for transfer?
    jz      .read_loop              ; No, keep waiting
    test    al, MSR_DIO             ; DIO=1 for read?
    jz      .done_ok                ; No, must be done

    ; Read the byte
    push    dx
    mov     dx, [current_fdc]
    add     dx, FDC_FIFO
    in      al, dx
    pop     dx

    mov     [di], al
    inc     di
    inc     bx

    ; Check limit
    cmp     bx, cx
    jb      .read_loop

.done_ok:
    mov     cx, bx
    clc
    jmp     .done

.done:
    pop     di
    pop     dx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Select Drive
;==============================================================================
; Selects a drive and turns on its motor.
;
; Input:  DL = drive number (0-3)
; Output: CF=0 on success, CF=1 on invalid drive
;==============================================================================
fdc_select_drive:
    push    ax
    push    bx
    push    dx

    ; Validate drive number
    cmp     dl, 4
    jae     .invalid

    ; Determine which FDC to use
    cmp     dl, 2
    jb      .primary_fdc

    ; Drive 2-3: Check if secondary FDC is present
    cmp     byte [cs:secondary_fdc_present], 0
    je      .invalid                ; Secondary FDC not present

    ; Secondary FDC exists - use it
    mov     word [current_fdc], FDC_SECONDARY
    sub     dl, 2                   ; Adjust drive number for secondary (0-1)
    jmp     .select

.primary_fdc:
    mov     word [current_fdc], FDC_PRIMARY

.select:
    ; Build DOR value
    ; Bits 0-1: drive select
    ; Bit 2: reset (1=normal)
    ; Bit 3: DMA/IRQ enable
    ; Bits 4-7: motor enables
    mov     al, dl                  ; Drive select
    or      al, DOR_RESET           ; Normal operation
    or      al, DOR_DMA_EN          ; Enable DMA/IRQ

    ; Calculate motor bit
    mov     cl, dl
    add     cl, 4                   ; Motor bits start at bit 4
    mov     bl, 1
    shl     bl, cl
    or      al, bl                  ; Enable motor

    ; Write to DOR
    push    dx
    mov     dx, [current_fdc]
    add     dx, FDC_DOR
    out     dx, al
    pop     dx

    ; Update motor status
    mov     [motor_status], al

    ; Wait for motor spin-up if needed
    ; (Motor start time varies by drive type, use conservative delay)
    mov     cx, 500                 ; 500ms delay
    call    delay_ms

    clc
    jmp     .done

.invalid:
    stc

.done:
    pop     dx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Turn Off Motor
;==============================================================================
; Turns off the motor for a specific drive.
;
; Input:  DL = drive number (0-3)
; Output: None
;==============================================================================
fdc_motor_off:
    push    ax
    push    cx
    push    dx

    ; Calculate which motor bit to clear
    mov     cl, dl
    and     cl, 0x03                ; Mask to 0-3
    add     cl, 4                   ; Motor bits start at bit 4
    mov     al, 1
    shl     al, cl
    not     al                      ; Create mask to clear bit

    ; Update motor status
    and     [motor_status], al

    ; Write new status (keep reset and DMA enable)
    mov     al, [motor_status]
    or      al, DOR_RESET | DOR_DMA_EN

    push    dx
    mov     dx, [current_fdc]
    add     dx, FDC_DOR
    out     dx, al
    pop     dx

    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; Set Data Rate
;==============================================================================
; Sets the FDC data rate.
;
; Input:  AL = rate code (RATE_250K, RATE_300K, RATE_500K, RATE_1M)
; Output: None
;==============================================================================
fdc_set_rate:
    push    dx

    mov     dx, [current_fdc]
    add     dx, FDC_CCR
    out     dx, al

    pop     dx
    ret

;==============================================================================
; Recalibrate
;==============================================================================
; Moves the drive head to track 0.
;
; Input:  DL = drive number (0-3)
; Output: CF=0 on success, CF=1 on failure
;==============================================================================
fdc_recalibrate:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Select drive and turn on motor
    call    fdc_select_drive
    jc      .error

    ; Send RECALIBRATE command
    mov     al, CMD_RECALIBRATE
    call    fdc_write_data
    jc      .error

    ; Send drive number
    mov     al, dl
    and     al, 0x03
    call    fdc_write_data
    jc      .error

    ; Wait for interrupt
    mov     cx, SEEK_TIMEOUT
    call    wait_fdc_int
    jc      .error

    ; Send SENSE INTERRUPT to clear interrupt
    mov     al, CMD_SENSE_INT
    call    fdc_write_data
    jc      .error

    ; Read ST0 result
    call    fdc_read_data
    jc      .error
    mov     bl, al                  ; Save ST0

    ; Read PCN (Present Cylinder Number)
    call    fdc_read_data
    jc      .error

    ; Check if at track 0
    test    al, al
    jnz     .error

    ; Check ST0 for success
    mov     al, bl
    and     al, ST0_IC
    cmp     al, ST0_IC_NORMAL
    jne     .error

    ; Update current track in BDA
    push    ds
    mov     ax, BDA_SEG
    mov     ds, ax
    mov     bl, dl
    xor     bh, bh
    mov     byte [BDA_CURR_TRACK + bx], 0
    pop     ds

    clc
    jmp     .done

.error:
    stc

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Seek
;==============================================================================
; Moves the drive head to the specified track.
;
; Input:  DL = drive number (0-3)
;         CH = cylinder number
;         DH = head number
; Output: CF=0 on success, CF=1 on failure
;==============================================================================
fdc_seek:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Select drive
    call    fdc_select_drive
    jc      .error

    ; Send SEEK command
    mov     al, CMD_SEEK
    call    fdc_write_data
    jc      .error

    ; Send head/drive byte: bits 0-1 = drive, bit 2 = head
    mov     al, dl
    and     al, 0x03
    mov     bl, dh
    and     bl, 0x01
    shl     bl, 2
    or      al, bl
    call    fdc_write_data
    jc      .error

    ; Send cylinder number
    mov     al, ch
    call    fdc_write_data
    jc      .error

    ; Wait for interrupt
    mov     cx, SEEK_TIMEOUT
    call    wait_fdc_int
    jc      .error

    ; Send SENSE INTERRUPT
    mov     al, CMD_SENSE_INT
    call    fdc_write_data
    jc      .error

    ; Read ST0
    call    fdc_read_data
    jc      .error
    mov     bl, al

    ; Read PCN
    call    fdc_read_data
    jc      .error

    ; Verify we're at the right track
    cmp     al, ch
    jne     .error

    ; Check ST0 for seek end
    test    bl, ST0_SE
    jz      .error

    ; Update current track in BDA
    push    ds
    mov     ax, BDA_SEG
    mov     ds, ax
    mov     bl, dl
    xor     bh, bh
    mov     [BDA_CURR_TRACK + bx], ch
    pop     ds

    clc
    jmp     .done

.error:
    stc

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Read Sector ID
;==============================================================================
; Reads the next sector ID from the current track.
;
; Input:  DL = drive number (0-3)
;         DH = head number
; Output: AL = cylinder
;         AH = head
;         BL = sector
;         BH = size code
;         CF=0 on success, CF=1 on failure
;==============================================================================
fdc_read_id:
    push    cx
    push    dx
    push    si

    ; Select drive
    call    fdc_select_drive
    jc      .error

    ; Send READ ID command
    mov     al, CMD_READ_ID
    call    fdc_write_data
    jc      .error

    ; Send head/drive
    mov     al, dl
    and     al, 0x03
    mov     cl, dh
    and     cl, 0x01
    shl     cl, 2
    or      al, cl
    call    fdc_write_data
    jc      .error

    ; Wait for interrupt
    mov     cx, READ_TIMEOUT
    call    wait_fdc_int
    jc      .error

    ; Read 7 result bytes
    ; ST0, ST1, ST2, C, H, R, N
    sub     sp, 8
    mov     si, sp
    mov     cx, 7
    call    fdc_read_results
    jc      .error_cleanup

    ; Check ST0 for success
    mov     al, [si]                ; ST0
    and     al, ST0_IC
    cmp     al, ST0_IC_NORMAL
    jne     .error_cleanup

    ; Extract ID fields
    mov     al, [si+3]              ; Cylinder
    mov     ah, [si+4]              ; Head
    mov     bl, [si+5]              ; Sector
    mov     bh, [si+6]              ; Size code

    add     sp, 8
    clc
    jmp     .done

.error_cleanup:
    add     sp, 8
.error:
    stc

.done:
    pop     si
    pop     dx
    pop     cx
    ret
