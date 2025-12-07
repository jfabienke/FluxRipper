/*-----------------------------------------------------------------------------
 * scsi_handler.c
 * SCSI Command Handler for USB Mass Storage Class
 *
 * Created: 2025-12-05 16:10
 *
 * Processes SCSI commands from the USB MSC transport layer and
 * translates them to MSC HAL operations.
 *---------------------------------------------------------------------------*/

#include "scsi_handler.h"
#include "msc_hal.h"
#include <string.h>

/*---------------------------------------------------------------------------
 * Private Data
 *---------------------------------------------------------------------------*/

static scsi_handler_state_t scsi_state;

/* Per-LUN sense data */
static scsi_sense_data_t sense_data[MSC_MAX_LUNS];

/*---------------------------------------------------------------------------
 * Private Functions - Sense Data
 *---------------------------------------------------------------------------*/

static void init_sense_data(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) return;

    memset(&sense_data[lun], 0, sizeof(scsi_sense_data_t));
    sense_data[lun].response_code = 0x70;  /* Current errors, fixed format */
    sense_data[lun].add_sense_len = 10;    /* Standard length */
}

/*---------------------------------------------------------------------------
 * Private Functions - CDB Parsing
 *---------------------------------------------------------------------------*/

static uint32_t get_be32(const uint8_t *buf)
{
    return ((uint32_t)buf[0] << 24) |
           ((uint32_t)buf[1] << 16) |
           ((uint32_t)buf[2] << 8)  |
           ((uint32_t)buf[3]);
}

static uint16_t get_be16(const uint8_t *buf)
{
    return ((uint16_t)buf[0] << 8) | (uint16_t)buf[1];
}

static void put_be32(uint8_t *buf, uint32_t val)
{
    buf[0] = (val >> 24) & 0xFF;
    buf[1] = (val >> 16) & 0xFF;
    buf[2] = (val >> 8) & 0xFF;
    buf[3] = val & 0xFF;
}

static void put_be16(uint8_t *buf, uint16_t val)
{
    buf[0] = (val >> 8) & 0xFF;
    buf[1] = val & 0xFF;
}

/*---------------------------------------------------------------------------
 * Public Functions - Initialization
 *---------------------------------------------------------------------------*/

int scsi_handler_init(void)
{
    int i;

    memset(&scsi_state, 0, sizeof(scsi_state));

    for (i = 0; i < MSC_MAX_LUNS; i++) {
        init_sense_data(i);
        scsi_state.unit_attention[i] = false;
    }

    scsi_state.initialized = true;
    return 0;
}

void scsi_handler_reset(void)
{
    int i;

    for (i = 0; i < MSC_MAX_LUNS; i++) {
        init_sense_data(i);
        scsi_state.unit_attention[i] = true;  /* Signal reset */
    }
}

/*---------------------------------------------------------------------------
 * Public Functions - Sense Data Management
 *---------------------------------------------------------------------------*/

void scsi_set_sense(uint8_t lun, uint8_t key, uint8_t asc, uint8_t ascq)
{
    if (lun >= MSC_MAX_LUNS) return;

    sense_data[lun].sense_key = key;
    sense_data[lun].asc = asc;
    sense_data[lun].ascq = ascq;

    scsi_state.last_lun = lun;
    scsi_state.last_sense_key = key;
    scsi_state.last_asc = asc;
    scsi_state.last_ascq = ascq;
}

void scsi_clear_sense(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) return;
    init_sense_data(lun);
}

int scsi_build_sense_response(uint8_t lun, uint8_t *buf)
{
    if (lun >= MSC_MAX_LUNS || buf == NULL) {
        return 0;
    }

    memcpy(buf, &sense_data[lun], SCSI_SENSE_RESPONSE_LEN);
    return SCSI_SENSE_RESPONSE_LEN;
}

void scsi_set_unit_attention(uint8_t lun, uint8_t asc, uint8_t ascq)
{
    if (lun >= MSC_MAX_LUNS) return;

    scsi_state.unit_attention[lun] = true;
    scsi_set_sense(lun, SENSE_UNIT_ATTENTION, asc, ascq);
}

bool scsi_unit_attention_pending(uint8_t lun)
{
    if (lun >= MSC_MAX_LUNS) return false;
    return scsi_state.unit_attention[lun];
}

/*---------------------------------------------------------------------------
 * Command Handlers - TEST UNIT READY
 *---------------------------------------------------------------------------*/

