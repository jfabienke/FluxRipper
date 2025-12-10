;==============================================================================
; FluxRipper HDD BIOS - Basic INT 13h Functions (00h-08h)
;==============================================================================
; Implements core INT 13h functions required for basic disk access.
;
; Functions:
;   00h - Reset disk system
;   01h - Get status of last operation
;   02h - Read sectors
;   03h - Write sectors
;   04h - Verify sectors
;   05h - Format track
;   08h - Get drive parameters
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Function 00h: Reset Disk System
;==============================================================================
; Resets the disk controller and recalibrates the drive.
;
; Input:  DL = drive number (80h, 81h)
; Output: AH = status (0 = success)
;         CF = 0 if success, 1 if error
;==============================================================================
int13h_reset:
    push    bx
    push    cx
    push    dx

    ; Select the drive
    call    select_drive

    ; Issue software reset to controller
    mov     dx, [current_base]
    add     dx, WD_DEV_CTRL - WD_BASE_PRIMARY + WD_BASE_ALTERNATE
    mov     al, CTRL_SRST           ; Assert reset
    out     dx, al

    ; Wait a bit
    mov     cx, 100
    call    delay_us

    ; Clear reset
    xor     al, al
    out     dx, al

    ; Wait for BSY to clear
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_RESET

.wait_bsy:
    in      al, dx
    test    al, STS_BSY
    jz      .bsy_clear
    loop    .wait_bsy

    ; Timeout
    mov     ah, ST_TIMEOUT
    jmp     .done

.bsy_clear:
    ; Check for errors
    test    al, STS_ERR
    jz      .no_error

    ; Read error register
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    mov     ah, ST_RESET_FAILED
    jmp     .done

.no_error:
    ; Issue recalibrate command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_RECALIBRATE
    out     dx, al

    ; Wait for completion
    call    wait_drive_ready
    jc      .timeout

    ; Check status
    mov     dx, [current_base]
    add     dx, WD_STATUS
    in      al, dx
    test    al, STS_ERR
    jnz     .recal_error

    mov     ah, ST_SUCCESS
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT
    jmp     .done

.recal_error:
    mov     ah, ST_SEEK_ERROR

.done:
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 01h: Get Status of Last Operation
;==============================================================================
; Returns the status of the last INT 13h operation.
;
; Input:  DL = drive number
; Output: AH = status from last operation
;         AL = 0
;         CF = 0 if last operation succeeded, 1 if failed
;==============================================================================
int13h_get_status:
    push    es
    push    bx

    ; Read status from BDA
    mov     bx, BDA_SEG
    mov     es, bx
    mov     ah, [es:BDA_HDD_STATUS]
    xor     al, al

    pop     bx
    pop     es
    ret

;==============================================================================
; Function 02h: Read Sectors
;==============================================================================
; Reads sectors from disk to memory.
;
; Input:  AL = number of sectors to read
;         CH = cylinder low 8 bits
;         CL = sector (bits 0-5) + cylinder high (bits 6-7)
;         DH = head number
;         DL = drive number
;         ES:BX = buffer address
; Output: AH = status
;         AL = sectors read
;         CF = 0 if success, 1 if error
;==============================================================================
int13h_read_sectors:
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; Save sector count
    mov     [.sector_count], al
    mov     byte [.sectors_done], 0

    ; Select drive and head
    call    select_drive

    ; Wait for drive ready
    call    wait_drive_ready
    jc      .timeout

    ; Set up task file registers
    ; Sector count
    mov     al, [.sector_count]
    mov     dx, [current_base]
    add     dx, WD_SECCNT
    out     dx, al

    ; Sector number (bits 0-5 of CL)
    mov     al, cl
    and     al, 0x3F
    inc     dx                      ; WD_SECNUM
    out     dx, al

    ; Cylinder low (CH)
    mov     al, ch
    inc     dx                      ; WD_CYL_LO
    out     dx, al

    ; Cylinder high (bits 6-7 of CL)
    mov     al, cl
    shr     al, 6
    inc     dx                      ; WD_CYL_HI
    out     dx, al

    ; Issue READ command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_READ
    out     dx, al

    ; Read sector data
    mov     di, bx                  ; ES:DI = buffer
    mov     cl, [.sector_count]

.read_sector_loop:
    ; Wait for DRQ
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_DRQ_SET

.wait_drq:
    in      al, dx
    test    al, STS_ERR
    jnz     .read_error
    test    al, STS_DRQ
    jnz     .drq_set
    loop    .wait_drq
    jmp     .timeout

