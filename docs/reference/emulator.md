# The emulator

How this emulator is built and how it runs a program, on one page: its
packages, the machine, what one step does, how Prev undoes it, how
devices plug in, the rules the code keeps, and how to add an instruction
or a device. The debugger's Docs window shows it whole. Same format as
instructions.md. The source is in `emulator/`; each file has one job,
listed in the tables in `emulator/README.md`.

## emulator - How the emulator works

*the packages, one step, undo, devices, and the rules the code keeps*

Does: runs RISC-V programs one step at a time, on a machine laid out like QEMU's virt board, and can undo every step. Next runs one step, Prev undoes it. This page goes from the big picture (the packages, the machine) to what one step does, how undo works, how devices plug in, and how to add to it.

For: knowing what Next and Prev really do, and finding your way around the code before changing it.

Emulator: what comes next, on the way to booting xv6 (supervisor and user modes, Sv39 paging, the PLIC, the virtio disk), is in TODO.md.

### The packages

The emulator is a few Odin packages, one per folder. Dependencies point one way: towards the core, which depends on nothing.
```
                        core (package rv)
          the hart, the bus, traps, interrupts, undo
          no files, no printing: compiles for any target
             ^           ^           ^           ^
             |           |           |           |
          devices      loader      disasm        |
       CLINT, UART    ELF / raw   bits -> text   |
             ^           ^           ^           |
             +-----------+-----+-----+-----------+
                               |
                 +-------------+-------------+
                 |                           |
                cli                       debugger
       rvemu: run, --trace,         rvdbg: raylib + Clay
       --disasm, --check-undo       step debugger, lessons, Docs
```
The core never reads files or prints, so the same core runs the command line, the debugger, and later a WebAssembly build. Front ends read the program, hand the bytes to `loader.load_program`, attach the devices the machine has (`devices.clint_attach`, `devices.uart_attach`), and show the results themselves. The disassembler writes into a buffer the caller gives it.

### The machine

A Machine is the whole emulated computer: one hart, the bus it is wired to, and the undo history.
```
 +---------------------------- Machine -----------------------------+
 |                                                                  |
 |  Cpu (one hart)                         Bus                      |
 |  x0..x31, pc, CSRs,       fetch    +-> RAM at 0x8000_0000        |
 |  privilege, instret,  ------------>|                             |
 |  cycle, reservation,   load/store  +-> devices, by address:      |
 |  undo record                       |     CLINT at 0x0200_0000    |
 |        ^                           |     UART  at 0x1000_0000    |
 |        |   mip (interrupt lines)   |                             |
 |        +---------------------------+                             |
 |                                                                  |
 |  History: one undo record per step, in a ring buffer             |
 +------------------------------------------------------------------+
```
| Piece | File (emulator/core) | What it models |
|---|---|---|
| Machine | machine.odin | the whole computer: one hart, its bus, the undo history; the public API |
| Cpu | cpu.odin, csr.odin | one hart's state: registers, pc, CSRs, privilege, counters, the LR / SC reservation |
| Bus | bus.odin | the physical address space: sends each access to RAM or a device |
| Device | bus.odin; the devices in emulator/devices | a device as the core sees it: a set of procedures |
| Memory map | memory_map.odin | where things live, copied from QEMU's virt board |
| Trap | trap.odin, priv_trap.odin | an exception or interrupt: cause (numbered like mcause) and value (like mtval) |
| Interrupts | interrupts.odin | the devices' lines into mip, and which interrupt to take |
| History | history.odin | undo records, one per step, in a ring buffer |

### One step (Next)

