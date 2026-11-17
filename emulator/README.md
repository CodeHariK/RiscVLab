# emulator (RiscVOdin)

RISC-V (RV64) emulator in Odin, modelled on QEMU's `virt` machine so it can eventually boot xv6.

**Current state:** RV64IMA + Zicsr + Zifencei (what xv6 needs), one hart in machine mode, RAM only. Traps enter the handler at `mtvec`; while no handler is set up (`mtvec` = 0) a trap stops the machine, so simple programs end with `ebreak`.

Docs: [architecture](../docs/emulator/architecture.md) and [supported instructions](../docs/emulator/instructions.md).

## Build and run

```
make                 # release build -> build/rvemu
make debug           # debug build   -> build/rvemu-debug
make test            # unit tests, test programs, undo self-test, disassembler diff
make unit            # unit tests only (unit_tests/)
make riscv-tests     # the official rv64ui, rv64um and rv64ua tests (run ../tests/riscv-tests/fetch.sh once first)
make run PROGRAM=../tests/programs/build/sum.bin ARGS=--trace
```

### Step debugger

```
make debug-ui                                              # opens the first lesson and the Programs window (P) to pick others
make debug-ui UI_PROGRAM=../tests/programs/build/rv64i_check.elf
```

- **Controls:** **Reset** reloads the program; **Prev** / **Next** (or the left / right arrow keys) undo or run one instruction. **Programs** (P or ~) opens the program list, **Docs** (D) the reference docs; both windows have a search box and close with Esc. **Theme** switches light / dark.
- **Code panel:** **Source** (the `.s` file with its comments; programs are assembled with `-g` and the build writes an address -> line map), **Disassembly** (with symbol labels) and **Steps** (every step so far, newest first; Compact or Detailed with every stage of each instruction).
- **Registers:** the pc and x0..x31; tags show what the next instruction reads (rs1 / rs2) and writes (rd), and the last change is highlighted.
- **Side panel:** **CSRs** (privilege level and CSRs, last change highlighted), **Memory** (around the address being used, as words or bytes), **Stack** (sp up to the top, with frames worked out from the steps) and **ELF** (what the loader found).
- **Encoding:** the next instruction's 32 bits as colour-coded fields, then what it reads, computes and writes.
- **Layout:** drag the gaps between panels to resize them, and a panel's `::` grip onto another to swap them.

Uses raylib (ships with Odin) and Clay (`vendor/clay-odin`).

Needs `odin` and the RISC-V binutils (`riscv64-elf-as`, `-ld`, `-objcopy`, `-objdump`; on macOS: `brew install riscv64-elf-binutils`).

```
rvemu <program> [--trace] [--disasm] [--check-undo] [--max-steps N]
```

- The program is an ELF executable (loaded by its segments, started at its entry point) or a raw binary (loaded and started at `0x80000000`).
- After `ebreak`, the exit code is the low 8 bits of `a0`, so test programs can report results. Programs with a `tohost` symbol (riscv-tests) report their exit code by writing to it.
- `--trace` prints one line per instruction: `pc  bits  disassembly  [reg <- value]`.
- `--disasm` lists the program's disassembly (objdump format) without running it.
- `--check-undo` runs the program, steps back to the start, and checks every register and byte of RAM is restored.

## Source layout

The emulator is split into a **core** and **front ends**, so the same core can drive the command-line runner, the debugger UI, and later a WebAssembly build. Each folder is an Odin package; the tools around the core (loading programs, disassembling) have their own, and depend on the core but not the other way round:

```
core      the CPU and the machine                         (package rv)
loader    ELF / raw program loading      -> uses core     (package loader)
disasm    instruction bits to text       -> uses core     (package disasm)
cli       command-line runner            -> uses all three
debugger  step debugger                  -> uses all three
```

### `core/` (package `rv`): the emulator itself

No file access and no printing, so it compiles for any target.

