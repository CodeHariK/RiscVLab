# Traps and privilege levels

A trap is the CPU stopping what it is doing and jumping to a handler.
Exceptions are caused by an instruction (a bad load, `ecall`); interrupts
come from outside (a timer, a device). This file explains how traps work,
what each cause means, and the privilege levels that traps move between.

The debugger's Docs window shows the entry for a trap cause when the next
instruction will trap. Same format as instructions.md and csrs.md.

## trap - What happens on a trap

*exceptions and interrupts*

Does: stops the current code, records why, and jumps to the handler in mtvec.

How it works: when an instruction raises an exception, instead of finishing it the hart:
1. mepc = the address of the instruction that trapped.
2. mcause = the cause code (bit 63 set for an interrupt).
3. mtval = extra information: the bad address, or the instruction's bits.
4. mstatus: MPIE = MIE, MIE = 0 (interrupts off in the handler), MPP = the current privilege level.
5. Switches to machine mode and jumps to the handler at mtvec.

The handler does its work and ends with `mret`, which undoes steps 4 and 5 and jumps back to mepc.

For: everything an OS does beyond running one program: system calls (`ecall`), handling faults (paging loads a missing page), and timer interrupts that switch between programs.

Emulator: if mtvec is 0, no handler has been set up, so the trap stops the machine (real hardware would jump to address 0). The step details show every CSR the trap writes.

Related: mtvec, mepc, mcause, mtval, mstatus, mret, handler

## handler - Writing a trap handler

*how a handler is laid out*

Does: the code mtvec points at, which runs on every trap.

How it works: a typical handler:
1. Frees a register to work with, often by swapping with mscratch.
2. Saves the registers it will use, so the interrupted code finds them unchanged.
3. Reads mcause to find out why it was called, and mtval if needed.
4. Does the work: a system call, a fault report, a timer tick.
5. For `ecall` (and faults it wants to skip), adds 4 to mepc.
6. Restores the registers and ends with `mret`.

Lessons 12 to 14 have small handlers that skip steps 1, 2 and 6, since they own all the registers.

Watch out:
- The handler must be 4-byte aligned (`.balign 4`): mtvec's low bits are its mode.
- Forgetting to add 4 to mepc after `ecall` returns to the `ecall`, which traps again forever.
- A trap inside the handler overwrites mepc and mcause, so save them first if that can happen.

Related: trap, mtvec, mscratch, mepc, mret

Example:
```
    .balign 4
handler:
    csrr t5, mcause          # why are we here?
    csrr t6, mepc
    addi t6, t6, 0x4         # skip the instruction that trapped
    csrw mepc, t6
    mret
```

## privilege - Privilege levels

*machine, supervisor, user*

Does: decides what the running code may do. Each level can use its own CSRs and those of the levels below it.
- Machine (M, 3): everything. Firmware runs here; the hart starts here after reset.
- Supervisor (S, 1): the OS kernel. Manages page tables and handles most traps of user programs.
- User (U, 0): ordinary programs. No CSRs except a few counters; anything else needs an `ecall` to the kernel.

How it works: traps go up (to machine mode, or to supervisor mode when delegated), and `mret` / `sret` come back down to the level saved in mstatus.MPP / SPP. That is the only way to change level.

For: protection. A user program can't touch the kernel's memory or devices, or turn off interrupts; it must ask with `ecall`. xv6 runs its kernel in supervisor mode and its programs in user mode.

Emulator: only machine mode exists so far. Supervisor and user mode come next on the way to xv6.

Related: mstatus, mret, ecall, csr-addresses

## Instruction_Address_Misaligned - Jump to a misaligned address (cause 0x0)

*exception*

Does: raised by a jump or taken branch whose target is not a multiple of 4.

How it works: mepc = the jump or branch itself (it did not happen), mtval = the bad target address.

For: catching corrupt return addresses and function pointers. With the C extension (2-byte instructions) only odd addresses fault; this emulator has no C extension.

Related: jal, jalr, mtval, trap

Example:
```
la   t3, target
addi t3, t3, 0x2         # target + 2 is not 4-byte aligned
jr   t3                  # traps (lesson 14)
```

## Instruction_Access_Fault - Fetch from outside memory (cause 0x1)

*exception*

Does: raised when pc points somewhere with no memory to fetch the instruction from.

How it works: mepc = mtval = the bad pc.

For: catching jumps into nowhere, e.g. through a null function pointer.

Related: trap, mtval

## Illegal_Instruction - Not a valid instruction (cause 0x2)

*exception*

Does: raised when the 32 bits at pc are not an instruction this CPU knows, or when a CSR instruction is not allowed.

How it works: mtval = the instruction's bits. The CSR cases:
- the CSR does not exist;
- writing a read-only CSR (numbers starting 0xc.. or 0xf..);
- using a CSR from too low a privilege level.

For: catching corrupt code, and emulating missing instructions in software: the handler reads mtval, does the work, and skips the instruction.

Related: mtval, csr-addresses, trap

Example:
```
.word 0xffffffff         # not a valid instruction: traps (lesson 14)
```

## Breakpoint - ebreak (cause 0x3)

*exception*

Does: raised by `ebreak`.

How it works: mepc = the `ebreak`, mtval = 0.

For: debuggers replace an instruction with `ebreak` to stop there. In this emulator, with no handler set up, it ends the program: the run stops and a0 is the result.

Related: ebreak, trap

## Load_Address_Misaligned Store_Address_Misaligned - Misaligned load or store (causes 0x4 and 0x6)

*exception*

Does: may be raised by a load or store whose address is not a multiple of its size (e.g. `lw` from an odd address).

Emulator: never raised: misaligned loads and stores just work, as on QEMU. Real CPUs may do either, or trap so software can do the access in pieces.

Related: lb lh lw ld, sb sh sw sd

## Load_Access_Fault Store_Access_Fault - Load or store outside memory (causes 0x5 and 0x7)

*exception*

Does: raised by a load (0x5) or store (0x7) to an address where there is no memory or device.

How it works: mepc = the load or store, mtval = the bad address. The destination register (for a load) or the memory (for a store) is left unchanged.

For: catching null and wild pointers. With paging, a missing page gives a page fault (0xd, 0xf) instead.

Related: lb lh lw ld, sb sh sw sd, mtval

Example:
```
li t1, 0x1000
ld t2, 0(t1)             # nothing at 0x1000: traps (lesson 14)
```

## Ecall_From_U_Mode Ecall_From_S_Mode Ecall_From_M_Mode - ecall (causes 0x8, 0x9, 0xb)

*exception*

Does: raised by `ecall`. The cause says which level made the call: 0x8 user, 0x9 supervisor, 0xb machine.

How it works: mepc = the `ecall`, mtval = 0. The handler finds the request in registers (by convention a7 = which request, a0..a5 = arguments) and puts the answer in a0.

For: system calls: a user program asking the kernel (cause 0x8), or the kernel asking the firmware (0x9).

Watch out: add 4 to mepc before returning, or the `ecall` runs again (lessons 12 and 13).

Related: ecall, mret, handler, privilege
