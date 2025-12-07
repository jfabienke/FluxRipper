/**
 * FluxRipper HDD CLI Commands
 *
 * Command-line interface for HDD operations
 * Dual-drive support for independent drive operations.
 *
 * Created: 2025-12-04 09:27:34
 * Updated: 2025-12-04 18:25 - Added ESDI esdi-config command for GET_DEV_CONFIG
 */

#include "cli.h"
#include "hdd_hal.h"
#include "uart.h"
#include <string.h>

/*============================================================================
 * String Parsing Helpers
 *============================================================================*/

static uint32_t parse_num(const char *s)
{
    /* Hex if starts with 0x */
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        uint32_t val = 0;
        s += 2;
        while (*s) {
            char c = *s++;
            uint8_t digit;
            if (c >= '0' && c <= '9')
                digit = c - '0';
            else if (c >= 'a' && c <= 'f')
                digit = c - 'a' + 10;
            else if (c >= 'A' && c <= 'F')
                digit = c - 'A' + 10;
            else
                break;
            val = (val << 4) | digit;
        }
        return val;
    }

    /* Otherwise decimal */
    uint32_t val = 0;
    while (*s >= '0' && *s <= '9') {
        val = val * 10 + (*s++ - '0');
    }
    return val;
}

/**
 * Parse drive number from argument
 * Returns HDD_DRIVE_0 or HDD_DRIVE_1, or -1 on error
 */
static int parse_drive(const char *s)
{
    if (strcmp(s, "0") == 0) return HDD_DRIVE_0;
    if (strcmp(s, "1") == 0) return HDD_DRIVE_1;
    return -1;
}

/*============================================================================
 * HDD CLI Command Implementations - Dual-Drive
 *============================================================================*/

/**
 * hdd select <drive> - Select active drive
 */
int cmd_hdd_select(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: hdd select <0|1>\n");
        uart_printf("Current: Drive %d\n", hdd_get_active_drive());
        return -1;
    }

    int drive = parse_drive(argv[1]);
    if (drive < 0) {
        uart_puts("Invalid drive. Use 0 or 1.\n");
        return -1;
    }

    int ret = hdd_select_drive(drive);
    if (ret != HAL_OK) {
        uart_printf("Select failed: %d\n", ret);
        return -1;
    }

    uart_printf("Active drive: %d\n", drive);
    return 0;
}

/**
 * hdd detect [drive] - Run interface detection
 */
int cmd_hdd_detect(int argc, char *argv[])
{
    uint8_t drive = hdd_get_active_drive();

    if (argc >= 2) {
        int d = parse_drive(argv[1]);
        if (d < 0) {
            uart_puts("Invalid drive. Use 0 or 1.\n");
            return -1;
        }
        drive = d;
    }

    uart_printf("Running HDD interface detection on drive %d...\n", drive);

    hdd_detection_t result;
    int ret = hdd_detect_interface(drive, &result);

    if (ret != HAL_OK) {
        uart_printf("Detection failed: %d\n", ret);
        return -1;
    }

    uart_printf("\nDrive %d Detection Results:\n", drive);
    uart_puts("-----------------------------------------\n");
    uart_printf("  Type:       %s\n", hdd_type_to_string(result.type));
    uart_printf("  Confidence: %d/15\n", result.confidence);
    uart_printf("  PHY Mode:   %s\n",
                result.phy_mode == HDD_PHY_SE ? "Single-ended" :
                result.phy_mode == HDD_PHY_DIFF ? "Differential" : "None");
    uart_printf("  Data Rate:  %s\n", hdd_rate_to_string(result.rate));
    uart_printf("  Forced:     %s\n", result.was_forced ? "Yes" : "No");

    uart_puts("\nEvidence Scores:\n");
    uart_printf("  Floppy: %3d  HDD:  %3d\n", result.score_floppy, result.score_hdd);
    uart_printf("  ST-506: %3d  ESDI: %3d\n", result.score_st506, result.score_esdi);
    uart_printf("  MFM:    %3d  RLL:  %3d\n", result.score_mfm, result.score_rll);
    uart_puts("-----------------------------------------\n");

    return 0;
}

