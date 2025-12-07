/**
 * FluxRipper SoC - UART Driver Header
 *
 * AXI UART Lite driver for MicroBlaze V
 *
 * Updated: 2025-12-03 18:00
 */

#ifndef UART_H
#define UART_H

#include <stdint.h>
#include <stdbool.h>

/**
 * Initialize UART peripheral
 * Resets TX/RX FIFOs
 */
void uart_init(void);

/**
 * Check if receive data is available
 * @return true if at least one byte available
 */
bool uart_rx_ready(void);

/**
 * Check if transmit FIFO has space
 * @return true if can accept a byte
 */
bool uart_tx_ready(void);

/**
 * Read a single character (blocking)
 * @return received character
 */
char uart_getc(void);

/**
 * Read a single character (non-blocking)
 * @param c pointer to store character
 * @return true if character was read, false if no data
 */
bool uart_getc_nb(char *c);

/**
 * Write a single character (blocking)
 * @param c character to send
 */
void uart_putc(char c);

/**
 * Write a null-terminated string
 * @param s string to send
 */
void uart_puts(const char *s);

/**
 * Print formatted string (minimal printf)
 * Supports: %s, %c, %d, %u, %x, %X, %p, %%
 * @param fmt format string
 * @return number of characters written
 */
int uart_printf(const char *fmt, ...);

/**
 * Read a line into buffer (with echo and backspace)
 * @param buf buffer to store line
 * @param maxlen maximum characters to read (including null)
 * @return number of characters read (excluding null)
 */
int uart_readline(char *buf, int maxlen);

/**
 * Print hexdump of memory region
 * @param addr starting address
 * @param len number of bytes to dump
 */
void uart_hexdump(const void *addr, uint32_t len);

#endif /* UART_H */
