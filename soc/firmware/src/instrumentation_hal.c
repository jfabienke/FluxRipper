/**
 * FluxRipper Instrumentation HAL - Implementation
 *
 * Created: 2025-12-04 13:30
 */

#include "instrumentation_hal.h"
#include "platform.h"

/*============================================================================
 * Constants
 *============================================================================*/

static const char *seek_bucket_names[8] = {
    "0-1 cyl",
    "2-10 cyl",
    "11-25 cyl",
    "26-50 cyl",
    "51-100 cyl",
    "101-200 cyl",
    "201-500 cyl",
    "501+ cyl"
};

static const char *error_names[] = {
    "CRC Data",
    "CRC Addr",
    "Missing AM",
    "Missing DAM",
    "Overrun",
    "Underrun",
    "Seek",
    "Write Fault",
    "PLL Unlock"
};

/*============================================================================
 * Initialization
 *============================================================================*/

int diag_init(void)
{
    /* Clear all statistics on init */
    diag_clear_all();
    return DIAG_OK;
}

/*============================================================================
 * Error Counter Functions
 *============================================================================*/

int diag_read_errors(diag_errors_t *errors)
{
    if (!errors) return DIAG_ERR_INVALID;

    errors->crc_data    = DIAG_ERR_CRC_DATA;
    errors->crc_addr    = DIAG_ERR_CRC_ADDR;
    errors->missing_am  = DIAG_ERR_MISSING_AM;
    errors->missing_dam = DIAG_ERR_MISSING_DAM;
    errors->overrun     = DIAG_ERR_OVERRUN;
    errors->underrun    = DIAG_ERR_UNDERRUN;
    errors->seek        = DIAG_ERR_SEEK;
    errors->write_fault = DIAG_ERR_WRITE_FAULT;
    errors->pll_unlock  = DIAG_ERR_PLL_UNLOCK;
    errors->total       = DIAG_ERR_TOTAL;
    errors->error_rate  = (uint8_t)(DIAG_ERR_RATE & 0xFF);

    return DIAG_OK;
}

int diag_clear_errors(void)
{
    DIAG_ERR_CTRL = 0x01;  /* Clear all bit */
    return DIAG_OK;
}

/*============================================================================
 * PLL Diagnostic Functions
 *============================================================================*/

int diag_read_pll(diag_pll_t *pll)
{
    if (!pll) return DIAG_ERR_INVALID;

    uint32_t phase = DIAG_PLL_PHASE_ERR;
    pll->phase_error = (int16_t)(phase & 0xFFFF);

    uint32_t avg_peak = DIAG_PLL_PHASE_AVG;
    pll->phase_avg = (int16_t)(avg_peak & 0xFFFF);
    pll->phase_peak = (int16_t)((DIAG_PLL_PHASE_PEAK) & 0xFFFF);

    pll->freq_word = DIAG_PLL_FREQ_WORD;
    pll->freq_offset_ppm = (int32_t)DIAG_PLL_FREQ_PPM;

    pll->lock_time = DIAG_PLL_LOCK_TIME;
    pll->total_lock_time = DIAG_PLL_TOTAL_LOCK;
    pll->unlock_count = DIAG_PLL_UNLOCK_CNT;

    uint32_t quality = DIAG_PLL_QUALITY;
    pll->quality_min = (uint8_t)(quality & 0xFF);
    pll->quality_max = (uint8_t)((quality >> 8) & 0xFF);
    pll->quality_avg = (uint8_t)((quality >> 16) & 0xFF);

    /* Read histogram (packed 2 per register) */
    uint32_t hist01 = DIAG_PLL_HIST_01;
    uint32_t hist23 = DIAG_PLL_HIST_23;
    uint32_t hist45 = DIAG_PLL_HIST_45;
    uint32_t hist67 = DIAG_PLL_HIST_67;

    pll->histogram[0] = (uint16_t)(hist01 & 0xFFFF);
    pll->histogram[1] = (uint16_t)(hist01 >> 16);
    pll->histogram[2] = (uint16_t)(hist23 & 0xFFFF);
    pll->histogram[3] = (uint16_t)(hist23 >> 16);
    pll->histogram[4] = (uint16_t)(hist45 & 0xFFFF);
    pll->histogram[5] = (uint16_t)(hist45 >> 16);
    pll->histogram[6] = (uint16_t)(hist67 & 0xFFFF);
    pll->histogram[7] = (uint16_t)(hist67 >> 16);

    return DIAG_OK;
}

int diag_snapshot_pll(void)
{
    DIAG_PLL_CTRL = 0x01;  /* Snapshot trigger */
    return DIAG_OK;
}

int diag_clear_pll(void)
{
    DIAG_PLL_CTRL = 0x02;  /* Clear stats */
    return DIAG_OK;
}

/*============================================================================
 * FIFO Statistics Functions
 *============================================================================*/

