/**
 * FluxRipper HDD HAL Driver - Hardware Abstraction Layer for Hard Drives
 *
 * Provides API for ST-506/ESDI hard drive support with dual-drive capability.
 * Supports MFM, RLL(2,7), and ESDI drives on two independent interfaces.
 *
 * Target: AMD Spartan UltraScale+ SCU35
 * Created: 2025-12-04 09:27:34
 * Updated: 2025-12-04 18:15 - Added ESDI configuration support (GET_DEV_CONFIG)
 */

#ifndef HDD_HAL_H
#define HDD_HAL_H

#include <stdint.h>
#include <stdbool.h>
#include "platform.h"

/*============================================================================
 * Drive Selection Constants
 *============================================================================*/

#define HDD_DRIVE_0         0   /* First HDD (DS0) */
#define HDD_DRIVE_1         1   /* Second HDD (DS1) */
#define HDD_NUM_DRIVES      2   /* Total number of supported drives */

/*============================================================================
 * HDD Register Definitions (Dual-Drive Register Map)
 *============================================================================*/

/* Shared Registers */
#define HDD_CTRL            (HDD_BASE + 0x00)   /* Global control */
#define HDD_TIMING          (HDD_BASE + 0x04)   /* Step rate, settle time */
#define HDD_DATA_RATE       (HDD_BASE + 0x08)   /* Data rate / mode */

/* Drive 0 Registers */
#define HDD0_STATUS         (HDD_BASE + 0x10)   /* Drive 0 status (RO) */
#define HDD0_CMD            (HDD_BASE + 0x14)   /* Drive 0 command (WO) */
#define HDD0_TARGET_CYL     (HDD_BASE + 0x18)   /* Drive 0 target cylinder */
#define HDD0_GEOMETRY       (HDD_BASE + 0x1C)   /* Drive 0 geometry (RO) */
#define HDD0_HEALTH         (HDD_BASE + 0x20)   /* Drive 0 health (RO) */

/* Drive 1 Registers */
#define HDD1_STATUS         (HDD_BASE + 0x30)   /* Drive 1 status (RO) */
#define HDD1_CMD            (HDD_BASE + 0x34)   /* Drive 1 command (WO) */
#define HDD1_TARGET_CYL     (HDD_BASE + 0x38)   /* Drive 1 target cylinder */
#define HDD1_GEOMETRY       (HDD_BASE + 0x3C)   /* Drive 1 geometry (RO) */
#define HDD1_HEALTH         (HDD_BASE + 0x40)   /* Drive 1 health (RO) */

/* Discovery Registers (shared, run on selected drive) */
#define HDD_DISCOVER_CTRL   (HDD_BASE + 0x50)   /* Discovery control */
#define HDD_DISCOVER_STATUS (HDD_BASE + 0x54)   /* Discovery status */
#define HDD_PHY_RESULT      (HDD_BASE + 0x58)   /* PHY probe result */
#define HDD_RATE_RESULT     (HDD_BASE + 0x5C)   /* Rate detection result */

/* Legacy Detection Registers (for interface detection) */
#define HDD_DETECT_CTRL     (HDD_BASE + 0x60)   /* Detection control */
#define HDD_DETECT_STATUS   (HDD_BASE + 0x64)   /* Detection status */
#define HDD_DETECT_RESULT   (HDD_BASE + 0x68)   /* Detection result */
#define HDD_DETECT_SCORES   (HDD_BASE + 0x6C)   /* Evidence scores */

/* Sector Buffer Registers */
#define HDD_SECTOR_CTRL     (HDD_BASE + 0x70)   /* Sector buffer control */
#define HDD_SECTOR_STATUS   (HDD_BASE + 0x74)   /* Sector buffer status */
#define HDD_SECTOR_ADDR     (HDD_BASE + 0x78)   /* Sector buffer address */
#define HDD_SECTOR_DATA     (HDD_BASE + 0x7C)   /* Sector buffer data */

