/*-----------------------------------------------------------------------------
 * diagnostics_handler.c
 * FluxRipper Diagnostics Command Handler Implementation
 *
 * Created: 2025-12-05 17:25
 *
 * Implements diagnostic and instrumentation commands for monitoring,
 * analysis, and debug.
 *---------------------------------------------------------------------------*/

#include "diagnostics_handler.h"
#include "diagnostics_protocol.h"
#include "raw_protocol.h"
#include <string.h>

/*---------------------------------------------------------------------------
 * Private Data - Performance Counters
 *---------------------------------------------------------------------------*/

static diag_perf_counters_t perf_counters;
static diag_fifo_stats_t fifo_stats;

/*---------------------------------------------------------------------------
 * Private Data - Signal Statistics
 *---------------------------------------------------------------------------*/

static diag_signal_stats_t signal_stats;
static diag_jitter_stats_t jitter_stats;
static diag_bit_timing_t bit_timing;

/* Histograms */
static diag_histogram_t flux_histogram;
static diag_histogram_t amplitude_histogram;
static diag_histogram_t phase_error_histogram;

/*---------------------------------------------------------------------------
 * Private Data - PLL/Clock
 *---------------------------------------------------------------------------*/

static diag_pll_detailed_t pll_status;
static diag_rpm_stats_t rpm_stats;
static diag_index_timing_t index_timing;

/*---------------------------------------------------------------------------
 * Private Data - Error Log
 *---------------------------------------------------------------------------*/

static diag_error_entry_t error_log[DIAG_ERROR_LOG_SIZE];
static uint32_t error_log_head;
static uint32_t error_log_count;
static uint32_t error_total_count;
static diag_error_entry_t last_error;

/*---------------------------------------------------------------------------
 * Private Data - Trace
 *---------------------------------------------------------------------------*/

#define TRACE_BUFFER_SIZE   256

static diag_trace_config_t trace_config;
static diag_trace_entry_t trace_buffer[TRACE_BUFFER_SIZE];
static uint32_t trace_head;
static uint32_t trace_count;
static bool trace_active;
static bool trigger_armed;
static bool trigger_fired;

/*---------------------------------------------------------------------------
 * Private Data - System
 *---------------------------------------------------------------------------*/

static uint32_t uptime_seconds;
static uint32_t uptime_ms;
static uint32_t reset_count;
static uint32_t power_cycles;
static bool initialized;

/*---------------------------------------------------------------------------
 * Private Functions
 *---------------------------------------------------------------------------*/

static uint32_t get_uptime_ms(void)
{
    /* TODO: Read from hardware timer */
    return uptime_seconds * 1000 + uptime_ms;
}

static void build_response_header(uint8_t *buf, uint8_t status,
                                  uint8_t opcode, uint16_t data_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)buf;
    hdr->signature = RAW_SIGNATURE;
    hdr->status = status;
    hdr->opcode = opcode;
    hdr->data_len = data_len;
}

static void histogram_init(diag_histogram_t *h, uint32_t min, uint32_t max)
{
    memset(h, 0, sizeof(diag_histogram_t));
    h->bin_min = min;
    h->bin_max = max;
    h->bin_width = (max - min) / DIAG_HISTOGRAM_BINS;
    if (h->bin_width == 0) h->bin_width = 1;
}

static void histogram_add(diag_histogram_t *h, uint32_t value)
{
    h->total_samples++;

    if (value < h->bin_min) {
        h->underflow++;
    } else if (value >= h->bin_max) {
        h->overflow++;
    } else {
        uint32_t bin = (value - h->bin_min) / h->bin_width;
        if (bin >= DIAG_HISTOGRAM_BINS) bin = DIAG_HISTOGRAM_BINS - 1;
        h->bins[bin]++;
    }
}

/*---------------------------------------------------------------------------
 * Initialization
 *---------------------------------------------------------------------------*/

