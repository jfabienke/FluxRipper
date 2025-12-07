/**
 * FluxRipper HAL Driver - Hardware Abstraction Layer
 *
 * Provides clean API for FluxRipper FDC hardware access.
 * Abstracts dual-interface 82077AA-compatible FDC with FluxRipper extensions.
 *
 * Target: AMD Spartan UltraScale+ SCU35
 * Updated: 2025-12-03 15:30:00
 */

#ifndef FLUXRIPPER_HAL_H
#define FLUXRIPPER_HAL_H

#include <stdint.h>
#include <stdbool.h>
#include "platform.h"

/*============================================================================
 * Hardware Register Definitions
 *============================================================================*/

/* 82077AA Standard Registers (relative to FDC_BASE) */
#define FDC_SRA_SRB         (FDC_BASE + 0x00)   /* Status Register A/B (R) */
#define FDC_DOR             (FDC_BASE + 0x04)   /* Digital Output Register (R/W) */
#define FDC_TDR             (FDC_BASE + 0x08)   /* Tape Drive Register (R/W) */
#define FDC_MSR_DSR         (FDC_BASE + 0x0C)   /* Main Status / Data Rate Select */
#define FDC_DATA            (FDC_BASE + 0x10)   /* FIFO Data Register */
#define FDC_DIR_CCR         (FDC_BASE + 0x14)   /* Digital Input / Config Control */
#define FDC_FLUX_CTRL       (FDC_BASE + 0x18)   /* Flux Capture Control (A) */
#define FDC_FLUX_STATUS     (FDC_BASE + 0x1C)   /* Flux Capture Status (A) */
#define FDC_CAPTURE_CNT     (FDC_BASE + 0x20)   /* Capture Count (A) */
#define FDC_INDEX_CNT       (FDC_BASE + 0x24)   /* Index Count (A) */
#define FDC_QUALITY         (FDC_BASE + 0x28)   /* Signal Quality (A) */
#define FDC_VERSION         (FDC_BASE + 0x2C)   /* Hardware Version */

/* FluxRipper Extension Registers */
#define FDC_DUAL_CTRL       (FDC_BASE + 0x30)   /* Dual Interface Control */
#define FDC_A_STATUS        (FDC_BASE + 0x34)   /* FDC A Extended Status */
#define FDC_B_STATUS        (FDC_BASE + 0x38)   /* FDC B Extended Status */
#define FDC_TRACK_A         (FDC_BASE + 0x3C)   /* Current Track A */
#define FDC_TRACK_B         (FDC_BASE + 0x40)   /* Current Track B */
#define FDC_FLUX_CTRL_A     (FDC_BASE + 0x44)   /* Flux Control A */
#define FDC_FLUX_CTRL_B     (FDC_BASE + 0x48)   /* Flux Control B */
#define FDC_FLUX_STAT_A     (FDC_BASE + 0x4C)   /* Flux Status A */
#define FDC_FLUX_STAT_B     (FDC_BASE + 0x50)   /* Flux Status B */
#define FDC_COPY_CTRL       (FDC_BASE + 0x54)   /* Disk-to-Disk Copy Control */
#define FDC_COPY_STATUS     (FDC_BASE + 0x58)   /* Copy Operation Status */
#define FDC_AUTO_STATUS_A   (FDC_BASE + 0x5C)   /* Auto-detection Status A */
#define FDC_AUTO_STATUS_B   (FDC_BASE + 0x60)   /* Auto-detection Status B */
#define FDC_EJECT_CTRL      (FDC_BASE + 0x64)   /* Motorized Eject Control */
#define FDC_DRIVE_PROFILE_A (FDC_BASE + 0x68)   /* Drive Profile A */
#define FDC_DRIVE_PROFILE_B (FDC_BASE + 0x74)   /* Drive Profile B */
#define FDC_B_MSR_DSR       (FDC_BASE + 0x78)   /* FDC B Main Status / Data Rate */
#define FDC_B_DATA          (FDC_BASE + 0x7C)   /* FDC B FIFO Data Register */

/*============================================================================
 * Register Bit Definitions
 *============================================================================*/

/* Main Status Register (MSR) - Read */
#define MSR_RQM             BIT(7)  /* Request for Master (ready for command) */
#define MSR_DIO             BIT(6)  /* Data Input/Output (1=read, 0=write) */
#define MSR_NON_DMA         BIT(5)  /* Non-DMA mode */
#define MSR_CB              BIT(4)  /* Command Busy */
#define MSR_DRV3_BUSY       BIT(3)  /* Drive 3 Busy */
#define MSR_DRV2_BUSY       BIT(2)  /* Drive 2 Busy */
#define MSR_DRV1_BUSY       BIT(1)  /* Drive 1 Busy */
#define MSR_DRV0_BUSY       BIT(0)  /* Drive 0 Busy */

