/**
 * FluxRipper USB Traffic Logger HAL Implementation
 *
 * Created: 2025-12-07 12:35
 * License: BSD-3-Clause
 */

#include "usb_logger_hal.h"
#include <string.h>
#include <stdio.h>

/*============================================================================
 * Hardware Register Definitions
 *============================================================================*/

/* Base address (adjust for your memory map) */
#define USBLOG_BASE_ADDR     0x44A40000

/* Register offsets (must match RTL) */
#define REG_CONTROL          0x00
#define REG_STATUS           0x04
#define REG_FILTER           0x08
#define REG_WRITE_PTR        0x0C
#define REG_READ_PTR         0x10
#define REG_TRANS_COUNT      0x14
#define REG_TIMESTAMP_LO     0x18
#define REG_TIMESTAMP_HI     0x1C
#define REG_BUFFER_DATA      0x20
#define REG_BUFFER_SIZE      0x24
#define REG_TRIGGER          0x28

/* Control register bits */
#define CTRL_ENABLE          (1 << 0)
#define CTRL_CLEAR           (1 << 1)
#define CTRL_WRAP_MODE       (1 << 2)

/* Status register bits */
#define STATUS_ACTIVE        (1 << 0)
#define STATUS_OVERFLOW      (1 << 1)
#define STATUS_WRAPPED       (1 << 2)

/* Trigger register bits */
#define TRIGGER_ENABLE       (1 << 8)

/*============================================================================
 * Register Access Macros
 *============================================================================*/

#define USBLOG_REG(offset)   (*(volatile uint32_t*)(USBLOG_BASE_ADDR + (offset)))

/*============================================================================
 * Module State
 *============================================================================*/

static bool g_initialized = false;
static uint32_t g_buffer_size = USBLOG_BUFFER_SIZE;
static uint32_t g_capture_start_ptr = 0;

/*============================================================================
 * Initialization
 *============================================================================*/

int usblog_init(void)
{
    /* Read buffer size from hardware */
    g_buffer_size = USBLOG_REG(REG_BUFFER_SIZE);
    if (g_buffer_size == 0) {
        g_buffer_size = USBLOG_BUFFER_SIZE;
    }

    /* Clear and disable */
    USBLOG_REG(REG_CONTROL) = CTRL_CLEAR;
    USBLOG_REG(REG_CONTROL) = 0;

    /* Default filter: capture everything */
    usblog_filter_t filter = {
        .ep_mask = USBLOG_FILTER_EP_ALL,
        .filter_dir = false,
        .dir_in = false,
        .capture_tokens = true,
        .capture_data = true,
        .capture_hs = true
    };
    usblog_set_filter(&filter);

    g_initialized = true;
    return USBLOG_OK;
}

/*============================================================================
 * Capture Control
 *============================================================================*/

int usblog_start(const usblog_trigger_t *trigger)
{
    if (!g_initialized) {
        return USBLOG_ERR_NOT_READY;
    }

    /* Configure trigger */
    if (trigger && trigger->enabled) {
        USBLOG_REG(REG_TRIGGER) = trigger->pid | TRIGGER_ENABLE;
    } else {
        USBLOG_REG(REG_TRIGGER) = 0;
    }

    /* Save start position for rewind */
    g_capture_start_ptr = USBLOG_REG(REG_WRITE_PTR);

    /* Enable capture */
    USBLOG_REG(REG_CONTROL) = CTRL_ENABLE;

    return USBLOG_OK;
}

int usblog_stop(void)
{
    if (!g_initialized) {
        return USBLOG_ERR_NOT_READY;
    }

    USBLOG_REG(REG_CONTROL) = 0;
    return USBLOG_OK;
}

int usblog_clear(void)
{
    if (!g_initialized) {
        return USBLOG_ERR_NOT_READY;
    }

    /* Must be stopped first */
    USBLOG_REG(REG_CONTROL) = 0;

    /* Clear buffer */
    USBLOG_REG(REG_CONTROL) = CTRL_CLEAR;
    USBLOG_REG(REG_CONTROL) = 0;

    g_capture_start_ptr = 0;
    return USBLOG_OK;
}

