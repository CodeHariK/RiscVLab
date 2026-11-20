# CSRs: the control and status registers

CSRs are registers inside the CPU that describe it and control it: where
traps go, why the last one happened, whether interrupts are on, how many
instructions have run. They are separate from x0..x31 and only reachable
with the CSR instructions (`csrrw`, `csrrs`, `csrrc` and their shorthands
`csrr`, `csrw`, ...).

The debugger's Docs window shows a CSR's entry when the next instruction
reads or writes it, and the CSRs tab shows their values. This file
covers the CSRs the emulator has today; the supervisor CSRs (`sstatus`,
`stvec`, `satp`, ...) arrive with supervisor mode.

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
- Bits 11..10 = 0b11 means read-only: writing it raises Illegal_Instruction.
- Bits 9..8 give the lowest privilege level allowed: 0b00 user, 0b01 supervisor, 0b11 machine.

For example, mhartid is 0xf14 = 0b1111_0001_0100: bits 11..10 are 0b11 (read-only) and bits 9..8 are 0b11 (machine only). mstatus is 0x300: writable, machine only. cycle is 0xc00: read-only, usable from user mode (it is the user name of mcycle, see mcycle).

Watch out: using a CSR that does not exist, writing a read-only one, or using one from too low a privilege level all raise Illegal_Instruction.

Related: csrrw, csrrs, csrrc, Illegal_Instruction

## mstatus - Machine status

*CSR 0x300, machine, read / write*

Does: the hart's global state: whether interrupts are on, and what to restore when a trap handler returns.

Fields: one 64-bit register made of small fields; these are the ones this emulator has (the rest read 0):
```
  bit:    63 ... 13 | 12  11 | 10  9  8 |   7  | 6  5  4 |  3  | 2  1  0
  field:     (0)    |  MPP   |   (0)    | MPIE |   (0)   | MIE |   (0)

  mstatus = 0x1880 = binary ...0001 1000 1000 0000
                                  ^ ^    ^
                                MPP=11   MPIE=1   (MIE, bit 3, is 0)
```
- MIE (bit 3): machine interrupts enabled. Trap entry clears it, so a handler is not interrupted.
- MPIE (bit 7): MIE as it was before the last trap. `mret` copies it back into MIE.
- MPP (bits 12..11): the privilege level before the last trap: 0b00 user, 0b01 supervisor, 0b11 machine (0b10 is reserved). `mret` returns to it.

How it works: a field in the middle of a register is read by masking and shifting. MPP is bits 12..11, so its mask is 0b11 << 11 = 0x1800: `(mstatus & 0x1800) >> 11` gives 0..3, the mode. Writing it clears those two bits and ORs in the mode shifted left by 11. On a trap, MPIE = MIE, MIE = 0 and MPP = the current level. On `mret`, MIE = MPIE, MPIE = 1, the level = MPP, and MPP = the least privileged mode.

Why MIE goes off in the handler: a second interrupt arriving inside the handler would trap again and overwrite mepc and mcause, so the handler could never get back. With MIE = 0 the handler runs undisturbed; a handler that wants to allow nesting saves mepc and mcause first, then turns MIE on itself.

Why MPIE exists: the handler must run with interrupts off, but afterwards they must be as they were before the trap, on or off. MPIE ("previous MIE") is where trap entry keeps the old value: a one-entry stack. MPP does the same for the privilege level.

Why mret restores it, instead of the handler doing `csrsi mstatus, 8` (MIE = 1) and then jumping back: an interrupt could arrive between those two instructions, while still in the handler, and overwrite mepc. mret turns interrupts back on and jumps in one indivisible step, so there is no such gap.

For: turning interrupts on and off (`csrsi mstatus, 0x8` / `csrci mstatus, 0x8`), and choosing which mode `mret` enters: an OS sets MPP to user mode, then `mret`s into a user program.

Emulator: machine and user mode exist so far, so MPP holds 0b11 (machine) or 0b00 (user); writing 0b01 (supervisor) or 0b10 leaves it as it was (WARL). After `mret`, MPP = 0b00, the least privileged mode. mstatus starts as 0x1800 (MPP = machine). Supervisor fields (SIE, SPP, SUM, MXR, ...) arrive with supervisor mode.

Watch out: MIE only affects interrupts (the CLINT's timer, lesson 21); exceptions from instructions happen whatever MIE says.

Related: mret, mie, mtvec, privilege

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
Page faults (0xc, 0xd, 0xf) come with paging, and interrupts (bit 63 set) with the timer.

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
| 1 | SSIP | SSIE | supervisor software | supervisor mode (later) |
| 3 | MSIP | MSIE | machine software | the CLINT's msip register (another hart) |
| 5 | STIP | STIE | supervisor timer | supervisor mode (later) |
| 7 | MTIP | MTIE | machine timer | the CLINT, when mtime reaches mtimecmp |
| 9 | SEIP | SEIE | supervisor external | supervisor mode (later) |
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
The main switch applies only in machine mode: running in a lower mode, machine interrupts are always taken, whatever mstatus.MIE says, so a user program can't block the timer.

Taking an interrupt doesn't clear mip. The bit follows the device: the timer's stays 1 while mtime >= mtimecmp. The handler must clear the source, by writing a later mtimecmp or writing 0 to msip; otherwise the same interrupt is taken again right after mret.

For: choosing which interrupt sources matter, e.g. an OS enables the timer to switch between programs.

Emulator: this hart has the three machine interrupts so far (MACHINE_INTERRUPT_BITS, interrupts.odin): mie keeps only those three bits, the others read 0. mip shows what the devices drive: MTIP and MSIP from the CLINT (MEIP waits for the PLIC). It is worked out again whenever a device could have changed it, and software writes to it are ignored, since its bits are wires. The CSRs tab spells out both: "software=0 timer=1 external=0".

Watch out:
- A handler that doesn't clear the source is interrupted again as soon as it returns, forever.
- In machine mode a bit in mie does nothing while mstatus.MIE = 0, so lesson 21 sets both: `csrs mie, t0` (MTIE), then `csrsi mstatus, 8` (MIE).

Related: interrupt, interrupt-sources, mstatus, mcause, clint

## misa - Machine ISA

*CSR 0x301, machine, read / write*

Does: describes which instruction set the hart implements.

Fields:
- MXL (bits 63..62): register width: 1 = 32-bit, 2 = 64-bit.
- Extensions (bits 25..0): one bit per letter: bit 0 = A, bit 8 = I, bit 12 = M, and so on.

How it works: here misa = 0x8000000000101101: MXL = 2 (RV64), bit 0 (A), bit 8 (I), bit 12 (M) and bit 20 (U: user mode).

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

For: measuring how long code takes, and how many instructions it ran.

Emulator: one cycle per step, so mcycle and minstret read the same number until something traps or a program writes one of them. Both are fields of Csr_File (core/csr.odin). There is no mcounteren yet, so user mode can always read cycle and instret. A trap or interrupt taken into a handler is a step: it takes a cycle, as on real hardware, but retires no instruction, so only mcycle counts it. A write changes only that counter. It doesn't move the timer either: mtime follows its own step clock, which no program can write (see emulator-time).

Watch out:
- reading the counter is itself an instruction: two `csrr` of minstret in a row differ by 1 (lesson 11).
- a write takes effect after the writing instruction, so `csrw minstret, t0` makes the next read give exactly t0: the csrw itself isn't counted.

Related: csr-addresses, retire, emulator-time

Example:
```
csrr t5, minstret        # instructions so far
csrr t6, minstret        # one more
```
