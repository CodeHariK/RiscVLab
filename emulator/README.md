# emulator (RiscVOdin)

RISC-V (RV64) emulator in Odin, modelled on QEMU's `virt` machine so it can eventually boot xv6.

**Current state:** RV64I + Zicsr, one hart in machine mode, RAM only. Traps enter the handler at `mtvec`; while no handler is set up (`mtvec` = 0) a trap stops the machine, so simple programs end with `ebreak`.

Docs: [architecture](../docs/emulator/architecture.md) and [supported instructions](../docs/emulator/instructions.md).

## Build and run

```
make                 # release build -> build/rvemu
make debug           # debug build   -> build/rvemu-debug
make test            # unit tests, test programs, undo self-test, disassembler diff
make unit            # unit tests only (unit_tests/)
make run PROGRAM=../tests/programs/build/sum.bin ARGS=--trace
```

### Step debugger

```
make debug-ui                                              # opens sum.elf
make debug-ui PROGRAM=../tests/programs/build/rv64i_check.elf
```

Controls: **Start** reloads the program; **Prev** / **Next** (buttons, or the left / right arrow keys) undo or run one instruction. On the right, **Theme** switches between light and dark. The window shows the disassembly around the PC, the current instruction's encoding (its 32 bits split into colour-coded fields: opcode, registers, funct, immediate pieces), a side panel with **Registers** (the last one written is highlighted) and **Program** (what the loader found) tabs that scroll with the mouse wheel, and a plain-language line for what the next instruction will do and what the last one changed. Uses raylib (ships with Odin) and Clay (`vendor/clay-odin`).

Needs `odin` and the RISC-V binutils (`riscv64-elf-as`, `-ld`, `-objcopy`, `-objdump`; on macOS: `brew install riscv64-elf-binutils`).

```
rvemu <program> [--trace] [--disasm] [--check-undo] [--max-steps N]
```

- The program is an ELF executable (loaded by its segments, started at its entry point) or a raw binary (loaded and started at `0x80000000`).
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
| `cpu.odin` | Hart state: registers, PC, `instret`, CSRs, the current undo record |
| `csr.odin` | Machine-mode CSRs: addresses, storage, read / write rules (WARL) |
| `csr_names.odin` | CSR names for the disassembler and debugger |
| `zicsr.odin` | The CSR instructions: CSRRW / CSRRS / CSRRC and immediate forms |
| `bus.odin` | Physical address routing (RAM for now) |
| `memory_map.odin` | Address constants, matching QEMU `virt` |
| `program.odin` | Loads a program (ELF or raw) and sets the PC: `machine_load_program` |
| `elf.odin` | ELF64 loader: segments, entry point, symbol lookup (`tohost`) |
| `image.odin` | Copies a raw binary into RAM |
| `history.odin` | Undo records and the ring buffer that makes stepping back possible |
| `trap.odin` | Trap causes (`mcause` numbering) and the step result type |
| `priv_trap.odin` | Trap entry: save `mepc` / `mcause` / `mtval`, update `mstatus`, jump to `mtvec`; privilege levels |
| `priv_return.odin` | MRET: return from a trap handler |
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

### `debugger/` (package `rvdbg`): the step debugger

| File | Responsibility |
|---|---|
| `main.odin` | Window, Clay setup, frame loop |
| `session.odin` | The machine being debugged and the Start / Prev / Next actions |
| `input.odin` | Buttons and arrow keys -> session actions |
| `layout.odin` | The Clay layout: toolbar, code, encoding strip, side panel (Registers / Program tabs), explanation |
| `encoding.odin` | Splits an instruction into colour-coded fields for the Encoding strip |
| `explain.odin` | Plain-language text for the next / last instruction and the status |
| `theme.odin` | Light and dark palettes, text styles (font + size), spacing |
| `settings.odin` | Theme setting, switched from the toolbar |
| `view.odin` | Which side-panel tab is showing |
| `fonts.odin` | Loads the embedded font at each text size |
| `fonts/` | JetBrains Mono Medium, embedded at compile time; licence in `fonts/README.md` |
| `program_file.odin` | Reads the program from disk |
| `clay_renderer_raylib.odin` | Clay's raylib renderer, copied from the Clay examples |

### `unit_tests/` (package `rv_unit_tests`)

Unit tests for core rules no test program can reach yet (`csr_test.odin`: CSR read / write rules; `zicsr_test.odin`: CSR instructions that trap, and undo). Run with `make unit`.

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

- Zicsr + machine-mode traps: CSRs, `mtvec` / `mepc` / `mcause`, `mret` (the official `riscv-tests` need these: their startup code configures CSRs and they report results from a trap handler)
- The official `riscv-tests` (`rv64ui`), using the ELF loader and `tohost`
- Supervisor / user modes, then M and A extensions, then Sv39, then the devices
- Debugger: memory view, then CSR / privilege panels
