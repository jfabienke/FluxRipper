/**
 * FluxStat HAL - Statistical Flux Recovery Hardware Abstraction Layer
 *
 * Provides access to multi-pass flux capture and statistical analysis
 * hardware for recovering marginal/weak sectors.
 *
 * Created: 2025-12-04 18:45
 */

#ifndef FLUXSTAT_HAL_H
#define FLUXSTAT_HAL_H

#include <stdint.h>
#include <stdbool.h>
#include "platform.h"

/*============================================================================
 * FluxStat Register Offsets (from FLUXSTAT_BASE)
 *============================================================================*/

#define FLUXSTAT_BASE           (PERIPH_BASE + 0xB000)

/* Multipass Capture Registers (0x00-0x1C) */
#define FLUXSTAT_MP_CTRL        (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x00))
#define FLUXSTAT_MP_STATUS      (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x04))
#define FLUXSTAT_MP_BASE_ADDR   (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x08))
#define FLUXSTAT_MP_TOTAL_FLUX  (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x0C))
#define FLUXSTAT_MP_MIN_FLUX    (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x10))
#define FLUXSTAT_MP_MAX_FLUX    (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x14))
#define FLUXSTAT_MP_TOTAL_TIME  (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x18))

/* Per-Pass Flux Count Array (0x20-0x9F) - 32 passes */
#define FLUXSTAT_PASS_FLUX(n)   (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x20 + (n)*4))

/* Per-Pass Index Time Array (0xA0-0x11F) - 32 passes */
#define FLUXSTAT_PASS_TIME(n)   (*(volatile uint32_t *)(FLUXSTAT_BASE + 0xA0 + (n)*4))

/* Histogram Registers (0x120-0x13C) */
#define FLUXSTAT_HIST_CTRL      (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x120))
#define FLUXSTAT_HIST_READ_BIN  (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x124))
#define FLUXSTAT_HIST_READ_DATA (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x128))
#define FLUXSTAT_HIST_TOTAL     (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x12C))
#define FLUXSTAT_HIST_MIN       (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x130))
#define FLUXSTAT_HIST_MAX       (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x134))
#define FLUXSTAT_HIST_PEAK_BIN  (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x138))
#define FLUXSTAT_HIST_MEAN      (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x13C))

/* Snapshot Registers (0x140-0x14C) */
#define FLUXSTAT_SNAP_TOTAL     (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x140))
#define FLUXSTAT_SNAP_PEAK_BIN  (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x144))
#define FLUXSTAT_SNAP_PEAK_CNT  (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x148))
#define FLUXSTAT_SNAP_MEAN      (*(volatile uint32_t *)(FLUXSTAT_BASE + 0x14C))

/*============================================================================
 * Register Bit Definitions
 *============================================================================*/

/* MP_CTRL Register */
#define MP_CTRL_START           (1 << 0)    /* Start multipass capture */
#define MP_CTRL_ABORT           (1 << 1)    /* Abort capture */
#define MP_CTRL_PASS_COUNT_SHIFT 2
#define MP_CTRL_PASS_COUNT_MASK (0x3F << 2) /* Pass count (1-64) */

/* MP_STATUS Register */
#define MP_STATUS_BUSY          (1 << 0)    /* Capture in progress */
#define MP_STATUS_DONE          (1 << 1)    /* Capture complete */
#define MP_STATUS_ERROR         (1 << 2)    /* Error occurred */
#define MP_STATUS_CURRENT_SHIFT 8
#define MP_STATUS_CURRENT_MASK  (0x3F << 8) /* Current pass number */
#define MP_STATUS_COMPLETE_SHIFT 16
#define MP_STATUS_COMPLETE_MASK (0x3F << 16) /* Passes completed */

/* HIST_CTRL Register */
#define HIST_CTRL_ENABLE        (1 << 0)    /* Enable histogram */
#define HIST_CTRL_CLEAR         (1 << 1)    /* Clear histogram */
#define HIST_CTRL_SNAPSHOT      (1 << 2)    /* Take snapshot */

