/**
 * FluxRipper System HAL
 *
 * Hardware abstraction for system-level diagnostics:
 * - Drive detection and status
 * - Version/build information
 * - Uptime and statistics
 * - Clock monitoring
 * - I2C bus diagnostics
 * - Temperature sensors
 * - GPIO state
 * - Memory diagnostics
 *
 * Created: 2025-12-07 13:30
 * License: BSD-3-Clause
 */

#ifndef SYSTEM_HAL_H
#define SYSTEM_HAL_H

#include <stdint.h>
#include <stdbool.h>

/*============================================================================
 * Version Information
 *============================================================================*/

/* Build-time constants (set by build system) */
#ifndef FIRMWARE_VERSION_MAJOR
#define FIRMWARE_VERSION_MAJOR   1
#endif
#ifndef FIRMWARE_VERSION_MINOR
#define FIRMWARE_VERSION_MINOR   3
#endif
#ifndef FIRMWARE_VERSION_PATCH
#define FIRMWARE_VERSION_PATCH   0
#endif
#ifndef FIRMWARE_BUILD_DATE
#define FIRMWARE_BUILD_DATE      "2025-12-07"
#endif
#ifndef FIRMWARE_BUILD_TIME
#define FIRMWARE_BUILD_TIME      "13:30:00"
#endif
#ifndef FIRMWARE_GIT_HASH
#define FIRMWARE_GIT_HASH        "unknown"
#endif
#ifndef FIRMWARE_GIT_BRANCH
#define FIRMWARE_GIT_BRANCH      "main"
#endif

typedef struct {
    uint8_t  major;
    uint8_t  minor;
    uint8_t  patch;
    char     build_date[12];      /* YYYY-MM-DD */
    char     build_time[10];      /* HH:MM:SS */
    char     git_hash[12];        /* Short hash */
    char     git_branch[32];
    bool     git_dirty;           /* Uncommitted changes */
} version_info_t;

typedef struct {
    uint32_t device_id;           /* FPGA device ID (IDCODE) */
    uint32_t bitstream_id;        /* User-defined bitstream ID */
    char     bitstream_date[12];  /* Build date */
    uint32_t bitstream_crc;       /* Bitstream CRC */
    bool     config_done;         /* Configuration complete */
    bool     init_done;           /* Initialization complete */
} fpga_info_t;

/*============================================================================
 * Drive Status
 *============================================================================*/

typedef enum {
    DRIVE_TYPE_NONE = 0,
    DRIVE_TYPE_FDD_35,            /* 3.5" floppy */
    DRIVE_TYPE_FDD_525,           /* 5.25" floppy */
    DRIVE_TYPE_FDD_8,             /* 8" floppy */
    DRIVE_TYPE_HDD_MFM,           /* MFM hard drive */
    DRIVE_TYPE_HDD_RLL,           /* RLL hard drive */
    DRIVE_TYPE_HDD_ESDI,          /* ESDI hard drive */
    DRIVE_TYPE_UNKNOWN
} drive_type_t;

typedef enum {
    DRIVE_STATE_NOT_PRESENT = 0,
    DRIVE_STATE_PRESENT,          /* Detected but not ready */
    DRIVE_STATE_SPINNING_UP,      /* Motor starting */
    DRIVE_STATE_READY,            /* Ready for operations */
    DRIVE_STATE_SEEKING,          /* Seek in progress */
    DRIVE_STATE_READING,          /* Read in progress */
    DRIVE_STATE_WRITING,          /* Write in progress */
    DRIVE_STATE_ERROR,            /* Error condition */
    DRIVE_STATE_NOT_READY         /* Present but not ready */
} drive_state_t;

typedef struct {
    uint8_t       slot;           /* Physical slot (0-3 FDD, 0-1 HDD) */
    bool          is_fdd;         /* true=FDD, false=HDD */
    drive_type_t  type;           /* Detected drive type */
    drive_state_t state;          /* Current state */
    bool          motor_on;       /* Motor running */
    bool          write_protected;/* Write protect status */
    bool          track0;         /* At track 0 */
    bool          index;          /* Index pulse present */
    uint16_t      current_track;  /* Current head position */
    uint16_t      rpm;            /* Measured RPM (0 if not spinning) */
    /* HDD-specific */
    uint16_t      cylinders;      /* Detected cylinders */
    uint8_t       heads;          /* Detected heads */
    uint8_t       sectors;        /* Sectors per track */
    uint32_t      total_sectors;  /* Total capacity in sectors */
    char          model[32];      /* Drive model (if readable) */
} drive_status_t;

