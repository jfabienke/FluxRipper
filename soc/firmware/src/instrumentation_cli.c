/**
 * FluxRipper Instrumentation CLI Commands
 *
 * Command-line interface for diagnostic instrumentation
 *
 * Created: 2025-12-04 14:15
 * Updated: 2025-12-07 14:20 - Added system diagnostics (drives, version, uptime, clocks, i2c, temp, gpio, mem)
 */

#include "cli.h"
#include "instrumentation_hal.h"
#include "power_hal.h"
#include "usb_logger_hal.h"
#include "system_hal.h"
#include "uart.h"
#include <string.h>
#include <stdlib.h>

/*============================================================================
 * Error Counter Display
 *============================================================================*/

static int cmd_diag_errors(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    diag_errors_t errors;
    int ret = diag_read_errors(&errors);

    if (ret != DIAG_OK) {
        uart_puts("Failed to read error counters.\n");
        return -1;
    }

    uart_puts("\nLifetime Error Counters\n");
    uart_puts("-----------------------------------------\n");
    uart_printf("  CRC Data:       %lu\n", errors.crc_data);
    uart_printf("  CRC Address:    %lu\n", errors.crc_addr);
    uart_printf("  Missing AM:     %lu\n", errors.missing_am);
    uart_printf("  Missing DAM:    %lu\n", errors.missing_dam);
    uart_printf("  Overrun:        %lu\n", errors.overrun);
    uart_printf("  Underrun:       %lu\n", errors.underrun);
    uart_printf("  Seek:           %lu\n", errors.seek);
    uart_printf("  Write Fault:    %lu\n", errors.write_fault);
    uart_printf("  PLL Unlock:     %lu\n", errors.pll_unlock);
    uart_puts("-----------------------------------------\n");
    uart_printf("  Total:          %lu\n", errors.total);
    uart_printf("  Error Rate:     %u per 1000 ops\n", errors.error_rate);
    uart_puts("-----------------------------------------\n");

    return 0;
}

/*============================================================================
 * PLL Diagnostics Display
 *============================================================================*/

static int cmd_diag_pll(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    /* Trigger snapshot first */
    diag_snapshot_pll();

    diag_pll_t pll;
    int ret = diag_read_pll(&pll);

    if (ret != DIAG_OK) {
        uart_puts("Failed to read PLL diagnostics.\n");
        return -1;
    }

    uart_puts("\nPLL/DPLL Diagnostics\n");
    uart_puts("-----------------------------------------\n");

    uart_puts("Phase Error:\n");
    uart_printf("  Instantaneous:  %d\n", pll.phase_error);
    uart_printf("  Average (EMA):  %d\n", pll.phase_avg);
    uart_printf("  Peak:           %d\n", pll.phase_peak);

    uart_puts("\nFrequency:\n");
    uart_printf("  NCO Word:       0x%08lX\n", pll.freq_word);
    uart_printf("  Offset:         %ld PPM\n", pll.freq_offset_ppm);

    uart_puts("\nLock Statistics:\n");
    uart_printf("  Lock Time:      %lu clocks\n", pll.lock_time);
    uart_printf("  Total Locked:   %lu clocks\n", pll.total_lock_time);
    uart_printf("  Unlock Events:  %lu\n", pll.unlock_count);

    uart_puts("\nQuality (0-255):\n");
    uart_printf("  Min/Avg/Max:    %u / %u / %u\n",
                pll.quality_min, pll.quality_avg, pll.quality_max);

    uart_puts("\nPhase Error Histogram:\n");
    uart_puts("  [Very Early] ");
    for (int i = 0; i < 8; i++) {
        uart_printf("%5u ", pll.histogram[i]);
    }
    uart_puts("[Very Late]\n");

    /* ASCII bar chart */
    uint16_t max_val = 1;
    for (int i = 0; i < 8; i++) {
        if (pll.histogram[i] > max_val) max_val = pll.histogram[i];
    }

    for (int row = 4; row >= 0; row--) {
        uart_puts("  ");
        for (int i = 0; i < 8; i++) {
            uint16_t threshold = (max_val * row) / 4;
            if (pll.histogram[i] > threshold) {
                uart_puts("##### ");
            } else {
                uart_puts("      ");
            }
        }
        uart_puts("\n");
    }
    uart_puts("  -3sig -2sig -1sig  <0   >0  +1sig +2sig +3sig\n");
    uart_puts("-----------------------------------------\n");

    return 0;
}

/*============================================================================
 * FIFO Statistics Display
 *============================================================================*/

static int cmd_diag_fifo(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    diag_fifo_t fifo;
    int ret = diag_read_fifo(&fifo);

    if (ret != DIAG_OK) {
        uart_puts("Failed to read FIFO statistics.\n");
        return -1;
    }

    uart_puts("\nFIFO Statistics\n");
    uart_puts("-----------------------------------------\n");

    uart_puts("Fill Level:\n");
    uart_printf("  Peak:           %u\n", fifo.peak_level);
    uart_printf("  Minimum:        %u\n", fifo.min_level);
    uart_printf("  Utilization:    %u%%\n", fifo.utilization_pct);

    uart_puts("\nEvent Counts:\n");
    uart_printf("  Overflows:      %lu", fifo.overflow_count);
    if (fifo.overflow_flag) uart_puts(" [STICKY]");
    uart_puts("\n");
    uart_printf("  Underruns:      %lu", fifo.underrun_count);
    if (fifo.underrun_flag) uart_puts(" [STICKY]");
    uart_puts("\n");
    uart_printf("  Backpressure:   %lu\n", fifo.backpressure_cnt);

    uart_puts("\nThroughput:\n");
    uart_printf("  Total Writes:   %lu\n", fifo.total_writes);
    uart_printf("  Total Reads:    %lu\n", fifo.total_reads);

    uart_puts("\nTiming (clocks):\n");
    uart_printf("  Time at Peak:   %lu\n", fifo.time_at_peak);
    uart_printf("  Time Empty:     %lu\n", fifo.time_empty);
    uart_printf("  Time Full:      %lu\n", fifo.time_full);
    uart_puts("-----------------------------------------\n");

    /* Health assessment */
    uart_puts("Health: ");
    if (fifo.overflow_flag || fifo.underrun_flag) {
        uart_puts("WARNING - ");
        if (fifo.overflow_flag) uart_puts("Overflow detected! ");
        if (fifo.underrun_flag) uart_puts("Underrun detected!");
        uart_puts("\n");
    } else if (fifo.utilization_pct > 90) {
        uart_puts("HIGH UTILIZATION\n");
    } else {
        uart_puts("OK\n");
    }

    return 0;
}

