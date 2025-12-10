;==============================================================================
; FluxRipper HDD BIOS - FPGA Discovery Register Access
;==============================================================================
; Routines for reading drive discovery information from FPGA registers.
;
; The FPGA automatically detects connected drives during power-up:
;   1. PHY probe - Check for drive presence on ST-506/ESDI interface
;   2. Rate detect - Measure data rate (5/7.5/10/15 Mbps)
;   3. Decode test - Verify MFM/RLL decoding
;   4. Geometry scan - Read track 0 to determine C/H/S
;
; This BIOS simply reads the results rather than probing the drive.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%include "discovery.inc"

;==============================================================================
; Wait for Discovery Complete
;==============================================================================
; Waits for FPGA discovery to finish (DISC_STS_DONE set or timeout).
;
; Output: CF = 0 if discovery complete, CF = 1 if timeout/error
;         AL = discovery status byte
; Destroys: AX, CX, DX
;==============================================================================
wait_discovery:
    push    bx
    push    cx

    ; Timeout counter (approximately 5 seconds at ~1ms per iteration)
    mov     cx, DISC_TIMEOUT_MS

.wait_loop:
    ; Read discovery status
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_STATUS
    in      al, dx

    ; Check for done flag
    test    al, DISC_STS_DONE
    jnz     .check_error

    ; Check for error flag
    test    al, DISC_STS_ERROR
    jnz     .error

    ; Not done yet - delay and retry
    push    cx
    mov     cx, 1                   ; 1ms delay
    call    delay_ms
    pop     cx

    loop    .wait_loop

    ; Timeout
    stc
    jmp     .done

.check_error:
    ; Done - but check if error occurred
    test    al, DISC_STS_ERROR
    jnz     .error
    clc                             ; Success
    jmp     .done

.error:
    stc                             ; Error

.done:
    pop     cx
    pop     bx
    ret

;==============================================================================
; Read Drive Geometry from FPGA
;==============================================================================
; Reads discovered geometry for both drives into drive parameter structures.
;
; Output: CF = 0 if at least one drive detected, CF = 1 if no drives
;         [num_drives] updated with drive count
;         [drive0_params] and [drive1_params] populated
; Destroys: AX, BX, CX, DX, SI
;==============================================================================
read_geometry:
    push    bx
    push    cx
    push    dx
    push    si

    ; Clear drive count
    mov     byte [num_drives], 0

    ; Read discovery status to check which drives are present
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_STATUS
    in      al, dx
    mov     bl, al                  ; Save status in BL

    ; Read global flags
    inc     dx
    in      al, dx
    mov     bh, al                  ; Save flags in BH

    ; Read detected personality
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_PERSONALITY
    in      al, dx
    mov     [personality], al

    ;--------------------------------------------------------------------------
    ; Read Drive 0 Geometry
    ;--------------------------------------------------------------------------
    test    bl, DISC_STS_D0_PRESENT
    jz      .try_drive1

    ; Drive 0 is present
    mov     si, drive0_params

    ; Read cylinders
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_D0_CYL_LO
    in      al, dx
    mov     [si + 0], al            ; Low byte
    inc     dx
    in      al, dx
    mov     [si + 1], al            ; High byte

    ; Read heads
    inc     dx
    in      al, dx
    mov     [si + 2], al            ; Heads

    ; Read sectors per track
    inc     dx
    in      al, dx
    mov     [si + 3], al            ; Sectors

    ; Read flags
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_D0_FLAGS
    in      al, dx
    mov     [si + 4], al            ; Flags

    ; Increment drive count
    inc     byte [num_drives]

    ;--------------------------------------------------------------------------
    ; Read Drive 1 Geometry
    ;--------------------------------------------------------------------------
.try_drive1:
    test    bl, DISC_STS_D1_PRESENT
    jz      .check_result

    ; Drive 1 is present
    mov     si, drive1_params

    ; Read cylinders
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_D1_CYL_LO
    in      al, dx
    mov     [si + 0], al
    inc     dx
    in      al, dx
    mov     [si + 1], al

    ; Read heads
    inc     dx
    in      al, dx
    mov     [si + 2], al

    ; Read sectors per track
    inc     dx
    in      al, dx
    mov     [si + 3], al

    ; Read flags
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_D1_FLAGS
    in      al, dx
    mov     [si + 4], al

    ; Increment drive count
    inc     byte [num_drives]

.check_result:
    ; Return success if at least one drive found
    cmp     byte [num_drives], 0
    je      .no_drives

    clc
    jmp     .done

.no_drives:
    stc

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;==============================================================================
; Read Drive Model String
;==============================================================================
; Reads the drive model string from FPGA into a buffer.
;
; Input:  ES:DI = destination buffer (32 bytes min)
; Output: CF = 0 success, CF = 1 if no string available
;         Buffer filled with null-terminated string
; Destroys: AX, CX, DX, DI
;==============================================================================
read_model_string:
    push    cx
    push    dx

    mov     cx, DISC_MODEL_LEN

    ; Read model string byte by byte
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_MODEL_BASE

.read_loop:
    in      al, dx
    stosb                           ; Store to ES:DI
    inc     dx
    loop    .read_loop

    ; Ensure null termination
    xor     al, al
    dec     di
    mov     [es:di], al

    clc

    pop     dx
    pop     cx
    ret

;==============================================================================
; Get Detected Personality
;==============================================================================
; Returns the detected WD controller personality.
;
; Output: AL = personality code (PERS_WD1002/1003/1006/1007)
; Destroys: None
;==============================================================================
get_personality:
    mov     al, [personality]
    ret

;==============================================================================
; Get Slot Type
;==============================================================================
; Returns the detected ISA slot type (8-bit XT or 16-bit AT).
;
; Output: AL = 0 for 8-bit XT slot, AL = 1 for 16-bit AT slot
; Destroys: DX
;==============================================================================
get_slot_type:
    push    dx
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_SLOT_TYPE
    in      al, dx
    pop     dx
    ret

;==============================================================================
; Check ESDI Mode
;==============================================================================
; Returns whether ESDI interface was detected.
;
; Output: CF = 1 if ESDI detected, CF = 0 if ST-506
; Destroys: AL, DX
;==============================================================================
check_esdi_mode:
    push    dx
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_FLAGS
    in      al, dx
    test    al, DISC_FLG_ESDI
    jz      .not_esdi
    stc
    jmp     .done
.not_esdi:
    clc
.done:
    pop     dx
    ret

;==============================================================================
; Check RLL Mode
;==============================================================================
; Returns whether RLL encoding was detected.
;
; Output: CF = 1 if RLL detected, CF = 0 if MFM
; Destroys: AL, DX
;==============================================================================
check_rll_mode:
    push    dx
    mov     dx, [current_base]
    add     dx, DISC_REG_BASE + DISC_FLAGS
    in      al, dx
    test    al, DISC_FLG_RLL
    jz      .not_rll
    stc
    jmp     .done
.not_rll:
    clc
.done:
    pop     dx
    ret

;==============================================================================
; Get Data Rate
;==============================================================================
; Returns the detected data rate for a drive.
;
; Input:  DL = drive number (0 or 1)
; Output: AL = rate code (RATE_5MBPS, RATE_7_5MBPS, etc.)
; Destroys: DX
;==============================================================================
get_data_rate:
    push    dx
    mov     dh, dl                  ; Save drive number

    mov     dx, [current_base]
    add     dx, DISC_REG_BASE

    ; Select correct register based on drive
    test    dh, dh
    jz      .drive0
    add     dx, DISC_D1_RATE
    jmp     .read
.drive0:
    add     dx, DISC_D0_RATE
.read:
    in      al, dx
    pop     dx
    ret

;==============================================================================
; Read Total Sectors (32-bit)
;==============================================================================
; Returns the total sector count for a drive.
;
; Input:  DL = drive number (0 or 1)
; Output: DX:AX = 32-bit sector count
; Destroys: BX
;==============================================================================
read_total_sectors:
    push    bx
    push    cx

    mov     bl, dl                  ; Save drive number

    mov     dx, [current_base]
    add     dx, DISC_REG_BASE

    ; Select correct register base
    test    bl, bl
    jz      .drive0
    add     dx, DISC_D1_CAP_0
    jmp     .read
.drive0:
    add     dx, DISC_D0_CAP_0

.read:
    ; Read 4 bytes (little-endian)
    in      al, dx                  ; Byte 0
    mov     cl, al
    inc     dx
    in      al, dx                  ; Byte 1
    mov     ch, al
    inc     dx
    in      al, dx                  ; Byte 2
    mov     bl, al
    inc     dx
    in      al, dx                  ; Byte 3
    mov     bh, al

    ; Assemble result in DX:AX
    mov     ax, cx                  ; AX = low word
    mov     dx, bx                  ; DX = high word

    pop     cx
    pop     bx
    ret