Next runs one step: one instruction, or one interrupt taken instead of an instruction.
1. Interrupts first: if a device is asking (its bit in mip), that interrupt is enabled (mie) and interrupts are on (mstatus.MIE), the step takes the interrupt. It is a trap like any other, and the instruction at the pc runs after the handler's mret.
2. Fetch: read the 32 bits at the pc, from RAM only (a device or an empty address raises Instruction_Access_Fault).
3. Decode: the opcode picks the group, funct3 and funct7 the instruction (see encodings).
4. Execute: read the registers, compute, perhaps load or store (RAM or a device), and write rd.
5. Finish: the pc moves on (pc + 4, or the jump or branch target); minstret and mcycle count one.
6. Or trap: if the instruction can't run (an illegal instruction, a bad address) or asks to (ecall, ebreak), nothing has changed. The pc stays on it and the hart enters the trap handler at mtvec. With no handler set up (mtvec's base is 0) the program stops instead: that is how the lessons end, with ebreak.
The Encoding tab shows what the next step will read, compute and write; the Steps tab lists every step so far. A step that takes an interrupt runs no instruction: the pc jumps to the handler, and the Steps tab marks it "interrupted before it ran". One step is one cycle here: mcycle counts every step, minstret only the instructions that finished, and the CLINT's clock moves on by one per step (see emulator-time). The toolbar's "step N" is that count.

