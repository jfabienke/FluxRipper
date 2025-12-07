/*-----------------------------------------------------------------------------
 * msc_config.c
 * MSC Configuration Register Interface Implementation
 *
 * Created: 2025-12-05 22:05
 *
 * Implements AXI register access for USB Mass Storage configuration.
 *---------------------------------------------------------------------------*/

#include "msc_config.h"
#include <stddef.h>

/*---------------------------------------------------------------------------
 * Register Access Macros
 *---------------------------------------------------------------------------*/

#define MSC_REG(offset) \
    (*(volatile uint32_t *)(MSC_CONFIG_BASE + (offset)))

#define MSC_REG_WRITE(offset, value) \
    do { MSC_REG(offset) = (value); } while(0)

#define MSC_REG_READ(offset) \
    MSC_REG(offset)

/*---------------------------------------------------------------------------
 * Initialization
 *---------------------------------------------------------------------------*/

void msc_config_init(void)
{
    /* Clear config valid - RTL uses defaults until firmware sets geometry */
    MSC_REG_WRITE(MSC_REG_CTRL, 0);

    /* Set default FDD geometry (1.44MB: 80 tracks, 2 heads, 18 SPT, 2880 sectors) */
    uint32_t default_fdd = (18 << MSC_FDD_SPT_SHIFT) |
                           (2 << MSC_FDD_HEADS_SHIFT) |
                           (80 << MSC_FDD_TRACKS_SHIFT) |
                           2880;
    MSC_REG_WRITE(MSC_REG_FDD0_GEOMETRY, default_fdd);
    MSC_REG_WRITE(MSC_REG_FDD1_GEOMETRY, default_fdd);

    /* Clear HDD capacity */
    MSC_REG_WRITE(MSC_REG_HDD0_CAP_LO, 0);
    MSC_REG_WRITE(MSC_REG_HDD0_CAP_HI, 0);
    MSC_REG_WRITE(MSC_REG_HDD1_CAP_LO, 0);
    MSC_REG_WRITE(MSC_REG_HDD1_CAP_HI, 0);

    /* Clear drive status (ready/wp) */
    MSC_REG_WRITE(MSC_REG_DRIVE_STATUS, 0);
}

/*---------------------------------------------------------------------------
 * FDD Geometry Configuration
 *---------------------------------------------------------------------------*/

void msc_config_set_fdd_geometry(msc_drive_t drive, const msc_fdd_geometry_t *geom)
{
    if (geom == NULL || drive > MSC_DRIVE_FDD1)
        return;

    msc_config_set_fdd_params(drive, geom->sectors, geom->tracks,
                              geom->heads, geom->spt);
}

void msc_config_set_fdd_params(msc_drive_t drive, uint16_t sectors,
                               uint8_t tracks, uint8_t heads, uint8_t spt)
{
    uint32_t reg_offset;
    uint32_t value;

    if (drive > MSC_DRIVE_FDD1)
        return;

    reg_offset = (drive == MSC_DRIVE_FDD0) ? MSC_REG_FDD0_GEOMETRY
                                           : MSC_REG_FDD1_GEOMETRY;

    value = ((uint32_t)(spt & 0x0F) << MSC_FDD_SPT_SHIFT) |
            ((uint32_t)(heads & 0x0F) << MSC_FDD_HEADS_SHIFT) |
            ((uint32_t)tracks << MSC_FDD_TRACKS_SHIFT) |
            (uint32_t)sectors;

    MSC_REG_WRITE(reg_offset, value);
}

/*---------------------------------------------------------------------------
 * HDD Capacity Configuration
 *---------------------------------------------------------------------------*/

void msc_config_set_hdd_capacity(msc_drive_t drive, uint64_t sectors)
{
    uint32_t lo_offset, hi_offset;

    if (drive == MSC_DRIVE_HDD0) {
        lo_offset = MSC_REG_HDD0_CAP_LO;
        hi_offset = MSC_REG_HDD0_CAP_HI;
    } else if (drive == MSC_DRIVE_HDD1) {
        lo_offset = MSC_REG_HDD1_CAP_LO;
        hi_offset = MSC_REG_HDD1_CAP_HI;
    } else {
        return;  /* Invalid drive for HDD capacity */
    }

    MSC_REG_WRITE(lo_offset, (uint32_t)(sectors & 0xFFFFFFFF));
    MSC_REG_WRITE(hi_offset, (uint32_t)(sectors >> 32));
}

/*---------------------------------------------------------------------------
 * Drive Status Configuration
 *---------------------------------------------------------------------------*/

void msc_config_set_ready(msc_drive_t drive, bool ready)
{
    uint32_t status = MSC_REG_READ(MSC_REG_DRIVE_STATUS);
    uint32_t bit = (1 << drive);  /* Ready bits are [3:0] */

    if (ready)
        status |= bit;
    else
        status &= ~bit;

    MSC_REG_WRITE(MSC_REG_DRIVE_STATUS, status);
}

void msc_config_set_write_protect(msc_drive_t drive, bool wp)
{
    uint32_t status = MSC_REG_READ(MSC_REG_DRIVE_STATUS);
    uint32_t bit = (1 << (8 + drive));  /* WP bits are [11:8] */

    if (wp)
        status |= bit;
    else
        status &= ~bit;

    MSC_REG_WRITE(MSC_REG_DRIVE_STATUS, status);
}

