/*-----------------------------------------------------------------------------
 * raw_mode.c
 * USB Vendor-Specific Raw Mode Handler
 *
 * Created: 2025-12-05 16:35
 *
 * Firmware implementation for the FluxRipper Raw Mode USB interface.
 * Handles flux capture, diagnostics, and low-level drive access.
 *---------------------------------------------------------------------------*/

#include "raw_mode.h"
#include "raw_protocol.h"
#include "fluxripper_hal.h"
#include "hdd_hal.h"
#include <string.h>

/*---------------------------------------------------------------------------
 * Private Data
 *---------------------------------------------------------------------------*/

static raw_mode_state_t raw_state;

/* Capture statistics */
static uint32_t capture_sample_count;
static uint32_t capture_index_count;
static uint32_t capture_overflow_count;
static uint32_t capture_start_time;

/*---------------------------------------------------------------------------
 * Private Functions
 *---------------------------------------------------------------------------*/

static uint32_t get_timestamp_us(void)
{
    /* TODO: Implement actual timestamp from timer */
    return 0;
}

static void build_response_header(raw_rsp_header_t *hdr, uint8_t status,
                                  uint8_t opcode, uint16_t data_len)
{
    hdr->signature = RAW_SIGNATURE;
    hdr->status = status;
    hdr->opcode = opcode;
    hdr->data_len = data_len;
}

/*---------------------------------------------------------------------------
 * Public Functions - Initialization
 *---------------------------------------------------------------------------*/

int raw_mode_init(void)
{
    memset(&raw_state, 0, sizeof(raw_state));

    raw_state.selected_drive = 0;
    raw_state.is_fdd = true;
    raw_state.capture_active = false;

    capture_sample_count = 0;
    capture_index_count = 0;
    capture_overflow_count = 0;
    capture_start_time = 0;

    raw_state.initialized = true;
    return 0;
}

void raw_mode_reset(void)
{
    /* Stop any active capture */
    if (raw_state.capture_active) {
        raw_mode_capture_stop();
    }

    /* Turn off motor */
    if (raw_state.is_fdd) {
        hal_motor_off(raw_state.selected_drive);
    }

    raw_state.capture_active = false;
}

/*---------------------------------------------------------------------------
 * Public Functions - Command Processing
 *---------------------------------------------------------------------------*/

int raw_mode_process_command(const raw_cmd_packet_t *cmd,
                             uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;

    if (cmd == NULL || response == NULL || response_len == NULL) {
        return -1;
    }

    /* Validate signature */
    if (cmd->signature != RAW_SIGNATURE) {
        build_response_header(hdr, RAW_RSP_ERR_INVALID_CMD, cmd->opcode, 0);
        *response_len = sizeof(raw_rsp_header_t);
        return -1;
    }

    raw_state.last_command = cmd->opcode;

    switch (cmd->opcode) {
        case RAW_CMD_NOP:
            return raw_cmd_nop(response, response_len);

        case RAW_CMD_GET_INFO:
            return raw_cmd_get_info(response, response_len);

        case RAW_CMD_SELECT_DRIVE:
            return raw_cmd_select_drive(cmd->param1, response, response_len);

        case RAW_CMD_MOTOR_CTRL:
            return raw_cmd_motor_ctrl(cmd->param1, response, response_len);

        case RAW_CMD_SEEK:
            return raw_cmd_seek(cmd->param1, response, response_len);

        case RAW_CMD_CAPTURE_START:
            return raw_cmd_capture_start(response, response_len);

        case RAW_CMD_CAPTURE_STOP:
            return raw_cmd_capture_stop(response, response_len);

        case RAW_CMD_GET_PLL_STATUS:
            return raw_cmd_get_pll_status(response, response_len);

        case RAW_CMD_GET_SIGNAL_QUAL:
            return raw_cmd_get_signal_qual(response, response_len);

        case RAW_CMD_GET_DRIVE_PROFILE:
            return raw_cmd_get_drive_profile(response, response_len);

        default:
            build_response_header(hdr, RAW_RSP_ERR_INVALID_CMD, cmd->opcode, 0);
            *response_len = sizeof(raw_rsp_header_t);
            return -1;
    }
}

/*---------------------------------------------------------------------------
 * Command Handlers
 *---------------------------------------------------------------------------*/

int raw_cmd_nop(uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;

    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_NOP, 0);
    *response_len = sizeof(raw_rsp_header_t);

    return 0;
}

