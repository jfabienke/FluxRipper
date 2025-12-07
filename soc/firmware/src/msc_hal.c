/*-----------------------------------------------------------------------------
 * msc_hal.c
 * USB Mass Storage Class - Hardware Abstraction Layer Implementation
 *
 * Created: 2025-12-05 15:50
 * Modified: 2025-12-05 21:30 - Added drive profile based geometry detection
 * Modified: 2025-12-05 21:45 - Dynamic SCSI Product ID from FDD profile/HDD metadata
 *
 * Bridges USB MSC operations to FluxRipper FDD and HDD HAL layers.
 *---------------------------------------------------------------------------*/

#include "msc_hal.h"
#include "msc_config.h"
#include "fluxripper_hal.h"
#include "hdd_hal.h"
#include "hdd_metadata.h"
#include <string.h>
#include <stdio.h>

/*---------------------------------------------------------------------------
 * Private Data
 *---------------------------------------------------------------------------*/

static msc_hal_state_t msc_state;

/* Per-LUN statistics */
static uint32_t lun_read_count[MSC_MAX_LUNS];
static uint32_t lun_write_count[MSC_MAX_LUNS];
static uint32_t lun_error_count[MSC_MAX_LUNS];
static int      lun_last_error[MSC_MAX_LUNS];

/*---------------------------------------------------------------------------
 * Private Functions
 *---------------------------------------------------------------------------*/

/**
 * Map LUN to physical drive type and index
 */
static void lun_to_drive(uint8_t lun, uint8_t *type, uint8_t *index)
{
    if (lun < MSC_MAX_FDDS) {
        *type = MSC_LUN_TYPE_FDD;
        *index = lun;
    } else if (lun < MSC_MAX_LUNS) {
        *type = MSC_LUN_TYPE_HDD;
        *index = lun - MSC_MAX_FDDS;
    } else {
        *type = MSC_LUN_TYPE_NONE;
        *index = 0;
    }
}

/**
 * Calculate FDD sector count from drive profile
 *
 * Common FDD geometries:
 *   360KB 5.25" DD:  40 tracks * 2 heads * 9 sectors  =  720 sectors
 *   720KB 3.5" DD:   80 tracks * 2 heads * 9 sectors  = 1440 sectors
 *   1.2MB 5.25" HD:  80 tracks * 2 heads * 15 sectors = 2400 sectors
 *   1.44MB 3.5" HD:  80 tracks * 2 heads * 18 sectors = 2880 sectors
 *   2.88MB 3.5" ED:  80 tracks * 2 heads * 36 sectors = 5760 sectors
 */
static uint32_t calculate_fdd_capacity(const drive_profile_t *profile)
{
    uint8_t cylinders;
    uint8_t heads = 2;  /* Assume double-sided */
    uint8_t spt;        /* Sectors per track */

    /* Get cylinder count from track density */
    switch (profile->tracks) {
        case TRACKS_40:
            cylinders = 40;
            break;
        case TRACKS_80:
            cylinders = 80;
            break;
        case TRACKS_77:
            cylinders = 77;  /* 8" floppies */
            break;
        default:
            cylinders = 80;  /* Default to 80 track */
            break;
    }

    /* Determine sectors per track from density and form factor */
    switch (profile->density) {
        case DENS_DD:  /* Double Density */
            if (profile->form_factor == FF_5_25) {
                spt = 9;   /* 360KB mode */
            } else if (profile->form_factor == FF_8) {
                spt = 26;  /* 8" SD/DD typically has 26 sectors */
            } else {
                spt = 9;   /* 720KB mode for 3.5" */
            }
            break;

        case DENS_HD:  /* High Density */
            if (profile->form_factor == FF_5_25) {
                spt = 15;  /* 1.2MB mode */
            } else {
                spt = 18;  /* 1.44MB mode for 3.5" */
            }
            break;

        case DENS_ED:  /* Extended Density */
            spt = 36;  /* 2.88MB mode */
            break;

        default:
            /* Unknown density - guess based on form factor */
            if (profile->form_factor == FF_3_5) {
                spt = 18;  /* Assume 1.44MB */
            } else {
                spt = 9;   /* Assume DD */
            }
            break;
    }

    return (uint32_t)cylinders * heads * spt;
}

/**
 * Build FDD Product ID from drive profile
 *
 * Format: "X.XX" YY ZZT EEE" (16 chars max)
 * Examples:
 *   "3.5\" HD 80T MFM"
 *   "5.25\" DD 40T MFM"
 *   "8\" SD 77T FM"
 */
