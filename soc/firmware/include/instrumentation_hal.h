/**
 * FluxRipper Instrumentation HAL
 *
 * Provides access to diagnostic counters, statistics, and
 * performance metrics from the FPGA.
 *
 * Created: 2025-12-04 13:30
 */

#ifndef INSTRUMENTATION_HAL_H
#define INSTRUMENTATION_HAL_H

#include <stdint.h>
#include <stdbool.h>
#include "platform.h"

/*============================================================================
 * Instrumentation Register Offsets (from DIAG_BASE)
 *============================================================================*/

#define DIAG_BASE           (PERIPH_BASE + 0xA000)

/* Error Counters (0x00-0x2C) */
#define DIAG_ERR_CRC_DATA   (*(volatile uint32_t *)(DIAG_BASE + 0x00))
#define DIAG_ERR_CRC_ADDR   (*(volatile uint32_t *)(DIAG_BASE + 0x04))
#define DIAG_ERR_MISSING_AM (*(volatile uint32_t *)(DIAG_BASE + 0x08))
#define DIAG_ERR_MISSING_DAM (*(volatile uint32_t *)(DIAG_BASE + 0x0C))
#define DIAG_ERR_OVERRUN    (*(volatile uint32_t *)(DIAG_BASE + 0x10))
#define DIAG_ERR_UNDERRUN   (*(volatile uint32_t *)(DIAG_BASE + 0x14))
#define DIAG_ERR_SEEK       (*(volatile uint32_t *)(DIAG_BASE + 0x18))
#define DIAG_ERR_WRITE_FAULT (*(volatile uint32_t *)(DIAG_BASE + 0x1C))
#define DIAG_ERR_PLL_UNLOCK (*(volatile uint32_t *)(DIAG_BASE + 0x20))
#define DIAG_ERR_TOTAL      (*(volatile uint32_t *)(DIAG_BASE + 0x24))
#define DIAG_ERR_RATE       (*(volatile uint32_t *)(DIAG_BASE + 0x28))
#define DIAG_ERR_CTRL       (*(volatile uint32_t *)(DIAG_BASE + 0x2C))

/* PLL Diagnostics (0x30-0x5C) */
#define DIAG_PLL_PHASE_ERR  (*(volatile uint32_t *)(DIAG_BASE + 0x30))
#define DIAG_PLL_FREQ_WORD  (*(volatile uint32_t *)(DIAG_BASE + 0x34))
#define DIAG_PLL_PHASE_AVG  (*(volatile uint32_t *)(DIAG_BASE + 0x38))
#define DIAG_PLL_PHASE_PEAK (*(volatile uint32_t *)(DIAG_BASE + 0x3C))
#define DIAG_PLL_FREQ_PPM   (*(volatile uint32_t *)(DIAG_BASE + 0x40))
#define DIAG_PLL_LOCK_TIME  (*(volatile uint32_t *)(DIAG_BASE + 0x44))
#define DIAG_PLL_TOTAL_LOCK (*(volatile uint32_t *)(DIAG_BASE + 0x48))
#define DIAG_PLL_UNLOCK_CNT (*(volatile uint32_t *)(DIAG_BASE + 0x4C))
#define DIAG_PLL_QUALITY    (*(volatile uint32_t *)(DIAG_BASE + 0x50))
#define DIAG_PLL_HIST_01    (*(volatile uint32_t *)(DIAG_BASE + 0x54))
#define DIAG_PLL_HIST_23    (*(volatile uint32_t *)(DIAG_BASE + 0x58))
#define DIAG_PLL_HIST_45    (*(volatile uint32_t *)(DIAG_BASE + 0x5C))
#define DIAG_PLL_HIST_67    (*(volatile uint32_t *)(DIAG_BASE + 0x60))
#define DIAG_PLL_CTRL       (*(volatile uint32_t *)(DIAG_BASE + 0x64))

/* FIFO Statistics (0x70-0x9C) */
#define DIAG_FIFO_PEAK      (*(volatile uint32_t *)(DIAG_BASE + 0x70))
#define DIAG_FIFO_OVERFLOW  (*(volatile uint32_t *)(DIAG_BASE + 0x74))
#define DIAG_FIFO_UNDERRUN  (*(volatile uint32_t *)(DIAG_BASE + 0x78))
#define DIAG_FIFO_BACKPRESS (*(volatile uint32_t *)(DIAG_BASE + 0x7C))
#define DIAG_FIFO_WRITES    (*(volatile uint32_t *)(DIAG_BASE + 0x80))
#define DIAG_FIFO_READS     (*(volatile uint32_t *)(DIAG_BASE + 0x84))
#define DIAG_FIFO_TIME_PEAK (*(volatile uint32_t *)(DIAG_BASE + 0x88))
#define DIAG_FIFO_TIME_EMPTY (*(volatile uint32_t *)(DIAG_BASE + 0x8C))
#define DIAG_FIFO_TIME_FULL (*(volatile uint32_t *)(DIAG_BASE + 0x90))
#define DIAG_FIFO_UTIL      (*(volatile uint32_t *)(DIAG_BASE + 0x94))
#define DIAG_FIFO_CTRL      (*(volatile uint32_t *)(DIAG_BASE + 0x98))