int usblog_get_status(usblog_status_t *status)
{
    if (!g_initialized || !status) {
        return USBLOG_ERR_NOT_READY;
    }

    uint32_t ctrl = USBLOG_REG(REG_CONTROL);
    uint32_t stat = USBLOG_REG(REG_STATUS);
    uint32_t wr_ptr = USBLOG_REG(REG_WRITE_PTR);
    uint32_t rd_ptr = USBLOG_REG(REG_READ_PTR);

    status->enabled = (ctrl & CTRL_ENABLE) != 0;
    status->triggered = (stat & STATUS_ACTIVE) != 0;
    status->overflow = (stat & STATUS_OVERFLOW) != 0;
    status->wrapped = (stat & STATUS_WRAPPED) != 0;
    status->write_ptr = wr_ptr;
    status->read_ptr = rd_ptr;
    status->trans_count = USBLOG_REG(REG_TRANS_COUNT);

    /* Calculate buffer usage */
    if (wr_ptr >= rd_ptr) {
        status->bytes_used = wr_ptr - rd_ptr;
    } else {
        status->bytes_used = g_buffer_size - rd_ptr + wr_ptr;
    }
    status->bytes_free = g_buffer_size - status->bytes_used;

    return USBLOG_OK;
}

/*============================================================================
 * Filter Configuration
 *============================================================================*/

int usblog_set_filter(const usblog_filter_t *filter)
{
    if (!g_initialized || !filter) {
        return USBLOG_ERR_NOT_READY;
    }

    uint32_t reg = filter->ep_mask & 0x0F;

    if (filter->filter_dir) {
        reg |= (1 << 4);
        if (filter->dir_in) {
            reg |= (1 << 5);
        }
    }

    if (filter->capture_tokens)  reg |= (1 << 6);
    if (filter->capture_data)    reg |= (1 << 7);
    if (filter->capture_hs)      reg |= (1 << 8);

    USBLOG_REG(REG_FILTER) = reg;
    return USBLOG_OK;
}

int usblog_get_filter(usblog_filter_t *filter)
{
    if (!g_initialized || !filter) {
        return USBLOG_ERR_NOT_READY;
    }

    uint32_t reg = USBLOG_REG(REG_FILTER);

    filter->ep_mask = reg & 0x0F;
    filter->filter_dir = (reg & (1 << 4)) != 0;
    filter->dir_in = (reg & (1 << 5)) != 0;
    filter->capture_tokens = (reg & (1 << 6)) != 0;
    filter->capture_data = (reg & (1 << 7)) != 0;
    filter->capture_hs = (reg & (1 << 8)) != 0;

    return USBLOG_OK;
}

/*============================================================================
 * Record Access
 *============================================================================*/

/**
 * Read raw byte from buffer (auto-increments read pointer)
 */
static uint8_t read_buffer_byte(void)
{
    return (uint8_t)(USBLOG_REG(REG_BUFFER_DATA) & 0xFF);
}

/**
 * Check if buffer has data available
 */
static bool has_data(void)
{
    uint32_t wr_ptr = USBLOG_REG(REG_WRITE_PTR);
    uint32_t rd_ptr = USBLOG_REG(REG_READ_PTR);
    return wr_ptr != rd_ptr;
}