/**
 * hdd discover [drive] - Run full discovery pipeline
 */
int cmd_hdd_discover(int argc, char *argv[])
{
    uint8_t drive = hdd_get_active_drive();

    if (argc >= 2) {
        int d = parse_drive(argv[1]);
        if (d < 0) {
            uart_puts("Invalid drive. Use 0 or 1.\n");
            return -1;
        }
        drive = d;
    }

    uart_printf("Running HDD discovery pipeline on drive %d...\n", drive);
    uart_puts("(This may take up to 60 seconds)\n\n");

    hdd_profile_t profile;
    int ret = hdd_discover(drive, &profile);

    if (ret != HAL_OK) {
        uart_printf("Discovery failed: %d\n", ret);
        return -1;
    }

    uart_printf("\nDrive %d Discovery Complete!\n", drive);
    uart_puts("=========================================\n");

    /* Interface */
    uart_puts("\nInterface:\n");
    uart_printf("  Type:       %s\n", hdd_type_to_string(profile.detection.type));
    uart_printf("  PHY:        %s\n",
                profile.detection.phy_mode == HDD_PHY_DIFF ? "Differential" : "Single-ended");
    uart_printf("  Rate:       %s\n", hdd_rate_to_string(profile.detection.rate));

    /* Geometry */
    uart_puts("\nGeometry:\n");
    uart_printf("  Cylinders:  %u\n", profile.geometry.cylinders);
    uart_printf("  Heads:      %u\n", profile.geometry.heads);
    uart_printf("  Sectors:    %u\n", profile.geometry.sectors);
    uart_printf("  Sector sz:  %u bytes\n", profile.geometry.sector_size);
    uart_printf("  Interleave: %u\n", profile.geometry.interleave);
    uart_printf("  Capacity:   %u MB (%u sectors)\n",
                profile.geometry.capacity_mb, profile.geometry.total_sectors);

    /* Health */
    uart_puts("\nHealth:\n");
    uart_printf("  RPM:        %u (variance: %u)\n",
                profile.health.rpm, profile.health.rpm_variance);
    uart_printf("  Seek time:  %u ms avg, %u ms max\n",
                profile.health.seek_avg_ms, profile.health.seek_max_ms);
    uart_printf("  Signal:     %u/255\n", profile.health.signal_quality);
    uart_printf("  Ready:      %s\n", profile.health.ready ? "Yes" : "No");

    uart_puts("=========================================\n");

    return 0;
}

/**
 * hdd status [drive] - Show current HDD status
 * If no drive specified, shows both drives
 */
