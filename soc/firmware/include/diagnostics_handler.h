/*-----------------------------------------------------------------------------
 * diagnostics_handler.h
 * FluxRipper Diagnostics Command Handler API
 *
 * Created: 2025-12-05 17:20
 *
 * Processes diagnostic and instrumentation commands for real-time
 * monitoring, signal analysis, and debug capabilities.
 *---------------------------------------------------------------------------*/

#ifndef DIAGNOSTICS_HANDLER_H
#define DIAGNOSTICS_HANDLER_H

#include <stdint.h>
#include <stdbool.h>
#include "diagnostics_protocol.h"

/*---------------------------------------------------------------------------
 * Initialization
 *---------------------------------------------------------------------------*/

/**
 * Initialize diagnostics subsystem
 * @return 0 on success
 */
int diag_init(void);

/**
 * Reset diagnostics state and counters
 */
void diag_reset(void);

/*---------------------------------------------------------------------------
 * Command Processing
 *---------------------------------------------------------------------------*/

/**
 * Process a diagnostics command
 * @param opcode Command opcode (0x80-0xFF)
 * @param params Command parameters
 * @param param_len Parameter length
 * @param response Response buffer
 * @param response_len Response length (in/out)
 * @return 0 on success, error code otherwise
 */
int diag_process_command(uint8_t opcode, const uint8_t *params,
                         uint32_t param_len, uint8_t *response,
                         uint32_t *response_len);

/*---------------------------------------------------------------------------
 * System Information Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_version(uint8_t *response, uint32_t *len);
int diag_cmd_get_build_info(uint8_t *response, uint32_t *len);
int diag_cmd_get_uptime(uint8_t *response, uint32_t *len);
int diag_cmd_get_temperature(uint8_t *response, uint32_t *len);
int diag_cmd_get_power_status(uint8_t *response, uint32_t *len);
int diag_cmd_self_test(uint32_t test_mask, uint8_t *response, uint32_t *len);
int diag_cmd_get_error_log(uint8_t *response, uint32_t *len);
int diag_cmd_clear_error_log(void);

/*---------------------------------------------------------------------------
 * Performance Counter Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_perf_counters(uint8_t *response, uint32_t *len);
int diag_cmd_reset_perf_counters(void);
int diag_cmd_get_usb_stats(uint8_t *response, uint32_t *len);
int diag_cmd_get_dma_stats(uint8_t *response, uint32_t *len);
int diag_cmd_get_fifo_stats(uint8_t *response, uint32_t *len);
int diag_cmd_get_irq_stats(uint8_t *response, uint32_t *len);

/*---------------------------------------------------------------------------
 * Signal Analysis Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_signal_stats(uint8_t *response, uint32_t *len);
int diag_cmd_get_flux_histogram(uint8_t *response, uint32_t *len);
int diag_cmd_get_amplitude_histogram(uint8_t *response, uint32_t *len);
int diag_cmd_get_jitter_stats(uint8_t *response, uint32_t *len);
int diag_cmd_get_bit_timing(uint8_t *response, uint32_t *len);
int diag_cmd_get_weak_bit_map(uint8_t track, uint8_t head,
                              uint8_t *response, uint32_t *len);
int diag_cmd_capture_waveform(const diag_waveform_config_t *config,
                              uint8_t *response, uint32_t *len);
int diag_cmd_get_eye_diagram(uint8_t *response, uint32_t *len);

/*---------------------------------------------------------------------------
 * PLL/Clock Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_pll_detailed(uint8_t *response, uint32_t *len);
int diag_cmd_get_clock_stats(uint8_t *response, uint32_t *len);
int diag_cmd_get_phase_error_histogram(uint8_t *response, uint32_t *len);
int diag_cmd_get_lock_history(uint8_t *response, uint32_t *len);
int diag_cmd_set_pll_params(uint32_t bandwidth, uint32_t damping);
int diag_cmd_get_rpm_stats(uint8_t *response, uint32_t *len);
int diag_cmd_get_index_timing(uint8_t *response, uint32_t *len);

/*---------------------------------------------------------------------------
 * Drive Characterization Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_get_drive_timing(uint8_t drive, uint8_t *response, uint32_t *len);
int diag_cmd_get_head_profile(uint8_t drive, uint8_t *response, uint32_t *len);
int diag_cmd_get_track_profile(uint8_t drive, uint8_t track,
                               uint8_t *response, uint32_t *len);
int diag_cmd_measure_step_time(uint8_t drive, uint8_t *response, uint32_t *len);
int diag_cmd_measure_settle_time(uint8_t drive, uint8_t *response, uint32_t *len);
int diag_cmd_get_motor_profile(uint8_t drive, uint8_t *response, uint32_t *len);
int diag_cmd_measure_eccentricity(uint8_t drive, uint8_t track,
                                  uint8_t *response, uint32_t *len);

/*---------------------------------------------------------------------------
 * Debug/Trace Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_set_trace_mask(uint32_t mask);
int diag_cmd_get_trace_data(uint8_t *response, uint32_t *len);
int diag_cmd_set_trigger(const diag_trace_config_t *config);
int diag_cmd_arm_trigger(void);
int diag_cmd_get_trigger_status(uint8_t *response, uint32_t *len);
int diag_cmd_read_register(uint32_t addr, uint32_t *value);
int diag_cmd_write_register(uint32_t addr, uint32_t value);
int diag_cmd_get_state_machines(uint8_t *response, uint32_t *len);

/*---------------------------------------------------------------------------
 * Calibration Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_run_calibration(uint32_t cal_mask, uint8_t *response, uint32_t *len);
int diag_cmd_get_calibration_data(uint8_t *response, uint32_t *len);
int diag_cmd_set_calibration_data(const uint8_t *data, uint32_t len);
int diag_cmd_save_calibration(void);
int diag_cmd_load_calibration(void);
int diag_cmd_factory_reset(void);

/*---------------------------------------------------------------------------
 * Stress Test Commands
 *---------------------------------------------------------------------------*/

int diag_cmd_stress_usb(uint32_t duration_ms, uint8_t *response, uint32_t *len);
int diag_cmd_stress_dma(uint32_t duration_ms, uint8_t *response, uint32_t *len);
int diag_cmd_stress_seek(uint8_t drive, uint32_t cycles,
                         uint8_t *response, uint32_t *len);
int diag_cmd_stress_rw(uint8_t drive, uint32_t cycles,
                       uint8_t *response, uint32_t *len);
int diag_cmd_loopback_test(uint32_t pattern, uint8_t *response, uint32_t *len);
int diag_cmd_pattern_test(uint32_t pattern, uint32_t length,
                          uint8_t *response, uint32_t *len);

/*---------------------------------------------------------------------------
 * Real-time Updates (called from ISR or main loop)
 *---------------------------------------------------------------------------*/

/**
 * Update performance counters
 */
void diag_update_usb_rx(uint32_t bytes);
void diag_update_usb_tx(uint32_t bytes);
void diag_update_dma(uint32_t bytes);
void diag_update_sector_read(void);
void diag_update_sector_write(void);
void diag_update_seek(bool success);
void diag_update_error(uint8_t source, uint16_t code, uint32_t context);

/**
 * Update signal statistics
 */
void diag_update_flux_sample(uint32_t flux_word);
void diag_update_amplitude(uint16_t amplitude_mv);
void diag_update_pll_lock(bool locked);
void diag_update_index_pulse(uint32_t period_ns);

/**
 * Trace recording
 */
void diag_trace_event(uint8_t event_type, uint32_t data0, uint32_t data1);

/*---------------------------------------------------------------------------
 * Histogram Management
 *---------------------------------------------------------------------------*/

/**
 * Add sample to flux timing histogram
 */
void diag_histogram_add_flux(uint32_t timing_ns);

/**
 * Add sample to amplitude histogram
 */
void diag_histogram_add_amplitude(uint16_t amplitude_mv);

/**
 * Add sample to phase error histogram
 */
void diag_histogram_add_phase_error(int16_t error_deg);

/**
 * Reset all histograms
 */
void diag_histogram_reset_all(void);

/*---------------------------------------------------------------------------
 * Status Functions
 *---------------------------------------------------------------------------*/

/**
 * Get current diagnostics state
 */
bool diag_is_tracing(void);
bool diag_is_capturing_waveform(void);
bool diag_trigger_armed(void);
bool diag_trigger_fired(void);

/**
 * Get error count since last clear
 */
uint32_t diag_get_error_count(void);

/**
 * Get last error info
 */
void diag_get_last_error(uint16_t *code, uint8_t *source, uint32_t *context);

#endif /* DIAGNOSTICS_HANDLER_H */
