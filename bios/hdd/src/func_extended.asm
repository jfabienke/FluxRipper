;==============================================================================
; FluxRipper HDD BIOS - Extended INT 13h Functions (09h-15h)
;==============================================================================
; Implements extended INT 13h functions for AT-class systems.
;
; Functions:
;   09h - Initialize drive parameters
;   0Ah - Read long (sector + ECC)
;   0Bh - Write long (sector + ECC)
;   0Ch - Seek to cylinder
;   0Dh - Alternate disk reset
;   10h - Test drive ready
;   11h - Recalibrate drive
;   14h - Controller internal diagnostic
;   15h - Get disk type
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%if ENABLE_EXTENDED

;==============================================================================
; Function 09h: Initialize Drive Parameters
;==============================================================================
; Sets up the drive with specified parameters from FDPT.
;
; Input:  DL = drive number
; Output: AH = status
;         CF = 0 if success
;==============================================================================
int13h_init_drive:
    push    bx
    push    cx
    push    dx
    push    si

    ; Get FDPT for this drive
    call    get_fdpt_ptr
    jc      .invalid_drive

    ; Select drive
    call    select_drive

    ; Wait for drive ready
    call    wait_drive_ready
    jc      .timeout

    ; Set up INITIALIZE DRIVE PARAMETERS command
    ; This tells the controller the drive geometry

    ; Sector count = sectors per track
    mov     al, [si + FDPT_SECTORS]
    mov     dx, [current_base]
    add     dx, WD_SECCNT
    out     dx, al

    ; SDH = max head number
    mov     al, [si + FDPT_MAX_HEAD]
    dec     al                      ; Convert count to max (0-based)
    and     al, 0x0F
    or      al, SDH_SIZE_512
    ; Add drive select
    mov     bl, [bp + 6]            ; Get DL from stack
    cmp     bl, 0x81
    jne     .drive0_init
    or      al, SDH_DRV1
.drive0_init:
    mov     dx, [current_base]
    add     dx, WD_SDH
    out     dx, al

    ; Issue INITIALIZE DRIVE PARAMETERS command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_INIT_PARAM
    out     dx, al

    ; Wait for completion
    call    wait_drive_ready
    jc      .timeout

    ; Check status
    mov     dx, [current_base]
    add     dx, WD_STATUS
    in      al, dx
    test    al, STS_ERR
    jnz     .error

    mov     ah, ST_SUCCESS
    jmp     .done

.invalid_drive:
    mov     ah, ST_BAD_COMMAND
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT
    jmp     .done

.error:
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 0Ah: Read Long (Sector + ECC)
;==============================================================================
; Reads sector data plus ECC bytes (typically 4-7 extra bytes).
;
; Input:  AL = sector count (usually 1)
;         CH = cylinder low
;         CL = sector + cylinder high
;         DH = head
;         DL = drive
;         ES:BX = buffer
; Output: AH = status
;         AL = sectors read
;         CF = 0 if success
;==============================================================================
int13h_read_long:
    push    bx
    push    cx
    push    dx
    push    di

    ; Save count
    mov     [.count], al

    ; Select drive
    call    select_drive

    ; Wait ready
    call    wait_drive_ready
    jc      .timeout

    ; Set up task file (same as regular read)
    mov     al, [.count]
    mov     dx, [current_base]
    add     dx, WD_SECCNT
    out     dx, al

    mov     al, cl
    and     al, 0x3F
    inc     dx
    out     dx, al

    mov     al, ch
    inc     dx
    out     dx, al

    mov     al, cl
    shr     al, 6
    inc     dx
    out     dx, al

    ; Issue READ LONG command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_READ_LONG
    out     dx, al

    ; Wait for DRQ
    call    wd_wait_drq
    jc      .error

    ; Read 516 bytes (512 data + 4 ECC) per sector
    mov     di, bx
    mov     cx, 258                 ; 258 words = 516 bytes
    mov     dx, [current_base]
    add     dx, WD_DATA
    rep insw

    mov     al, [.count]
    mov     ah, ST_SUCCESS
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT
    xor     al, al
    jmp     .done

.error:
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error
    xor     al, al

.done:
    pop     di
    pop     dx
    pop     cx
    pop     bx
    ret

.count: db 0

;==============================================================================
; Function 0Bh: Write Long (Sector + ECC)
;==============================================================================
; Writes sector data plus ECC bytes.
;
; Input:  Same as Read Long
; Output: Same as Read Long
;==============================================================================
int13h_write_long:
    push    bx
    push    cx
    push    dx
    push    si

    mov     [.count], al

    call    select_drive
    call    wait_drive_ready
    jc      .timeout

    ; Set up task file
    mov     al, [.count]
    mov     dx, [current_base]
    add     dx, WD_SECCNT
    out     dx, al

    mov     al, cl
    and     al, 0x3F
    inc     dx
    out     dx, al

    mov     al, ch
    inc     dx
    out     dx, al

    mov     al, cl
    shr     al, 6
    inc     dx
    out     dx, al

    ; Issue WRITE LONG command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_WRITE_LONG
    out     dx, al

    ; Wait for DRQ
    call    wd_wait_drq
    jc      .error

    ; Write 516 bytes
    mov     si, bx
    push    es
    pop     ds
    mov     cx, 258
    mov     dx, [cs:current_base]
    add     dx, WD_DATA
    rep outsw
    push    cs
    pop     ds

    ; Wait for completion
    call    wd_wait_not_busy
    jc      .timeout

    mov     al, [.count]
    mov     ah, ST_SUCCESS
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT
    xor     al, al
    jmp     .done

