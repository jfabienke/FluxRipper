/*-----------------------------------------------------------------------------
 * FluxRipper SoC - Verilator Testbench
 *
 * Simulates the FluxRipper FDC IP with AXI stimulus
 *
 * Updated: 2025-12-03 19:30
 *-----------------------------------------------------------------------------*/

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vfluxripper_dual_top.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

/*-----------------------------------------------------------------------------
 * Simulation Parameters
 *-----------------------------------------------------------------------------*/

#define CLK_PERIOD_NS       5       /* 200 MHz = 5ns period */
#define AXI_CLK_PERIOD_NS   10      /* 100 MHz = 10ns period */
#define SIM_TIME_US         1000    /* Simulation time in microseconds */

#define TRACE_ENABLE        1       /* Enable VCD waveform output */
#define TRACE_DEPTH         99      /* VCD trace depth */

/*-----------------------------------------------------------------------------
 * AXI Register Addresses (from plan)
 *-----------------------------------------------------------------------------*/

/* 82077AA Compatible Registers */
#define REG_SRA         0x00    /* Status Register A */
#define REG_SRB         0x04    /* Status Register B */
#define REG_DOR         0x08    /* Digital Output Register */
#define REG_TDR         0x0C    /* Tape Drive Register */
#define REG_MSR         0x10    /* Main Status Register */
#define REG_DSR         0x10    /* Data Rate Select (write) */
#define REG_DATA        0x14    /* Data FIFO */
#define REG_DIR         0x1C    /* Digital Input Register */
#define REG_CCR         0x1C    /* Configuration Control (write) */

/* FluxRipper Extensions */
#define REG_FLUX_CTRL_A     0x30
#define REG_FLUX_STATUS_A   0x34
#define REG_AUTO_STATUS_A   0x5C
#define REG_AUTO_STATUS_B   0x60
#define REG_DRIVE_PROFILE_A 0x68
#define REG_DRIVE_PROFILE_B 0x74

/*-----------------------------------------------------------------------------
 * Global Variables
 *-----------------------------------------------------------------------------*/

static Vfluxripper_dual_top *dut;
static VerilatedVcdC *trace;
static vluint64_t sim_time = 0;
static vluint64_t clk_200_cycle = 0;
static vluint64_t axi_clk_cycle = 0;

/*-----------------------------------------------------------------------------
 * Clock Generation
 *-----------------------------------------------------------------------------*/

void tick_200mhz()
{
    dut->clk_200mhz = 0;
    dut->eval();
    if (trace) trace->dump(sim_time);
    sim_time += CLK_PERIOD_NS / 2;

    dut->clk_200mhz = 1;
    dut->eval();
    if (trace) trace->dump(sim_time);
    sim_time += CLK_PERIOD_NS / 2;

    clk_200_cycle++;
}

void tick_axi()
{
    dut->s_axi_aclk = 0;
    dut->eval();
    if (trace) trace->dump(sim_time);
    sim_time += AXI_CLK_PERIOD_NS / 2;

    dut->s_axi_aclk = 1;
    dut->eval();
    if (trace) trace->dump(sim_time);
    sim_time += AXI_CLK_PERIOD_NS / 2;

    axi_clk_cycle++;
}

/* Combined clock tick - runs both clocks */
void tick()
{
    /* Run 2 ticks of 200MHz for every 1 tick of 100MHz */
    tick_200mhz();
    tick_200mhz();
    tick_axi();
}

/*-----------------------------------------------------------------------------
 * AXI4-Lite Transactions
 *-----------------------------------------------------------------------------*/

uint32_t axi_read(uint32_t addr)
{
    uint32_t data;

    /* Setup read address */
    dut->s_axi_araddr = addr;
    dut->s_axi_arvalid = 1;
    dut->s_axi_rready = 1;

    /* Wait for address accept */
    int timeout = 100;
    while (!dut->s_axi_arready && timeout-- > 0) {
        tick();
    }
    if (timeout <= 0) {
        printf("ERROR: AXI read address timeout @ 0x%02x\n", addr);
        return 0xDEADBEEF;
    }

    tick();
    dut->s_axi_arvalid = 0;

    /* Wait for read data */
    timeout = 100;
    while (!dut->s_axi_rvalid && timeout-- > 0) {
        tick();
    }
    if (timeout <= 0) {
        printf("ERROR: AXI read data timeout @ 0x%02x\n", addr);
        return 0xDEADBEEF;
    }

    data = dut->s_axi_rdata;
    tick();
    dut->s_axi_rready = 0;

    return data;
}

