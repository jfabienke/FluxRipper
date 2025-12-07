/**
 * FluxRipper WD Controller Emulation - Western Digital AT Controller
 *
 * Emulates WD1003/WD1006/WD1007 compatible hard disk controllers.
 * Provides AT-compatible interface for vintage operating systems.
 *
 * Target: AMD Spartan UltraScale+ SCU35
 * Created: 2025-12-04 21:30
 */

#ifndef WD_EMU_H
#define WD_EMU_H

#include <stdint.h>
#include <stdbool.h>
#include "platform.h"
#include "hdd_hal.h"
#include "hdd_metadata.h"

/*============================================================================
 * WD Controller Base Address and Register Offsets
 *============================================================================*/

#define WD_BASE             0x80007100  /* WD controller base address */

/* Task File Registers (AT-compatible) */
#define WD_DATA             (WD_BASE + 0x00)   /* Data register (16-bit) */
#define WD_ERROR_FEATURES   (WD_BASE + 0x04)   /* Error (R) / Features (W) */
#define WD_SECTOR_COUNT     (WD_BASE + 0x08)   /* Sector count */
#define WD_SECTOR_NUMBER    (WD_BASE + 0x0C)   /* Sector number */
#define WD_CYL_LOW          (WD_BASE + 0x10)   /* Cylinder low byte */
#define WD_CYL_HIGH         (WD_BASE + 0x14)   /* Cylinder high byte */
#define WD_SDH              (WD_BASE + 0x18)   /* Size/Drive/Head */
#define WD_STATUS_CMD       (WD_BASE + 0x1C)   /* Status (R) / Command (W) */
#define WD_ALT_STATUS       (WD_BASE + 0x20)   /* Alt status (no IRQ clear) */

/* Extended Registers */
#define WD_CTRL             (WD_BASE + 0x24)   /* Control/feature flags */
#define WD_BUFFER_ADDR      (WD_BASE + 0x28)   /* Track buffer pointer */
#define WD_BUFFER_DATA      (WD_BASE + 0x2C)   /* Track buffer access */
#define WD_CONFIG           (WD_BASE + 0x30)   /* Variant configuration */
#define WD_GEOMETRY         (WD_BASE + 0x34)   /* Drive geometry (C/H/S) */
#define WD_DIAG_STATUS      (WD_BASE + 0x38)   /* Diagnostic results */
#define WD_VERSION          (WD_BASE + 0x3C)   /* Hardware version */

/* Interrupt Control */
#define WD_IRQ_STATUS       (WD_BASE + 0x40)   /* IRQ status/clear */
#define WD_IRQ_MASK         (WD_BASE + 0x44)   /* IRQ mask */

/*============================================================================
 * Status Register Bits
 *============================================================================*/

#define WD_STATUS_BSY       BIT(7)  /* Busy - controller executing */
#define WD_STATUS_RDY       BIT(6)  /* Ready - drive ready for command */
#define WD_STATUS_WF        BIT(5)  /* Write Fault */
#define WD_STATUS_SC        BIT(4)  /* Seek Complete */
#define WD_STATUS_DRQ       BIT(3)  /* Data Request */
#define WD_STATUS_CORR      BIT(2)  /* Corrected data (ECC) */
#define WD_STATUS_IDX       BIT(1)  /* Index pulse */
#define WD_STATUS_ERR       BIT(0)  /* Error occurred */

/*============================================================================
 * Error Register Bits
 *============================================================================*/

#define WD_ERROR_BBK        BIT(7)  /* Bad Block */
#define WD_ERROR_UNC        BIT(6)  /* Uncorrectable error */
#define WD_ERROR_MC         BIT(5)  /* Media Changed */
#define WD_ERROR_IDNF       BIT(4)  /* ID Not Found */
#define WD_ERROR_MCR        BIT(3)  /* Media Change Request */
#define WD_ERROR_ABRT       BIT(2)  /* Command Aborted */
#define WD_ERROR_TK0NF      BIT(1)  /* Track 0 Not Found */
#define WD_ERROR_AMNF       BIT(0)  /* Address Mark Not Found */

/*============================================================================
 * SDH Register Bits
 *============================================================================*/

#define WD_SDH_SIZE_MASK    (0x7 << 5)  /* Sector size (usually 010 = 512) */
#define WD_SDH_SIZE_SHIFT   5
#define WD_SDH_DRV          BIT(4)      /* Drive select (0 or 1) */
#define WD_SDH_HEAD_MASK    0x0F        /* Head select (0-15) */