/*============================================================================
 * Capture Timing Display
 *============================================================================*/

static int cmd_diag_capture(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    diag_capture_t capture;
    int ret = diag_read_capture(&capture);

    if (ret != DIAG_OK) {
        uart_puts("Failed to read capture timing.\n");
        return -1;
    }

    /* Assume 200 MHz clock for conversions */
    const uint32_t clk_mhz = 200;

    uart_puts("\nCapture Timing Statistics\n");
    uart_puts("-----------------------------------------\n");

    uart_printf("Duration:           %lu clocks (%lu ms)\n",
                capture.duration,
                diag_clocks_to_ms(capture.duration, clk_mhz));

    uart_puts("\nFirst Events:\n");
    uart_printf("  Time to 1st flux: %lu clocks (%lu us)\n",
                capture.time_to_first_flux,
                diag_clocks_to_us(capture.time_to_first_flux, clk_mhz));
    uart_printf("  Time to 1st idx:  %lu clocks (%lu us)\n",
                capture.time_to_first_idx,
                diag_clocks_to_us(capture.time_to_first_idx, clk_mhz));

    uart_puts("\nIndex Period:\n");
    uart_printf("  Last:             %lu clocks (%lu us)\n",
                capture.index_period_last,
                diag_clocks_to_us(capture.index_period_last, clk_mhz));
    uart_printf("  Min:              %lu clocks (%lu us)\n",
                capture.index_period_min,
                diag_clocks_to_us(capture.index_period_min, clk_mhz));
    uart_printf("  Max:              %lu clocks (%lu us)\n",
                capture.index_period_max,
                diag_clocks_to_us(capture.index_period_max, clk_mhz));
    uart_printf("  Avg (EMA):        %lu clocks (%lu us)\n",
                capture.index_period_avg,
                diag_clocks_to_us(capture.index_period_avg, clk_mhz));

    /* Calculate RPM from average index period */
    if (capture.index_period_avg > 0) {
        uint32_t us = diag_clocks_to_us(capture.index_period_avg, clk_mhz);
        if (us > 0) {
            uint32_t rpm = 60000000UL / us;
            uart_printf("  Calculated RPM:   %lu\n", rpm);
        }
    }

    uart_puts("\nFlux Intervals:\n");
    uart_printf("  Min:              %lu clocks\n", capture.flux_interval_min);
    uart_printf("  Max:              %lu clocks\n", capture.flux_interval_max);
    uart_printf("  Count:            %u transitions\n", capture.flux_count);
    uart_puts("-----------------------------------------\n");

    return 0;
}

/*============================================================================
 * Seek Histogram Display (HDD)
 *============================================================================*/

static int cmd_diag_seek(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    diag_seek_t seek;
    int ret = diag_read_seek(&seek);

    if (ret != DIAG_OK) {
        uart_puts("Failed to read seek histogram.\n");
        return -1;
    }

    uart_puts("\nSeek Distance Histogram (HDD)\n");
    uart_puts("-----------------------------------------\n");

    uart_puts("Distance Bucket     Count    Avg Time\n");
    uart_puts("-----------------------------------------\n");

    for (int i = 0; i < 8; i++) {
        const char *name = diag_seek_bucket_name(i);
        uart_printf("  %-12s %8u    %5u us\n",
                    name, seek.count[i], seek.time_us[i]);
    }

    uart_puts("-----------------------------------------\n");
    uart_printf("  Total Seeks:      %lu\n", seek.total_seeks);
    uart_printf("  Total Errors:     %lu\n", seek.total_errors);
    uart_printf("  Average Time:     %u us\n", seek.avg_time_us);
    uart_printf("  Min Time:         %u us\n", seek.min_time_us);
    uart_printf("  Max Time:         %u us\n", seek.max_time_us);

    uart_puts("\nErrors by Distance:\n");
    uart_printf("  Short (<25 cyl):  %u\n", seek.errors_short);
    uart_printf("  Medium (25-100):  %u\n", seek.errors_medium);
    uart_printf("  Long (>100 cyl):  %u\n", seek.errors_long);
    uart_puts("-----------------------------------------\n");

    /* ASCII histogram bar chart */
    uint16_t max_count = 1;
    for (int i = 0; i < 8; i++) {
        if (seek.count[i] > max_count) max_count = seek.count[i];
    }

    uart_puts("\nDistribution:\n");
    for (int i = 0; i < 8; i++) {
        uint16_t bars = (seek.count[i] * 30) / max_count;
        uart_printf("  %d: ", i);
        for (uint16_t b = 0; b < bars; b++) {
            uart_puts("#");
        }
        uart_puts("\n");
    }

    return 0;
}

/*============================================================================
 * Clear Statistics
 *============================================================================*/

static int cmd_diag_clear(int argc, char *argv[])
{
    if (argc >= 2) {
        /* Clear specific category */
        if (strcmp(argv[1], "errors") == 0) {
            diag_clear_errors();
            uart_puts("Error counters cleared.\n");
        } else if (strcmp(argv[1], "pll") == 0) {
            diag_clear_pll();
            uart_puts("PLL statistics cleared.\n");
        } else if (strcmp(argv[1], "fifo") == 0) {
            diag_clear_fifo();
            uart_puts("FIFO statistics cleared.\n");
        } else if (strcmp(argv[1], "capture") == 0) {
            diag_clear_capture();
            uart_puts("Capture timing cleared.\n");
        } else if (strcmp(argv[1], "seek") == 0) {
            diag_clear_seek();
            uart_puts("Seek histogram cleared.\n");
        } else {
            uart_puts("Unknown category. Use: errors, pll, fifo, capture, seek\n");
            return -1;
        }
    } else {
        /* Clear all */
        diag_clear_all();
        uart_puts("All diagnostic statistics cleared.\n");
    }

    return 0;
}

/*============================================================================
 * Show All Statistics
 *============================================================================*/

/*============================================================================
 * Power Rail Display
 *============================================================================*/

