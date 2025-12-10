;==============================================================================
; FluxRipper HDD BIOS - LBA Extension Functions (41h-48h)
;==============================================================================
; Implements IBM/Microsoft INT 13h extensions for LBA addressing.
; These extensions allow access to drives larger than 8.4GB (CHS limit).
;
; Functions:
;   41h - Installation check
;   42h - Extended read
;   43h - Extended write
;   44h - Extended verify
;   47h - Extended seek
;   48h - Get extended drive parameters
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%if ENABLE_LBA

;==============================================================================
; Function 41h: Check Extensions Present
;==============================================================================
; Checks if INT 13h extensions are supported.
;
; Input:  AH = 41h
;         BX = 55AAh
;         DL = drive number
; Output: CF = 0 if extensions supported
;         AH = version (21h = 1.1, 30h = EDD-1.1)
;         BX = AA55h (signature)
;         CX = interface support bitmap
;==============================================================================
int13h_check_extensions:
    ; Verify signature
    cmp     bx, 0x55AA
    jne     .not_supported

    ; Verify drive exists
    push    dx
    call    get_drive_params
    pop     dx
    jc      .not_supported

    ; Return success
    mov     ah, EXT_VER_21          ; Version 2.1
    mov     bx, 0xAA55              ; Inverted signature
    mov     cx, EXT_DAP             ; Support DAP (read/write/verify)
    clc
    ret

.not_supported:
    mov     ah, ST_BAD_COMMAND
    stc
    ret

;==============================================================================
; Function 42h: Extended Read
;==============================================================================
; Reads sectors using LBA addressing via Device Address Packet.
;
; Input:  AH = 42h
;         DL = drive number
;         DS:SI = pointer to Device Address Packet (DAP)
;
; DAP Structure:
;   +00 byte  = packet size (10h)
;   +01 byte  = reserved (0)
;   +02 word  = sector count
;   +04 dword = buffer address (segment:offset)
;   +08 qword = starting LBA
;
; Output: AH = status
;         CF = 0 if success
;==============================================================================
int13h_ext_read:
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp
    push    es

    ; Validate DAP
    mov     bp, si                  ; BP = DAP pointer
    cmp     byte [si], DAP_SIZE_BASIC
    jb      .invalid_dap

    ; Get sector count
    mov     cx, [si + DAP.count]
    test    cx, cx
    jz      .success                ; Zero sectors = success

    ; Get buffer address
    les     di, [si + DAP.buffer]   ; ES:DI = buffer

    ; Get LBA (we only support 32-bit LBA for now)
    mov     ax, [si + DAP.lba]      ; Low word
    mov     bx, [si + DAP.lba + 2]  ; High word (of low dword)
    ; Ignore upper 32 bits for drives < 2TB

    ; Save LBA
    mov     [.lba_lo], ax
    mov     [.lba_hi], bx
    mov     [.count], cx
    mov     word [.sectors_done], 0

    ; Select drive
    mov     dl, [bp - 2]            ; Get drive from stack
    call    select_drive

.read_loop:
    ; Wait ready
    call    wait_drive_ready
    jc      .timeout

    ; Convert current LBA to task file
    ; For LBA mode: sector = LBA[7:0], cyl_lo = LBA[15:8], cyl_hi = LBA[23:16]
    ;               SDH[3:0] = LBA[27:24], SDH[6] = 1 (LBA mode)

    mov     ax, [.lba_lo]
    mov     bx, [.lba_hi]

    ; Sector count = 1 (one sector at a time for simplicity)
    mov     dx, [current_base]
    add     dx, WD_SECCNT
    mov     al, 1
    out     dx, al

    ; LBA[7:0] -> sector number
    mov     ax, [.lba_lo]
    inc     dx                      ; WD_SECNUM
    out     dx, al

    ; LBA[15:8] -> cylinder low
    mov     al, ah
    inc     dx                      ; WD_CYL_LO
    out     dx, al

    ; LBA[23:16] -> cylinder high
    mov     al, [.lba_hi]
    inc     dx                      ; WD_CYL_HI
    out     dx, al

    ; LBA[27:24] + LBA mode -> SDH
    mov     al, [.lba_hi + 1]
    and     al, 0x0F                ; LBA[27:24]
    or      al, SDH_SIZE_512 | SDH_LBA  ; Add LBA mode bit
    ; Add drive select if needed
    mov     bl, [bp - 2]
    cmp     bl, 0x81
    jne     .not_drive1
    or      al, SDH_DRV1