/* Data Rate Select Register (DSR) - Write to MSR address */
#define DSR_SW_RESET        BIT(7)  /* Software Reset */
#define DSR_POWER_DOWN      BIT(6)  /* Power Down */
#define DSR_PRECOMP_MASK    (0x7 << 2)  /* Precompensation */
#define DSR_DRATE_MASK      (0x3 << 0)  /* Data Rate */
#define DSR_DRATE_500K      0x00    /* 500 Kbps (HD) */
#define DSR_DRATE_300K      0x01    /* 300 Kbps (DD) */
#define DSR_DRATE_250K      0x02    /* 250 Kbps (DD) */
#define DSR_DRATE_1M        0x03    /* 1 Mbps (ED) */

/* Digital Output Register (DOR) */
#define DOR_MOTOR_3         BIT(7)  /* Motor Enable Drive 3 */
#define DOR_MOTOR_2         BIT(6)  /* Motor Enable Drive 2 */
#define DOR_MOTOR_1         BIT(5)  /* Motor Enable Drive 1 */
#define DOR_MOTOR_0         BIT(4)  /* Motor Enable Drive 0 */
#define DOR_DMA_ENABLE      BIT(3)  /* DMA Enable */
#define DOR_NOT_RESET       BIT(2)  /* Not Reset (1=normal, 0=reset) */
#define DOR_DRIVE_SEL_MASK  0x03    /* Drive Select (0-3) */

/* Digital Input Register (DIR) - Read from DIR_CCR */
#define DIR_DISK_CHANGE     BIT(7)  /* Disk Change */

/* Configuration Control Register (CCR) - Write to DIR_CCR */
#define CCR_DRATE_MASK      0x03    /* Data Rate (same as DSR) */

/* Status Register A (SRA) - Lower byte of SRA_SRB */
#define SRA_INT_PENDING     BIT(7)  /* Interrupt Pending */
#define SRA_DRV2_WP         BIT(6)  /* Drive 2 Write Protect */
#define SRA_HEAD1_SEL       BIT(5)  /* Head 1 Select */
#define SRA_TRACK0          BIT(4)  /* Track 0 */
#define SRA_STEP            BIT(3)  /* Step */
#define SRA_DRV2_SEL        BIT(2)  /* Drive 2 Select */
#define SRA_INDEX           BIT(1)  /* Index */
#define SRA_DIR             BIT(0)  /* Direction (1=out, 0=in) */

/* Status Register B (SRB) - Upper byte of SRA_SRB */
#define SRB_DRV_SEL_MASK    (0x3 << 14) /* Drive Select */
#define SRB_WRITE_DATA      BIT(13)     /* Write Data */
#define SRB_READ_DATA       BIT(12)     /* Read Data */
#define SRB_WRITE_ENABLE    BIT(11)     /* Write Enable */
#define SRB_MOTOR_ON        BIT(10)     /* Motor On */
#define SRB_DRV0_WP         BIT(9)      /* Drive 0 Write Protect */
#define SRB_DRV1_WP         BIT(8)      /* Drive 1 Write Protect */

/* Flux Control Register */
#define FLUX_CTRL_START     BIT(0)  /* Start Capture */
#define FLUX_CTRL_STOP      BIT(1)  /* Stop Capture */
#define FLUX_CTRL_RESET     BIT(2)  /* Reset Capture Logic */
#define FLUX_CTRL_REV_MASK  (0xFF << 8) /* Revolution Count */

/* Flux Status Register */
#define FLUX_STAT_ACTIVE    BIT(0)  /* Capture Active */
#define FLUX_STAT_DONE      BIT(1)  /* Capture Complete */
#define FLUX_STAT_ERROR     BIT(2)  /* Capture Error */
#define FLUX_STAT_OVERFLOW  BIT(3)  /* FIFO Overflow */

/* Auto-Detection Status Register */
#define AUTO_STAT_VALID     BIT(0)  /* Profile Valid */
#define AUTO_STAT_LOCKED    BIT(1)  /* Profile Locked */
#define AUTO_STAT_BUSY      BIT(2)  /* Detection in Progress */

/* Dual Control Register */
#define DUAL_CTRL_ENABLE    BIT(0)  /* Enable Dual Interface Mode */
#define DUAL_CTRL_SYNC_IDX  BIT(1)  /* Synchronize on Index */
#define DUAL_CTRL_IF_A_SEL  (0x3 << 2)  /* Interface A Drive Select */
#define DUAL_CTRL_IF_B_SEL  (0x3 << 4)  /* Interface B Drive Select */

/*============================================================================
 * Drive Profile Register Format
 *============================================================================*/

