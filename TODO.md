# TODO

The road from the emulator to xv6, then games and a C compiler. Small,
reviewable steps; each one gets tests, docs (docs/reference, Docs window)
and, where it teaches something new, a lesson.

## Done

- [x] RV64I base, Zicsr, Zifencei, machine-mode traps, mret
- [x] M extension: multiply and divide (lesson 15, rv64um tests)
- [x] A extension: lr / sc and the AMOs (lessons 16-18, rv64ua tests)
- [x] ELF and raw binary loading, tohost, riscv-tests (rv64ui, rv64um, rv64ua: 86 pass)
- [x] Undo history (step back), disassembler matching objdump
- [x] Debugger: source / disassembly / steps (compact and detailed), encoding,
      registers, CSRs, memory, stack, ELF tabs; Programs and Docs windows with
      search; lessons 01-19
- [x] Lessons name their Docs entries (# Docs: line); the Docs window opens on them
- [x] Reference docs: instructions, pseudo-instructions, directives, CSRs,
      traps, concurrency, ELF and memory map, devices, terms

## Emulator: on the way to xv6

- [x] UART at 0x10000000: programs can print (lesson 19); Console tab in the
      debugger; devices on the bus with their own undo (receiving keys comes
      with xv6's console)
- [ ] Supervisor and user modes: s-CSRs (sstatus, stvec, sepc, scause, ...),
      medeleg / mideleg, sret, ecall from U / S (rv64mi / rv64si tests);
      a lesson that drops into user mode
- [ ] CLINT timer and interrupts: mtime, mtimecmp, interrupts that fire, wfi
- [ ] Sv39 paging: page tables, page faults, satp, sfence.vma; a debugger
      view of one address being translated
- [ ] PLIC (interrupt controller)
- [ ] virtio disk (xv6's file system)
- [ ] Boot stock xv6 with one hart (CPUS=1); needs riscv64-elf-gcc
- [ ] More harts (xv6's default)

## xv6 in Odin

- [ ] Odin freestanding "hello" on QEMU, then on this emulator
- [ ] Port xv6 piece by piece (Xv6Odin)

## Graphics and games

- [ ] Framebuffer device: pixels in memory, shown in a window / Display tab
- [ ] Input device: keys and mouse as registers, interrupts through the PLIC
- [ ] xv6 driver and device file for the framebuffer and input
- [ ] Simple games (Pong, Snake, Tetris)
- [ ] Command-queue "GPU": fill, copy sprite, draw triangle; DMA and
      completion interrupts
- [ ] Tiny GUI library and window manager on xv6

## C compiler from scratch

- [ ] Lexer, recursive-descent parser, AST
- [ ] Stack-machine code generator emitting RISC-V assembly
- [ ] Locals, functions (calling convention), pointers, arrays, structs,
      globals, strings
- [ ] Compile the lessons' C equivalents, then xv6 user programs or the games

## Maybe later

- [ ] Pre-decoded instruction cache (2-3x faster interpreter)
- [ ] WebAssembly build of the debugger
- [ ] Bitmap or own TrueType font rendering