/*============================================================================
 * Control Register Bits
 *============================================================================*/

#define WD_CTRL_SRST        BIT(2)  /* Software Reset */
#define WD_CTRL_NIEN        BIT(1)  /* Interrupt Disable */

/*============================================================================
 * Command Codes
 *============================================================================*/

/* Recalibrate commands (0x10-0x1F) */
#define WD_CMD_RESTORE_BASE     0x10    /* Restore (recalibrate) */
#define WD_CMD_RESTORE_MASK     0xF0    /* Mask for RESTORE class */

/* Read commands */
#define WD_CMD_READ_SECTORS     0x20    /* Read sector(s) with retry */
#define WD_CMD_READ_SECTORS_NR  0x21    /* Read sector(s) no retry */
#define WD_CMD_READ_LONG        0x22    /* Read sector + ECC bytes */
#define WD_CMD_READ_LONG_NR     0x23    /* Read long no retry */

/* Write commands */
#define WD_CMD_WRITE_SECTORS    0x30    /* Write sector(s) with retry */
#define WD_CMD_WRITE_SECTORS_NR 0x31    /* Write sector(s) no retry */
#define WD_CMD_WRITE_LONG       0x32    /* Write sector + ECC bytes */
#define WD_CMD_WRITE_LONG_NR    0x33    /* Write long no retry */

/* Verify commands */
#define WD_CMD_VERIFY           0x40    /* Verify sector(s) with retry */
#define WD_CMD_VERIFY_NR        0x41    /* Verify sector(s) no retry */

/* Format command */
#define WD_CMD_FORMAT_TRACK     0x50    /* Format track */

/* Seek commands (0x70-0x7F) */
#define WD_CMD_SEEK_BASE        0x70    /* Seek to cylinder */
#define WD_CMD_SEEK_MASK        0xF0    /* Mask for SEEK class */

/* Diagnostic commands */
#define WD_CMD_EXEC_DIAG        0x90    /* Execute diagnostics */
#define WD_CMD_SET_PARAMS       0x91    /* Set drive parameters */

/* Identify command (WD1007/ESDI) */
#define WD_CMD_IDENTIFY         0xEC    /* Identify drive */

/*============================================================================
 * Controller Variants
 *============================================================================*/

typedef enum {
    WD_VARIANT_1003     = 0,    /* WD1003 - Basic MFM controller */
    WD_VARIANT_1006     = 1,    /* WD1006 - RLL support, diagnostics */
    WD_VARIANT_1007     = 2,    /* WD1007 - ESDI, identify command */
    WD_VARIANT_GENERIC  = 3     /* Generic superset (all features) */
} wd_variant_t;

/*============================================================================
 * Feature Flags
 *============================================================================*/

typedef enum {
    WD_FEAT_NONE            = 0x00000000u,
    WD_FEAT_RLL27           = 0x00000001u,  /* RLL(2,7) encoding support */
    WD_FEAT_BIG_BUFFER      = 0x00000002u,  /* Track buffer enabled */
    WD_FEAT_CORRECTED_STAT  = 0x00000004u,  /* Report ECC corrections */
    WD_FEAT_READ_WRITE_LONG = 0x00000008u,  /* Long commands available */
    WD_FEAT_SET_GET_PARAMS  = 0x00000010u,  /* Geometry commands */
    WD_FEAT_GET_DIAG        = 0x00000020u,  /* Diagnostics command */
    WD_FEAT_GET_ID          = 0x00000040u,  /* Identify command */
    WD_FEAT_ESDI            = 0x00000080u,  /* ESDI mode */
    WD_FEAT_MULTIPLE_SECT   = 0x00000100u   /* Multi-sector transfers */
} wd_feature_t;

/*============================================================================
 * Command State
 *============================================================================*/

typedef enum {
    WD_STATE_IDLE           = 0,
    WD_STATE_COMMAND        = 1,    /* Processing command */
    WD_STATE_DATA_IN        = 2,    /* Waiting for data from host */
    WD_STATE_DATA_OUT       = 3,    /* Data ready for host */
    WD_STATE_DRQ_WAIT       = 4,    /* Waiting for host DRQ ack */
    WD_STATE_SEEK           = 5,    /* Seek in progress */
    WD_STATE_READ           = 6,    /* Reading from disk */
    WD_STATE_WRITE          = 7,    /* Writing to disk */
    WD_STATE_VERIFY         = 8,    /* Verifying sectors */
    WD_STATE_FORMAT         = 9,    /* Formatting track */
    WD_STATE_DIAG           = 10,   /* Running diagnostics */
    WD_STATE_COMPLETE       = 11,   /* Command complete */
    WD_STATE_ERROR          = 12    /* Error state */
} wd_state_t;

