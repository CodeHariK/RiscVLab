# ELF files and the memory map

How a program gets from a file into the emulator's memory, and where
things live in that memory. The ELF tab in the debugger shows what the
loader found in the program that is open. Same format as
instructions.md.

## elf - ELF executable files

*file format*

Does: ELF (Executable and Linkable Format) is the file format of programs on Linux and most bare-metal toolchains. An ELF file holds the program's bytes plus a description of where to put them and where to start.

How it works: the parts the emulator uses:
1. The header, at the start: checks that it is a 64-bit, little-endian RISC-V executable, and gives the entry point (the address of the first instruction, `_start`).
2. The program headers (segments): what to copy into memory and where.
3. The symbol table: the names of labels and variables, for the debugger's views and for `tohost`.

The loader copies each loadable segment to its address, fills the rest of the segment with zeros, and sets pc to the entry point.

For: the same file works for the emulator, QEMU and a debugger, because the layout is described inside it.

Related: segment, section, symbol, raw-binary

## segment - Segments (program headers)

*part of an ELF file*

Does: a segment says "copy these bytes from the file to this address", plus whether the memory is readable, writable or executable. Segments are what the loader uses.

How it works: each PT_LOAD segment has an address, a size in the file (filesz) and a size in memory (memsz). The loader copies filesz bytes and fills up to memsz with zeros. That gap is the `.bss`: variables that start as zero take no room in the file.

Here the programs have a code segment at 0x80000000 (read / execute) and, if they have data, a data segment on the next 4 KiB page (read / write). The ELF tab shows both ranges.

Related: section, elf, .section

## section - Sections

*part of an ELF file*

Does: sections are the named pieces the assembler and linker work with: `.text`, `.data`, `.bss`, `.rodata`, `.symtab`, debug information.

How it works: the linker groups sections into segments: `.text` goes into the code segment, `.data` and `.bss` into the data segment. Sections such as the symbol table and debug info are not loaded at all.

For: segments are for loading; sections are for building and for tools. The emulator loads by segment and only reads one section, the symbol table.

Related: segment, .section, link.ld

## symbol - Symbols

*part of an ELF file*

Does: the symbol table lists names and their addresses: every label (`_start`, `loop`, `handler`) and variable (`numbers`, `total`, `tohost`).

For: the debugger uses it to show names in the Disassembly and Memory tabs and in the step details (`numbers+0x4`). The emulator uses it to find `tohost`.

Watch out: names are kept only if the assembler is told to keep them; local labels such as `1:` are left out.

Related: labels, .globl, elf

## link.ld - The linker script

*build file*

Does: tells the linker where each section goes in memory and which symbol is the entry point.

How it works: tests/programs/link.ld:
```
ENTRY(_start)                  # the entry point is the label _start
. = 0x80000000;                # start at the beginning of RAM
.text : { ... }                # code first
. = ALIGN(0x1000);             # move on to the next 4 KiB page
.data : { ... }                # then variables with starting values
.bss  : { ... }                # then variables that start as zero
```

For: putting the program where the machine starts running. On QEMU `virt` (and here) that is 0x80000000, so the first instruction must be there.

Watch out: putting data on its own page keeps code and data in separate segments, so the code can stay read / execute only. Without the ALIGN the linker warns about a segment that is readable, writable and executable at once.

Related: section, segment, memory-map

## memory-map - Physical memory map

*where things are*

Does: which physical addresses hold RAM and which hold devices. This emulator copies QEMU's `virt` board, so the same programs (and later xv6) run on both.

How it works:
| Address | What | In this emulator |
|---|---|---|
| 0x00001000 | boot ROM on QEMU | no |
| 0x02000000 | CLINT: timer and software interrupts (see clint) | coming |
| 0x0c000000 | PLIC: device interrupt controller | coming |
| 0x10000000 | UART: serial port, for printing (see uart) | yes |
| 0x10001000 | virtio disk | coming |
| 0x80000000-0x87ffffff | RAM, 128 MiB: programs are loaded here | yes |
Anything else is empty: a load or store there raises an access fault.

For: devices are used with ordinary loads and stores to their addresses (memory-mapped I/O, see mmio); the bus decides whether an address means RAM or a device.

Related: link.ld, Load_Access_Fault Store_Access_Fault, segment, mmio, uart, clint

## raw-binary - Raw binary files (.bin)

*file format*

Does: just the program's bytes, with no header: what `objcopy -O binary` makes from an ELF.

How it works: the emulator copies a .bin to 0x80000000 and starts there. There is no entry point, no symbols, no separate data segment, so the debugger shows less (no names), and the whole file counts as code.

For: the simplest possible format; some boards load raw images.

Related: elf

## tohost - The tohost exit convention

*how test programs report results*

Does: riscv-tests end by storing to a variable named `tohost`. The emulator watches it: when bit 0 of the stored value is 1, the program has finished, with exit code value >> 1 (0 = all tests passed, otherwise the number of the test that failed).

How it works: this is "HTIF", the host interface of the Spike simulator. The test program has no screen or OS to report to, so it writes to an agreed address and the simulator reads it.

For: running the official riscv-tests unchanged. Our own programs end with `ebreak` instead.

Related: symbol, ebreak
