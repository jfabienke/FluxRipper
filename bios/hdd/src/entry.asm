;==============================================================================
; FluxRipper HDD BIOS - ROM Entry Point
;==============================================================================
; This is the main entry file for the HDD BIOS Option ROM. It contains:
;   - ROM signature (55 AA)
;   - PnP header (16KB build only)
;   - Initialization entry point
;   - Jump table for internal functions
;
; The ROM is designed to be detected by the system BIOS during POST and
; called for initialization. It then hooks INT 13h to provide hard disk
; services.
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

[BITS 16]
[ORG 0]

;------------------------------------------------------------------------------
; Include Configuration
;------------------------------------------------------------------------------
%include "config.inc"
%include "bda.inc"
%include "wd_regs.inc"

;==============================================================================
; ROM Header (Required by BIOS)
;==============================================================================
; The first three bytes must be:
;   55 AA nn
; Where nn is the ROM size in 512-byte blocks.

rom_header:
    db      0x55, 0xAA              ; ROM signature
    db      ROM_BLOCKS              ; Size in 512-byte blocks

    ; Entry point - BIOS will FAR CALL here with CS:0003
    jmp     near rom_init

;------------------------------------------------------------------------------
; Reserved area / PnP Header location
;------------------------------------------------------------------------------
%if ENABLE_PNP
    ; Align to 16-byte boundary for PnP header
    times (0x1A - ($ - $$)) db 0

;==============================================================================
; PnP Header (16KB Build Only)
;==============================================================================
; ISA Plug and Play expansion header per PnP BIOS Specification 1.0a
pnp_header:
    db      '$PnP'                  ; Signature
    db      0x01                    ; Structure revision (1.0)
    db      0x02                    ; Header length (32 bytes / 16 = 2)
    dw      0                       ; Offset to next header (0 = none)
    db      0                       ; Reserved
    db      0                       ; Checksum (calculated later)
    dd      PNP_DEVICE_ID           ; Device identifier
    dw      pnp_mfg_string          ; Manufacturer string offset
    dw      pnp_prod_string         ; Product name string offset
    db      3                       ; Device type: Mass Storage
    db      0                       ; Device sub-type: Generic
    db      0                       ; Device interface
    dw      0                       ; Device indicators
    dw      0                       ; Boot connection vector (0 = use INT)
    dw      0                       ; Disconnect vector
    dw      pnp_bev                 ; Bootstrap Entry Vector
    dw      0                       ; Reserved
    dw      0                       ; Static resource info (0 = none)

; PnP Device ID: FLX0100 (FluxRipper HDD Controller)
; Format: EISA compressed vendor ID (3 chars) + 4-digit hex product
PNP_DEVICE_ID   equ     0x464C5801  ; 'FLX' + 0x0100

pnp_mfg_string:
    db      "FluxRipper Project", 0

pnp_prod_string:
    db      "FluxRipper HDD BIOS", 0

; Bootstrap Entry Vector - called for INT 19h boot
pnp_bev:
    ; This is called when BIOS wants to boot from this device
    pushf
    call    far [cs:old_int19]      ; Chain to original INT 19h
    ; If we return here, boot failed - just return
    retf
%else
    ; No PnP header - just pad
    times (0x20 - ($ - $$)) db 0
%endif

;==============================================================================
; ROM Initialization Entry Point
;==============================================================================
; Called by system BIOS during POST via FAR CALL to CS:0003.
; Must preserve all registers except AX.
;
; Our job:
;   1. Check for FluxRipper FPGA (not a generic WD card)
;   2. Wait for FPGA discovery to complete
;   3. Read detected geometry
;   4. Set up Fixed Disk Parameter Tables
;   5. Hook INT 13h
;   6. Update drive count in BDA
;   7. Display banner
;==============================================================================

rom_init:
    ; Save registers
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp
    push    ds
    push    es

    ; Set DS to ROM segment (CS should already be correct)
    push    cs
    pop     ds

    ; Check if we should initialize (detect FluxRipper FPGA)
    call    detect_fluxripper
    jc      .init_done              ; CF=1: Not FluxRipper, skip init

    ; Display initialization banner
    mov     si, msg_banner
    call    print_string

    ; Wait for FPGA drive discovery to complete
    call    wait_discovery
    jc      .init_error             ; CF=1: Discovery timeout

    ; Read detected geometry from FPGA
    call    read_geometry
    jc      .init_error             ; CF=1: No drives detected

    ; Set up Fixed Disk Parameter Tables in our ROM
    call    setup_fdpt

    ; Hook INT 13h
    call    hook_int13h

    ; Update BDA with drive count
    call    update_bda

    ; Display detected drives
    call    display_drives

    ; Success
    mov     si, msg_ready
    call    print_string
    jmp     .init_done

