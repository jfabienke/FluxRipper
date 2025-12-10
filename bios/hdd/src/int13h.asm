;==============================================================================
; FluxRipper HDD BIOS - INT 13h Handler
;==============================================================================
; Main INT 13h interrupt handler and function dispatcher.
;
; This handler:
;   1. Checks if request is for hard disk (DL >= 80h)
;   2. Maps drive number to our physical drive
;   3. Dispatches to appropriate function handler
;   4. Chains to original INT 13h for floppy requests
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%include "int13h.inc"

;==============================================================================
; INT 13h Entry Point
;==============================================================================
; Called via INT 13h from user code.
;
; We handle hard disk requests (DL >= 80h) and chain to original for floppy.
;==============================================================================
int13h_handler:
    ; Check if this is a hard disk request
    cmp     dl, 0x80
    jb      .chain_to_original      ; DL < 80h = floppy, chain

    ; Check if drive is one we manage
    push    ax
    mov     al, dl
    sub     al, 0x80                ; Convert 80h/81h to 0/1
    cmp     al, [cs:num_drives]     ; Compare with our drive count
    pop     ax
    jae     .chain_to_original      ; Drive not ours, chain

    ; This is our drive - save registers and dispatch
    INT13_SAVE_REGS

    ; Set up BP to access saved registers
    mov     bp, sp

    ; Set DS to ROM segment for access to our data
    push    cs
    pop     ds

    ; Dispatch based on function number in AH
    cmp     ah, FN_RESET
    je      .fn_reset
    cmp     ah, FN_GET_STATUS
    je      .fn_get_status
    cmp     ah, FN_READ_SECTORS
    je      .fn_read_sectors
    cmp     ah, FN_WRITE_SECTORS
    je      .fn_write_sectors
    cmp     ah, FN_VERIFY_SECTORS
    je      .fn_verify_sectors
    cmp     ah, FN_FORMAT_TRACK
    je      .fn_format_track
    cmp     ah, FN_GET_PARAMETERS
    je      .fn_get_parameters

%if ENABLE_EXTENDED
    ; Extended functions (16KB build only)
    cmp     ah, FN_INIT_DRIVE
    je      .fn_init_drive
    cmp     ah, FN_READ_LONG
    je      .fn_read_long
    cmp     ah, FN_WRITE_LONG
    je      .fn_write_long
    cmp     ah, FN_SEEK
    je      .fn_seek
    cmp     ah, FN_RESET_ALTERNATE
    je      .fn_reset_alternate
    cmp     ah, FN_TEST_READY
    je      .fn_test_ready
    cmp     ah, FN_RECALIBRATE
    je      .fn_recalibrate
    cmp     ah, FN_CTRL_DIAGNOSTIC
    je      .fn_diagnostic
    cmp     ah, FN_GET_DISK_TYPE
    je      .fn_get_disk_type
%endif

%if ENABLE_LBA
    ; LBA extension functions (16KB build only)
    cmp     ah, FN_CHECK_EXTENSIONS
    je      .fn_check_extensions
    cmp     ah, FN_EXT_READ
    je      .fn_ext_read
    cmp     ah, FN_EXT_WRITE
    je      .fn_ext_write
    cmp     ah, FN_EXT_VERIFY
    je      .fn_ext_verify
    cmp     ah, FN_EXT_SEEK
    je      .fn_ext_seek
    cmp     ah, FN_GET_EXT_PARAMS
    je      .fn_get_ext_params
%endif

    ; Unknown function - return invalid command error
    mov     ah, ST_BAD_COMMAND
    INT13_RETURN

;------------------------------------------------------------------------------
; Function Dispatch Table
;------------------------------------------------------------------------------
.fn_reset:
    call    int13h_reset
    INT13_RETURN

.fn_get_status:
    call    int13h_get_status
    INT13_RETURN

.fn_read_sectors:
    call    int13h_read_sectors
    INT13_RETURN

.fn_write_sectors:
    call    int13h_write_sectors
    INT13_RETURN

.fn_verify_sectors:
    call    int13h_verify_sectors
    INT13_RETURN

.fn_format_track:
    call    int13h_format_track
    INT13_RETURN

.fn_get_parameters:
    call    int13h_get_parameters
    INT13_RETURN

%if ENABLE_EXTENDED
.fn_init_drive:
    call    int13h_init_drive
    INT13_RETURN

.fn_read_long:
    call    int13h_read_long
    INT13_RETURN

.fn_write_long:
    call    int13h_write_long
    INT13_RETURN

.fn_seek:
    call    int13h_seek
    INT13_RETURN