int cmd_hdd_status(int argc, char *argv[])
{
    int show_drive = -1;  /* -1 = show both */

    if (argc >= 2) {
        show_drive = parse_drive(argv[1]);
        if (show_drive < 0) {
            uart_puts("Invalid drive. Use 0 or 1.\n");
            return -1;
        }
    }

    /* Get dual status in one call */
    bool ready_0, ready_1;
    uint16_t cyl_0, cyl_1;
    hdd_get_dual_status(&ready_0, &ready_1, &cyl_0, &cyl_1);

    uart_puts("\nHDD Status\n");
    uart_puts("=========================================\n");

    /* Show Drive 0 */
    if (show_drive == -1 || show_drive == 0) {
        hdd_profile_t profile;
        int ret = hdd_get_profile(HDD_DRIVE_0, &profile);

        uart_puts("\nDrive 0:\n");
        uart_puts("-----------------------------------------\n");
        if (ret == HAL_OK && profile.valid) {
            uart_printf("  Type:       %s\n", hdd_type_to_string(profile.detection.type));
            uart_printf("  Geometry:   %u/%u/%u (C/H/S)\n",
                        profile.geometry.cylinders,
                        profile.geometry.heads,
                        profile.geometry.sectors);
            uart_printf("  Capacity:   %u MB\n", profile.geometry.capacity_mb);
        } else {
            uart_puts("  [Not discovered]\n");
        }
        uart_printf("  Ready:      %s\n", ready_0 ? "Yes" : "No");
        uart_printf("  Position:   Cyl %u, Head %u\n", cyl_0, hdd_get_head(HDD_DRIVE_0));
        bool seeking;
        hdd_get_status(HDD_DRIVE_0, NULL, NULL, &seeking);
        uart_printf("  Seeking:    %s\n", seeking ? "Yes" : "No");
    }

    /* Show Drive 1 */
    if (show_drive == -1 || show_drive == 1) {
        hdd_profile_t profile;
        int ret = hdd_get_profile(HDD_DRIVE_1, &profile);

        uart_puts("\nDrive 1:\n");
        uart_puts("-----------------------------------------\n");
        if (ret == HAL_OK && profile.valid) {
            uart_printf("  Type:       %s\n", hdd_type_to_string(profile.detection.type));
            uart_printf("  Geometry:   %u/%u/%u (C/H/S)\n",
                        profile.geometry.cylinders,
                        profile.geometry.heads,
                        profile.geometry.sectors);
            uart_printf("  Capacity:   %u MB\n", profile.geometry.capacity_mb);
        } else {
            uart_puts("  [Not discovered]\n");
        }
        uart_printf("  Ready:      %s\n", ready_1 ? "Yes" : "No");
        uart_printf("  Position:   Cyl %u, Head %u\n", cyl_1, hdd_get_head(HDD_DRIVE_1));
        bool seeking;
        hdd_get_status(HDD_DRIVE_1, NULL, NULL, &seeking);
        uart_printf("  Seeking:    %s\n", seeking ? "Yes" : "No");
    }

    uart_puts("=========================================\n");
    uart_printf("Active drive: %d\n", hdd_get_active_drive());

    return 0;
}

/**
 * hdd seek <drive> <cylinder> - Seek to cylinder
 */
int cmd_hdd_seek(int argc, char *argv[])
{
    if (argc < 3) {
        uart_puts("Usage: hdd seek <drive> <cylinder>\n");
        uart_puts("       hdd seek-both <cyl0> <cyl1>\n");
        return -1;
    }

    int drive = parse_drive(argv[1]);
    if (drive < 0) {
        uart_puts("Invalid drive. Use 0 or 1.\n");
        return -1;
    }

    uint16_t cylinder = (uint16_t)parse_num(argv[2]);

    uart_printf("Seeking drive %d to cylinder %u...\n", drive, cylinder);

    int ret = hdd_seek(drive, cylinder);
    if (ret != HAL_OK) {
        uart_printf("Seek failed: %d\n", ret);
        return -1;
    }

    uart_puts("Seek complete.\n");
    return 0;
}

/**
 * hdd seek-both <cyl0> <cyl1> - Parallel seek both drives
 */
int cmd_hdd_seek_both(int argc, char *argv[])
{
    if (argc < 3) {
        uart_puts("Usage: hdd seek-both <cyl0> <cyl1>\n");
        return -1;
    }

    uint16_t cyl_0 = (uint16_t)parse_num(argv[1]);
    uint16_t cyl_1 = (uint16_t)parse_num(argv[2]);

    uart_printf("Seeking both drives: 0→%u, 1→%u...\n", cyl_0, cyl_1);

    int ret = hdd_seek_both(cyl_0, cyl_1);
    if (ret != HAL_OK) {
        uart_printf("Seek start failed: %d\n", ret);
        return -1;
    }

    ret = hdd_wait_seeks(10000);
    if (ret != HAL_OK) {
        uart_printf("Seek wait failed: %d\n", ret);
        return -1;
    }

    uart_puts("Both seeks complete.\n");

    /* Show final positions */
    uart_printf("  Drive 0: Cyl %u\n", hdd_get_cylinder(HDD_DRIVE_0));
    uart_printf("  Drive 1: Cyl %u\n", hdd_get_cylinder(HDD_DRIVE_1));

    return 0;
}