static void build_fdd_product_id(const drive_profile_t *profile, char *product)
{
    const char *ff_str;
    const char *dens_str;
    const char *enc_str;
    int tracks;

    /* Form factor */
    switch (profile->form_factor) {
        case FF_3_5:  ff_str = "3.5\""; break;
        case FF_5_25: ff_str = "5.25\""; break;
        case FF_8:    ff_str = "8\""; break;
        default:      ff_str = "?\""; break;
    }

    /* Density */
    switch (profile->density) {
        case DENS_DD: dens_str = "DD"; break;
        case DENS_HD: dens_str = "HD"; break;
        case DENS_ED: dens_str = "ED"; break;
        default:      dens_str = "??"; break;
    }

    /* Encoding */
    switch (profile->encoding) {
        case ENC_FM:        enc_str = "FM"; break;
        case ENC_MFM:       enc_str = "MFM"; break;
        case ENC_GCR_APPLE: enc_str = "GCR"; break;
        case ENC_GCR_C64:   enc_str = "GCR"; break;
        default:            enc_str = "???"; break;
    }

    /* Track count */
    switch (profile->tracks) {
        case TRACKS_40: tracks = 40; break;
        case TRACKS_80: tracks = 80; break;
        case TRACKS_77: tracks = 77; break;
        default:        tracks = 80; break;
    }

    /* Build product string: "3.5\" HD 80T MFM" */
    snprintf(product, 17, "%s %s %dT %s", ff_str, dens_str, tracks, enc_str);
}

/**
 * Build HDD Product ID from secret metadata record
 *
 * Uses the user-entered model name from drive label if available,
 * otherwise returns generic identifier.
 *
 * Examples:
 *   "ST-225" (from Seagate label)
 *   "Wren III" (from CDC label)
 *   "3425" (from Miniscribe label)
 */
static void build_hdd_product_id(uint8_t drive_index, char *vendor, char *product)
{
    hdd_metadata_t meta;

    /* Try to read secret metadata from drive */
    if (meta_read(drive_index, &meta) == META_OK &&
        meta.signature == METADATA_SIGNATURE) {

        /* Use vendor from metadata if available */
        if (meta.identity.vendor[0] != '\0' && meta.identity.vendor[0] != 0xFF) {
            strncpy(vendor, meta.identity.vendor, 8);
            vendor[8] = '\0';
        } else {
            strncpy(vendor, "FluxRip", 8);
            vendor[8] = '\0';
        }

        /* Use model from metadata if available */
        if (meta.identity.model[0] != '\0' && meta.identity.model[0] != 0xFF) {
            strncpy(product, meta.identity.model, 16);
            product[16] = '\0';
        } else {
            /* Generic based on fingerprint if model not set */
            if (meta.fingerprint.max_cylinder > 0) {
                snprintf(product, 17, "HDD %uMB",
                         (unsigned int)((meta.fingerprint.max_cylinder *
                                         meta.fingerprint.heads *
                                         meta.fingerprint.spt_outer * 512) / (1024*1024)));
            } else {
                snprintf(product, 17, "FluxRipper HDD %d", drive_index);
            }
        }
    } else {
        /* No metadata - use defaults */
        strncpy(vendor, "FluxRip", 8);
        vendor[8] = '\0';
        snprintf(product, 17, "FluxRipper HDD %d", drive_index);
    }
}

/**
 * Configure FDD LUN
 */