int diag_init(void)
{
    memset(&perf_counters, 0, sizeof(perf_counters));
    memset(&fifo_stats, 0, sizeof(fifo_stats));
    memset(&signal_stats, 0, sizeof(signal_stats));
    memset(&jitter_stats, 0, sizeof(jitter_stats));
    memset(&bit_timing, 0, sizeof(bit_timing));
    memset(&pll_status, 0, sizeof(pll_status));
    memset(&rpm_stats, 0, sizeof(rpm_stats));
    memset(&index_timing, 0, sizeof(index_timing));
    memset(error_log, 0, sizeof(error_log));
    memset(&trace_config, 0, sizeof(trace_config));
    memset(trace_buffer, 0, sizeof(trace_buffer));

    /* Initialize histograms with typical ranges */
    histogram_init(&flux_histogram, 1000, 10000);       /* 1-10 us */
    histogram_init(&amplitude_histogram, 0, 2000);      /* 0-2000 mV */
    histogram_init(&phase_error_histogram, 0, 360);     /* 0-360 degrees */

    error_log_head = 0;
    error_log_count = 0;
    error_total_count = 0;
    trace_head = 0;
    trace_count = 0;
    trace_active = false;
    trigger_armed = false;
    trigger_fired = false;

    uptime_seconds = 0;
    uptime_ms = 0;
    reset_count = 0;
    power_cycles = 0;

    initialized = true;
    return 0;
}

void diag_reset(void)
{
    diag_cmd_reset_perf_counters();
    diag_cmd_clear_error_log();
    diag_histogram_reset_all();
    trace_active = false;
    trigger_armed = false;
    trigger_fired = false;
}

/*---------------------------------------------------------------------------
 * Command Dispatcher
 *---------------------------------------------------------------------------*/

int diag_process_command(uint8_t opcode, const uint8_t *params,
                         uint32_t param_len, uint8_t *response,
                         uint32_t *response_len)
{
    switch (opcode) {
        /* System Information */
        case DIAG_CMD_GET_VERSION:
            return diag_cmd_get_version(response, response_len);
        case DIAG_CMD_GET_BUILD_INFO:
            return diag_cmd_get_build_info(response, response_len);
        case DIAG_CMD_GET_UPTIME:
            return diag_cmd_get_uptime(response, response_len);
        case DIAG_CMD_GET_TEMPERATURE:
            return diag_cmd_get_temperature(response, response_len);
        case DIAG_CMD_GET_POWER_STATUS:
            return diag_cmd_get_power_status(response, response_len);
        case DIAG_CMD_SELF_TEST:
            return diag_cmd_self_test(param_len >= 4 ? *(uint32_t*)params : 0xFFFF,
                                      response, response_len);
        case DIAG_CMD_GET_ERROR_LOG:
            return diag_cmd_get_error_log(response, response_len);
        case DIAG_CMD_CLEAR_ERROR_LOG:
            diag_cmd_clear_error_log();
            build_response_header(response, RAW_RSP_OK, opcode, 0);
            *response_len = sizeof(raw_rsp_header_t);
            return 0;

        /* Performance Counters */
        case DIAG_CMD_GET_PERF_COUNTERS:
            return diag_cmd_get_perf_counters(response, response_len);
        case DIAG_CMD_RESET_PERF_COUNTERS:
            diag_cmd_reset_perf_counters();
            build_response_header(response, RAW_RSP_OK, opcode, 0);
            *response_len = sizeof(raw_rsp_header_t);
            return 0;
        case DIAG_CMD_GET_USB_STATS:
            return diag_cmd_get_usb_stats(response, response_len);
        case DIAG_CMD_GET_FIFO_STATS:
            return diag_cmd_get_fifo_stats(response, response_len);

        /* Signal Analysis */
        case DIAG_CMD_GET_SIGNAL_STATS:
            return diag_cmd_get_signal_stats(response, response_len);
        case DIAG_CMD_GET_FLUX_HISTOGRAM:
            return diag_cmd_get_flux_histogram(response, response_len);
        case DIAG_CMD_GET_AMPLITUDE_HIST:
            return diag_cmd_get_amplitude_histogram(response, response_len);
        case DIAG_CMD_GET_JITTER_STATS:
            return diag_cmd_get_jitter_stats(response, response_len);
        case DIAG_CMD_GET_BIT_TIMING:
            return diag_cmd_get_bit_timing(response, response_len);

        /* PLL/Clock */
        case DIAG_CMD_GET_PLL_DETAILED:
            return diag_cmd_get_pll_detailed(response, response_len);
        case DIAG_CMD_GET_RPM_STATS:
            return diag_cmd_get_rpm_stats(response, response_len);
        case DIAG_CMD_GET_INDEX_TIMING:
            return diag_cmd_get_index_timing(response, response_len);

        /* Debug/Trace */
        case DIAG_CMD_SET_TRACE_MASK:
            if (param_len >= 4) {
                diag_cmd_set_trace_mask(*(uint32_t*)params);
            }
            build_response_header(response, RAW_RSP_OK, opcode, 0);
            *response_len = sizeof(raw_rsp_header_t);
            return 0;
        case DIAG_CMD_GET_TRACE_DATA:
            return diag_cmd_get_trace_data(response, response_len);
        case DIAG_CMD_ARM_TRIGGER:
            diag_cmd_arm_trigger();
            build_response_header(response, RAW_RSP_OK, opcode, 0);
            *response_len = sizeof(raw_rsp_header_t);
            return 0;
        case DIAG_CMD_GET_STATE_MACHINE:
            return diag_cmd_get_state_machines(response, response_len);

        default:
            build_response_header(response, RAW_RSP_ERR_INVALID_CMD, opcode, 0);
            *response_len = sizeof(raw_rsp_header_t);
            return -1;
    }
}