/* DRIVE_PROFILE_A/B 32-bit packed format:
 * [1:0]   = Form factor (00=unk, 01=3.5", 10=5.25", 11=8")
 * [3:2]   = Density cap (00=DD, 01=HD, 10=ED, 11=unk)
 * [5:4]   = Track density (00=40T, 01=80T, 10=77T, 11=unk)
 * [8:6]   = Encoding detected (see encoding definitions)
 * [9]     = Valid flag
 * [10]    = Locked flag
 * [15:11] = Reserved
 * [23:16] = RPM / 10 (30=300, 36=360)
 * [31:24] = Quality score (0-255)
 */

#define PROFILE_FF_MASK         0x00000003
#define PROFILE_FF_UNKNOWN      0x00000000
#define PROFILE_FF_3_5          0x00000001
#define PROFILE_FF_5_25         0x00000002
#define PROFILE_FF_8            0x00000003

#define PROFILE_DENS_MASK       0x0000000C
#define PROFILE_DENS_DD         0x00000000
#define PROFILE_DENS_HD         0x00000004
#define PROFILE_DENS_ED         0x00000008
#define PROFILE_DENS_UNKNOWN    0x0000000C

#define PROFILE_TRACKS_MASK     0x00000030
#define PROFILE_TRACKS_40       0x00000000
#define PROFILE_TRACKS_80       0x00000010
#define PROFILE_TRACKS_77       0x00000020
#define PROFILE_TRACKS_UNKNOWN  0x00000030

#define PROFILE_ENC_MASK        0x000001C0
#define PROFILE_ENC_SHIFT       6
#define PROFILE_ENC_UNKNOWN     0x00000000
#define PROFILE_ENC_FM          0x00000040
#define PROFILE_ENC_MFM         0x00000080
#define PROFILE_ENC_GCR_APPLE   0x000000C0
#define PROFILE_ENC_GCR_C64     0x00000100
#define PROFILE_ENC_M2FM        0x00000140

#define PROFILE_VALID           0x00000200
#define PROFILE_LOCKED          0x00000400

#define PROFILE_RPM_MASK        0x00FF0000
#define PROFILE_RPM_SHIFT       16

#define PROFILE_QUALITY_MASK    0xFF000000
#define PROFILE_QUALITY_SHIFT   24

/*============================================================================
 * Constants and Enumerations
 *============================================================================*/

/* Form Factor */
#define FF_UNKNOWN      0
#define FF_3_5          1
#define FF_5_25         2
#define FF_8            3

/* Density */
#define DENS_DD         0  /* Double Density */
#define DENS_HD         1  /* High Density */
#define DENS_ED         2  /* Extended Density */
#define DENS_UNKNOWN    3

/* Encoding */
#define ENC_UNKNOWN     0
#define ENC_FM          1  /* FM (Single Density) */
#define ENC_MFM         2  /* MFM (Double Density) */
#define ENC_GCR_APPLE   3  /* GCR (Apple II, Mac) */
#define ENC_GCR_C64     4  /* GCR (Commodore 64) */
#define ENC_M2FM        5  /* M2FM (HP) */

/* Operating Modes */
typedef enum {
    MODE_IDLE = 0,
    MODE_FDC,
    MODE_FLUX_CAPTURE
} hal_mode_t;

/* Error Codes */
#define HAL_OK              0
#define HAL_ERR_INVALID     -1  /* Invalid parameter */
#define HAL_ERR_TIMEOUT     -2  /* Operation timeout */
#define HAL_ERR_NOT_READY   -3  /* Hardware not ready */
#define HAL_ERR_NO_DISK     -4  /* No disk present */
#define HAL_ERR_WRITE_PROT  -5  /* Disk write protected */
#define HAL_ERR_OVERFLOW    -6  /* Buffer overflow */
#define HAL_ERR_HARDWARE    -7  /* Hardware error */
#define HAL_ERR_MODE        -8  /* Invalid mode for operation */

/* Drive Numbers */
#define DRIVE_A         0
#define DRIVE_B         1
#define MAX_DRIVES      2

/* Timeouts (in milliseconds) */
#define TIMEOUT_READY       1000    /* Wait for FDC ready */
#define TIMEOUT_MOTOR       500     /* Motor spin-up */
#define TIMEOUT_SEEK        5000    /* Head seek */
#define TIMEOUT_OPERATION   10000   /* General operation */

/*============================================================================
 * Data Structures
 *============================================================================*/

/**
 * Drive Profile Structure
 * Contains detected or configured drive parameters
 */
