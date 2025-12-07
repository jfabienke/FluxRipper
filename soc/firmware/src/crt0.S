/**
 * FluxRipper SoC - C Runtime Startup
 *
 * Minimal startup code for MicroBlaze V (RISC-V)
 *
 * Updated: 2025-12-03 18:00
 */

.section .text.init, "ax"
.global _start
.type _start, @function

_start:
    /* Disable interrupts */
    csrw    mstatus, zero

    /* Set up global pointer */
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    /* Set up stack pointer */
    la      sp, _stack_start
    /* Align stack to 16 bytes (RISC-V ABI) */
    andi    sp, sp, -16

    /* Clear BSS section */
    la      t0, _bss_start
    la      t1, _bss_end
clear_bss:
    bge     t0, t1, bss_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       clear_bss
bss_done:

    /* Call global constructors (if any) */
    la      a0, _init
    jalr    a0

    /* Call main */
    li      a0, 0               /* argc = 0 */
    li      a1, 0               /* argv = NULL */
    call    main

    /* If main returns, halt */
halt:
    wfi
    j       halt

.size _start, . - _start

/*============================================================================
 * Trap Vector
 *============================================================================*/

.section .text.trap, "ax"
.global _trap_vector
.type _trap_vector, @function
.align 4

_trap_vector:
    /* Save context (minimal) */
    addi    sp, sp, -64
    sw      ra, 0(sp)
    sw      t0, 4(sp)
    sw      t1, 8(sp)
    sw      t2, 12(sp)
    sw      a0, 16(sp)
    sw      a1, 20(sp)
    sw      a2, 24(sp)
    sw      a3, 28(sp)

    /* Call C trap handler */
    call    trap_handler

    /* Restore context */
    lw      ra, 0(sp)
    lw      t0, 4(sp)
    lw      t1, 8(sp)
    lw      t2, 12(sp)
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    lw      a3, 28(sp)
    addi    sp, sp, 64

    mret

.size _trap_vector, . - _trap_vector

/*============================================================================
 * Weak default handlers
 *============================================================================*/

.weak trap_handler
.weak external_interrupt_handler