/*---------------------------------------------------------------------------
 * System Information Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_version(uint8_t *response, uint32_t *len)
{
    diag_version_info_t *info;

    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_VERSION,
                          sizeof(diag_version_info_t));

    info = (diag_version_info_t *)(response + sizeof(raw_rsp_header_t));

    info->fw_major = 1;
    info->fw_minor = 0;
    info->fw_patch = 0;
    info->fw_build = 1;
    info->hw_major = 1;
    info->hw_minor = 0;
    info->fpga_version = 0x00010000;
    info->fpga_build_date = 20251205;
    strncpy(info->git_hash, "abcd1234", 8);
    info->capabilities = 0x0000FFFF;  /* All features enabled */

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_version_info_t);
    return 0;
}

int diag_cmd_get_build_info(uint8_t *response, uint32_t *len)
{
    diag_build_info_t *info;

    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_BUILD_INFO,
                          sizeof(diag_build_info_t));

    info = (diag_build_info_t *)(response + sizeof(raw_rsp_header_t));

    info->build_timestamp = 1733414400;  /* Example timestamp */
    strncpy(info->build_date, "2025-12-05", 16);
    strncpy(info->build_time, "17:00:00", 16);
    strncpy(info->compiler, "GCC 12.2.0", 16);
    strncpy(info->target, "FluxRipper", 16);
    info->code_size = 128 * 1024;
    info->data_size = 32 * 1024;

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_build_info_t);
    return 0;
}

int diag_cmd_get_uptime(uint8_t *response, uint32_t *len)
{
    diag_uptime_t *info;

    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_UPTIME,
                          sizeof(diag_uptime_t));

    info = (diag_uptime_t *)(response + sizeof(raw_rsp_header_t));

    info->uptime_seconds = uptime_seconds;
    info->uptime_ms = uptime_ms;
    info->reset_count = reset_count;
    info->last_reset_reason = 0;
    info->power_cycles = power_cycles;
    info->total_run_hours = uptime_seconds / 3600;

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_uptime_t);
    return 0;
}

int diag_cmd_get_temperature(uint8_t *response, uint32_t *len)
{
    /* Simple temperature response - just FPGA temp */
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_TEMPERATURE, 4);

    /* TODO: Read actual XADC temperature */
    int16_t temp = 450;  /* 45.0°C */
    response[sizeof(raw_rsp_header_t)] = temp & 0xFF;
    response[sizeof(raw_rsp_header_t) + 1] = (temp >> 8) & 0xFF;
    response[sizeof(raw_rsp_header_t) + 2] = 0;
    response[sizeof(raw_rsp_header_t) + 3] = 0;

    *len = sizeof(raw_rsp_header_t) + 4;
    return 0;
}

int diag_cmd_get_power_status(uint8_t *response, uint32_t *len)
{
    diag_power_status_t *info;

    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_POWER_STATUS,
                          sizeof(diag_power_status_t));

    info = (diag_power_status_t *)(response + sizeof(raw_rsp_header_t));

    /* TODO: Read actual voltages from ADC/XADC */
    info->fpga_temp_c = 450;        /* 45.0°C */
    info->board_temp_c = 350;       /* 35.0°C */
    info->vcc_int_mv = 1000;        /* 1.0V */
    info->vcc_aux_mv = 1800;        /* 1.8V */
    info->vcc_bram_mv = 1000;       /* 1.0V */
    info->v5_rail_mv = 5000;        /* 5.0V */
    info->v3v3_rail_mv = 3300;      /* 3.3V */
    info->v12_rail_mv = 12000;      /* 12.0V */
    info->current_ma = 500;         /* 500mA */
    info->fan_speed_pct = 50;
    info->thermal_throttle = 0;

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_power_status_t);
    return 0;
}

