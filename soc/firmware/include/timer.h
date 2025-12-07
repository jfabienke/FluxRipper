/**
 * FluxRipper SoC - Timer Driver Header
 *
 * AXI Timer driver for MicroBlaze V
 *
 * Updated: 2025-12-03 18:00
 */

#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

/**
 * Initialize timer peripheral
 * Configures as free-running up-counter
 */
void timer_init(void);

/**
 * Get current timer count
 * @return 32-bit counter value
 */
uint32_t timer_get_count(void);

/**
 * Get elapsed time in microseconds
 * @param start starting count value
 * @return microseconds elapsed since start
 */
uint32_t timer_elapsed_us(uint32_t start);

/**
 * Delay for specified microseconds
 * @param us microseconds to delay
 */
void timer_delay_us(uint32_t us);

/**
 * Delay for specified milliseconds
 * @param ms milliseconds to delay
 */
void timer_delay_ms(uint32_t ms);

/**
 * Get system uptime in milliseconds
 * @return milliseconds since timer_init()
 */
uint32_t timer_uptime_ms(void);

#endif /* TIMER_H */