/**
 * hdd recal <drive> - Recalibrate (seek to cylinder 0)
 */
int cmd_hdd_recal(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: hdd recal <drive>\n");
        return -1;
    }

    int drive = parse_drive(argv[1]);
    if (drive < 0) {
        uart_puts("Invalid drive. Use 0 or 1.\n");
        return -1;
    }

    uart_printf("Recalibrating drive %d...\n", drive);

    int ret = hdd_recalibrate(drive);
    if (ret != HAL_OK) {
        uart_printf("Recalibrate failed: %d\n", ret);
        return -1;
    }

    uart_printf("Drive %d recalibrate complete. At cylinder 0.\n", drive);
    return 0;
}

/**
 * hdd read <drive> <cyl> <head> <sector> - Read a sector
 */
int cmd_hdd_read(int argc, char *argv[])
{
    if (argc < 5) {
        uart_puts("Usage: hdd read <drive> <cylinder> <head> <sector>\n");
        return -1;
    }

    int drive = parse_drive(argv[1]);
    if (drive < 0) {
        uart_puts("Invalid drive. Use 0 or 1.\n");
        return -1;
    }

    uint16_t cylinder = (uint16_t)parse_num(argv[2]);
    uint8_t head = (uint8_t)parse_num(argv[3]);
    uint8_t sector = (uint8_t)parse_num(argv[4]);

    static uint8_t buffer[512];

    uart_printf("Reading drive %d C/H/S %u/%u/%u...\n", drive, cylinder, head, sector);

    int ret = hdd_read_sector(drive, cylinder, head, sector, buffer);
    if (ret != HAL_OK) {
        uart_printf("Read failed: %d\n", ret);
        return -1;
    }

    uart_puts("Sector data (first 128 bytes):\n");
    uart_hexdump(buffer, 128);

    return 0;
}

/**
 * hdd geometry [drive] - Show geometry details
 */
int cmd_hdd_geometry(int argc, char *argv[])
{
    uint8_t drive = hdd_get_active_drive();

    if (argc >= 2) {
        int d = parse_drive(argv[1]);
        if (d < 0) {
            uart_puts("Invalid drive. Use 0 or 1.\n");
            return -1;
        }
        drive = d;
    }

    hdd_profile_t profile;
    int ret = hdd_get_profile(drive, &profile);

    if (ret != HAL_OK || !profile.valid) {
        uart_printf("No geometry available for drive %d. Run 'hdd discover %d' first.\n",
                    drive, drive);
        return -1;
    }

    uart_printf("\nDrive %d Geometry\n", drive);
    uart_puts("-----------------------------------------\n");
    uart_printf("  Cylinders:     %u\n", profile.geometry.cylinders);
    uart_printf("  Heads:         %u\n", profile.geometry.heads);
    uart_printf("  Sectors/Track: %u\n", profile.geometry.sectors);
    uart_printf("  Sector Size:   %u bytes\n", profile.geometry.sector_size);
    uart_printf("  Interleave:    %u:1\n", profile.geometry.interleave);
    uart_printf("  Track Skew:    %u sectors\n", profile.geometry.skew);
    uart_puts("-----------------------------------------\n");
    uart_printf("  Total Sectors: %u\n", profile.geometry.total_sectors);
    uart_printf("  Capacity:      %u MB\n", profile.geometry.capacity_mb);
    uart_puts("-----------------------------------------\n");

    /* Show geometry source */
    if (profile.geometry.from_esdi_config) {
        uart_puts("  Source:        ESDI GET_DEV_CONFIG (authoritative)\n");
    } else {
        uart_puts("  Source:        Probed from disk format\n");
    }
    uart_puts("-----------------------------------------\n");

    return 0;
}