/* Discovery Result Registers (shared) */
#define HDD_DISCOVER_RESULT (HDD_BASE + 0x80)   /* Discovery result */
#define HDD_ENCODE_RESULT   (HDD_BASE + 0x90)   /* Encoding result + ESDI flag */
#define HDD_GEOMETRY_A      (HDD_BASE + 0x94)   /* Heads/cylinders */
#define HDD_GEOMETRY_B      (HDD_BASE + 0x98)   /* SPT/interleave/skew */
#define HDD_QUALITY_REG     (HDD_BASE + 0x9C)   /* Quality score */

/* ESDI Command Registers */
#define HDD_ESDI_CMD_CTRL   (HDD_BASE + 0xA0)   /* ESDI command control */
#define HDD_ESDI_CMD_STATUS (HDD_BASE + 0xA4)   /* ESDI command status */
#define HDD_ESDI_CONFIG_A   (HDD_BASE + 0xA8)   /* ESDI config word A (cylinders) */
#define HDD_ESDI_CONFIG_B   (HDD_BASE + 0xAC)   /* ESDI config word B (heads/SPT) */

/* Helper macro for per-drive register access */
#define HDD_STATUS(drv)     ((drv) == 0 ? HDD0_STATUS : HDD1_STATUS)
#define HDD_CMD(drv)        ((drv) == 0 ? HDD0_CMD : HDD1_CMD)
#define HDD_TARGET_CYL(drv) ((drv) == 0 ? HDD0_TARGET_CYL : HDD1_TARGET_CYL)
#define HDD_GEOMETRY(drv)   ((drv) == 0 ? HDD0_GEOMETRY : HDD1_GEOMETRY)
#define HDD_HEALTH(drv)     ((drv) == 0 ? HDD0_HEALTH : HDD1_HEALTH)

/*============================================================================
 * Register Bit Definitions
 *============================================================================*/

/* HDD_CTRL - Global Control Register */
#define HDD_CTRL_ENABLE         BIT(0)  /* Enable HDD subsystem */
#define HDD_CTRL_MODE_MASK      (0x3 << 1)  /* Mode: 00=MFM, 01=RLL, 10=ESDI */
#define HDD_CTRL_MODE_SHIFT     1
#define HDD_CTRL_RATE_MASK      (0x3 << 3)  /* Data rate select */
#define HDD_CTRL_RATE_SHIFT     3
#define HDD_CTRL_DIFF_MODE      BIT(5)  /* Differential mode */
#define HDD_CTRL_DRIVE0_ACTIVE  BIT(8)  /* Drive 0 active for NCO */
#define HDD_CTRL_DRIVE1_ACTIVE  BIT(9)  /* Drive 1 active for NCO */
#define HDD_CTRL_FLUX_CAPTURE   BIT(12) /* Enable flux capture */
#define HDD_CTRL_DISCOVERY      BIT(13) /* Discovery mode */

/* HDDx_STATUS - Per-Drive Status Register */
#define HDD_STAT_READY          BIT(0)  /* Drive ready */
#define HDD_STAT_SEEK_COMPLETE  BIT(1)  /* Seek complete signal */
#define HDD_STAT_TRACK00        BIT(2)  /* At track 0 */
#define HDD_STAT_WRITE_FAULT    BIT(3)  /* Write fault */
#define HDD_STAT_INDEX          BIT(4)  /* Index pulse */
#define HDD_STAT_SEEK_BUSY      BIT(8)  /* Seek in progress */
#define HDD_STAT_SEEK_DONE      BIT(9)  /* Seek done (one-shot) */
#define HDD_STAT_SEEK_ERROR     BIT(10) /* Seek error */
#define HDD_STAT_CYL_MASK       (0xFFFF << 16) /* Current cylinder */
#define HDD_STAT_CYL_SHIFT      16