int diag_cmd_self_test(uint32_t test_mask, uint8_t *response, uint32_t *len)
{
    diag_self_test_result_t *result;

    build_response_header(response, RAW_RSP_OK, DIAG_CMD_SELF_TEST,
                          sizeof(diag_self_test_result_t));

    result = (diag_self_test_result_t *)(response + sizeof(raw_rsp_header_t));

    /* TODO: Actually run self-tests */
    result->test_mask = test_mask;
    result->pass_mask = test_mask;  /* All pass for now */
    result->fail_mask = 0;
    result->skip_mask = 0;
    result->duration_ms = 100;
    result->overall_result = 0;     /* Pass */

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_self_test_result_t);
    return 0;
}

int diag_cmd_get_error_log(uint8_t *response, uint32_t *len)
{
    uint32_t count, data_len;

    count = (error_log_count < DIAG_ERROR_LOG_SIZE) ?
            error_log_count : DIAG_ERROR_LOG_SIZE;
    data_len = 4 + count * sizeof(diag_error_entry_t);

    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_ERROR_LOG, data_len);

    /* Write count */
    uint8_t *ptr = response + sizeof(raw_rsp_header_t);
    *(uint32_t *)ptr = count;
    ptr += 4;

    /* Write entries */
    for (uint32_t i = 0; i < count; i++) {
        memcpy(ptr, &error_log[i], sizeof(diag_error_entry_t));
        ptr += sizeof(diag_error_entry_t);
    }

    *len = sizeof(raw_rsp_header_t) + data_len;
    return 0;
}

int diag_cmd_clear_error_log(void)
{
    memset(error_log, 0, sizeof(error_log));
    error_log_head = 0;
    error_log_count = 0;
    /* Note: error_total_count not reset */
    return 0;
}