/**
 * hdd esdi-config [drive] - Query ESDI drive configuration
 */
int cmd_hdd_esdi_config(int argc, char *argv[])
{
    uint8_t drive = hdd_get_active_drive();

    if (argc >= 2) {
        int d = parse_drive(argv[1]);
        if (d < 0) {
            uart_puts("Invalid drive. Use 0 or 1.\n");
            return -1;
        }
        drive = d;
    }

    uart_printf("Querying ESDI configuration from drive %d...\n", drive);

    esdi_config_t config;
    int ret = hdd_esdi_get_config(drive, &config);

    if (ret == HAL_ERR_NOT_SUPPORTED) {
        uart_printf("Drive %d is not an ESDI drive.\n", drive);
        return -1;
    }

    if (ret != HAL_OK || !config.valid) {
        uart_printf("Failed to get ESDI configuration (error: %d)\n", ret);
        return -1;
    }

    uart_printf("\nDrive %d ESDI Configuration\n", drive);
    uart_puts("=========================================\n");
    uart_puts("  (Data directly from drive firmware)\n");
    uart_puts("-----------------------------------------\n");
    uart_printf("  Cylinders:     %u\n", config.cylinders);
    uart_printf("  Heads:         %u\n", config.heads);
    uart_printf("  Sectors/Track: %u\n", config.sectors_per_track);
    uart_printf("  Total Sectors: %u\n", config.total_sectors);
    uart_puts("-----------------------------------------\n");
    uart_printf("  Transfer Rate: %s\n",
                config.transfer_rate == 0 ? "10 Mbps" :
                config.transfer_rate == 1 ? "15 Mbps" :
                config.transfer_rate == 2 ? "20 Mbps" : "Unknown");
    uart_printf("  Soft Sectored: %s\n", config.soft_sectored ? "Yes" : "No");
    uart_printf("  Fixed Drive:   %s\n", config.fixed_drive ? "Yes" : "No");
    uart_puts("=========================================\n");

    return 0;
}

/**
 * hdd health [drive] - Show health metrics
 */
int cmd_hdd_health(int argc, char *argv[])
{
    uint8_t drive = hdd_get_active_drive();

    if (argc >= 2) {
        int d = parse_drive(argv[1]);
        if (d < 0) {
            uart_puts("Invalid drive. Use 0 or 1.\n");
            return -1;
        }
        drive = d;
    }

    hdd_health_t health;
    int ret = hdd_get_health(drive, &health);

    if (ret != HAL_OK) {
        uart_printf("Failed to read health metrics for drive %d.\n", drive);
        return -1;
    }

    uart_printf("\nDrive %d Health Metrics\n", drive);
    uart_puts("-----------------------------------------\n");
    uart_printf("  RPM:            %u\n", health.rpm);
    uart_printf("  RPM Variance:   %u\n", health.rpm_variance);
    uart_printf("  Seek Avg:       %u ms\n", health.seek_avg_ms);
    uart_printf("  Seek Max:       %u ms\n", health.seek_max_ms);
    uart_printf("  Signal Quality: %u/255\n", health.signal_quality);
    uart_printf("  Error Rate:     %u\n", health.error_rate);
    uart_printf("  Spindle:        %s\n", health.spinning ? "Running" : "Stopped");
    uart_printf("  Ready:          %s\n", health.ready ? "Yes" : "No");
    uart_puts("-----------------------------------------\n");

    /* Health assessment */
    uart_puts("\nAssessment: ");
    if (health.signal_quality > 200 && health.rpm_variance < 10) {
        uart_puts("GOOD\n");
    } else if (health.signal_quality > 128 && health.rpm_variance < 50) {
        uart_puts("FAIR\n");
    } else {
        uart_puts("POOR\n");
    }

    return 0;
}