/*============================================================================
 * Diagnostic Results
 *============================================================================*/

typedef struct {
    uint8_t     code;           /* Diagnostic result code */
    bool        drive0_ok;      /* Drive 0 passed */
    bool        drive1_ok;      /* Drive 1 passed */
    bool        controller_ok;  /* Controller passed */
    bool        buffer_ok;      /* Track buffer passed */
    uint16_t    error_count;    /* Number of errors detected */
} wd_diag_result_t;

/* Diagnostic result codes */
#define WD_DIAG_OK              0x01    /* No error */
#define WD_DIAG_CTRL_ERROR      0x02    /* Controller error */
#define WD_DIAG_BUFFER_ERROR    0x03    /* Sector buffer error */
#define WD_DIAG_ECC_ERROR       0x04    /* ECC circuitry error */
#define WD_DIAG_UCODE_ERROR     0x05    /* Microcode error */
#define WD_DIAG_DRIVE0_FAIL     0x80    /* Drive 0 failed */
#define WD_DIAG_DRIVE1_FAIL     0x40    /* Drive 1 failed (added to above) */

/*============================================================================
 * Track Buffer Status
 *============================================================================*/

typedef struct {
    uint16_t    current_track;      /* Track currently in buffer */
    uint8_t     current_head;       /* Head currently in buffer */
    uint8_t     buffer_state;       /* 0=empty, 1=clean, 2=dirty */
    uint32_t    valid_bitmap;       /* Which sectors are valid */
    uint32_t    dirty_bitmap;       /* Which sectors need write-back */
    uint16_t    fill_count;         /* Sectors filled */
    uint16_t    flush_count;        /* Sectors flushed */
} wd_buffer_status_t;

/*============================================================================
 * Controller Configuration
 *============================================================================*/

typedef struct {
    wd_variant_t    variant;        /* Controller variant */
    uint32_t        features;       /* Enabled feature flags */
    uint8_t         step_rate;      /* Step rate (ms) */
    uint8_t         head_settle;    /* Head settle time (ms) */
    bool            irq_enabled;    /* Interrupts enabled */
    bool            buffer_enabled; /* Track buffer enabled */
} wd_config_t;

/*============================================================================
 * Controller State
 *============================================================================*/

typedef struct {
    wd_state_t      state;          /* Current command state */
    uint8_t         status;         /* Status register */
    uint8_t         error;          /* Error register */
    uint8_t         command;        /* Current/last command */
    uint8_t         drive;          /* Selected drive (0 or 1) */
    uint8_t         head;           /* Selected head */
    uint16_t        cylinder;       /* Target cylinder */
    uint8_t         sector;         /* Target sector */
    uint8_t         sector_count;   /* Sector count */
    uint16_t        bytes_pending;  /* Bytes pending transfer */
    bool            irq_pending;    /* Interrupt pending */
} wd_controller_state_t;

/*============================================================================
 * WD Emulation API
 *============================================================================*/

/**
 * Initialize WD controller emulation
 *
 * @return HAL_OK on success, error code otherwise
 */
int wd_init(void);

/**
 * Reset WD controller (soft reset)
 *
 * @return HAL_OK on success
 */
int wd_reset(void);

/**
 * Set controller variant
 *
 * @param variant   Controller variant to emulate
 * @return HAL_OK on success
 */
int wd_set_variant(wd_variant_t variant);

/**
 * Get current controller variant
 *
 * @return Current variant
 */
wd_variant_t wd_get_variant(void);

/**
 * Enable/disable feature flags
 *
 * @param features  Feature flags to enable
 * @return HAL_OK on success
 */
int wd_set_features(uint32_t features);

/**
 * Get current feature flags
 *
 * @return Current feature flags
 */
uint32_t wd_get_features(void);

/**
 * Check if feature is enabled
 *
 * @param feature   Feature to check
 * @return true if enabled
 */
bool wd_feature_enabled(wd_feature_t feature);

/**
 * Set drive geometry (for SET_PARAMS command)
 *
 * @param drive     Drive number (0 or 1)
 * @param cylinders Number of cylinders
 * @param heads     Number of heads
 * @param sectors   Sectors per track
 * @return HAL_OK on success
 */