/* HDDx_CMD - Per-Drive Command Register */
#define HDD_CMD_SEEK            BIT(0)  /* Start seek */
#define HDD_CMD_RECAL           BIT(1)  /* Recalibrate (seek to 0) */
#define HDD_CMD_READ            BIT(2)  /* Start read */
#define HDD_CMD_WRITE           BIT(3)  /* Start write */
#define HDD_CMD_HEAD_MASK       (0xF << 4)  /* Head select */
#define HDD_CMD_HEAD_SHIFT      4

/* Detection Control Register */
#define DETECT_CTRL_START       BIT(0)  /* Start detection */
#define DETECT_CTRL_ABORT       BIT(1)  /* Abort detection */
#define DETECT_CTRL_FORCE_MASK  (0x7 << 4)  /* Force personality */
#define DETECT_CTRL_FORCE_SHIFT 4
#define DETECT_CTRL_LOCK        BIT(8)  /* Lock personality */

/* Detection Status Register */
#define DETECT_STAT_BUSY        BIT(0)  /* Detection in progress */
#define DETECT_STAT_DONE        BIT(1)  /* Detection complete */
#define DETECT_STAT_ERROR       BIT(2)  /* Detection error */

/* Detection Result Register */
#define DETECT_RESULT_TYPE_MASK     0x07    /* Interface type */
#define DETECT_RESULT_CONFIDENCE    (0xF << 4)  /* Confidence 0-15 */
#define DETECT_RESULT_PHY_MASK      (0x3 << 8)  /* PHY mode */
#define DETECT_RESULT_RATE_MASK     (0x7 << 12) /* Rate code */
#define DETECT_RESULT_FORCED        BIT(15) /* Was forced */

/* Discovery Control Register */
#define DISCOVER_CTRL_START     BIT(0)  /* Start discovery */
#define DISCOVER_CTRL_ABORT     BIT(1)  /* Abort discovery */
#define DISCOVER_CTRL_FULL      BIT(2)  /* Full scan (vs quick) */
#define DISCOVER_CTRL_DRIVE_SEL BIT(8)  /* Drive to discover (0 or 1) */

/* Discovery Status Register */
#define DISCOVER_STAT_BUSY      BIT(0)  /* Discovery in progress */
#define DISCOVER_STAT_DONE      BIT(1)  /* Discovery complete */
#define DISCOVER_STAT_PHASE_MASK (0xF << 4) /* Current phase */

/* Encoding Result Register */
#define ENCODE_RESULT_TYPE_MASK     0x07    /* Encoding type (0-3) */
#define ENCODE_RESULT_ESDI_CONFIG   BIT(7)  /* Geometry from ESDI config */

/* ESDI Command Control Register */
#define ESDI_CMD_START      BIT(0)      /* Start ESDI command */
#define ESDI_CMD_ABORT      BIT(1)      /* Abort ESDI command */
#define ESDI_CMD_OP_MASK    (0xFF << 8) /* Command opcode */
#define ESDI_CMD_OP_SHIFT   8

/* ESDI Command Status Register */
#define ESDI_STAT_BUSY      BIT(0)      /* Command in progress */
#define ESDI_STAT_DONE      BIT(1)      /* Command complete */
#define ESDI_STAT_ERROR     BIT(2)      /* Command error */
#define ESDI_STAT_CONFIG_VALID BIT(3)   /* Config data valid */

/* ESDI Command Opcodes (for reference) */
#define ESDI_CMD_READ           0x01
#define ESDI_CMD_WRITE          0x02
#define ESDI_CMD_SEEK           0x05
#define ESDI_CMD_GET_STATUS     0x08
#define ESDI_CMD_GET_CONFIG     0x09
#define ESDI_CMD_GET_POS        0x0A

/*============================================================================
 * Interface Types
 *============================================================================*/

typedef enum {
    HDD_TYPE_UNKNOWN    = 0,
    HDD_TYPE_FLOPPY     = 1,    /* Detected as floppy (not HDD) */
    HDD_TYPE_MFM        = 2,    /* ST-506 MFM */
    HDD_TYPE_RLL        = 3,    /* ST-506 RLL(2,7) */
    HDD_TYPE_ESDI       = 4     /* ESDI */
} hdd_type_t;

