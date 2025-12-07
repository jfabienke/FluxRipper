/**
 * FluxRipper USB Traffic Logger HAL
 *
 * Hardware abstraction for USB traffic capture and PCAP export.
 * Interfaces with usb_traffic_logger.v RTL module.
 *
 * Created: 2025-12-07 12:30
 * License: BSD-3-Clause
 */

#ifndef USB_LOGGER_HAL_H
#define USB_LOGGER_HAL_H

#include <stdint.h>
#include <stdbool.h>

/*============================================================================
 * Constants
 *============================================================================*/

/* Logger return codes */
#define USBLOG_OK              0
#define USBLOG_ERR_NOT_READY  -1
#define USBLOG_ERR_OVERFLOW   -2
#define USBLOG_ERR_EMPTY      -3
#define USBLOG_ERR_INVALID    -4
#define USBLOG_ERR_TIMEOUT    -5

/* Buffer size (must match RTL parameter) */
#define USBLOG_BUFFER_SIZE    8192   /* 8KB */

/* Maximum packet payload */
#define USBLOG_MAX_PAYLOAD    64

/* Record types (matches RTL encoding) */
#define USBLOG_REC_TOKEN      0
#define USBLOG_REC_SOF        1
#define USBLOG_REC_DATA       2
#define USBLOG_REC_HANDSHAKE  3
#define USBLOG_REC_SPECIAL    4
#define USBLOG_REC_BUS_EVENT  5

/* USB PIDs */
#define USB_PID_OUT           0x01
#define USB_PID_IN            0x09
#define USB_PID_SOF           0x05
#define USB_PID_SETUP         0x0D
#define USB_PID_DATA0         0x03
#define USB_PID_DATA1         0x0B
#define USB_PID_DATA2         0x07
#define USB_PID_MDATA         0x0F
#define USB_PID_ACK           0x02
#define USB_PID_NAK           0x0A
#define USB_PID_STALL         0x0E
#define USB_PID_NYET          0x06

/* Filter flags */
#define USBLOG_FILTER_EP_ALL    0x0F
#define USBLOG_FILTER_EP0       0x01
#define USBLOG_FILTER_EP1       0x02
#define USBLOG_FILTER_EP2       0x04
#define USBLOG_FILTER_EP3       0x08

#define USBLOG_FILTER_DIR_BOTH  0x00
#define USBLOG_FILTER_DIR_OUT   0x10
#define USBLOG_FILTER_DIR_IN    0x30

#define USBLOG_FILTER_TOKENS    0x40
#define USBLOG_FILTER_DATA      0x80
#define USBLOG_FILTER_HANDSHAKE 0x100
#define USBLOG_FILTER_ALL       0x1C0

/*============================================================================
 * Data Structures
 *============================================================================*/

/**
 * USB transaction record (decoded from buffer)
 */
typedef struct {
    uint8_t  rec_type;        /* Record type (USBLOG_REC_*) */
    uint8_t  pid;             /* USB PID */
    uint8_t  endpoint;        /* Endpoint number (0-15) */
    uint8_t  direction;       /* 0=OUT/Host->Device, 1=IN/Device->Host */
    uint8_t  is_tx;           /* 0=Received, 1=Transmitted */
    uint32_t timestamp_us;    /* Relative timestamp in microseconds */
    uint8_t  length;          /* Payload length (0-64) */
    uint8_t  payload[USBLOG_MAX_PAYLOAD + 2];  /* Payload + CRC */
} usblog_record_t;

/**
 * Logger status
 */
typedef struct {
    bool     enabled;         /* Capture enabled */
    bool     triggered;       /* Trigger condition met */
    bool     overflow;        /* Buffer overflow occurred */
    bool     wrapped;         /* Buffer has wrapped */
    uint32_t write_ptr;       /* Current write position */
    uint32_t read_ptr;        /* Current read position */
    uint32_t trans_count;     /* Transactions captured */
    uint32_t bytes_used;      /* Bytes in buffer */
    uint32_t bytes_free;      /* Free space in buffer */
} usblog_status_t;

/**
 * Capture filter configuration
 */
typedef struct {
    uint8_t  ep_mask;         /* Endpoint mask (USBLOG_FILTER_EP*) */
    bool     filter_dir;      /* Enable direction filtering */
    bool     dir_in;          /* If filter_dir: true=IN only, false=OUT only */
    bool     capture_tokens;  /* Capture token packets */
    bool     capture_data;    /* Capture data packets */
    bool     capture_hs;      /* Capture handshakes */
} usblog_filter_t;

/**
 * Trigger configuration
 */
typedef struct {
    bool     enabled;         /* Trigger enabled */
    uint8_t  pid;             /* PID to trigger on */
} usblog_trigger_t;

/**
 * PCAP file header (global)
 */
