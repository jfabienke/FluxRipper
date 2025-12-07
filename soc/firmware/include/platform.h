/**
 * FluxRipper SoC - Platform Definitions
 *
 * Hardware addresses and constants for MicroBlaze V SoC
 * Target: AMD Spartan UltraScale+ SCU35
 *
 * Updated: 2025-12-03
 */

#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdint.h>
#include <stdbool.h>

/*============================================================================
 * Memory Map
 *============================================================================*/

/* Local Memory (BRAM) */
#define CODE_BRAM_BASE      0x00000000
#define CODE_BRAM_SIZE      (32 * 1024)     /* 32KB */

#define DATA_BRAM_BASE      0x00010000
#define DATA_BRAM_SIZE      (16 * 1024)     /* 16KB */

/* HyperRAM (Milestone 2+) */
#define HYPERRAM_BASE       0x40000000
#define HYPERRAM_SIZE       (8 * 1024 * 1024)   /* 8MB */

/* Track buffers in HyperRAM */
#define TRACK_BUF_A_BASE    0x40000000
#define TRACK_BUF_A_SIZE    (2 * 1024 * 1024)   /* 2MB */

#define TRACK_BUF_B_BASE    0x40200000
#define TRACK_BUF_B_SIZE    (2 * 1024 * 1024)   /* 2MB */

#define SECTOR_CACHE_BASE   0x40400000
#define SECTOR_CACHE_SIZE   (2 * 1024 * 1024)   /* 2MB */

#define FS_METADATA_BASE    0x40600000
#define FS_METADATA_SIZE    (512 * 1024)        /* 512KB */

#define HEAP_BASE           0x40680000
#define HEAP_SIZE           (1536 * 1024)       /* 1.5MB */

/* Peripherals */
#define PERIPH_BASE         0x80000000

#define FDC_BASE            (PERIPH_BASE + 0x0000)  /* FluxRipper FDC (M1+) */
#define TIMER_BASE          (PERIPH_BASE + 0x1000)  /* AXI Timer */
#define UART_BASE           (PERIPH_BASE + 0x2000)  /* AXI UART Lite */
#define DMA_BASE            (PERIPH_BASE + 0x3000)  /* AXI DMA (M2+) */
#define HYPERRAM_CTRL_BASE  (PERIPH_BASE + 0x4000)  /* HyperRAM Controller (M2+) */
#define INTC_BASE           (PERIPH_BASE + 0x5000)  /* AXI Interrupt Controller */
#define GPIO_BASE           (PERIPH_BASE + 0x6000)  /* AXI GPIO */
#define HDD_BASE            (PERIPH_BASE + 0x7000)  /* HDD Controller (ST-506/ESDI) */
#define I2C_BASE            (PERIPH_BASE + 0x8000)  /* AXI I2C Master */
#define PMU_BASE            (PERIPH_BASE + 0x9000)  /* Power Monitor Unit */

/*============================================================================
 * AXI UART Lite Registers
 *============================================================================*/

#define UART_RX_FIFO        (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_TX_FIFO        (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_STAT           (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_CTRL           (*(volatile uint32_t *)(UART_BASE + 0x0C))

/* UART Status bits */
#define UART_STAT_RX_VALID      (1 << 0)
#define UART_STAT_RX_FULL       (1 << 1)
#define UART_STAT_TX_EMPTY      (1 << 2)
#define UART_STAT_TX_FULL       (1 << 3)
#define UART_STAT_INTR_EN       (1 << 4)
#define UART_STAT_OVERRUN       (1 << 5)
#define UART_STAT_FRAME_ERR     (1 << 6)
#define UART_STAT_PARITY_ERR    (1 << 7)

/* UART Control bits */
#define UART_CTRL_RST_TX        (1 << 0)
#define UART_CTRL_RST_RX        (1 << 1)
#define UART_CTRL_INTR_EN       (1 << 4)

/*============================================================================
 * AXI Timer Registers
 *============================================================================*/

#define TIMER_TCSR0         (*(volatile uint32_t *)(TIMER_BASE + 0x00))
#define TIMER_TLR0          (*(volatile uint32_t *)(TIMER_BASE + 0x04))
#define TIMER_TCR0          (*(volatile uint32_t *)(TIMER_BASE + 0x08))

/* Timer Control/Status bits */
#define TIMER_TCSR_MDT          (1 << 0)    /* Mode: 0=generate, 1=capture */
#define TIMER_TCSR_UDT          (1 << 1)    /* Up/Down: 0=up, 1=down */
#define TIMER_TCSR_GENT         (1 << 2)    /* Generate external signal */
#define TIMER_TCSR_CAPT         (1 << 3)    /* Capture external signal */
#define TIMER_TCSR_ARHT         (1 << 4)    /* Auto reload */
#define TIMER_TCSR_LOAD         (1 << 5)    /* Load timer */
#define TIMER_TCSR_ENIT         (1 << 6)    /* Enable interrupt */
#define TIMER_TCSR_ENT          (1 << 7)    /* Enable timer */
#define TIMER_TCSR_T0INT        (1 << 8)    /* Timer 0 interrupt */
#define TIMER_TCSR_PWMA         (1 << 9)    /* PWM mode */
#define TIMER_TCSR_ENALL        (1 << 10)   /* Enable all timers */
#define TIMER_TCSR_CASC         (1 << 11)   /* Cascade mode */