typedef enum {
    HDD_PHY_NONE        = 0,
    HDD_PHY_SE          = 1,    /* Single-ended */
    HDD_PHY_DIFF        = 2     /* Differential */
} hdd_phy_mode_t;

typedef enum {
    HDD_RATE_UNKNOWN    = 0,
    HDD_RATE_5M         = 1,    /* 5 Mbps (MFM) */
    HDD_RATE_7_5M       = 2,    /* 7.5 Mbps (RLL) */
    HDD_RATE_10M        = 3,    /* 10 Mbps (ESDI) */
    HDD_RATE_15M        = 4,    /* 15 Mbps (ESDI) */
    HDD_RATE_20M        = 5,    /* 20 Mbps (ESDI) */
    HDD_RATE_24M        = 6     /* 24 Mbps (ESDI) */
} hdd_rate_t;

typedef enum {
    HDD_ENC_UNKNOWN     = 0,
    HDD_ENC_MFM         = 1,
    HDD_ENC_RLL_2_7     = 2,
    HDD_ENC_ESDI_NRZ    = 3
} hdd_encoding_t;

/*============================================================================
 * Data Structures
 *============================================================================*/

/**
 * HDD Detection Result
 */
typedef struct {
    hdd_type_t      type;           /* Detected interface type */
    hdd_phy_mode_t  phy_mode;       /* PHY mode (SE/DIFF) */
    hdd_rate_t      rate;           /* Detected data rate */
    uint8_t         confidence;     /* Confidence 0-15 */
    bool            was_forced;     /* True if forced, not detected */

    /* Evidence scores */
    uint8_t         score_floppy;
    uint8_t         score_hdd;
    uint8_t         score_st506;
    uint8_t         score_esdi;
    uint8_t         score_mfm;
    uint8_t         score_rll;
} hdd_detection_t;

/**
 * HDD Geometry
 */
typedef struct {
    uint16_t        cylinders;      /* Number of cylinders */
    uint8_t         heads;          /* Number of heads */
    uint8_t         sectors;        /* Sectors per track */
    uint16_t        sector_size;    /* Bytes per sector (typically 512) */
    uint8_t         interleave;     /* Sector interleave factor */
    uint8_t         skew;           /* Track-to-track skew */
    uint32_t        total_sectors;  /* Total sectors */
    uint32_t        capacity_mb;    /* Capacity in MB */
    bool            from_esdi_config; /* Geometry from ESDI GET_DEV_CONFIG */
} hdd_geometry_t;

/**
 * HDD Health Status
 */
typedef struct {
    uint16_t        rpm;            /* Measured RPM */
    uint16_t        rpm_variance;   /* RPM variance (jitter) */
    uint16_t        seek_avg_ms;    /* Average seek time (ms) */
    uint16_t        seek_max_ms;    /* Maximum seek time (ms) */
    uint8_t         signal_quality; /* Signal quality 0-255 */
    uint8_t         error_rate;     /* Error rate metric */
    bool            ready;          /* Drive ready */
    bool            spinning;       /* Spindle running */
} hdd_health_t;

/**
 * ESDI Configuration (from GET_DEV_CONFIG command)
 * Only valid for ESDI drives
 */
typedef struct {
    uint16_t        cylinders;          /* Cylinders reported by drive */
    uint8_t         heads;              /* Heads reported by drive */
    uint8_t         sectors_per_track;  /* SPT reported by drive */
    uint32_t        total_sectors;      /* Total sectors */
    uint8_t         transfer_rate;      /* 0=10M, 1=15M, 2=20M */
    bool            soft_sectored;      /* Drive is soft-sectored */
    bool            fixed_drive;        /* Fixed (non-removable) drive */
    bool            valid;              /* Configuration is valid */
} esdi_config_t;

/**
 * Complete HDD Profile
 */
typedef struct {
    hdd_detection_t detection;
    hdd_geometry_t  geometry;
    hdd_health_t    health;
    esdi_config_t   esdi_config;    /* ESDI-specific config (if applicable) */
    bool            valid;          /* Profile is valid */
} hdd_profile_t;