/*---------------------------------------------------------------------------
 * Configuration Validation
 *---------------------------------------------------------------------------*/

void msc_config_validate(void)
{
    uint32_t ctrl = MSC_REG_READ(MSC_REG_CTRL);
    ctrl |= MSC_CTRL_CONFIG_VALID;
    MSC_REG_WRITE(MSC_REG_CTRL, ctrl);
}

void msc_config_invalidate(void)
{
    uint32_t ctrl = MSC_REG_READ(MSC_REG_CTRL);
    ctrl &= ~MSC_CTRL_CONFIG_VALID;
    MSC_REG_WRITE(MSC_REG_CTRL, ctrl);
}

/*---------------------------------------------------------------------------
 * Media Changed Handling
 *---------------------------------------------------------------------------*/

bool msc_config_media_changed(msc_drive_t drive)
{
    uint32_t status = MSC_REG_READ(MSC_REG_DRIVE_STATUS);
    uint32_t bit = (1 << (4 + drive));  /* Changed bits are [7:4] */
    return (status & bit) != 0;
}

void msc_config_clear_media_changed(msc_drive_t drive)
{
    /* Write 1 to clear the media changed bit */
    uint32_t bit = (1 << (4 + drive));
    MSC_REG_WRITE(MSC_REG_DRIVE_STATUS, bit);
}

/*---------------------------------------------------------------------------
 * Status Queries
 *---------------------------------------------------------------------------*/

bool msc_config_drive_present(msc_drive_t drive)
{
    uint32_t status = MSC_REG_READ(MSC_REG_STATUS);
    uint32_t bit = (1 << drive);  /* Present bits are [3:0] */
    return (status & bit) != 0;
}

uint32_t msc_config_read_ctrl(void)
{
    return MSC_REG_READ(MSC_REG_CTRL);
}

uint32_t msc_config_read_status(void)
{
    return MSC_REG_READ(MSC_REG_STATUS);
}

/*---------------------------------------------------------------------------
 * Interrupt Control
 *---------------------------------------------------------------------------*/

void msc_config_int_global_enable(bool enable)
{
    uint32_t int_ctrl = MSC_REG_READ(MSC_REG_INT_CTRL);

    if (enable)
        int_ctrl |= MSC_INT_GLOBAL_ENABLE;
    else
        int_ctrl &= ~MSC_INT_GLOBAL_ENABLE;

    MSC_REG_WRITE(MSC_REG_INT_CTRL, int_ctrl);
}

void msc_config_int_enable(msc_drive_t drive, bool enable)
{
    uint32_t int_ctrl = MSC_REG_READ(MSC_REG_INT_CTRL);
    uint32_t bit = (1 << drive);  /* Enable bits are [3:0] */

    if (enable)
        int_ctrl |= bit;
    else
        int_ctrl &= ~bit;

    MSC_REG_WRITE(MSC_REG_INT_CTRL, int_ctrl);
}

bool msc_config_int_pending(msc_drive_t drive)
{
    uint32_t int_ctrl = MSC_REG_READ(MSC_REG_INT_CTRL);
    uint32_t bit = (1 << (4 + drive));  /* Pending bits are [7:4] */
    return (int_ctrl & bit) != 0;
}

void msc_config_int_clear(msc_drive_t drive)
{
    /* Write 1 to pending bit to clear it (write-1-to-clear) */
    uint32_t bit = (1 << (4 + drive));
    MSC_REG_WRITE(MSC_REG_INT_CTRL, bit);
}

uint32_t msc_config_read_int_ctrl(void)
{
    return MSC_REG_READ(MSC_REG_INT_CTRL);
}

/*---------------------------------------------------------------------------
 * Interrupt Handler
 *---------------------------------------------------------------------------*/

/* Forward declaration for MSC HAL media changed notification */
extern void msc_hal_notify_media_changed(uint8_t lun);

void msc_config_irq_handler(void)
{
    uint32_t int_ctrl = MSC_REG_READ(MSC_REG_INT_CTRL);
    uint32_t pending = (int_ctrl >> 4) & 0x0F;
    uint32_t enabled = int_ctrl & 0x0F;

    /* Only process enabled and pending interrupts */
    uint32_t active = pending & enabled;

    if (active & (1 << MSC_DRIVE_FDD0)) {
        msc_hal_notify_media_changed(0);
        msc_config_int_clear(MSC_DRIVE_FDD0);
    }

    if (active & (1 << MSC_DRIVE_FDD1)) {
        msc_hal_notify_media_changed(1);
        msc_config_int_clear(MSC_DRIVE_FDD1);
    }

    if (active & (1 << MSC_DRIVE_HDD0)) {
        msc_hal_notify_media_changed(2);
        msc_config_int_clear(MSC_DRIVE_HDD0);
    }

    if (active & (1 << MSC_DRIVE_HDD1)) {
        msc_hal_notify_media_changed(3);
        msc_config_int_clear(MSC_DRIVE_HDD1);
    }
}