int raw_cmd_get_info(uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;
    raw_info_data_t *info = (raw_info_data_t *)(response + sizeof(raw_rsp_header_t));

    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_GET_INFO, sizeof(raw_info_data_t));

    info->device_id = 0x464C5558;  /* "FLUX" */
    info->fw_version = 0x0100;     /* v1.0 */
    info->hw_version = 0x0100;     /* v1.0 */
    info->max_luns = 4;
    info->max_fdds = 2;
    info->max_hdds = 2;
    info->reserved1 = 0;

    /* Build status flags */
    info->status_flags = 0;
    if (raw_state.is_fdd) {
        if (hal_disk_present(raw_state.selected_drive)) {
            info->status_flags |= RAW_STATUS_DISK_PRESENT;
        }
        if (hal_write_protected(raw_state.selected_drive)) {
            info->status_flags |= RAW_STATUS_WRITE_PROTECTED;
        }
    } else {
        if (hal_hdd_is_ready(raw_state.selected_drive)) {
            info->status_flags |= RAW_STATUS_HDD_READY;
        }
    }
    if (raw_state.capture_active) {
        info->status_flags |= RAW_STATUS_CAPTURE_ACTIVE;
    }

    info->selected_drive = raw_state.selected_drive;
    info->drive_type = raw_state.is_fdd ? 0 : 1;
    info->current_track = raw_state.current_track;
    info->reserved3 = 0;

    /* Get capacity */
    if (raw_state.is_fdd) {
        info->capacity = 2880;  /* 1.44MB default */
    } else {
        hdd_geometry_t geom;
        if (hal_hdd_get_geometry(raw_state.selected_drive, &geom) == HAL_OK) {
            info->capacity = geom.total_sectors;
        } else {
            info->capacity = 0;
        }
    }

    *response_len = sizeof(raw_rsp_header_t) + sizeof(raw_info_data_t);
    return 0;
}

int raw_cmd_select_drive(uint8_t drive, uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;

    if (drive >= 4) {
        build_response_header(hdr, RAW_RSP_ERR_INVALID_PARAM, RAW_CMD_SELECT_DRIVE, 0);
        *response_len = sizeof(raw_rsp_header_t);
        return -1;
    }

    raw_state.selected_drive = drive;
    raw_state.is_fdd = (drive < 2);

    if (raw_state.is_fdd) {
        hal_select_drive(drive);
    }

    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_SELECT_DRIVE, 0);
    *response_len = sizeof(raw_rsp_header_t);

    return 0;
}

int raw_cmd_motor_ctrl(uint8_t on, uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;

    if (raw_state.is_fdd) {
        if (on) {
            hal_motor_on(raw_state.selected_drive);
        } else {
            hal_motor_off(raw_state.selected_drive);
        }
    }
    /* HDD motors are always on, ignore */

    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_MOTOR_CTRL, 0);
    *response_len = sizeof(raw_rsp_header_t);

    return 0;
}

int raw_cmd_seek(uint8_t track, uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;
    int ret;

    if (!raw_state.is_fdd) {
        build_response_header(hdr, RAW_RSP_ERR_INVALID_CMD, RAW_CMD_SEEK, 0);
        *response_len = sizeof(raw_rsp_header_t);
        return -1;
    }

    ret = hal_seek(raw_state.selected_drive, track);

    if (ret == HAL_OK) {
        raw_state.current_track = track;
        build_response_header(hdr, RAW_RSP_OK, RAW_CMD_SEEK, 0);
    } else {
        build_response_header(hdr, RAW_RSP_ERR_NOT_READY, RAW_CMD_SEEK, 0);
    }

    *response_len = sizeof(raw_rsp_header_t);
    return ret;
}

int raw_cmd_capture_start(uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;

    if (raw_state.capture_active) {
        build_response_header(hdr, RAW_RSP_ERR_BUSY, RAW_CMD_CAPTURE_START, 0);
        *response_len = sizeof(raw_rsp_header_t);
        return -1;
    }

    /* Reset capture statistics */
    capture_sample_count = 0;
    capture_index_count = 0;
    capture_overflow_count = 0;
    capture_start_time = get_timestamp_us();

    /* Enable capture in RTL (this would be done via register write) */
    raw_state.capture_active = true;

    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_CAPTURE_START, 0);
    *response_len = sizeof(raw_rsp_header_t);

    return 0;
}

int raw_cmd_capture_stop(uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;
    raw_capture_info_t *info;

    if (!raw_state.capture_active) {
        build_response_header(hdr, RAW_RSP_OK, RAW_CMD_CAPTURE_STOP, 0);
        *response_len = sizeof(raw_rsp_header_t);
        return 0;
    }

    /* Disable capture */
    raw_state.capture_active = false;

    /* Build response with capture info */
    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_CAPTURE_STOP, sizeof(raw_capture_info_t));

    info = (raw_capture_info_t *)(response + sizeof(raw_rsp_header_t));
    info->sample_count = capture_sample_count;
    info->index_count = capture_index_count;
    info->overflow_count = capture_overflow_count;
    info->duration_us = get_timestamp_us() - capture_start_time;

    *response_len = sizeof(raw_rsp_header_t) + sizeof(raw_capture_info_t);

    return 0;
}

int raw_cmd_get_pll_status(uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;
    raw_pll_status_t *status;

    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_GET_PLL_STATUS, sizeof(raw_pll_status_t));

    status = (raw_pll_status_t *)(response + sizeof(raw_rsp_header_t));

    /* TODO: Read actual PLL status from registers */
    status->frequency = 500;     /* 500 kHz data rate (example) */
    status->locked = 1;
    status->lock_count = 0;
    status->reserved = 0;
    status->reserved2 = 0;
    status->error_count = 0;

    *response_len = sizeof(raw_rsp_header_t) + sizeof(raw_pll_status_t);

    return 0;
}

int raw_cmd_get_signal_qual(uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;
    raw_signal_qual_t *qual;

    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_GET_SIGNAL_QUAL, sizeof(raw_signal_qual_t));

    qual = (raw_signal_qual_t *)(response + sizeof(raw_rsp_header_t));

    /* TODO: Read actual signal quality from diagnostics module */
    qual->amplitude = 800;       /* 800 mV (example) */
    qual->noise = 50;            /* 50 mV noise */
    qual->reserved = 0;
    qual->bit_error_rate = 0;    /* No errors */
    qual->jitter_ns = 25;        /* 25 ns jitter */
    qual->overflow = 0;
    memset(qual->reserved2, 0, sizeof(qual->reserved2));

    *response_len = sizeof(raw_rsp_header_t) + sizeof(raw_signal_qual_t);

    return 0;
}

int raw_cmd_get_drive_profile(uint8_t *response, uint32_t *response_len)
{
    raw_rsp_header_t *hdr = (raw_rsp_header_t *)response;
    raw_drive_profile_t *profile;
    raw_fdd_geometry_t *geom;

    build_response_header(hdr, RAW_RSP_OK, RAW_CMD_GET_DRIVE_PROFILE,
                          sizeof(raw_drive_profile_t) + sizeof(raw_fdd_geometry_t));

    profile = (raw_drive_profile_t *)(response + sizeof(raw_rsp_header_t));
    geom = (raw_fdd_geometry_t *)(response + sizeof(raw_rsp_header_t) + sizeof(raw_drive_profile_t));

    profile->drive_num = raw_state.selected_drive;
    profile->drive_type = raw_state.is_fdd ? 0 : 1;

    if (raw_state.is_fdd) {
        profile->disk_present = hal_disk_present(raw_state.selected_drive);
        profile->write_protected = hal_write_protected(raw_state.selected_drive);
        profile->at_track0 = hal_track0(raw_state.selected_drive);
        profile->current_track = raw_state.current_track;
        profile->capacity = 2880;  /* 1.44MB */
        profile->block_size = 512;

        /* FDD geometry */
        geom->tracks = 80;
        geom->heads = 2;
        geom->sectors = 18;
        geom->reserved = 0;
    } else {
        hdd_geometry_t hdd_geom;

        profile->disk_present = hal_hdd_is_ready(raw_state.selected_drive);
        profile->write_protected = 0;
        profile->at_track0 = 0;
        profile->current_track = 0;
        profile->block_size = 512;

        if (hal_hdd_get_geometry(raw_state.selected_drive, &hdd_geom) == HAL_OK) {
            profile->capacity = hdd_geom.total_sectors;
        } else {
            profile->capacity = 0;
        }

        /* No FDD geometry for HDD */
        geom->tracks = 0;
        geom->heads = 0;
        geom->sectors = 0;
        geom->reserved = 0;
    }

    memset(profile->reserved, 0, sizeof(profile->reserved));

    *response_len = sizeof(raw_rsp_header_t) + sizeof(raw_drive_profile_t) + sizeof(raw_fdd_geometry_t);

    return 0;
}

/*---------------------------------------------------------------------------
 * Capture Control
 *---------------------------------------------------------------------------*/

int raw_mode_capture_start(void)
{
    if (raw_state.capture_active) {
        return -1;
    }

    capture_sample_count = 0;
    capture_index_count = 0;
    capture_overflow_count = 0;
    capture_start_time = get_timestamp_us();

    raw_state.capture_active = true;
    return 0;
}

int raw_mode_capture_stop(void)
{
    raw_state.capture_active = false;
    return 0;
}

bool raw_mode_is_capturing(void)
{
    return raw_state.capture_active;
}

int raw_mode_get_capture_info(raw_capture_info_t *info)
{
    if (info == NULL) {
        return -1;
    }

    info->sample_count = capture_sample_count;
    info->index_count = capture_index_count;
    info->overflow_count = capture_overflow_count;
    info->duration_us = get_timestamp_us() - capture_start_time;

    return 0;
}

/*---------------------------------------------------------------------------
 * Flux Data Processing
 *---------------------------------------------------------------------------*/

void raw_mode_process_flux(uint32_t flux_word)
{
    capture_sample_count++;

    if (flux_word & FLUX_FLAG_INDEX) {
        capture_index_count++;
    }

    if (flux_word & FLUX_FLAG_OVERFLOW) {
        capture_overflow_count++;
    }
}

/*---------------------------------------------------------------------------
 * Status Functions
 *---------------------------------------------------------------------------*/

void raw_mode_get_state(raw_mode_state_t *state)
{
    if (state != NULL) {
        memcpy(state, &raw_state, sizeof(raw_mode_state_t));
    }
}

uint8_t raw_mode_get_selected_drive(void)
{
    return raw_state.selected_drive;
}

bool raw_mode_is_fdd_selected(void)
{
    return raw_state.is_fdd;
}