int wd_set_geometry(uint8_t drive, uint16_t cylinders, uint8_t heads, uint8_t sectors);

/**
 * Get configured drive geometry
 *
 * @param drive     Drive number (0 or 1)
 * @param cylinders Pointer to receive cylinders
 * @param heads     Pointer to receive heads
 * @param sectors   Pointer to receive sectors
 * @return HAL_OK on success
 */
int wd_get_geometry(uint8_t drive, uint16_t *cylinders, uint8_t *heads, uint8_t *sectors);

/*============================================================================
 * Register Access (for host interface)
 *============================================================================*/

/**
 * Read WD register
 *
 * @param reg       Register offset (0-7 for task file)
 * @return Register value
 */
uint8_t wd_read_reg(uint8_t reg);

/**
 * Write WD register
 *
 * @param reg       Register offset (0-7 for task file)
 * @param value     Value to write
 */
void wd_write_reg(uint8_t reg, uint8_t value);

/**
 * Read data register (16-bit)
 *
 * @return Data word
 */
uint16_t wd_read_data(void);

/**
 * Write data register (16-bit)
 *
 * @param value     Data word to write
 */
void wd_write_data(uint16_t value);

/*============================================================================
 * Command Processing
 *============================================================================*/

/**
 * Process command (called when command register written)
 * Internal use - called by wd_write_reg()
 *
 * @param cmd       Command code
 * @return HAL_OK on success
 */
int wd_process_command(uint8_t cmd);

/**
 * Poll command completion (call periodically)
 *
 * @return true if command complete
 */
bool wd_poll(void);

/**
 * Get controller state
 *
 * @param state     Pointer to state structure
 * @return HAL_OK on success
 */
int wd_get_state(wd_controller_state_t *state);

/**
 * Abort current command
 *
 * @return HAL_OK on success
 */
int wd_abort_command(void);

/*============================================================================
 * Track Buffer Access
 *============================================================================*/

/**
 * Get track buffer status
 *
 * @param status    Pointer to status structure
 * @return HAL_OK on success
 */
int wd_get_buffer_status(wd_buffer_status_t *status);

/**
 * Force buffer flush (write dirty sectors)
 *
 * @return HAL_OK on success
 */
int wd_flush_buffer(void);

/**
 * Invalidate buffer (discard contents)
 *
 * @return HAL_OK on success
 */
int wd_invalidate_buffer(void);

/*============================================================================
 * Diagnostics
 *============================================================================*/

/**
 * Run controller diagnostics
 *
 * @param result    Pointer to result structure
 * @return HAL_OK on success
 */
int wd_run_diagnostics(wd_diag_result_t *result);

/**
 * Get last diagnostic result
 *
 * @param result    Pointer to result structure
 * @return HAL_OK on success
 */
int wd_get_diag_result(wd_diag_result_t *result);

/*============================================================================
 * Interrupt Management
 *============================================================================*/

/**
 * Enable/disable interrupts
 *
 * @param enable    true to enable interrupts
 * @return HAL_OK on success
 */
int wd_set_irq_enable(bool enable);

/**
 * Check if interrupt is pending
 *
 * @return true if IRQ pending
 */
bool wd_irq_pending(void);

/**
 * Acknowledge interrupt (called when status read)
 */
void wd_irq_ack(void);

/*============================================================================
 * Status Functions
 *============================================================================*/

/**
 * Get status register value
 *
 * @return Status register
 */
uint8_t wd_get_status(void);

/**
 * Get error register value
 *
 * @return Error register
 */
uint8_t wd_get_error(void);

/**
 * Check if controller is busy
 *
 * @return true if busy
 */
bool wd_is_busy(void);

/**
 * Check if data request is pending
 *
 * @return true if DRQ set
 */
bool wd_drq_pending(void);

/*============================================================================
 * Configuration
 *============================================================================*/

/**
 * Get controller configuration
 *
 * @param config    Pointer to config structure
 * @return HAL_OK on success
 */
int wd_get_config(wd_config_t *config);

/**
 * Set controller configuration
 *
 * @param config    Pointer to config structure
 * @return HAL_OK on success
 */
int wd_set_config(const wd_config_t *config);

/*============================================================================
 * Utility Functions
 *============================================================================*/

/**
 * Convert variant to string
 *
 * @param variant   Controller variant
 * @return String name
 */
