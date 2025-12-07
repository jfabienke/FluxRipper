/*-----------------------------------------------------------------------------
 * msc_hal.h
 * USB Mass Storage Class - Hardware Abstraction Layer
 *
 * Created: 2025-12-05 15:45
 *
 * Provides the interface between USB MSC SCSI commands and the underlying
 * FluxRipper drive HAL (FDD and HDD).
 *---------------------------------------------------------------------------*/

#ifndef MSC_HAL_H
#define MSC_HAL_H

#include <stdint.h>
#include <stdbool.h>

/*---------------------------------------------------------------------------
 * Constants
 *---------------------------------------------------------------------------*/

#define MSC_MAX_LUNS        4       /* Maximum logical units */
#define MSC_MAX_FDDS        2       /* FDD LUNs (0-1) */
#define MSC_MAX_HDDS        2       /* HDD LUNs (2-3) */

#define MSC_SECTOR_SIZE     512     /* Default sector size */

/* LUN Types */
#define MSC_LUN_TYPE_NONE   0
#define MSC_LUN_TYPE_FDD    1
#define MSC_LUN_TYPE_HDD    2

/* Error codes */
#define MSC_OK              0
#define MSC_ERR_NO_MEDIA    1
#define MSC_ERR_NOT_READY   2
#define MSC_ERR_WRITE_PROT  3
#define MSC_ERR_LBA_RANGE   4
#define MSC_ERR_READ        5
#define MSC_ERR_WRITE       6
#define MSC_ERR_INVALID_LUN 7

/*---------------------------------------------------------------------------
 * Data Structures
 *---------------------------------------------------------------------------*/

/**
 * LUN Configuration
 */
typedef struct {
    uint8_t     lun_type;       /* MSC_LUN_TYPE_xxx */
    uint8_t     drive_index;    /* Physical drive index within type */
    bool        present;        /* Media present */
    bool        removable;      /* Removable media flag */
    bool        readonly;       /* Write-protected */
    bool        changed;        /* Media changed since last check */
    uint32_t    capacity;       /* Total sectors */
    uint16_t    block_size;     /* Bytes per sector */
    char        vendor[9];      /* Vendor string (8 chars + null) */
    char        product[17];    /* Product string (16 chars + null) */
    char        revision[5];    /* Revision string (4 chars + null) */
} msc_lun_config_t;

/**
 * MSC HAL State
 */
typedef struct {
    bool        initialized;
    uint8_t     lun_count;
    msc_lun_config_t luns[MSC_MAX_LUNS];
} msc_hal_state_t;

/*---------------------------------------------------------------------------
 * Initialization
 *---------------------------------------------------------------------------*/

/**
 * Initialize MSC HAL
 * Detects connected drives and configures LUNs
 * @return MSC_OK on success
 */
int msc_hal_init(void);

/**
 * Get number of configured LUNs
 * @return LUN count (0-4)
 */
int msc_hal_get_lun_count(void);

/**
 * Get LUN configuration
 * @param lun LUN number (0-3)
 * @param config Pointer to config structure to fill
 * @return MSC_OK on success, MSC_ERR_INVALID_LUN if LUN doesn't exist
 */
int msc_hal_get_lun_config(uint8_t lun, msc_lun_config_t *config);

/*---------------------------------------------------------------------------
 * Drive Operations
 *---------------------------------------------------------------------------*/

/**
 * Check if LUN is ready
 * @param lun LUN number
 * @return true if ready, false otherwise
 */
bool msc_hal_is_ready(uint8_t lun);

/**
 * Check if LUN is write-protected
 * @param lun LUN number
 * @return true if write-protected
 */
bool msc_hal_is_write_protected(uint8_t lun);

/**
 * Check if media has changed
 * @param lun LUN number
 * @return true if media changed since last check (clears flag)
 */
bool msc_hal_media_changed(uint8_t lun);

/**
 * Notify that media has changed (called from interrupt handler)
 * Sets the changed flag and re-scans drive geometry
 * @param lun LUN index (0-3)
 */
void msc_hal_notify_media_changed(uint8_t lun);

/**
 * Read sectors from LUN
 * @param lun LUN number
 * @param lba Starting logical block address
 * @param buf Buffer to receive data
 * @param count Number of sectors to read
 * @return MSC_OK on success, error code otherwise
 */
int msc_hal_read_sectors(uint8_t lun, uint32_t lba, void *buf, uint32_t count);

/**
 * Write sectors to LUN
 * @param lun LUN number
 * @param lba Starting logical block address
 * @param buf Buffer containing data to write
 * @param count Number of sectors to write
 * @return MSC_OK on success, error code otherwise
 */
int msc_hal_write_sectors(uint8_t lun, uint32_t lba, const void *buf, uint32_t count);

/**
 * Start/Stop unit (motor control)
 * @param lun LUN number
 * @param start true to start, false to stop
 * @param eject true to eject media (if supported)
 * @return MSC_OK on success
 */
int msc_hal_start_stop(uint8_t lun, bool start, bool eject);

/**
 * Prevent/Allow medium removal
 * @param lun LUN number
 * @param prevent true to prevent removal, false to allow
 * @return MSC_OK on success
 */
int msc_hal_prevent_removal(uint8_t lun, bool prevent);

/*---------------------------------------------------------------------------
 * Geometry and Capacity
 *---------------------------------------------------------------------------*/

/**
 * Get LUN capacity
 * @param lun LUN number
 * @param last_lba Pointer to receive last valid LBA
 * @param block_size Pointer to receive block size
 * @return MSC_OK on success
 */
int msc_hal_get_capacity(uint8_t lun, uint32_t *last_lba, uint16_t *block_size);

/**
 * Refresh LUN configuration (re-detect media)
 * @param lun LUN number
 * @return MSC_OK on success
 */
int msc_hal_refresh_lun(uint8_t lun);

/*---------------------------------------------------------------------------
 * Status and Diagnostics
 *---------------------------------------------------------------------------*/

/**
 * Get last error for LUN
 * @param lun LUN number
 * @return Last error code
 */
int msc_hal_get_last_error(uint8_t lun);

/**
 * Get HAL statistics
 * @param lun LUN number
 * @param read_count Pointer to receive read sector count
 * @param write_count Pointer to receive write sector count
 * @param error_count Pointer to receive error count
 */
void msc_hal_get_stats(uint8_t lun, uint32_t *read_count,
                       uint32_t *write_count, uint32_t *error_count);

#endif /* MSC_HAL_H */