static void configure_fdd_lun(uint8_t lun, uint8_t drive_index)
{
    msc_lun_config_t *cfg = &msc_state.luns[lun];
    drive_profile_t profile;

    cfg->lun_type = MSC_LUN_TYPE_FDD;
    cfg->drive_index = drive_index;
    cfg->removable = true;
    cfg->block_size = 512;

    /* Check if disk is present */
    cfg->present = hal_disk_present(drive_index);
    cfg->readonly = hal_write_protected(drive_index);

    /* Set capacity based on detected drive profile */
    cfg->capacity = 2880;  /* Default to 1.44MB if detection fails */

    if (cfg->present) {
        /* Query drive profile for geometry detection */
        if (hal_get_profile(drive_index, &profile) == HAL_OK && profile.valid) {
            cfg->capacity = calculate_fdd_capacity(&profile);

            /* Build dynamic Product ID from detected profile */
            /* Examples: "3.5\" HD 80T MFM", "5.25\" DD 40T MFM" */
            build_fdd_product_id(&profile, cfg->product);
        } else {
            /* Profile not available - use defaults */
            cfg->capacity = 2880;  /* Assume 1.44MB for 3.5" HD */
            if (drive_index == 0) {
                strncpy(cfg->product, "FluxRipper FDD A", 16);
            } else {
                strncpy(cfg->product, "FluxRipper FDD B", 16);
            }
        }
    } else {
        /* No disk - generic identifier */
        if (drive_index == 0) {
            strncpy(cfg->product, "FluxRipper FDD A", 16);
        } else {
            strncpy(cfg->product, "FluxRipper FDD B", 16);
        }
    }
    cfg->product[16] = '\0';

    /* Vendor is always FluxRip for FDDs */
    strncpy(cfg->vendor, "FluxRip", 8);
    cfg->vendor[8] = '\0';

    strncpy(cfg->revision, "1.00", 4);
    cfg->revision[4] = '\0';

    cfg->changed = false;

    /* Update RTL configuration registers with detected geometry */
    if (cfg->present && hal_get_profile(drive_index, &profile) == HAL_OK && profile.valid) {
        uint8_t spt;
        switch (profile.density) {
            case DENS_DD: spt = 9;  break;
            case DENS_HD: spt = 18; break;
            case DENS_ED: spt = 36; break;
            default:      spt = 18; break;
        }
        msc_config_set_fdd_params(
            (drive_index == 0) ? MSC_DRIVE_FDD0 : MSC_DRIVE_FDD1,
            (uint16_t)cfg->capacity,
            profile.tracks,
            2,  /* heads */
            spt
        );
    }
    msc_config_set_ready(
        (drive_index == 0) ? MSC_DRIVE_FDD0 : MSC_DRIVE_FDD1,
        cfg->present
    );
    msc_config_set_write_protect(
        (drive_index == 0) ? MSC_DRIVE_FDD0 : MSC_DRIVE_FDD1,
        cfg->readonly
    );
}

/**
 * Configure HDD LUN
 */
static void configure_hdd_lun(uint8_t lun, uint8_t drive_index)
{
    msc_lun_config_t *cfg = &msc_state.luns[lun];

    cfg->lun_type = MSC_LUN_TYPE_HDD;
    cfg->drive_index = drive_index;
    cfg->removable = false;  /* HDDs are fixed */
    cfg->block_size = 512;

    /* Check if drive is present/ready */
    cfg->present = hal_hdd_is_ready(drive_index);
    cfg->readonly = false;  /* HDDs typically not write-protected */

    /* Get capacity from HDD discovery */
    if (cfg->present) {
        hdd_geometry_t geom;
        if (hal_hdd_get_geometry(drive_index, &geom) == HAL_OK) {
            cfg->capacity = geom.total_sectors;
        } else {
            cfg->capacity = 0;
        }
    } else {
        cfg->capacity = 0;
    }

    /* Set identification strings from secret metadata record */
    /* Uses vendor/model from drive label if user entered it */
    /* Examples: Vendor="Seagate", Product="ST-225" */
    /*           Vendor="CDC", Product="Wren III" */
    build_hdd_product_id(drive_index, cfg->vendor, cfg->product);

    strncpy(cfg->revision, "1.00", 4);
    cfg->revision[4] = '\0';

    cfg->changed = false;

    /* Update RTL configuration registers with detected capacity */
    msc_config_set_hdd_capacity(
        (drive_index == 0) ? MSC_DRIVE_HDD0 : MSC_DRIVE_HDD1,
        cfg->capacity
    );
    msc_config_set_ready(
        (drive_index == 0) ? MSC_DRIVE_HDD0 : MSC_DRIVE_HDD1,
        cfg->present
    );
}

/*---------------------------------------------------------------------------
 * Public Functions - Initialization
 *---------------------------------------------------------------------------*/

