/**
 * FluxRipper SoC - UART Driver
 *
 * AXI UART Lite driver implementation
 *
 * Updated: 2025-12-03 18:00
 */

#include "uart.h"
#include "platform.h"
#include <stdarg.h>

void uart_init(void)
{
    /* Reset TX and RX FIFOs */
    UART_CTRL = UART_CTRL_RST_TX | UART_CTRL_RST_RX;
}

bool uart_rx_ready(void)
{
    return (UART_STAT & UART_STAT_RX_VALID) != 0;
}

bool uart_tx_ready(void)
{
    return (UART_STAT & UART_STAT_TX_FULL) == 0;
}

char uart_getc(void)
{
    /* Wait for data */
    while (!uart_rx_ready())
        ;
    return (char)(UART_RX_FIFO & 0xFF);
}

bool uart_getc_nb(char *c)
{
    if (!uart_rx_ready())
        return false;
    *c = (char)(UART_RX_FIFO & 0xFF);
    return true;
}

void uart_putc(char c)
{
    /* Wait for space in TX FIFO */
    while (!uart_tx_ready())
        ;
    UART_TX_FIFO = (uint32_t)c;
}

void uart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n')
            uart_putc('\r');
        uart_putc(*s++);
    }
}

/*============================================================================
 * Minimal printf implementation
 *============================================================================*/

static void print_dec(uint32_t val, bool is_signed)
{
    char buf[12];
    int i = 0;
    bool neg = false;

    if (is_signed && (int32_t)val < 0) {
        neg = true;
        val = (uint32_t)(-(int32_t)val);
    }

    if (val == 0) {
        uart_putc('0');
        return;
    }

    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }

    if (neg)
        uart_putc('-');

    while (i > 0)
        uart_putc(buf[--i]);
}

static void print_hex(uint32_t val, bool uppercase)
{
    const char *digits = uppercase ? "0123456789ABCDEF" : "0123456789abcdef";
    char buf[8];
    int i = 0;

    if (val == 0) {
        uart_putc('0');
        return;
    }

    while (val > 0) {
        buf[i++] = digits[val & 0xF];
        val >>= 4;
    }

    while (i > 0)
        uart_putc(buf[--i]);
}

static void print_hex_padded(uint32_t val, int width, bool uppercase)
{
    const char *digits = uppercase ? "0123456789ABCDEF" : "0123456789abcdef";

    for (int i = width - 1; i >= 0; i--) {
        uart_putc(digits[(val >> (i * 4)) & 0xF]);
    }
}

int uart_printf(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);

    int count = 0;
    char c;

    while ((c = *fmt++) != '\0') {
        if (c != '%') {
            if (c == '\n')
                uart_putc('\r');
            uart_putc(c);
            count++;
            continue;
        }

        c = *fmt++;
        switch (c) {
        case 's': {
            const char *s = va_arg(args, const char *);
            if (!s) s = "(null)";
            while (*s) {
                uart_putc(*s++);
                count++;
            }
            break;
        }
        case 'c':
            uart_putc((char)va_arg(args, int));
            count++;
            break;
        case 'd':
        case 'i':
            print_dec((uint32_t)va_arg(args, int), true);
            count++;  /* Approximate */
            break;
        case 'u':
            print_dec(va_arg(args, uint32_t), false);
            count++;
            break;
        case 'x':
            print_hex(va_arg(args, uint32_t), false);
            count++;
            break;
        case 'X':
            print_hex(va_arg(args, uint32_t), true);
            count++;
            break;
        case 'p':
            uart_puts("0x");
            print_hex_padded((uint32_t)va_arg(args, void *), 8, false);
            count += 10;
            break;
        case '%':
            uart_putc('%');
            count++;
            break;
        case '\0':
            goto done;
        default:
            uart_putc('%');
            uart_putc(c);
            count += 2;
            break;
        }
    }

done:
    va_end(args);
    return count;
}

int uart_readline(char *buf, int maxlen)
{
    int i = 0;
    char c;

    while (i < maxlen - 1) {
        c = uart_getc();

        if (c == '\r' || c == '\n') {
            uart_puts("\r\n");
            break;
        }

        if (c == '\b' || c == 0x7F) {  /* Backspace or DEL */
            if (i > 0) {
                i--;
                uart_puts("\b \b");  /* Erase character */
            }
            continue;
        }

        if (c == 0x03) {  /* Ctrl+C */
            uart_puts("^C\r\n");
            buf[0] = '\0';
            return 0;
        }

        if (c >= 0x20 && c < 0x7F) {  /* Printable */
            buf[i++] = c;
            uart_putc(c);  /* Echo */
        }
    }

    buf[i] = '\0';
    return i;
}

void uart_hexdump(const void *addr, uint32_t len)
{
    const uint8_t *p = (const uint8_t *)addr;
    uint32_t offset = 0;

    while (offset < len) {
        /* Address */
        uart_printf("%p: ", (void *)((uint32_t)addr + offset));

        /* Hex bytes */
        for (int i = 0; i < 16; i++) {
            if (offset + i < len) {
                print_hex_padded(p[offset + i], 2, false);
                uart_putc(' ');
            } else {
                uart_puts("   ");
            }
            if (i == 7)
                uart_putc(' ');
        }

        uart_puts(" |");

        /* ASCII */
        for (int i = 0; i < 16 && offset + i < len; i++) {
            char c = p[offset + i];
            uart_putc((c >= 0x20 && c < 0x7F) ? c : '.');
        }

        uart_puts("|\n");
        offset += 16;
    }
}
