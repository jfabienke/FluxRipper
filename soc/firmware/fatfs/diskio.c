/*-----------------------------------------------------------------------*/
/* FluxRipper - FatFs Disk I/O Glue Layer                                */
/*                                                                       */
/* Bridges FatFs generic disk operations to FluxRipper HAL               */
/*                                                                       */
/* Updated: 2025-12-03 19:00                                             */
/*-----------------------------------------------------------------------*/

#include "ff.h"
#include "diskio.h"
#include "fluxripper_hal.h"

/*-----------------------------------------------------------------------*/
/* Get Drive Status                                                       */
/*-----------------------------------------------------------------------*/

DSTATUS disk_status(BYTE pdrv)
{
    DSTATUS stat = 0;

    /* Check drive number */
    if (pdrv >= FF_VOLUMES)
        return STA_NOINIT;

    /* Check if disk is present */
    if (!hal_disk_present(pdrv))
        return STA_NODISK;

    /* Check write protection */
    if (hal_write_protected(pdrv))
        stat |= STA_PROTECT;

    return stat;
}

/*-----------------------------------------------------------------------*/
/* Initialize Drive                                                       */
/*-----------------------------------------------------------------------*/

DSTATUS disk_initialize(BYTE pdrv)
{
    int ret;

    /* Check drive number */
    if (pdrv >= FF_VOLUMES)
        return STA_NOINIT;

    /* Turn on motor and wait for spin-up */
    ret = hal_motor_on(pdrv);
    if (ret != HAL_OK)
        return STA_NOINIT;

    /* Seek to track 0 to establish position */
    ret = hal_seek(pdrv, 0);
    if (ret != HAL_OK)
        return STA_NOINIT;

    /* Return current status */
    return disk_status(pdrv);
}

/*-----------------------------------------------------------------------*/
/* Read Sectors                                                           */
/*-----------------------------------------------------------------------*/

DRESULT disk_read(
    BYTE pdrv,      /* Physical drive number */
    BYTE *buff,     /* Data buffer */
    LBA_t sector,   /* Start sector (LBA) */
    UINT count      /* Number of sectors */
)
{
    int ret;

    /* Check drive number */
    if (pdrv >= FF_VOLUMES)
        return RES_PARERR;

    /* Check buffer */
    if (!buff)
        return RES_PARERR;

    /* Read sectors via HAL */
    ret = hal_read_sectors(pdrv, (uint32_t)sector, buff, count);

    switch (ret) {
    case HAL_OK:
        return RES_OK;
    case HAL_ERR_NO_DISK:
        return RES_NOTRDY;
    case HAL_ERR_TIMEOUT:
    case HAL_ERR_NOT_READY:
        return RES_NOTRDY;
    default:
        return RES_ERROR;
    }
}

/*-----------------------------------------------------------------------*/
/* Write Sectors                                                          */
/*-----------------------------------------------------------------------*/

#if FF_FS_READONLY == 0

DRESULT disk_write(
    BYTE pdrv,          /* Physical drive number */
    const BYTE *buff,   /* Data buffer */
    LBA_t sector,       /* Start sector (LBA) */
    UINT count          /* Number of sectors */
)
{
    int ret;

    /* Check drive number */
    if (pdrv >= FF_VOLUMES)
        return RES_PARERR;

    /* Check buffer */
    if (!buff)
        return RES_PARERR;

    /* Check write protection */
    if (hal_write_protected(pdrv))
        return RES_WRPRT;

    /* Write sectors via HAL */
    ret = hal_write_sectors(pdrv, (uint32_t)sector, buff, count);

    switch (ret) {
    case HAL_OK:
        return RES_OK;
    case HAL_ERR_NO_DISK:
        return RES_NOTRDY;
    case HAL_ERR_WRITE_PROT:
        return RES_WRPRT;
    case HAL_ERR_TIMEOUT:
    case HAL_ERR_NOT_READY:
        return RES_NOTRDY;
    default:
        return RES_ERROR;
    }
}

#endif /* FF_FS_READONLY == 0 */

/*-----------------------------------------------------------------------*/
/* Miscellaneous Functions                                                */
/*-----------------------------------------------------------------------*/

DRESULT disk_ioctl(
    BYTE pdrv,      /* Physical drive number */
    BYTE cmd,       /* Control command */
    void *buff      /* Buffer to send/receive data */
)
{
    /* Check drive number */
    if (pdrv >= FF_VOLUMES)
        return RES_PARERR;

    switch (cmd) {

    case CTRL_SYNC:
        /* Ensure all pending writes are complete */
        /* Floppy writes are synchronous, nothing to do */
        return RES_OK;

    case GET_SECTOR_COUNT:
        /* Return total sectors on disk based on drive profile */
        if (buff) {
            drive_profile_t profile;
            LBA_t sectors;

            if (hal_get_profile(pdrv, &profile) == HAL_OK && profile.valid) {
                /* Calculate sectors: tracks * 2 sides * sectors_per_track */
                uint16_t spt;  /* Sectors per track */
                switch (profile.density) {
                    case DENS_DD: spt = 9;  break;  /* 720KB: 9 sectors/track */
                    case DENS_HD: spt = 18; break;  /* 1.44MB: 18 sectors/track */
                    case DENS_ED: spt = 36; break;  /* 2.88MB: 36 sectors/track */
                    default:      spt = 18; break;  /* Default to HD */
                }
                sectors = (LBA_t)profile.tracks * 2 * spt;
            } else {
                /* Fallback to 1.44MB if profile unavailable */
                sectors = 2880;
            }

            *(LBA_t *)buff = sectors;
            return RES_OK;
        }
        return RES_PARERR;

    case GET_SECTOR_SIZE:
        /* Return sector size (always 512 for floppy) */
        if (buff) {
            *(WORD *)buff = 512;
            return RES_OK;
        }
        return RES_PARERR;

    case GET_BLOCK_SIZE:
        /* Return erase block size in sectors (not applicable to floppy) */
        if (buff) {
            *(DWORD *)buff = 1;
            return RES_OK;
        }
        return RES_PARERR;

    default:
        return RES_PARERR;
    }
}

/*-----------------------------------------------------------------------*/
/* Get FAT Time (for file timestamps)                                     */
/*-----------------------------------------------------------------------*/

#if FF_FS_NORTC == 0

DWORD get_fattime(void)
{
    /* Return packed FAT time
     * Bits 31-25: Year from 1980 (0-127)
     * Bits 24-21: Month (1-12)
     * Bits 20-16: Day (1-31)
     * Bits 15-11: Hour (0-23)
     * Bits 10-5:  Minute (0-59)
     * Bits 4-0:   Second/2 (0-29)
     */

    /* TODO: Get real time from RTC if available */
    /* For now, return fixed time: 2025-12-03 12:00:00 */
    return ((DWORD)(2025 - 1980) << 25)  /* Year 2025 */
         | ((DWORD)12 << 21)             /* December */
         | ((DWORD)3 << 16)              /* Day 3 */
         | ((DWORD)12 << 11)             /* 12:00 */
         | ((DWORD)0 << 5)               /* :00 */
         | ((DWORD)0);                   /* :00 */
}

#endif /* FF_FS_NORTC == 0 */