int msc_hal_init(void)
{
    int i;

    memset(&msc_state, 0, sizeof(msc_state));
    memset(lun_read_count, 0, sizeof(lun_read_count));
    memset(lun_write_count, 0, sizeof(lun_write_count));
    memset(lun_error_count, 0, sizeof(lun_error_count));
    memset(lun_last_error, 0, sizeof(lun_last_error));

    /* Initialize RTL configuration registers (config_valid=0 initially) */
    msc_config_init();

    /* Configure FDD LUNs */
    for (i = 0; i < MSC_MAX_FDDS; i++) {
        configure_fdd_lun(i, i);
    }

    /* Configure HDD LUNs */
    for (i = 0; i < MSC_MAX_HDDS; i++) {
        configure_hdd_lun(MSC_MAX_FDDS + i, i);
    }

    /* Mark configuration as valid - RTL can now use these values */
    msc_config_validate();

    /* Enable media change interrupts for all FDD drives */
    msc_config_int_enable(MSC_DRIVE_FDD0, true);
    msc_config_int_enable(MSC_DRIVE_FDD1, true);
    /* HDD doesn't have physical disk change, but enable for completeness */
    msc_config_int_enable(MSC_DRIVE_HDD0, false);
    msc_config_int_enable(MSC_DRIVE_HDD1, false);
    /* Enable global interrupt */
    msc_config_int_global_enable(true);

    msc_state.lun_count = MSC_MAX_LUNS;
    msc_state.initialized = true;

    return MSC_OK;
}

int msc_hal_get_lun_count(void)
{
    return msc_state.lun_count;
}

int msc_hal_get_lun_config(uint8_t lun, msc_lun_config_t *config)
{
    if (lun >= MSC_MAX_LUNS || config == NULL) {
        return MSC_ERR_INVALID_LUN;
    }

    memcpy(config, &msc_state.luns[lun], sizeof(msc_lun_config_t));
    return MSC_OK;
}

/*---------------------------------------------------------------------------
 * Public Functions - Drive Operations
 *---------------------------------------------------------------------------*/

bool msc_hal_is_ready(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) {
        return false;
    }

    /* Refresh presence status */
    msc_lun_config_t *cfg = &msc_state.luns[lun];

    if (cfg->lun_type == MSC_LUN_TYPE_FDD) {
        cfg->present = hal_disk_present(cfg->drive_index);
    } else if (cfg->lun_type == MSC_LUN_TYPE_HDD) {
        cfg->present = hal_hdd_is_ready(cfg->drive_index);
    }

    return cfg->present;
}

bool msc_hal_is_write_protected(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) {
        return true;
    }

    msc_lun_config_t *cfg = &msc_state.luns[lun];

    if (cfg->lun_type == MSC_LUN_TYPE_FDD) {
        cfg->readonly = hal_write_protected(cfg->drive_index);
    }

    return cfg->readonly;
}

bool msc_hal_media_changed(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) {
        return false;
    }

    msc_lun_config_t *cfg = &msc_state.luns[lun];
    bool changed = cfg->changed;
    cfg->changed = false;  /* Clear flag on read */

    return changed;
}

void msc_hal_notify_media_changed(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) {
        return;
    }

    msc_lun_config_t *cfg = &msc_state.luns[lun];

    /* Set the changed flag - will be reported on next SCSI TEST_UNIT_READY */
    cfg->changed = true;

    /* Re-scan drive to update capacity and presence */
    if (cfg->lun_type == MSC_LUN_TYPE_FDD && lun < MSC_MAX_FDDS) {
        configure_fdd_lun(lun, cfg->drive_index);
    }
}

int msc_hal_read_sectors(uint8_t lun, uint32_t lba, void *buf, uint32_t count)
{
    int ret;

    if (lun >= MSC_MAX_LUNS) {
        return MSC_ERR_INVALID_LUN;
    }

    msc_lun_config_t *cfg = &msc_state.luns[lun];

    if (!cfg->present) {
        lun_last_error[lun] = MSC_ERR_NO_MEDIA;
        return MSC_ERR_NO_MEDIA;
    }

    /* Check LBA range */
    if (lba + count > cfg->capacity) {
        lun_last_error[lun] = MSC_ERR_LBA_RANGE;
        return MSC_ERR_LBA_RANGE;
    }

    /* Route to appropriate HAL */
    if (cfg->lun_type == MSC_LUN_TYPE_FDD) {
        ret = hal_read_sectors(cfg->drive_index, lba, buf, count);
    } else if (cfg->lun_type == MSC_LUN_TYPE_HDD) {
        ret = hal_hdd_read_sectors(cfg->drive_index, lba, buf, count);
    } else {
        return MSC_ERR_INVALID_LUN;
    }

    if (ret == HAL_OK) {
        lun_read_count[lun] += count;
        lun_last_error[lun] = MSC_OK;
        return MSC_OK;
    } else {
        lun_error_count[lun]++;
        lun_last_error[lun] = MSC_ERR_READ;
        return MSC_ERR_READ;
    }
}

