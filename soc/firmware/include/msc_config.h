/*-----------------------------------------------------------------------------
 * msc_config.h
 * MSC Configuration Register Interface
 *
 * Created: 2025-12-05 22:00
 *
 * Provides functions to configure USB Mass Storage geometry and status
 * via AXI-accessible registers. Firmware writes geometry after profile
 * detection; RTL uses values for SCSI READ_CAPACITY responses.
 *---------------------------------------------------------------------------*/

#ifndef MSC_CONFIG_H
#define MSC_CONFIG_H

#include <stdint.h>
#include <stdbool.h>

/*---------------------------------------------------------------------------
 * Register Base Address
 *---------------------------------------------------------------------------*/

#define MSC_CONFIG_BASE     0x40050000

/*---------------------------------------------------------------------------
 * Register Offsets
 *---------------------------------------------------------------------------*/

#define MSC_REG_CTRL            0x00    /* Control register */
#define MSC_REG_STATUS          0x04    /* Status register (read-only) */
#define MSC_REG_INT_CTRL        0x08    /* Interrupt control register */
#define MSC_REG_FDD0_GEOMETRY   0x10    /* FDD 0 geometry */
#define MSC_REG_FDD1_GEOMETRY   0x14    /* FDD 1 geometry */
#define MSC_REG_HDD0_CAP_LO     0x20    /* HDD 0 capacity (low 32 bits) */
#define MSC_REG_HDD0_CAP_HI     0x24    /* HDD 0 capacity (high 32 bits) */
#define MSC_REG_HDD1_CAP_LO     0x28    /* HDD 1 capacity (low 32 bits) */
#define MSC_REG_HDD1_CAP_HI     0x2C    /* HDD 1 capacity (high 32 bits) */
#define MSC_REG_DRIVE_STATUS    0x30    /* Drive ready/changed/wp status */

/*---------------------------------------------------------------------------
 * Control Register (0x00) Bits
 *---------------------------------------------------------------------------*/

#define MSC_CTRL_CONFIG_VALID   (1 << 0)    /* Configuration is valid */
#define MSC_CTRL_FORCE_UPDATE   (1 << 1)    /* Force geometry update */

/*---------------------------------------------------------------------------
 * Interrupt Control Register (0x08) Bits
 *---------------------------------------------------------------------------*/

#define MSC_INT_FDD0_ENABLE     (1 << 0)    /* FDD 0 interrupt enable */
#define MSC_INT_FDD1_ENABLE     (1 << 1)    /* FDD 1 interrupt enable */
#define MSC_INT_HDD0_ENABLE     (1 << 2)    /* HDD 0 interrupt enable */
#define MSC_INT_HDD1_ENABLE     (1 << 3)    /* HDD 1 interrupt enable */
#define MSC_INT_FDD0_PENDING    (1 << 4)    /* FDD 0 interrupt pending (W1C) */
#define MSC_INT_FDD1_PENDING    (1 << 5)    /* FDD 1 interrupt pending (W1C) */
#define MSC_INT_HDD0_PENDING    (1 << 6)    /* HDD 0 interrupt pending (W1C) */
#define MSC_INT_HDD1_PENDING    (1 << 7)    /* HDD 1 interrupt pending (W1C) */
#define MSC_INT_GLOBAL_ENABLE   (1 << 8)    /* Global interrupt enable */

#define MSC_INT_ENABLE_MASK     (0x0F)      /* Per-drive enable mask */
#define MSC_INT_PENDING_MASK    (0xF0)      /* Per-drive pending mask */

/*---------------------------------------------------------------------------
 * Status Register (0x04) Bits
 *---------------------------------------------------------------------------*/

#define MSC_STATUS_FDD0_PRESENT (1 << 0)    /* FDD 0 media present */
#define MSC_STATUS_FDD1_PRESENT (1 << 1)    /* FDD 1 media present */
#define MSC_STATUS_HDD0_PRESENT (1 << 2)    /* HDD 0 ready */
#define MSC_STATUS_HDD1_PRESENT (1 << 3)    /* HDD 1 ready */
#define MSC_STATUS_FDD0_CHANGED (1 << 4)    /* FDD 0 media changed */
#define MSC_STATUS_FDD1_CHANGED (1 << 5)    /* FDD 1 media changed */
#define MSC_STATUS_HDD0_CHANGED (1 << 6)    /* HDD 0 changed */
#define MSC_STATUS_HDD1_CHANGED (1 << 7)    /* HDD 1 changed */

/*---------------------------------------------------------------------------
 * FDD Geometry Register (0x10, 0x14) Bits
 *---------------------------------------------------------------------------*/

#define MSC_FDD_SECTORS_MASK    0x0000FFFF  /* [15:0] Total sectors */
#define MSC_FDD_TRACKS_MASK     0x00FF0000  /* [23:16] Number of tracks */
#define MSC_FDD_TRACKS_SHIFT    16
#define MSC_FDD_HEADS_MASK      0x0F000000  /* [27:24] Number of heads */
#define MSC_FDD_HEADS_SHIFT     24
#define MSC_FDD_SPT_MASK        0xF0000000  /* [31:28] Sectors per track */
#define MSC_FDD_SPT_SHIFT       28

/*---------------------------------------------------------------------------
 * Drive Status Register (0x30) Bits
 *---------------------------------------------------------------------------*/