/*============================================================================
 * HDD HAL API Functions - Dual-Drive Support
 *============================================================================*/

/**
 * Initialize HDD HAL
 *
 * @return HAL_OK on success, error code otherwise
 */
int hdd_hal_init(void);

/**
 * Select active drive for shared operations (NCO, decoder)
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @return HAL_OK on success, error code otherwise
 */
int hdd_select_drive(uint8_t drive);

/**
 * Get currently selected drive
 *
 * @return Current active drive number
 */
uint8_t hdd_get_active_drive(void);

/**
 * Run interface detection (Phase 0) on specified drive
 * Identifies whether connected drive is Floppy, MFM, RLL, or ESDI.
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param result    Pointer to detection result structure
 * @return HAL_OK on success, error code otherwise
 */
int hdd_detect_interface(uint8_t drive, hdd_detection_t *result);

/**
 * Force interface type (skip auto-detection)
 *
 * @param type      Interface type to force
 * @return HAL_OK on success, error code otherwise
 */
int hdd_force_interface(hdd_type_t type);

/**
 * Run full discovery pipeline on specified drive
 * Detects geometry, health metrics, and optimal parameters.
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param profile   Pointer to profile structure to fill
 * @return HAL_OK on success, error code otherwise
 */
int hdd_discover(uint8_t drive, hdd_profile_t *profile);

/**
 * Get HDD profile for specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param profile   Pointer to profile structure to fill
 * @return HAL_OK on success, error code otherwise
 */
int hdd_get_profile(uint8_t drive, hdd_profile_t *profile);

/**
 * Seek to cylinder on specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param cylinder  Target cylinder number
 * @return HAL_OK on success, error code otherwise
 */
int hdd_seek(uint8_t drive, uint16_t cylinder);

/**
 * Select head on specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param head      Head number (0-15)
 * @return HAL_OK on success, error code otherwise
 */
int hdd_select_head(uint8_t drive, uint8_t head);

/**
 * Recalibrate drive (seek to cylinder 0)
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @return HAL_OK on success, error code otherwise
 */
int hdd_recalibrate(uint8_t drive);

/**
 * Read sector from specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param cylinder  Cylinder number
 * @param head      Head number
 * @param sector    Sector number
 * @param buf       Buffer for sector data
 * @return HAL_OK on success, error code otherwise
 */
int hdd_read_sector(uint8_t drive, uint16_t cylinder, uint8_t head,
                    uint8_t sector, void *buf);

/**
 * Read sectors by LBA from specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param lba       Logical block address
 * @param count     Number of sectors
 * @param buf       Buffer for sector data
 * @return HAL_OK on success, error code otherwise
 */
int hdd_read_lba(uint8_t drive, uint32_t lba, uint32_t count, void *buf);

/**
 * Get drive ready status
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @return true if drive is ready
 */
bool hdd_is_ready(uint8_t drive);

/**
 * Get current cylinder position for specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @return Current cylinder number
 */
uint16_t hdd_get_cylinder(uint8_t drive);

/**
 * Get current head for specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @return Current head number
 */
uint8_t hdd_get_head(uint8_t drive);

/**
 * Get health metrics for specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param health    Pointer to health structure to fill
 * @return HAL_OK on success, error code otherwise
 */
int hdd_get_health(uint8_t drive, hdd_health_t *health);

/**
 * Get status for specified drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param ready     Pointer to receive ready status (can be NULL)
 * @param cylinder  Pointer to receive current cylinder (can be NULL)
 * @param seeking   Pointer to receive seek busy status (can be NULL)
 * @return HAL_OK on success, error code otherwise
 */
int hdd_get_status(uint8_t drive, bool *ready, uint16_t *cylinder, bool *seeking);

/**
 * Set data rate (shared for both drives)
 *
 * @param rate      Data rate selection
 * @return HAL_OK on success, error code otherwise
 */
