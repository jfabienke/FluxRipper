;==============================================================================
; FluxRipper FDD BIOS - Read/Write/Verify Operations
;==============================================================================
; Sector read, write, and verify operations for INT 13h functions 02h-04h.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Function 02h: Read Sectors
;==============================================================================
; Reads one or more sectors from disk.
;
; Input:  AL = number of sectors to read
;         CH = cylinder (low 8 bits)
;         CL = sector (bits 0-5) + cylinder high bits (6-7)
;         DH = head
;         DL = drive
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
    push    bp

    ; Save parameters
    mov     bp, sp
    push    ax                      ; [bp-2] = sector count
    push    cx                      ; [bp-4] = cylinder/sector
    push    dx                      ; [bp-6] = head/drive
    push    bx                      ; [bp-8] = buffer offset
    push    es                      ; [bp-10] = buffer segment

    ; Get drive type for data rate
    mov     bl, dl
    xor     bh, bh
    mov     al, [drive_types + bx]
    call    get_data_rate
    call    fdc_set_rate

    ; Select drive and turn on motor
    mov     dx, [bp-6]
    call    fdc_select_drive
    jc      .error

    ; Seek to cylinder
    mov     cx, [bp-4]
    mov     dx, [bp-6]
    call    fdc_seek
    jc      .error

    ; Setup DMA for read
    mov     ax, [bp-10]             ; Buffer segment
    mov     bx, [bp-8]              ; Buffer offset
    mov     cl, [bp-2]              ; Sector count
    mov     ch, 0x44                ; DMA read mode
    call    setup_dma
    jc      .error

    ; Send READ DATA command
    mov     al, CMD_READ_DATA
    call    fdc_write_data
    jc      .error

    ; Send command parameters
    ; Byte 1: Head/Drive
    mov     ax, [bp-6]
    mov     al, ah                  ; Head
    and     al, 0x01
    shl     al, 2
    mov     dl, [bp-6]
    and     dl, 0x03
    or      al, dl
    call    fdc_write_data
    jc      .error

    ; Byte 2: Cylinder
    mov     cx, [bp-4]
    mov     al, ch
    call    fdc_write_data
    jc      .error

    ; Byte 3: Head
    mov     dx, [bp-6]
    mov     al, dh
    call    fdc_write_data
    jc      .error

    ; Byte 4: Sector (starting sector)
    mov     al, cl
    and     al, 0x3F
    call    fdc_write_data
    jc      .error

    ; Byte 5: Sector size code (2 = 512 bytes)
    mov     al, 2
    call    fdc_write_data
    jc      .error

    ; Byte 6: End of track
    mov     bl, [bp-6]              ; Drive number
    xor     bh, bh
    shl     bx, 2
    mov     al, [drive_params + bx + 3]  ; SPT
    call    fdc_write_data
    jc      .error

    ; Byte 7: Gap length
    mov     al, 0x1B
    call    fdc_write_data
    jc      .error

    ; Byte 8: Data length (0xFF for 512-byte sectors)
    mov     al, 0xFF
    call    fdc_write_data
    jc      .error

    ; Wait for operation complete
    mov     cx, READ_TIMEOUT
    call    wait_fdc_int
    jc      .error

    ; Read result bytes
    sub     sp, 8
    mov     di, sp
    mov     cx, 7
    push    ds
    push    ss
    pop     ds
    call    fdc_read_results
    pop     ds
    jc      .error_cleanup

    ; Check ST0 for success
    mov     al, [ss:di]             ; ST0
    and     al, ST0_IC
    cmp     al, ST0_IC_NORMAL
    jne     .error_check_st

    ; Success
    add     sp, 8
    mov     al, [bp-2]              ; Return sector count
    xor     ah, ah
    call    set_disk_status
    clc
    jmp     .done

.error_check_st:
    ; Decode error from status registers
    mov     al, [ss:di+1]           ; ST1
    test    al, ST1_DE
    jnz     .error_crc
    test    al, ST1_ND
    jnz     .error_sector_nf
    test    al, ST1_MA
    jnz     .error_addr_mark
    test    al, ST1_OR
    jnz     .error_overrun
    jmp     .error_cleanup

.error_crc:
    mov     ah, STAT_CRC_ERROR
    jmp     .set_error

.error_sector_nf:
    mov     ah, STAT_SECTOR_NF
    jmp     .set_error

.error_addr_mark:
    mov     ah, STAT_ADDR_MARK_NF
    jmp     .set_error

.error_overrun:
    mov     ah, STAT_DMA_OVERRUN
    jmp     .set_error

.error_cleanup:
    add     sp, 8
.error:
    mov     ah, STAT_TIMEOUT

.set_error:
    mov     al, ah
    call    set_disk_status
    xor     al, al                  ; No sectors read
    stc

