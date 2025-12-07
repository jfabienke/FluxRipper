/*-----------------------------------------------------------------------------
 * scsi_handler.h
 * SCSI Command Handler for USB Mass Storage Class
 *
 * Created: 2025-12-05 16:05
 *
 * Processes SCSI commands from the USB MSC transport layer and
 * translates them to MSC HAL operations.
 *---------------------------------------------------------------------------*/

#ifndef SCSI_HANDLER_H
#define SCSI_HANDLER_H

#include <stdint.h>
#include <stdbool.h>

/*---------------------------------------------------------------------------
 * SCSI Command Opcodes (Minimal set for USB MSC compliance)
 *---------------------------------------------------------------------------*/

#define SCSI_TEST_UNIT_READY        0x00
#define SCSI_REQUEST_SENSE          0x03
#define SCSI_INQUIRY                0x12
#define SCSI_MODE_SENSE_6           0x1A
#define SCSI_START_STOP_UNIT        0x1B
#define SCSI_PREVENT_ALLOW_REMOVAL  0x1E
#define SCSI_READ_FORMAT_CAPACITIES 0x23
#define SCSI_READ_CAPACITY_10       0x25
#define SCSI_READ_10                0x28
#define SCSI_WRITE_10               0x2A
#define SCSI_VERIFY_10              0x2F

/*---------------------------------------------------------------------------
 * SCSI Sense Keys
 *---------------------------------------------------------------------------*/

#define SENSE_NO_SENSE              0x00
#define SENSE_RECOVERED_ERROR       0x01
#define SENSE_NOT_READY             0x02
#define SENSE_MEDIUM_ERROR          0x03
#define SENSE_HARDWARE_ERROR        0x04
#define SENSE_ILLEGAL_REQUEST       0x05
#define SENSE_UNIT_ATTENTION        0x06
#define SENSE_DATA_PROTECT          0x07
#define SENSE_BLANK_CHECK           0x08
#define SENSE_ABORTED_COMMAND       0x0B

/*---------------------------------------------------------------------------
 * Additional Sense Codes (ASC)
 *---------------------------------------------------------------------------*/

#define ASC_NO_ADDITIONAL_INFO      0x00
#define ASC_INVALID_COMMAND         0x20
#define ASC_LBA_OUT_OF_RANGE        0x21
#define ASC_INVALID_FIELD_IN_CDB    0x24
#define ASC_LOGICAL_UNIT_NOT_READY  0x04
#define ASC_NOT_READY_TO_READY      0x28
#define ASC_MEDIUM_NOT_PRESENT      0x3A
#define ASC_WRITE_PROTECTED         0x27

/*---------------------------------------------------------------------------
 * Additional Sense Code Qualifiers (ASCQ)
 *---------------------------------------------------------------------------*/

#define ASCQ_NO_ADDITIONAL_INFO     0x00
#define ASCQ_CAUSE_NOT_REPORTABLE   0x00
#define ASCQ_BECOMING_READY         0x01
#define ASCQ_NOT_REPORTABLE         0x00

/*---------------------------------------------------------------------------
 * SCSI Response Constants
 *---------------------------------------------------------------------------*/

#define SCSI_INQUIRY_RESPONSE_LEN   36
#define SCSI_SENSE_RESPONSE_LEN     18
#define SCSI_READ_CAPACITY_LEN      8
#define SCSI_MODE_SENSE_6_LEN       4
#define SCSI_FORMAT_CAPACITY_LEN    12

/* Device types for INQUIRY */
#define SCSI_DEVICE_DIRECT_ACCESS   0x00    /* SBC-3 (disk) */
#define SCSI_DEVICE_RBC             0x0E    /* Reduced Block Commands */

/* Peripheral qualifier */
#define SCSI_PQ_CONNECTED           0x00
#define SCSI_PQ_NOT_CONNECTED       0x20
#define SCSI_PQ_NOT_SUPPORTED       0x60

/*---------------------------------------------------------------------------
 * Data Structures
 *---------------------------------------------------------------------------*/

/**
 * SCSI Sense Data (fixed format)
 */
typedef struct {
    uint8_t     response_code;      /* 0x70 = current, 0x71 = deferred */
    uint8_t     segment_number;     /* Obsolete */
    uint8_t     sense_key;          /* Sense key + flags */
    uint8_t     information[4];     /* Command-specific info */
    uint8_t     add_sense_len;      /* Additional sense length (n-7) */
    uint8_t     cmd_specific[4];    /* Command-specific info */
    uint8_t     asc;                /* Additional Sense Code */
    uint8_t     ascq;               /* Additional Sense Code Qualifier */
    uint8_t     fru_code;           /* Field Replaceable Unit code */
    uint8_t     sense_key_specific[3]; /* Sense key specific info */
} __attribute__((packed)) scsi_sense_data_t;

/**
 * SCSI Command Descriptor Block (CDB) - Generic 16-byte
 */
typedef struct {
    uint8_t     opcode;
    uint8_t     bytes[15];
} __attribute__((packed)) scsi_cdb_t;

/**
 * SCSI Handler State
 */
typedef struct {
    bool        initialized;
    uint8_t     last_lun;           /* LUN of last command */
    uint8_t     last_sense_key;     /* Last sense key */
    uint8_t     last_asc;           /* Last ASC */
    uint8_t     last_ascq;          /* Last ASCQ */
    bool        unit_attention[4];  /* Unit attention pending per LUN */
} scsi_handler_state_t;