typedef struct {
    uint8_t  form_factor;   /* FF_3_5, FF_5_25, FF_8 */
    uint8_t  density;       /* DENS_DD, DENS_HD, DENS_ED */
    uint8_t  tracks;        /* 40, 77, 80 */
    uint8_t  encoding;      /* ENC_MFM, ENC_FM, ENC_GCR_* */
    uint16_t rpm;           /* 300, 360 */
    uint8_t  quality;       /* 0-255 signal quality */
    bool     valid;         /* Profile has been detected */
    bool     locked;        /* Profile is stable */
} drive_profile_t;

/**
 * Flux Capture Callback
 * Called when flux data is available or capture completes
 *
 * @param drive     Drive number (0-1)
 * @param data      Pointer to flux transition data
 * @param length    Number of transitions
 * @param done      True if capture is complete
 */
typedef void (*flux_cb_t)(uint8_t drive, const uint32_t *data,
                          uint32_t length, bool done);

/*============================================================================
 * HAL API Functions
 *============================================================================*/

/**
 * Initialize FluxRipper HAL
 * Must be called before any other HAL functions.
 *
 * @return HAL_OK on success, error code otherwise
 */
int hal_init(void);

/**
 * Get current hardware version
 *
 * @return 32-bit version code (0xFDxxyyzz = FluxRipper vxx.yy.zz)
 */
uint32_t hal_get_version(void);

/**
 * Get current operating mode for a drive
 *
 * @param drive     Drive number (0-1)
 * @return Current mode or MODE_IDLE on error
 */
hal_mode_t hal_get_mode(uint8_t drive);

/**
 * Get detected drive profile
 * Reads auto-detected or manually configured drive parameters.
 *
 * @param drive     Drive number (0-1)
 * @param profile   Pointer to profile structure to fill
 * @return HAL_OK on success, error code otherwise
 */
int hal_get_profile(uint8_t drive, drive_profile_t *profile);

/**
 * Turn drive motor on
 * Waits for motor to reach operating speed.
 *
 * @param drive     Drive number (0-1)
 * @return HAL_OK on success, error code otherwise
 */
int hal_motor_on(uint8_t drive);

/**
 * Turn drive motor off
 *
 * @param drive     Drive number (0-1)
 * @return HAL_OK on success, error code otherwise
 */
int hal_motor_off(uint8_t drive);

/**
 * Seek to specified track
 * Uses FDC SEEK command for accurate positioning.
 *
 * @param drive     Drive number (0-1)
 * @param track     Target track number
 * @return HAL_OK on success, error code otherwise
 */
int hal_seek(uint8_t drive, uint8_t track);

/**
 * Read sectors using FDC
 * Standard sector read using 82077AA commands.
 *
 * @param drive     Drive number (0-1)
 * @param lba       Logical block address
 * @param buf       Buffer for data (must be 512*count bytes)
 * @param count     Number of sectors to read
 * @return HAL_OK on success, error code otherwise
 */
int hal_read_sectors(uint8_t drive, uint32_t lba, void *buf, uint32_t count);

/**
 * Start flux capture
 * Captures raw flux transitions for specified number of revolutions.
 * Callback is invoked when data is available or capture completes.
 *
 * @param drive         Drive number (0-1)
 * @param track         Track to capture
 * @param revolutions   Number of revolutions (1-255)
 * @param callback      Callback for flux data
 * @return HAL_OK on success, error code otherwise
 */
int hal_start_flux_capture(uint8_t drive, uint8_t track,
                           uint8_t revolutions, flux_cb_t callback);

/**
 * Stop flux capture
 *
 * @param drive     Drive number (0-1)
 * @return HAL_OK on success, error code otherwise
 */
int hal_stop_flux_capture(uint8_t drive);

/**
 * Check if disk is present in drive
 *
 * @param drive     Drive number (0-1)
 * @return true if disk present, false otherwise
 */
bool hal_disk_present(uint8_t drive);

/**
 * Check if disk is write protected
 *
 * @param drive     Drive number (0-1)
 * @return true if write protected, false otherwise
 */
bool hal_write_protected(uint8_t drive);

/**
 * Reset FDC controller
 * Performs software reset of the FDC.
 *
 * @return HAL_OK on success, error code otherwise
 */
int hal_reset(void);

/*============================================================================
 * Low-Level Register Access (for advanced use)
 *============================================================================*/

/**
 * Wait for FDC to be ready for command
 *
 * @param timeout_ms    Timeout in milliseconds
 * @return HAL_OK if ready, error code otherwise
 */
int hal_wait_ready(uint32_t timeout_ms);

/**
 * Send command byte to FDC
 *
 * @param cmd       Command byte
 * @return HAL_OK on success, error code otherwise
 */
int hal_send_cmd(uint8_t cmd);

/**
 * Read result byte from FDC
 *
 * @param result    Pointer to store result byte
 * @return HAL_OK on success, error code otherwise
 */
int hal_read_result(uint8_t *result);

#endif /* FLUXRIPPER_HAL_H */