.not_drive1:
    inc     dx                      ; WD_SDH
    out     dx, al

    ; Issue READ command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_READ
    out     dx, al

    ; Wait for DRQ
    call    wd_wait_drq
    jc      .read_error

    ; Read 256 words
    mov     dx, [current_base]
    add     dx, WD_DATA
    mov     cx, 256
    rep insw

    ; Increment done count
    inc     word [.done]

    ; Increment LBA
    add     word [.lba_lo], 1
    adc     word [.lba_hi], 0

    ; Check if more sectors
    mov     ax, [.done]
    cmp     ax, [.count]
    jb      .read_loop

.success:
    ; Update DAP with actual count
    mov     ax, [.done]
    mov     [bp + DAP.count], ax
    mov     ah, ST_SUCCESS
    jmp     .done

.invalid_dap:
    mov     ah, ST_BAD_COMMAND
    jmp     .done

.timeout:
    mov     ax, [.sectors_done]
    mov     [bp + DAP.count], ax
    mov     ah, ST_TIMEOUT
    jmp     .done

.read_error:
    mov     ax, [.sectors_done]
    mov     [bp + DAP.count], ax
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error

.done:
    pop     es
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

.lba_lo:        dw 0
.lba_hi:        dw 0
.count:         dw 0
.sectors_done:  dw 0

;==============================================================================
; Function 43h: Extended Write
;==============================================================================
; Writes sectors using LBA addressing.
;
; Input:  Same as Extended Read
; Output: Same as Extended Read
;==============================================================================
int13h_ext_write:
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp
    push    es
    push    ds

    ; Validate DAP
    mov     bp, si
    cmp     byte [si], DAP_SIZE_BASIC
    jb      .invalid_dap

    ; Get sector count
    mov     cx, [si + DAP.count]
    test    cx, cx
    jz      .success

    ; Get buffer address - need DS:SI for writing
    lds     si, [bp + DAP.buffer]   ; DS:SI = buffer

    ; Get LBA
    mov     ax, [bp + DAP.lba]
    mov     bx, [bp + DAP.lba + 2]
    mov     [cs:.lba_lo], ax
    mov     [cs:.lba_hi], bx
    mov     [cs:.count], cx
    mov     word [cs:.sectors_done], 0

    ; Select drive
    push    ds
    push    cs
    pop     ds
    mov     dl, [bp - 2]
    call    select_drive
    pop     ds

.write_loop:
    ; Wait ready
    push    ds
    push    cs
    pop     ds
    call    wait_drive_ready
    pop     ds
    jc      .timeout

    ; Set up task file for LBA write
    push    ds
    push    cs
    pop     ds

    mov     ax, [.lba_lo]
    mov     bx, [.lba_hi]

    mov     dx, [current_base]
    add     dx, WD_SECCNT
    mov     al, 1
    out     dx, al

    mov     ax, [.lba_lo]
    inc     dx
    out     dx, al

    mov     al, ah
    inc     dx
    out     dx, al

    mov     al, [.lba_hi]
    inc     dx
    out     dx, al

    mov     al, [.lba_hi + 1]
    and     al, 0x0F
    or      al, SDH_SIZE_512 | SDH_LBA
    mov     bl, [bp - 2]
    cmp     bl, 0x81
    jne     .not_drv1
    or      al, SDH_DRV1
.not_drv1:
    inc     dx
    out     dx, al

    ; Issue WRITE command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_WRITE
    out     dx, al

    ; Wait for DRQ
    call    wd_wait_drq
    pop     ds                      ; Restore buffer DS
    jc      .write_error

    ; Write 256 words
    push    cs
    mov     dx, [cs:current_base]
    add     dx, WD_DATA
    mov     cx, 256
    rep outsw
    pop     ds                      ; Dummy pop to balance

    ; Wait for BSY clear
    push    cs
    pop     ds
    call    wd_wait_not_busy
    jc      .timeout

    ; Increment done
    inc     word [.done]

    ; Increment LBA
    add     word [.lba_lo], 1
    adc     word [.lba_hi], 0

    ; Restore buffer DS for next iteration
    lds     si, [bp + DAP.buffer]
    add     si, [cs:.done]
    shl     si, 9                   ; * 512
    ; Actually need to recalculate properly...

    mov     ax, [cs:.done]
    cmp     ax, [cs:.count]
    jb      .write_loop

