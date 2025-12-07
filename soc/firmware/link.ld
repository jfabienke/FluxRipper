/**
 * FluxRipper SoC - Linker Script
 *
 * Memory layout for MicroBlaze V bare-metal firmware
 * Milestone 0: BRAM only (no HyperRAM)
 *
 * Updated: 2025-12-03 18:00
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    /* Code BRAM - 32KB */
    CODE (rx)  : ORIGIN = 0x00000000, LENGTH = 32K

    /* Data BRAM - 16KB */
    DATA (rwx) : ORIGIN = 0x00010000, LENGTH = 16K
}

/* Stack size */
_stack_size = 2K;

/* Heap size */
_heap_size = 4K;

SECTIONS
{
    /* Code section in CODE BRAM */
    .text :
    {
        _text_start = .;
        *(.text.init)       /* Startup code first */
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
        _text_end = .;
    } > CODE

    /* Data sections in DATA BRAM */
    .data :
    {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > DATA

    /* BSS section */
    .bss (NOLOAD) :
    {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DATA

    /* Heap */
    .heap (NOLOAD) :
    {
        . = ALIGN(8);
        _heap_start = .;
        . += _heap_size;
        _heap_end = .;
    } > DATA

    /* Stack (grows down) */
    .stack (NOLOAD) :
    {
        . = ALIGN(16);
        _stack_end = .;
        . += _stack_size;
        _stack_start = .;
    } > DATA

    /* Ensure we fit in BRAM */
    ASSERT(_stack_start <= ORIGIN(DATA) + LENGTH(DATA),
           "Error: Stack exceeds DATA BRAM bounds")
}

/* Symbols for startup code */
PROVIDE(_stack = _stack_start);
PROVIDE(_estack = _stack_start);