/*============================================================================
 * Constants
 *============================================================================*/

#define FLUXSTAT_MAX_PASSES     64          /* Maximum capture passes */
#define FLUXSTAT_MIN_PASSES     2           /* Minimum for statistics */
#define FLUXSTAT_DEFAULT_PASSES 8           /* Default pass count */

#define FLUXSTAT_HIST_BINS      256         /* Histogram bin count */
#define FLUXSTAT_HIST_BIN_SHIFT 2           /* Interval >> shift = bin */

#define FLUXSTAT_PASS_SIZE      0x10000     /* 64KB per pass */

/* Bit cell classifications */
#define BITCELL_STRONG_1        0           /* High confidence "1" */
#define BITCELL_WEAK_1          1           /* Low confidence "1" */
#define BITCELL_STRONG_0        2           /* High confidence "0" */
#define BITCELL_WEAK_0          3           /* Low confidence "0" */
#define BITCELL_AMBIGUOUS       4           /* Cannot determine */

/* Confidence thresholds */
#define CONF_STRONG             90          /* >= 90% = strong */
#define CONF_WEAK               60          /* 60-89% = weak */
#define CONF_AMBIGUOUS          60          /* < 60% = ambiguous */

/*============================================================================
 * Return Codes
 *============================================================================*/

#define FLUXSTAT_OK             0
#define FLUXSTAT_ERR_INVALID    -1          /* Invalid parameter */
#define FLUXSTAT_ERR_BUSY       -2          /* Operation in progress */
#define FLUXSTAT_ERR_TIMEOUT    -3          /* Operation timeout */
#define FLUXSTAT_ERR_OVERFLOW   -4          /* Buffer overflow */
#define FLUXSTAT_ERR_NO_DATA    -5          /* No capture data */
#define FLUXSTAT_ERR_ABORT      -6          /* Operation aborted */

/*============================================================================
 * Data Structures
 *============================================================================*/

/**
 * FluxStat configuration
 */
typedef struct {
    uint8_t  pass_count;            /* Number of capture passes (2-64) */
    uint8_t  confidence_threshold;  /* Minimum confidence for "good" bit (0-100) */
    uint8_t  max_correction_bits;   /* Max bits to try correcting per sector */
    uint8_t  encoding;              /* MFM, FM, GCR, etc. (from fluxripper_hal.h) */
    uint32_t data_rate;             /* Expected data rate in bps */
    bool     use_crc_correction;    /* Enable CRC-guided correction */
    bool     preserve_weak_bits;    /* Preserve weak bit info in output */
} fluxstat_config_t;

/**
 * Per-pass capture metadata
 */
typedef struct {
    uint32_t flux_count;            /* Number of flux transitions */
    uint32_t index_time;            /* Index-to-index time (clocks) */
    uint32_t start_time;            /* Capture start timestamp */
    uint32_t data_size;             /* Bytes written to memory */
    uint32_t base_addr;             /* Memory base address for this pass */
} fluxstat_pass_t;

/**
 * Multipass capture result
 */
typedef struct {
    uint8_t  pass_count;            /* Number of passes captured */
    uint32_t total_flux;            /* Sum of flux counts */
    uint32_t min_flux;              /* Minimum flux count (any pass) */
    uint32_t max_flux;              /* Maximum flux count (any pass) */
    uint32_t total_time;            /* Total capture time (clocks) */
    uint32_t base_addr;             /* Base memory address */
    fluxstat_pass_t passes[FLUXSTAT_MAX_PASSES];
} fluxstat_capture_t;

/**
 * Histogram statistics
 */
