/**
 * FluxStat CLI - Command Line Interface Implementation
 *
 * CLI commands for statistical flux recovery operations.
 *
 * Created: 2025-12-04 19:20
 */

#include "fluxstat_cli.h"
#include "fluxstat_hal.h"
#include "uart.h"
#include <string.h>
#include <stdlib.h>

/*============================================================================
 * Helper Functions
 *============================================================================*/

static void print_separator(void)
{
    uart_puts("-----------------------------------------\n");
}

static void print_confidence_bar(uint8_t confidence)
{
    /* Print visual confidence bar [####----] */
    int bars = (confidence + 9) / 10;  /* 0-10 bars */
    uart_puts("[");
    for (int i = 0; i < 10; i++) {
        uart_puts(i < bars ? "#" : "-");
    }
    uart_printf("] %d%%", confidence);
}

/*============================================================================
 * fluxstat config - Configure FluxStat Parameters
 *============================================================================*/

static int cmd_fluxstat_config(int argc, char *argv[])
{
    fluxstat_config_t config;
    fluxstat_get_config(&config);

    if (argc < 2) {
        /* Show current config */
        uart_puts("\nFluxStat Configuration\n");
        print_separator();
        uart_printf("  Pass Count:         %d\n", config.pass_count);
        uart_printf("  Confidence Thresh:  %d%%\n", config.confidence_threshold);
        uart_printf("  Max Correction:     %d bits\n", config.max_correction_bits);
        uart_printf("  Encoding:           %d\n", config.encoding);
        uart_printf("  Data Rate:          %lu bps\n", config.data_rate);
        uart_printf("  CRC Correction:     %s\n", config.use_crc_correction ? "ON" : "OFF");
        uart_printf("  Preserve Weak:      %s\n", config.preserve_weak_bits ? "ON" : "OFF");
        print_separator();
        uart_puts("\nUsage: fluxstat config <param>=<value> ...\n");
        uart_puts("  passes=N        Pass count (2-64)\n");
        uart_puts("  threshold=N     Confidence threshold (0-100)\n");
        uart_puts("  correction=on|off  CRC correction\n");
        uart_puts("  rate=N          Expected data rate (bps)\n");
        return 0;
    }

    /* Parse parameters */
    for (int i = 1; i < argc; i++) {
        char *param = argv[i];
        char *value = strchr(param, '=');
        if (!value) continue;
        *value++ = '\0';

        if (strcmp(param, "passes") == 0) {
            int n = atoi(value);
            if (n >= FLUXSTAT_MIN_PASSES && n <= FLUXSTAT_MAX_PASSES) {
                config.pass_count = n;
                uart_printf("Pass count set to %d\n", n);
            } else {
                uart_printf("Invalid pass count (must be %d-%d)\n",
                           FLUXSTAT_MIN_PASSES, FLUXSTAT_MAX_PASSES);
            }
        }
        else if (strcmp(param, "threshold") == 0) {
            int n = atoi(value);
            if (n >= 0 && n <= 100) {
                config.confidence_threshold = n;
                uart_printf("Threshold set to %d%%\n", n);
            } else {
                uart_puts("Invalid threshold (must be 0-100)\n");
            }
        }
        else if (strcmp(param, "correction") == 0) {
            if (strcmp(value, "on") == 0 || strcmp(value, "1") == 0) {
                config.use_crc_correction = true;
                uart_puts("CRC correction enabled\n");
            } else {
                config.use_crc_correction = false;
                uart_puts("CRC correction disabled\n");
            }
        }
        else if (strcmp(param, "rate") == 0) {
            config.data_rate = atoi(value);
            uart_printf("Data rate set to %lu bps\n", config.data_rate);
        }
        else {
            uart_printf("Unknown parameter: %s\n", param);
        }
    }

    fluxstat_configure(&config);
    return 0;
}

/*============================================================================
 * fluxstat capture - Multi-Pass Flux Capture
 *============================================================================*/