int diag_read_fifo(diag_fifo_t *fifo)
{
    if (!fifo) return DIAG_ERR_INVALID;

    uint32_t peak = DIAG_FIFO_PEAK;
    fifo->peak_level = (uint16_t)(peak & 0xFFFF);
    fifo->min_level = (uint16_t)(peak >> 16);

    fifo->overflow_count = DIAG_FIFO_OVERFLOW;
    fifo->underrun_count = DIAG_FIFO_UNDERRUN;
    fifo->backpressure_cnt = DIAG_FIFO_BACKPRESS;
    fifo->total_writes = DIAG_FIFO_WRITES;
    fifo->total_reads = DIAG_FIFO_READS;
    fifo->time_at_peak = DIAG_FIFO_TIME_PEAK;
    fifo->time_empty = DIAG_FIFO_TIME_EMPTY;
    fifo->time_full = DIAG_FIFO_TIME_FULL;

    uint32_t util = DIAG_FIFO_UTIL;
    fifo->utilization_pct = (uint8_t)(util & 0xFF);
    fifo->overflow_flag = (util >> 8) & 0x01;
    fifo->underrun_flag = (util >> 9) & 0x01;

    return DIAG_OK;
}

int diag_clear_fifo(void)
{
    DIAG_FIFO_CTRL = 0x01;  /* Clear stats */
    return DIAG_OK;
}

/*============================================================================
 * Capture Timing Functions
 *============================================================================*/

int diag_read_capture(diag_capture_t *capture)
{
    if (!capture) return DIAG_ERR_INVALID;

    capture->duration = DIAG_CAP_DURATION;
    capture->time_to_first_flux = DIAG_CAP_FIRST_FLUX;
    capture->time_to_first_idx = DIAG_CAP_FIRST_IDX;
    capture->index_period_last = DIAG_CAP_IDX_PERIOD;
    capture->index_period_min = DIAG_CAP_IDX_MIN;
    capture->index_period_max = DIAG_CAP_IDX_MAX;
    capture->index_period_avg = DIAG_CAP_IDX_AVG;
    capture->flux_interval_min = DIAG_CAP_FLUX_MIN;
    capture->flux_interval_max = DIAG_CAP_FLUX_MAX;
    capture->flux_count = (uint16_t)(DIAG_CAP_FLUX_CNT & 0xFFFF);

    return DIAG_OK;
}

int diag_clear_capture(void)
{
    DIAG_CAP_CTRL = 0x01;  /* Clear stats */
    return DIAG_OK;
}

/*============================================================================
 * Seek Histogram Functions
 *============================================================================*/

int diag_read_seek(diag_seek_t *seek)
{
    if (!seek) return DIAG_ERR_INVALID;

    /* Read histogram counts */
    for (int i = 0; i < 8; i++) {
        uint32_t val = DIAG_SEEK_HIST(i);
        seek->count[i] = (uint16_t)(val & 0xFFFF);
    }

    /* Read average times per bucket */
    for (int i = 0; i < 8; i++) {
        uint32_t val = DIAG_SEEK_TIME(i);
        seek->time_us[i] = (uint16_t)(val & 0xFFFF);
    }

    seek->total_seeks = DIAG_SEEK_TOTAL;
    seek->total_errors = DIAG_SEEK_ERRORS;

    uint32_t avg = DIAG_SEEK_AVG_TIME;
    seek->avg_time_us = (uint16_t)(avg & 0xFFFF);
    seek->min_time_us = (uint16_t)((avg >> 16) & 0xFFFF);

    /* Max and error breakdown would need additional registers */
    seek->max_time_us = 0;  /* TODO: add register */
    seek->errors_short = 0;
    seek->errors_medium = 0;
    seek->errors_long = 0;

    return DIAG_OK;
}

int diag_clear_seek(void)
{
    DIAG_SEEK_CTRL = 0x01;  /* Clear stats */
    return DIAG_OK;
}

/*============================================================================
 * Aggregate Functions
 *============================================================================*/

int diag_read_all(diag_snapshot_t *snapshot)
{
    if (!snapshot) return DIAG_ERR_INVALID;

    int ret;

    ret = diag_read_errors(&snapshot->errors);
    if (ret != DIAG_OK) return ret;

    ret = diag_read_pll(&snapshot->pll);
    if (ret != DIAG_OK) return ret;

    ret = diag_read_fifo(&snapshot->fifo);
    if (ret != DIAG_OK) return ret;

    ret = diag_read_capture(&snapshot->capture);
    if (ret != DIAG_OK) return ret;

    ret = diag_read_seek(&snapshot->seek);
    if (ret != DIAG_OK) return ret;

    return DIAG_OK;
}

int diag_clear_all(void)
{
    diag_clear_errors();
    diag_clear_pll();
    diag_clear_fifo();
    diag_clear_capture();
    diag_clear_seek();
    return DIAG_OK;
}

/*============================================================================
 * Utility Functions
 *============================================================================*/

uint32_t diag_clocks_to_us(uint32_t clocks, uint32_t clk_mhz)
{
    return clocks / clk_mhz;
}

uint32_t diag_clocks_to_ms(uint32_t clocks, uint32_t clk_mhz)
{
    return clocks / (clk_mhz * 1000);
}

const char *diag_seek_bucket_name(int bucket)
{
    if (bucket < 0 || bucket >= 8) return "Unknown";
    return seek_bucket_names[bucket];
}

const char *diag_error_name(int error_type)
{
    if (error_type < 0 || error_type >= 9) return "Unknown";
    return error_names[error_type];
}
