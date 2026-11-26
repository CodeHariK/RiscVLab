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
      search; lessons 01-21
- [x] Lessons name their Docs entries (# Docs: line); the Docs window opens on them
- [x] Reference docs: instructions, pseudo-instructions, directives, CSRs,
      traps, concurrency, ELF and memory map, devices, terms

## Emulator: on the way to xv6

- [x] UART at 0x10000000: programs can print (lessons 19, 20); Console tab in the
      debugger; devices on the bus with their own undo (receiving keys comes
      with xv6's console)
- [x] CLINT timer and machine-mode interrupts: msip, mtimecmp, mtime following
      the step clock (deterministic, undoable), interrupts taken at instruction
      boundaries, vectored mtvec, wfi as a nop (lesson 21)
- [x] User mode: mret down, ecall up, CSR levels enforced (lesson 24)
- [x] Supervisor mode: s-CSRs (sstatus, stvec, sepc, scause, stval,
      sscratch), medeleg, sret; mideleg, sie / sip, taking supervisor
      interrupts; the time CSR; mcounteren / scounteren
- [ ] Sstc for xv6's timer: menvcfg.STCE, stimecmp, STIP from
      time >= stimecmp
- [ ] rv64mi / rv64si tests; a lesson in supervisor mode
- [ ] Time: wfi jumps the clock to the next alarm; a host clock for running
      xv6's shell from rvemu
- [ ] UART output is kept whole (undo puts back its length); a long xv6
      session will want the oldest output dropped (rvemu has printed it)
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

## Own ISA: simple, but runs an OS

After xv6 on RISC-V: by then it is clear which parts an OS really needs,
and xv6's tests have shown the emulator is right. A "RISC-V distilled"
that the C compiler targets, the games run on, and that fits an FPGA.
Most of RISC-V's weight is the privileged side's generality (three modes,
delegation, extensions), not the instructions.

- [ ] Look at small designs for ideas: Wirth's RISC5 (Project Oberon),
      MIPS R3000 with OS/161 (software-filled TLB), Nand2Tetris Hack
- [ ] Design it: 32-bit, 16 registers, about 40 instructions; two modes
      (user, kernel), one trap vector, a few control registers (status,
      cause, epc, trap value, page-table base); one timer compare; a
      two-level page table; one interrupt line from a simple controller
- [ ] Spec document and encoding tables, written like docs/reference
- [ ] Emulator core for it, reusing the bus, devices, undo history,
      debugger and docs system
- [ ] Assembler, then a C compiler back end for it
- [ ] Port the small OS (xv6 in Odin, or a smaller one) to it
- [ ] Maybe: run it on an FPGA

## Maybe later

- [ ] Pre-decoded instruction cache (2-3x faster interpreter)
- [ ] WebAssembly build of the debugger
- [ ] Bitmap or own TrueType font rendering