static int cmd_fluxstat_capture(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: fluxstat capture <track> [head=N] [passes=N]\n");
        uart_puts("  track     Track number (0-79)\n");
        uart_puts("  head=N    Head number (0-1, default 0)\n");
        uart_puts("  passes=N  Override pass count\n");
        return 0;
    }

    uint8_t track = atoi(argv[1]);
    uint8_t head = 0;
    uint8_t passes = 0;  /* 0 = use config default */

    /* Parse optional parameters */
    for (int i = 2; i < argc; i++) {
        char *param = argv[i];
        char *value = strchr(param, '=');
        if (!value) continue;
        *value++ = '\0';

        if (strcmp(param, "head") == 0) {
            head = atoi(value);
        }
        else if (strcmp(param, "passes") == 0) {
            passes = atoi(value);
        }
    }

    /* Temporarily override pass count if specified */
    fluxstat_config_t config;
    fluxstat_get_config(&config);
    uint8_t orig_passes = config.pass_count;

    if (passes > 0) {
        config.pass_count = passes;
        fluxstat_configure(&config);
    }

    uart_printf("\nCapturing track %d, head %d with %d passes...\n",
                track, head, config.pass_count);

    /* Start capture */
    int ret = fluxstat_capture_start(0, track, head);
    if (ret != FLUXSTAT_OK) {
        uart_printf("Failed to start capture: %d\n", ret);
        return -1;
    }

    /* Wait with progress display */
    uint8_t last_pass = 255;
    while (fluxstat_capture_busy()) {
        uint8_t current, total;
        fluxstat_capture_progress(&current, &total);

        if (current != last_pass) {
            uart_printf("  Pass %d/%d...\r", current + 1, total);
            last_pass = current;
        }

        /* Small delay */
        for (volatile int i = 0; i < 100000; i++);
    }

    uart_puts("\n");

    /* Get result */
    fluxstat_capture_t result;
    ret = fluxstat_capture_result(&result);
    if (ret != FLUXSTAT_OK) {
        uart_printf("Failed to get result: %d\n", ret);
        return -1;
    }

    /* Display results */
    uart_puts("\nCapture Complete\n");
    print_separator();
    uart_printf("  Passes:         %d\n", result.pass_count);
    uart_printf("  Total Flux:     %lu transitions\n", result.total_flux);
    uart_printf("  Min Flux:       %lu\n", result.min_flux);
    uart_printf("  Max Flux:       %lu\n", result.max_flux);
    uart_printf("  Variation:      %.1f%%\n",
                100.0f * (result.max_flux - result.min_flux) / result.min_flux);

    /* Calculate RPM from average index time */
    uint32_t avg_index = result.total_time / result.pass_count;
    uint32_t rpm = fluxstat_calculate_rpm(avg_index, 200);
    uart_printf("  Avg RPM:        %lu\n", rpm);

    uart_puts("\nPer-Pass Data:\n");
    uart_puts("  Pass   Flux Count   Index Time    RPM\n");
    for (int i = 0; i < result.pass_count && i < 16; i++) {
        uint32_t pass_rpm = fluxstat_calculate_rpm(result.passes[i].index_time, 200);
        uart_printf("  %2d     %8lu     %8lu   %4lu\n",
                    i, result.passes[i].flux_count,
                    result.passes[i].index_time, pass_rpm);
    }
    if (result.pass_count > 16) {
        uart_printf("  ... and %d more passes\n", result.pass_count - 16);
    }

    print_separator();

    /* Restore original pass count */
    if (passes > 0) {
        config.pass_count = orig_passes;
        fluxstat_configure(&config);
    }

    return 0;
}

/*============================================================================
 * fluxstat histogram - Display Flux Histogram
 *============================================================================*/