static void print_voltage_diag(uint16_t mv)
{
    uart_printf("%u.%02uV", mv / 1000, (mv % 1000) / 10);
}

static void print_current_diag(int16_t ma)
{
    if (ma < 0) {
        uart_printf("-%umA", (uint16_t)(-ma));
    } else {
        uart_printf("%umA", (uint16_t)ma);
    }
}

static void print_power_diag(uint16_t mw)
{
    if (mw >= 1000) {
        uart_printf("%u.%02uW", mw / 1000, (mw % 1000) / 10);
    } else {
        uart_printf("%umW", mw);
    }
}

static const char *get_conn_status_diag(pwr_conn_status_t *c)
{
    if (c->fault) return "FAULT!";
    if (!c->enabled) return "OFF";
    if (!c->present) return "N/C";
    return "OK";
}

static int cmd_diag_power(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    pmu_system_t sys;
    int ret = pmu_read_all(&sys);

    if (ret != PMU_OK) {
        uart_puts("Failed to read power status (INA3221 not detected?)\n");
        return -1;
    }

    uart_puts("\nPower Summary (6 Drive Connectors)\n");
    uart_puts("=======================================================\n");

    /* Input sources */
    uart_puts("Input:   ");
    switch (sys.active_source) {
        case PWR_SRC_USB_C: uart_puts("USB-C PD"); break;
        case PWR_SRC_ATX:   uart_puts("ATX PSU"); break;
        case PWR_SRC_BOTH:  uart_puts("USB-C + ATX"); break;
        default:            uart_puts("NONE"); break;
    }
    uart_printf("  (%luW available)\n",
        (sys.usbc_status.voltage_mv * sys.usbc_status.current_ma) / 1000000);

    uart_puts("-------------------------------------------------------\n");
    uart_puts("  Conn     5V Rail       12V Rail      Total   Status\n");
    uart_puts("-------------------------------------------------------\n");

    /* Display 6 connectors */
    for (int i = 0; i < PWR_CONN_COUNT; i++) {
        pwr_conn_status_t *c = &sys.connectors[i];

        uart_printf("  %-5s   ", pwr_conn_name((pwr_conn_t)i));

        /* 5V rail */
        if (c->rail_5v.valid) {
            print_voltage_diag(c->rail_5v.voltage_mv);
            uart_printf("/%4umA  ", c->rail_5v.current_ma);
        } else {
            uart_puts("  --/--     ");
        }

        /* 12V rail (or 24V for 8" mode on FDD3) */
        if (c->rail_12v.valid) {
            print_voltage_diag(c->rail_12v.voltage_mv);
            uart_printf("/%4umA  ", c->rail_12v.current_ma);
        } else {
            uart_puts("  --/--     ");
        }

        /* Total power */
        if (c->enabled && (c->rail_5v.valid || c->rail_12v.valid)) {
            print_power_diag(c->total_power_mw);
        } else {
            uart_puts("  --");
        }
        uart_puts("  ");

        /* Status */
        uart_printf("%-6s", get_conn_status_diag(c));

        /* 8" mode indicator */
        if (i == PWR_CONN_FDD3 && pwr_conn_is_8inch_mode()) {
            uart_puts("[24V]");
        }
        uart_puts("\n");
    }

    uart_puts("-------------------------------------------------------\n");

    /* System rails summary */
    uart_puts("System:  3V3 IO: ");
    if (sys.rails[PMU_RAIL_3V3_IO].valid) {
        print_voltage_diag(sys.rails[PMU_RAIL_3V3_IO].voltage_mv);
    } else {
        uart_puts("--");
    }
    uart_puts("   1V0 Core: ");
    if (sys.rails[PMU_RAIL_1V0_CORE].valid) {
        print_voltage_diag(sys.rails[PMU_RAIL_1V0_CORE].voltage_mv);
    } else {
        uart_puts("--");
    }
    if (pwr_conn_is_8inch_mode()) {
        uart_puts("   24V: ");
        if (sys.rails[PMU_RAIL_24V_8INCH].valid) {
            print_voltage_diag(sys.rails[PMU_RAIL_24V_8INCH].voltage_mv);
        } else {
            uart_puts("--");
        }
    }
    uart_puts("\n");

    uart_puts("-------------------------------------------------------\n");

    /* Power totals */
    uart_printf("  FDD Power:  ");
    print_power_diag(sys.fdd_power_mw);
    uart_printf("   HDD Power: ");
    print_power_diag(sys.hdd_power_mw);
    uart_printf("   System: ");
    print_power_diag(sys.system_power_mw);
    uart_puts("\n");

    uart_printf("  TOTAL:      ");
    print_power_diag(sys.total_power_mw);

    /* Power budget */
    uint32_t available, allocated, remaining;
    pwr_budget_report(&available, &allocated, &remaining);
    if (available > 0) {
        uart_printf("  (%lu%% of %luW budget)",
            (allocated * 100) / available, available / 1000);
    }
    uart_puts("\n");
    uart_puts("=======================================================\n");

    /* DC-DC converter summary */
    uart_puts("DC-DC:   ");
    uint8_t faults = dcdc_check_faults();
    if (faults) {
        uart_puts("FAULT(");
        if (faults & (1 << DCDC_24V_BOOST)) uart_puts("24V ");
        if (faults & (1 << DCDC_5V_BUCK)) uart_puts("5V ");
        if (faults & (1 << DCDC_3V3_BUCK)) uart_puts("3V3 ");
        if (faults & (1 << DCDC_1V0_BUCK)) uart_puts("1V0 ");
        uart_puts(")");
    } else if (dcdc_all_pgood()) {
        uart_puts("All PGOOD");
    } else {
        uart_puts("Starting...");
    }
    uart_puts("\n");

    /* INA3221 presence (now 6 devices: A-F) */
    uart_puts("INA3221: ");
    int found = 0;
    const char *names[] = {"A", "B", "C", "D", "E", "F"};
    for (int i = 0; i < INA3221_COUNT_TOTAL; i++) {
        if (sys.ina3221_present[i]) {
            uart_printf("%s ", names[i]);
            found++;
        }
    }
    if (!found) uart_puts("None");
    uart_printf("(%d/6)\n", found);

    return 0;
}

/*============================================================================
 * USB Traffic Logger Commands
 *============================================================================*/