| File | Responsibility |
|---|---|
| `machine.odin` | Public API: create, `machine_step`, `machine_step_back`, `machine_run` |
| `cpu.odin` | Hart state: registers, PC, `instret`, CSRs, the LR / SC reservation, the current undo record |
| `csr.odin` | Machine-mode CSRs: addresses, storage, read / write rules (WARL) |
| `zicsr.odin` | The CSR instructions: CSRRW / CSRRS / CSRRC and immediate forms |
| `bus.odin` | Physical address routing (RAM for now) |
| `memory_map.odin` | Address constants, matching QEMU `virt` |
| `zeroed_pages.odin` | RAM and undo history mapped straight from the OS (`zeroed_pages_wasm.odin` for WebAssembly) |
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
| `rv64m.odin` | M extension: multiply and divide |
| `rv64a.odin` | A extension: LR / SC and the AMOs |

### `loader/` (package `loader`): putting a program in memory

| File | Responsibility |
|---|---|
| `program.odin` | Loads a program (ELF or raw) and sets the PC: `loader.load_program` |
| `elf.odin` | ELF64 loader: segments, entry point, symbol lookup (`tohost`), symbol list for the debugger |
| `image.odin` | Copies a raw binary into RAM |

### `disasm/` (package `disasm`): instructions as text

| File | Responsibility |
|---|---|
| `disasm.odin` | Instruction bits to assembly text, matching `objdump -M no-aliases`: `disasm.disassemble` |
| `register_names.odin` | ABI register names (`zero`, `ra`, `sp`, ...) |
| `csr_names.odin` | CSR names, for the disassembler and the debugger |

### `debugger/` (package `rvdbg`): the step debugger

The debugger links the core, `loader` and `disasm` into its own program and calls them directly. Two sub-packages hold the parts that know nothing about RISC-V:

| Folder | Package | What it is |
|---|---|---|
| `ui/` | `ui` | Generic UI on raylib + Clay: the Clay renderer, theme (palettes, text styles), embedded fonts, settings, buttons and tabs, the modal window frame, the search box |
| `reference/` | `reference` | The reference docs (`docs/reference/*.md`, embedded): parsing entries, lookup by name, search |

The debugger itself:

| File | Responsibility |
|---|---|
| `main.odin` | Arguments, window (native fullscreen on macOS: `window_mode_*.odin`), Clay setup, frame loop |
| `session.odin` | The machine being debugged: open, Reset / Prev / Next, and the preview of what Next will do |
| `timeline.odin` | Every step taken: what it read and changed, and its one-line summary |
| `step_detail.odin` | The stages of one step (fetch, decode, read, execute, memory, write); `step_execute.odin` writes the execute stage |
| `instruction_text.odin`, `explain.odin`, `number_format.odin` | Words for instructions, the status line, and hex-with-decimal numbers |
| `layout.odin` | The Clay layout: toolbar, code panel, registers, side panel, encoding |
| `panel_layout.odin` | Resizing (dividers) and rearranging (drag a panel's grip onto another) the panels |
| `steps_view.odin` | The Steps tab, Compact and Detailed |
| `memory_view.odin`, `stack_view.odin`, `csr_view.odin` | The Memory, Stack and CSRs tabs |
| `encoding.odin`, `field_colors.odin` | An instruction as colour-coded fields, and the field colours per theme |
| `source.odin`, `symbols.odin` | The program's source and address -> line map, and its symbol names |
| `catalog.odin`, `programs_modal.odin` | The program list (lessons, test programs, riscv-tests) and the Programs window |
| `docs_view.odin` | The Docs window: follows the next instruction, the lesson's own entries (`# Docs:` line), search |
| `input.odin`, `modal_input.odin` | Buttons, keys and clicks; the windows' keys |
| `view.odin` | Which tabs and windows are showing, scroll positions, searches |
| `program_file.odin` | Reads the program from disk |

### `unit_tests/` (package `rv_unit_tests`)

Unit tests for core rules the test programs can't reach easily: CSR read / write rules (`csr_test.odin`), CSR instructions that trap (`zicsr_test.odin`), multiply / divide special cases (`muldiv_test.odin`), LR / SC reservations and atomics (`atomic_test.odin`). Run with `make unit`.

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

See [TODO.md](../TODO.md).