int hdd_set_rate(hdd_rate_t rate);

/**
 * Set encoding mode (shared for both drives)
 *
 * @param encoding  Encoding selection
 * @return HAL_OK on success, error code otherwise
 */
int hdd_set_encoding(hdd_encoding_t encoding);

/**
 * Enable/disable ESDI termination
 *
 * @param enable    true to enable 100Ω termination
 * @return HAL_OK on success, error code otherwise
 */
int hdd_set_termination(bool enable);

/*============================================================================
 * ESDI-Specific Functions
 *============================================================================*/

/**
 * Query ESDI drive configuration (GET_DEV_CONFIG command)
 * This sends the ESDI GET_DEV_CONFIG command and retrieves drive geometry.
 * Only valid for ESDI drives.
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param config    Pointer to ESDI config structure to fill
 * @return HAL_OK on success, HAL_ERR_NOT_SUPPORTED if not ESDI
 */
int hdd_esdi_get_config(uint8_t drive, esdi_config_t *config);

/**
 * Send raw ESDI command
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @param opcode    ESDI command opcode
 * @param param     Command parameter (cylinder, etc.)
 * @return HAL_OK on success, error code otherwise
 */
int hdd_esdi_command(uint8_t drive, uint8_t opcode, uint16_t param);

/**
 * Wait for ESDI command completion
 *
 * @param timeout_ms    Timeout in milliseconds
 * @return HAL_OK on success, HAL_ERR_TIMEOUT if timeout, HAL_ERR_CMD if error
 */
int hdd_esdi_wait(uint32_t timeout_ms);

/**
 * Check if ESDI configuration is available for drive
 *
 * @param drive     Drive number (HDD_DRIVE_0 or HDD_DRIVE_1)
 * @return true if ESDI config was successfully queried
 */
bool hdd_esdi_config_valid(uint8_t drive);

/*============================================================================
 * Dual-Drive Convenience Functions
 *============================================================================*/

/**
 * Seek both drives simultaneously
 *
 * @param cyl_0     Target cylinder for drive 0
 * @param cyl_1     Target cylinder for drive 1
 * @return HAL_OK on success, error code otherwise
 */
int hdd_seek_both(uint16_t cyl_0, uint16_t cyl_1);

/**
 * Wait for all pending seeks to complete
 *
 * @param timeout_ms    Timeout in milliseconds
 * @return HAL_OK on success, HAL_ERR_TIMEOUT if timeout
 */
int hdd_wait_seeks(uint32_t timeout_ms);

/**
 * Check if any drive is currently seeking
 *
 * @return true if any drive is seeking
 */
bool hdd_any_seeking(void);

/**
 * Get status summary for both drives
 *
 * @param ready_0   Pointer to receive drive 0 ready status
 * @param ready_1   Pointer to receive drive 1 ready status
 * @param cyl_0     Pointer to receive drive 0 cylinder
 * @param cyl_1     Pointer to receive drive 1 cylinder
 * @return HAL_OK on success
 */
int hdd_get_dual_status(bool *ready_0, bool *ready_1,
                        uint16_t *cyl_0, uint16_t *cyl_1);

/*============================================================================
 * Utility Functions
 *============================================================================*/

/**
 * Convert interface type to string
 */
const char *hdd_type_to_string(hdd_type_t type);

/**
 * Convert rate to string
 */
const char *hdd_rate_to_string(hdd_rate_t rate);

/**
 * Convert encoding to string
 */
const char *hdd_encoding_to_string(hdd_encoding_t encoding);

/**
 * Convert CHS to LBA
 */
uint32_t hdd_chs_to_lba(uint16_t cylinder, uint8_t head, uint8_t sector,
                        const hdd_geometry_t *geom);

/**
 * Convert LBA to CHS
 */
void hdd_lba_to_chs(uint32_t lba, uint16_t *cylinder, uint8_t *head,
                    uint8_t *sector, const hdd_geometry_t *geom);

#endif /* HDD_HAL_H */