.init_error:
    ; Display error message
    mov     si, msg_error
    call    print_string

.init_done:
    ; Restore registers
    pop     es
    pop     ds
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx

    ; Return to BIOS (AX is not preserved per convention)
    retf

;==============================================================================
; FluxRipper Detection
;==============================================================================
; Check if this is a FluxRipper FPGA by reading a signature register.
; Returns: CF=0 if FluxRipper detected, CF=1 if not
;==============================================================================
detect_fluxripper:
    push    ax
    push    dx

    ; Read FPGA signature from discovery register base
    mov     dx, WD_BASE_PRIMARY + DISC_REG_BASE
    in      al, dx

    ; Check for FluxRipper signature (magic byte)
    cmp     al, 0xFB                ; 'FB' for FluxRipper Base
    je      .found
    cmp     al, 0xFD                ; 'FD' for FluxRipper Discovery
    je      .found

    ; Not FluxRipper - could be real WD controller
    stc
    jmp     .done

.found:
    clc

.done:
    pop     dx
    pop     ax
    ret

;==============================================================================
; Include Sub-Modules
;==============================================================================
%include "util.asm"
%include "discovery.asm"
%include "init.asm"
%include "int13h.asm"
%include "func_basic.asm"
%include "wd_io.asm"
%include "geometry.asm"
%include "boot.asm"
%include "strings.asm"

%if BUILD_16KB
%include "func_extended.asm"
%include "func_lba.asm"
%include "video.asm"
%include "keyboard.asm"
%include "instr.inc"
%if ENABLE_DIAG
; Diagnostics module (includes surface scan, seek test, flux histogram, etc.)
%include "diag.asm"
%include "monitor.asm"
%endif
%if ENABLE_SETUP
%include "setup.asm"
%endif
%endif

;==============================================================================
; Data Section
;==============================================================================

;------------------------------------------------------------------------------
; Saved INT 13h Vector
;------------------------------------------------------------------------------
old_int13h:
    dw      0                       ; Offset
    dw      0                       ; Segment

%if ENABLE_PNP
old_int19:
    dw      0                       ; Offset
    dw      0                       ; Segment
%endif

;------------------------------------------------------------------------------
; Drive Parameter Storage (2 drives max)
;------------------------------------------------------------------------------
; These are populated from FPGA discovery registers

drive0_params:
    .cylinders  dw  0               ; Detected cylinders
    .heads      db  0               ; Detected heads
    .sectors    db  0               ; Detected sectors per track
    .flags      db  0               ; Feature flags (bit 0=ESDI, bit 1=RLL)
    .reserved   db  0,0,0           ; Padding to 8 bytes

drive1_params:
    .cylinders  dw  0
    .heads      db  0
    .sectors    db  0
    .flags      db  0
    .reserved   db  0,0,0

;------------------------------------------------------------------------------
; Fixed Disk Parameter Tables (INT 41h/46h format)
;------------------------------------------------------------------------------
; These are 16-byte tables pointed to by INT 41h (drive 0) and INT 46h (drive 1)

fdpt_drive0:
    dw      0                       ; +00: Maximum cylinders
    db      0                       ; +02: Maximum heads
    dw      0                       ; +03: Reserved
    dw      0xFFFF                  ; +05: Write precomp (0xFFFF = none)
    db      0                       ; +07: Reserved
    db      0x08                    ; +08: Control byte (>8 heads flag set if needed)
    db      0                       ; +09: Standard timeout (use default)
    db      0                       ; +0A: Format timeout
    db      0                       ; +0B: Check timeout
    dw      0                       ; +0C: Landing zone (same as max cyl)
    db      0                       ; +0E: Sectors per track
    db      0                       ; +0F: Reserved

fdpt_drive1:
    dw      0
    db      0
    dw      0
    dw      0xFFFF
    db      0
    db      0x08
    db      0
    db      0
    db      0
    dw      0
    db      0
    db      0

;------------------------------------------------------------------------------
; Controller State
;------------------------------------------------------------------------------
num_drives:
    db      0                       ; Number of detected drives (0-2)

current_base:
    dw      WD_BASE_PRIMARY         ; Current WD I/O base address

personality:
    db      PERSONALITY_WD1003      ; Detected personality (WD1002/3/6/7)

;==============================================================================
; ROM Padding and Checksum
;==============================================================================
; Pad to ROM size minus 1 byte, then add checksum byte

%if BUILD_8KB
    times (8192 - 1 - ($ - $$)) db 0xFF
%else
    times (16384 - 1 - ($ - $$)) db 0xFF
%endif

; Final byte will be set by romsum.py to make total sum = 0
rom_checksum:
    db      0

;==============================================================================
; End of ROM
;==============================================================================
