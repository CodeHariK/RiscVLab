# docs

Everything is in `reference/`: RISC-V itself, and how this emulator is
built. The debugger's Docs window shows these files (they are embedded
in it), following the instruction about to run; each lesson names the
entries it is about on its `# Docs:` line, and every entry links to its
related entries and to the lessons that use it. `make docs-check` (part
of `make test`) checks those links.

One file sits outside `reference/`, because the Docs window can't draw
Mermaid diagrams: [How the machine works](machine_flow.md), flowcharts
of the whole emulator, grouped by file and function (start-up, the run
loop, one step, one instruction, the bus, interrupts, trap entry and
mret, step back). GitHub and mermaid.live render them.

- [Start here](reference/start.md): how to learn with the lessons and the Docs window, and what the lessons teach, in order.
- [Instruction encodings](reference/encodings.md): the six formats and the major opcodes, what the emulator supports, and every instruction's opcode and funct values.
- [The emulator](reference/emulator.md): how it is built: the packages, the machine, what one step does, how Prev undoes any step, devices on the bus, design rules, and how to add an instruction or a device.
- [Instructions](reference/instructions.md): what each instruction is for, the pseudo-instructions built from it, common mistakes, and an example.
- [Pseudo-instructions](reference/pseudo-instructions.md): `li`, `la`, `mv`, `ret`, `csrr` and the rest: what each expands to and why.
- [Assembler directives](reference/directives.md): sections, `.globl`, data (`.word`, `.space`), alignment, constants, macros, labels.
- [CSRs](reference/csrs.md): every CSR the emulator has, its fields, and what it is for.
- [Traps and privilege](reference/traps.md): what happens on a trap, interrupts and where they come from, writing a handler, privilege levels, and every trap cause.
- [Devices](reference/devices.md): memory-mapped I/O, polling, the UART, the CLINT, where time comes from and how the emulator counts it.
- [ELF and memory](reference/elf.md): ELF files, segments and sections, symbols, the linker script, the memory map, raw binaries, `tohost`.
- [Terms](reference/terms.md): hart, registers and the ABI, the stack, sign extension, little-endian, WARL and other words the docs use.
- [Concurrency](reference/concurrency.md): race conditions, locks, and memory ordering (fence, acquire and release), from beginner to advanced.