#define MSC_DRV_FDD0_READY      (1 << 0)    /* FDD 0 ready */
#define MSC_DRV_FDD1_READY      (1 << 1)    /* FDD 1 ready */
#define MSC_DRV_HDD0_READY      (1 << 2)    /* HDD 0 ready */
#define MSC_DRV_HDD1_READY      (1 << 3)    /* HDD 1 ready */
#define MSC_DRV_FDD0_CHANGED    (1 << 4)    /* FDD 0 changed (write 1 to clear) */
#define MSC_DRV_FDD1_CHANGED    (1 << 5)    /* FDD 1 changed (write 1 to clear) */
#define MSC_DRV_HDD0_CHANGED    (1 << 6)    /* HDD 0 changed (write 1 to clear) */
#define MSC_DRV_HDD1_CHANGED    (1 << 7)    /* HDD 1 changed (write 1 to clear) */
#define MSC_DRV_FDD0_WP         (1 << 8)    /* FDD 0 write protected */
#define MSC_DRV_FDD1_WP         (1 << 9)    /* FDD 1 write protected */
#define MSC_DRV_HDD0_WP         (1 << 10)   /* HDD 0 write protected */
#define MSC_DRV_HDD1_WP         (1 << 11)   /* HDD 1 write protected */

/*---------------------------------------------------------------------------
 * Drive Types
 *---------------------------------------------------------------------------*/

typedef enum {
    MSC_DRIVE_FDD0 = 0,
    MSC_DRIVE_FDD1 = 1,
    MSC_DRIVE_HDD0 = 2,
    MSC_DRIVE_HDD1 = 3
} msc_drive_t;

/*---------------------------------------------------------------------------
 * FDD Geometry Structure
 *---------------------------------------------------------------------------*/

typedef struct {
    uint16_t sectors;       /* Total sectors */
    uint8_t  tracks;        /* Number of tracks (40, 77, 80) */
    uint8_t  heads;         /* Number of heads (1 or 2) */
    uint8_t  spt;           /* Sectors per track (9, 18, 36) */
} msc_fdd_geometry_t;

/*---------------------------------------------------------------------------
 * Function Prototypes
 *---------------------------------------------------------------------------*/

/**
 * Initialize MSC configuration registers
 * Clears config_valid and sets default geometry
 */
void msc_config_init(void);

/**
 * Set FDD geometry
 * @param drive Drive index (MSC_DRIVE_FDD0 or MSC_DRIVE_FDD1)
 * @param geom Geometry structure
 */
void msc_config_set_fdd_geometry(msc_drive_t drive, const msc_fdd_geometry_t *geom);

/**
 * Set FDD geometry from individual parameters
 * @param drive Drive index
 * @param sectors Total sectors
 * @param tracks Number of tracks
 * @param heads Number of heads
 * @param spt Sectors per track
 */
void msc_config_set_fdd_params(msc_drive_t drive, uint16_t sectors,
                               uint8_t tracks, uint8_t heads, uint8_t spt);

/**
 * Set HDD capacity
 * @param drive Drive index (MSC_DRIVE_HDD0 or MSC_DRIVE_HDD1)
 * @param sectors Total sectors (64-bit)
 */
void msc_config_set_hdd_capacity(msc_drive_t drive, uint64_t sectors);

/**
 * Set drive ready state
 * @param drive Drive index
 * @param ready true if drive is ready
 */
void msc_config_set_ready(msc_drive_t drive, bool ready);

/**
 * Set drive write-protect state
 * @param drive Drive index
 * @param wp true if write protected
 */
void msc_config_set_write_protect(msc_drive_t drive, bool wp);

/**
 * Mark configuration as valid
 * Call after setting all geometry values
 */
void msc_config_validate(void);

/**
 * Mark configuration as invalid
 * RTL will use default values
 */
void msc_config_invalidate(void);

/**
 * Check if media changed flag is set
 * @param drive Drive index
 * @return true if media changed
 */
bool msc_config_media_changed(msc_drive_t drive);

/**
 * Clear media changed flag
 * @param drive Drive index
 */
void msc_config_clear_media_changed(msc_drive_t drive);

/**
 * Get drive presence status
 * @param drive Drive index
 * @return true if drive/media present
 */
bool msc_config_drive_present(msc_drive_t drive);

/**
 * Read control register
 * @return Control register value
 */
uint32_t msc_config_read_ctrl(void);

/**
 * Read status register
 * @return Status register value
 */
uint32_t msc_config_read_status(void);

/*---------------------------------------------------------------------------
 * Interrupt Control Functions
 *---------------------------------------------------------------------------*/

/**
 * Enable media change interrupts globally
 * @param enable true to enable global interrupts
 */
void msc_config_int_global_enable(bool enable);

/**
 * Enable media change interrupt for a specific drive
 * @param drive Drive index
 * @param enable true to enable interrupt for this drive
 */
void msc_config_int_enable(msc_drive_t drive, bool enable);

/**
 * Check if interrupt is pending for a drive
 * @param drive Drive index
 * @return true if interrupt pending
 */
bool msc_config_int_pending(msc_drive_t drive);

/**
 * Clear interrupt pending flag for a drive
 * @param drive Drive index
 */
void msc_config_int_clear(msc_drive_t drive);

/**
 * Read interrupt control register
 * @return INT_CTRL register value
 */
uint32_t msc_config_read_int_ctrl(void);

/**
 * Media change interrupt handler
 * Call from ISR when media change interrupt occurs.
 * Checks which drives have pending changes and updates MSC HAL state.
 */
void msc_config_irq_handler(void);

#endif /* MSC_CONFIG_H */
