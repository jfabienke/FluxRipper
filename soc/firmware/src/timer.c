/**
 * FluxRipper SoC - Timer Driver
 *
 * AXI Timer driver implementation
 *
 * Updated: 2025-12-03 18:00
 */

#include "timer.h"
#include "platform.h"

/* Clocks per microsecond */
#define CLKS_PER_US     (CPU_FREQ_HZ / 1000000)

/* Uptime tracking */
static volatile uint32_t uptime_overflows = 0;
static uint32_t last_count = 0;

void timer_init(void)
{
    /* Load max value for free-running */
    TIMER_TLR0 = 0xFFFFFFFF;

    /* Configure: up counter, auto-reload, enable */
    TIMER_TCSR0 = TIMER_TCSR_LOAD;  /* Load counter */
    TIMER_TCSR0 = TIMER_TCSR_ENT | TIMER_TCSR_ARHT;  /* Enable, auto-reload */

    uptime_overflows = 0;
    last_count = 0;
}

uint32_t timer_get_count(void)
{
    return TIMER_TCR0;
}

uint32_t timer_elapsed_us(uint32_t start)
{
    uint32_t now = timer_get_count();
    uint32_t elapsed;

    /* Handle wrap-around (up counter) */
    if (now >= start)
        elapsed = now - start;
    else
        elapsed = (0xFFFFFFFF - start) + now + 1;

    return elapsed / CLKS_PER_US;
}

void timer_delay_us(uint32_t us)
{
    uint32_t start = timer_get_count();
    uint32_t target = us * CLKS_PER_US;

    while (timer_elapsed_us(start) < us)
        ;
}

void timer_delay_ms(uint32_t ms)
{
    while (ms > 0) {
        timer_delay_us(1000);
        ms--;
    }
}

uint32_t timer_uptime_ms(void)
{
    uint32_t count = timer_get_count();

    /* Detect overflow */
    if (count < last_count) {
        uptime_overflows++;
    }
    last_count = count;

    /* Calculate total milliseconds */
    /* At 100 MHz, 32-bit counter overflows every ~42.9 seconds */
    uint32_t ms_from_count = count / (CLKS_PER_US * 1000);
    uint32_t ms_from_overflows = uptime_overflows * 42949;  /* ~42949 ms per overflow */

    return ms_from_overflows + ms_from_count;
}