/*---------------------------------------------------------------------------
 * Performance Counter Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_perf_counters(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_PERF_COUNTERS,
                          sizeof(diag_perf_counters_t));

    memcpy(response + sizeof(raw_rsp_header_t), &perf_counters,
           sizeof(diag_perf_counters_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_perf_counters_t);
    return 0;
}

int diag_cmd_reset_perf_counters(void)
{
    memset(&perf_counters, 0, sizeof(perf_counters));
    return 0;
}

int diag_cmd_get_usb_stats(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_USB_STATS, 32);

    uint8_t *ptr = response + sizeof(raw_rsp_header_t);
    memcpy(ptr, &perf_counters.usb_bytes_rx, 8);
    memcpy(ptr + 8, &perf_counters.usb_bytes_tx, 8);
    memcpy(ptr + 16, &perf_counters.usb_packets_rx, 4);
    memcpy(ptr + 20, &perf_counters.usb_packets_tx, 4);
    memcpy(ptr + 24, &perf_counters.usb_errors, 4);
    memcpy(ptr + 28, &perf_counters.usb_retries, 4);

    *len = sizeof(raw_rsp_header_t) + 32;
    return 0;
}

int diag_cmd_get_fifo_stats(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_FIFO_STATS,
                          sizeof(diag_fifo_stats_t));

    memcpy(response + sizeof(raw_rsp_header_t), &fifo_stats,
           sizeof(diag_fifo_stats_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_fifo_stats_t);
    return 0;
}

/*---------------------------------------------------------------------------
 * Signal Analysis Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_signal_stats(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_SIGNAL_STATS,
                          sizeof(diag_signal_stats_t));

    memcpy(response + sizeof(raw_rsp_header_t), &signal_stats,
           sizeof(diag_signal_stats_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_signal_stats_t);
    return 0;
}

int diag_cmd_get_flux_histogram(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_FLUX_HISTOGRAM,
                          sizeof(diag_histogram_t));

    memcpy(response + sizeof(raw_rsp_header_t), &flux_histogram,
           sizeof(diag_histogram_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_histogram_t);
    return 0;
}

int diag_cmd_get_amplitude_histogram(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_AMPLITUDE_HIST,
                          sizeof(diag_histogram_t));

    memcpy(response + sizeof(raw_rsp_header_t), &amplitude_histogram,
           sizeof(diag_histogram_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_histogram_t);
    return 0;
}

int diag_cmd_get_jitter_stats(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_JITTER_STATS,
                          sizeof(diag_jitter_stats_t));

    memcpy(response + sizeof(raw_rsp_header_t), &jitter_stats,
           sizeof(diag_jitter_stats_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_jitter_stats_t);
    return 0;
}

int diag_cmd_get_bit_timing(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_BIT_TIMING,
                          sizeof(diag_bit_timing_t));

    memcpy(response + sizeof(raw_rsp_header_t), &bit_timing,
           sizeof(diag_bit_timing_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_bit_timing_t);
    return 0;
}

/*---------------------------------------------------------------------------
 * PLL/Clock Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_pll_detailed(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_PLL_DETAILED,
                          sizeof(diag_pll_detailed_t));

    memcpy(response + sizeof(raw_rsp_header_t), &pll_status,
           sizeof(diag_pll_detailed_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_pll_detailed_t);
    return 0;
}

int diag_cmd_get_rpm_stats(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_RPM_STATS,
                          sizeof(diag_rpm_stats_t));

    memcpy(response + sizeof(raw_rsp_header_t), &rpm_stats,
           sizeof(diag_rpm_stats_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_rpm_stats_t);
    return 0;
}

int diag_cmd_get_index_timing(uint8_t *response, uint32_t *len)
{
    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_INDEX_TIMING,
                          sizeof(diag_index_timing_t));

    memcpy(response + sizeof(raw_rsp_header_t), &index_timing,
           sizeof(diag_index_timing_t));

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_index_timing_t);
    return 0;
}

/*---------------------------------------------------------------------------
 * Debug/Trace Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_set_trace_mask(uint32_t mask)
{
    trace_config.trace_mask = mask;
    trace_config.enabled = (mask != 0);
    trace_active = trace_config.enabled;
    return 0;
}

int diag_cmd_get_trace_data(uint8_t *response, uint32_t *len)
{
    uint32_t count = (trace_count < TRACE_BUFFER_SIZE) ?
                     trace_count : TRACE_BUFFER_SIZE;
    uint32_t data_len = 4 + count * sizeof(diag_trace_entry_t);

    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_TRACE_DATA, data_len);

    uint8_t *ptr = response + sizeof(raw_rsp_header_t);
    *(uint32_t *)ptr = count;
    ptr += 4;

    for (uint32_t i = 0; i < count; i++) {
        memcpy(ptr, &trace_buffer[i], sizeof(diag_trace_entry_t));
        ptr += sizeof(diag_trace_entry_t);
    }

    *len = sizeof(raw_rsp_header_t) + data_len;
    return 0;
}

int diag_cmd_arm_trigger(void)
{
    trigger_armed = true;
    trigger_fired = false;
    return 0;
}

int diag_cmd_get_state_machines(uint8_t *response, uint32_t *len)
{
    diag_state_machine_t *state;

    build_response_header(response, RAW_RSP_OK, DIAG_CMD_GET_STATE_MACHINE,
                          sizeof(diag_state_machine_t));

    state = (diag_state_machine_t *)(response + sizeof(raw_rsp_header_t));

    /* TODO: Read actual state machine registers */
    state->usb_state = 0;
    state->msc_state = 0;
    state->scsi_state = 0;
    state->raw_state = 0;
    state->fdd_state = 0;
    state->hdd_state = 0;
    state->pll_state = 0;
    state->capture_state = 0;
    state->flags = 0;

    *len = sizeof(raw_rsp_header_t) + sizeof(diag_state_machine_t);
    return 0;
}

/*---------------------------------------------------------------------------
 * Real-time Updates
 *---------------------------------------------------------------------------*/

void diag_update_usb_rx(uint32_t bytes)
{
    perf_counters.usb_bytes_rx += bytes;
    perf_counters.usb_packets_rx++;
}

void diag_update_usb_tx(uint32_t bytes)
{
    perf_counters.usb_bytes_tx += bytes;
    perf_counters.usb_packets_tx++;
}

void diag_update_dma(uint32_t bytes)
{
    perf_counters.dma_bytes_total += bytes;
    perf_counters.dma_transfers++;
}

void diag_update_sector_read(void)
{
    perf_counters.sectors_read++;
}

void diag_update_sector_write(void)
{
    perf_counters.sectors_written++;
}

void diag_update_seek(bool success)
{
    perf_counters.seeks_total++;
    if (!success) {
        perf_counters.seek_errors++;
    }
}

void diag_update_error(uint8_t source, uint16_t code, uint32_t context)
{
    diag_error_entry_t *entry = &error_log[error_log_head];

    entry->timestamp = get_uptime_ms();
    entry->error_code = code;
    entry->severity = DIAG_SEV_ERROR;
    entry->source = source;
    entry->context[0] = context;
    entry->context[1] = 0;

    error_log_head = (error_log_head + 1) % DIAG_ERROR_LOG_SIZE;
    if (error_log_count < DIAG_ERROR_LOG_SIZE) {
        error_log_count++;
    }
    error_total_count++;

    last_error = *entry;
}

void diag_update_flux_sample(uint32_t flux_word)
{
    uint32_t timestamp = flux_word & FLUX_TIMESTAMP_MASK;

    /* Update signal stats */
    signal_stats.total_transitions++;

    if (flux_word & FLUX_FLAG_INDEX) {
        /* Index pulse handling */
    }

    if (flux_word & FLUX_FLAG_WEAK) {
        signal_stats.weak_bit_count++;
    }

    /* Add to histogram (convert to nanoseconds assuming 5ns/tick) */
    histogram_add(&flux_histogram, timestamp * 5);
}

void diag_update_amplitude(uint16_t amplitude_mv)
{
    histogram_add(&amplitude_histogram, amplitude_mv);

    /* Update running stats */
    if (amplitude_mv < signal_stats.amplitude_min_mv ||
        signal_stats.amplitude_min_mv == 0) {
        signal_stats.amplitude_min_mv = amplitude_mv;
    }
    if (amplitude_mv > signal_stats.amplitude_max_mv) {
        signal_stats.amplitude_max_mv = amplitude_mv;
    }
}

void diag_update_pll_lock(bool locked)
{
    if (locked && !pll_status.locked) {
        pll_status.lock_count++;
    } else if (!locked && pll_status.locked) {
        pll_status.unlock_count++;
    }
    pll_status.locked = locked;
}

void diag_update_index_pulse(uint32_t period_ns)
{
    index_timing.period_ns = period_ns;
    index_timing.pulse_count++;

    if (period_ns < index_timing.min_period_ns ||
        index_timing.min_period_ns == 0) {
        index_timing.min_period_ns = period_ns;
    }
    if (period_ns > index_timing.max_period_ns) {
        index_timing.max_period_ns = period_ns;
    }

    /* Calculate RPM (period in ns -> RPM) */
    if (period_ns > 0) {
        rpm_stats.measured_rpm = (uint16_t)(60000000000ULL / period_ns);
    }
}

void diag_trace_event(uint8_t event_type, uint32_t data0, uint32_t data1)
{
    if (!trace_active) return;

    diag_trace_entry_t *entry = &trace_buffer[trace_head];

    entry->timestamp = get_uptime_ms();
    entry->event_type = event_type;
    entry->flags = 0;
    entry->data_len = 8;
    entry->data[0] = data0;
    entry->data[1] = data1;
    entry->data[2] = 0;
    entry->data[3] = 0;

    trace_head = (trace_head + 1) % TRACE_BUFFER_SIZE;
    if (trace_count < TRACE_BUFFER_SIZE) {
        trace_count++;
    }
}

/*---------------------------------------------------------------------------
 * Histogram Management
 *---------------------------------------------------------------------------*/

void diag_histogram_add_flux(uint32_t timing_ns)
{
    histogram_add(&flux_histogram, timing_ns);
}

void diag_histogram_add_amplitude(uint16_t amplitude_mv)
{
    histogram_add(&amplitude_histogram, amplitude_mv);
}

void diag_histogram_add_phase_error(int16_t error_deg)
{
    histogram_add(&phase_error_histogram, (uint32_t)(error_deg + 180));
}

void diag_histogram_reset_all(void)
{
    histogram_init(&flux_histogram, 1000, 10000);
    histogram_init(&amplitude_histogram, 0, 2000);
    histogram_init(&phase_error_histogram, 0, 360);
}

/*---------------------------------------------------------------------------
 * Status Functions
 *---------------------------------------------------------------------------*/

bool diag_is_tracing(void)
{
    return trace_active;
}

bool diag_trigger_armed(void)
{
    return trigger_armed;
}

bool diag_trigger_fired(void)
{
    return trigger_fired;
}

uint32_t diag_get_error_count(void)
{
    return error_total_count;
}

void diag_get_last_error(uint16_t *code, uint8_t *source, uint32_t *context)
{
    if (code) *code = last_error.error_code;
    if (source) *source = last_error.source;
    if (context) *context = last_error.context[0];
}