int usblog_read_record(usblog_record_t *record)
{
    if (!g_initialized || !record) {
        return USBLOG_ERR_NOT_READY;
    }

    if (!has_data()) {
        return USBLOG_ERR_EMPTY;
    }

    /* Read header byte */
    uint8_t header = read_buffer_byte();

    /* Decode header */
    record->rec_type = (header >> 5) & 0x07;
    record->direction = (header >> 4) & 0x01;
    record->pid = header & 0x0F;
    record->is_tx = (header & 0x80) != 0;
    record->endpoint = 0;  /* Extracted from token if present */

    /* Read timestamp (4 bytes, little-endian) */
    uint32_t ts = 0;
    ts |= read_buffer_byte();
    ts |= read_buffer_byte() << 8;
    ts |= read_buffer_byte() << 16;
    ts |= read_buffer_byte() << 24;

    /* Convert from 60 MHz ticks to microseconds */
    record->timestamp_us = ts / 60;

    /* Read length */
    record->length = read_buffer_byte();
    if (record->length > USBLOG_MAX_PAYLOAD + 2) {
        record->length = USBLOG_MAX_PAYLOAD + 2;
    }

    /* Read payload */
    for (uint8_t i = 0; i < record->length; i++) {
        record->payload[i] = read_buffer_byte();
    }

    /* Extract endpoint from token data if applicable */
    if (record->rec_type == USBLOG_REC_TOKEN && record->length >= 2) {
        record->endpoint = ((record->payload[1] & 0x07) << 1) |
                          ((record->payload[0] >> 7) & 0x01);
    }

    return USBLOG_OK;
}

int usblog_peek_record(usblog_record_t *record)
{
    if (!g_initialized || !record) {
        return USBLOG_ERR_NOT_READY;
    }

    /* Save current read pointer */
    uint32_t saved_ptr = USBLOG_REG(REG_READ_PTR);

    /* Read record */
    int ret = usblog_read_record(record);

    /* Restore read pointer */
    USBLOG_REG(REG_READ_PTR) = saved_ptr;

    return ret;
}

uint32_t usblog_records_available(void)
{
    /* Approximate - assumes average record size of 10 bytes */
    usblog_status_t status;
    if (usblog_get_status(&status) != USBLOG_OK) {
        return 0;
    }
    return status.bytes_used / 10;
}

int usblog_rewind(void)
{
    if (!g_initialized) {
        return USBLOG_ERR_NOT_READY;
    }

    USBLOG_REG(REG_READ_PTR) = g_capture_start_ptr;
    return USBLOG_OK;
}

/*============================================================================
 * PCAP Export
 *============================================================================*/

/* PCAP magic and link type for USB 2.0 */
#define PCAP_MAGIC           0xa1b2c3d4
#define PCAP_VERSION_MAJOR   2
#define PCAP_VERSION_MINOR   4
#define PCAP_SNAPLEN         65535
#define LINKTYPE_USB_2_0     293

int usblog_write_pcap_header(void (*write_fn)(const uint8_t*, uint32_t))
{
    if (!write_fn) {
        return USBLOG_ERR_INVALID;
    }

    pcap_header_t hdr = {
        .magic_number = PCAP_MAGIC,
        .version_major = PCAP_VERSION_MAJOR,
        .version_minor = PCAP_VERSION_MINOR,
        .thiszone = 0,
        .sigfigs = 0,
        .snaplen = PCAP_SNAPLEN,
        .network = LINKTYPE_USB_2_0
    };

    write_fn((const uint8_t*)&hdr, sizeof(hdr));
    return USBLOG_OK;
}

int usblog_write_pcap_record(const usblog_record_t *record,
                              void (*write_fn)(const uint8_t*, uint32_t))
{
    if (!record || !write_fn) {
        return USBLOG_ERR_INVALID;
    }

    /* Build USB 2.0 PCAP header */
    pcap_usb2_header_t usb_hdr = {
        .pid = record->pid,
        .endpoint = record->endpoint | (record->direction ? 0x80 : 0x00),
        .device = 0,  /* Not tracked in our simple logger */
        .bus = 0,
        .flags = record->is_tx ? 0x01 : 0x00,
        .data_length = record->length,
        .reserved = 0
    };

    /* Calculate packet length */
    uint32_t pkt_len = sizeof(pcap_usb2_header_t) + record->length;

    /* PCAP packet header */
    pcap_packet_header_t pkt_hdr = {
        .ts_sec = record->timestamp_us / 1000000,
        .ts_usec = record->timestamp_us % 1000000,
        .incl_len = pkt_len,
        .orig_len = pkt_len
    };

    /* Write headers and payload */
    write_fn((const uint8_t*)&pkt_hdr, sizeof(pkt_hdr));
    write_fn((const uint8_t*)&usb_hdr, sizeof(usb_hdr));
    if (record->length > 0) {
        write_fn(record->payload, record->length);
    }

    return USBLOG_OK;
}

