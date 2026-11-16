# docs

Notes written per milestone: what was built, what was learned, bugs found.

## Emulator

- [Architecture](emulator/architecture.md): the pieces, how one instruction flows through them, design rules, how to add an instruction.
- [Supported instructions](emulator/instructions.md): every instruction the emulator executes, with its encoding fields.

## Reference

What things are for, in plain words. The debugger's Docs window shows these
files (they are embedded in it), following the instruction about to run.

- [Instructions](reference/instructions.md): what each instruction is for, the pseudo-instructions built from it, common mistakes, and an example.
- [Pseudo-instructions](reference/pseudo-instructions.md): `li`, `la`, `mv`, `ret`, `csrr` and the rest: what each expands to and why.
- [Assembler directives](reference/directives.md): sections, `.globl`, data (`.word`, `.space`), alignment, constants, macros, labels.
- [CSRs](reference/csrs.md): every CSR the emulator has, its fields, and what it is for.
- [Traps and privilege](reference/traps.md): what happens on a trap, writing a handler, privilege levels, and every trap cause.
- [ELF and memory](reference/elf.md): ELF files, segments and sections, symbols, the linker script, the memory map, raw binaries, `tohost`.
- [Terms](reference/terms.md): hart, registers and the ABI, the stack, sign extension, little-endian, WARL and other words the docs use.
- [Concurrency](reference/concurrency.md): race conditions, locks, and memory ordering (fence, acquire and release), from beginner to advanced.