In the code, `machine_step` (machine.odin) runs a step, in this order:
1. Start the undo record: the pc, the counters and the privilege level.
2. If the step clock has reached the time a device said its lines would change (the CLINT's alarm), work out mip again. Then the interrupt check; the common case, nothing pending, costs one test (`mip & mie`).
3. Otherwise `cpu_step` (execute.odin): fetch, set `next_pc = pc + 4`, and `execute` switches on the opcode to the handler for the group (rv64i_alu.odin, rv64a.odin, ...). Handlers read fields with decode.odin, write rd through `reg_write`, jump by setting `next_pc`, and note everything they overwrite in the undo record first. No trap: pc = next_pc, and instret and cycle count one.
4. If the step's load or store reached a device, the bus kept the device's state from before; it goes into the undo record.
5. A trap with a handler: `trap_enter` (priv_trap.odin) sets mepc, mcause, mtval and mstatus (their old values go into the undo record), switches to machine mode and jumps to mtvec; cycle counts the step, instret doesn't. With no handler, nothing is recorded and the trap is returned: the machine stops.
6. The record goes into the history.
7. If a device was used or an alarm time came, mip is worked out again for the next step.
`machine_run` repeats `machine_step` until a trap stops it, the program writes to tohost, or the step limit is reached, calling an observer after each step (the command line's --trace).

### Undo (Prev)

Prev puts the machine back exactly as it was before the last step: registers, memory, CSRs, devices, the pc, the privilege level and the counters. It steps back over traps and interrupts too. One instruction changes very little, so before each change the emulator notes the old value, in one fixed-size record per step (`Undo_Record`, history.odin); `machine_step_back` (machine.odin) puts it back.
| The step changed | Prev | Noted before the change, by |
|---|---|---|
| a register | writes it back | reg_write (cpu.odin), the only place registers change |
| memory | stores the old bytes back (up to 8) | the store handlers, exec_store and amo_store |
| a CSR | csr_restore (csr.odin): exactly, without WARL fix-ups | the CSR instructions (zicsr.odin) and mret |
| a device (UART, CLINT) | the device's restore | the bus, saving the device's whole state before its first access in the step (note_touch) |
| the reservation | copied back | reservation_set (cpu.odin) |
| trap entry | copied back | machine_step, saving mstatus, mepc, mcause and mtval before trap_enter |
| always | copied back | machine_step: the pc, the privilege level, minstret, mcycle |
A device puts its own state back because storing the old value again would act again: storing the old byte to THR would send a second byte.
The records go into a ring buffer, the history. The debugger keeps the last 262144 steps (256K); when it is full, the oldest are forgotten and Prev stops there. The debugger also uses undo to show what Next will do: it runs the step, notes the result and undoes it straight away. mip isn't recorded: it follows from the devices and the clock, so it is worked out again after each step back. The command line records nothing unless it runs `rvemu --check-undo`, which runs a whole program, undoes every step and checks the machine is back where it started; `make test` does that for every test program and lesson.

Real hardware can't step back; this is something an emulator can offer. It only works because nothing leaves the machine for real: the UART's output exists only in the Console, so Prev can take a byte back off it. A real serial line couldn't.

### Devices

The core knows a device only as an `rv.Device` (bus.odin): an address range and a set of procedures. The devices themselves live in the devices package (devices/clint.odin, devices/uart.odin), so the core doesn't depend on any of them. The Devices tab shows their registers.
| Procedure | What it does |
|---|---|
| load, store | a program's access. May change the device: reading the UART's RBR takes the byte out. ok = false (an access size it doesn't take) raises an access fault, and must leave the device as it was |
| peek | a read with no side effects, for the debugger and for undo |
| interrupts | the mip bits the device drives now, and the step clock time at which they change by themselves (the CLINT's alarm), so the core needn't ask every step |
| save, restore | the device's state as 32 bytes, for undo |
| destroy | frees it, when the bus goes |
Rules the bus applies to every device: instructions are fetched from RAM only, atomics (lr, sc, the AMOs) work on RAM only, and an access must fit inside one device's range.

### Design rules

- Registers are u64, and arithmetic wraps. Unsigned wrap-around is exactly the hardware's behaviour, so add and sub need no overflow handling. Signed comparisons and shifts cast to i64 / i32 where they are used.
- Immediates are decoded already sign-extended to 64 bits (as u64), so rs1 + imm just works.
- x0 is enforced in one place: reg_write drops writes to register 0.
- Every state change is recorded for undo: registers change only through reg_write, memory only through the store handlers, devices only through the bus.
- A step that traps changes nothing. Handlers check everything before they write, so a trap with no handler can stop the machine with nothing to undo.
- Every handler returns a Step_Result: nil for success, or a Trap. No handler stops the machine itself; the run loop decides what a trap means.
- The bus owns address checks. Handlers never index RAM directly. A new device is a Device in emulator/devices, attached by the front end; the core doesn't change.
- Big buffers come straight from the OS. RAM and the undo history are mapped with mmap (zeroed_pages.odin), so pages read as zero and take physical memory only once written: a small program costs a few pages, not 128 MiB. (WebAssembly falls back to a normal allocation.)
- Little-endian host assumed. RISC-V is little-endian, and so are Apple Silicon and x86, so multi-byte accesses are direct (unaligned) loads and stores.
- Misaligned data accesses are allowed in RAM (as on QEMU). Misaligned jump targets trap, because without the C extension instructions must be 4-byte aligned; atomics must be naturally aligned.
- The hot loop is measured. A 500M-step loop is the benchmark for changes to machine_step and Cpu: even the size of Cpu shows up in it.

### Adding an instruction

1. Find its major opcode and fields in the spec's instruction listing (see encodings).
2. If the opcode is new, add an OPCODE_* constant and a case in execute (execute.odin).
3. Add the logic to the handler for its group, or a new rv64<ext>.odin file for a new extension.
4. Note everything it overwrites in the undo record before writing. If it changes something the record can't hold yet, extend Undo_Record (history.odin) and machine_step_back.
5. Add its text form to disasm/disasm.odin.
6. Add a check to a test program in tests/programs/ and run `make test` (this also checks undo and the disassembler against objdump).
7. Add it to its group's table in docs/reference/encodings.md, and an entry to docs/reference/instructions.md for the Docs window.

### Adding a device

1. Add its address range to core/memory_map.odin, matching QEMU's virt board.
2. Write it in devices/<name>.odin: its state as a struct, the Device procedures (see Devices above), and <name>_attach(bus). Its saved state must fit in a Device_State (32 bytes).
3. Attach it in the front ends (cli/main.odin, the debugger's session).
4. Add unit tests in unit_tests/, a lesson if it teaches something new, a Docs entry in docs/reference/devices.md, and its registers in the debugger's Devices tab.

Related: encodings, emulator-time, trap, interrupt, mmio, clint, uart, memory-map, csr-overview, retire