static int cmd_diag_usb_status(void)
{
    usblog_status_t status;
    int ret = usblog_get_status(&status);

    if (ret != USBLOG_OK) {
        uart_puts("USB logger not initialized\n");
        return -1;
    }

    uart_puts("\nUSB Traffic Logger Status\n");
    uart_puts("-----------------------------------------\n");
    uart_printf("  Capture:      %s\n", status.enabled ? "ENABLED" : "disabled");
    uart_printf("  Triggered:    %s\n", status.triggered ? "YES" : "no");
    uart_printf("  Overflow:     %s\n", status.overflow ? "YES!" : "no");
    uart_printf("  Wrapped:      %s\n", status.wrapped ? "yes" : "no");
    uart_puts("-----------------------------------------\n");
    uart_printf("  Transactions: %lu\n", status.trans_count);
    uart_printf("  Buffer Used:  %lu / %u bytes (%u%%)\n",
        status.bytes_used, USBLOG_BUFFER_SIZE, usblog_utilization_pct());
    uart_printf("  Write Ptr:    0x%04lX\n", status.write_ptr);
    uart_printf("  Read Ptr:     0x%04lX\n", status.read_ptr);
    uart_puts("-----------------------------------------\n");

    /* Show current filter */
    usblog_filter_t filter;
    usblog_get_filter(&filter);
    uart_puts("  Filter:       EP=");
    if (filter.ep_mask == USBLOG_FILTER_EP_ALL) {
        uart_puts("all");
    } else {
        if (filter.ep_mask & USBLOG_FILTER_EP0) uart_puts("0");
        if (filter.ep_mask & USBLOG_FILTER_EP1) uart_puts("1");
        if (filter.ep_mask & USBLOG_FILTER_EP2) uart_puts("2");
        if (filter.ep_mask & USBLOG_FILTER_EP3) uart_puts("3");
    }
    uart_puts(" Types=");
    if (filter.capture_tokens) uart_puts("T");
    if (filter.capture_data) uart_puts("D");
    if (filter.capture_hs) uart_puts("H");
    if (filter.filter_dir) {
        uart_printf(" Dir=%s", filter.dir_in ? "IN" : "OUT");
    }
    uart_puts("\n");

    return 0;
}

static int cmd_diag_usb_start(int argc, char *argv[])
{
    usblog_trigger_t trigger = {0};

    /* Check for trigger PID argument */
    if (argc >= 2) {
        if (strcmp(argv[1], "setup") == 0) {
            trigger.enabled = true;
            trigger.pid = USB_PID_SETUP;
        } else if (strcmp(argv[1], "in") == 0) {
            trigger.enabled = true;
            trigger.pid = USB_PID_IN;
        } else if (strcmp(argv[1], "out") == 0) {
            trigger.enabled = true;
            trigger.pid = USB_PID_OUT;
        } else if (strcmp(argv[1], "data0") == 0) {
            trigger.enabled = true;
            trigger.pid = USB_PID_DATA0;
        } else if (strcmp(argv[1], "nak") == 0) {
            trigger.enabled = true;
            trigger.pid = USB_PID_NAK;
        } else if (strcmp(argv[1], "stall") == 0) {
            trigger.enabled = true;
            trigger.pid = USB_PID_STALL;
        }
    }

    int ret = usblog_start(trigger.enabled ? &trigger : NULL);
    if (ret == USBLOG_OK) {
        if (trigger.enabled) {
            uart_printf("USB capture started, trigger on %s\n",
                usblog_pid_name(trigger.pid));
        } else {
            uart_puts("USB capture started (immediate)\n");
        }
    } else {
        uart_puts("Failed to start capture\n");
    }
    return ret;
}

static int cmd_diag_usb_stop(void)
{
    int ret = usblog_stop();
    if (ret == USBLOG_OK) {
        usblog_status_t status;
        usblog_get_status(&status);
        uart_printf("USB capture stopped. %lu transactions captured.\n",
            status.trans_count);
    }
    return ret;
}

static int cmd_diag_usb_clear(void)
{
    int ret = usblog_clear();
    if (ret == USBLOG_OK) {
        uart_puts("USB capture buffer cleared\n");
    }
    return ret;
}

static int cmd_diag_usb_dump(int argc, char *argv[])
{
    int max_records = 20;  /* Default */
    if (argc >= 2) {
        max_records = atoi(argv[1]);
        if (max_records <= 0) max_records = 20;
        if (max_records > 1000) max_records = 1000;
    }

    uart_puts("\nUSB Traffic Dump\n");
    uart_puts("================================================================\n");
    uart_puts("  Time (ms)    Dir   PID    EP  Dir   Payload\n");
    uart_puts("----------------------------------------------------------------\n");

    usblog_rewind();

    char buf[128];
    usblog_record_t record;
    int count = 0;

    while (count < max_records && usblog_read_record(&record) == USBLOG_OK) {
        usblog_format_record(&record, buf, sizeof(buf));
        uart_printf("  %s\n", buf);
        count++;
    }

    uart_puts("----------------------------------------------------------------\n");
    uart_printf("  Showing %d records\n", count);
    uart_puts("================================================================\n");

    return 0;
}

/* UART write callback for PCAP export */
static void uart_write_bytes(const uint8_t *data, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++) {
        uart_putc(data[i]);
    }
}

static int cmd_diag_usb_export(void)
{
    uart_puts("Exporting PCAP... (use terminal to capture binary output)\n");
    uart_puts("PCAP_START\n");

    int count = usblog_export_pcap(uart_write_bytes);

    uart_puts("\nPCAP_END\n");
    uart_printf("Exported %d records\n", count);

    return 0;
}

