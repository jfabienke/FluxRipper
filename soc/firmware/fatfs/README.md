# FatFs Integration for FluxRipper

**Updated: 2025-12-03 19:00**

## Overview

This directory contains the FatFs integration for FluxRipper. FatFs is a generic FAT filesystem module by ChaN.

## Files

| File | Source | Description |
|------|--------|-------------|
| `ff.c` | FatFs | Core filesystem module (download from ChaN) |
| `ff.h` | FatFs | FatFs API header (download from ChaN) |
| `ffconf.h` | FluxRipper | Configuration customized for floppy disks |
| `diskio.c` | FluxRipper | Disk I/O glue layer to HAL |
| `diskio.h` | FluxRipper | Disk I/O interface definitions |

## Installation

1. Download FatFs R0.15 from: http://elm-chan.org/fsw/ff/arc/ff15.zip

2. Extract and copy these files to this directory:
   - `source/ff.c`
   - `source/ff.h`
   - `source/ffsystem.c` (optional, for OS support)
   - `source/ffunicode.c` (optional, for Unicode support)

3. The `ffconf.h` and `diskio.c` files are already configured for FluxRipper.

## Configuration Highlights

The `ffconf.h` is optimized for floppy disk operations:

- **FF_USE_LFN = 0**: Long filenames disabled (DOS floppies use 8.3)
- **FF_FS_EXFAT = 0**: exFAT disabled (saves 8KB code)
- **FF_FS_TINY = 1**: Shared sector buffer (saves RAM)
- **FF_VOLUMES = 4**: Matches FluxRipper's 4 drives
- **FF_MAX_SS = 512**: Floppy sector size

Estimated footprint:
- Code: ~12KB
- RAM: ~1KB + 512 bytes per mounted volume

## Usage Example

```c
#include "ff.h"

FATFS fs;           /* Filesystem object */
FIL fil;            /* File object */
FRESULT res;
UINT bw;

/* Mount drive 0 */
res = f_mount(&fs, "0:", 1);
if (res != FR_OK) {
    /* Handle error */
}

/* Open file */
res = f_open(&fil, "0:/HELLO.TXT", FA_READ);
if (res == FR_OK) {
    char buf[128];
    UINT br;

    /* Read file */
    res = f_read(&fil, buf, sizeof(buf), &br);

    /* Close file */
    f_close(&fil);
}

/* Unmount */
f_mount(NULL, "0:", 0);
```

## License

FatFs is distributed under a BSD-style license. See the FatFs documentation for details.