/* Capture Timing (0xA0-0xCC) */
#define DIAG_CAP_DURATION   (*(volatile uint32_t *)(DIAG_BASE + 0xA0))
#define DIAG_CAP_FIRST_FLUX (*(volatile uint32_t *)(DIAG_BASE + 0xA4))
#define DIAG_CAP_FIRST_IDX  (*(volatile uint32_t *)(DIAG_BASE + 0xA8))
#define DIAG_CAP_IDX_PERIOD (*(volatile uint32_t *)(DIAG_BASE + 0xAC))
#define DIAG_CAP_IDX_MIN    (*(volatile uint32_t *)(DIAG_BASE + 0xB0))
#define DIAG_CAP_IDX_MAX    (*(volatile uint32_t *)(DIAG_BASE + 0xB4))
#define DIAG_CAP_IDX_AVG    (*(volatile uint32_t *)(DIAG_BASE + 0xB8))
#define DIAG_CAP_FLUX_MIN   (*(volatile uint32_t *)(DIAG_BASE + 0xBC))
#define DIAG_CAP_FLUX_MAX   (*(volatile uint32_t *)(DIAG_BASE + 0xC0))
#define DIAG_CAP_FLUX_CNT   (*(volatile uint32_t *)(DIAG_BASE + 0xC4))
#define DIAG_CAP_CTRL       (*(volatile uint32_t *)(DIAG_BASE + 0xC8))

/* Seek Histogram (0xD0-0x11C) - HDD only */
#define DIAG_SEEK_HIST_BASE (DIAG_BASE + 0xD0)
#define DIAG_SEEK_HIST(n)   (*(volatile uint32_t *)(DIAG_SEEK_HIST_BASE + (n)*4))
#define DIAG_SEEK_TIME_BASE (DIAG_BASE + 0xF0)
#define DIAG_SEEK_TIME(n)   (*(volatile uint32_t *)(DIAG_SEEK_TIME_BASE + (n)*4))
#define DIAG_SEEK_TOTAL     (*(volatile uint32_t *)(DIAG_BASE + 0x110))
#define DIAG_SEEK_ERRORS    (*(volatile uint32_t *)(DIAG_BASE + 0x114))
#define DIAG_SEEK_AVG_TIME  (*(volatile uint32_t *)(DIAG_BASE + 0x118))
#define DIAG_SEEK_CTRL      (*(volatile uint32_t *)(DIAG_BASE + 0x11C))

/*============================================================================
 * Data Structures
 *============================================================================*/

/**
 * Lifetime error counters
 */
typedef struct {
    uint32_t crc_data;          /* CRC errors in data field */
    uint32_t crc_addr;          /* CRC errors in address field */
    uint32_t missing_am;        /* Missing address mark */
    uint32_t missing_dam;       /* Missing data address mark */
    uint32_t overrun;           /* Data overrun */
    uint32_t underrun;          /* Data underrun */
    uint32_t seek;              /* Seek errors */
    uint32_t write_fault;       /* Write faults */
    uint32_t pll_unlock;        /* PLL unlock events */
    uint32_t total;             /* Total errors */
    uint8_t  error_rate;        /* Errors per 1000 operations */
} diag_errors_t;

/**
 * PLL diagnostics
 */
typedef struct {
    int16_t  phase_error;       /* Instantaneous phase error */
    int16_t  phase_avg;         /* Averaged phase error */
    int16_t  phase_peak;        /* Peak phase error seen */
    uint32_t freq_word;         /* NCO frequency word */
    int32_t  freq_offset_ppm;   /* Frequency offset in PPM */
    uint32_t lock_time;         /* Time to achieve lock (clocks) */
    uint32_t total_lock_time;   /* Total time locked */
    uint32_t unlock_count;      /* Number of unlock events */
    uint8_t  quality_min;       /* Minimum lock quality */
    uint8_t  quality_max;       /* Maximum lock quality */
    uint8_t  quality_avg;       /* Average lock quality */
    uint16_t histogram[8];      /* Phase error histogram */
} diag_pll_t;