.drq_set:
    ; Read 256 words (512 bytes) from data register
    mov     dx, [current_base]
    add     dx, WD_DATA
    mov     cx, 256
    rep insw                        ; Read words to ES:DI

    ; Increment sectors done
    inc     byte [.sectors_done]

    ; Check if more sectors to read
    mov     al, [.sectors_done]
    cmp     al, [.sector_count]
    jb      .read_sector_loop

    ; Success
    mov     al, [.sectors_done]
    mov     ah, ST_SUCCESS
    jmp     .done

.read_error:
    ; Get error code
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error
    mov     al, [.sectors_done]
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT
    mov     al, [.sectors_done]

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

.sector_count:  db 0
.sectors_done:  db 0

;==============================================================================
; Function 03h: Write Sectors
;==============================================================================
; Writes sectors from memory to disk.
;
; Input:  AL = number of sectors to write
;         CH = cylinder low 8 bits
;         CL = sector (bits 0-5) + cylinder high (bits 6-7)
;         DH = head number
;         DL = drive number
;         ES:BX = buffer address
; Output: AH = status
;         AL = sectors written
;         CF = 0 if success, 1 if error
;==============================================================================
int13h_write_sectors:
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; Save sector count
    mov     [.sector_count], al
    mov     byte [.sectors_done], 0

    ; Select drive and head
    call    select_drive

    ; Wait for drive ready
    call    wait_drive_ready
    jc      .timeout

    ; Set up task file registers
    mov     al, [.sector_count]
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

    ; Issue WRITE command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_WRITE
    out     dx, al

    ; Write sector data
    mov     si, bx                  ; DS:SI = buffer (need to set up DS)
    push    es
    pop     ds                      ; DS = ES (buffer segment)

.write_sector_loop:
    ; Wait for DRQ
    push    ds
    push    cs
    pop     ds
    mov     dx, [current_base]
    pop     ds
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_DRQ_SET

.wait_drq:
    in      al, dx
    test    al, STS_ERR
    jnz     .write_error
    test    al, STS_DRQ
    jnz     .drq_set
    loop    .wait_drq
    jmp     .timeout

.drq_set:
    ; Write 256 words from buffer
    push    ds
    push    cs
    pop     ds
    mov     dx, [current_base]
    pop     ds
    add     dx, WD_DATA
    mov     cx, 256
    rep outsw                       ; Write words from DS:SI

    ; Wait for BSY to clear (sector written)
    push    ds
    push    cs
    pop     ds
    mov     dx, [current_base]
    pop     ds
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_BSY_CLR

.wait_bsy:
    in      al, dx
    test    al, STS_BSY
    jz      .bsy_clear
    loop    .wait_bsy
    jmp     .timeout

.bsy_clear:
    ; Check for write fault
    test    al, STS_DWF
    jnz     .write_fault

    ; Increment sectors done
    push    cs
    pop     ds
    inc     byte [.sectors_done]

    ; Check if more sectors
    mov     al, [.sectors_done]
    cmp     al, [.sector_count]
    jb      .write_sector_loop

    ; Success
    mov     al, [.sectors_done]
    mov     ah, ST_SUCCESS
    jmp     .done

.write_error:
    push    cs
    pop     ds
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error
    mov     al, [.sectors_done]
    jmp     .done

.write_fault:
    push    cs
    pop     ds
    mov     ah, ST_WRITE_FAULT
    mov     al, [.sectors_done]
    jmp     .done

.timeout:
    push    cs
    pop     ds
    mov     ah, ST_TIMEOUT
    mov     al, [.sectors_done]

.done:
    push    cs
    pop     ds                      ; Restore DS to ROM segment
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

.sector_count:  db 0
.sectors_done:  db 0

;==============================================================================
; Function 04h: Verify Sectors
;==============================================================================
; Verifies sectors on disk (reads and checks CRC, discards data).
;
; Input:  AL = number of sectors to verify
;         CH = cylinder low
;         CL = sector + cylinder high
;         DH = head
;         DL = drive
; Output: AH = status
;         AL = sectors verified
;         CF = 0 if success, 1 if error
;==============================================================================
int13h_verify_sectors:
    push    bx
    push    cx
    push    dx

    ; Save sector count
    mov     [.sector_count], al

    ; Select drive
    call    select_drive

    ; Wait for ready
    call    wait_drive_ready
    jc      .timeout

    ; Set up task file
    mov     al, [.sector_count]
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

    ; Issue VERIFY command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_VERIFY
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

    mov     al, [.sector_count]
    mov     ah, ST_SUCCESS
    jmp     .done