static int cmd_fluxstat_histogram(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    fluxstat_histogram_t hist;
    int ret = fluxstat_histogram_stats(&hist);
    if (ret != FLUXSTAT_OK) {
        uart_puts("Failed to read histogram.\n");
        return -1;
    }

    uart_puts("\nFlux Interval Histogram\n");
    print_separator();
    uart_printf("  Total Count:    %lu transitions\n", hist.total_count);
    uart_printf("  Min Interval:   %u clocks (%u ns)\n",
                hist.interval_min, hist.interval_min * 5);
    uart_printf("  Max Interval:   %u clocks (%u ns)\n",
                hist.interval_max, hist.interval_max * 5);
    uart_printf("  Peak Bin:       %u (interval ~%u clocks)\n",
                hist.peak_bin, hist.peak_bin << FLUXSTAT_HIST_BIN_SHIFT);
    uart_printf("  Peak Count:     %u\n", hist.peak_count);
    uart_printf("  Mean Interval:  %u clocks (%u ns)\n",
                hist.mean_interval, hist.mean_interval * 5);

    /* Estimate data rate */
    uint32_t rate;
    if (fluxstat_estimate_rate(&rate) == FLUXSTAT_OK) {
        uart_printf("  Est. Data Rate: %lu bps\n", rate);
    }

    /* Draw ASCII histogram around peak */
    uart_puts("\nDistribution (around peak):\n");

    int start_bin = (hist.peak_bin > 20) ? hist.peak_bin - 20 : 0;
    int end_bin = (hist.peak_bin + 20 < 255) ? hist.peak_bin + 20 : 255;

    /* Find max in range for scaling */
    uint16_t max_count = 1;
    for (int b = start_bin; b <= end_bin; b++) {
        uint16_t count;
        fluxstat_histogram_read_bin(b, &count);
        if (count > max_count) max_count = count;
    }

    /* Draw bins */
    for (int b = start_bin; b <= end_bin; b += 2) {
        uint16_t count;
        fluxstat_histogram_read_bin(b, &count);

        int bars = (count * 40) / max_count;
        uart_printf("  %3d: ", b);
        for (int i = 0; i < bars; i++) {
            uart_puts("#");
        }
        if (b == hist.peak_bin) {
            uart_puts(" <-- peak");
        }
        uart_puts("\n");
    }

    print_separator();
    return 0;
}

/*============================================================================
 * fluxstat analyze - Analyze Captured Data
 *============================================================================*/

static int cmd_fluxstat_analyze(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uart_puts("\nAnalyzing captured flux data...\n");

    fluxstat_track_t track;
    int ret = fluxstat_analyze_track(&track);
    if (ret != FLUXSTAT_OK) {
        uart_printf("Analysis failed: %d\n", ret);
        if (ret == FLUXSTAT_ERR_NO_DATA) {
            uart_puts("No capture data. Run 'fluxstat capture' first.\n");
        }
        return -1;
    }

    uart_puts("\nTrack Analysis Results\n");
    print_separator();
    uart_printf("  Track:              %d\n", track.track);
    uart_printf("  Head:               %d\n", track.head);
    uart_printf("  Sectors Found:      %d\n", track.sector_count);
    uart_printf("  Fully Recovered:    %d\n", track.sectors_recovered);
    uart_printf("  Partial Recovery:   %d\n", track.sectors_partial);
    uart_printf("  Failed:             %d\n", track.sectors_failed);
    uart_puts("  Overall Confidence: ");
    print_confidence_bar(track.overall_confidence);
    uart_puts("\n");

    print_separator();
    uart_puts("\nPer-Sector Results:\n");
    uart_puts("  Sec  Size   CRC   Conf   Weak  Corr  Status\n");

    for (int s = 0; s < track.sector_count; s++) {
        fluxstat_sector_t *sec = &track.sectors[s];

        const char *status;
        if (sec->crc_ok && sec->confidence_min >= CONF_STRONG) {
            status = "OK";
        } else if (sec->crc_ok) {
            status = "WEAK";
        } else if (sec->confidence_avg >= CONF_WEAK) {
            status = "PARTIAL";
        } else {
            status = "FAILED";
        }

        uart_printf("  %2d   %4d   %s   %3d%%   %2d    %2d    %s\n",
                    s, sec->size,
                    sec->crc_ok ? "OK " : "BAD",
                    sec->confidence_avg,
                    sec->weak_bit_count,
                    sec->corrected_count,
                    status);
    }

    print_separator();
    return 0;
}