/**
 * SCSI Command Result
 */
typedef struct {
    int         status;             /* 0 = success, non-zero = error */
    uint32_t    data_len;           /* Response data length (if any) */
    bool        data_in;            /* true = data to host, false = data from host */
} scsi_result_t;

/*---------------------------------------------------------------------------
 * Initialization
 *---------------------------------------------------------------------------*/

/**
 * Initialize SCSI handler
 * @return 0 on success
 */
int scsi_handler_init(void);

/**
 * Reset SCSI handler state
 */
void scsi_handler_reset(void);

/*---------------------------------------------------------------------------
 * Command Processing
 *---------------------------------------------------------------------------*/

/**
 * Process a SCSI command
 * @param lun Logical Unit Number
 * @param cdb Command Descriptor Block (16 bytes)
 * @param cdb_len CDB length (6, 10, 12, or 16)
 * @param data_buf Buffer for data transfer (in or out)
 * @param data_len On entry: max buffer size; On exit: actual data length
 * @param result Command result structure
 * @return 0 on success, error code otherwise
 */
int scsi_process_command(uint8_t lun, const uint8_t *cdb, uint8_t cdb_len,
                         uint8_t *data_buf, uint32_t *data_len,
                         scsi_result_t *result);

/*---------------------------------------------------------------------------
 * Individual Command Handlers
 *---------------------------------------------------------------------------*/

/**
 * Handle TEST UNIT READY command
 */
int scsi_cmd_test_unit_ready(uint8_t lun, scsi_result_t *result);

/**
 * Handle REQUEST SENSE command
 */
int scsi_cmd_request_sense(uint8_t lun, uint8_t *buf, uint32_t *len,
                           scsi_result_t *result);

/**
 * Handle INQUIRY command
 */
int scsi_cmd_inquiry(uint8_t lun, const uint8_t *cdb, uint8_t *buf,
                     uint32_t *len, scsi_result_t *result);

/**
 * Handle MODE SENSE (6) command
 */
int scsi_cmd_mode_sense_6(uint8_t lun, const uint8_t *cdb, uint8_t *buf,
                          uint32_t *len, scsi_result_t *result);

/**
 * Handle START STOP UNIT command
 */
int scsi_cmd_start_stop_unit(uint8_t lun, const uint8_t *cdb,
                             scsi_result_t *result);

/**
 * Handle PREVENT ALLOW MEDIUM REMOVAL command
 */
int scsi_cmd_prevent_allow_removal(uint8_t lun, const uint8_t *cdb,
                                   scsi_result_t *result);

/**
 * Handle READ FORMAT CAPACITIES command
 */
int scsi_cmd_read_format_capacities(uint8_t lun, uint8_t *buf,
                                    uint32_t *len, scsi_result_t *result);

/**
 * Handle READ CAPACITY (10) command
 */
int scsi_cmd_read_capacity_10(uint8_t lun, uint8_t *buf, uint32_t *len,
                              scsi_result_t *result);

/**
 * Handle READ (10) command
 */
int scsi_cmd_read_10(uint8_t lun, const uint8_t *cdb, uint8_t *buf,
                     uint32_t *len, scsi_result_t *result);

/**
 * Handle WRITE (10) command
 */
int scsi_cmd_write_10(uint8_t lun, const uint8_t *cdb, const uint8_t *buf,
                      uint32_t len, scsi_result_t *result);

/**
 * Handle VERIFY (10) command
 */
int scsi_cmd_verify_10(uint8_t lun, const uint8_t *cdb, scsi_result_t *result);

/*---------------------------------------------------------------------------
 * Sense Data Management
 *---------------------------------------------------------------------------*/

/**
 * Set sense data for error reporting
 * @param lun Logical Unit Number
 * @param key Sense key
 * @param asc Additional Sense Code
 * @param ascq Additional Sense Code Qualifier
 */
void scsi_set_sense(uint8_t lun, uint8_t key, uint8_t asc, uint8_t ascq);

/**
 * Clear sense data
 * @param lun Logical Unit Number
 */
void scsi_clear_sense(uint8_t lun);

/**
 * Build sense data response
 * @param lun Logical Unit Number
 * @param buf Buffer to fill with sense data
 * @return Length of sense data
 */
int scsi_build_sense_response(uint8_t lun, uint8_t *buf);

/**
 * Set unit attention condition
 * @param lun Logical Unit Number
 * @param asc Additional Sense Code for unit attention
 * @param ascq Additional Sense Code Qualifier
 */
void scsi_set_unit_attention(uint8_t lun, uint8_t asc, uint8_t ascq);

/**
 * Check if unit attention is pending
 * @param lun Logical Unit Number
 * @return true if unit attention pending
 */
bool scsi_unit_attention_pending(uint8_t lun);

/*---------------------------------------------------------------------------
 * Utility Functions
 *---------------------------------------------------------------------------*/

/**
 * Get SCSI opcode name for debugging
 * @param opcode SCSI opcode
 * @return String name of opcode
 */
const char *scsi_opcode_name(uint8_t opcode);

/**
 * Get sense key name for debugging
 * @param key Sense key
 * @return String name of sense key
 */
const char *scsi_sense_key_name(uint8_t key);

#endif /* SCSI_HANDLER_H */