/*============================================================================
 * Uptime and Statistics
 *============================================================================*/

typedef struct {
    uint32_t uptime_seconds;      /* Seconds since boot */
    uint32_t boot_count;          /* Number of boots (stored in NV) */
    /* Operation counts */
    uint32_t tracks_read;         /* Total tracks read */
    uint32_t tracks_written;      /* Total tracks written */
    uint32_t seeks_performed;     /* Total seeks */
    uint32_t bytes_transferred;   /* Total USB bytes (in KB) */
    uint32_t captures_completed;  /* Flux captures completed */
    /* Session stats */
    uint32_t session_errors;      /* Errors this session */
    uint32_t session_retries;     /* Retries this session */
} uptime_stats_t;

/*============================================================================
 * Clock Monitoring
 *============================================================================*/

typedef enum {
    CLK_SYS_100MHZ = 0,           /* System clock */
    CLK_USB_60MHZ,                /* ULPI clock */
    CLK_CAPTURE_200MHZ,           /* Flux capture clock */
    CLK_CAPTURE_300MHZ,           /* HDD capture clock */
    CLK_REF_25MHZ,                /* Reference oscillator */
    CLK_COUNT
} clock_id_t;

typedef struct {
    clock_id_t id;
    const char *name;
    uint32_t   nominal_hz;        /* Expected frequency */
    uint32_t   measured_hz;       /* Measured frequency */
    int16_t    ppm_offset;        /* Offset from nominal */
    bool       pll_locked;        /* PLL lock status */
    bool       present;           /* Clock detected */
} clock_status_t;

/*============================================================================
 * I2C Diagnostics
 *============================================================================*/

#define I2C_BUS_COUNT       2
#define I2C_MAX_DEVICES     16

typedef struct {
    uint8_t  address;             /* 7-bit address */
    bool     present;             /* Device responded */
    char     name[16];            /* Known device name */
} i2c_device_t;

typedef struct {
    uint8_t      bus_id;          /* Bus number (0 or 1) */
    bool         bus_ok;          /* Bus operational */
    uint32_t     clock_hz;        /* Bus clock speed */
    uint32_t     tx_count;        /* Transactions completed */
    uint32_t     error_count;     /* Bus errors */
    uint32_t     nak_count;       /* NAK responses */
    uint32_t     timeout_count;   /* Timeouts */
    uint8_t      device_count;    /* Devices found */
    i2c_device_t devices[I2C_MAX_DEVICES];
} i2c_bus_status_t;

/*============================================================================
 * Temperature Sensors
 *============================================================================*/

typedef enum {
    TEMP_SENSOR_FPGA = 0,         /* FPGA internal (XADC) */
    TEMP_SENSOR_BOARD,            /* Board temperature */
    TEMP_SENSOR_USB_PHY,          /* USB PHY (if available) */
    TEMP_SENSOR_COUNT
} temp_sensor_id_t;

typedef struct {
    temp_sensor_id_t id;
    const char      *name;
    bool             present;     /* Sensor available */
    int16_t          temp_c;      /* Temperature in 0.1°C units */
    int16_t          min_c;       /* Minimum observed */
    int16_t          max_c;       /* Maximum observed */
    int16_t          warning_c;   /* Warning threshold */
    int16_t          critical_c;  /* Critical threshold */
    bool             warning;     /* Above warning threshold */
    bool             critical;    /* Above critical threshold */
} temp_status_t;

/*============================================================================
 * GPIO State
 *============================================================================*/