/*============================================================================
 * fluxstat recover - Recover Specific Sector
 *============================================================================*/

static int cmd_fluxstat_recover(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: fluxstat recover <sector>\n");
        return 0;
    }

    uint8_t sector = atoi(argv[1]);

    uart_printf("\nRecovering sector %d...\n", sector);

    fluxstat_sector_t result;
    int ret = fluxstat_recover_sector(sector, &result);
    if (ret != FLUXSTAT_OK) {
        uart_printf("Recovery failed: %d\n", ret);
        return -1;
    }

    uart_puts("\nSector Recovery Result\n");
    print_separator();
    uart_printf("  Sector:         %d\n", sector);
    uart_printf("  Size:           %d bytes\n", result.size);
    uart_printf("  CRC:            %s\n", result.crc_ok ? "OK" : "FAILED");
    uart_printf("  Min Confidence: %d%%\n", result.confidence_min);
    uart_printf("  Avg Confidence: %d%%\n", result.confidence_avg);
    uart_printf("  Weak Bits:      %d\n", result.weak_bit_count);
    uart_printf("  Corrected:      %d bits\n", result.corrected_count);

    uart_puts("  Quality:        ");
    print_confidence_bar(result.confidence_avg);
    uart_puts("\n");

    if (result.weak_bit_count > 0) {
        uart_puts("\nWeak Bit Positions:\n  ");
        for (int i = 0; i < result.weak_bit_count && i < 16; i++) {
            uart_printf("%d ", result.weak_positions[i]);
        }
        if (result.weak_bit_count > 16) {
            uart_printf("... +%d more", result.weak_bit_count - 16);
        }
        uart_puts("\n");
    }

    /* Hexdump first 64 bytes */
    uart_puts("\nData (first 64 bytes):\n");
    for (int row = 0; row < 4; row++) {
        uart_printf("  %04X: ", row * 16);
        for (int col = 0; col < 16; col++) {
            uart_printf("%02X ", result.data[row * 16 + col]);
        }
        uart_puts(" ");
        for (int col = 0; col < 16; col++) {
            char c = result.data[row * 16 + col];
            uart_printf("%c", (c >= 32 && c < 127) ? c : '.');
        }
        uart_puts("\n");
    }

    print_separator();
    return 0;
}

/*============================================================================
 * fluxstat map - Display Bit Confidence Map
 *============================================================================*/

static int cmd_fluxstat_map(int argc, char *argv[])
{
    uint32_t offset = 0;
    uint32_t count = 256;

    if (argc >= 2) {
        offset = atoi(argv[1]);
    }
    if (argc >= 3) {
        count = atoi(argv[2]);
    }

    if (count > 512) count = 512;

    uart_printf("\nBit Confidence Map (offset %lu, count %lu)\n", offset, count);
    print_separator();

    fluxstat_bit_t bits[64];
    uint32_t remaining = count;
    uint32_t pos = offset;

    while (remaining > 0) {
        uint32_t chunk = (remaining > 64) ? 64 : remaining;

        int ret = fluxstat_get_bit_analysis(pos, chunk, bits);
        if (ret != FLUXSTAT_OK) {
            uart_printf("Analysis failed at offset %lu\n", pos);
            break;
        }

        /* Display as visual map */
        uart_printf("  %5lu: ", pos);
        for (uint32_t i = 0; i < chunk; i++) {
            char c;
            if (bits[i].confidence >= CONF_STRONG) {
                c = bits[i].value ? '1' : '0';
            } else if (bits[i].confidence >= CONF_WEAK) {
                c = bits[i].value ? '+' : '-';  /* Weak */
            } else {
                c = '?';  /* Ambiguous */
            }
            uart_printf("%c", c);

            if ((i + 1) % 64 == 0 && i + 1 < chunk) {
                uart_printf("\n  %5lu: ", pos + i + 1);
            }
        }
        uart_puts("\n");

        pos += chunk;
        remaining -= chunk;
    }

    uart_puts("\nLegend: 0/1=strong, +/-=weak, ?=ambiguous\n");
    print_separator();
    return 0;
}

