;==============================================================================
; FluxRipper FDD BIOS - FPGA Discovery Interface
;==============================================================================
; Routines to read drive profiles from the FluxRipper FPGA's auto-detection
; registers. These registers contain the results of the FPGA's drive
; characterization process.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Wait for Discovery Complete
;==============================================================================
; Waits for the FPGA to complete drive discovery on all connected drives.
; The FPGA sets PROFILE_VALID when detection is complete for each drive.
;
; Input:  None
; Output: CF=0 if discovery complete, CF=1 if timeout
;==============================================================================
wait_discovery:
    push    ax
    push    bx
    push    cx
    push    dx
    push    es

    ; Get BIOS tick counter for timeout
    xor     ax, ax
    mov     es, ax
    mov     bx, [es:0x046C]
    add     bx, DISC_TIMEOUT        ; Timeout in ticks (~5 seconds)

.wait_loop:
    ; Check primary FDC drive 0
    mov     dx, FDC_PRIMARY + DISC_PROFILE_A + 1
    in      al, dx                  ; Read profile byte 1 (bits 15:8)
    test    al, 0x80                ; PROFILE_VALID is bit 15 (byte 1, bit 7)
    jnz     .check_locked

    ; Check timeout
    mov     ax, [es:0x046C]
    cmp     ax, bx
    jb      .wait_loop

    ; Timeout
    stc
    jmp     .done

.check_locked:
    ; Also check if PROFILE_LOCKED (bit 14 = byte 1, bit 6) for confidence
    test    al, 0x40
    jz      .wait_loop              ; Wait for high-confidence detection

    ; Discovery complete
    clc

.done:
    pop     es
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Read Drive Profiles
;==============================================================================
; Reads the 32-bit DRIVE_PROFILE registers for all drives from the FPGA.
; Stores results in drive_profiles array.
;
; Input:  None
; Output: CF=0 if at least one drive detected, CF=1 if no drives
;         [num_drives] = number of drives found
;==============================================================================
read_profiles:
    push    ax
    push    bx
    push    cx
    push    dx
    push    di

    ; Clear drive count
    mov     byte [num_drives], 0

    ; Read primary FDC drive 0
    mov     dx, FDC_PRIMARY + DISC_PROFILE_A
    mov     di, drive_profiles
    call    read_one_profile
    jc      .try_drive1

    ; Drive 0 detected
    inc     byte [num_drives]

.try_drive1:
    ; Read primary FDC drive 1
    mov     dx, FDC_PRIMARY + DISC_PROFILE_B
    add     di, 4
    call    read_one_profile
    jc      .try_drive2

    ; Drive 1 detected
    inc     byte [num_drives]

.try_drive2:
    ; Check if secondary FDC is present before probing
    cmp     byte [secondary_fdc_present], 0
    je      .check_result           ; Skip drives 2-3 if no secondary FDC

    ; Read secondary FDC drive 0
    mov     dx, FDC_SECONDARY + DISC_PROFILE_A
    add     di, 4
    call    read_one_profile
    jc      .try_drive3

    ; Drive 2 detected
    inc     byte [num_drives]

.try_drive3:
    ; Read secondary FDC drive 1
    mov     dx, FDC_SECONDARY + DISC_PROFILE_B
    add     di, 4
    call    read_one_profile
    jc      .check_result

    ; Drive 3 detected
    inc     byte [num_drives]

.check_result:
    ; Check if any drives were found
    cmp     byte [num_drives], 0
    je      .no_drives

    clc
    jmp     .done

.no_drives:
    stc

.done:
    pop     di
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Read One Profile
;==============================================================================
; Reads a single 32-bit DRIVE_PROFILE register.
;
; Input:  DX = I/O port base for profile register
;         DS:DI = destination for 4-byte profile
; Output: CF=0 if valid profile, CF=1 if no drive/invalid
;         [DS:DI] = 32-bit profile value
;==============================================================================
read_one_profile:
    push    ax
    push    cx
    push    dx

    ; Read 4 bytes of profile
    mov     cx, 4
.read_loop:
    in      al, dx
    mov     [di], al
    inc     di
    inc     dx
    loop    .read_loop

    ; Reset DI to start of profile
    sub     di, 4

    ; Check if PROFILE_VALID is set
    mov     al, [di+1]              ; Byte 1 contains bits 15:8
    test    al, 0x80                ; PROFILE_VALID = bit 15
    jz      .invalid

    ; Check if profile indicates a valid drive type
    mov     al, [di]                ; Byte 0 contains form factor, density, tracks
    and     al, FORM_MASK
    cmp     al, FORM_UNKNOWN
    je      .invalid

    ; Valid profile
    clc
    jmp     .done

.invalid:
    ; Clear the profile to indicate no drive
    xor     al, al
    mov     [di], al
    mov     [di+1], al
    mov     [di+2], al
    mov     [di+3], al
    stc

.done:
    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; Get Drive Profile
;==============================================================================
; Returns the profile for a specific drive.
;
; Input:  DL = drive number (0-3)
; Output: EAX = 32-bit profile (0 if invalid drive)
;         CF=0 if valid, CF=1 if invalid
;==============================================================================
get_drive_profile:
    push    bx
    push    si

    ; Validate drive number
    cmp     dl, 4
    jae     .invalid

    ; Calculate offset into profile array
    mov     bl, dl
    xor     bh, bh
    shl     bx, 2                   ; Multiply by 4
    mov     si, drive_profiles
    add     si, bx

    ; Load 32-bit profile (in two 16-bit reads for 8086 compat)
    mov     ax, [si]                ; Low word
    mov     bx, [si+2]              ; High word

    ; Check if valid
    test    bh, 0x80                ; PROFILE_VALID in high byte
    jz      .invalid

    ; Return in EAX equivalent (DX:AX for 16-bit)
    mov     dx, bx
    clc
    jmp     .done

.invalid:
    xor     ax, ax
    xor     dx, dx
    stc

.done:
    pop     si
    pop     bx
    ret

;==============================================================================
; Get Profile Field
;==============================================================================
; Extracts a specific field from a drive profile.
;
; Input:  DL = drive number (0-3)
;         BL = field selector:
;              0 = Form Factor
;              1 = Density
;              2 = Track Density
;              3 = Encoding
;              4 = RPM/10
;              5 = Quality
; Output: AL = field value
;         CF=0 if valid, CF=1 if invalid
;==============================================================================
get_profile_field:
    push    bx
    push    cx
    push    dx
    push    si

    ; Get the full profile first
    call    get_drive_profile
    jc      .invalid

    ; DX:AX now contains the profile
    ; Select field based on BL
    cmp     bl, 0
    je      .form_factor
    cmp     bl, 1
    je      .density
    cmp     bl, 2
    je      .track_density
    cmp     bl, 3
    je      .encoding
    cmp     bl, 4
    je      .rpm
    cmp     bl, 5
    je      .quality
    jmp     .invalid

.form_factor:
    and     al, FORM_MASK
    jmp     .done

.density:
    and     al, DENS_MASK
    shr     al, DENS_SHIFT
    jmp     .done

.track_density:
    and     al, TRACK_MASK
    shr     al, TRACK_SHIFT
    jmp     .done

.encoding:
    mov     cl, ENC_SHIFT
    shr     ax, cl
    and     al, 0x07
    jmp     .done

.rpm:
    mov     al, dh                  ; RPM is in bits 23:16 (high word, low byte)
    jmp     .done

.quality:
    mov     al, [si+3]              ; Quality is in bits 31:24 (highest byte)
    jmp     .done

.invalid:
    xor     al, al
    stc
    jmp     .exit

.done:
    clc

.exit:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret
