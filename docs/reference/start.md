# Start here

Where to begin, and how the lessons and these docs fit together. Same
format as instructions.md.

## start - Start here

*how to learn with the lessons and the Docs window*

Does: RiscVLab shows how a computer runs a program, one instruction at a time, on a RISC-V emulator you can step forwards and backwards. Each lesson is a short assembly program whose comments explain it; these docs explain every instruction, CSR, trap and device the lessons use.

How it works:
1. Open a lesson from the Programs window (P). The lessons are in order: each builds on the ones before it.
2. Read the comments at the top of the Source tab: what the lesson does, and which registers it uses and why.
3. Press Next (or the right arrow key) to run one instruction. Encoding shows its bits and what it is about to do; Registers and CSRs light up what it changed.
4. Press Prev (the left arrow key) to undo a step, as often as you like: every step can be undone, even a trap or an interrupt.
5. Open Docs (D). It follows the instruction about to run. "This lesson", at the top of its list, holds the entries the lesson is about; under each entry, Related leads to other entries and Lessons to the other lessons that use it.
6. A lesson ends at `ebreak`. Its result is in a0, and the header's `# Expect:` line says what it should be.

The lessons:
| Lessons | What they teach |
|---|---|
| 01-06 | registers, add and sub, logic and shifts, big constants, branches and loops, signed vs unsigned |
| 07-10 | memory, calling a function, recursion and the stack, 32-bit word operations |
| 11-14 | CSRs, traps and a handler, returning with mret, faults |
| 15 | multiply and divide (the M extension) |
| 16-18 | atomics and locks (the A extension) |
| 19-20 | printing through the UART, and setting it up |
| 21 | a timer interrupt |
| 22 | copying memory: a byte or 8 bytes at a time, and what each costs |
| 23 | a real memcpy and memset: any length and alignment (head, body, tail) |
| 24 | user mode: down with mret, what user code may not do, back up with ecall |
| 25 | supervisor mode: firmware, kernel and program; user system calls go to the kernel (medeleg), which returns with sret |

For: anyone new to RISC-V, to assembly, or to how an operating system works with the hardware underneath it. No assembly is needed to start; some C helps.

Emulator: one RISC-V hart (RV64IMA) with a UART and a timer, laid out like QEMU's virt board, so programs written for QEMU run here too. The goal is to boot xv6, a small Unix-like teaching OS, on it.

Watch out: a lesson's comments come before the code they explain. Read the block, then step through the lines it talks about.

Related: register, addi, lb, jal, stack, csr-overview, trap, mul, race-condition, mmio, interrupt