typedef struct {
    uint32_t total_count;           /* Total flux transitions */
    uint16_t interval_min;          /* Minimum interval seen */
    uint16_t interval_max;          /* Maximum interval seen */
    uint8_t  peak_bin;              /* Bin with highest count */
    uint16_t peak_count;            /* Count in peak bin */
    uint16_t mean_interval;         /* Mean flux interval */
    uint32_t overflow_count;        /* Intervals above max bin */
} fluxstat_histogram_t;

/**
 * Per-bit analysis result
 */
typedef struct {
    uint8_t  value;                 /* Most likely bit value (0 or 1) */
    uint8_t  confidence;            /* Confidence 0-100% */
    uint8_t  classification;        /* BITCELL_STRONG_1, etc. */
    uint8_t  corrected;             /* Was CRC-corrected */
    uint16_t transition_count;      /* Passes with transition */
    uint16_t timing_stddev;         /* Timing standard deviation */
} fluxstat_bit_t;

/**
 * Sector recovery result
 */
typedef struct {
    uint8_t  data[4096];            /* Recovered sector data */
    uint16_t size;                  /* Sector size in bytes */
    uint8_t  crc_ok;                /* CRC verified */
    uint8_t  confidence_min;        /* Minimum bit confidence */
    uint8_t  confidence_avg;        /* Average bit confidence */
    uint8_t  weak_bit_count;        /* Number of weak bits */
    uint8_t  corrected_count;       /* Bits corrected by CRC guidance */
    uint16_t weak_positions[64];    /* Bit positions of weak bits (first 64) */
} fluxstat_sector_t;

/**
 * Track recovery result
 */
typedef struct {
    uint8_t  sector_count;          /* Total sectors on track */
    uint8_t  sectors_recovered;     /* Fully recovered */
    uint8_t  sectors_partial;       /* Partially recovered */
    uint8_t  sectors_failed;        /* Completely failed */
    uint8_t  track;                 /* Track number */
    uint8_t  head;                  /* Head number */
    uint8_t  overall_confidence;    /* Overall track confidence */
    fluxstat_sector_t sectors[32];  /* Per-sector results */
} fluxstat_track_t;

/**
 * Flux correlation result (for internal use)
 */
typedef struct {
    uint32_t time_mean;             /* Mean transition time */
    uint16_t time_stddev;           /* Standard deviation */
    uint16_t hit_count;             /* Passes with transition */
    uint16_t total_passes;          /* Total passes analyzed */
} fluxstat_correlation_t;

/*============================================================================
 * HAL Functions - Initialization
 *============================================================================*/

/**
 * Initialize FluxStat subsystem
 *
 * @return FLUXSTAT_OK on success
 */
int fluxstat_init(void);

/**
 * Configure FluxStat parameters
 *
 * @param config    Configuration structure
 * @return FLUXSTAT_OK on success
 */
int fluxstat_configure(const fluxstat_config_t *config);

/**
 * Get current configuration
 *
 * @param config    Configuration structure to fill
 * @return FLUXSTAT_OK on success
 */
int fluxstat_get_config(fluxstat_config_t *config);

/*============================================================================
 * HAL Functions - Multi-Pass Capture
 *============================================================================*/

/**
 * Start multi-pass flux capture of a track
 *
 * @param drive     Drive number (0-1)
 * @param track     Track number
 * @param head      Head number (0-1)
 * @return FLUXSTAT_OK on success
 */
int fluxstat_capture_start(uint8_t drive, uint8_t track, uint8_t head);

/**
 * Abort current multi-pass capture
 *
 * @return FLUXSTAT_OK on success
 */
int fluxstat_capture_abort(void);

/**
 * Check if capture is in progress
 *
 * @return true if busy
 */
bool fluxstat_capture_busy(void);

/**
 * Wait for capture to complete
 *
 * @param timeout_ms    Timeout in milliseconds
 * @return FLUXSTAT_OK on success, FLUXSTAT_ERR_TIMEOUT on timeout
 */
int fluxstat_capture_wait(uint32_t timeout_ms);