static int cmd_diag_usb_filter(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: diag usb filter <options>\n");
        uart_puts("  all        - Capture all traffic (default)\n");
        uart_puts("  ep0        - Endpoint 0 only (control)\n");
        uart_puts("  ep1        - Endpoint 1 only\n");
        uart_puts("  ep2        - Endpoint 2 only\n");
        uart_puts("  data       - Data packets only\n");
        uart_puts("  tokens     - Tokens only\n");
        uart_puts("  hs         - Handshakes only\n");
        uart_puts("  in         - IN direction only\n");
        uart_puts("  out        - OUT direction only\n");
        return 0;
    }

    usblog_filter_t filter = {
        .ep_mask = USBLOG_FILTER_EP_ALL,
        .filter_dir = false,
        .capture_tokens = true,
        .capture_data = true,
        .capture_hs = true
    };

    const char *arg = argv[1];

    if (strcmp(arg, "all") == 0) {
        /* Default - capture everything */
    } else if (strcmp(arg, "ep0") == 0) {
        filter.ep_mask = USBLOG_FILTER_EP0;
    } else if (strcmp(arg, "ep1") == 0) {
        filter.ep_mask = USBLOG_FILTER_EP1;
    } else if (strcmp(arg, "ep2") == 0) {
        filter.ep_mask = USBLOG_FILTER_EP2;
    } else if (strcmp(arg, "data") == 0) {
        filter.capture_tokens = false;
        filter.capture_hs = false;
    } else if (strcmp(arg, "tokens") == 0) {
        filter.capture_data = false;
        filter.capture_hs = false;
    } else if (strcmp(arg, "hs") == 0) {
        filter.capture_tokens = false;
        filter.capture_data = false;
    } else if (strcmp(arg, "in") == 0) {
        filter.filter_dir = true;
        filter.dir_in = true;
    } else if (strcmp(arg, "out") == 0) {
        filter.filter_dir = true;
        filter.dir_in = false;
    } else {
        uart_printf("Unknown filter: %s\n", arg);
        return -1;
    }

    usblog_set_filter(&filter);
    uart_printf("Filter set: %s\n", arg);
    return 0;
}

static int cmd_diag_usb(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("USB Logger Commands:\n");
        uart_puts("  diag usb status           - Show logger status\n");
        uart_puts("  diag usb start [trigger]  - Start capture (trigger: setup,in,out,nak,stall)\n");
        uart_puts("  diag usb stop             - Stop capture\n");
        uart_puts("  diag usb clear            - Clear buffer\n");
        uart_puts("  diag usb dump [n]         - Show last n transactions (default 20)\n");
        uart_puts("  diag usb export           - Export as PCAP (binary)\n");
        uart_puts("  diag usb filter <type>    - Set capture filter\n");
        return cmd_diag_usb_status();
    }

    const char *subcmd = argv[1];

    if (strcmp(subcmd, "status") == 0) {
        return cmd_diag_usb_status();
    } else if (strcmp(subcmd, "start") == 0) {
        return cmd_diag_usb_start(argc - 1, &argv[1]);
    } else if (strcmp(subcmd, "stop") == 0) {
        return cmd_diag_usb_stop();
    } else if (strcmp(subcmd, "clear") == 0) {
        return cmd_diag_usb_clear();
    } else if (strcmp(subcmd, "dump") == 0) {
        return cmd_diag_usb_dump(argc - 1, &argv[1]);
    } else if (strcmp(subcmd, "export") == 0) {
        return cmd_diag_usb_export();
    } else if (strcmp(subcmd, "filter") == 0) {
        return cmd_diag_usb_filter(argc - 1, &argv[1]);
    } else {
        uart_printf("Unknown USB command: %s\n", subcmd);
        return -1;
    }
}

/*============================================================================
 * Version Display
 *============================================================================*/

static int cmd_diag_version(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    version_info_t ver;
    fpga_info_t fpga;

    sys_get_version(&ver);
    sys_get_fpga_info(&fpga);

    uart_puts("\nFluxRipper Version Information\n");
    uart_puts("-----------------------------------------\n");

    uart_puts("Firmware:\n");
    uart_printf("  Version:        %u.%u.%u\n", ver.major, ver.minor, ver.patch);
    uart_printf("  Build Date:     %s %s\n", ver.build_date, ver.build_time);
    uart_printf("  Git Branch:     %s\n", ver.git_branch);
    uart_printf("  Git Hash:       %s%s\n", ver.git_hash, ver.git_dirty ? " (dirty)" : "");

    uart_puts("\nFPGA Bitstream:\n");
    uart_printf("  Device ID:      0x%08lX\n", fpga.device_id);
    uart_printf("  Bitstream ID:   0x%08lX\n", fpga.bitstream_id);
    uart_printf("  Build Date:     %s\n", fpga.bitstream_date);
    uart_printf("  CRC:            0x%08lX\n", fpga.bitstream_crc);
    uart_printf("  Config Done:    %s\n", fpga.config_done ? "Yes" : "No");
    uart_printf("  Init Done:      %s\n", fpga.init_done ? "Yes" : "No");
    uart_puts("-----------------------------------------\n");

    return 0;
}

/*============================================================================
 * Drive Status Display
 *============================================================================*/

static int cmd_diag_drives(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    drive_status_t drv;

    uart_puts("\nDrive Status\n");
    uart_puts("=======================================================\n");

    /* FDD drives */
    uart_puts("Floppy Drives (FDD 0-3):\n");
    uart_puts("-------------------------------------------------------\n");
    uart_puts("  Slot  Type         State        Track  RPM   Flags\n");
    uart_puts("-------------------------------------------------------\n");

    for (int i = 0; i < 4; i++) {
        if (sys_get_drive_status(true, i, &drv) == 0) {
            uart_printf("  FDD%d  %-12s %-12s",
                i, sys_drive_type_name(drv.type), sys_drive_state_name(drv.state));

            if (drv.state != DRIVE_STATE_NOT_PRESENT) {
                uart_printf(" %3u    %4u  ", drv.current_track, drv.rpm);

                /* Flags */
                if (drv.motor_on) uart_puts("M");
                if (drv.track0) uart_puts("T0");
                if (drv.write_protected) uart_puts("WP");
                if (drv.index) uart_puts("I");
            }
            uart_puts("\n");
        }
    }

    /* HDD drives */
    uart_puts("\nHard Drives (HDD 0-1):\n");
    uart_puts("-------------------------------------------------------\n");
    uart_puts("  Slot  Type         State        Cyl   Hd  Sec  Flags\n");
    uart_puts("-------------------------------------------------------\n");

    for (int i = 0; i < 2; i++) {
        if (sys_get_drive_status(false, i, &drv) == 0) {
            uart_printf("  HDD%d  %-12s %-12s",
                i, sys_drive_type_name(drv.type), sys_drive_state_name(drv.state));

            if (drv.state != DRIVE_STATE_NOT_PRESENT) {
                uart_printf(" %4u  %2u  %2u  ",
                    drv.cylinders, drv.heads, drv.sectors);

                /* Flags */
                if (drv.motor_on) uart_puts("M");
                if (drv.track0) uart_puts("T0");
            }
            uart_puts("\n");
        }
    }

    uart_puts("=======================================================\n");
    uart_puts("Flags: M=Motor, T0=Track0, WP=Write Protect, I=Index\n");

    return 0;
}

