;==============================================================================
; FluxRipper FDD BIOS - Initialization
;==============================================================================
; Hooks INT 13h and updates BIOS Data Area for detected drives.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Hook INT 13h
;==============================================================================
; Saves the current INT 13h vector and installs our handler.
;
; Input:  None
; Output: [old_int13h] = saved original vector
;==============================================================================
hook_int13h:
    push    ax
    push    bx
    push    dx
    push    ds
    push    es

    ; Point to interrupt vector table
    xor     ax, ax
    mov     es, ax

    ; Save original INT 13h vector
    cli                             ; Disable interrupts while modifying IVT
    mov     ax, [es:0x4C]           ; INT 13h offset (13h * 4 = 0x4C)
    mov     [old_int13h], ax
    mov     ax, [es:0x4E]           ; INT 13h segment
    mov     [old_int13h+2], ax

    ; Install our handler
    mov     ax, int13h_handler
    mov     [es:0x4C], ax           ; Our offset
    mov     ax, cs
    mov     [es:0x4E], ax           ; Our segment
    sti                             ; Re-enable interrupts

%if ENABLE_PNP
    ; Also save INT 19h for boot vector
    mov     ax, [es:0x64]           ; INT 19h offset
    mov     [old_int19], ax
    mov     ax, [es:0x66]           ; INT 19h segment
    mov     [old_int19+2], ax
%endif

    pop     es
    pop     ds
    pop     dx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Update BIOS Data Area
;==============================================================================
; Updates the BIOS Data Area with information about detected drives.
; This makes the drives visible to DOS and other software.
;
; Input:  [num_drives] = number of detected drives
;         [drive_types] = BIOS type codes
; Output: BDA updated
;==============================================================================
update_bda:
    push    ax
    push    bx
    push    cx
    push    dx
    push    ds
    push    es

    ; Point DS to our data, ES to BDA
    push    cs
    pop     ds
    mov     ax, BDA_SEG
    mov     es, ax

    ; Update drive types in BDA (40:8F)
    ; Format: high nibble = drive 0, low nibble = drive 1
    mov     al, [drive_types]       ; Drive 0 type
    and     al, 0x0F
    mov     cl, 4
    shl     al, cl                  ; Shift to high nibble

    mov     bl, [drive_types+1]     ; Drive 1 type
    and     bl, 0x0F
    or      al, bl                  ; Combine

    mov     [es:BDA_DRIVE_TYPES], al

    ; Initialize media state for each drive (40:90-93)
    ; Set to "unknown" initially - will be determined on first access
    mov     cx, 4
    mov     bx, BDA_MEDIA_STATE
    xor     al, al
.clear_media:
    mov     [es:bx], al
    inc     bx
    loop    .clear_media

    ; Clear current track for each drive (40:94-97)
    mov     cx, 4
    mov     bx, BDA_CURR_TRACK
    xor     al, al
.clear_track:
    mov     [es:bx], al
    inc     bx
    loop    .clear_track

    ; Clear diskette status
    mov     byte [es:BDA_FLOPPY_STATUS], 0

    ; Clear motor status
    mov     byte [es:BDA_FLOPPY_MOTOR], 0

    ; Clear motor timeout counter
    mov     byte [es:BDA_MOTOR_COUNT], 0

    ; Clear recalibrate status
    mov     byte [es:BDA_FLOPPY_RECAL], 0

    pop     es
    pop     ds
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Display Detected Drives
;==============================================================================
; Prints a summary of detected drives to the console.
;
; Input:  [num_drives] = number of drives
;         [drive_types] = type codes
; Output: None
;==============================================================================
display_drives:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; Print header
    mov     si, msg_drives_header
    call    print_string

    ; Loop through drives
    mov     cl, [num_drives]
    test    cl, cl
    jz      .no_drives

    xor     ch, ch
    xor     dl, dl                  ; Drive number

.display_loop:
    push    cx

    ; Print drive number
    mov     si, msg_drive_prefix
    call    print_string
    mov     al, dl
    add     al, '0'
    mov     ah, 0x0E
    mov     bx, 0x0007
    int     0x10

    ; Print colon and space
    mov     al, ':'
    int     0x10
    mov     al, ' '
    int     0x10

    ; Get and print drive type string
    mov     bl, dl
    xor     bh, bh
    mov     al, [drive_types + bx]
    call    get_type_string
    call    print_string

    ; Print auto-detect indicator
    mov     si, msg_auto_detect
    call    print_string

    ; Newline
    mov     si, msg_crlf
    call    print_string

    pop     cx
    inc     dl
    loop    .display_loop
    jmp     .done

.no_drives:
    mov     si, msg_no_drives
    call    print_string

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Initialize FDC
;==============================================================================
; Performs initial FDC setup for primary and secondary (if present) FDC.
;
; Input:  None
; Output: None
;==============================================================================
init_fdc:
    push    ax
    push    cx
    push    dx

    ; Reset primary FDC
    mov     dx, FDC_PRIMARY + FDC_DOR
    mov     al, 0                   ; Assert reset
    out     dx, al

    ; Short delay
    mov     cx, 10
    call    delay_ms

    ; Release reset, enable DMA/IRQ
    mov     al, DOR_RESET | DOR_DMA_EN
    out     dx, al

    ; Configure primary FDC with SPECIFY command
    call    fdc_specify

    ; Detect and initialize secondary FDC
    call    detect_secondary_fdc

    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; Detect Secondary FDC