typedef struct __attribute__((packed)) {
    uint32_t magic_number;    /* 0xa1b2c3d4 */
    uint16_t version_major;   /* 2 */
    uint16_t version_minor;   /* 4 */
    int32_t  thiszone;        /* GMT offset (0) */
    uint32_t sigfigs;         /* Timestamp accuracy (0) */
    uint32_t snaplen;         /* Max packet length (65535) */
    uint32_t network;         /* Link-layer type (293 = USB 2.0) */
} pcap_header_t;

/**
 * PCAP packet header
 */
typedef struct __attribute__((packed)) {
    uint32_t ts_sec;          /* Timestamp seconds */
    uint32_t ts_usec;         /* Timestamp microseconds */
    uint32_t incl_len;        /* Captured length */
    uint32_t orig_len;        /* Original length */
} pcap_packet_header_t;

/**
 * USB 2.0 PCAP packet header (LINKTYPE_USB_2_0 = 293)
 */
typedef struct __attribute__((packed)) {
    uint8_t  pid;             /* USB PID */
    uint8_t  endpoint;        /* Endpoint address (dir in bit 7) */
    uint8_t  device;          /* Device address */
    uint8_t  bus;             /* Bus number */
    uint8_t  flags;           /* Flags */
    uint8_t  data_length;     /* Data length */
    uint16_t reserved;        /* Reserved */
} pcap_usb2_header_t;

/*============================================================================
 * Initialization
 *============================================================================*/

/**
 * Initialize USB traffic logger
 * @return USBLOG_OK on success
 */
int usblog_init(void);

/*============================================================================
 * Capture Control
 *============================================================================*/

/**
 * Start capture with optional trigger
 * @param trigger  Trigger configuration (NULL for immediate start)
 * @return USBLOG_OK on success
 */
int usblog_start(const usblog_trigger_t *trigger);

/**
 * Stop capture
 * @return USBLOG_OK on success
 */
int usblog_stop(void);

/**
 * Clear buffer and reset counters
 * @return USBLOG_OK on success
 */
int usblog_clear(void);

/**
 * Get current status
 * @param status  Output status structure
 * @return USBLOG_OK on success
 */
int usblog_get_status(usblog_status_t *status);

/*============================================================================
 * Filter Configuration
 *============================================================================*/

/**
 * Set capture filter
 * @param filter  Filter configuration
 * @return USBLOG_OK on success
 */
int usblog_set_filter(const usblog_filter_t *filter);

/**
 * Get current filter
 * @param filter  Output filter structure
 * @return USBLOG_OK on success
 */
int usblog_get_filter(usblog_filter_t *filter);

/*============================================================================
 * Record Access
 *============================================================================*/

/**
 * Read next transaction record from buffer
 * @param record  Output record structure
 * @return USBLOG_OK on success, USBLOG_ERR_EMPTY if no more records
 */
int usblog_read_record(usblog_record_t *record);

/**
 * Peek at record without consuming it
 * @param record  Output record structure
 * @return USBLOG_OK on success, USBLOG_ERR_EMPTY if no records
 */
int usblog_peek_record(usblog_record_t *record);

/**
 * Get number of records available
 * @return Number of complete records in buffer
 */
uint32_t usblog_records_available(void);

/**
 * Reset read pointer to beginning of capture
 * @return USBLOG_OK on success
 */
int usblog_rewind(void);

/*============================================================================
 * PCAP Export
 *============================================================================*/

/**
 * Write PCAP global header
 * @param write_fn  Function to write bytes (e.g., uart_write)
 * @return USBLOG_OK on success
 */
int usblog_write_pcap_header(void (*write_fn)(const uint8_t*, uint32_t));

/**
 * Write single record as PCAP packet
 * @param record    Record to export
 * @param write_fn  Function to write bytes
 * @return USBLOG_OK on success
 */
int usblog_write_pcap_record(const usblog_record_t *record,
                              void (*write_fn)(const uint8_t*, uint32_t));

/**
 * Export entire buffer as PCAP file
 * @param write_fn  Function to write bytes
 * @return Number of records exported, negative on error
 */
int usblog_export_pcap(void (*write_fn)(const uint8_t*, uint32_t));

/*============================================================================
 * Utility Functions
 *============================================================================*/

/**
 * Get human-readable PID name
 * @param pid  USB PID value
 * @return Static string name
 */
const char* usblog_pid_name(uint8_t pid);

/**
 * Get human-readable record type name
 * @param rec_type  Record type
 * @return Static string name
 */
const char* usblog_rec_type_name(uint8_t rec_type);

/**
 * Format record as human-readable string
 * @param record  Record to format
 * @param buf     Output buffer
 * @param buflen  Buffer length
 * @return Number of characters written
 */
int usblog_format_record(const usblog_record_t *record, char *buf, uint32_t buflen);

/**
 * Calculate buffer utilization percentage
 * @return Percentage (0-100)
 */
uint8_t usblog_utilization_pct(void);

#endif /* USB_LOGGER_HAL_H */