/*============================================================================
 * Uptime Display
 *============================================================================*/

static int cmd_diag_uptime(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uptime_stats_t stats;
    sys_get_uptime(&stats);

    /* Convert seconds to d:h:m:s */
    uint32_t days = stats.uptime_seconds / 86400;
    uint32_t hours = (stats.uptime_seconds % 86400) / 3600;
    uint32_t mins = (stats.uptime_seconds % 3600) / 60;
    uint32_t secs = stats.uptime_seconds % 60;

    uart_puts("\nUptime and Statistics\n");
    uart_puts("-----------------------------------------\n");

    uart_puts("Uptime:           ");
    if (days > 0) {
        uart_printf("%lu days, %lu:%02lu:%02lu\n", days, hours, mins, secs);
    } else {
        uart_printf("%lu:%02lu:%02lu\n", hours, mins, secs);
    }
    uart_printf("Boot Count:       %lu\n", stats.boot_count);

    uart_puts("\nLifetime Operations:\n");
    uart_printf("  Tracks Read:    %lu\n", stats.tracks_read);
    uart_printf("  Tracks Written: %lu\n", stats.tracks_written);
    uart_printf("  Seeks:          %lu\n", stats.seeks_performed);
    uart_printf("  USB Data:       %lu KB\n", stats.bytes_transferred);
    uart_printf("  Captures:       %lu\n", stats.captures_completed);

    uart_puts("\nSession Statistics:\n");
    uart_printf("  Errors:         %lu\n", stats.session_errors);
    uart_printf("  Retries:        %lu\n", stats.session_retries);
    uart_puts("-----------------------------------------\n");

    return 0;
}

/*============================================================================
 * Clock Monitoring Display
 *============================================================================*/

static int cmd_diag_clocks(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    clock_status_t clocks[CLK_COUNT];
    sys_get_all_clocks(clocks, CLK_COUNT);

    uart_puts("\nClock Status\n");
    uart_puts("---------------------------------------------------------------\n");
    uart_puts("  Clock         Nominal      Measured     Offset    PLL\n");
    uart_puts("---------------------------------------------------------------\n");

    for (int i = 0; i < CLK_COUNT; i++) {
        clock_status_t *c = &clocks[i];

        uart_printf("  %-12s  ", c->name);

        if (c->present) {
            uart_printf("%3lu.%03lu MHz  %3lu.%03lu MHz  ",
                c->nominal_hz / 1000000, (c->nominal_hz / 1000) % 1000,
                c->measured_hz / 1000000, (c->measured_hz / 1000) % 1000);

            /* PPM offset with sign */
            if (c->ppm_offset >= 0) {
                uart_printf("+%4d ppm  ", c->ppm_offset);
            } else {
                uart_printf("%5d ppm  ", c->ppm_offset);
            }

            uart_printf("%s\n", c->pll_locked ? "LOCKED" : "UNLOCK");
        } else {
            uart_puts("     --           --           --     --\n");
        }
    }

    uart_puts("---------------------------------------------------------------\n");

    /* Overall status */
    uart_puts("Status: ");
    if (sys_all_clocks_locked()) {
        uart_puts("All PLLs locked - OK\n");
    } else {
        uart_puts("WARNING - One or more PLLs not locked!\n");
    }

    return 0;
}

/*============================================================================
 * I2C Bus Diagnostics
 *============================================================================*/

static int cmd_diag_i2c(int argc, char *argv[])
{
    bool do_scan = false;
    int bus = -1;  /* -1 = both buses */

    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "scan") == 0) {
            do_scan = true;
        } else if (strcmp(argv[i], "0") == 0) {
            bus = 0;
        } else if (strcmp(argv[i], "1") == 0) {
            bus = 1;
        }
    }

    uart_puts("\nI2C Bus Diagnostics\n");
    uart_puts("=======================================================\n");

    int start = (bus >= 0) ? bus : 0;
    int end = (bus >= 0) ? bus + 1 : I2C_BUS_COUNT;

    for (int b = start; b < end; b++) {
        i2c_bus_status_t status;

        uart_printf("\nI2C Bus %d:\n", b);
        uart_puts("-------------------------------------------------------\n");

        /* Get statistics */
        sys_i2c_get_stats(b, &status);
        uart_printf("  Transactions:   %lu\n", status.tx_count);
        uart_printf("  Errors:         %lu\n", status.error_count);
        uart_printf("  NAKs:           %lu\n", status.nak_count);
        uart_printf("  Timeouts:       %lu\n", status.timeout_count);
        uart_printf("  Bus Status:     %s\n", status.bus_ok ? "OK" : "ERROR");

        /* Scan if requested */
        if (do_scan) {
            uart_puts("\n  Scanning... ");
            int found = sys_i2c_scan(b, &status);
            uart_printf("found %d devices:\n", found);

            if (found > 0) {
                uart_puts("  Addr  Device\n");
                uart_puts("  ----  ----------------\n");
                for (int d = 0; d < status.device_count; d++) {
                    uart_printf("  0x%02X  %s\n",
                        status.devices[d].address,
                        status.devices[d].name);
                }
            }
        }
    }

    uart_puts("=======================================================\n");

    if (!do_scan) {
        uart_puts("Use 'diag i2c scan' to scan for devices\n");
    }

    return 0;
}

/*============================================================================
 * Temperature Display
 *============================================================================*/