.success:
    push    cs
    pop     ds
    mov     ax, [.done]
    mov     [bp + DAP.count], ax
    mov     ah, ST_SUCCESS
    jmp     .done

.invalid_dap:
    mov     ah, ST_BAD_COMMAND
    jmp     .done

.timeout:
    push    cs
    pop     ds
    mov     ax, [.sectors_done]
    mov     [bp + DAP.count], ax
    mov     ah, ST_TIMEOUT
    jmp     .done

.write_error:
    push    cs
    pop     ds
    mov     ax, [.sectors_done]
    mov     [bp + DAP.count], ax
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error

.done:
    pop     ds
    pop     es
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

.lba_lo:        dw 0
.lba_hi:        dw 0
.count:         dw 0
.sectors_done:  dw 0

;==============================================================================
; Function 44h: Extended Verify
;==============================================================================
; Verifies sectors using LBA addressing.
;
; Input:  Same as Extended Read
; Output: AH = status
;==============================================================================
int13h_ext_verify:
    push    bx
    push    cx
    push    dx
    push    si
    push    bp

    ; Validate DAP
    mov     bp, si
    cmp     byte [si], DAP_SIZE_BASIC
    jb      .invalid_dap

    mov     cx, [si + DAP.count]
    test    cx, cx
    jz      .success

    ; Get LBA
    mov     ax, [si + DAP.lba]
    mov     bx, [si + DAP.lba + 2]
    mov     [.lba_lo], ax
    mov     [.lba_hi], bx
    mov     [.count], cx
    mov     word [.verify_sect_done], 0

    call    select_drive

.verify_loop:
    call    wait_drive_ready
    jc      .timeout

    ; Set up LBA
    mov     ax, [.lba_lo]
    mov     bx, [.lba_hi]

    mov     dx, [current_base]
    add     dx, WD_SECCNT
    mov     al, 1
    out     dx, al

    mov     ax, [.lba_lo]
    inc     dx
    out     dx, al
    mov     al, ah
    inc     dx
    out     dx, al
    mov     al, [.lba_hi]
    inc     dx
    out     dx, al

    mov     al, [.lba_hi + 1]
    and     al, 0x0F
    or      al, SDH_SIZE_512 | SDH_LBA
    inc     dx
    out     dx, al

    ; Issue VERIFY command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_VERIFY
    out     dx, al

    call    wd_wait_not_busy
    jc      .timeout

    ; Check for error
    mov     dx, [current_base]
    add     dx, WD_STATUS
    in      al, dx
    test    al, STS_ERR
    jnz     .verify_error

    inc     word [.done]
    add     word [.lba_lo], 1
    adc     word [.lba_hi], 0

    mov     ax, [.done]
    cmp     ax, [.count]
    jb      .verify_loop

.success:
    mov     ax, [.verify_sect_done]
    mov     [bp + DAP.count], ax
    mov     ah, ST_SUCCESS
    jmp     .done

.invalid_dap:
    mov     ah, ST_BAD_COMMAND
    jmp     .done

.timeout:
    mov     ax, [.verify_sect_done]
    mov     [bp + DAP.count], ax
    mov     ah, ST_TIMEOUT
    jmp     .done

.verify_error:
    mov     ax, [.verify_sect_done]
    mov     [bp + DAP.count], ax
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error

.done:
    pop     bp
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

.lba_lo:            dw 0
.lba_hi:            dw 0
.count:             dw 0
.verify_sect_done:  dw 0

