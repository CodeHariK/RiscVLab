# tests

- `programs/lessons/`: short, heavily commented programs that each teach one idea, for stepping through in the debugger (Programs tab). The header's first two lines are the title and description shown there; `# Expect: exit N` is checked by `run_lessons.sh` during `make test`.
- `programs/`: our own small bare-metal test programs (assembly, self-checking; see each `.s` file). Built and run by `make test` in `emulator/`.
- `riscv-tests/`: the official RISC-V test suite (rv64ui-p: every RV64I instruction). `./fetch.sh` downloads it once, then `make riscv-tests` in `emulator/` builds and runs it. Each test reports pass / fail through its `tohost` variable.
- `compare_disasm.sh`: compares the emulator's disassembler with objdump for one program.
