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

Emulator: on RV64 every CSR is 64 bits wide (on RV32 they are 32 bits, and the 64-bit counters are read in two halves, e.g. cycle and cycleh). Here mhartid, misa and the ID CSRs are constants in the code, the counters all read the step count, and the rest are fields of the Csr_File struct in core/csr.odin.

Related: csr-addresses, csrrw, csrrs, trap

## csr-addresses - CSR numbers and who may use them

*how CSRs are numbered*

Does: every CSR has a 12-bit number (0x000 to 0xfff); the assembler accepts names instead.

How it works: the top four bits of the number say who may use the CSR.
- Bits 11..10 = 0b11 means read-only: writing it raises Illegal_Instruction.
- Bits 9..8 give the lowest privilege level allowed: 0b00 user, 0b01 supervisor, 0b11 machine.

For example, mhartid is 0xf14 = 0b1111_0001_0100: bits 11..10 are 0b11 (read-only) and bits 9..8 are 0b11 (machine only). mstatus is 0x300: writable, machine only. cycle is 0xc00: read-only, usable from user mode.

Watch out: using a CSR that does not exist, writing a read-only one, or using one from too low a privilege level all raise Illegal_Instruction.

Related: csrrw, csrrs, csrrc, Illegal_Instruction

## mstatus - Machine status

*CSR 0x300, machine, read / write*

Does: the hart's global state: whether interrupts are on, and what to restore when a trap handler returns.

Fields:
- MIE (bit 3): machine interrupts enabled. Trap entry clears it, so a handler is not interrupted.
- MPIE (bit 7): MIE as it was before the last trap. `mret` copies it back into MIE.
- MPP (bits 12..11): the privilege level before the last trap: 0b00 user, 0b01 supervisor, 0b11 machine. `mret` returns to it.

How it works: on a trap, MPIE = MIE, MIE = 0 and MPP = the current level. On `mret`, MIE = MPIE, MPIE = 1, the level = MPP, and MPP = the least privileged mode.

For: turning interrupts on and off (`csrsi mstatus, 0x8` / `csrci mstatus, 0x8`), and choosing which mode `mret` enters: an OS sets MPP to user mode, then `mret`s into a user program.

Emulator: only machine mode exists so far, so MPP always reads 0b11 (machine): writing anything else is ignored (WARL). mstatus starts as 0x1800 for that reason. Supervisor fields (SIE, SPP, SUM, MXR, ...) arrive with supervisor mode.

Watch out: MIE only matters once there are interrupts (the timer comes later); traps from instructions happen whatever MIE says.

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

For: the first thing a program that wants to handle traps does: `la` the handler, `csrw mtvec`.

Emulator: mtvec = 0 means "no handler": a trap then stops the machine instead of jumping to address 0. That is how the test programs end with `ebreak`. MODE 2 and 3 are reserved, so bit 1 always reads 0.

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

Does: per-interrupt switches. In mie, a 1 bit allows that interrupt; in mip, a 1 bit means that interrupt is waiting.

Fields: the same bit positions in both.
- MSI (bit 3): software interrupt, sent by another hart.
- MTI (bit 7): timer interrupt.
- MEI (bit 11): external interrupt, from a device through the interrupt controller.

How it works: an interrupt is taken when its mip bit and its mie bit are both 1 and mstatus.MIE is 1.

For: choosing which interrupt sources matter, e.g. an OS enables the timer to switch between programs.

Emulator: there are no interrupt sources yet (the timer comes later), so mip stays 0 and writes to it are ignored. mie keeps only the three bits above.

Related: mstatus, mcause

## misa - Machine ISA

*CSR 0x301, machine, read / write*

Does: describes which instruction set the hart implements.

Fields:
- MXL (bits 63..62): register width: 1 = 32-bit, 2 = 64-bit.
- Extensions (bits 25..0): one bit per letter: bit 0 = A, bit 8 = I, bit 12 = M, and so on.

How it works: here misa = 0x8000000000001101: MXL = 2 (RV64), bit 0 (A), bit 8 (I) and bit 12 (M).

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

Does:
- mcycle / cycle: clock cycles since reset.
- minstret / instret: instructions finished ("retired") since reset.

The m versions can be written; cycle and instret are read-only copies that user programs may read.

For: measuring how long code takes.

Emulator: one instruction per cycle, so all four read the same number, the step count shown in the toolbar.

Watch out: reading the counter is itself an instruction: two `csrr` of minstret in a row differ by 1 (lesson 11).

Related: csr-addresses

Example:
```
csrr t5, minstret        # instructions so far
csrr t6, minstret        # one more
```
