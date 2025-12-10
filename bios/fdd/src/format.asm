;==============================================================================
; FluxRipper FDD BIOS - Track Formatting
;==============================================================================
; Implements INT 13h function 05h for track formatting.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Function 05h: Format Track
;==============================================================================
; Formats a track with sector IDs.
;
; Input:  CH = cylinder
;         CL = sector (not used, format whole track)
;         DH = head
;         DL = drive
;         AL = sectors per track (interleave info)
;         ES:BX = address of format buffer
;                 Format: 4 bytes per sector: C, H, R, N
; Output: AH = status
;         CF = 0 if success, 1 if error
;==============================================================================
int13h_format_track:
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp

    ; Save parameters
    mov     bp, sp
    push    ax                      ; [bp-2] = sector count
    push    cx                      ; [bp-4] = cylinder
    push    dx                      ; [bp-6] = head/drive
    push    bx                      ; [bp-8] = format buffer offset
    push    es                      ; [bp-10] = format buffer segment

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

    ; Get sectors per track for this drive
    mov     bl, [bp-6]              ; Drive
    xor     bh, bh
    shl     bx, 2
    mov     cl, [drive_params + bx + 3]  ; SPT

    ; Calculate format buffer size (4 bytes per sector)
    xor     ch, ch
    mov     ax, cx
    shl     ax, 2                   ; * 4

    ; Setup DMA for write (format uses write mode)
    push    cx
    mov     ax, [bp-10]             ; Segment
    mov     bx, [bp-8]              ; Offset
    mov     cl, al                  ; Byte count (approximate)
    mov     ch, 0x48                ; DMA write mode
    call    setup_dma
    pop     cx
    jc      .error

    ; Send FORMAT TRACK command
    mov     al, CMD_FORMAT_TRACK
    call    fdc_write_data
    jc      .error

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

    ; Byte 2: Bytes per sector code (2 = 512)
    mov     al, 2
    call    fdc_write_data
    jc      .error

    ; Byte 3: Sectors per track
    mov     al, cl
    call    fdc_write_data
    jc      .error

    ; Byte 4: Gap 3 length for format
    mov     al, 0x6C                ; Standard gap for 1.44M
    call    fdc_write_data
    jc      .error

    ; Byte 5: Fill byte
    mov     al, 0xF6                ; Standard fill byte
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

    ; Success
    add     sp, 8
    xor     ah, ah
    call    set_disk_status
    clc
    jmp     .done

.error_cleanup:
    add     sp, 8
.error:
    mov     ah, STAT_WRITE_FAULT
    mov     al, ah
    call    set_disk_status
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
; Build Format Buffer
;==============================================================================
; Builds a format buffer for a track with standard interleave.
;
; Input:  CH = cylinder
;         DH = head
;         CL = sectors per track
;         ES:DI = destination buffer (4 * SPT bytes)
; Output: Buffer filled with C, H, R, N for each sector
;==============================================================================
build_format_buffer:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Sector number starts at 1
    mov     bl, 1                   ; Current sector
    xor     bh, bh

    ; Clear count
    xor     dx, dx

.format_loop:
    ; Cylinder
    mov     al, ch
    stosb

    ; Head
    mov     al, dh
    stosb

    ; Sector number
    mov     al, bl
    stosb

    ; Sector size code (2 = 512 bytes)
    mov     al, 2
    stosb

    ; Next sector with interleave
    ; Standard PC interleave is 1:1 (no interleave)
    inc     bl
    cmp     bl, cl
    jbe     .check_count

    ; Wrap around
    mov     bl, 1

.check_count:
    inc     dl
    cmp     dl, cl
    jb      .format_loop

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
