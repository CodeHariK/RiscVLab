# emulator (RiscVOdin)

RISC-V (RV64) emulator in Odin, modelled on QEMU's `virt` machine so it can eventually boot xv6.

**Current state:** RV64IMA + Zicsr + Zifencei (what xv6 needs), one hart in machine mode, with RAM, the UART and the CLINT timer, and machine-mode interrupts. Traps enter the handler at `mtvec`; while no handler is set up (`mtvec`'s base is 0) a trap stops the machine, so simple programs end with `ebreak`. Every step can be undone.

Docs: [how the emulator is built](../docs/reference/emulator.md) and [instruction encodings](../docs/reference/encodings.md), also in the debugger's Docs window; the full list is in [docs/README.md](../docs/README.md).

## Build and run

```
make                 # release build -> build/rvemu (no step recording: fastest, no --trace / --check-undo)
make check-build     # release build that records steps -> build/rvemu-check
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

`rvdbg` options: `--windowed` opens a normal maximized window instead of native fullscreen (which on macOS is a Space of its own). For a picture of the UI without clicking: `--steps N` runs N instructions, `--tab <name>` selects a tab (repeatable), `--docs <entry>` opens the Docs window on an entry, `--screenshot <file.png>` saves the window once the layout has settled and quits. Scripted runs don't save the settings.

```
./build/rvdbg ../tests/programs/build/lessons/19_uart_hello.elf --steps 40 --tab Devices --tab Steps --screenshot build/ui.png
```

- **Controls:** **Reset** reloads the program; **Prev** / **Next** (or the left / right arrow keys) undo or run one instruction. **Programs** (P or ~) opens the program list, **Docs** (D) the reference docs; both windows have a search box and close with Esc. **Theme** switches light / dark.
- **Code panel:** **Source** (the `.s` file with its comments; programs are assembled with `-g` and the build writes an address -> line map), **Disassembly** (with symbol labels) and **Steps** (every step so far, newest first; Compact or Detailed with every stage of each instruction).
- **Registers:** the pc and x0..x31; tags show what the next instruction reads (rs1 / rs2) and writes (rd), and the last change is highlighted.
- **Side panel:** **CSRs** (privilege level and CSRs, last change highlighted), **Memory** (around the address being used, as words or bytes), **Stack** (sp up to the top, with frames worked out from the steps), **ELF** (what the loader found) and **Devices** (the CLINT's and UART's registers, decoded, with a countdown to the next timer interrupt).
- **Encoding:** the next instruction's 32 bits as colour-coded fields, then what it reads, computes and writes. Next to it, **Console** shows what the program printed through the UART.
- **Layout:** drag the gaps between panels to resize them, and a panel's `::` grip onto another to swap them; **Reset layout** puts them back.
- **Remembered:** theme, layout, each panel's tab, the Steps and Memory modes and the last program are saved to `~/Library/Application Support/RiscVLab/rvdbg.json` (macOS; `~/.config/RiscVLab/` elsewhere) whenever they change, and restored at startup.

Uses raylib (ships with Odin) and Clay (`vendor/clay-odin`).

Needs `odin` and the RISC-V binutils (`riscv64-elf-as`, `-ld`, `-objcopy`, `-objdump`; on macOS: `brew install riscv64-elf-binutils`).

```
rvemu <program> [--trace] [--disasm] [--check-undo] [--max-steps N]
```

`build/rvemu` is built without step recording (`-define:DEBUG_RECORD_STEPS=false`, see `core/history.odin`): about a fifth faster, but it can't undo or say what each step wrote, so `--trace` and `--check-undo` need `build/rvemu-check`. The debugger always records.

- The program is an ELF executable (loaded by its segments, started at its entry point) or a raw binary (loaded and started at `0x80000000`).
- After `ebreak`, the exit code is the low 8 bits of `a0`, so test programs can report results. Programs with a `tohost` symbol (riscv-tests) report their exit code by writing to it.
- What the program prints (bytes stored to the UART at `0x10000000`) goes to stdout, as it runs. The report of how it stopped, and `--trace`, go to stderr.
- `--trace` prints one line per instruction: `pc  bits  disassembly  [reg <- value]`.
- `--disasm` lists the program's disassembly (objdump format) without running it.
- `--check-undo` runs the program, steps back to the start, and checks every register, CSR, byte of RAM and device (the UART and the CLINT) is restored.

## Source layout

The emulator is split into a **core** and **front ends**, so the same core can drive the command-line runner, the debugger UI, and later a WebAssembly build. Each folder is an Odin package; the tools around the core (loading programs, disassembling) have their own, and depend on the core but not the other way round:

```
core      the CPU and the machine                         (package rv)
devices   CLINT, UART (later the PLIC)   -> uses core     (package devices)
loader    ELF / raw program loading      -> uses core     (package loader)
disasm    instruction bits to text       -> uses core     (package disasm)
cli       command-line runner            -> uses all four
debugger  step debugger                  -> uses all four
```

The core's bus only knows devices through `rv.Device`, a set of procedures (load, peek, store, and save / restore for undo); front ends attach the devices a machine has (`devices.uart_attach`).

### `core/` (package `rv`): the emulator itself

No file access and no printing, so it compiles for any target.

| File | Responsibility |
|---|---|
| `machine.odin` | Public API: create, `machine_step`, `machine_step_back`, `machine_run` |
| `cpu.odin` | Hart state: registers, PC, `instret`, `cycle`, CSRs, the LR / SC reservation, the current undo record; the step clock (`cpu_clock`) that devices keep time by |
| `csr.odin` | Machine-mode CSRs: addresses, storage, read / write rules (WARL) |
| `zicsr.odin` | The CSR instructions: CSRRW / CSRRS / CSRRC and immediate forms |
| `bus.odin` | Physical address routing: RAM, or an attached device (`Device`, `bus_attach`); `bus_peek` reads without side effects; fetch is from RAM only |
| `interrupts.odin` | Interrupts: the devices' lines into mip (read only when they can have changed), which interrupt to take at an instruction boundary |
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

### `devices/` (package `devices`): the hardware around the CPU

| File | Responsibility |
|---|---|
| `clint.odin` | The CLINT at `0x02000000`: msip, mtimecmp, and mtime following the step clock (clock + offset); drives mip's MTIP and MSIP |
| `uart.odin` | The UART (NS16550A, as on QEMU) at `0x10000000`: its registers, `output` (what the program printed), `uart_input`, and undo of its state |

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

The debugger links the core, `devices`, `loader` and `disasm` into its own program and calls them directly. It is five packages, with dependencies pointing one way: `rvdbg` -> `view` -> `state` -> the emulator, and `view` and `reference` draw with `ui`:

| Folder | Package | What it is |
|---|---|---|
| `.` | `rvdbg` | `main.odin` (arguments, window, frame loop; native fullscreen in `window_mode_*.odin`), `input.odin` and `modal_input.odin` (buttons, keys, clicks), `settings_file.odin` (saving and restoring the settings, as JSON) |
| `state/` | `state` | The model, no drawing: the session (open, Reset / Prev / Next, the preview of Next), the timeline of steps, memory access tracking, the program list, source and line map, symbols, reading the program file |
| `view/` | `view` | Everything on screen, plus the view state (`display_state.odin`: tabs, scrolls, searches, open windows; the global is `display`) |
| `ui/` | `ui` | Generic UI on raylib + Clay: Clay renderer, theme, fonts, settings, buttons and tabs, tables (`table.odin`), the Markdown subset the docs use (`markdown.odin`), rows of links that wrap (`links.odin`), modal window frame, search box |
| `reference/` | `reference` | The reference docs (`docs/reference/*.md`, embedded): parsing, lookup, search, Related items. `reference_test.odin` checks the docs (`make docs-check`, part of `make test`) |

`view/` in more detail. Everything shown is a tab (`tab_*.odin`); a panel is just a box holding a list of tabs, drawn by one generic proc. `window_` files are windows over everything.

| File | Responsibility |
|---|---|
| `layout.odin`, `panel_layout.odin` | The frame (toolbar, panel slots, dividers, grips), and resizing / rearranging the panels |
| `panel.odin` | The `Tab` enum, which tabs each panel holds (`panel_tabs`), and `draw_panel`: header with tab buttons (or the title of a single tab), then the selected tab's content |
| `code_scroll.odin` | How the code tabs (Source, Disassembly, Steps) scroll and how many lines fit |
| `tab_source.odin`, `tab_disassembly.odin`, `tab_steps.odin` | The program's source, its disassembly, the steps taken (Compact and Detailed) |
| `tab_registers.odin`, `tab_encoding.odin` | Registers with read / write tags; the next instruction's fields and effect |
| `tab_csrs.odin` (with `csr_meaning.odin`), `tab_memory.odin`, `tab_stack.odin`, `tab_elf.odin` | CSRs, memory dump, stack, ELF info |
| `tab_console.odin`, `tab_devices.odin`, `device_text.odin` | What the program printed through the UART; the devices' registers, decoded; device registers in the step text (`uart THR <- 0x48 'H'`) |
| `window_programs.odin`, `window_docs.odin`, `docs_related.odin` | The Programs and Docs windows; an entry's Related and Lessons links (what they lead to, drawn with `ui.link_rows`) |
| `step_detail.odin`, `step_execute.odin`, `timeline_text.odin`, `explain.odin`, `instruction_text.odin`, `number_format.odin` | Text: the stages of a step, step summaries, the status line, numbers in hex with decimals |
| `encoding.odin`, `field_colors.odin` | An instruction as colour-coded fields, and the field colours per theme |
| `display_state.odin`, `ids.odin` | The view state (global `display`), and the ids of buttons and tabs shared with the input handling |

### `unit_tests/` (package `rv_unit_tests`)

Unit tests for core rules the test programs can't reach easily: CSR read / write rules (`csr_test.odin`), CSR instructions that trap (`zicsr_test.odin`), multiply / divide special cases (`muldiv_test.odin`), LR / SC reservations and atomics (`atomic_test.odin`), the undo history (`history_test.odin`), the loader's checks (`loader_test.odin`), the UART and devices on the bus (`uart_test.odin`), attaching devices (`bus_test.odin`), the CLINT, interrupts and the step clock (`clint_test.odin`). Run with `make unit`.

### `cli/` (package `rvemu`): the command-line runner

| File | Responsibility |
|---|---|
| `main.odin` | Entry point: parse options, read the file, run in the chosen mode |
| `options.odin` | Command-line parsing |
| `program_file.odin` | Reads the program from disk |
| `report.odin` | Prints how the run ended (stderr); picks the exit code |
| `console.odin` | Runs the program, writing what it prints through the UART to stdout as it goes |
| `trace.odin` | `--trace` output |
| `disasm_listing.odin` | `--disasm` output |
| `undo_check.odin` | `--check-undo` self-test |

## Next milestones

See [TODO.md](../TODO.md).
