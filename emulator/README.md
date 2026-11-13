# emulator (RiscVOdin)

RISC-V (RV64) emulator in Odin, modelled on QEMU's `virt` machine so it can eventually boot xv6.

**Current milestone: 1, RV64I core.** One hart, always in machine mode, RAM only, no CSRs yet. Every trap stops the machine; `ebreak` is the normal way for a program to finish.

Docs: [architecture](../docs/emulator/architecture.md) and [supported instructions](../docs/emulator/instructions.md).

## Build and run

```
make                 # release build -> build/rvemu
make debug           # debug build   -> build/rvemu-debug
make test            # assemble ../tests/programs and run them
make run PROGRAM=../tests/programs/build/sum.bin ARGS=--trace
```

Needs `odin` and the RISC-V binutils (`riscv64-elf-as`, `-ld`, `-objcopy`, `-objdump`; on macOS: `brew install riscv64-elf-binutils`).

```
rvemu <program.bin> [--trace] [--max-steps N]
```

- The program is a raw binary loaded at `0x80000000`, where execution starts.
- After `ebreak`, the exit code is the low 8 bits of `a0`, so test programs can report results.
- `--trace` prints one line per instruction: `pc  bits  [xN <- value]`.

## Source layout (`src/`)

| File | Responsibility |
|---|---|
| `main.odin` | Entry point: parse options, load, run, report |
| `options.odin` | Command-line parsing |
| `machine.odin` | The machine (CPU + bus), run loop, final report |
| `cpu.odin` | Hart state: registers, PC, `instret` |
| `bus.odin` | Physical address routing (RAM for now) |
| `memory_map.odin` | Address constants, matching QEMU `virt` |
| `loader.odin` | Raw binary loading |
| `trap.odin` | Trap causes (`mcause` numbering) and the step result type |
| `decode.odin` | Instruction field and immediate extraction |
| `execute.odin` | Fetch, then dispatch by major opcode |
| `rv64i_upper.odin` | LUI, AUIPC |
| `rv64i_control.odin` | JAL, JALR, branches |
| `rv64i_load_store.odin` | Loads and stores |
| `rv64i_alu.odin` | OP-IMM and OP (64-bit arithmetic) |
| `rv64i_alu_word.odin` | OP-IMM-32 and OP-32 (the *W instructions) |
| `rv64i_system.odin` | FENCE, ECALL, EBREAK |
| `trace.odin` | Per-instruction trace output |

## Next milestones

- ELF loading and the official `riscv-tests` (`rv64ui`)
- Zicsr: CSRs, M/S/U modes, trap entry and `mret` / `sret`
- M and A extensions, then Sv39, then the devices
