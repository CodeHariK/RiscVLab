/* Linker script for the bare-metal test programs.
 *
 * Everything starts at 0x80000000, the start of RAM on QEMU `virt` (and in
 * the emulator), with no ELF headers in front of it, so the ELF's single
 * loadable segment begins exactly there. (ld's default script puts the
 * headers in the segment too, which would start it below RAM.)
 * Same idea as the link.ld used by riscv-tests. */

OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text .text.*) }
  .data : { *(.data .data.*) *(.sdata .sdata.*) }
  .bss  : { *(.bss .bss.*) *(.sbss .sbss.*) }
}