/**
 * hdd force <type> - Force interface type
 */
int cmd_hdd_force(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("Usage: hdd force <type>\n");
        uart_puts("Types: mfm, rll, esdi\n");
        return -1;
    }

    hdd_type_t type;

    if (strcmp(argv[1], "mfm") == 0) {
        type = HDD_TYPE_MFM;
    } else if (strcmp(argv[1], "rll") == 0) {
        type = HDD_TYPE_RLL;
    } else if (strcmp(argv[1], "esdi") == 0) {
        type = HDD_TYPE_ESDI;
    } else {
        uart_puts("Unknown type. Use: mfm, rll, esdi\n");
        return -1;
    }

    uart_printf("Forcing interface type to %s (both drives)...\n", hdd_type_to_string(type));

    int ret = hdd_force_interface(type);
    if (ret != HAL_OK) {
        uart_printf("Force failed: %d\n", ret);
        return -1;
    }

    uart_puts("Interface type forced.\n");
    return 0;
}

/**
 * Main HDD command dispatcher
 */
int cmd_hdd(int argc, char *argv[])
{
    if (argc < 2) {
        uart_puts("HDD Commands (Dual-Drive Support):\n");
        uart_puts("  hdd status [d]       - Show drive status (default: both)\n");
        uart_puts("  hdd select <d>       - Select active drive (0 or 1)\n");
        uart_puts("  hdd detect [d]       - Detect interface type\n");
        uart_puts("  hdd discover [d]     - Full discovery (geometry, health)\n");
        uart_puts("  hdd seek <d> <c>     - Seek drive to cylinder\n");
        uart_puts("  hdd seek-both <c0> <c1> - Parallel seek both drives\n");
        uart_puts("  hdd recal <d>        - Recalibrate drive (seek to 0)\n");
        uart_puts("  hdd read <d> <c> <h> <s> - Read sector\n");
        uart_puts("  hdd geometry [d]     - Show geometry details\n");
        uart_puts("  hdd health [d]       - Show health metrics\n");
        uart_puts("  hdd force <type>     - Force type (mfm/rll/esdi)\n");
        uart_puts("  hdd esdi-config [d]  - Query ESDI drive configuration\n");
        uart_puts("\n  <d> = drive (0 or 1), [d] = optional (uses active drive)\n");
        return 0;
    }

    /* Dispatch to subcommand */
    if (strcmp(argv[1], "select") == 0) {
        return cmd_hdd_select(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "detect") == 0) {
        return cmd_hdd_detect(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "discover") == 0) {
        return cmd_hdd_discover(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "status") == 0) {
        return cmd_hdd_status(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "seek") == 0) {
        return cmd_hdd_seek(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "seek-both") == 0) {
        return cmd_hdd_seek_both(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "recal") == 0) {
        return cmd_hdd_recal(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "read") == 0) {
        return cmd_hdd_read(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "geometry") == 0) {
        return cmd_hdd_geometry(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "health") == 0) {
        return cmd_hdd_health(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "force") == 0) {
        return cmd_hdd_force(argc - 1, &argv[1]);
    } else if (strcmp(argv[1], "esdi-config") == 0) {
        return cmd_hdd_esdi_config(argc - 1, &argv[1]);
    } else {
        uart_printf("Unknown HDD command: %s\n", argv[1]);
        uart_puts("Type 'hdd' for available commands.\n");
        return -1;
    }
}

/*============================================================================
 * CLI Registration
 *============================================================================*/

/**
 * HDD CLI command definition for registration
 */
const cli_cmd_t hdd_cli_cmd = {
    "hdd", "HDD commands (dual-drive: status, detect, discover, seek, read)",
    cmd_hdd
};

/**
 * Initialize and register HDD CLI commands
 */
void hdd_cli_init(void)
{
    /* Initialize HDD HAL */
    hdd_hal_init();

    /* Register HDD command */
    cli_register(&hdd_cli_cmd);
}