void axi_write(uint32_t addr, uint32_t data)
{
    /* Setup write address and data */
    dut->s_axi_awaddr = addr;
    dut->s_axi_awvalid = 1;
    dut->s_axi_wdata = data;
    dut->s_axi_wstrb = 0xF;
    dut->s_axi_wvalid = 1;
    dut->s_axi_bready = 1;

    /* Wait for address accept */
    int timeout = 100;
    while ((!dut->s_axi_awready || !dut->s_axi_wready) && timeout-- > 0) {
        tick();
    }
    if (timeout <= 0) {
        printf("ERROR: AXI write address/data timeout @ 0x%02x\n", addr);
        return;
    }

    tick();
    dut->s_axi_awvalid = 0;
    dut->s_axi_wvalid = 0;

    /* Wait for write response */
    timeout = 100;
    while (!dut->s_axi_bvalid && timeout-- > 0) {
        tick();
    }
    if (timeout <= 0) {
        printf("ERROR: AXI write response timeout @ 0x%02x\n", addr);
        return;
    }

    if (dut->s_axi_bresp != 0) {
        printf("WARNING: AXI write error response %d @ 0x%02x\n",
               dut->s_axi_bresp, addr);
    }

    tick();
    dut->s_axi_bready = 0;
}

/*-----------------------------------------------------------------------------
 * Drive Simulation
 *-----------------------------------------------------------------------------*/

/* Simulated drive state */
struct drive_state {
    bool motor_on;
    bool ready;
    bool disk_present;
    bool write_protect;
    uint8_t track;
    uint32_t index_counter;
};

static drive_state drives[4];

void init_drives()
{
    for (int i = 0; i < 4; i++) {
        drives[i].motor_on = false;
        drives[i].ready = false;
        drives[i].disk_present = (i == 0);  /* Disk in drive 0 only */
        drives[i].write_protect = false;
        drives[i].track = 0;
        drives[i].index_counter = 0;
    }
}

void update_drive_signals()
{
    /* Update drive 0 inputs */
    dut->if_a_drv0_ready = drives[0].ready;
    dut->if_a_drv0_track0 = (drives[0].track == 0);
    dut->if_a_drv0_wp = drives[0].write_protect;

    /* Simulate index pulse every 40000 cycles (200ms @ 200MHz) */
    /* 300 RPM = 200ms per revolution */
    dut->if_a_drv0_index = (drives[0].motor_on && (clk_200_cycle % 40000000) < 1000);

    /* Drive 1-3 not present */
    dut->if_a_drv1_ready = 0;
    dut->if_a_drv1_track0 = 1;
    dut->if_a_drv1_wp = 0;
    dut->if_a_drv1_index = 0;

    dut->if_b_drv0_ready = 0;
    dut->if_b_drv0_track0 = 1;
    dut->if_b_drv0_wp = 0;
    dut->if_b_drv0_index = 0;

    dut->if_b_drv1_ready = 0;
    dut->if_b_drv1_track0 = 1;
    dut->if_b_drv1_wp = 0;
    dut->if_b_drv1_index = 0;

    /* Simulate read data (MFM flux pattern) */
    /* Simple: toggle every ~4 cycles for 500Kbps data rate */
    dut->if_a_drv0_read_data = drives[0].motor_on ? ((clk_200_cycle / 400) & 1) : 0;
    dut->if_a_drv1_read_data = 0;
    dut->if_b_drv0_read_data = 0;
    dut->if_b_drv1_read_data = 0;

    /* Monitor motor output */
    if (dut->if_a_drv0_motor && !drives[0].motor_on) {
        printf("[%lu] Drive 0: Motor ON\n", (unsigned long)sim_time);
        drives[0].motor_on = true;
        /* Spin-up delay: become ready after 500ms */
    }
    if (!dut->if_a_drv0_motor && drives[0].motor_on) {
        printf("[%lu] Drive 0: Motor OFF\n", (unsigned long)sim_time);
        drives[0].motor_on = false;
        drives[0].ready = false;
    }

    /* Simulate spin-up: ready after motor has been on for a while */
    if (drives[0].motor_on && drives[0].disk_present) {
        drives[0].ready = true;  /* Instant ready for simulation */
    }
}

/*-----------------------------------------------------------------------------
 * Test Cases
 *-----------------------------------------------------------------------------*/

void test_register_access()
{
    printf("\n=== Test: Register Access ===\n");

    /* Read SRA */
    uint32_t sra = axi_read(REG_SRA);
    printf("SRA = 0x%08x\n", sra);

    /* Read SRB */
    uint32_t srb = axi_read(REG_SRB);
    printf("SRB = 0x%08x\n", srb);

    /* Read MSR */
    uint32_t msr = axi_read(REG_MSR);
    printf("MSR = 0x%08x (RQM=%d, DIO=%d)\n",
           msr, (msr >> 7) & 1, (msr >> 6) & 1);

    /* Write DOR: enable motor for drive 0, select drive 0 */
    printf("Writing DOR: Motor ON, Select Drive 0\n");
    axi_write(REG_DOR, 0x1C);  /* Motor A on, not reset, DMA enable */

    /* Let motor spin up */
    for (int i = 0; i < 100; i++) {
        tick();
        update_drive_signals();
    }

    /* Read MSR again */
    msr = axi_read(REG_MSR);
    printf("MSR = 0x%08x after motor on\n", msr);
}

