;==============================================================================
; FluxRipper FDD BIOS - ROM Entry Point
;==============================================================================
; This is the main entry file for the FDD BIOS Option ROM. It contains:
;   - ROM signature (55 AA)
;   - PnP header (16KB build only)
;   - Initialization entry point
;   - INT 13h hook
;
; The ROM is designed to be detected by the system BIOS during POST and
; called for initialization. It then hooks INT 13h to provide floppy disk
; services with FPGA auto-detection.
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
%include "fdc_regs.inc"
%include "profile.inc"
%include "int13h.inc"

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
    db      1                       ; Device type: Mass Storage
    db      2                       ; Device sub-type: Floppy
    db      0                       ; Device interface
    dw      0                       ; Device indicators
    dw      0                       ; Boot connection vector (0 = use INT)
    dw      0                       ; Disconnect vector
    dw      pnp_bev                 ; Bootstrap Entry Vector
    dw      0                       ; Reserved
    dw      0                       ; Static resource info (0 = none)

; PnP Device ID: FLX0200 (FluxRipper FDD Controller)
; Format: EISA compressed vendor ID (3 chars) + 4-digit hex product
PNP_DEVICE_ID   equ     0x464C5802  ; 'FLX' + 0x0200

pnp_mfg_string:
    db      "FluxRipper Project", 0

pnp_prod_string:
    db      "FluxRipper FDD BIOS", 0

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
;   1. Check for FluxRipper FPGA (not a generic FDC)
;   2. Wait for FPGA discovery to complete
;   3. Read detected drive profiles
;   4. Configure drive parameters
;   5. Hook INT 13h
;   6. Display banner
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

    ; Read detected drive profiles from FPGA
    call    read_profiles
    jc      .init_error             ; CF=1: No drives detected

    ; Map profiles to drive type codes
    call    map_drive_types

    ; Setup default DOS drive letter mapping
    call    setup_default_mapping

    ; Hook INT 13h
    call    hook_int13h

    ; Update BIOS data area
    call    update_bda

    ; Update equipment word with floppy count
    call    update_bda_equipment

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
; Check if this is a FluxRipper FPGA by reading a signature from the
; discovery register area.
; Returns: CF=0 if FluxRipper detected, CF=1 if not
;==============================================================================
detect_fluxripper:
    push    ax
    push    dx

    ; Read FPGA signature from discovery register base
    ; FluxRipper uses extended registers at FDC_BASE + 0x68
    mov     dx, FDC_PRIMARY + DISC_PROFILE_A
    in      al, dx

    ; Check for FluxRipper signature (non-zero profile with valid bit)
    ; If profile has PROFILE_VALID set, this is FluxRipper
    test    al, al
    jz      .check_magic

    ; Read next byte to check valid flag
    inc     dx
    in      al, dx
    test    al, 0x80                ; Check PROFILE_VALID (bit 15 = byte 1 bit 7)
    jnz     .found

.check_magic:
    ; Alternative: check for magic signature at base
    mov     dx, FDC_PRIMARY + DISC_PROFILE_A
    in      al, dx
    cmp     al, 0xFB                ; 'FB' for FluxRipper Base
    je      .found
    cmp     al, 0xFD                ; 'FD' for FluxRipper Discovery
    je      .found

    ; Not FluxRipper - could be real FDC
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
%include "detect.asm"
%include "init.asm"
%include "fdc_io.asm"
%include "int13h.asm"
%include "read_write.asm"
%include "format.asm"
%include "strings.asm"

%if BUILD_16KB && ENABLE_DIAG
%include "diag.asm"
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
; Drive Profile Storage (4 drives max)
;------------------------------------------------------------------------------
; These are populated from FPGA discovery registers
; Each profile is 4 bytes (32-bit DRIVE_PROFILE register)

drive_profiles:
    .drive0     dd  0               ; Drive 0 profile
    .drive1     dd  0               ; Drive 1 profile
    .drive2     dd  0               ; Drive 2 profile (secondary FDC)
    .drive3     dd  0               ; Drive 3 profile (secondary FDC)

;------------------------------------------------------------------------------
; Detected Drive Types (BIOS type codes)
;------------------------------------------------------------------------------
drive_types:
    .drive0     db  DTYPE_NONE      ; Drive 0 type code
    .drive1     db  DTYPE_NONE      ; Drive 1 type code
    .drive2     db  DTYPE_NONE      ; Drive 2 type code
    .drive3     db  DTYPE_NONE      ; Drive 3 type code

;------------------------------------------------------------------------------
; Drive Parameters (per drive)
;------------------------------------------------------------------------------
; Cylinders, heads, sectors for each detected drive

drive_params:
    .d0_cyls    dw  0               ; Drive 0 cylinders
    .d0_heads   db  0               ; Drive 0 heads
    .d0_spt     db  0               ; Drive 0 sectors per track
    .d1_cyls    dw  0
    .d1_heads   db  0
    .d1_spt     db  0
    .d2_cyls    dw  0
    .d2_heads   db  0
    .d2_spt     db  0
    .d3_cyls    dw  0
    .d3_heads   db  0
    .d3_spt     db  0

;------------------------------------------------------------------------------
; Controller State
;------------------------------------------------------------------------------
num_drives:
    db      0                       ; Number of detected drives (0-4)

current_fdc:
    dw      FDC_PRIMARY             ; Current FDC I/O base address

motor_status:
    db      0                       ; Motor on/off status bits

secondary_fdc_present:
    db      0                       ; Secondary FDC (0x370) present flag

;------------------------------------------------------------------------------
; Drive Letter Mapping Tables
;------------------------------------------------------------------------------
; Logical (BIOS) to physical drive mapping
; Index = BIOS drive number (0=A:, 1=B:, 2, 3)
; Value = physical drive (0-3), or 0xFF = not mapped
drive_map:
    db      0                       ; A: → Physical 0 (default)
    db      1                       ; B: → Physical 1 (default)
    db      2                       ; C: → Physical 2 (default)
    db      3                       ; D: → Physical 3 (default)

; Reverse mapping: physical to logical drive letter
; Index = physical drive (0-3)
; Value = logical drive (0=A:, 1=B:, etc), or 0xFF = not mapped
phys_to_logical:
    db      0                       ; Physical 0 → A: (default)
    db      1                       ; Physical 1 → B: (default)
    db      2                       ; Physical 2 → C: (default)
    db      3                       ; Physical 3 → D: (default)

; Number of mapped (visible to DOS) drives
mapped_drive_count:
    db      0

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
