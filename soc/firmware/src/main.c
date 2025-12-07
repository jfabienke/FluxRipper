/**
 * FluxRipper SoC - Main Entry Point
 *
 * Milestone 0: Basic SoC bring-up
 * - MicroBlaze V (RV32IMC) @ 100 MHz
 * - UART CLI interface
 * - Timer peripheral
 * - Memory test capability
 *
 * Updated: 2025-12-03 18:00
 */

#include "platform.h"
#include "uart.h"
#include "timer.h"
#include "cli.h"
#include "msc_config.h"

/*============================================================================
 * Early Initialization
 *============================================================================*/

/**
 * Minimal BSP initialization
 * Called before main() by crt0
 */
void _init(void)
{
    /* Hardware is already configured by bitstream */
    /* Nothing to do here for M0 */
}

/**
 * Cleanup (not used in bare-metal)
 */
void _fini(void)
{
}

/*============================================================================
 * Main
 *============================================================================*/

int main(void)
{
    /* Initialize peripherals */
    uart_init();
    timer_init();

    /* Initialize CLI */
    cli_init();

    /* Run CLI loop (never returns) */
    cli_run();

    /* Should never reach here */
    return 0;
}

/*============================================================================
 * Interrupt Handlers (stubs for M0)
 *============================================================================*/

/**
 * Default trap handler
 */
void trap_handler(void) __attribute__((interrupt));
void trap_handler(void)
{
    uart_puts("\n*** TRAP ***\n");
    while (1)
        ;
}

/**
 * External interrupt handler
 * Dispatches to appropriate handler based on interrupt source
 */
void external_interrupt_handler(void) __attribute__((interrupt));
void external_interrupt_handler(void)
{
    /* Read interrupt controller status to determine source */
    /* For now, assume MSC media change is the only enabled interrupt */
    /* In M1+, will read INTC_ISR to determine source */

    uint32_t int_ctrl = msc_config_read_int_ctrl();
    uint32_t pending = (int_ctrl >> 4) & 0x0F;
    uint32_t enabled = int_ctrl & 0x0F;

    /* Check if MSC media change interrupt is active */
    if (pending & enabled) {
        msc_config_irq_handler();
    }

    /* Additional interrupt sources will be added in M1+:
     * - IRQ_FDC_A, IRQ_FDC_B: FDC completion
     * - IRQ_DMA_A, IRQ_DMA_B: DMA completion
     * - IRQ_HDD: HDD controller
     */
}