/**
 * FIFO statistics
 */
typedef struct {
    uint16_t peak_level;        /* Maximum fill level */
    uint16_t min_level;         /* Minimum fill level */
    uint32_t overflow_count;    /* Write attempts when full */
    uint32_t underrun_count;    /* Read attempts when empty */
    uint32_t backpressure_cnt;  /* TREADY deassertions */
    uint32_t total_writes;      /* Total write operations */
    uint32_t total_reads;       /* Total read operations */
    uint32_t time_at_peak;      /* Time at peak level */
    uint32_t time_empty;        /* Time spent empty */
    uint32_t time_full;         /* Time spent full */
    uint8_t  utilization_pct;   /* Average utilization % */
    uint8_t  overflow_flag;     /* Sticky overflow */
    uint8_t  underrun_flag;     /* Sticky underrun */
} diag_fifo_t;

/**
 * Capture timing statistics
 */
typedef struct {
    uint32_t duration;          /* Total capture time (clocks) */
    uint32_t time_to_first_flux;/* Time to first flux */
    uint32_t time_to_first_idx; /* Time to first index */
    uint32_t index_period_last; /* Last index period */
    uint32_t index_period_min;  /* Min index period */
    uint32_t index_period_max;  /* Max index period */
    uint32_t index_period_avg;  /* Avg index period */
    uint32_t flux_interval_min; /* Min flux interval */
    uint32_t flux_interval_max; /* Max flux interval */
    uint16_t flux_count;        /* Total flux transitions */
} diag_capture_t;

/**
 * Seek histogram (HDD)
 */
typedef struct {
    uint16_t count[8];          /* Seek counts by distance bucket */
    uint16_t time_us[8];        /* Average seek time per bucket */
    uint32_t total_seeks;       /* Total seek operations */
    uint32_t total_errors;      /* Total seek errors */
    uint16_t avg_time_us;       /* Overall average seek time */
    uint16_t min_time_us;       /* Minimum seek time */
    uint16_t max_time_us;       /* Maximum seek time */
    uint8_t  errors_short;      /* Errors on short seeks */
    uint8_t  errors_medium;     /* Errors on medium seeks */
    uint8_t  errors_long;       /* Errors on long seeks */
} diag_seek_t;

/**
 * Complete diagnostics snapshot
 */
typedef struct {
    diag_errors_t  errors;
    diag_pll_t     pll;
    diag_fifo_t    fifo;
    diag_capture_t capture;
    diag_seek_t    seek;
} diag_snapshot_t;

/*============================================================================
 * HAL Return Codes
 *============================================================================*/

#define DIAG_OK             0
#define DIAG_ERR_INVALID    -1

/*============================================================================
 * HAL Functions
 *============================================================================*/

/**
 * Initialize instrumentation subsystem
 */
int diag_init(void);

/**
 * Read all error counters
 */
int diag_read_errors(diag_errors_t *errors);

/**
 * Clear all error counters
 */
int diag_clear_errors(void);

/**
 * Read PLL diagnostics
 */
int diag_read_pll(diag_pll_t *pll);

/**
 * Trigger PLL state snapshot
 */
int diag_snapshot_pll(void);

/**
 * Clear PLL statistics
 */
int diag_clear_pll(void);

/**
 * Read FIFO statistics
 */
int diag_read_fifo(diag_fifo_t *fifo);

/**
 * Clear FIFO statistics
 */
int diag_clear_fifo(void);

/**
 * Read capture timing
 */
int diag_read_capture(diag_capture_t *capture);

/**
 * Clear capture timing
 */
int diag_clear_capture(void);

/**
 * Read seek histogram (HDD only)
 */
int diag_read_seek(diag_seek_t *seek);

/**
 * Clear seek histogram
 */
int diag_clear_seek(void);

/**
 * Read complete diagnostics snapshot
 */
int diag_read_all(diag_snapshot_t *snapshot);

/**
 * Clear all diagnostics
 */
int diag_clear_all(void);

/*============================================================================
 * Utility Functions
 *============================================================================*/

/**
 * Convert clocks to microseconds
 */
uint32_t diag_clocks_to_us(uint32_t clocks, uint32_t clk_mhz);

/**
 * Convert clocks to milliseconds
 */
uint32_t diag_clocks_to_ms(uint32_t clocks, uint32_t clk_mhz);

/**
 * Get seek distance bucket name
 */
const char *diag_seek_bucket_name(int bucket);

/**
 * Get error type name
 */
const char *diag_error_name(int error_type);

#endif /* INSTRUMENTATION_HAL_H */