/**
 * Get capture result after completion
 *
 * @param result    Capture result structure to fill
 * @return FLUXSTAT_OK on success
 */
int fluxstat_capture_result(fluxstat_capture_t *result);

/**
 * Get current capture progress
 *
 * @param current_pass  Current pass number (0-based)
 * @param total_passes  Total passes to capture
 * @return FLUXSTAT_OK on success
 */
int fluxstat_capture_progress(uint8_t *current_pass, uint8_t *total_passes);

/*============================================================================
 * HAL Functions - Histogram
 *============================================================================*/

/**
 * Clear histogram data
 *
 * @return FLUXSTAT_OK on success
 */
int fluxstat_histogram_clear(void);

/**
 * Get histogram statistics
 *
 * @param hist  Histogram structure to fill
 * @return FLUXSTAT_OK on success
 */
int fluxstat_histogram_stats(fluxstat_histogram_t *hist);

/**
 * Read histogram bin value
 *
 * @param bin       Bin index (0-255)
 * @param count     Count value at bin
 * @return FLUXSTAT_OK on success
 */
int fluxstat_histogram_read_bin(uint8_t bin, uint16_t *count);

/**
 * Snapshot current histogram state
 *
 * @return FLUXSTAT_OK on success
 */
int fluxstat_histogram_snapshot(void);

/*============================================================================
 * HAL Functions - Analysis (Firmware Implementation)
 *============================================================================*/

/**
 * Analyze captured flux data and recover track
 *
 * @param result    Track recovery result to fill
 * @return FLUXSTAT_OK on success
 */
int fluxstat_analyze_track(fluxstat_track_t *result);

/**
 * Recover specific sector from captured data
 *
 * @param sector_num    Sector number to recover
 * @param result        Sector result to fill
 * @return FLUXSTAT_OK on success
 */
int fluxstat_recover_sector(uint8_t sector_num, fluxstat_sector_t *result);

/**
 * Get bit-level analysis for range of bits
 *
 * @param bit_offset    Starting bit position
 * @param count         Number of bits to analyze
 * @param bits          Array of bit results (caller allocated)
 * @return FLUXSTAT_OK on success
 */
int fluxstat_get_bit_analysis(uint32_t bit_offset, uint32_t count,
                              fluxstat_bit_t *bits);

/**
 * Calculate confidence score for data buffer
 *
 * @param data          Data buffer
 * @param length        Length in bytes
 * @param min_conf      Minimum bit confidence (output)
 * @param avg_conf      Average bit confidence (output)
 * @return FLUXSTAT_OK on success
 */
int fluxstat_calculate_confidence(const uint8_t *data, uint32_t length,
                                  uint8_t *min_conf, uint8_t *avg_conf);

/*============================================================================
 * HAL Functions - Utilities
 *============================================================================*/

/**
 * Estimate optimal data rate from histogram
 *
 * @param rate_bps  Estimated data rate in bps
 * @return FLUXSTAT_OK on success
 */
int fluxstat_estimate_rate(uint32_t *rate_bps);

/**
 * Get memory address for specific pass data
 *
 * @param pass      Pass number (0-based)
 * @param addr      Memory address (output)
 * @param size      Data size (output)
 * @return FLUXSTAT_OK on success
 */
int fluxstat_get_pass_data(uint8_t pass, uint32_t *addr, uint32_t *size);

/**
 * Convert bit cell classification to string
 *
 * @param classification    BITCELL_* value
 * @return String name
 */
const char *fluxstat_classification_name(uint8_t classification);

/**
 * Calculate RPM from index period
 *
 * @param index_clocks  Index period in clocks
 * @param clk_mhz       Clock frequency in MHz
 * @return RPM value
 */
uint32_t fluxstat_calculate_rpm(uint32_t index_clocks, uint32_t clk_mhz);

#endif /* FLUXSTAT_HAL_H */
