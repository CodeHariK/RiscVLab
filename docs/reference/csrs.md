# CSRs: the control and status registers

CSRs are registers inside the CPU that describe it and control it: where
traps go, why the last one happened, whether interrupts are on, how many
instructions have run. They are separate from x0..x31 and only reachable
with the CSR instructions (`csrrw`, `csrrs`, `csrrc` and their shorthands
`csrr`, `csrw`, ...).

The debugger's Docs window shows a CSR's entry when the next instruction
reads or writes it, and the CSRs tab shows their values. This file
covers the CSRs the emulator has today: the machine CSRs, and supervisor
mode's trap CSRs (`stvec`, `sepc`, ...). More supervisor CSRs
(`sstatus`, `sie`, `satp`, ...) arrive as supervisor mode grows.

Same format as instructions.md, plus two labels: `Fields:` for the bits
of a CSR, and `Emulator:` for what this emulator does differently from
real hardware.

## csr-overview - What CSRs are, and who changes them

*overview*

Does: CSRs are the CPU's own settings and status, kept inside the CPU next to x0..x31. There are three kinds:
- Settings that software writes and the hardware obeys: mtvec (where traps go), mie (which interrupts are allowed), and later satp (which page table to use).
- Reports that the hardware writes and software reads: mcause, mepc and mtval after a trap, mip when a device wants attention, the cycle and instruction counters.
- Fixed facts about the CPU: mhartid, misa, mvendorid. These are usually wired-in constants, not storage.

How it works: the CPU changes CSRs by itself in a few places:
- Trap entry writes mepc, mcause, mtval and mstatus, then jumps to mtvec.
- `mret` reads mepc and mstatus and updates mstatus.
- The counters go up on every cycle / finished instruction.
- Devices set bits in mip.

Everything else changes only when software runs a CSR instruction.

For: anything that is about the CPU itself rather than about the program's data: traps, interrupts, privilege levels, and later virtual memory. Keeping these out of x0..x31 means ordinary code can't change them by accident, and a privilege level can lock away the CSRs of the levels above it.

Emulator: on RV64 every CSR is 64 bits wide (on RV32 they are 32 bits, and the 64-bit counters are read in two halves, e.g. cycle and cycleh). Here mhartid, misa and the ID CSRs are constants in the code, and the rest, the counters mcycle and minstret included, are fields of the Csr_File struct in core/csr.odin.

Related: csr-addresses, csrrw, csrrs, trap

## csr-addresses - CSR numbers and who may use them

*how CSRs are numbered*

Does: every CSR has a 12-bit number (0x000 to 0xfff); the assembler accepts names instead.

How it works: the top four bits of the number say who may use the CSR.
```
  bit:          11 10  | 9 8   | 7 ......... 0
  field:        region | level | number

  mstatus 0x300 00     | 11    | 0000 0000     read/write, machine only
  cycle   0xc00 11     | 00    | 0000 0000     read-only, anyone
  mhartid 0xf14 11     | 11    | 0001 0100     read-only, machine only
```
- Bits 11..10 = 0b11 means read-only: writing it raises Illegal_Instruction (csr_is_read_only, core/csr.odin). 00, 01 and 10 are all read/write.
- Bits 9..8 give the lowest privilege level allowed (00 user, 01 supervisor, 11 machine): the hart's level must be at least this (csr_allowed, core/csr.odin). These are the same numbers as the privilege levels and mstatus.MPP.