typedef struct {
    /* FDD control signals */
    uint8_t  fdd_drive_sel;       /* Drive select (active low, bits 0-3) */
    bool     fdd_motor_on;        /* Motor enable */
    bool     fdd_direction;       /* Step direction */
    bool     fdd_step;            /* Step pulse */
    bool     fdd_write_gate;      /* Write gate */
    bool     fdd_side_sel;        /* Side select */
    /* FDD status signals */
    bool     fdd_index;           /* Index pulse */
    bool     fdd_track0;          /* Track 0 */
    bool     fdd_write_protect;   /* Write protect */
    bool     fdd_ready;           /* Drive ready */
    bool     fdd_disk_change;     /* Disk changed */
    /* HDD control signals */
    uint8_t  hdd_drive_sel;       /* Drive select */
    bool     hdd_direction;       /* Step direction */
    bool     hdd_step;            /* Step pulse */
    bool     hdd_write_gate;      /* Write gate */
    uint8_t  hdd_head_sel;        /* Head select (bits) */
    /* HDD status signals */
    bool     hdd_index;           /* Index pulse */
    bool     hdd_track0;          /* Track 0 */
    bool     hdd_write_fault;     /* Write fault */
    bool     hdd_seek_complete;   /* Seek complete */
    bool     hdd_ready;           /* Drive ready */
    /* USB PHY signals */
    bool     usb_vbus;            /* VBUS present */
    bool     usb_id;              /* ID pin state */
    bool     usb_suspend;         /* Suspend state */
    /* Power control */
    uint8_t  pwr_enable;          /* Connector enables (bits 0-5) */
    bool     pwr_8inch_mode;      /* 24V mode active */
    /* LEDs */
    uint8_t  led_state;           /* LED states */
} gpio_state_t;

/*============================================================================
 * Memory Diagnostics
 *============================================================================*/

typedef struct {
    /* BRAM usage */
    uint32_t bram_total_kb;       /* Total BRAM (KB) */
    uint32_t bram_used_kb;        /* Used BRAM (KB) */
    /* Buffer allocations */
    uint32_t flux_buffer_kb;      /* Flux capture buffer */
    uint32_t sector_buffer_kb;    /* Sector buffer */
    uint32_t usb_buffer_kb;       /* USB buffers */
    uint32_t log_buffer_kb;       /* USB logger buffer */
    /* DDR (if present) */
    bool     ddr_present;
    uint32_t ddr_total_mb;
    uint32_t ddr_free_mb;
    /* Health */
    bool     bram_test_pass;      /* BRAM self-test result */
    uint32_t bram_ecc_errors;     /* ECC errors (if supported) */
} memory_status_t;

/*============================================================================
 * API Functions
 *============================================================================*/

/* Initialization */
int sys_init(void);

/* Version Information */
void sys_get_version(version_info_t *ver);
void sys_get_fpga_info(fpga_info_t *info);

/* Drive Status */
int sys_get_drive_count(bool is_fdd);
int sys_get_drive_status(bool is_fdd, uint8_t slot, drive_status_t *status);
const char* sys_drive_type_name(drive_type_t type);
const char* sys_drive_state_name(drive_state_t state);

/* Uptime and Statistics */
void sys_get_uptime(uptime_stats_t *stats);
uint32_t sys_get_uptime_seconds(void);
void sys_reset_session_stats(void);

/* Clock Monitoring */
int sys_get_clock_status(clock_id_t clk, clock_status_t *status);
int sys_get_all_clocks(clock_status_t *clocks, uint8_t max_count);
bool sys_all_clocks_locked(void);

/* I2C Diagnostics */
int sys_i2c_scan(uint8_t bus_id, i2c_bus_status_t *status);
int sys_i2c_get_stats(uint8_t bus_id, i2c_bus_status_t *status);
void sys_i2c_reset_stats(uint8_t bus_id);

/* Temperature */
int sys_get_temperature(temp_sensor_id_t sensor, temp_status_t *status);
int sys_get_all_temperatures(temp_status_t *temps, uint8_t max_count);
int16_t sys_get_fpga_temp_c(void);  /* Quick access to FPGA temp */

/* GPIO */
void sys_get_gpio_state(gpio_state_t *state);

/* Memory */
void sys_get_memory_status(memory_status_t *status);
int sys_run_memory_test(void);

#endif /* SYSTEM_HAL_H */
