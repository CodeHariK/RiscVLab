# tests

- `programs/lessons/`: short, heavily commented programs that each teach one idea, for stepping through in the debugger (Programs tab): 01 registers, 02 add / sub, 03 logic and shifts, 04 big constants, 05 loops, 06 signed vs unsigned, 07 memory, 08 function calls, 09 recursion and the stack, 10 word operations, 11 CSRs, 12 trap entry, 13 mret, 14 faults. The header's first two lines are the title and description shown there; `# Expect: exit N` is checked by `run_lessons.sh` during `make test`, along with an undo check of the whole run.
- `programs/`: our own small bare-metal test programs (assembly, self-checking; see each `.s` file). Built and run by `make test` in `emulator/`.
- `riscv-tests/`: the official RISC-V test suite (rv64ui-p: every RV64I instruction). `./fetch.sh` downloads it once, then `make riscv-tests` in `emulator/` builds and runs it. Each test reports pass / fail through its `tohost` variable.
- `compare_disasm.sh`: compares the emulator's disassembler with objdump for one program.