/*============================================================================
 * AXI GPIO Registers
 *============================================================================*/

#define GPIO_DATA           (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_TRI            (*(volatile uint32_t *)(GPIO_BASE + 0x04))
#define GPIO_DATA2          (*(volatile uint32_t *)(GPIO_BASE + 0x08))
#define GPIO_TRI2           (*(volatile uint32_t *)(GPIO_BASE + 0x0C))

/*============================================================================
 * DC-DC Converter GPIO Bit Assignments (GPIO Channel 2)
 *============================================================================*/

/* 24V Boost Converter (12V → 24V for 8" drives) */
#define DCDC_24V_PGOOD      BIT(0)      /* Input: Power Good */
#define DCDC_24V_ENABLE     BIT(1)      /* Output: Enable */
#define DCDC_24V_FAULT      BIT(2)      /* Input: Fault (OVP/OCP/OTP) */

/* 5V Buck Converter (12V → 5V for drives) */
#define DCDC_5V_PGOOD       BIT(4)      /* Input: Power Good */
#define DCDC_5V_ENABLE      BIT(5)      /* Output: Enable */
#define DCDC_5V_FAULT       BIT(6)      /* Input: Fault */
#define DCDC_5V_MODE        BIT(7)      /* Output: Mode (0=auto, 1=forced PWM) */

/* 3.3V Buck Converter (5V → 3.3V for FPGA I/O) */
#define DCDC_3V3_PGOOD      BIT(8)      /* Input: Power Good */
#define DCDC_3V3_ENABLE     BIT(9)      /* Output: Enable */
#define DCDC_3V3_FAULT      BIT(10)     /* Input: Fault */

/* 1.0V Buck Converter (3.3V → 1.0V for FPGA core) */
#define DCDC_1V0_PGOOD      BIT(12)     /* Input: Power Good */
#define DCDC_1V0_ENABLE     BIT(13)     /* Output: Enable */
#define DCDC_1V0_FAULT      BIT(14)     /* Input: Fault */

/* Combined masks */
#define DCDC_ALL_PGOOD      (DCDC_24V_PGOOD | DCDC_5V_PGOOD | DCDC_3V3_PGOOD | DCDC_1V0_PGOOD)
#define DCDC_ALL_ENABLE     (DCDC_24V_ENABLE | DCDC_5V_ENABLE | DCDC_3V3_ENABLE | DCDC_1V0_ENABLE)
#define DCDC_ALL_FAULT      (DCDC_24V_FAULT | DCDC_5V_FAULT | DCDC_3V3_FAULT | DCDC_1V0_FAULT)

/* GPIO Direction: 0=output, 1=input */
#define DCDC_GPIO_INPUTS    (DCDC_ALL_PGOOD | DCDC_ALL_FAULT)
#define DCDC_GPIO_OUTPUTS   (DCDC_ALL_ENABLE | DCDC_5V_MODE)

/*============================================================================
 * Clock Frequencies
 *============================================================================*/

#define CPU_FREQ_HZ         100000000   /* 100 MHz */
#define AXI_FREQ_HZ         100000000   /* 100 MHz */
#define FDC_FREQ_HZ         200000000   /* 200 MHz (Floppy domain) */
#define HDD_FREQ_HZ         300000000   /* 300 MHz (HDD domain) */

/*============================================================================
 * Interrupt Numbers
 *============================================================================*/

#define IRQ_UART            0
#define IRQ_TIMER           1
#define IRQ_FDC_A           2   /* Milestone 1+ */
#define IRQ_FDC_B           3   /* Milestone 1+ */
#define IRQ_DMA_A           4   /* Milestone 2+ */
#define IRQ_DMA_B           5   /* Milestone 2+ */
#define IRQ_HDD             6   /* HDD Controller */
#define IRQ_I2C             7   /* I2C Controller */
#define IRQ_PMU             8   /* Power Monitor Alert */
#define IRQ_MSC_MEDIA       9   /* MSC Media Change */

/*============================================================================
 * Utility Macros
 *============================================================================*/

#define BIT(n)              (1U << (n))
#define ARRAY_SIZE(a)       (sizeof(a) / sizeof((a)[0]))

/* Memory-mapped register access */
#define REG32(addr)         (*(volatile uint32_t *)(addr))
#define REG16(addr)         (*(volatile uint16_t *)(addr))
#define REG8(addr)          (*(volatile uint8_t *)(addr))

#endif /* PLATFORM_H */
