;==============================================================================
; FluxRipper HDD BIOS - FPGA Instrumentation Register Definitions
;==============================================================================
; Defines the register map for accessing FPGA instrumentation data.
;
; The FPGA provides real-time diagnostic information through these registers:
;   - Performance counters
;   - Error statistics
;   - Flux analysis
;   - Health monitoring
;   - Signal quality metrics
;
; Access Method:
;   1. Write address to INSTR_ADDR_LO/HI registers
;   2. Read 32-bit data from INSTR_DATA_0..3 registers
;
; Register Base: WD_BASE + 0xC0 (e.g., 0x1F0 + 0xC0 = 0x2B0)
;
; SPDX-License-Identifier: BSD-3-Clause
; Copyright (c) 2025 FluxRipper Project
;==============================================================================

%ifndef INSTR_INC
%define INSTR_INC

;------------------------------------------------------------------------------
; Instrumentation I/O Port Offsets (from WD_BASE + 0xC0)
;------------------------------------------------------------------------------
%define INSTR_ADDR_LO       0x00    ; W: Address [7:0]
%define INSTR_ADDR_HI       0x01    ; W: Address [9:8]
%define INSTR_DATA_0        0x02    ; R: Data [7:0]
%define INSTR_DATA_1        0x03    ; R: Data [15:8]
%define INSTR_DATA_2        0x04    ; R: Data [23:16]
%define INSTR_DATA_3        0x05    ; R: Data [31:24]
%define INSTR_CTRL          0x06    ; W: Control register

;------------------------------------------------------------------------------
; Instrumentation Control Register Bits
;------------------------------------------------------------------------------
%define INSTR_CTRL_RESET    0x01    ; Reset all counters
%define INSTR_CTRL_FREEZE   0x02    ; Freeze counters (snapshot)
%define INSTR_CTRL_ENABLE   0x80    ; Enable instrumentation

;------------------------------------------------------------------------------
; Instrumentation Address Map
;------------------------------------------------------------------------------
; System Information (0x000-0x00F)
%define INSTR_MAGIC         0x000   ; Magic number (0xFB010001)
%define INSTR_VERSION       0x004   ; Instrumentation version
%define INSTR_CAPS          0x008   ; Capabilities bitmap
%define INSTR_STATUS        0x00C   ; Global status

; Timing Information (0x010-0x02F)
%define INSTR_UPTIME        0x010   ; System uptime (seconds)
%define INSTR_LAST_CMD_TIME 0x014   ; Last command duration (us)
%define INSTR_TOTAL_CMD_TIME 0x018  ; Total command time (ms)
%define INSTR_INDEX_PERIOD  0x01C   ; Index pulse period (ns)
%define INSTR_DATA_RATE     0x020   ; Measured data rate (bits/sec)
%define INSTR_RPM           0x024   ; Spindle RPM * 10

; Command Statistics (0x030-0x04F)
%define INSTR_CMD_COUNT     0x030   ; Total commands executed
%define INSTR_READ_COUNT    0x034   ; Read commands
%define INSTR_WRITE_COUNT   0x038   ; Write commands
%define INSTR_SEEK_COUNT    0x03C   ; Seek commands
%define INSTR_FORMAT_COUNT  0x040   ; Format commands

; Error Counters (0x050-0x07F)
%define INSTR_ERR_TOTAL     0x050   ; Total errors
%define INSTR_ERR_CRC       0x054   ; CRC/ECC errors
%define INSTR_ERR_SEEK      0x058   ; Seek errors
%define INSTR_ERR_TIMEOUT   0x05C   ; Timeout errors
%define INSTR_ERR_OVERRUN   0x060   ; Data overrun errors
%define INSTR_ERR_ID_NF     0x064   ; ID not found errors
%define INSTR_ERR_ADDR_MARK 0x068   ; Address mark not found
%define INSTR_ERR_WRITE_FLT 0x06C   ; Write fault errors
%define INSTR_ERR_RECOVERED 0x070   ; Recovered errors (ECC)

; Sector Statistics (0x080-0x09F)
%define INSTR_SECTORS_READ  0x080   ; Sectors read (32-bit)
%define INSTR_SECTORS_WRITE 0x084   ; Sectors written
%define INSTR_SECTORS_VERIFY 0x088  ; Sectors verified
%define INSTR_BYTES_READ_LO 0x08C   ; Bytes read [31:0]
%define INSTR_BYTES_READ_HI 0x090   ; Bytes read [63:32]
%define INSTR_BYTES_WRITE_LO 0x094  ; Bytes written [31:0]
%define INSTR_BYTES_WRITE_HI 0x098  ; Bytes written [63:32]

; Seek Statistics (0x0A0-0x0BF)
%define INSTR_SEEK_TOTAL    0x0A0   ; Total seeks
%define INSTR_SEEK_AVG_TIME 0x0A4   ; Average seek time (us)
%define INSTR_SEEK_MIN_TIME 0x0A8   ; Minimum seek time
%define INSTR_SEEK_MAX_TIME 0x0AC   ; Maximum seek time
%define INSTR_SEEK_1TRK     0x0B0   ; 1-track seeks count
%define INSTR_SEEK_SHORT    0x0B4   ; Short seeks (<16 tracks)
%define INSTR_SEEK_MEDIUM   0x0B8   ; Medium seeks (16-256)
%define INSTR_SEEK_LONG     0x0BC   ; Long seeks (>256)

