;==============================================================================
; FluxRipper HDD BIOS - Boot Sector Loading
;==============================================================================
; Handles loading and executing the MBR boot sector.
;
; Boot Process:
;   1. Read sector 0 (MBR) from first hard disk
;   2. Verify boot signature (55 AA)
;   3. Jump to loaded code at 0000:7C00
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

;==============================================================================
; Boot Signature Constants
;==============================================================================
%define BOOT_SEG        0x0000      ; Boot sector loads at 0000:7C00
%define BOOT_OFF        0x7C00      ; Offset within segment
%define BOOT_SIG_OFF    0x1FE       ; Signature offset in sector
%define BOOT_SIG_LO     0x55        ; Signature low byte
%define BOOT_SIG_HI     0xAA        ; Signature high byte

;==============================================================================
; Load Boot Sector
;==============================================================================
; Attempts to load and verify the MBR from the first hard disk.
;
; Input:  DL = drive number to boot from
; Output: CF = 0 if boot sector loaded and valid
;         CF = 1 if failed (no valid boot sector)
;         ES:BX = 0000:7C00 (boot sector location)
; Destroys: AX, BX, CX, DX, ES
;==============================================================================
load_boot_sector:
    push    si
    push    di

    ; Set up destination at 0000:7C00
    xor     ax, ax
    mov     es, ax
    mov     bx, BOOT_OFF

    ; Set up INT 13h parameters for reading sector 0
    ; AL = 1 sector
    ; CH = cylinder 0
    ; CL = sector 1 (sectors are 1-based)
    ; DH = head 0
    ; DL = drive number (passed in)
    mov     ax, 0x0201              ; AH=02 (read), AL=01 (1 sector)
    mov     cx, 0x0001              ; CH=0 (cyl), CL=1 (sector)
    xor     dh, dh                  ; Head 0

    ; Read the sector
    int     0x13
    jc      .read_failed

    ; Verify boot signature
    mov     di, BOOT_OFF + BOOT_SIG_OFF
    cmp     byte [es:di], BOOT_SIG_LO
    jne     .bad_signature
    cmp     byte [es:di + 1], BOOT_SIG_HI
    jne     .bad_signature

    ; Success - boot sector loaded
    clc
    jmp     .done

.read_failed:
    ; Read error - AH contains error code
    stc
    jmp     .done

.bad_signature:
    ; Invalid boot signature
    stc

.done:
    pop     di
    pop     si
    ret

;==============================================================================
; Execute Boot Sector
;==============================================================================
; Transfers control to the loaded boot sector.
; This function does not return on success.
;
; Input:  DL = drive number (passed to boot code)
; Note:   Boot sector must be loaded at 0000:7C00
; Destroys: Everything (never returns)
;==============================================================================
execute_boot_sector:
    ; Set up segment registers for boot code
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, BOOT_OFF            ; Stack just below boot code

    ; DL already contains drive number

    ; Far jump to boot sector
    jmp     BOOT_SEG:BOOT_OFF

;==============================================================================
; Find Bootable Partition
;==============================================================================
; Scans the MBR partition table for a bootable (active) partition.
;
; Input:  ES:BX = MBR location (0000:7C00)
; Output: CF = 0 if found, SI = pointer to partition entry
;         CF = 1 if no bootable partition
; Destroys: AX, CX, SI
;==============================================================================
find_bootable_partition:
    ; Partition table starts at offset 1BEh in MBR
    mov     si, BOOT_OFF + 0x1BE
    mov     cx, 4                   ; 4 partition entries

.check_entry:
    ; Check boot indicator (first byte of entry)
    mov     al, [es:si]
    test    al, 0x80                ; Boot flag set?
    jnz     .found

    ; Next entry (16 bytes each)
    add     si, 16
    loop    .check_entry

    ; No bootable partition found
    stc
    ret

.found:
    clc
    ret

;==============================================================================
; Get Partition CHS
;==============================================================================
; Extracts starting CHS from partition table entry.
;
; Input:  ES:SI = partition table entry
; Output: CH = cylinder low
;         CL = sector | (cylinder high << 6)
;         DH = head
; Destroys: AX
;==============================================================================
get_partition_chs:
    ; Partition entry format:
    ;   +0: Boot indicator
    ;   +1: Starting head
    ;   +2: Starting sector/cylinder
    ;   +3: Starting cylinder high
    ;   +4: System ID
    ;   +5: Ending head
    ;   +6: Ending sector/cylinder
    ;   +7: Ending cylinder high
    ;   +8: Starting LBA (4 bytes)
    ;   +12: Sector count (4 bytes)

    mov     dh, [es:si + 1]         ; Starting head
    mov     cl, [es:si + 2]         ; Sector and cyl high bits
    mov     ch, [es:si + 3]         ; Cylinder low
    ret

;==============================================================================
; Get Partition LBA
;==============================================================================
; Extracts starting LBA from partition table entry.
;
; Input:  ES:SI = partition table entry
; Output: DX:AX = 32-bit starting LBA
; Destroys: Nothing else
;==============================================================================
get_partition_lba:
    mov     ax, [es:si + 8]         ; Low word
    mov     dx, [es:si + 10]        ; High word
    ret

;==============================================================================
; Boot with Retry
;==============================================================================
; Attempts to boot, with retry on failure.
;
; Input:  DL = drive number
; Output: Does not return on success
;         CF = 1 if all retries failed
; Destroys: AX, BX, CX, DX, ES
;==============================================================================
boot_with_retry:
    mov     cx, 3                   ; 3 attempts

.try_boot:
    push    cx
    push    dx

    ; Reset disk system
    xor     ax, ax
    int     0x13

    pop     dx
    push    dx

    ; Try to load boot sector
    call    load_boot_sector
    jc      .retry

    ; Verify signature
    xor     ax, ax
    mov     es, ax
    mov     di, BOOT_OFF + BOOT_SIG_OFF
    cmp     word [es:di], 0xAA55
    jne     .retry

    ; Success - boot
    pop     dx
    pop     cx
    call    execute_boot_sector     ; Does not return

.retry:
    pop     dx
    pop     cx
    loop    .try_boot

    ; All attempts failed
    stc
    ret
