# Emulator architecture

How RiscVOdin is put together, and how a single instruction flows through it.
Source lives in `emulator/core/` (the emulator, package `rv`), with `emulator/loader/` (program loading) and `emulator/disasm/` (the disassembler) around it, and the front ends `emulator/cli/` and `emulator/debugger/`. Each file has one responsibility; see the tables in `emulator/README.md`.

## The pieces

```
            +-------------------- Machine --------------------+
            |                                                 |
 program -> |  loader  ->  Bus (RAM @ 0x8000_0000)            |
  .bin      |               ^   ^                             |
            |   fetch / load|   |store                        |
            |               |   |                             |
            |   Cpu: x0..x31, pc, next_pc, instret            |
            |    cpu_step -> execute -> rv64i_* handlers      |
            |                                                 |
            +----------------------|--------------------------+
                                   v
                     Step_Result: nil (ok) or Trap
                                   |
                    machine_run: trace, stop on trap
```

| Piece | What it models | File |
|---|---|---|
| **Machine** | The whole computer: one hart wired to one bus | `machine.odin` |
| **Cpu** | One hart's architectural state: 32 registers, PC, retired-instruction count | `cpu.odin` |
| **Bus** | The physical address space. Routes each access to RAM (devices later) | `bus.odin` |
| **Memory map** | Where things live, copied from QEMU's `virt` board | `memory_map.odin` |
| **Trap** | An exception: cause (numbered like `mcause`) plus value (like `mtval`) | `trap.odin` |
| **History** | Undo records, one per step, in a ring buffer | `history.odin` |

## One step, in order

`cpu_step` in `execute.odin` runs exactly one instruction:

1. **Clear** `last_write` (used only by the trace).
2. **Fetch**: read 4 bytes at `pc` from the bus. If nothing is mapped there: `Instruction_Access_Fault`.
3. **Default next PC**: `next_pc = pc + 4`.
4. **Decode and dispatch**: `execute` switches on the 7-bit major opcode and calls the handler for that instruction group (`rv64i_alu.odin`, `rv64i_control.odin`, ...). Handlers pull fields out with the helpers in `decode.odin`.
5. **Execute**: the handler reads registers, may use the bus, writes `rd` with `reg_write`, and jumps by setting `next_pc`.
6. **Commit or trap**:
   - No trap: `pc = next_pc`, `instret += 1`.
   - Trap: the handler returns a `Trap` and the PC stays on the faulting instruction. `machine_step` then either enters the trap handler (`priv_trap.odin`: `mepc` = that PC, `mcause`, `mtval`, `mstatus`, jump to `mtvec`) or, if no handler is set up (`mtvec` = 0), stops the machine.

`machine_step` (in `machine.odin`) wraps this: before the step it notes the PC and `instret`; during it, `reg_write` and the store handler note the old value of anything they overwrite; afterwards the record goes into the history. `machine_step_back` pops a record and puts those old values back.

`machine_run` repeats `machine_step` until a trap or the step limit, calling an optional observer after each step (the command line uses it for `--trace`).

## Core and front ends

```
 emulator/core   package rv: CPU, bus, decode, execute, history, disassembler
       ^    ^
       |    +------ emulator/cli        rvemu: run, --trace, --disasm, --check-undo
       +----------- emulator/debugger   (next) raylib + Clay step debugger
                    (later)             WebAssembly build for the browser
```

The core never reads files or prints. Front ends read the program (from disk, or from the browser later), pass the bytes to `load_image`, and display results themselves. The disassembler formats into a caller-provided buffer rather than printing.

## Design rules

- **Registers are `u64`, arithmetic wraps.** Unsigned wrap-around is exactly the hardware's behaviour, so `ADD`/`SUB` need no overflow handling. Signed comparisons and shifts cast to `i64` / `i32` at the point of use.
- **Immediates are decoded already sign-extended** to 64 bits (as `u64`), so `rs1 + imm` just works.
- **x0 is enforced in one place**: `reg_write` drops writes to register 0.
- **Every state change is recorded for undo**: registers only change through `reg_write`, memory only through the store handler, and both note the old value first.
- **Every handler returns a `Step_Result`**: `nil` for success, or a `Trap`. No handler stops the machine itself; the run loop decides what a trap means.
- **The bus owns address checks.** Handlers never index RAM directly, so adding a device later means changing only `bus.odin` and `memory_map.odin`.
- **Big buffers come straight from the OS.** RAM and the undo history are mapped with `mmap` (`zeroed_pages.odin`), so pages read as zero and take physical memory only once written: a small program costs a few pages, not 128 MiB, even after the debugger recreates the machine on Reset. (WebAssembly falls back to a normal allocation.)
- **Little-endian host assumed.** RISC-V is little-endian, and so are Apple Silicon and x86, so multi-byte accesses are direct (unaligned) loads and stores.
- **Misaligned data accesses are allowed** (as on QEMU). Misaligned jump targets trap, because without the C extension instructions must be 4-byte aligned.

## Adding an instruction

1. Find its major opcode and fields in the spec's instruction listing.
2. If the opcode is new, add an `OPCODE_*` constant and a `case` in `execute` (`execute.odin`).
3. Add the logic to the handler for its group, or a new `rv64<ext>_<group>.odin` file for a new extension.
4. If it changes state other than one register and one memory location, extend `Undo_Record` (`history.odin`) and `machine_step_back`.
5. Add its text form to `disasm/disasm.odin`.
6. Add a check to a test program in `tests/programs/` and run `make test` (this also checks undo and the disassembler).
7. Add a row to [instructions.md](instructions.md).

## What changes in later milestones

| Milestone | Change to this design |
|---|---|
| ELF loading (done) | `loader/elf.odin` / `loader/program.odin` load ELF segments and set the PC to the entry point |
| riscv-tests | The machine watches the `tohost` address for the pass/fail result |
| Zicsr + machine traps (done) | `Cpu` has CSRs and a privilege level; traps jump to `mtvec`; undo records trap entry |
| Supervisor / user mode | `stvec` / `sepc` / ..., delegation (`medeleg`), `sret` |
| M, A extensions | New `rv64m_*.odin` / `rv64a_*.odin` handlers under existing opcodes (OP, OP-32, AMO) |
| Sv39 | A new MMU between the CPU and the bus translates virtual to physical addresses |
| Devices | UART, CLINT, PLIC, virtio-blk each claim an address range in the bus |