static int cmd_diag_temp(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    temp_status_t temps[TEMP_SENSOR_COUNT];
    sys_get_all_temperatures(temps, TEMP_SENSOR_COUNT);

    uart_puts("\nTemperature Sensors\n");
    uart_puts("---------------------------------------------------------------\n");
    uart_puts("  Sensor      Current    Min      Max      Warn     Crit   Status\n");
    uart_puts("---------------------------------------------------------------\n");

    for (int i = 0; i < TEMP_SENSOR_COUNT; i++) {
        temp_status_t *t = &temps[i];

        uart_printf("  %-10s  ", t->name);

        if (t->present) {
            /* Current temp */
            uart_printf("%3d.%d°C  ", t->temp_c / 10, abs(t->temp_c) % 10);
            /* Min */
            uart_printf("%3d.%d°C  ", t->min_c / 10, abs(t->min_c) % 10);
            /* Max */
            uart_printf("%3d.%d°C  ", t->max_c / 10, abs(t->max_c) % 10);
            /* Warning threshold */
            uart_printf("%3d.%d°C  ", t->warning_c / 10, t->warning_c % 10);
            /* Critical threshold */
            uart_printf("%3d.%d°C  ", t->critical_c / 10, t->critical_c % 10);

            /* Status */
            if (t->critical) {
                uart_puts("CRITICAL!");
            } else if (t->warning) {
                uart_puts("WARNING");
            } else {
                uart_puts("OK");
            }
        } else {
            uart_puts("   --       --       --       --       --     N/A");
        }
        uart_puts("\n");
    }

    uart_puts("---------------------------------------------------------------\n");

    /* Quick FPGA temp */
    int16_t fpga_temp = sys_get_fpga_temp_c();
    uart_printf("FPGA Die Temperature: %d.%d°C\n", fpga_temp / 10, abs(fpga_temp) % 10);

    return 0;
}

/*============================================================================
 * GPIO State Display
 *============================================================================*/

static int cmd_diag_gpio(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    gpio_state_t gpio;
    sys_get_gpio_state(&gpio);

    uart_puts("\nGPIO State\n");
    uart_puts("=======================================================\n");

    uart_puts("\nFDD Control Outputs:\n");
    uart_printf("  Drive Select:   0x%X (DS0=%d DS1=%d DS2=%d DS3=%d)\n",
        gpio.fdd_drive_sel,
        (gpio.fdd_drive_sel >> 0) & 1,
        (gpio.fdd_drive_sel >> 1) & 1,
        (gpio.fdd_drive_sel >> 2) & 1,
        (gpio.fdd_drive_sel >> 3) & 1);
    uart_printf("  Motor On:       %s\n", gpio.fdd_motor_on ? "YES" : "no");
    uart_printf("  Direction:      %s\n", gpio.fdd_direction ? "OUT" : "IN");
    uart_printf("  Step:           %s\n", gpio.fdd_step ? "PULSE" : "idle");
    uart_printf("  Write Gate:     %s\n", gpio.fdd_write_gate ? "ACTIVE" : "off");
    uart_printf("  Side Select:    %s\n", gpio.fdd_side_sel ? "Side 1" : "Side 0");

    uart_puts("\nFDD Status Inputs:\n");
    uart_printf("  Index:          %s\n", gpio.fdd_index ? "PULSE" : "---");
    uart_printf("  Track 0:        %s\n", gpio.fdd_track0 ? "YES" : "no");
    uart_printf("  Write Protect:  %s\n", gpio.fdd_write_protect ? "PROTECTED" : "writable");
    uart_printf("  Ready:          %s\n", gpio.fdd_ready ? "READY" : "not ready");
    uart_printf("  Disk Change:    %s\n", gpio.fdd_disk_change ? "CHANGED" : "---");

    uart_puts("\nHDD Control Outputs:\n");
    uart_printf("  Drive Select:   %d\n", gpio.hdd_drive_sel);
    uart_printf("  Head Select:    %d\n", gpio.hdd_head_sel);
    uart_printf("  Direction:      %s\n", gpio.hdd_direction ? "OUT" : "IN");
    uart_printf("  Step:           %s\n", gpio.hdd_step ? "PULSE" : "idle");
    uart_printf("  Write Gate:     %s\n", gpio.hdd_write_gate ? "ACTIVE" : "off");

    uart_puts("\nHDD Status Inputs:\n");
    uart_printf("  Index:          %s\n", gpio.hdd_index ? "PULSE" : "---");
    uart_printf("  Track 0:        %s\n", gpio.hdd_track0 ? "YES" : "no");
    uart_printf("  Write Fault:    %s\n", gpio.hdd_write_fault ? "FAULT!" : "ok");
    uart_printf("  Seek Complete:  %s\n", gpio.hdd_seek_complete ? "DONE" : "seeking");
    uart_printf("  Ready:          %s\n", gpio.hdd_ready ? "READY" : "not ready");

    uart_puts("\nUSB PHY:\n");
    uart_printf("  VBUS:           %s\n", gpio.usb_vbus ? "PRESENT" : "absent");
    uart_printf("  ID Pin:         %s\n", gpio.usb_id ? "HIGH (device)" : "LOW (host)");
    uart_printf("  Suspend:        %s\n", gpio.usb_suspend ? "SUSPENDED" : "active");

    uart_puts("\nPower Control:\n");
    uart_printf("  Enables:        0x%02X (", gpio.pwr_enable);
    const char *conn_names[] = {"FDD0", "FDD1", "FDD2", "FDD3", "HDD0", "HDD1"};
    for (int i = 0; i < 6; i++) {
        if (gpio.pwr_enable & (1 << i)) {
            uart_printf("%s ", conn_names[i]);
        }
    }
    uart_puts(")\n");
    uart_printf("  8\" Mode (24V):  %s\n", gpio.pwr_8inch_mode ? "ENABLED" : "disabled");

    uart_puts("\nLEDs:\n");
    uart_printf("  LED State:      0x%X (PWR=%s ACT=%s)\n",
        gpio.led_state,
        (gpio.led_state & 0x01) ? "ON" : "off",
        (gpio.led_state & 0x02) ? "ON" : "off");

    uart_puts("=======================================================\n");

    return 0;
}

/*============================================================================
 * Memory Diagnostics
 *============================================================================*/