/*============================================================================
 * fluxstat status - Show Current Status
 *============================================================================*/

static int cmd_fluxstat_status(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    uart_puts("\nFluxStat Status\n");
    print_separator();

    if (fluxstat_capture_busy()) {
        uint8_t current, total;
        fluxstat_capture_progress(&current, &total);
        uart_printf("  Status:         CAPTURING (pass %d/%d)\n", current + 1, total);
    } else {
        fluxstat_capture_t result;
        if (fluxstat_capture_result(&result) == FLUXSTAT_OK) {
            uart_puts("  Status:         DATA AVAILABLE\n");
            uart_printf("  Passes:         %d\n", result.pass_count);
            uart_printf("  Total Flux:     %lu\n", result.total_flux);
        } else {
            uart_puts("  Status:         NO DATA\n");
        }
    }

    /* Show histogram stats if available */
    fluxstat_histogram_t hist;
    if (fluxstat_histogram_stats(&hist) == FLUXSTAT_OK && hist.total_count > 0) {
        uart_puts("\n  Histogram:      Available\n");
        uart_printf("  Flux Count:     %lu\n", hist.total_count);
        uart_printf("  Peak Interval:  %u clocks\n", hist.peak_bin << FLUXSTAT_HIST_BIN_SHIFT);
    }

    print_separator();
    return 0;
}

/*============================================================================
 * fluxstat clear - Clear Data
 *============================================================================*/

static int cmd_fluxstat_clear(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    fluxstat_histogram_clear();
    uart_puts("FluxStat data cleared.\n");
    return 0;
}

/*============================================================================
 * Main FluxStat Command Dispatcher
 *============================================================================*/

int cmd_fluxstat(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("FluxStat Statistical Recovery Commands:\n");
        uart_puts("  fluxstat config    - Show/set configuration\n");
        uart_puts("  fluxstat capture   - Multi-pass flux capture\n");
        uart_puts("  fluxstat histogram - Display flux histogram\n");
        uart_puts("  fluxstat analyze   - Analyze captured data\n");
        uart_puts("  fluxstat recover   - Recover specific sector\n");
        uart_puts("  fluxstat map       - Display bit confidence map\n");
        uart_puts("  fluxstat status    - Show current status\n");
        uart_puts("  fluxstat clear     - Clear captured data\n");
        return 0;
    }

    /* Dispatch to subcommand */
    if (strcmp(argv[1], "config") == 0) {
        return cmd_fluxstat_config(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "capture") == 0) {
        return cmd_fluxstat_capture(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "histogram") == 0 || strcmp(argv[1], "hist") == 0) {
        return cmd_fluxstat_histogram(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "analyze") == 0) {
        return cmd_fluxstat_analyze(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "recover") == 0) {
        return cmd_fluxstat_recover(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "map") == 0) {
        return cmd_fluxstat_map(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "status") == 0) {
        return cmd_fluxstat_status(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "clear") == 0) {
        return cmd_fluxstat_clear(argc - 1, &argv[1]);
    } else {
        uart_printf("Unknown fluxstat command: %s\n", argv[1]);
        uart_puts("Type 'fluxstat' for available commands.\n");
        return -1;
    }
}

/*============================================================================
 * CLI Registration
 *============================================================================*/

const cli_cmd_t fluxstat_cli_cmd = {
    "fluxstat", "Statistical flux recovery (capture, analyze, recover)",
    cmd_fluxstat
};

void fluxstat_cli_init(void)
{
    /* Initialize FluxStat HAL */
    fluxstat_init();

    /* Register CLI command */
    cli_register(&fluxstat_cli_cmd);
}
