/*---------------------------------------------------------------------------/
/  FluxRipper - FatFs Configuration
/  Based on FatFs R0.15 by ChaN
/
/  Configuration for embedded floppy disk operations
/
/  Updated: 2025-12-03 19:00
/---------------------------------------------------------------------------*/

#ifndef FFCONF_DEF
#define FFCONF_DEF  80286   /* Revision ID */

/*---------------------------------------------------------------------------/
/ Function Configurations
/---------------------------------------------------------------------------*/

#define FF_FS_READONLY  0
/* 0: Read/Write, 1: Read only */

#define FF_FS_MINIMIZE  0
/* 0: Full function, 1-3: Remove features to reduce code size */

#define FF_USE_FIND     1
/* 0: Disable f_findfirst/f_findnext */

#define FF_USE_MKFS     1
/* 0: Disable f_mkfs() */

#define FF_USE_FASTSEEK 0
/* 0: Disable fast seek (saves RAM) */

#define FF_USE_EXPAND   0
/* 0: Disable f_expand() */

#define FF_USE_CHMOD    0
/* 0: Disable f_chmod/f_utime (not needed for floppy) */

#define FF_USE_LABEL    1
/* 0: Disable volume label functions */

#define FF_USE_FORWARD  0
/* 0: Disable f_forward() */

#define FF_USE_STRFUNC  1
/* 0: Disable string functions (f_gets, f_putc, f_puts, f_printf) */

#define FF_PRINT_LLI    0
/* 0: Disable long long in f_printf */

#define FF_PRINT_FLOAT  0
/* 0: Disable floating point in f_printf */

#define FF_STRF_ENCODE  0
/* 0: ANSI/OEM in string functions */

/*---------------------------------------------------------------------------/
/ Locale and Namespace Configurations
/---------------------------------------------------------------------------*/

#define FF_CODE_PAGE    437
/* OEM code page (437 = US, 850 = Latin 1) */

#define FF_USE_LFN      0
/* 0: Disable Long File Names (saves ~3KB code + RAM)
   1: Enable LFN with static buffer
   2: Enable LFN with dynamic buffer on stack
   3: Enable LFN with dynamic buffer on heap */

#define FF_MAX_LFN      255
/* Maximum LFN length (12-255) - only used if FF_USE_LFN > 0 */

#define FF_LFN_UNICODE  0
/* 0: ANSI/OEM, 1: UTF-16, 2: UTF-8, 3: UTF-32 */

#define FF_LFN_BUF      255
#define FF_SFN_BUF      12
/* Buffer sizes for LFN/SFN */

#define FF_FS_RPATH     0
/* 0: Disable relative path (simpler API) */

/*---------------------------------------------------------------------------/
/ Drive/Volume Configurations
/---------------------------------------------------------------------------*/

#define FF_VOLUMES      4
/* Number of volumes (drives) to support (1-10)
   FluxRipper has 4 drives max (2 per interface) */

#define FF_STR_VOLUME_ID    0
/* 0: Use numbers for volume ID (0:, 1:, etc.)
   1: Use strings */

#define FF_VOLUME_STRS      "A","B","C","D"
/* Volume ID strings when FF_STR_VOLUME_ID == 1 */

#define FF_MULTI_PARTITION  0
/* 0: Single partition per drive (floppy standard)
   1: Support multiple partitions */

#define FF_MIN_SS       512
#define FF_MAX_SS       512
/* Sector size range. Floppies are always 512 bytes. */

#define FF_LBA64        0
/* 0: 32-bit LBA (sufficient for floppy - max 2TB) */

#define FF_MIN_GPT      0x10000000
/* Minimum sectors to use GPT. Set high to never use GPT on floppy. */

#define FF_USE_TRIM     0
/* 0: Disable TRIM (not applicable to floppy) */

/*---------------------------------------------------------------------------/
/ System Configurations
/---------------------------------------------------------------------------*/

#define FF_FS_TINY      1
/* 0: Normal (uses per-file buffer)
   1: Tiny (shares buffer across files - saves RAM) */

#define FF_FS_EXFAT     0
/* 0: Disable exFAT (not needed for floppy, saves ~8KB code) */

#define FF_FS_NORTC     1
/* 0: Use RTC for timestamps
   1: Fixed timestamp (no RTC hardware) */

#define FF_NORTC_MON    12
#define FF_NORTC_MDAY   3
#define FF_NORTC_YEAR   2025
/* Fixed timestamp when FF_FS_NORTC == 1 */

#define FF_FS_NOFSINFO  0
/* 0: Use FSINFO if available */

#define FF_FS_LOCK      0
/* 0: Disable file lock (single-threaded)
   n: Enable lock for n files (needs OS support) */

#define FF_FS_REENTRANT 0
/* 0: Disable reentrancy (bare-metal, single-threaded)
   1: Enable reentrancy (needs ff_mutex_* functions) */

#define FF_FS_TIMEOUT   1000
/* Timeout for reentrancy */


/*---------------------------------------------------------------------------/
/ FluxRipper-Specific Optimizations
/---------------------------------------------------------------------------*/

/* These settings optimize for floppy disk operations:
 *
 * 1. FF_FS_TINY = 1: Shares a single sector buffer across all open files.
 *    Floppy operations are slow enough that this doesn't hurt performance.
 *
 * 2. FF_USE_LFN = 0: DOS floppies don't use long filenames. Saves 3-4KB.
 *
 * 3. FF_FS_EXFAT = 0: Floppies use FAT12/FAT16 only. Saves 8KB.
 *
 * 4. FF_MAX_SS = 512: Floppy sectors are always 512 bytes.
 *
 * 5. FF_VOLUMES = 4: Matches FluxRipper's 4 physical drives.
 *
 * Estimated footprint:
 *   Code: ~12KB
 *   RAM:  ~1KB (+ FF_MAX_SS per volume for tiny mode)
 */

#endif /* FFCONF_DEF */