.error:
    push    cs
    pop     ds
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error
    xor     al, al

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

.count: db 0

;==============================================================================
; Function 0Ch: Seek to Cylinder
;==============================================================================
; Moves the head to the specified cylinder.
;
; Input:  CH = cylinder low
;         CL = cylinder high (bits 6-7)
;         DH = head
;         DL = drive
; Output: AH = status
;         CF = 0 if success
;==============================================================================
int13h_seek:
    push    bx
    push    cx
    push    dx

    ; Select drive and head
    call    select_drive

    ; Wait ready
    call    wait_drive_ready
    jc      .timeout

    ; Set cylinder
    mov     al, ch
    mov     dx, [current_base]
    add     dx, WD_CYL_LO
    out     dx, al

    mov     al, cl
    shr     al, 6
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
    jnz     .continue
    test    al, STS_DSC             ; Seek complete?
    jnz     .seek_done
.continue:
    loop    .wait_seek
    jmp     .timeout

.seek_done:
    test    al, STS_ERR
    jnz     .error

    mov     ah, ST_SUCCESS
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
; Function 10h: Test Drive Ready
;==============================================================================
; Checks if the drive is ready.
;
; Input:  DL = drive
; Output: AH = status (0 if ready)
;         CF = 0 if ready
;==============================================================================
int13h_test_ready:
    push    dx

    ; Select drive
    call    select_drive

    ; Check status
    mov     dx, [current_base]
    add     dx, WD_STATUS
    in      al, dx

    ; Check BSY
    test    al, STS_BSY
    jnz     .not_ready

    ; Check DRDY
    test    al, STS_DRDY
    jz      .not_ready

    mov     ah, ST_SUCCESS
    jmp     .done

.not_ready:
    mov     ah, ST_NOT_READY

.done:
    pop     dx
    ret

;==============================================================================
; Function 11h: Recalibrate Drive
;==============================================================================
; Moves the head to track 0.
;
; Input:  DL = drive
; Output: AH = status
;         CF = 0 if success
;==============================================================================
int13h_recalibrate:
    push    bx
    push    cx
    push    dx

    ; Select drive
    call    select_drive

    ; Wait ready
    call    wait_drive_ready
    jc      .timeout

    ; Issue RECALIBRATE command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_RECALIBRATE
    out     dx, al

    ; Wait for completion (recalibrate can take a while)
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, 0                   ; Long timeout (65536 iterations)

.wait_loop:
    in      al, dx
    test    al, STS_BSY
    jz      .check_done
    loop    .wait_loop
    jmp     .timeout

.check_done:
    ; Check for error
    test    al, STS_ERR
    jnz     .error

    ; Check Track 0 found (seek complete)
    test    al, STS_DSC
    jz      .error

    mov     ah, ST_SUCCESS
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT
    jmp     .done

.error:
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    test    al, ERR_TK0NF
    jnz     .track0_error
    mov     ah, ST_SEEK_ERROR
    jmp     .done

.track0_error:
    mov     ah, ST_SEEK_ERROR

.done:
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 14h: Controller Internal Diagnostic
;==============================================================================
; Runs controller self-test.
;
; Input:  DL = drive
; Output: AH = status (0 = passed)
;         CF = 0 if passed
;==============================================================================
int13h_diagnostic:
    push    bx
    push    cx
    push    dx

    ; Issue EXECUTE DRIVE DIAGNOSTICS command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_DIAG
    out     dx, al

    ; Wait for completion
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_DRDY

.wait_loop:
    in      al, dx
    test    al, STS_BSY
    jz      .check_result
    loop    .wait_loop
    jmp     .timeout

.check_result:
    ; Read diagnostic code from error register
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx

    ; Code 01h = passed (no error)
    cmp     al, 0x01
    je      .passed

    ; Convert diagnostic code to status
    mov     ah, ST_CONTROLLER
    jmp     .done

.passed:
    mov     ah, ST_SUCCESS
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT

.done:
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 15h: Get Disk Type
;==============================================================================
; Returns disk type and size.
;
; Input:  DL = drive
; Output: AH = disk type (0=not present, 1=floppy no change, 2=floppy change, 3=hard disk)
;         CX:DX = number of 512-byte sectors (if AH=3)
;         CF = 0 if success
;==============================================================================
int13h_get_disk_type:
    push    bx
    push    si

    ; Validate drive
    call    get_drive_params
    jc      .not_present

    ; It's a hard disk
    mov     ah, 3                   ; Type 3 = hard disk

    ; Calculate total sectors
    ; Total = cylinders * heads * sectors
    mov     ax, [si + 0]            ; Cylinders
    xor     bh, bh
    mov     bl, [si + 2]            ; Heads
    mul     bx                      ; DX:AX = cyl * heads

    xor     bh, bh
    mov     bl, [si + 3]            ; Sectors
    ; 32-bit multiply
    push    dx
    mul     bx                      ; Low result
    mov     cx, ax                  ; Save low word
    pop     ax
    push    dx
    mul     bx                      ; High result
    pop     bx
    add     ax, bx

    ; Result: CX = low word, DX = high word (swapped for return)
    xchg    cx, dx                  ; CX:DX = sector count

    mov     ah, 3                   ; Disk type
    clc
    jmp     .done

.not_present:
    mov     ah, 0                   ; Not present
    xor     cx, cx
    xor     dx, dx
    ; CF already set from get_drive_params

.done:
    pop     si
    pop     bx
    ret

%endif ; ENABLE_EXTENDED