.fn_reset_alternate:
    call    int13h_reset             ; Same as regular reset
    INT13_RETURN

.fn_test_ready:
    call    int13h_test_ready
    INT13_RETURN

.fn_recalibrate:
    call    int13h_recalibrate
    INT13_RETURN

.fn_diagnostic:
    call    int13h_diagnostic
    INT13_RETURN

.fn_get_disk_type:
    call    int13h_get_disk_type
    INT13_RETURN
%endif

%if ENABLE_LBA
.fn_check_extensions:
    call    int13h_check_extensions
    INT13_RETURN

.fn_ext_read:
    call    int13h_ext_read
    INT13_RETURN

.fn_ext_write:
    call    int13h_ext_write
    INT13_RETURN

.fn_ext_verify:
    call    int13h_ext_verify
    INT13_RETURN

.fn_ext_seek:
    call    int13h_ext_seek
    INT13_RETURN

.fn_get_ext_params:
    call    int13h_get_ext_params
    INT13_RETURN
%endif

;------------------------------------------------------------------------------
; Chain to Original INT 13h (for floppy or unhandled drives)
;------------------------------------------------------------------------------
.chain_to_original:
    ; Jump to original handler (saved during init)
    jmp     far [cs:old_int13h]

;==============================================================================
; Helper: Get Drive Parameters Pointer
;==============================================================================
; Returns pointer to drive parameter structure for given drive.
;
; Input:  DL = drive number (80h or 81h)
; Output: SI = pointer to drive_params structure
;         CF = 0 if valid, CF = 1 if invalid drive
; Destroys: AX
;==============================================================================
get_drive_params:
    mov     al, dl
    sub     al, 0x80                ; Convert to 0/1

    cmp     al, [num_drives]        ; Valid drive?
    jae     .invalid

    ; Calculate pointer
    test    al, al
    jz      .drive0
    mov     si, drive1_params
    clc
    ret

.drive0:
    mov     si, drive0_params
    clc
    ret

.invalid:
    stc
    ret

;==============================================================================
; Helper: Get FDPT Pointer
;==============================================================================
; Returns pointer to FDPT for given drive.
;
; Input:  DL = drive number (80h or 81h)
; Output: SI = pointer to FDPT structure
;         CF = 0 if valid, CF = 1 if invalid drive
; Destroys: AX
;==============================================================================
get_fdpt_ptr:
    mov     al, dl
    sub     al, 0x80

    cmp     al, [num_drives]
    jae     .invalid

    test    al, al
    jz      .drive0
    mov     si, fdpt_drive1
    clc
    ret

.drive0:
    mov     si, fdpt_drive0
    clc
    ret

.invalid:
    stc
    ret

;==============================================================================
; Helper: Select Drive on WD Controller
;==============================================================================
; Sets up SDH register to select the appropriate drive.
;
; Input:  DL = drive number (80h or 81h)
;         DH = head number
; Output: SDH register written
; Destroys: AX, DX
;==============================================================================
select_drive:
    push    dx

    ; Calculate SDH value
    mov     al, dh                  ; Head in low 4 bits
    and     al, 0x0F
    or      al, SDH_SIZE_512        ; 512-byte sectors

    ; Set drive select bit if drive 1
    cmp     dl, 0x81
    jne     .write_sdh
    or      al, SDH_DRV1

.write_sdh:
    mov     dx, [current_base]
    add     dx, WD_SDH
    out     dx, al

    pop     dx
    ret

;==============================================================================
; Helper: Wait for Drive Ready
;==============================================================================
; Waits for drive to become ready (BSY clear, DRDY set).
;
; Output: CF = 0 if ready, CF = 1 if timeout
;         AL = status register value
; Destroys: AX, CX, DX
;==============================================================================
wait_drive_ready:
    mov     dx, [current_base]
    add     dx, WD_STATUS
    mov     cx, TIMEOUT_DRDY

.wait_loop:
    in      al, dx
    test    al, STS_BSY             ; Busy?
    jnz     .continue
    test    al, STS_DRDY            ; Ready?
    jnz     .ready

.continue:
    loop    .wait_loop

    ; Timeout
    stc
    ret

.ready:
    clc
    ret

;==============================================================================
; Helper: Store Last Status
;==============================================================================
; Stores status in BDA for subsequent GET_STATUS calls.
;
; Input: AH = status code
; Destroys: Nothing (preserves all registers)
;==============================================================================
store_status:
    push    es
    push    bx
    push    ax

    mov     bx, BDA_SEG
    mov     es, bx
    mov     [es:BDA_HDD_STATUS], ah

    pop     ax
    pop     bx
    pop     es
    ret