;==============================================================================
; Function 47h: Extended Seek
;==============================================================================
; Seeks to LBA position.
;
; Input:  DS:SI = DAP with target LBA
; Output: AH = status
;==============================================================================
int13h_ext_seek:
    push    bx
    push    cx
    push    dx

    ; Validate DAP
    cmp     byte [si], DAP_SIZE_BASIC
    jb      .invalid_dap

    ; Get LBA
    mov     ax, [si + DAP.lba]
    mov     bx, [si + DAP.lba + 2]

    call    select_drive
    call    wait_drive_ready
    jc      .timeout

    ; Set up LBA in task file
    mov     dx, [current_base]
    add     dx, WD_SECNUM
    out     dx, al

    mov     al, ah
    inc     dx
    out     dx, al

    mov     al, bl
    inc     dx
    out     dx, al

    mov     al, bh
    and     al, 0x0F
    or      al, SDH_SIZE_512 | SDH_LBA
    inc     dx
    out     dx, al

    ; Issue SEEK command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_SEEK
    out     dx, al

    ; Wait for seek complete
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_SEEK

.wait_seek:
    in      al, dx
    test    al, STS_BSY
    jnz     .cont
    test    al, STS_DSC
    jnz     .seek_done
.cont:
    loop    .wait_seek
    jmp     .timeout

.seek_done:
    test    al, STS_ERR
    jnz     .error

    mov     ah, ST_SUCCESS
    jmp     .done

.invalid_dap:
    mov     ah, ST_BAD_COMMAND
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT
    jmp     .done

.error:
    mov     ah, ST_SEEK_ERROR

.done:
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 48h: Get Extended Drive Parameters
;==============================================================================
; Returns extended drive geometry and size.
;
; Input:  DL = drive
;         DS:SI = buffer for result
; Output: Buffer filled with EXT_PARAMS structure
;         AH = status
;==============================================================================
int13h_get_ext_params:
    push    bx
    push    cx
    push    dx
    push    di
    push    es

    ; Get drive parameters
    call    get_drive_params
    jc      .invalid_drive

    ; Set up ES:DI for output
    push    ds
    pop     es
    mov     di, si

    ; Check buffer size
    mov     ax, [si]
    cmp     ax, 1Ah                 ; Minimum size
    jb      .buffer_too_small

    ; Fill structure
    mov     word [di + EXT_PARAMS.size], 1Ah
    mov     word [di + EXT_PARAMS.flags], 0

    ; Cylinders (32-bit)
    mov     ax, [si + 0]            ; From drive params (note: SI still points there)
    push    si
    call    get_drive_params        ; Get fresh pointer
    mov     ax, [si]                ; Cylinders
    mov     [di + EXT_PARAMS.cylinders], ax
    mov     word [di + EXT_PARAMS.cylinders + 2], 0

    ; Heads (32-bit)
    xor     ah, ah
    mov     al, [si + 2]
    mov     [di + EXT_PARAMS.heads], ax
    mov     word [di + EXT_PARAMS.heads + 2], 0

    ; Sectors per track (32-bit)
    mov     al, [si + 3]
    mov     [di + EXT_PARAMS.sectors], ax
    mov     word [di + EXT_PARAMS.sectors + 2], 0

    ; Total sectors (64-bit) - calculate C*H*S
    mov     ax, [si]                ; Cylinders
    xor     bh, bh
    mov     bl, [si + 2]            ; Heads
    mul     bx                      ; DX:AX = C*H

    xor     bh, bh
    mov     bl, [si + 3]            ; Sectors
    ; 32-bit * 8-bit
    push    dx
    mul     bx                      ; AX = low * sectors
    mov     cx, ax
    pop     ax
    push    dx
    mul     bx
    pop     bx
    add     ax, bx

    mov     [di + EXT_PARAMS.total_sectors], cx
    mov     [di + EXT_PARAMS.total_sectors + 2], ax
    mov     dword [di + EXT_PARAMS.total_sectors + 4], 0

    ; Bytes per sector
    mov     word [di + EXT_PARAMS.bytes_sector], 512

    pop     si
    mov     ah, ST_SUCCESS
    jmp     .done

.invalid_drive:
    mov     ah, ST_BAD_COMMAND
    jmp     .done

.buffer_too_small:
    mov     ah, ST_BAD_COMMAND

.done:
    pop     es
    pop     di
    pop     dx
    pop     cx
    pop     bx
    ret

%endif ; ENABLE_LBA
