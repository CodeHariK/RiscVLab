# emulator (RiscVOdin)

RISC-V (RV64) emulator in Odin, modelled on QEMU's `virt` machine so it can eventually boot xv6.

**Current milestone: 1, RV64I core.** One hart, always in machine mode, RAM only, no CSRs yet. Every trap stops the machine; `ebreak` is the normal way for a program to finish.

Docs: [architecture](../docs/emulator/architecture.md) and [supported instructions](../docs/emulator/instructions.md).

## Build and run

```
make                 # release build -> build/rvemu
make debug           # debug build   -> build/rvemu-debug
make test            # run the test programs, the undo self-test and the disassembler diff
make run PROGRAM=../tests/programs/build/sum.bin ARGS=--trace
```

Needs `odin` and the RISC-V binutils (`riscv64-elf-as`, `-ld`, `-objcopy`, `-objdump`; on macOS: `brew install riscv64-elf-binutils`).

```
rvemu <program.bin> [--trace] [--disasm] [--check-undo] [--max-steps N]
```

- The program is a raw binary loaded at `0x80000000`, where execution starts.
- After `ebreak`, the exit code is the low 8 bits of `a0`, so test programs can report results.
- `--trace` prints one line per instruction: `pc  bits  disassembly  [reg <- value]`.
- `--disasm` lists the program's disassembly (objdump format) without running it.
- `--check-undo` runs the program, steps back to the start, and checks every register and byte of RAM is restored.

## Source layout

The emulator is split into a **core** and **front ends**, so the same core can drive the command-line runner, the debugger UI, and later a WebAssembly build.

### `core/` (package `rv`): the emulator itself

No file access and no printing, so it compiles for any target.

| File | Responsibility |
|---|---|
| `machine.odin` | Public API: create, `machine_step`, `machine_step_back`, `machine_run` |
| `cpu.odin` | Hart state: registers, PC, `instret`, the current undo record |
| `bus.odin` | Physical address routing (RAM for now) |
| `memory_map.odin` | Address constants, matching QEMU `virt` |
| `image.odin` | Copies a program image (bytes) into RAM |
| `history.odin` | Undo records and the ring buffer that makes stepping back possible |
| `trap.odin` | Trap causes (`mcause` numbering) and the step result type |
| `decode.odin` | Instruction field and immediate extraction |
| `execute.odin` | Fetch, then dispatch by major opcode |
| `rv64i_upper.odin` | LUI, AUIPC |
| `rv64i_control.odin` | JAL, JALR, branches |
| `rv64i_load_store.odin` | Loads and stores |
| `rv64i_alu.odin` | OP-IMM and OP (64-bit arithmetic) |
| `rv64i_alu_word.odin` | OP-IMM-32 and OP-32 (the *W instructions) |
| `rv64i_system.odin` | FENCE, ECALL, EBREAK |
| `disasm.odin` | Instruction bits to assembly text (objdump format) |
| `register_names.odin` | ABI register names (`zero`, `ra`, `sp`, ...) |

### `cli/` (package `rvemu`): the command-line runner

| File | Responsibility |
|---|---|
| `main.odin` | Entry point: parse options, read the file, run in the chosen mode |
| `options.odin` | Command-line parsing |
| `program_file.odin` | Reads the program from disk |
| `report.odin` | Prints how the run ended; picks the exit code |
| `trace.odin` | `--trace` output |
| `disasm_listing.odin` | `--disasm` output |
| `undo_check.odin` | `--check-undo` self-test |

## Next milestones

- Debugger UI (raylib + Clay): Start, Prev / Next, disassembly, registers, explanation
- ELF loading and the official `riscv-tests` (`rv64ui`)
- Zicsr: CSRs, M/S/U modes, trap entry and `mret` / `sret`
- M and A extensions, then Sv39, then the devices