.error:
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error
    xor     al, al
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT
    xor     al, al

.done:
    pop     dx
    pop     cx
    pop     bx
    ret

.sector_count:  db 0

;==============================================================================
; Function 05h: Format Track
;==============================================================================
; Formats a track with specified interleave.
;
; Input:  AL = interleave factor (ignored, use 1:1)
;         CH = cylinder low
;         CL = cylinder high bits (6-7)
;         DH = head
;         DL = drive
;         ES:BX = address list (not used on WD controllers)
; Output: AH = status
;         CF = 0 if success, 1 if error
;==============================================================================
int13h_format_track:
    push    bx
    push    cx
    push    dx

    ; Select drive
    call    select_drive

    ; Wait for ready
    call    wait_drive_ready
    jc      .timeout

    ; Set up task file
    ; Sector count = sectors per track from FDPT
    push    si
    call    get_fdpt_ptr
    mov     al, [si + FDPT_SECTORS]
    pop     si

    mov     dx, [current_base]
    add     dx, WD_SECCNT
    out     dx, al

    ; Sector number = 1
    mov     al, 1
    inc     dx
    out     dx, al

    ; Cylinder
    mov     al, ch
    inc     dx
    out     dx, al

    mov     al, cl
    shr     al, 6
    inc     dx
    out     dx, al

    ; Issue FORMAT command
    mov     dx, [current_base]
    add     dx, WD_COMMAND
    mov     al, CMD_FORMAT
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

.error:
    mov     dx, [current_base]
    add     dx, WD_ERROR
    in      al, dx
    call    translate_error
    jmp     .done

.timeout:
    mov     ah, ST_TIMEOUT

.done:
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 08h: Get Drive Parameters
;==============================================================================
; Returns drive geometry information.
;
; Input:  DL = drive number
; Output: AH = status
;         BL = drive type (not used, returned as 0)
;         CH = max cylinder low 8 bits
;         CL = max sector (bits 0-5) + max cylinder high (bits 6-7)
;         DH = max head number
;         DL = number of drives
;         ES:DI = FDPT pointer
;         CF = 0 if success, 1 if error
;==============================================================================
int13h_get_parameters:
    push    bx
    push    si

    ; Get FDPT pointer for this drive
    call    get_fdpt_ptr
    jc      .invalid_drive

    ; Read geometry from FDPT
    mov     ax, [si + FDPT_MAX_CYL]
    dec     ax                      ; Max = count - 1
    mov     ch, al                  ; Low 8 bits
    shl     ah, 6                   ; High 2 bits to bits 6-7
    mov     al, [si + FDPT_SECTORS]
    or      al, ah                  ; Combine with max sector
    mov     cl, al

    mov     dh, [si + FDPT_MAX_HEAD]
    dec     dh                      ; Max = count - 1

    ; Return number of drives
    mov     dl, [num_drives]

    ; Return drive type (0 for HD)
    xor     bl, bl

    ; Return FDPT pointer in ES:DI
    push    cs
    pop     es
    mov     di, si

    mov     ah, ST_SUCCESS
    jmp     .done

.invalid_drive:
    mov     ah, ST_BAD_COMMAND

.done:
    pop     si
    pop     bx
    ret

;==============================================================================
; Helper: Translate WD Error to INT 13h Status
;==============================================================================
; Input:  AL = WD error register value
; Output: AH = INT 13h status code
;==============================================================================
translate_error:
    push    bx

    ; Default to undefined error
    mov     ah, ST_UNDEFINED

    test    al, ERR_BBK
    jnz     .bad_sector
    test    al, ERR_UNC
    jnz     .crc_error
    test    al, ERR_IDNF
    jnz     .sector_not_found
    test    al, ERR_ABRT
    jnz     .controller
    test    al, ERR_TK0NF
    jnz     .seek
    test    al, ERR_AMNF
    jnz     .addr_mark
    jmp     .done

.bad_sector:
    mov     ah, ST_BAD_SECTOR
    jmp     .done

.crc_error:
    mov     ah, ST_CRC_ERROR
    jmp     .done

.sector_not_found:
    mov     ah, ST_SECTOR_NOT_FOUND
    jmp     .done

.controller:
    mov     ah, ST_CONTROLLER
    jmp     .done

.seek:
    mov     ah, ST_SEEK_ERROR
    jmp     .done

.addr_mark:
    mov     ah, ST_ADDR_MARK

.done:
    pop     bx
    ret