int scsi_cmd_test_unit_ready(uint8_t lun, scsi_result_t *result)
{
    result->data_len = 0;
    result->data_in = false;

    /* Check for unit attention first */
    if (scsi_state.unit_attention[lun]) {
        scsi_state.unit_attention[lun] = false;
        scsi_set_sense(lun, SENSE_UNIT_ATTENTION, ASC_NOT_READY_TO_READY, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        return -1;
    }

    /* Check if media is ready */
    if (!msc_hal_is_ready(lun)) {
        scsi_set_sense(lun, SENSE_NOT_READY, ASC_MEDIUM_NOT_PRESENT, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        return -1;
    }

    /* Check for media change */
    if (msc_hal_media_changed(lun)) {
        scsi_set_sense(lun, SENSE_UNIT_ATTENTION, ASC_NOT_READY_TO_READY, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        return -1;
    }

    scsi_clear_sense(lun);
    result->status = 0;
    return 0;
}

/*---------------------------------------------------------------------------
 * Command Handlers - REQUEST SENSE
 *---------------------------------------------------------------------------*/

int scsi_cmd_request_sense(uint8_t lun, uint8_t *buf, uint32_t *len,
                           scsi_result_t *result)
{
    int sense_len;

    sense_len = scsi_build_sense_response(lun, buf);

    if (*len > (uint32_t)sense_len) {
        *len = sense_len;
    }

    result->data_len = *len;
    result->data_in = true;
    result->status = 0;

    /* Clear sense after reading */
    scsi_clear_sense(lun);

    return 0;
}

/*---------------------------------------------------------------------------
 * Command Handlers - INQUIRY
 *---------------------------------------------------------------------------*/

int scsi_cmd_inquiry(uint8_t lun, const uint8_t *cdb, uint8_t *buf,
                     uint32_t *len, scsi_result_t *result)
{
    msc_lun_config_t config;
    uint8_t evpd = cdb[1] & 0x01;
    uint8_t page_code = cdb[2];
    uint16_t alloc_len = get_be16(&cdb[3]);

    if (evpd) {
        /* VPD pages not supported for now */
        scsi_set_sense(lun, SENSE_ILLEGAL_REQUEST, ASC_INVALID_FIELD_IN_CDB, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        result->data_len = 0;
        return -1;
    }

    /* Standard INQUIRY */
    memset(buf, 0, SCSI_INQUIRY_RESPONSE_LEN);

    /* Get LUN configuration */
    if (msc_hal_get_lun_config(lun, &config) != MSC_OK) {
        /* LUN not supported */
        buf[0] = SCSI_PQ_NOT_SUPPORTED | SCSI_DEVICE_DIRECT_ACCESS;
    } else {
        /* Peripheral qualifier and device type */
        if (config.present) {
            buf[0] = SCSI_PQ_CONNECTED | SCSI_DEVICE_DIRECT_ACCESS;
        } else {
            buf[0] = SCSI_PQ_NOT_CONNECTED | SCSI_DEVICE_DIRECT_ACCESS;
        }
    }

    /* Removable media bit */
    buf[1] = config.removable ? 0x80 : 0x00;

    /* Version (SPC-4) */
    buf[2] = 0x06;

    /* Response data format (SPC-4) */
    buf[3] = 0x02;

    /* Additional length */
    buf[4] = SCSI_INQUIRY_RESPONSE_LEN - 5;

    /* Flags */
    buf[5] = 0x00;
    buf[6] = 0x00;
    buf[7] = 0x00;

    /* Vendor ID (8 bytes, padded with spaces) */
    memset(&buf[8], ' ', 8);
    memcpy(&buf[8], config.vendor, strlen(config.vendor) < 8 ? strlen(config.vendor) : 8);

    /* Product ID (16 bytes, padded with spaces) */
    memset(&buf[16], ' ', 16);
    memcpy(&buf[16], config.product, strlen(config.product) < 16 ? strlen(config.product) : 16);

    /* Product Revision (4 bytes, padded with spaces) */
    memset(&buf[32], ' ', 4);
    memcpy(&buf[32], config.revision, strlen(config.revision) < 4 ? strlen(config.revision) : 4);

    /* Return requested length */
    *len = (alloc_len < SCSI_INQUIRY_RESPONSE_LEN) ? alloc_len : SCSI_INQUIRY_RESPONSE_LEN;

    result->data_len = *len;
    result->data_in = true;
    result->status = 0;

    return 0;
}

/*---------------------------------------------------------------------------
 * Command Handlers - MODE SENSE (6)
 *---------------------------------------------------------------------------*/

int scsi_cmd_mode_sense_6(uint8_t lun, const uint8_t *cdb, uint8_t *buf,
                          uint32_t *len, scsi_result_t *result)
{
    uint8_t page_code = cdb[2] & 0x3F;
    uint8_t alloc_len = cdb[4];

    memset(buf, 0, SCSI_MODE_SENSE_6_LEN);

    /* Mode parameter header */
    buf[0] = SCSI_MODE_SENSE_6_LEN - 1;  /* Mode data length */
    buf[1] = 0x00;                        /* Medium type */
    buf[2] = msc_hal_is_write_protected(lun) ? 0x80 : 0x00;  /* Write protect bit */
    buf[3] = 0x00;                        /* Block descriptor length */

    *len = (alloc_len < SCSI_MODE_SENSE_6_LEN) ? alloc_len : SCSI_MODE_SENSE_6_LEN;

    result->data_len = *len;
    result->data_in = true;
    result->status = 0;

    return 0;
}

/*---------------------------------------------------------------------------
 * Command Handlers - START STOP UNIT
 *---------------------------------------------------------------------------*/

int scsi_cmd_start_stop_unit(uint8_t lun, const uint8_t *cdb,
                             scsi_result_t *result)
{
    bool start = (cdb[4] & 0x01) != 0;
    bool loej = (cdb[4] & 0x02) != 0;

    msc_hal_start_stop(lun, start, loej);

    result->data_len = 0;
    result->data_in = false;
    result->status = 0;

    return 0;
}

/*---------------------------------------------------------------------------
 * Command Handlers - PREVENT ALLOW MEDIUM REMOVAL
 *---------------------------------------------------------------------------*/

int scsi_cmd_prevent_allow_removal(uint8_t lun, const uint8_t *cdb,
                                   scsi_result_t *result)
{
    bool prevent = (cdb[4] & 0x01) != 0;

    msc_hal_prevent_removal(lun, prevent);

    result->data_len = 0;
    result->data_in = false;
    result->status = 0;

    return 0;
}

/*---------------------------------------------------------------------------
 * Command Handlers - READ FORMAT CAPACITIES
 *---------------------------------------------------------------------------*/

int scsi_cmd_read_format_capacities(uint8_t lun, uint8_t *buf,
                                    uint32_t *len, scsi_result_t *result)
{
    uint32_t last_lba;
    uint16_t block_size;

    if (msc_hal_get_capacity(lun, &last_lba, &block_size) != MSC_OK) {
        scsi_set_sense(lun, SENSE_NOT_READY, ASC_MEDIUM_NOT_PRESENT, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        result->data_len = 0;
        return -1;
    }

    memset(buf, 0, SCSI_FORMAT_CAPACITY_LEN);

    /* Capacity list header */
    buf[0] = 0x00;
    buf[1] = 0x00;
    buf[2] = 0x00;
    buf[3] = 0x08;  /* Capacity list length */

    /* Current/Maximum capacity descriptor */
    put_be32(&buf[4], last_lba + 1);  /* Number of blocks */
    buf[8] = 0x02;                     /* Descriptor code: Formatted media */
    buf[9] = (block_size >> 16) & 0xFF;
    buf[10] = (block_size >> 8) & 0xFF;
    buf[11] = block_size & 0xFF;

    *len = SCSI_FORMAT_CAPACITY_LEN;

    result->data_len = *len;
    result->data_in = true;
    result->status = 0;

    return 0;
}

/*---------------------------------------------------------------------------
 * Command Handlers - READ CAPACITY (10)
 *---------------------------------------------------------------------------*/

int scsi_cmd_read_capacity_10(uint8_t lun, uint8_t *buf, uint32_t *len,
                              scsi_result_t *result)
{
    uint32_t last_lba;
    uint16_t block_size;

    if (!msc_hal_is_ready(lun)) {
        scsi_set_sense(lun, SENSE_NOT_READY, ASC_MEDIUM_NOT_PRESENT, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        result->data_len = 0;
        return -1;
    }

    if (msc_hal_get_capacity(lun, &last_lba, &block_size) != MSC_OK) {
        scsi_set_sense(lun, SENSE_NOT_READY, ASC_MEDIUM_NOT_PRESENT, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        result->data_len = 0;
        return -1;
    }

    memset(buf, 0, SCSI_READ_CAPACITY_LEN);

    /* Last logical block address */
    put_be32(&buf[0], last_lba);

    /* Block length in bytes */
    put_be32(&buf[4], block_size);

    *len = SCSI_READ_CAPACITY_LEN;

    result->data_len = *len;
    result->data_in = true;
    result->status = 0;

    return 0;
}

/*---------------------------------------------------------------------------
 * Command Handlers - READ (10)
 *---------------------------------------------------------------------------*/

int scsi_cmd_read_10(uint8_t lun, const uint8_t *cdb, uint8_t *buf,
                     uint32_t *len, scsi_result_t *result)
{
    uint32_t lba;
    uint16_t transfer_len;
    int ret;

    /* Parse CDB */
    lba = get_be32(&cdb[2]);
    transfer_len = get_be16(&cdb[7]);

    if (transfer_len == 0) {
        result->data_len = 0;
        result->data_in = true;
        result->status = 0;
        return 0;
    }

    /* Check if ready */
    if (!msc_hal_is_ready(lun)) {
        scsi_set_sense(lun, SENSE_NOT_READY, ASC_MEDIUM_NOT_PRESENT, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        result->data_len = 0;
        return -1;
    }

    /* Read sectors */
    ret = msc_hal_read_sectors(lun, lba, buf, transfer_len);

    if (ret == MSC_OK) {
        *len = transfer_len * MSC_SECTOR_SIZE;
        result->data_len = *len;
        result->data_in = true;
        result->status = 0;
        return 0;
    } else if (ret == MSC_ERR_LBA_RANGE) {
        scsi_set_sense(lun, SENSE_ILLEGAL_REQUEST, ASC_LBA_OUT_OF_RANGE, ASCQ_NO_ADDITIONAL_INFO);
    } else {
        scsi_set_sense(lun, SENSE_MEDIUM_ERROR, ASC_NO_ADDITIONAL_INFO, ASCQ_NO_ADDITIONAL_INFO);
    }

    result->status = -1;
    result->data_len = 0;
    return -1;
}

/*---------------------------------------------------------------------------
 * Command Handlers - WRITE (10)
 *---------------------------------------------------------------------------*/

int scsi_cmd_write_10(uint8_t lun, const uint8_t *cdb, const uint8_t *buf,
                      uint32_t len, scsi_result_t *result)
{
    uint32_t lba;
    uint16_t transfer_len;
    int ret;

    /* Parse CDB */
    lba = get_be32(&cdb[2]);
    transfer_len = get_be16(&cdb[7]);

    if (transfer_len == 0) {
        result->data_len = 0;
        result->data_in = false;
        result->status = 0;
        return 0;
    }

    /* Check if ready */
    if (!msc_hal_is_ready(lun)) {
        scsi_set_sense(lun, SENSE_NOT_READY, ASC_MEDIUM_NOT_PRESENT, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        return -1;
    }

    /* Check write protection */
    if (msc_hal_is_write_protected(lun)) {
        scsi_set_sense(lun, SENSE_DATA_PROTECT, ASC_WRITE_PROTECTED, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        return -1;
    }

    /* Write sectors */
    ret = msc_hal_write_sectors(lun, lba, buf, transfer_len);

    if (ret == MSC_OK) {
        result->data_len = 0;
        result->data_in = false;
        result->status = 0;
        return 0;
    } else if (ret == MSC_ERR_LBA_RANGE) {
        scsi_set_sense(lun, SENSE_ILLEGAL_REQUEST, ASC_LBA_OUT_OF_RANGE, ASCQ_NO_ADDITIONAL_INFO);
    } else if (ret == MSC_ERR_WRITE_PROT) {
        scsi_set_sense(lun, SENSE_DATA_PROTECT, ASC_WRITE_PROTECTED, ASCQ_NO_ADDITIONAL_INFO);
    } else {
        scsi_set_sense(lun, SENSE_MEDIUM_ERROR, ASC_NO_ADDITIONAL_INFO, ASCQ_NO_ADDITIONAL_INFO);
    }

    result->status = -1;
    return -1;
}

/*---------------------------------------------------------------------------
 * Command Handlers - VERIFY (10)
 *---------------------------------------------------------------------------*/

int scsi_cmd_verify_10(uint8_t lun, const uint8_t *cdb, scsi_result_t *result)
{
    /* For now, just return success - actual verification would read and compare */
    if (!msc_hal_is_ready(lun)) {
        scsi_set_sense(lun, SENSE_NOT_READY, ASC_MEDIUM_NOT_PRESENT, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        return -1;
    }

    result->data_len = 0;
    result->data_in = false;
    result->status = 0;
    return 0;
}

/*---------------------------------------------------------------------------
 * Main Command Dispatcher
 *---------------------------------------------------------------------------*/

int scsi_process_command(uint8_t lun, const uint8_t *cdb, uint8_t cdb_len,
                         uint8_t *data_buf, uint32_t *data_len,
                         scsi_result_t *result)
{
    uint8_t opcode;

    if (cdb == NULL || result == NULL) {
        return -1;
    }

    if (lun >= MSC_MAX_LUNS) {
        scsi_set_sense(0, SENSE_ILLEGAL_REQUEST, ASC_INVALID_FIELD_IN_CDB, ASCQ_NO_ADDITIONAL_INFO);
        result->status = -1;
        result->data_len = 0;
        return -1;
    }

    opcode = cdb[0];

    switch (opcode) {
        case SCSI_TEST_UNIT_READY:
            return scsi_cmd_test_unit_ready(lun, result);

        case SCSI_REQUEST_SENSE:
            return scsi_cmd_request_sense(lun, data_buf, data_len, result);

        case SCSI_INQUIRY:
            return scsi_cmd_inquiry(lun, cdb, data_buf, data_len, result);

        case SCSI_MODE_SENSE_6:
            return scsi_cmd_mode_sense_6(lun, cdb, data_buf, data_len, result);

        case SCSI_START_STOP_UNIT:
            return scsi_cmd_start_stop_unit(lun, cdb, result);

        case SCSI_PREVENT_ALLOW_REMOVAL:
            return scsi_cmd_prevent_allow_removal(lun, cdb, result);

        case SCSI_READ_FORMAT_CAPACITIES:
            return scsi_cmd_read_format_capacities(lun, data_buf, data_len, result);

        case SCSI_READ_CAPACITY_10:
            return scsi_cmd_read_capacity_10(lun, data_buf, data_len, result);

        case SCSI_READ_10:
            return scsi_cmd_read_10(lun, cdb, data_buf, data_len, result);

        case SCSI_WRITE_10:
            return scsi_cmd_write_10(lun, cdb, data_buf, *data_len, result);

        case SCSI_VERIFY_10:
            return scsi_cmd_verify_10(lun, cdb, result);

        default:
            /* Unsupported command */
            scsi_set_sense(lun, SENSE_ILLEGAL_REQUEST, ASC_INVALID_COMMAND, ASCQ_NO_ADDITIONAL_INFO);
            result->status = -1;
            result->data_len = 0;
            return -1;
    }
}

/*---------------------------------------------------------------------------
 * Utility Functions - Debug
 *---------------------------------------------------------------------------*/

const char *scsi_opcode_name(uint8_t opcode)
{
    switch (opcode) {
        case SCSI_TEST_UNIT_READY:        return "TEST_UNIT_READY";
        case SCSI_REQUEST_SENSE:          return "REQUEST_SENSE";
        case SCSI_INQUIRY:                return "INQUIRY";
        case SCSI_MODE_SENSE_6:           return "MODE_SENSE_6";
        case SCSI_START_STOP_UNIT:        return "START_STOP_UNIT";
        case SCSI_PREVENT_ALLOW_REMOVAL:  return "PREVENT_ALLOW_REMOVAL";
        case SCSI_READ_FORMAT_CAPACITIES: return "READ_FORMAT_CAPACITIES";
        case SCSI_READ_CAPACITY_10:       return "READ_CAPACITY_10";
        case SCSI_READ_10:                return "READ_10";
        case SCSI_WRITE_10:               return "WRITE_10";
        case SCSI_VERIFY_10:              return "VERIFY_10";
        default:                          return "UNKNOWN";
    }
}

const char *scsi_sense_key_name(uint8_t key)
{
    switch (key) {
        case SENSE_NO_SENSE:          return "NO_SENSE";
        case SENSE_RECOVERED_ERROR:   return "RECOVERED_ERROR";
        case SENSE_NOT_READY:         return "NOT_READY";
        case SENSE_MEDIUM_ERROR:      return "MEDIUM_ERROR";
        case SENSE_HARDWARE_ERROR:    return "HARDWARE_ERROR";
        case SENSE_ILLEGAL_REQUEST:   return "ILLEGAL_REQUEST";
        case SENSE_UNIT_ATTENTION:    return "UNIT_ATTENTION";
        case SENSE_DATA_PROTECT:      return "DATA_PROTECT";
        case SENSE_BLANK_CHECK:       return "BLANK_CHECK";
        case SENSE_ABORTED_COMMAND:   return "ABORTED_COMMAND";
        default:                      return "UNKNOWN";
    }
}