;==============================================================================
; Checks if secondary FDC (0x370) is present and initializes it.
;
; Input:  None
; Output: [secondary_fdc_present] = 0 or 1
;==============================================================================
detect_secondary_fdc:
    push    ax
    push    cx
    push    dx

    ; Read MSR from secondary FDC
    mov     dx, FDC_SECONDARY + FDC_MSR
    in      al, dx

    ; Check for valid response (0xFF = floating bus, no FDC)
    cmp     al, 0xFF
    je      .not_present

    ; Additional check: on a real FDC, RQM (bit 7) should be set when idle
    ; and command busy (bit 4) should be clear
    test    al, MSR_RQM
    jz      .not_present

    ; Secondary FDC appears present - initialize it
    mov     byte [secondary_fdc_present], 1

    ; Reset secondary FDC
    mov     dx, FDC_SECONDARY + FDC_DOR
    xor     al, al                  ; Assert reset
    out     dx, al

    mov     cx, 10
    call    delay_ms

    mov     al, DOR_RESET | DOR_DMA_EN
    out     dx, al

    ; Send SPECIFY command to secondary FDC
    push    word [current_fdc]      ; Save current FDC
    mov     word [current_fdc], FDC_SECONDARY
    call    fdc_specify
    pop     word [current_fdc]      ; Restore current FDC

    jmp     .done

.not_present:
    mov     byte [secondary_fdc_present], 0

.done:
    pop     dx
    pop     cx
    pop     ax
    ret

;==============================================================================
; Setup Default Drive Mapping
;==============================================================================
; Maps detected physical drives to logical DOS drive letters (A:, B:, etc.)
; Detected drives are mapped in order, skipping non-existent drives.
;
; Input:  [num_drives] = number of detected drives
;         [drive_types] = type codes for each physical drive
; Output: [drive_map] = logical to physical mapping
;         [phys_to_logical] = physical to logical mapping
;         [mapped_drive_count] = number of mapped drives
;==============================================================================
setup_default_mapping:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Clear mapping tables first
    mov     cx, 4
    xor     bx, bx
.clear_map:
    mov     byte [drive_map + bx], 0xFF     ; 0xFF = not mapped
    mov     byte [phys_to_logical + bx], 0xFF
    inc     bx
    loop    .clear_map

    ; Map detected drives in order to A:, B:, C:, D:
    xor     cx, cx                  ; CL = logical drive counter (A:=0, B:=1...)
    xor     dx, dx                  ; DL = physical drive counter

.map_loop:
    cmp     dl, 4
    jae     .done                   ; Checked all physical drives

    ; Check if physical drive exists
    mov     bl, dl
    xor     bh, bh
    mov     al, [drive_types + bx]
    test    al, al
    jz      .next_physical          ; No drive at this position, skip

    ; Map this physical drive to next logical drive letter
    ; drive_map[logical] = physical
    mov     bx, cx
    mov     [drive_map + bx], dl

    ; phys_to_logical[physical] = logical
    mov     bx, dx
    mov     [phys_to_logical + bx], cl

    inc     cl                      ; Next logical drive

.next_physical:
    inc     dl                      ; Next physical drive
    jmp     .map_loop

.done:
    ; Store mapped drive count
    mov     [mapped_drive_count], cl

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; Update BDA Equipment Word
;==============================================================================
; Updates the BIOS Data Area equipment word with floppy drive count.
; Equipment word (0040:0010):
;   Bit 0: Floppy drive(s) present
;   Bits 6-7: Number of floppy drives - 1 (if bit 0 set)
;
; Input:  [mapped_drive_count] = number of mapped drives
; Output: BDA equipment word updated
;==============================================================================
update_bda_equipment:
    push    ax
    push    bx
    push    cx
    push    es

    ; Point ES to BDA
    mov     ax, BDA_SEG
    mov     es, ax

    ; Get mapped drive count
    mov     al, [mapped_drive_count]
    test    al, al
    jz      .no_floppies

    ; Calculate equipment word bits
    ; Bits 6-7 = (num_drives - 1), max 3
    dec     al                      ; num_drives - 1
    cmp     al, 3
    jbe     .count_ok
    mov     al, 3                   ; Cap at 3 (represents 4 drives)
.count_ok:
    mov     cl, 6
    shl     al, cl                  ; Shift to bits 6-7
    or      al, 0x01                ; Set bit 0 (floppy present)

    ; Read current equipment word and update floppy bits
    ; First clear existing floppy bits (0, 6, 7)
    mov     bx, [es:BDA_EQUIPMENT]
    and     bx, 0xFF3E              ; Clear bits 0, 6, 7
    or      bl, al                  ; Set new floppy bits
    mov     [es:BDA_EQUIPMENT], bx

    jmp     .done

.no_floppies:
    ; Clear floppy bits in equipment word
    mov     bx, [es:BDA_EQUIPMENT]
    and     bx, 0xFF3E              ; Clear bits 0, 6, 7
    mov     [es:BDA_EQUIPMENT], bx

.done:
    pop     es
    pop     cx
    pop     bx
    pop     ax
    ret

;==============================================================================
; FDC Specify Command
;==============================================================================
; Sends the SPECIFY command to set timing parameters.
;
; Input:  None
; Output: None
;==============================================================================
fdc_specify:
    push    ax
    push    dx

    ; Wait for FDC ready
    call    wait_fdc_ready
    jc      .done

    ; Send SPECIFY command
    mov     al, CMD_SPECIFY
    call    fdc_write_data

    ; Specify byte 1: SRT=8 (8ms), HUT=0 (maximum)
    mov     al, 0x80                ; SRT=8, HUT=0
    call    fdc_write_data

    ; Specify byte 2: HLT=1 (2ms), ND=0 (DMA mode)
    mov     al, 0x02                ; HLT=1, ND=0
    call    fdc_write_data

.done:
    pop     dx
    pop     ax
    ret
