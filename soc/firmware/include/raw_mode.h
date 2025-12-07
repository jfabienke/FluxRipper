/*-----------------------------------------------------------------------------
 * raw_mode.h
 * USB Vendor-Specific Raw Mode Handler API
 *
 * Created: 2025-12-05 16:40
 *
 * Firmware API for the FluxRipper Raw Mode USB interface.
 *---------------------------------------------------------------------------*/

#ifndef RAW_MODE_H
#define RAW_MODE_H

#include <stdint.h>
#include <stdbool.h>
#include "raw_protocol.h"

/*---------------------------------------------------------------------------
 * Data Structures
 *---------------------------------------------------------------------------*/

/**
 * Raw Mode State
 */
typedef struct {
    bool        initialized;
    bool        capture_active;
    uint8_t     selected_drive;     /* Currently selected drive (0-3) */
    bool        is_fdd;             /* Selected drive is FDD */
    uint8_t     current_track;      /* Current track (FDD only) */
    uint8_t     last_command;       /* Last command received */
    uint8_t     last_error;         /* Last error code */
} raw_mode_state_t;

/*---------------------------------------------------------------------------
 * Initialization
 *---------------------------------------------------------------------------*/

/**
 * Initialize raw mode handler
 * @return 0 on success
 */
int raw_mode_init(void);

/**
 * Reset raw mode state (stop capture, turn off motors)
 */
void raw_mode_reset(void);

/*---------------------------------------------------------------------------
 * Command Processing
 *---------------------------------------------------------------------------*/

/**
 * Process a raw mode command packet
 * @param cmd Command packet (16 bytes)
 * @param response Buffer for response data
 * @param response_len On exit: actual response length
 * @return 0 on success, error code otherwise
 */
int raw_mode_process_command(const raw_cmd_packet_t *cmd,
                             uint8_t *response, uint32_t *response_len);

/*---------------------------------------------------------------------------
 * Individual Command Handlers
 *---------------------------------------------------------------------------*/

/**
 * Handle NOP command - return status
 */
int raw_cmd_nop(uint8_t *response, uint32_t *response_len);

/**
 * Handle GET_INFO command - device information
 */
int raw_cmd_get_info(uint8_t *response, uint32_t *response_len);

/**
 * Handle SELECT_DRIVE command
 * @param drive Drive number (0-3)
 */
int raw_cmd_select_drive(uint8_t drive, uint8_t *response, uint32_t *response_len);

/**
 * Handle MOTOR_CTRL command
 * @param on 1 = motor on, 0 = motor off
 */
int raw_cmd_motor_ctrl(uint8_t on, uint8_t *response, uint32_t *response_len);

/**
 * Handle SEEK command
 * @param track Target track number
 */
int raw_cmd_seek(uint8_t track, uint8_t *response, uint32_t *response_len);

/**
 * Handle CAPTURE_START command
 */
int raw_cmd_capture_start(uint8_t *response, uint32_t *response_len);

/**
 * Handle CAPTURE_STOP command
 */
int raw_cmd_capture_stop(uint8_t *response, uint32_t *response_len);

/**
 * Handle GET_PLL_STATUS command
 */
int raw_cmd_get_pll_status(uint8_t *response, uint32_t *response_len);

/**
 * Handle GET_SIGNAL_QUAL command
 */
int raw_cmd_get_signal_qual(uint8_t *response, uint32_t *response_len);

/**
 * Handle GET_DRIVE_PROFILE command
 */
int raw_cmd_get_drive_profile(uint8_t *response, uint32_t *response_len);

/*---------------------------------------------------------------------------
 * Capture Control
 *---------------------------------------------------------------------------*/

/**
 * Start flux capture
 * @return 0 on success, -1 if already capturing
 */
int raw_mode_capture_start(void);

/**
 * Stop flux capture
 * @return 0 on success
 */
int raw_mode_capture_stop(void);

/**
 * Check if capture is active
 * @return true if capturing
 */
bool raw_mode_is_capturing(void);

/**
 * Get capture statistics
 * @param info Capture info structure to fill
 * @return 0 on success
 */
int raw_mode_get_capture_info(raw_capture_info_t *info);

/*---------------------------------------------------------------------------
 * Flux Data Processing
 *---------------------------------------------------------------------------*/

/**
 * Process a flux data word (called from ISR or polling loop)
 * @param flux_word 32-bit flux data word
 */
void raw_mode_process_flux(uint32_t flux_word);

/*---------------------------------------------------------------------------
 * Status
 *---------------------------------------------------------------------------*/

/**
 * Get current raw mode state
 * @param state State structure to fill
 */
void raw_mode_get_state(raw_mode_state_t *state);

/**
 * Get currently selected drive
 * @return Drive number (0-3)
 */
uint8_t raw_mode_get_selected_drive(void);

/**
 * Check if selected drive is FDD
 * @return true if FDD, false if HDD
 */
bool raw_mode_is_fdd_selected(void);

#endif /* RAW_MODE_H */