const char *wd_variant_to_string(wd_variant_t variant);

/**
 * Convert command code to string
 *
 * @param cmd       Command code
 * @return String name
 */
const char *wd_cmd_to_string(uint8_t cmd);

/**
 * Convert state to string
 *
 * @param state     Controller state
 * @return String name
 */
const char *wd_state_to_string(wd_state_t state);

/**
 * Convert error code to string
 *
 * @param error     Error register value
 * @return String description
 */
const char *wd_error_to_string(uint8_t error);

/**
 * Get default features for variant
 *
 * @param variant   Controller variant
 * @return Default feature flags
 */
uint32_t wd_variant_default_features(wd_variant_t variant);

/*============================================================================
 * Identify Drive Response (for WD_CMD_IDENTIFY - 0xEC)
 *============================================================================*/

/**
 * @brief ATA/ESDI Identify Drive response structure
 *
 * This 512-byte structure is returned by the IDENTIFY DRIVE command (0xEC).
 * The fields are populated from FluxRipper metadata when available.
 */
typedef struct __attribute__((packed)) {
    uint16_t config;                /* Word 0: Configuration bits */
    uint16_t cylinders;             /* Word 1: Number of cylinders */
    uint16_t reserved_2;            /* Word 2: Reserved */
    uint16_t heads;                 /* Word 3: Number of heads */
    uint16_t unformatted_bpt;       /* Word 4: Unformatted bytes per track */
    uint16_t unformatted_bps;       /* Word 5: Unformatted bytes per sector */
    uint16_t sectors_per_track;     /* Word 6: Sectors per track */
    uint16_t vendor_7[3];           /* Word 7-9: Vendor specific */
    char     serial_number[20];     /* Word 10-19: Serial number (ASCII) */
    uint16_t buffer_type;           /* Word 20: Buffer type */
    uint16_t buffer_size;           /* Word 21: Buffer size (512-byte units) */
    uint16_t ecc_bytes;             /* Word 22: ECC bytes per sector */
    char     firmware_rev[8];       /* Word 23-26: Firmware revision */
    char     model_number[40];      /* Word 27-46: Model number (ASCII) */
    uint16_t max_multi_sect;        /* Word 47: Max sectors per multi-read */
    uint16_t reserved_48;           /* Word 48: Reserved */
    uint16_t capabilities;          /* Word 49: Capabilities */
    uint16_t reserved_50;           /* Word 50: Reserved */
    uint16_t pio_timing_mode;       /* Word 51: PIO timing mode */
    uint16_t dma_timing_mode;       /* Word 52: DMA timing mode */
    uint16_t field_validity;        /* Word 53: Field validity bits */
    uint16_t cur_cylinders;         /* Word 54: Current cylinders */
    uint16_t cur_heads;             /* Word 55: Current heads */
    uint16_t cur_sectors;           /* Word 56: Current sectors/track */
    uint32_t cur_capacity;          /* Word 57-58: Current capacity (sectors) */
    uint16_t multi_sector_setting;  /* Word 59: Multi-sector setting */
    uint32_t total_sectors_lba;     /* Word 60-61: Total LBA sectors */
    uint16_t reserved_62[194];      /* Word 62-255: Reserved/vendor */
} wd_identify_t;

/**
 * Build IDENTIFY response from FluxRipper metadata
 *
 * Populates the 512-byte identify buffer using:
 *   - User-supplied identity (vendor, model, serial) from metadata
 *   - Discovered geometry (cylinders, heads, SPT) from fingerprint
 *   - FluxRipper-specific extensions in vendor words
 *
 * If metadata is not present, uses default placeholder values.
 *
 * @param drive     Drive number (0 or 1)
 * @param identify  Pointer to identify structure to fill
 * @return HAL_OK on success
 */
int wd_build_identify(uint8_t drive, wd_identify_t *identify);

/**
 * Build IDENTIFY response from explicit metadata
 *
 * Same as wd_build_identify() but takes metadata directly instead
 * of reading from drive.
 *
 * @param meta      Metadata structure (can be NULL for defaults)
 * @param identify  Pointer to identify structure to fill
 * @return HAL_OK on success
 */
int wd_build_identify_from_meta(const hdd_metadata_t *meta, wd_identify_t *identify);

/**
 * Print IDENTIFY response (debug)
 *
 * @param identify  Identify structure to print
 */
void wd_print_identify(const wd_identify_t *identify);

#endif /* WD_EMU_H */