int msc_hal_write_sectors(uint8_t lun, uint32_t lba, const void *buf, uint32_t count)
{
    int ret;

    if (lun >= MSC_MAX_LUNS) {
        return MSC_ERR_INVALID_LUN;
    }

    msc_lun_config_t *cfg = &msc_state.luns[lun];

    if (!cfg->present) {
        lun_last_error[lun] = MSC_ERR_NO_MEDIA;
        return MSC_ERR_NO_MEDIA;
    }

    if (cfg->readonly) {
        lun_last_error[lun] = MSC_ERR_WRITE_PROT;
        return MSC_ERR_WRITE_PROT;
    }

    /* Check LBA range */
    if (lba + count > cfg->capacity) {
        lun_last_error[lun] = MSC_ERR_LBA_RANGE;
        return MSC_ERR_LBA_RANGE;
    }

    /* Route to appropriate HAL */
    if (cfg->lun_type == MSC_LUN_TYPE_FDD) {
        ret = hal_write_sectors(cfg->drive_index, lba, buf, count);
    } else if (cfg->lun_type == MSC_LUN_TYPE_HDD) {
        ret = hal_hdd_write_sectors(cfg->drive_index, lba, buf, count);
    } else {
        return MSC_ERR_INVALID_LUN;
    }

    if (ret == HAL_OK) {
        lun_write_count[lun] += count;
        lun_last_error[lun] = MSC_OK;
        return MSC_OK;
    } else {
        lun_error_count[lun]++;
        lun_last_error[lun] = MSC_ERR_WRITE;
        return MSC_ERR_WRITE;
    }
}

int msc_hal_start_stop(uint8_t lun, bool start, bool eject)
{
    if (lun >= MSC_MAX_LUNS) {
        return MSC_ERR_INVALID_LUN;
    }

    msc_lun_config_t *cfg = &msc_state.luns[lun];

    if (cfg->lun_type == MSC_LUN_TYPE_FDD) {
        if (start) {
            hal_motor_on(cfg->drive_index);
        } else {
            hal_motor_off(cfg->drive_index);
        }
        /* Eject not supported for floppy (no motorized eject) */
    } else if (cfg->lun_type == MSC_LUN_TYPE_HDD) {
        /* HDD motors are always on, ignore start/stop */
        (void)start;
        (void)eject;
    }

    return MSC_OK;
}

int msc_hal_prevent_removal(uint8_t lun, bool prevent)
{
    /* Not implemented - FluxRipper doesn't have door lock */
    (void)lun;
    (void)prevent;
    return MSC_OK;
}

/*---------------------------------------------------------------------------
 * Public Functions - Geometry
 *---------------------------------------------------------------------------*/

int msc_hal_get_capacity(uint8_t lun, uint32_t *last_lba, uint16_t *block_size)
{
    if (lun >= MSC_MAX_LUNS) {
        return MSC_ERR_INVALID_LUN;
    }

    msc_lun_config_t *cfg = &msc_state.luns[lun];

    if (last_lba) {
        *last_lba = (cfg->capacity > 0) ? cfg->capacity - 1 : 0;
    }
    if (block_size) {
        *block_size = cfg->block_size;
    }

    return MSC_OK;
}

int msc_hal_refresh_lun(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) {
        return MSC_ERR_INVALID_LUN;
    }

    msc_lun_config_t *cfg = &msc_state.luns[lun];
    bool was_present = cfg->present;

    if (cfg->lun_type == MSC_LUN_TYPE_FDD) {
        configure_fdd_lun(lun, cfg->drive_index);
    } else if (cfg->lun_type == MSC_LUN_TYPE_HDD) {
        configure_hdd_lun(lun, cfg->drive_index);
    }

    /* Detect media change */
    if (cfg->present != was_present) {
        cfg->changed = true;
    }

    return MSC_OK;
}

/*---------------------------------------------------------------------------
 * Public Functions - Status
 *---------------------------------------------------------------------------*/

int msc_hal_get_last_error(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) {
        return MSC_ERR_INVALID_LUN;
    }
    return lun_last_error[lun];
}

void msc_hal_get_stats(uint8_t lun, uint32_t *read_count,
                       uint32_t *write_count, uint32_t *error_count)
{
    if (lun >= MSC_MAX_LUNS) {
        if (read_count) *read_count = 0;
        if (write_count) *write_count = 0;
        if (error_count) *error_count = 0;
        return;
    }

    if (read_count) *read_count = lun_read_count[lun];
    if (write_count) *write_count = lun_write_count[lun];
    if (error_count) *error_count = lun_error_count[lun];
}
