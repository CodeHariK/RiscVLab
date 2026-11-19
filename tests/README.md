# tests

- `programs/lessons/`: short, heavily commented programs that each teach one idea, for stepping through in the debugger (Programs window, P). Each starts with a header:
  - line 1: the title, line 2: a one-line description (both shown in the Programs window);
  - `# Expect: exit N`: the exit code (`a0` at `ebreak`), checked by `run_lessons.sh` during `make test`, along with an undo check of the whole run;
  - `# Expect output: text` (optional): what the program prints through the UART, also checked;
  - `# Docs: a, b`: the Docs entries the lesson is about; the Docs window opens on the first.

  | Lessons | Topic |
  |---|---|
  | 01-06 | registers, add / sub, logic and shifts, big constants, loops, signed vs unsigned |
  | 07-10 | memory, function calls, recursion and the stack, 32-bit word operations |
  | 11-14 | CSRs, trap entry, mret, faults |
  | 15 | multiply and divide (M extension) |
  | 16-18 | an atomic counter, a spinlock, lr / sc (A extension) |
  | 19-20 | printing with the UART, setting it up like xv6 |
  | 21 | a timer interrupt from the CLINT |

- `programs/`: our own small bare-metal test programs (assembly, self-checking; see each `.s` file). Built and run by `make test` in `emulator/`. `link.ld` is the linker script for every program here.
- `riscv-tests/`: the official RISC-V test suites rv64ui (every RV64I instruction), rv64um (M) and rv64ua (A), in the "-p" environment (machine mode, no paging). `./fetch.sh` downloads them once, then `make riscv-tests` in `emulator/` builds and runs them. Each test reports pass / fail through its `tohost` variable.
- `run_lessons.sh`: runs every lesson and checks its `# Expect` lines (part of `make test`).
- `compare_disasm.sh`: compares the emulator's disassembler with objdump for one program.
