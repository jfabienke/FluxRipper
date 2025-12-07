/*-----------------------------------------------------------------------*/
/* FluxRipper - FatFs Disk I/O Header                                    */
/*                                                                       */
/* Low level disk interface module include file                          */
/* Based on FatFs R0.15 by ChaN                                          */
/*                                                                       */
/* Updated: 2025-12-03 19:00                                             */
/*-----------------------------------------------------------------------*/

#ifndef DISKIO_DEFINED
#define DISKIO_DEFINED

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/*-----------------------------------------------------------------------*/
/* Type definitions                                                       */
/*-----------------------------------------------------------------------*/

/* Status of Disk Functions */
typedef uint8_t DSTATUS;

/* Results of Disk Functions */
typedef enum {
    RES_OK = 0,     /* 0: Successful */
    RES_ERROR,      /* 1: R/W Error */
    RES_WRPRT,      /* 2: Write Protected */
    RES_NOTRDY,     /* 3: Not Ready */
    RES_PARERR      /* 4: Invalid Parameter */
} DRESULT;

/*-----------------------------------------------------------------------*/
/* Disk Status Bits                                                       */
/*-----------------------------------------------------------------------*/

#define STA_NOINIT      0x01    /* Drive not initialized */
#define STA_NODISK      0x02    /* No medium in the drive */
#define STA_PROTECT     0x04    /* Write protected */

/*-----------------------------------------------------------------------*/
/* Command codes for disk_ioctl function                                  */
/*-----------------------------------------------------------------------*/

/* Generic commands (used by FatFs) */
#define CTRL_SYNC           0   /* Complete pending write process */
#define GET_SECTOR_COUNT    1   /* Get media size */
#define GET_SECTOR_SIZE     2   /* Get sector size */
#define GET_BLOCK_SIZE      3   /* Get erase block size */
#define CTRL_TRIM           4   /* Inform device data not needed */

/* FluxRipper-specific commands */
#define CTRL_POWER          5   /* Motor power control */
#define CTRL_LOCK           6   /* Lock/unlock drive */
#define CTRL_EJECT          7   /* Eject disk (for motorized eject) */
#define GET_GEOMETRY        10  /* Get CHS geometry */
#define GET_DISK_TYPE       11  /* Get disk type (DD/HD/ED) */

/*-----------------------------------------------------------------------*/
/* Prototypes for disk I/O functions                                      */
/*-----------------------------------------------------------------------*/

DSTATUS disk_initialize(uint8_t pdrv);
DSTATUS disk_status(uint8_t pdrv);
DRESULT disk_read(uint8_t pdrv, uint8_t* buff, uint32_t sector, unsigned int count);
DRESULT disk_write(uint8_t pdrv, const uint8_t* buff, uint32_t sector, unsigned int count);
DRESULT disk_ioctl(uint8_t pdrv, uint8_t cmd, void* buff);

/* Real time clock function (optional) */
uint32_t get_fattime(void);

#ifdef __cplusplus
}
#endif

#endif /* DISKIO_DEFINED */