int usblog_export_pcap(void (*write_fn)(const uint8_t*, uint32_t))
{
    if (!write_fn) {
        return USBLOG_ERR_INVALID;
    }

    /* Write PCAP global header */
    int ret = usblog_write_pcap_header(write_fn);
    if (ret != USBLOG_OK) {
        return ret;
    }

    /* Rewind to start of capture */
    usblog_rewind();

    /* Export all records */
    int count = 0;
    usblog_record_t record;

    while (usblog_read_record(&record) == USBLOG_OK) {
        ret = usblog_write_pcap_record(&record, write_fn);
        if (ret != USBLOG_OK) {
            return ret;
        }
        count++;
    }

    return count;
}

/*============================================================================
 * Utility Functions
 *============================================================================*/

const char* usblog_pid_name(uint8_t pid)
{
    switch (pid & 0x0F) {
        case USB_PID_OUT:   return "OUT";
        case USB_PID_IN:    return "IN";
        case USB_PID_SOF:   return "SOF";
        case USB_PID_SETUP: return "SETUP";
        case USB_PID_DATA0: return "DATA0";
        case USB_PID_DATA1: return "DATA1";
        case USB_PID_DATA2: return "DATA2";
        case USB_PID_MDATA: return "MDATA";
        case USB_PID_ACK:   return "ACK";
        case USB_PID_NAK:   return "NAK";
        case USB_PID_STALL: return "STALL";
        case USB_PID_NYET:  return "NYET";
        default:            return "???";
    }
}

const char* usblog_rec_type_name(uint8_t rec_type)
{
    switch (rec_type) {
        case USBLOG_REC_TOKEN:     return "TOKEN";
        case USBLOG_REC_SOF:       return "SOF";
        case USBLOG_REC_DATA:      return "DATA";
        case USBLOG_REC_HANDSHAKE: return "HS";
        case USBLOG_REC_SPECIAL:   return "SPECIAL";
        case USBLOG_REC_BUS_EVENT: return "EVENT";
        default:                   return "???";
    }
}

int usblog_format_record(const usblog_record_t *record, char *buf, uint32_t buflen)
{
    if (!record || !buf || buflen < 32) {
        return 0;
    }

    int n = snprintf(buf, buflen, "%8lu.%03lu %s %s EP%d %s",
        record->timestamp_us / 1000,
        record->timestamp_us % 1000,
        record->is_tx ? "TX" : "RX",
        usblog_pid_name(record->pid),
        record->endpoint,
        record->direction ? "IN" : "OUT");

    /* Add payload hex dump for data packets */
    if (record->rec_type == USBLOG_REC_DATA && record->length > 0) {
        int remaining = buflen - n;
        if (remaining > 4) {
            n += snprintf(buf + n, remaining, " [");
            uint8_t show = (record->length > 8) ? 8 : record->length;
            for (uint8_t i = 0; i < show && (buflen - n) > 4; i++) {
                n += snprintf(buf + n, buflen - n, "%02X ", record->payload[i]);
            }
            if (record->length > 8) {
                n += snprintf(buf + n, buflen - n, "...");
            }
            n += snprintf(buf + n, buflen - n, "]");
        }
    }

    return n;
}

uint8_t usblog_utilization_pct(void)
{
    usblog_status_t status;
    if (usblog_get_status(&status) != USBLOG_OK) {
        return 0;
    }
    if (g_buffer_size == 0) {
        return 0;
    }
    return (uint8_t)((status.bytes_used * 100) / g_buffer_size);
}