; Signal Quality (0x0C0-0x0DF)
%define INSTR_SIG_AMPLITUDE 0x0C0   ; Signal amplitude (mV)
%define INSTR_SIG_SNR       0x0C4   ; Signal-to-noise ratio (dB*10)
%define INSTR_SIG_JITTER    0x0C8   ; Timing jitter (ns)
%define INSTR_SIG_ASYM      0x0CC   ; Pulse asymmetry (%)
%define INSTR_PLL_LOCK      0x0D0   ; PLL lock status
%define INSTR_PLL_FREQ_ERR  0x0D4   ; PLL frequency error (ppm)

; Flux Analysis (0x0E0-0x0FF)
%define INSTR_FLUX_DENSITY  0x0E0   ; Flux transitions/inch
%define INSTR_FLUX_PERIOD_AVG 0x0E4 ; Average flux period (ns)
%define INSTR_FLUX_PERIOD_MIN 0x0E8 ; Minimum flux period
%define INSTR_FLUX_PERIOD_MAX 0x0EC ; Maximum flux period
%define INSTR_FLUX_VARIANCE 0x0F0   ; Period variance

; Health Monitor (0x100-0x11F)
%define INSTR_HEALTH_SCORE  0x100   ; Overall health (0-100)
%define INSTR_MEDIA_SCORE   0x104   ; Media quality score
%define INSTR_HEAD_SCORE    0x108   ; Head condition score
%define INSTR_SPINDLE_SCORE 0x10C   ; Spindle health score
%define INSTR_TEMP_DRIVE    0x110   ; Drive temperature (C*10)
%define INSTR_TEMP_FPGA     0x114   ; FPGA temperature

; Flux Histogram (0x200-0x2FF) - 64 x 32-bit bins
%define INSTR_HIST_BASE     0x200   ; Histogram base address
%define INSTR_HIST_COUNT    64      ; Number of histogram bins
%define INSTR_HIST_BIN_SIZE 4       ; Bytes per bin

; Error Log (0x300-0x3FF) - 16 x 16-byte entries
%define INSTR_LOG_BASE      0x300   ; Error log base
%define INSTR_LOG_ENTRIES   16      ; Number of log entries
%define INSTR_LOG_ENTRY_SIZE 16     ; Bytes per entry

;------------------------------------------------------------------------------
; Error Log Entry Format
;------------------------------------------------------------------------------
; Offset  Size  Description
; 0x00    4     Timestamp (seconds since power-on)
; 0x04    2     Cylinder
; 0x06    1     Head
; 0x07    1     Sector
; 0x08    1     Error type
; 0x09    1     Command that failed
; 0x0A    2     Additional info
; 0x0C    4     Raw error data

%define LOG_TIMESTAMP       0
%define LOG_CYLINDER        4
%define LOG_HEAD            6
%define LOG_SECTOR          7
%define LOG_ERROR_TYPE      8
%define LOG_COMMAND         9
%define LOG_INFO            10
%define LOG_RAW_DATA        12

;------------------------------------------------------------------------------
; Histogram Bin Definitions
;------------------------------------------------------------------------------
; Each bin represents a flux period range
; Bin width = 50ns, starting at 0ns
; Bin 0:  0-49ns
; Bin 1:  50-99ns
; ...
; Bin 63: 3150-3199ns

%define HIST_BIN_WIDTH      50      ; ns per bin
%define HIST_MIN_PERIOD     0       ; ns
%define HIST_MAX_PERIOD     3200    ; ns

;------------------------------------------------------------------------------
; Macros for Instrumentation Access
;------------------------------------------------------------------------------

; Set instrumentation address
; Input: AX = 10-bit address
; Destroys: DX
%macro INSTR_SET_ADDR 0
    push    dx
    mov     dx, [current_base]
    add     dx, INSTR_REG_BASE + INSTR_ADDR_LO
    out     dx, al                  ; Low byte
    inc     dx
    mov     al, ah
    out     dx, al                  ; High byte
    pop     dx
%endmacro

; Read 32-bit instrumentation data
; Output: EAX = 32-bit value (or DX:AX if no 32-bit support)
; Destroys: DX
%macro INSTR_READ_DATA 0
    push    bx
    mov     dx, [current_base]
    add     dx, INSTR_REG_BASE + INSTR_DATA_0
    in      al, dx                  ; Byte 0
    mov     bl, al
    inc     dx
    in      al, dx                  ; Byte 1
    mov     bh, al
    inc     dx
    in      al, dx                  ; Byte 2
    mov     cl, al
    inc     dx
    in      al, dx                  ; Byte 3
    mov     ch, al
    ; Result: CX:BX = 32-bit value
    mov     ax, bx
    mov     dx, cx
    pop     bx
%endmacro

; Read instrumentation register (combined)
; Input: register address constant
; Output: DX:AX = 32-bit value
%macro INSTR_READ_REG 1
    mov     ax, %1
    INSTR_SET_ADDR
    INSTR_READ_DATA
%endmacro

%endif ; INSTR_INC