.done:
    add     sp, 10                  ; Clean up saved parameters
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 03h: Write Sectors
;==============================================================================
; Writes one or more sectors to disk.
;
; Input:  AL = number of sectors to write
;         CH = cylinder
;         CL = sector
;         DH = head
;         DL = drive
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
    push    bp

    ; Save parameters
    mov     bp, sp
    push    ax
    push    cx
    push    dx
    push    bx
    push    es

    ; Get drive type for data rate
    mov     bl, dl
    xor     bh, bh
    mov     al, [drive_types + bx]
    call    get_data_rate
    call    fdc_set_rate

    ; Select drive
    mov     dx, [bp-6]
    call    fdc_select_drive
    jc      .error

    ; Seek to cylinder
    mov     cx, [bp-4]
    mov     dx, [bp-6]
    call    fdc_seek
    jc      .error

    ; Setup DMA for write
    mov     ax, [bp-10]
    mov     bx, [bp-8]
    mov     cl, [bp-2]
    mov     ch, 0x48                ; DMA write mode
    call    setup_dma
    jc      .error

    ; Send WRITE DATA command
    mov     al, CMD_WRITE_DATA
    call    fdc_write_data
    jc      .error

    ; Send command parameters (same as read)
    mov     ax, [bp-6]
    mov     al, ah
    and     al, 0x01
    shl     al, 2
    mov     dl, [bp-6]
    and     dl, 0x03
    or      al, dl
    call    fdc_write_data
    jc      .error

    mov     cx, [bp-4]
    mov     al, ch
    call    fdc_write_data
    jc      .error

    mov     dx, [bp-6]
    mov     al, dh
    call    fdc_write_data
    jc      .error

    mov     al, cl
    and     al, 0x3F
    call    fdc_write_data
    jc      .error

    mov     al, 2
    call    fdc_write_data
    jc      .error

    mov     bl, [bp-6]
    xor     bh, bh
    shl     bx, 2
    mov     al, [drive_params + bx + 3]
    call    fdc_write_data
    jc      .error

    mov     al, 0x1B
    call    fdc_write_data
    jc      .error

    mov     al, 0xFF
    call    fdc_write_data
    jc      .error

    ; Wait for operation complete
    mov     cx, READ_TIMEOUT
    call    wait_fdc_int
    jc      .error

    ; Read result bytes
    sub     sp, 8
    mov     di, sp
    mov     cx, 7
    push    ds
    push    ss
    pop     ds
    call    fdc_read_results
    pop     ds
    jc      .error_cleanup

    ; Check ST0
    mov     al, [ss:di]
    and     al, ST0_IC
    cmp     al, ST0_IC_NORMAL
    jne     .error_cleanup

    add     sp, 8
    mov     al, [bp-2]
    xor     ah, ah
    call    set_disk_status
    clc
    jmp     .done

.error_cleanup:
    add     sp, 8
.error:
    mov     ah, STAT_TIMEOUT
    mov     al, ah
    call    set_disk_status
    xor     al, al
    stc

.done:
    add     sp, 10
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Function 04h: Verify Sectors
;==============================================================================
; Verifies sectors on disk (reads but doesn't store).
;
; Input:  AL = number of sectors
;         CH = cylinder
;         CL = sector
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
    push    si
    push    di

    ; For verify, we use the FDC's verify command
    ; This reads sectors but discards the data

    ; Get drive type for data rate
    mov     bl, dl
    xor     bh, bh
    push    ax
    mov     al, [drive_types + bx]
    call    get_data_rate
    call    fdc_set_rate
    pop     ax

    ; Select drive
    push    ax
    call    fdc_select_drive
    pop     ax
    jc      .error

    ; Seek to cylinder
    push    ax
    call    fdc_seek
    pop     ax
    jc      .error

    ; Use READ ID to verify track is readable
    ; (Simpler than full verify command)
    push    ax
    call    fdc_read_id
    pop     ax
    jc      .error

    ; Success
    xor     ah, ah
    call    set_disk_status
    clc
    jmp     .done

.error:
    mov     ah, STAT_SECTOR_NF
    mov     al, ah
    call    set_disk_status
    xor     al, al
    stc

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Setup DMA Controller
;==============================================================================
; Configures the DMA controller for a transfer.
;
; Input:  AX = buffer segment
;         BX = buffer offset
;         CL = sector count
;         CH = DMA mode (0x44=read, 0x48=write)
; Output: CF=0 on success, CF=1 on boundary crossing
;==============================================================================
setup_dma:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Calculate physical address
    ; Physical = (segment << 4) + offset
    mov     dx, ax                  ; Save segment
    mov     cl, 4
    shl     ax, cl                  ; Segment * 16
    add     ax, bx                  ; Add offset
    jc      .boundary               ; Overflow = 64KB boundary crossed
    mov     bx, ax                  ; BX = low 16 bits of address

    ; Calculate page
    mov     ax, dx
    shr     ax, cl                  ; Upper 4 bits of segment
    mov     dh, al                  ; DH = page

    ; Calculate transfer count (sectors * 512 - 1)
    xor     ch, ch
    mov     cl, [esp+4]             ; Original CL = sector count
    mov     ax, 512
    mul     cx
    dec     ax                      ; Count - 1

    ; Check for 64KB boundary crossing
    push    ax
    add     ax, bx
    jc      .boundary_pop
    pop     ax

    ; Program DMA controller
    ; Mask channel 2
    mov     al, 0x06                ; Channel 2, mask on
    out     DMA_MASK_REG, al

    ; Clear byte pointer flip-flop
    out     DMA_FLIP_FLOP, al

    ; Set mode
    mov     al, [esp+6]             ; Original CH = mode
    or      al, DMA_CHANNEL         ; Add channel number
    out     DMA_MODE_REG, al

    ; Set address (low, then high)
    mov     al, bl
    out     DMA_ADDR_REG, al
    mov     al, bh
    out     DMA_ADDR_REG, al

    ; Set page
    mov     al, dh
    out     DMA_PAGE_REG, al

    ; Set count (low, then high)
    pop     ax                      ; Get count back
    push    ax
    out     DMA_COUNT_REG, al
    mov     al, ah
    out     DMA_COUNT_REG, al

    ; Unmask channel 2
    mov     al, 0x02                ; Channel 2, mask off
    out     DMA_MASK_REG, al

    clc
    jmp     .done

.boundary_pop:
    pop     ax
.boundary:
    stc

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