static int cmd_diag_mem(int argc, char *argv[])
{
    bool run_test = false;

    /* Check for test argument */
    if (argc >= 2 && strcmp(argv[1], "test") == 0) {
        run_test = true;
    }

    memory_status_t mem;
    sys_get_memory_status(&mem);

    uart_puts("\nMemory Status\n");
    uart_puts("-----------------------------------------\n");

    uart_puts("BRAM:\n");
    uart_printf("  Total:          %lu KB\n", mem.bram_total_kb);
    uart_printf("  Used:           %lu KB (%lu%%)\n",
        mem.bram_used_kb,
        (mem.bram_used_kb * 100) / mem.bram_total_kb);
    uart_printf("  Self-Test:      %s\n", mem.bram_test_pass ? "PASS" : "FAIL");
    if (mem.bram_ecc_errors > 0) {
        uart_printf("  ECC Errors:     %lu\n", mem.bram_ecc_errors);
    }

    uart_puts("\nBuffer Allocations:\n");
    uart_printf("  Flux Capture:   %lu KB\n", mem.flux_buffer_kb);
    uart_printf("  Sector Buffer:  %lu KB\n", mem.sector_buffer_kb);
    uart_printf("  USB Buffers:    %lu KB\n", mem.usb_buffer_kb);
    uart_printf("  USB Logger:     %lu KB\n", mem.log_buffer_kb);
    uart_printf("  ─────────────────────\n");
    uart_printf("  Total Buffers:  %lu KB\n",
        mem.flux_buffer_kb + mem.sector_buffer_kb +
        mem.usb_buffer_kb + mem.log_buffer_kb);

    if (mem.ddr_present) {
        uart_puts("\nDDR Memory:\n");
        uart_printf("  Total:          %lu MB\n", mem.ddr_total_mb);
        uart_printf("  Free:           %lu MB (%lu%%)\n",
            mem.ddr_free_mb,
            (mem.ddr_free_mb * 100) / mem.ddr_total_mb);
    } else {
        uart_puts("\nDDR Memory:       Not Present\n");
    }

    uart_puts("-----------------------------------------\n");

    /* Run memory test if requested */
    if (run_test) {
        uart_puts("Running BRAM self-test... ");
        int result = sys_run_memory_test();
        if (result == 0) {
            uart_puts("PASS\n");
        } else {
            uart_puts("FAIL!\n");
            return -1;
        }
    } else {
        uart_puts("Use 'diag mem test' to run BRAM self-test\n");
    }

    return 0;
}

/*============================================================================
 * Show All Diagnostics
 *============================================================================*/

static int cmd_diag_all(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uart_puts("\n========================================\n");
    uart_puts("     FLUXRIPPER DIAGNOSTICS SUMMARY     \n");
    uart_puts("========================================\n");

    cmd_diag_version(0, NULL);
    cmd_diag_uptime(0, NULL);
    cmd_diag_drives(0, NULL);
    cmd_diag_errors(0, NULL);
    cmd_diag_pll(0, NULL);
    cmd_diag_fifo(0, NULL);
    cmd_diag_capture(0, NULL);
    cmd_diag_seek(0, NULL);
    cmd_diag_power(0, NULL);
    cmd_diag_clocks(0, NULL);
    cmd_diag_temp(0, NULL);
    cmd_diag_usb_status();

    uart_puts("\n========================================\n");
    uart_puts("          END OF DIAGNOSTICS            \n");
    uart_puts("========================================\n");

    return 0;
}

/*============================================================================
 * Main Diagnostics Command Dispatcher
 *============================================================================*/

int cmd_diag(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Diagnostics Commands:\n");
        uart_puts("  diag version  - Show firmware/FPGA version info\n");
        uart_puts("  diag drives   - Show connected drive status\n");
        uart_puts("  diag uptime   - Show uptime and statistics\n");
        uart_puts("  diag errors   - Show lifetime error counters\n");
        uart_puts("  diag pll      - Show PLL/DPLL diagnostics\n");
        uart_puts("  diag fifo     - Show FIFO statistics\n");
        uart_puts("  diag capture  - Show capture timing\n");
        uart_puts("  diag seek     - Show seek histogram (HDD)\n");
        uart_puts("  diag power    - Show power rail monitoring\n");
        uart_puts("  diag clocks   - Show clock status and frequencies\n");
        uart_puts("  diag i2c [scan] - Show I2C bus diagnostics\n");
        uart_puts("  diag temp     - Show temperature sensors\n");
        uart_puts("  diag gpio     - Show GPIO pin states\n");
        uart_puts("  diag mem [test] - Show memory status\n");
        uart_puts("  diag usb      - USB traffic logger (start/stop/dump/export)\n");
        uart_puts("  diag clear [cat] - Clear stats (all or category)\n");
        uart_puts("  diag all      - Show all diagnostics\n");
        return 0;
    }

    /* Dispatch to subcommand */
    if (strcmp(argv[1], "version") == 0) {
        return cmd_diag_version(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "drives") == 0) {
        return cmd_diag_drives(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "uptime") == 0) {
        return cmd_diag_uptime(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "errors") == 0) {
        return cmd_diag_errors(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "pll") == 0) {
        return cmd_diag_pll(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "fifo") == 0) {
        return cmd_diag_fifo(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "capture") == 0) {
        return cmd_diag_capture(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "seek") == 0) {
        return cmd_diag_seek(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "power") == 0) {
        return cmd_diag_power(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "clocks") == 0) {
        return cmd_diag_clocks(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "i2c") == 0) {
        return cmd_diag_i2c(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "temp") == 0) {
        return cmd_diag_temp(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "gpio") == 0) {
        return cmd_diag_gpio(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "mem") == 0) {
        return cmd_diag_mem(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "usb") == 0) {
        return cmd_diag_usb(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "clear") == 0) {
        return cmd_diag_clear(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "all") == 0) {
        return cmd_diag_all(argc - 1, &argv[1]);
    } else {
        uart_printf("Unknown diag command: %s\n", argv[1]);
        uart_puts("Type 'diag' for available commands.\n");
        return -1;
    }
}

/*============================================================================
 * CLI Registration
 *============================================================================*/

/**
 * Diagnostics CLI command definition for registration
 */
const cli_cmd_t diag_cli_cmd = {
    "diag", "Diagnostics (version, drives, uptime, errors, pll, fifo, capture, seek, power, clocks, i2c, temp, gpio, mem, usb)",
    cmd_diag
};

/**
 * Initialize and register instrumentation CLI commands
 */
void instrumentation_cli_init(void)
{
    /* Initialize system HAL */
    sys_init();

    /* Initialize diagnostics HAL */
    diag_init();

    /* Initialize USB traffic logger */
    usblog_init();

    /* Register diag command */
    cli_register(&diag_cli_cmd);
}