Why bits 11..10 have three read/write values: together with the level they split the numbers into regions, one block per family of CSRs. Only 11 means something to the hardware (read-only); the rest is how the spec keeps families apart:
| Top bits (11..8) | Range | Region | Examples |
|---|---|---|---|
| 00 00 | 0x000 - 0x0ff | user, standard | the floating-point CSRs (not here) |
| 11 00 | 0xc00 - 0xcff | user, read-only | cycle, time, instret |
| 00 01 | 0x100 - 0x1ff | supervisor, standard | sstatus, stvec, sepc, satp |
| 00 11 | 0x300 - 0x3ff | machine, standard | mstatus, mtvec, mepc |
| 01 11 | 0x700 - 0x7ff | machine: debug and trace; custom from 0x7c0 | 0x7c0, the custom CSR the unit tests try (this hart has none) |
| 10 11 | 0xb00 - 0xbff | machine counters; custom from 0xbc0 | mcycle, minstret |
| 11 11 | 0xf00 - 0xfff | machine, read-only | mhartid and the other IDs |
The other combinations are more custom ranges (a chip maker's own CSRs: 0x8xx for user, parts of 0x5xx and 0x9xx for supervisor) and hypervisor mode (level 10), which this hart doesn't have. The counters show the regions at work: mcycle (0xb00, region 10) and cycle (0xc00, region 11) are the same counter, writable under the machine name and read-only under the user name.

cycle is the user-mode name of mcycle (see mcycle).

Every CSR this emulator has, and the ones the supervisor plan adds next, by number (the low bits are grouped by job: 0x00..0x06 trap setup, 0x40..0x44 trap handling, the same at each level):
| Number | Binary: region, level, number | Name | Level | Access | Group | In the emulator |
|---|---|---|---|---|---|---|
| 0x100 | 00 01 0000 0000 | sstatus | supervisor | read/write | trap setup | yes (a view of mstatus) |
| 0x104 | 00 01 0000 0100 | sie | supervisor | read/write | trap setup | yes (view of mie) |
| 0x105 | 00 01 0000 0101 | stvec | supervisor | read/write | trap setup | yes |
| 0x106 | 00 01 0000 0110 | scounteren | supervisor | read/write | trap setup | yes |
| 0x140 | 00 01 0100 0000 | sscratch | supervisor | read/write | trap handling | yes |
| 0x141 | 00 01 0100 0001 | sepc | supervisor | read/write | trap handling | yes |
| 0x142 | 00 01 0100 0010 | scause | supervisor | read/write | trap handling | yes |
| 0x143 | 00 01 0100 0011 | stval | supervisor | read/write | trap handling | yes |
| 0x144 | 00 01 0100 0100 | sip | supervisor | read/write | trap handling | yes (view of mip) |
| 0x14d | 00 01 0100 1101 | stimecmp | supervisor | read/write | timer (Sstc) | yes |
| 0x180 | 00 01 1000 0000 | satp | supervisor | read/write | memory protection | later (paging) |
| 0x300 | 00 11 0000 0000 | mstatus | machine | read/write | trap setup | yes |
| 0x301 | 00 11 0000 0001 | misa | machine | read/write (writes ignored) | trap setup | yes |
| 0x302 | 00 11 0000 0010 | medeleg | machine | read/write | trap setup | yes |
| 0x303 | 00 11 0000 0011 | mideleg | machine | read/write | trap setup | yes |
| 0x304 | 00 11 0000 0100 | mie | machine | read/write | trap setup | yes |
| 0x305 | 00 11 0000 0101 | mtvec | machine | read/write | trap setup | yes |
| 0x306 | 00 11 0000 0110 | mcounteren | machine | read/write | trap setup | yes |
| 0x30a | 00 11 0000 1010 | menvcfg | machine | read/write | configuration | yes |
| 0x340 | 00 11 0100 0000 | mscratch | machine | read/write | trap handling | yes |
| 0x341 | 00 11 0100 0001 | mepc | machine | read/write | trap handling | yes |
| 0x342 | 00 11 0100 0010 | mcause | machine | read/write | trap handling | yes |
| 0x343 | 00 11 0100 0011 | mtval | machine | read/write | trap handling | yes |
| 0x344 | 00 11 0100 0100 | mip | machine | read/write (M bits ignore writes) | trap handling | yes |
| 0xb00 | 10 11 0000 0000 | mcycle | machine | read/write | counters | yes |
| 0xb02 | 10 11 0000 0010 | minstret | machine | read/write | counters | yes |
| 0xc00 | 11 00 0000 0000 | cycle | user | read-only | counters | yes |
| 0xc01 | 11 00 0000 0001 | time | user | read-only | counters | yes (the CLINT's mtime) |
| 0xc02 | 11 00 0000 0010 | instret | user | read-only | counters | yes |
| 0xf11 | 11 11 0001 0001 | mvendorid | machine | read-only | machine information | yes |
| 0xf12 | 11 11 0001 0010 | marchid | machine | read-only | machine information | yes |
| 0xf13 | 11 11 0001 0011 | mimpid | machine | read-only | machine information | yes |
| 0xf14 | 11 11 0001 0100 | mhartid | machine | read-only | machine information | yes |
Using a CSR marked coming or later, or one not in the table, raises Illegal_Instruction here: it doesn't exist yet.

Watch out: using a CSR that does not exist, writing a read-only one, or using one from too low a privilege level all raise Illegal_Instruction.

Related: csrrw, csrrs, csrrc, Illegal_Instruction

## mstatus - Machine status

*CSR 0x300, machine, read / write*

Does: the hart's global state: whether interrupts are on, and what to restore when a trap handler returns.

Fields: one 64-bit register made of small fields; these are the ones this emulator has (the rest read 0):
```
  bit:    63 .. 13 | 12 11 | 10 9 |  8  |  7   | 6 |  5   | 4 |  3  | 2 |  1  | 0
  field:    (0)    |  MPP  | (0)  | SPP | MPIE | 0 | SPIE | 0 | MIE | 0 | SIE | 0

  mstatus = 0x1880 = binary ...0001 1000 1000 0000
                                  ^ ^    ^
                                MPP=11   MPIE=1   (MIE, bit 3, is 0)
```
- MIE (bit 3): machine interrupts enabled. Trap entry clears it, so a handler is not interrupted.
- MPIE (bit 7): MIE as it was before the last trap. `mret` copies it back into MIE.
- MPP (bits 12..11): the privilege level before the last trap: 0b00 user, 0b01 supervisor, 0b11 machine (0b10 is reserved). `mret` returns to it.
- SIE (bit 1), SPIE (bit 5), SPP (bit 8): supervisor mode's copies of MIE, MPIE and MPP, for traps into supervisor mode. SPP is one bit (0 user, 1 supervisor): a trap into supervisor mode never comes from machine mode. Supervisor mode reaches them through sstatus.

How it works: a field in the middle of a register is read by masking and shifting. MPP is bits 12..11, so its mask is 0b11 << 11 = 0x1800: `(mstatus & 0x1800) >> 11` gives 0..3, the mode. Writing it clears those two bits and ORs in the mode shifted left by 11. On a trap, MPIE = MIE, MIE = 0 and MPP = the current level. On `mret`, MIE = MPIE, MPIE = 1, the level = MPP, and MPP = the least privileged mode.

Why MIE goes off in the handler: a second interrupt arriving inside the handler would trap again and overwrite mepc and mcause, so the handler could never get back. With MIE = 0 the handler runs undisturbed; a handler that wants to allow nesting saves mepc and mcause first, then turns MIE on itself.

Why MPIE exists: the handler must run with interrupts off, but afterwards they must be as they were before the trap, on or off. MPIE ("previous MIE") is where trap entry keeps the old value: a one-entry stack. MPP does the same for the privilege level.

Why mret restores it, instead of the handler doing `csrsi mstatus, 8` (MIE = 1) and then jumping back: an interrupt could arrive between those two instructions, while still in the handler, and overwrite mepc. mret turns interrupts back on and jumps in one indivisible step, so there is no such gap.

For: turning interrupts on and off (`csrsi mstatus, 0x8` / `csrci mstatus, 0x8`), and choosing which mode `mret` enters: an OS sets MPP to user mode, then `mret`s into a user program.

Emulator: all three modes exist, so MPP holds 0b11 (machine), 0b01 (supervisor) or 0b00 (user); writing the reserved 0b10 leaves it as it was (WARL). After `mret`, MPP = 0b00, the least privileged mode. mstatus starts as 0x1800 (MPP = machine). SIE, SPIE and SPP are written by traps delegated to supervisor mode (medeleg) and read back by `sret`. SUM and MXR arrive with paging.

Watch out: MIE only affects interrupts (the CLINT's timer, lesson 21); exceptions from instructions happen whatever MIE says.

Related: mret, mie, mtvec, privilege, sstatus

Example:
```
csrsi mstatus, 0x8       # MIE = 1: interrupts on
csrci mstatus, 0x8       # MIE = 0: interrupts off
```

## mtvec - Machine trap vector

*CSR 0x305, machine, read / write*

Does: where the CPU jumps when a trap happens: the address of the trap handler, plus a mode.

Fields:
- BASE (bits 63..2): the handler's address. Its low 2 bits are assumed 0, so the handler must be 4-byte aligned.
- MODE (bits 1..0): 0 = direct, every trap jumps to BASE; 1 = vectored, exceptions jump to BASE but interrupts jump to BASE + 4 * cause.

How it works: why the mode shares the register with the address. Instructions are 4 bytes and must start at a multiple of 4, so any handler's address ends in two 0 bits. Those two bits carry no information, so the spec reuses them for the mode instead of spending a whole CSR on it: one `csrw` sets both, and the hardware just masks them off (`mtvec & ~0b11`) to get the address. The same trick appears elsewhere: page table entries keep their flags in the low bits of a page-aligned address (Sv39), and satp keeps its mode in its top bits.

For: the first thing a program that wants to handle traps does: `la` the handler, `csrw mtvec`.

Emulator: a base address of 0 (mtvec = 0, or 1 for vectored) means "no handler": a trap then stops the machine instead of jumping to address 0. That is how the test programs end with `ebreak`. MODE 2 and 3 are reserved, so bit 1 always reads 0.

Watch out: put `.balign 4` before the handler, or its address has bits in the MODE field.

Related: mepc, mcause, trap, handler, .balign

Example:
```
    la   t0, handler
    csrw mtvec, t0          # direct mode: all traps go to handler
    ...
    .balign 4
handler:
```

## mepc - Machine exception program counter

*CSR 0x341, machine, read / write*

Does: the address of the instruction that was running when the trap happened. `mret` jumps back to it.

How it works: for a fault (a bad load, an illegal instruction) mepc points at the instruction that failed, so returning retries it. For `ecall` and `ebreak` it also points at the instruction itself.

For: a handler reads mepc to see where the trap came from, and changes it to choose where to return.

Emulator: instructions are always 4-byte aligned (no compressed instructions), so the low 2 bits of mepc always read 0.

Watch out: to skip the instruction that trapped (always needed after `ecall`), add 4 to mepc before `mret`, or the same instruction runs again, forever.

Related: mret, mcause, ecall, handler

Example:
```
csrr t0, mepc
addi t0, t0, 0x4         # return to the instruction after the one that trapped
csrw mepc, t0
```

## mcause - Machine trap cause

*CSR 0x342, machine, read / write*

Does: why the last trap happened.

Fields:
- Interrupt (bit 63): 1 for an interrupt (timer, device), 0 for an exception caused by an instruction.
- Exception code (the other bits): which one.

How it works: the exception codes the emulator raises today:
| Code | Cause | When |
|---|---|---|
| 0x0 | Instruction_Address_Misaligned | jump to an address not a multiple of 4 |
| 0x1 | Instruction_Access_Fault | pc outside memory |
| 0x2 | Illegal_Instruction | not a valid instruction, or a CSR not allowed |
| 0x3 | Breakpoint | ebreak |
| 0x5 | Load_Access_Fault | load from outside memory |
| 0x7 | Store_Access_Fault | store to outside memory |
| 0x8 | Ecall_From_U_Mode | ecall in user mode |
| 0x9 | Ecall_From_S_Mode | ecall in supervisor mode |
| 0xb | Ecall_From_M_Mode | ecall in machine mode |
Page faults (0xc, 0xd, 0xf) come with paging. The interrupts have bit 63 set, then their bit in mip:
| mcause | Cause | When |
|---|---|---|
| 0x8000000000000001 | Supervisor_Software_Interrupt | SSIP, not delegated (delegated, it goes to scause) |
| 0x8000000000000003 | Machine_Software_Interrupt | the CLINT's msip |
| 0x8000000000000005 | Supervisor_Timer_Interrupt | STIP, not delegated |
| 0x8000000000000007 | Machine_Timer_Interrupt | the CLINT's alarm (lesson 21) |
| 0x8000000000000009 | Supervisor_External_Interrupt | SEIP, not delegated |
| 0x800000000000000b | Machine_External_Interrupt | the PLIC (later) |

For: the first thing a handler does is read mcause and decide what to do: a system call, a fault to report, a timer tick.

Related: mepc, mtval, trap

Example:
```
csrr t0, mcause
addi t1, zero, 0xb
beq  t0, t1, syscall     # ecall from machine mode
```

## mtval - Machine trap value

*CSR 0x343, machine, read / write*

Does: extra information about the last trap, depending on its cause.
- Access faults and misaligned jumps: the address that failed.
- Illegal_Instruction: the instruction's bits.
- `ecall`, `ebreak`: 0.

For: reporting a fault precisely ("load from 0x1000 failed"), or emulating an instruction the hardware does not have.

Related: mcause, mepc

Example:
```
csrr t1, mtval           # which address was bad?
```

## mscratch - Machine scratch register

*CSR 0x340, machine, read / write*

Does: nothing by itself: a 64-bit register the hardware never touches, free for machine-mode software.

How it works: a trap handler starts with every x register still holding the interrupted code's values, so it has nowhere to keep anything. Swapping a register with mscratch frees one up:
```
csrrw t0, mscratch, t0   # t0 = mscratch (e.g. a save area), mscratch = old t0
```
At the end the same instruction swaps them back.

For: giving the trap handler a pointer to a save area, so it can save the other registers there. xv6 does this.

Related: mtvec, handler, csrrw

Example:
```
csrw mscratch, t1        # store a value (lesson 11)
csrr t4, mscratch        # read it back
```

## mie mip - Machine interrupt enable, interrupt pending

*CSR 0x304 (mie) and 0x344 (mip), machine, read / write*

Does: per-interrupt switches, one bit per interrupt. In mip, a 1 bit means that interrupt is pending: a device is asking. In mie, a 1 bit means software wants that interrupt. mip never turns into mie: the hardware sets one and software sets the other, and an interrupt is taken only when both bits are 1 and the main switch, mstatus.MIE, allows it.

Fields: both registers have the same layout. Bit n is interrupt n, the number that goes into mcause (with bit 63 set) when it is taken. They are 64 bits wide only because every CSR is on RV64; there aren't 64 interrupts. The spec defines a few low bits:
| Bit | In mip | In mie | Interrupt | Comes from |
|---|---|---|---|---|
| 1 | SSIP | SSIE | supervisor software | software: `csrs mip`, or `csrs sip` from supervisor mode |
| 3 | MSIP | MSIE | machine software | the CLINT's msip register (another hart) |
| 5 | STIP | STIE | supervisor timer | software: machine mode's `csrs mip` (stimecmp, later) |
| 7 | MTIP | MTIE | machine timer | the CLINT, when mtime reaches mtimecmp |
| 9 | SEIP | SEIE | supervisor external | software: machine mode's `csrs mip` (the PLIC, later) |
| 11 | MEIP | MEIE | machine external | the PLIC (later), for the UART, the disk, ... |
Bits 16 and up are left for platform-specific interrupts. The rest are reserved and read 0.

How it works: three switches decide whether an interrupt is taken. All three must be on:
| Switch | Who sets it | What it means |
|---|---|---|
| mip bit | the hardware: a wire from a device | this interrupt is pending: the timer reached its alarm |
| mie bit | software, usually once | this interrupt is wanted: timer interrupts are allowed |
| mstatus.MIE | software, and trap entry / mret | machine mode may be interrupted right now |
```
 CLINT alarm --> mip.MTIP ---+
                             AND ---+
 software    --> mie.MTIE ---+      |
                                    AND --> taken: mcause = 0x8000000000000007
 mstatus.MIE -----------------------+
 (or running below machine mode)
```
A pending interrupt that isn't enabled waits in mip, and is taken as soon as the other two switches are on. When several are ready at once, external goes first, then software, then timer.

Why a main switch, when mie exists: the two do different jobs. mie is the long-term choice ("I handle the timer and the UART"). mstatus.MIE is a quick off switch for a short while: trap entry clears it, so a second interrupt can't overwrite mepc and mcause in the middle of a handler, and mret turns it back on. Code can also turn it off around a critical section with `csrci mstatus, 8`. Flipping one bit is cheaper than saving, clearing and restoring all of mie, and the handler never loses track of which interrupts were wanted. In a house, mie is the light switch in each room and mstatus.MIE is the main breaker.
| | mie | mstatus.MIE |
|---|---|---|
| How many bits | one per interrupt | one for all of them |
| Set by | software | software; trap entry turns it off, mret back on |
| Changes | rarely: when the OS starts using a device | on every trap and every return |
| Applies in | every mode | machine mode only |
The main switch applies only in machine mode: running in a lower mode, machine interrupts are always taken, whatever mstatus.MIE says, so a user program can't block the timer. Supervisor mode's interrupts follow the same rule with its own switch, sstatus.SIE (see interrupt for the full table).

Taking an interrupt doesn't clear mip. The bit follows the device: the timer's stays 1 while mtime >= mtimecmp. The handler must clear the source, by writing a later mtimecmp or writing 0 to msip; otherwise the same interrupt is taken again right after mret.

For: choosing which interrupt sources matter, e.g. an OS enables the timer to switch between programs.

Why software can write the supervisor bits: before supervisor mode had its own timer (stimecmp), only machine mode could see the CLINT. So the firmware's machine-mode timer handler passed each tick down by setting STIP (OpenSBI does this), or SSIP (older xv6 does this, through sip). The kernel's supervisor handler then clears it. The machine bits can't be written: they follow their device, and software silences a device by telling the device, not by writing mip.

Emulator: mie keeps the six bits that exist (INTERRUPT_BITS, interrupts.odin: 0xaaa), the others read 0.

mip has two owners, and each may change only its own bits:
```
   devices (the CLINT; the PLIC later)      software (csrw / csrs / csrc mip)
                  |                                       |
     machine bits 11, 7, 3 = 0x888           supervisor bits 9, 5, 1 = 0x222
     MEIP, MTIP, MSIP                        SEIP, STIP, SSIP
                  |                                       |
                  +------------------> mip <--------------+
```
| | Machine bits | Supervisor bits |
|---|---|---|
| Mask (interrupts.odin) | MACHINE_INTERRUPT_BITS = 0x888 | SUPERVISOR_INTERRUPT_BITS = 0x222 |
| Owner | the devices: MTIP and MSIP from the CLINT (MEIP waits for the PLIC) | software |
| A write to mip | ignored | takes the written value |
| Undo | not recorded: worked out again from the devices after every step back | restored like any CSR write |

So two places write mip, and they mirror each other. Each keeps the other owner's bits from the old mip and takes its own bits from the new value:
| | The program writes mip | A device changes |
|---|---|---|
| Code | csr_write, core/csr.odin | machine_update_interrupts, core/machine.odin |
| When | csrw / csrs / csrc mip | after a step that touched a device, after a step back, when an alarm time comes |
| Keeps from the old mip | the machine bits (0x888) | the supervisor bits (0x222) |
| Takes from the new value | the supervisor bits of the written value | the machine bits the devices drive now (bus_interrupt_lines returns only those) |
```
csr.mip = (csr.mip & MACHINE_INTERRUPT_BITS)    | (value & SUPERVISOR_INTERRUPT_BITS)   // program writes
csr.mip = (csr.mip & SUPERVISOR_INTERRUPT_BITS) | lines                               // device changes
```
Both together, step by step, starting with mip = 0:
| What happens | Who | Keeps | Takes | mip after |
|---|---|---|---|---|
| the CLINT's alarm rings | device | S bits: 0x000 | M bits: 0x080 (MTIP) | 0x080 |
| `csrs mip, t0` with t0 = 0x20 (STIP) | program | M bits: 0x080 | S bits: 0x020 | 0x0a0 |
| `csrw mip, t0` with t0 = -1 (all ones) | program | M bits: 0x080 | S bits: 0x222 | 0x2a2: MSIP and MEIP stay 0 |
| `csrw mip, zero` | program | M bits: 0x080 | S bits: 0x000 | 0x080: MTIP can't be written away |
| `csrs mip, t0` with t0 = 0x20 again | program | M bits: 0x080 | S bits: 0x020 | 0x0a0 |
| the program sets a later mtimecmp | device | S bits: 0x020 | M bits: 0x000 | 0x020: STIP survives |
Without the "keeps" half, a write would wipe out the timer's MTIP, and the next device update would wipe out software's STIP.

A supervisor bit that is pending and enabled is taken like any interrupt: by supervisor mode if mideleg delegates it, by machine mode otherwise (see interrupt). The CSRs tab spells out both modes: "M software=0 timer=1 external=0, S software=0 timer=0 external=0".

Watch out:
- A handler that doesn't clear the source is interrupted again as soon as it returns, forever.
- In machine mode a bit in mie does nothing while mstatus.MIE = 0, so lesson 21 sets both: `csrs mie, t0` (MTIE), then `csrsi mstatus, 8` (MIE).

Related: interrupt, interrupt-sources, mstatus, mcause, clint, mideleg

## medeleg - Machine exception delegation

*CSR 0x302, machine, read / write*

Does: chooses which exceptions go straight to supervisor mode instead of machine mode. Bit n is exception cause n (the mcause number): set, and that exception, when it happens in user or supervisor mode, is taken by supervisor mode.

How it works: where an exception goes:
| It happens in | Its medeleg bit | It goes to |
|---|---|---|
| user or supervisor mode | 0 | machine mode: mepc, mcause, mtval, MPP, mtvec |
| user or supervisor mode | 1 | supervisor mode: sepc, scause, stval, SPP, stvec |
| machine mode | either | machine mode: a trap never goes down a level |
The bits this hart has:
| Bit | Exception |
|---|---|
| 0, 1, 2 | Instruction_Address_Misaligned, Instruction_Access_Fault, Illegal_Instruction |
| 3 | Breakpoint |
| 4, 5, 6, 7 | the load and store misaligned and access faults |
| 8, 9 | ecall from user mode, ecall from supervisor mode |
| 11 | ecall from machine mode: can never be delegated, always reads 0 |
| 12, 13, 15 | the page faults (with paging, later) |

For: an OS kernel in supervisor mode handling its own programs' exceptions. Without delegation, every system call and fault from a user program would trap to machine mode (the firmware), which would have to pass it on to the kernel. xv6's firmware stage (start.c) sets medeleg to all ones at boot, so everything that can go to the kernel does. Interrupts have their own register, mideleg.

Emulator: medeleg keeps the bits for causes 0 to 9 and reads 0 everywhere else (WARL). Trap entry follows it (trap_target, core/privilege.odin): a delegated exception from user or supervisor mode writes sepc, scause, stval and sstatus's SPIE / SIE / SPP, and jumps to stvec. If stvec's base is 0, supervisor mode has no handler and the machine stops, as for mtvec = 0. The step details say when a trap was delegated. `sret` returns from a supervisor trap.

Watch out: delegation only moves where the trap goes, not what is allowed. A delegated exception from user mode lands in supervisor mode, but supervisor mode still can't touch machine CSRs, and an exception in machine mode always stays there.

Related: mcause, stvec sepc scause stval sscratch, sstatus, trap, privilege, csr-addresses

Example:
```
li    t0, 0x100           # bit 8: ecall from user mode
csrw  medeleg, t0         # user system calls go to supervisor mode
```

## mideleg - Machine interrupt delegation

*CSR 0x303, machine, read / write*

Does: medeleg's twin for interrupts. Bit n is interrupt n (the number in mcause without bit 63, and the bit in mie / mip): set, and that interrupt is taken by supervisor mode instead of machine mode.

How it works: only the supervisor interrupts can be delegated. A machine interrupt always goes to machine mode, so its mideleg bit reads 0:
| Bit | Interrupt | Can be delegated |
|---|---|---|
| 1 | supervisor software (SSIP) | yes |
| 3 | machine software (MSIP) | no, reads 0 |
| 5 | supervisor timer (STIP) | yes |
| 7 | machine timer (MTIP) | no, reads 0 |
| 9 | supervisor external (SEIP) | yes |
| 11 | machine external (MEIP) | no, reads 0 |
So writing all ones leaves 0x222. A supervisor interrupt whose bit is 0 still exists, but goes to machine mode.

Why the supervisor interrupts aren't simply always supervisor mode's: machine mode decides what a lower mode handles, for interrupts as for exceptions. A firmware that runs no kernel in supervisor mode can keep them all.

For: a kernel in supervisor mode taking its own timer, device and software interrupts. xv6's start.c sets mideleg to 0xffff at boot (the writable bits stick: 0x222).

Emulator: mideleg keeps bits 1, 5 and 9 (MIDELEG_WRITABLE, core/csr.odin) and reads 0 everywhere else. Interrupt entry follows it (trap_target, core/privilege.odin): a delegated interrupt writes sepc, scause (bit 63 set) and sstatus's SPIE / SIE / SPP and jumps to stvec, plus 4 * its number when stvec is vectored. It is held back by sstatus.SIE in supervisor mode and never taken in machine mode (interrupt_to_take, core/interrupts.odin). The step details say "mideleg delegates it". The CSRs tab lists the delegated ones: "to supervisor: S software=0 timer=1 external=0".

Watch out: delegating is half the job. A delegated interrupt is also held back by its bit in mie (STIE for the timer; supervisor mode sets it through sie) and, in supervisor mode, by sstatus.SIE.

Related: medeleg, mie mip, sie sip, interrupt, sstatus, csr-addresses

Example:
```
li    t0, 0x20            # bit 5: supervisor timer
csrw  mideleg, t0         # timer ticks for supervisor mode go to its handler
```

## sstatus - Supervisor status

*CSR 0x100, supervisor, read / write: a view of mstatus*

Does: supervisor mode's window onto mstatus. It is not a register of its own: reading sstatus gives mstatus's supervisor fields, and writing it changes only those fields.

Fields: the supervisor bits of mstatus, at the same positions; every other bit reads 0 through sstatus:
```
  bit:      ... | 12 11 | 10 9 | 8   | 7    | 6 | 5    | 4 | 3   | 2 | 1   | 0
  mstatus:  ... | MPP   | (0)  | SPP | MPIE | 0 | SPIE | 0 | MIE | 0 | SIE | 0
  sstatus:  ... | 0     | 0    | SPP | 0    | 0 | SPIE | 0 | 0   | 0 | SIE | 0
```
| Field | Bit | Meaning | Machine twin |
|---|---|---|---|
| SIE | 1 | supervisor interrupts on | MIE (bit 3) |
| SPIE | 5 | SIE as it was before the last trap into supervisor mode | MPIE (bit 7) |
| SPP | 8 | the level the last trap into supervisor mode came from: 0 user, 1 supervisor | MPP (bits 12..11) |

How it works: one register, two names. Write sstatus = 0x2 (SIE) and mstatus's bit 1 turns on; write mstatus with SPP set and sstatus shows it. The machine fields (MIE, MPIE, MPP) can't be seen or changed through sstatus, so a kernel in supervisor mode manages its own interrupt state without touching the firmware's.

For: the kernel's half of trap handling. A trap into supervisor mode saves SIE into SPIE and the old level into SPP; `sret` puts them back, as `mret` does with the machine fields. xv6 reads sstatus to check where a trap came from (SPP) and sets SIE to turn its interrupts on and off.

Emulator: sstatus reads and writes mstatus through a mask (SSTATUS_MASK, core/csr.odin), and undo puts back only the supervisor fields. A trap delegated to supervisor mode sets SPIE = SIE, SIE = 0 and SPP; `sret` puts them back (SIE = SPIE, SPIE = 1, SPP = user, level = old SPP). SIE holds back delegated interrupts while the hart is in supervisor mode (in user mode they are always taken). RV64 also has a read-only UXL field (bits 33..32, user mode's width); it reads 0 here for now.

Related: mstatus, privilege, stvec sepc scause stval sscratch, sie sip, csr-addresses

Example:
```
csrsi sstatus, 0x2       # SIE = 1: supervisor interrupts on
csrr  t0, sstatus        # read SIE, SPIE, SPP
andi  t0, t0, 0x100      # SPP: did the trap come from supervisor mode?
```

## sie sip - Supervisor interrupt enable, interrupt pending

*CSR 0x104 (sie) and 0x144 (sip), supervisor, read / write: views of mie and mip*

Does: supervisor mode's windows onto mie and mip. Like sstatus, they are not registers of their own. They show only the interrupts machine mode delegated (mideleg), so a kernel in supervisor mode enables and checks its own interrupts without seeing or changing machine mode's.

How it works: the three supervisor views side by side. sstatus looks through a fixed mask; sie and sip look through mideleg, a register machine mode can change:
| | Reads | A write changes |
|---|---|---|
| sstatus | mstatus & SSTATUS_MASK | only the bits in SSTATUS_MASK |
| sie | mie & mideleg | only the delegated enable bits; the rest of mie stays |
| sip | mip & mideleg | only SSIP, and only if it is delegated |
The bits are at the same places as in mie and mip; with all three supervisor interrupts delegated (mideleg = 0x222):
```
  bit:   11    9     7     5     3     1
  mie:   MEIE  SEIE  MTIE  STIE  MSIE  SSIE
  sie:   0     SEIE  0     STIE  0     SSIE      machine bits read 0
  mip:   MEIP  SEIP  MTIP  STIP  MSIP  SSIP
  sip:   0     SEIP  0     STIP  0     SSIP      only SSIP writable
```
For example, with mideleg = 0x20 (only the timer delegated) and mie = 0xa0 (MTIE and STIE):
| Supervisor mode does | sees / gets | mie after |
|---|---|---|
| `csrr t0, sie` | t0 = 0x020: MTIE is hidden | 0x0a0 |
| `csrw sie, zero` | STIE off | 0x080: MTIE stays |
| `csrw sie, t0` with t0 = -1 | STIE on; SSIE and SEIE aren't delegated, so stay off | 0x0a0 |

Why sip lets supervisor mode write only SSIP: SSIP is a software interrupt: nothing outside raises it but software, so the kernel may set and clear it (older xv6 gets its timer ticks as SSIP, and clears it after each one). STIP and SEIP stand for something outside the kernel: the timer (forwarded by machine mode, or stimecmp later) and the PLIC. The kernel clears those by dealing with the source, as with mip's machine bits.

For: a kernel's interrupt setup. xv6's start.c delegates everything (mideleg) and turns on the supervisor timer, software and external interrupts through sie (machine mode may use the supervisor CSRs too); older xv6's handler clears each forwarded tick by clearing SSIP in sip.

Emulator: sie and sip read and write mie and mip through mideleg (core/csr.odin); undo puts back only the bits a write could change. The CSRs tab shows them under sstatus ("enabled (delegated only): S software=0 timer=1 external=0"). It marks a view and the CSR behind it whenever its value changed, whichever was written: a `csrw sie` marks mie too, a `csrw mie` marks sie only if a delegated bit changed, and a `csrw mideleg` marks sie and sip if what they show changed (debugger/state/csr_views.odin).

Watch out: an interrupt that isn't delegated reads 0 in both, even when it is enabled and pending in mie / mip. A kernel that sees sip = 0 while an interrupt is ringing should check mideleg first.

Related: mie mip, mideleg, sstatus, interrupt, csr-addresses

Example:
```
li    t0, 0x222           # SEIE, STIE, SSIE
csrs  sie, t0             # the kernel's interrupts on (those delegated)
csrc  sip, 2              # SSIP handled: clear it
```

## stvec sepc scause stval sscratch - Supervisor trap CSRs

*CSRs 0x105, 0x141, 0x142, 0x143, 0x140, supervisor, read / write*

Does: supervisor mode's own copies of the machine trap CSRs. When a trap is handed to supervisor mode instead of machine mode (delegated, see medeleg), the hardware records it in these, and the supervisor's handler reads them, exactly as a machine handler reads the m ones.

Fields: each works like its machine twin, at the same number with bits 9..8 = 01 (supervisor) instead of 11 (machine):
| S CSR | Number | Machine twin | Holds |
|---|---|---|---|
| stvec | 0x105 | mtvec (0x305) | where supervisor traps go: BASE and MODE, the same layout |
| sepc | 0x141 | mepc (0x341) | the instruction that trapped (the one not yet run, for an interrupt) |
| scause | 0x142 | mcause (0x342) | why: the same cause numbers, bit 63 for an interrupt |
| stval | 0x143 | mtval (0x343) | the bad address or instruction bits |
| sscratch | 0x140 | mscratch (0x340) | nothing by itself: free for the supervisor handler |

How it works: supervisor and machine mode may use them; user mode may not (Illegal_Instruction). They are separate registers from the m ones: a trap into supervisor mode writes sepc and scause and leaves mepc and mcause alone, so a machine handler's state survives a supervisor trap and the other way round.

For: an OS kernel in supervisor mode handling its programs' traps itself. Without its own set, every system call and page fault from a user program would go to machine mode first (the firmware), which would have to pass it on. With them, machine mode delegates those traps once at boot, and from then on they go straight to the kernel. xv6's kernel sets stvec to its trap handler and reads scause, sepc and stval there.

Emulator: all five exist and keep their values (stvec clears bit 1 and sepc its low 2 bits, as mtvec and mepc do), and undo restores them. A trap delegated by medeleg or mideleg writes sepc, scause and stval and jumps to stvec (vectored: interrupts go to stvec base + 4 * number); machine traps leave them alone. `sret` jumps back to sepc.

Related: mtvec, mepc, mcause, mtval, mscratch, privilege, csr-addresses

Example:
```
la    t0, s_handler
csrw  stvec, t0          # supervisor traps will go to s_handler
csrr  t1, scause         # in the handler: why
csrr  t2, sepc           # and where
```

## mcounteren scounteren - Counter enable

*CSR 0x306 (mcounteren), machine, and 0x106 (scounteren), supervisor; read / write*

Does: say which counters (cycle, time, instret) the next mode down may read. Machine mode can always read them; supervisor mode needs machine mode's permission, user mode needs both.

Fields: one bit per counter, at the counter's offset from cycle (cycle 0xc00 is bit 0, time 0xc01 bit 1, instret 0xc02 bit 2):
```
  bit:          2    1    0
  mcounteren:   IR   TM   CY     machine mode lets supervisor mode read
  scounteren:   IR   TM   CY     supervisor mode lets user mode read
                |    |    +---- cycle
                |    +--------- time
                +-------------- instret
```
Bits 3 to 31 would be for the performance counters hpmcounter3..31, which this hart doesn't have.

How it works: permission goes down one mode at a time, so a mode can only pass on what it was given:
| Hart in | May read cycle if | A refused read |
|---|---|---|
| machine mode | always | - |
| supervisor mode | mcounteren.CY = 1 | Illegal_Instruction, to machine mode |
| user mode | mcounteren.CY = 1 and scounteren.CY = 1 | Illegal_Instruction (to supervisor mode if medeleg delegates it) |
time and instret work the same way with TM and IR. Only the read-only names are affected: mcycle and minstret are machine CSRs anyway.

Why a counter needs permission at all: a precise clock is a tool for timing attacks (measuring how long a cache access takes reveals another program's secrets), so a careful system may hide it. And a refused read traps, so a kernel can answer it itself, for example with the cycles of the current process only.

For: firmware and kernels setting up what lower modes see. xv6's start.c sets mcounteren.TM so its kernel can read time for the supervisor timer; Linux lets user programs read time (for gettimeofday without a system call) through scounteren.

Emulator: both keep bits 0 to 2 and start at 0 (as on QEMU): nothing below machine mode may read a counter until machine mode allows it. The check is counter_allowed (core/csr.odin), part of csr_allowed, so a CSR instruction checks it with the level. Lesson 24 sets CY in both before dropping to user mode. The CSRs tab reads them: "lets supervisor mode read: cycle=1 time=0 instret=0".

Watch out: setting mcounteren alone isn't enough for user mode; scounteren must allow it too, even on a system whose supervisor mode does nothing else.

Related: mcycle minstret cycle instret, time, csr-addresses, privilege

Example:
```
li    t0, 0x2             # TM: time
csrs  mcounteren, t0      # supervisor mode may read time
csrs  scounteren, t0      # and user mode too
```

## stimecmp - Supervisor timer compare

*CSR 0x14d, supervisor, read / write (Sstc)*

Does: the supervisor timer's alarm: supervisor mode's own mtimecmp. When time reaches stimecmp, the supervisor timer interrupt (STIP) becomes pending, and it stays pending until the kernel sets a later stimecmp.

How it works: the two timers side by side:
| | Machine timer | Supervisor timer (Sstc) |
|---|---|---|
| Alarm | mtimecmp, a CLINT register (memory address) | stimecmp, a CSR |
| Clock | mtime | time (the same clock) |
| Pending | MTIP while mtime >= mtimecmp | STIP while time >= stimecmp |
| Set by | machine mode | the kernel, in supervisor mode |
Without Sstc, a kernel only gets ticks through machine mode: the firmware takes MTIP, sets STIP by hand, and the kernel clears it again. With it, the firmware stays out of every tick.

Below machine mode it may be used only when machine mode has turned Sstc on (menvcfg.STCE) and lets supervisor mode read time (mcounteren.TM); otherwise it raises Illegal_Instruction.

For: a kernel's clock tick. xv6 sets `stimecmp = time + 1000000` in start.c and again in each timer interrupt.

Emulator: stimecmp is stored and checked (stimecmp_allowed, core/csr.odin) and starts as all ones (no alarm). It doesn't raise STIP yet: that comes next, with the comparison against time.

Related: menvcfg, time, mcounteren scounteren, mie mip, clint

Example:
```
rdtime t0                 # now
li     t1, 1000000
add    t0, t0, t1
csrw   stimecmp, t0       # next tick: now + 1000000
```

## menvcfg - Machine environment configuration

*CSR 0x30a, machine, read / write*

Does: switches, set by machine mode, for features the modes below it may use. Here only one: STCE (bit 63), which turns Sstc (stimecmp) on.

How it works: with STCE = 0, stimecmp doesn't exist below machine mode and STIP is software's to set (the old way). With STCE = 1, supervisor mode may use stimecmp (if mcounteren.TM is set too), and STIP follows the timer. The other fields (bit 0 FIOM, the cache-block bits 4 to 7, PBMTE in bit 62, ...) belong to extensions this hart doesn't have and read 0.

For: firmware enabling extensions for the kernel. xv6's start.c sets STCE first thing in its timer setup.

Emulator: only STCE is writable (MENVCFG_WRITABLE, core/csr.odin); it starts as 0.

Related: stimecmp, mcounteren scounteren, csr-addresses

Example:
```
li    t0, 1
slli  t0, t0, 63          # bit 63: STCE
csrs  menvcfg, t0         # Sstc on for supervisor mode
```

## misa - Machine ISA

*CSR 0x301, machine, read / write*

Does: describes which instruction set the hart implements.

Fields:
- MXL (bits 63..62): register width: 1 = 32-bit, 2 = 64-bit.
- Extensions (bits 25..0): one bit per letter: bit 0 = A, bit 8 = I, bit 12 = M, and so on.

How it works: here misa = 0x8000000000141101: MXL = 2 (RV64), bit 0 (A), bit 8 (I), bit 12 (M), bit 18 (S: supervisor mode) and bit 20 (U: user mode).

For: software that adapts to the hardware it runs on.

Emulator: writes are accepted but ignored: the extensions can't be switched off. Zicsr and Zifencei have no letter, so they don't show up here.

Related: mhartid

## mhartid mvendorid marchid mimpid - Machine ID registers

*CSRs 0xf14, 0xf11, 0xf12, 0xf13, machine, read-only*

Does:
- mhartid: this hart's number, 0 to (number of harts - 1).
- mvendorid, marchid, mimpid: who made the CPU, which design, which version.

For: mhartid lets each hart pick its own stack and work at boot, while all harts run the same code. xv6's start code reads it.

Emulator: one hart, so mhartid is 0; the other three are 0, meaning "not a commercial implementation".

Watch out: writing them raises Illegal_Instruction (their numbers start with 0xf: read-only).

Related: csr-addresses

Example:
```
csrr t0, mhartid         # which hart this is: 0 (lesson 11)
```

## mcycle minstret cycle instret - Counters

*CSRs 0xb00, 0xb02 (machine, read / write) and 0xc00, 0xc02 (user, read-only)*

Does: two counters, each with two names. The m name is for machine mode, which can read and write it; the name without m reads the same counter, read-only, from any mode:
| Counter | Machine name (read / write) | Name for every mode (read-only) | Counts |
|---|---|---|---|
| clock cycles | mcycle, 0xb00 | cycle, 0xc00 | every cycle since reset |
| instructions retired | minstret, 0xb02 | instret, 0xc02 | every instruction that finished since reset |
So there is no separate "cycle" register: `csrr t0, cycle` and `csrr t0, mcycle` read the same number. The m prefix is the usual one for machine-mode CSRs (mstatus, mepc, ...); supervisor ones start with s.

How it works: a counter goes up by itself, without any instruction asking. A program reads it twice and subtracts to see how long something took. Machine mode may write a counter; lower modes can only read (and on real hardware only if machine mode allows it, through mcounteren). After a write the counter carries on going up from the new value. Most programs never write one; machine-mode software does, for a few reasons:
| Why write it | Who does it |
|---|---|
| start a measurement from 0, so the value read later is the answer, with no subtraction | benchmark harnesses, firmware |
| give each process its own count: on a switch, save this process's value and load the next one's, so a program sees only the cycles it ran for | an OS that virtualizes the counters |
| put back a saved machine state (resume after suspend, move a virtual machine) | firmware, hypervisors |
| check that the CSR is writable | test suites (riscv-tests) |

What each one counts:
| | mcycle (cycles: how long) | minstret (instructions: how much work) |
|---|---|---|
| an instruction that completes | +1 here (more on real hardware, see below) | +1 |
| an instruction that traps (it never completes) | +1: the trap still takes time | +0 |
| an interrupt taken | +1 | +0 |
| used by the emulator itself | yes: the step clock, which mtime follows, is mcycle + an offset | no: only programs read it |

Why a CPU has both: on real hardware a cycle is a tick of the clock, and one instruction can take many of them: a divide 10 to 40, a load that misses the cache 100 or more, a mispredicted branch a few. A wide CPU can also finish several instructions in one cycle. So the two counters together say how efficiently code runs, as cycles per instruction:
| Code | mcycle | minstret | Cycles per instruction |
|---|---|---|---|
| a tight loop, all in the cache | 1,000 | 2,000 | 0.5 (two at once) |
| walking a big linked list | 50,000 | 2,000 | 25 (waiting for memory) |
The same amount of work takes 50 times as long. minstret alone can't tell those two apart, and neither can mcycle alone.

For: measuring how long code takes (mcycle), and how much work it did (minstret). Lesson 22 compares two copy loops with minstret: 385 instructions against 49.

Emulator: one cycle per step, so mcycle and minstret read the same number until something traps or a program writes one of them. Both are fields of Csr_File (core/csr.odin). Lower modes read cycle and instret only when machine mode allows it (see mcounteren scounteren). A trap or interrupt taken into a handler is a step: it takes a cycle, as on real hardware, but retires no instruction, so only mcycle counts it. With no writes, mcycle - minstret is the number of traps and interrupts taken so far. Every step costs exactly one cycle here, so cycles per instruction is always about 1: the emulator doesn't model cache misses, slow divides or branch prediction, and timing measured inside it tells you about instructions, not about real hardware. A write changes only that counter. It doesn't move the timer either: mtime follows its own step clock, which no program can write (see emulator-time).

Watch out:
- reading the counter is itself an instruction: two `csrr` of minstret in a row differ by 1 (lesson 11).
- a write takes effect after the writing instruction, so `csrw minstret, t0` makes the next read give exactly t0: the csrw itself isn't counted.

Related: csr-addresses, retire, emulator-time, time, mcounteren scounteren

Example:
```
csrr t5, minstret        # instructions so far
csrr t6, minstret        # one more
```

## time - The platform clock

*CSR 0xc01, user, read-only*

Does: reads the platform's real-time clock: the same counter as the CLINT's mtime. Any mode may read it, so supervisor and user code can tell the time without reaching the CLINT, which sits at a physical address only machine mode normally maps.

How it works: time is a third counter next to cycle and instret, but it doesn't belong to the hart:
| | cycle (mcycle) | time | instret (minstret) |
|---|---|---|---|
| Counts | the hart's clock cycles | the platform clock, at a fixed rate | instructions retired |
| Lives in | the hart | the CLINT (mtime), shared by all harts | the hart |
| Machine name, read / write | mcycle | none: write the CLINT's mtime | minstret |
| Rate | the CPU's clock, which can change (power saving) | fixed (10 MHz on QEMU's virt board) | depends on the code |
That last row is why time exists: cycles say how much work the CPU did, but a CPU that slows down to save power runs fewer cycles per second. time ticks at the same rate whatever the CPU does, so it measures seconds; mtimecmp (and stimecmp, next) set alarms against it.

For: timeouts and timestamps in a kernel, and the supervisor timer: xv6 reads time and sets stimecmp = time + an interval (step 9c).

Emulator: time asks the CLINT (Cpu.time_source, set by clint_attach), so it always equals mtime, including after software writes mtime and after a step back. An instruction sees the clock as its step starts: `csrr t0, time` as the 4th step reads 3. With no CLINT attached (most unit tests) the CSR doesn't exist, and reading it raises Illegal_Instruction, as on cores that leave rdtime to firmware. Like everything here it counts steps, not seconds (see emulator-time). Below machine mode it needs TM in mcounteren (and in scounteren for user mode): see mcounteren scounteren.

Related: mcycle minstret cycle instret, mcounteren scounteren, clint, emulator-time, csr-addresses

Example:
```
rdtime t0                # t0 = time (csrr t0, time)
csrr   t1, cycle         # cycles: can differ from time on real hardware
```