void test_drive_profile()
{
    printf("\n=== Test: Drive Profile ===\n");

    /* Read drive profile A */
    uint32_t profile = axi_read(REG_DRIVE_PROFILE_A);
    printf("DRIVE_PROFILE_A = 0x%08x\n", profile);

    /* Decode profile */
    uint8_t form_factor = profile & 0x03;
    uint8_t density = (profile >> 2) & 0x03;
    uint8_t tracks = (profile >> 4) & 0x03;
    uint8_t encoding = (profile >> 6) & 0x07;
    uint8_t rpm = (profile >> 16) & 0xFF;
    uint8_t quality = (profile >> 24) & 0xFF;

    const char *ff_str[] = {"Unknown", "3.5\"", "5.25\"", "8\""};
    const char *dens_str[] = {"DD", "HD", "ED", "?"};
    const char *enc_str[] = {"MFM", "FM", "GCR-CBM", "GCR-Apple", "M2FM", "Tandy", "?", "?"};

    printf("  Form Factor: %s\n", ff_str[form_factor]);
    printf("  Density:     %s\n", dens_str[density]);
    printf("  Encoding:    %s\n", enc_str[encoding]);
    printf("  RPM:         %d\n", rpm * 10);
    printf("  Quality:     %d\n", quality);
}

void test_interrupts()
{
    printf("\n=== Test: Interrupts ===\n");

    /* Check interrupt outputs */
    printf("IRQ_FDC_A = %d\n", dut->irq_fdc_a);
    printf("IRQ_FDC_B = %d\n", dut->irq_fdc_b);
}

void test_axis_output()
{
    printf("\n=== Test: AXI-Stream Flux Output ===\n");

    /* Enable flux capture for interface A */
    axi_write(REG_FLUX_CTRL_A, 0x01);  /* Enable capture */

    /* Check AXIS outputs */
    printf("M_AXIS_A: TVALID=%d, TDATA=0x%08x\n",
           dut->m_axis_a_tvalid, dut->m_axis_a_tdata);

    /* Simulate TREADY and capture some data */
    dut->m_axis_a_tready = 1;

    int captured = 0;
    for (int i = 0; i < 1000 && captured < 10; i++) {
        tick();
        update_drive_signals();

        if (dut->m_axis_a_tvalid) {
            printf("  Flux[%d]: 0x%08x\n", captured, dut->m_axis_a_tdata);
            captured++;
        }
    }

    printf("Captured %d flux words\n", captured);

    /* Disable capture */
    axi_write(REG_FLUX_CTRL_A, 0x00);
    dut->m_axis_a_tready = 0;
}

/*-----------------------------------------------------------------------------
 * Main
 *-----------------------------------------------------------------------------*/

int main(int argc, char **argv)
{
    printf("============================================\n");
    printf("FluxRipper SoC - Verilator Testbench\n");
    printf("============================================\n");

    /* Initialize Verilator */
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(TRACE_ENABLE);

    /* Create DUT */
    dut = new Vfluxripper_dual_top;

    /* Setup trace */
    if (TRACE_ENABLE) {
        trace = new VerilatedVcdC;
        dut->trace(trace, TRACE_DEPTH);
        trace->open("fluxripper_soc.vcd");
        printf("VCD trace enabled: fluxripper_soc.vcd\n");
    }

    /* Initialize signals */
    dut->clk_200mhz = 0;
    dut->s_axi_aclk = 0;
    dut->reset_n = 0;
    dut->s_axi_aresetn = 0;

    /* Initialize AXI signals */
    dut->s_axi_awaddr = 0;
    dut->s_axi_awvalid = 0;
    dut->s_axi_wdata = 0;
    dut->s_axi_wstrb = 0;
    dut->s_axi_wvalid = 0;
    dut->s_axi_bready = 0;
    dut->s_axi_araddr = 0;
    dut->s_axi_arvalid = 0;
    dut->s_axi_rready = 0;

    /* Initialize AXIS */
    dut->m_axis_a_tready = 0;
    dut->m_axis_b_tready = 0;

    /* Initialize drives */
    init_drives();
    update_drive_signals();

    /* Hard-sector inputs */
    dut->if_sector_a = 0;
    dut->if_sector_b = 0;

    /* Apply reset */
    printf("\nApplying reset...\n");
    for (int i = 0; i < 10; i++) {
        tick();
    }

    /* Release reset */
    dut->reset_n = 1;
    dut->s_axi_aresetn = 1;
    printf("Reset released\n");

    /* Wait for initialization */
    for (int i = 0; i < 100; i++) {
        tick();
        update_drive_signals();
    }

    /* Run tests */
    test_register_access();
    test_drive_profile();
    test_interrupts();
    test_axis_output();

    /* Run simulation for remaining time */
    printf("\n=== Running simulation... ===\n");
    vluint64_t end_time = SIM_TIME_US * 1000;  /* Convert to ns */
    while (sim_time < end_time) {
        tick();
        update_drive_signals();

        /* Print progress every 100us */
        if (sim_time % 100000 == 0) {
            printf("  Time: %lu us\n", (unsigned long)(sim_time / 1000));
        }
    }

    /* Cleanup */
    printf("\n============================================\n");
    printf("Simulation complete: %lu ns (%lu us)\n",
           (unsigned long)sim_time, (unsigned long)(sim_time / 1000));
    printf("============================================\n");

    if (trace) {
        trace->close();
        delete trace;
    }
    delete dut;

    return 0;
}
