# Traps and privilege levels

A trap is the CPU stopping what it is doing and jumping to a handler.
Exceptions are caused by an instruction (a bad load, `ecall`); interrupts
come from outside (a timer, a device). This file starts with why traps
exist, then how they work, writing a handler, returning with mret,
system calls, the privilege levels that traps move between, and what
each cause means.

The debugger's Docs window shows the entry for a trap cause when the next
instruction will trap. Same format as instructions.md and csrs.md.

## why-traps - Why traps exist

*overview: read this first*

Does: explains what traps are for. In lesson 12 a trap looks like a function call, because one program, in machine mode, both makes the trap and handles it. Traps exist for the cases where that is not true.

How it works: a trap differs from a function call in three ways.
1. It can happen without the code planning it. A load hits a bad address, an instruction is invalid, a timer fires between two instructions. The interrupted code saved nothing and may be using every register, ra included. So the CPU can't put the return address or the reason in x0..x31 without destroying the program's values: it puts them in CSRs (mepc: where, mcause: why, mtval: detail).
2. It changes privilege. A user program must not `jal` into the kernel: it could jump into the middle of kernel code and run it with kernel power. A trap enters only through one door, the address in mtvec, which the kernel chose, and raises the privilege level on the way in. `mret` lowers it on the way out.
3. The door must be locked. If a user program could write mtvec, it could point traps at its own code and give itself kernel power. So mtvec, mstatus and the rest are privileged CSRs: only more privileged code can change them. That is why this state lives in CSRs, not in ordinary registers or memory.

The kinds of traps:
| Kind | Cause | Examples |
|---|---|---|
| Faults | an instruction can't complete (at that instruction) | illegal instruction, access fault, misaligned jump, page faults (later) |
| Deliberate traps | an instruction meant to trap | ecall (system call), ebreak (debugger) |
| Interrupts | something outside the program (between any two instructions) | timer, a device, another hart (coming with the timer) |
Faults and deliberate traps are exceptions: mcause bit 63 is 0. Interrupts set bit 63.

For: an OS like xv6 needs every kind.
- System calls: user programs can't reach the disk or screen; they ask the kernel with `ecall`. The trap is the only safe way in.
- Protection: a bad pointer or a garbage instruction faults into the kernel, which kills just that program instead of the whole machine going down.
- Sharing the CPU: a program stuck in `while(1);` never calls the kernel. Only the timer interrupt gets the CPU back, so the kernel can switch to another process.
- Devices: instead of asking "is the disk done yet?" in a loop, the kernel lets the disk interrupt it when it finishes.
- Virtual memory: a page fault tells the kernel a program touched memory that isn't mapped.

Watch out: the lessons run everything in machine mode, so they show the mechanism but not the protection. That part appears with user and supervisor mode, on the way to xv6.

Related: trap, handler, privilege, mtvec, mepc, mcause, ecall

## trap - What happens on a trap

*exceptions and interrupts*

Does: stops the current code, records why, and jumps to the handler in mtvec.

How it works: in short, the hardware stores the pc in a CSR (mepc), runs the handler's instructions, and `mret` puts the pc back. When an instruction raises an exception, or an interrupt is taken between two instructions, the hart:
1. mepc = where to come back: the instruction that trapped (an exception), or the one that hadn't run yet (an interrupt).
2. mcause = why: the cause code, with bit 63 set for an interrupt.
3. mtval = extra information: the bad address, or the instruction's bits (0 for interrupts).
4. mstatus: MPIE = MIE, MIE = 0 (interrupts off in the handler), MPP = the current privilege level.
5. Switches to machine mode and jumps to the handler: pc = mtvec. From here the CPU simply runs the handler's instructions, like any other code.

The instruction that trapped changes nothing else: a faulting load leaves its rd alone, a faulting jump doesn't move the pc. The handler sees the state exactly as it was just before the mistake.

The handler does its work and ends with `mret`, which undoes steps 4 and 5: pc = mepc, MIE = MPIE, the privilege level = MPP.

Lesson 21's timer interrupt, from start to finish:
```
main code                 hardware (trap entry)            handler
addi a0, a0, 1
beqz a1, count  <- the interrupt arrives before this runs
                mepc   = pc of the beqz  (come back here)
                mcause = 0x8000000000000007  (the timer)
                mtval  = 0
                MPIE = MIE, MIE = 0, MPP = old level
                pc = mtvec  ---------------------------->  li  a1, 1
                                                           sd  t0, 0(s1)
                                                           mret
                pc = mepc, MIE = MPIE  <-----------------
beqz a1, count  (runs now, as if nothing had happened)
```

Where to come back differs between the two kinds of trap. After an `ecall`, mepc points at the `ecall` itself: returning there would run it again, so the handler adds 4 first (lesson 13). After an interrupt, nothing needs fixing: the instruction at mepc hasn't run yet, and should.

For: everything an OS does beyond running one program: system calls (`ecall`), handling faults (paging loads a missing page), and timer interrupts that switch between programs.

Emulator: if mtvec's base address is 0 (mtvec = 0, or 1 for vectored), no handler has been set up, so the trap stops the machine (real hardware would jump to address 0). The step details show every CSR the trap writes.

Watch out: only the pc (in mepc), a few mstatus bits and the privilege level are saved; the 31 registers are not. A handler that uses t0 overwrites whatever the interrupted code had in t0, so it must save every register it touches and put them back before `mret` (see handler; mscratch is a spare CSR for parking one). xv6 saves all 31 to memory at the start of its handler. Lesson 21 gets away without it because its loop never uses t0 again.

Related: why-traps, exception, interrupt, mtvec, mepc, mcause, mtval, mstatus, mret, handler, trap-return

## handler - Writing a trap handler

*how a handler is laid out*

Does: the code mtvec points at, which runs on every trap. There is only one: every kind of trap arrives there, so it starts by asking why (mcause, plus mtval for the detail) and where from (mepc). Since a trap can interrupt code that didn't expect it, the handler must leave every register as it found it, except a result it hands back on purpose, such as a system call's answer in a0. After a fault it can kill the program, skip the faulting instruction (mepc + 4), or fix the cause and return to mepc unchanged so the instruction runs again.

How it works: a typical handler:
1. Frees a register to work with, often by swapping with mscratch.
2. Saves the registers it will use, so the interrupted code finds them unchanged.
3. Reads mcause to find out why it was called, and mtval if needed.
4. Does the work: a system call, a fault report, a timer tick.
5. For `ecall` (and faults it wants to skip), adds 4 to mepc.
6. Restores the registers and ends with `mret` (trap-return says why not a plain jump).

Lessons 12 to 14 have small handlers that skip steps 1, 2 and 6, since they own all the registers.

Watch out:
- The handler must be 4-byte aligned (`.balign 4`): mtvec's low bits are its mode.
- Forgetting to add 4 to mepc after `ecall` returns to the `ecall`, which traps again forever.
- A trap inside the handler overwrites mepc and mcause, so save them first if that can happen.

Related: why-traps, trap, trap-return, mtvec, mscratch, mepc, mret

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

## trap-return - Returning from a trap: mret, not jr

*how a handler goes back*

Does: a handler must undo everything the trap did, not only go back to the right address. `mret` does all of it in one instruction; a plain jump does not.

How it works: what the trap changed, and what each way back restores:
| | trap entry | jr mepc+4 | mret |
|---|---|---|---|
| pc | -> mtvec | restored | restored (= mepc) |
| mstatus.MIE (interrupts) | -> 0 | stays 0 | = MPIE (as before) |
| privilege level | -> machine | stays machine | = MPP (as before) |
So the handler first sets mepc to where it should return (for `ecall`, mepc + 4), then ends with `mret`.

For: a correct handler.
- Interrupts: the trap turned them off so the handler isn't interrupted halfway. With `jr` they would stay off after the first trap.
- Privilege: a trap from a user program raises the level to machine (or supervisor). Only `mret` (or `sret`) can bring it back down; `jr` would leave the user program running with full power.

Watch out: lesson 12 returns with `jr`. It works there only because everything runs in machine mode and nothing turned interrupts on. Lesson 13 does it properly: it turns MIE on, and you can watch the trap clear it and `mret` restore it.

Related: mret, trap, handler, mstatus, mepc

Example:
```
handler:
    csrr t1, mepc
    addi t1, t1, 0x4         # return after the ecall, not to it
    csrw mepc, t1
    mret                     # pc = mepc, MIE = MPIE, privilege = MPP
```

## system-call - System calls

*the ecall convention*

Does: a system call is a program asking the kernel to do something it may not do itself: write to the screen, read a file, start a process. The program makes the request with `ecall`; the kernel's trap handler does the work and returns with `mret` (or `sret`).

How it works: registers carry the request, by convention (the same in Linux and xv6):
1. The program puts the request number in a7, and the arguments in a0 to a5.
2. `ecall` traps: mcause = 0x8 (from user mode), mepc = the `ecall`.
3. The handler sees mcause 0x8, reads a7 to pick the request, and does it with the arguments.
4. It puts the result in a0, sets mepc to mepc + 4, and `mret`s.
5. The program continues after the `ecall`, with the answer in a0. To the program it looks like a function call into the kernel.

For: every interaction with the outside world in a protected OS goes through here. In xv6, user programs call C functions such as `write(fd, buf, n)`; each is a few lines of assembly that set a7 (16 for write) and run `ecall`.

Watch out: the handler must not change other registers the program uses: a real kernel saves all of them on entry and restores them before returning. Lesson 13 is a tiny version: request 1 in a7, argument 1 in a0, result 3 in a0.

Related: ecall, Ecall_From_U_Mode Ecall_From_S_Mode Ecall_From_M_Mode, trap-return, handler, abi

Example:
```
li   a0, 0x1             # argument
li   a7, 0x1             # which system call
ecall                    # into the kernel...
                         # ...back here, result in a0
```

## privilege - Privilege levels

*machine, supervisor, user*

Does: decides what the running code may do. Each level can use its own CSRs and those of the levels below it. Each level has a number, and that number is exactly what mstatus.MPP (bits 12..11) holds for it:
| Level | Number | MPP bits | mstatus with only MPP set | Who runs there |
|---|---|---|---|---|
| User (U) | 0 | 00 | 0x0000 | ordinary programs: no CSRs except a few counters; anything else needs an `ecall` to the kernel |
| Supervisor (S) | 1 | 01 | 0x0800 | the OS kernel: manages page tables and handles most traps of user programs |
| (reserved) | 2 | 10 | 0x1000 | nothing: MPP can't hold it |
| Machine (M) | 3 | 11 | 0x1800 | firmware; the hart starts here after reset. Everything is allowed |
The same numbers appear in a CSR's address: bits 9..8 are the lowest level that may use it (mstatus is 0x300: 11, machine only; cycle is 0xc00: 00, anyone). Supervisor mode's own field, mstatus.SPP (bit 8), is one bit, because `sret` can only go back to user (0) or supervisor (1).

How it works: traps go up (to machine mode, or to supervisor mode when delegated), and `mret` / `sret` come back down to the level saved in mstatus.MPP / SPP. That is the only way to change level. Two things hold a level, and they mean different things:
| | The current level | mstatus.MPP |
|---|---|---|
| Holds | the level the hart is running at right now | where the next `mret` goes: the level the last trap came from |
| Set by | trap entry (to machine) and `mret` (to MPP) | trap entry (to the current level) and `mret` (to the least privileged level) |
| Seen by | no CSR: the hardware keeps it to itself | machine-mode code, in mstatus |
| Like | the pc | ra: a saved place to return to |
In this emulator the current level is Cpu.privilege, and the debugger's CSRs tab shows it on its first line ("privilege"), next to mstatus.MPP.

How they move, starting from machine code that set MPP to supervisor and runs `mret`:
| Moment | Current level | MPP |
|---|---|---|
| before the `mret` | machine | supervisor (set by the program, as if a trap had come from there) |
| after the `mret` | supervisor (taken from MPP) | user (`mret` clears it to the least privileged level, see mret) |
| after an `ecall` in supervisor mode | machine (every trap goes up) | supervisor (the trap saved where it came from) |
| after the handler's `mret` | supervisor | user |
To enter user mode, machine code clears MPP and runs `mret`: `li t0, 0x1800`, `csrc mstatus, t0`, `mret` (lesson 24).

Why no CSR shows the current level: so a program can't simply check which level it really runs at. That keeps virtualization possible: a hypervisor can run a kernel one level lower than the kernel thinks, and catch (trap) whatever the kernel isn't allowed to do there. Code finds out what it may do only by trying and seeing whether it traps. Machine code never needs the current level anyway: inside a trap handler it is machine, and MPP says where the trap came from.

For: protection. A user program can't touch the kernel's memory or devices, or turn off interrupts; it must ask with `ecall`. xv6 runs its kernel in supervisor mode and its programs in user mode.

Emulator: all three levels exist. `mret` with MPP = 0b00 drops into user mode and with MPP = 0b01 into supervisor mode. Below machine mode the machine CSRs and `mret` raise Illegal_Instruction, `ecall` traps with cause 0x8 (from user) or 0x9 (from supervisor), and machine interrupts are always taken (mstatus.MIE only matters in machine mode). Supervisor mode has no CSRs of its own yet, and nothing is delegated to it, so every trap still goes to machine mode; the S CSRs, delegation and `sret` come next, on the way to xv6.

Related: mstatus, mret, ecall, csr-addresses

## interrupt - Interrupts

*a device asking for attention*

Does: lets a device (a timer, the UART, a disk) tell the CPU that something happened. The CPU stops the running program between two instructions, runs a handler for the device, then goes back exactly where it left off. The alternative is polling: the program asks the device again and again (lesson 19).

How it works: an interrupt is a trap, with the same steps as an exception (see trap):
1. mepc = the next instruction, the one that hadn't run yet.
2. mcause = the cause, with bit 63 set: 0x8000000000000007 is the machine timer, 0x800000000000000b an external device.
3. mstatus: MPIE = MIE, MIE = 0 (no interrupts inside the handler), MPP = the privilege level it came from.
4. pc = mtvec (in vectored mode: mtvec base + 4 * cause).
The handler deals with the device (reads the byte, sets the next timer) and ends with `mret`; the program never notices it was stopped.

| | Exception | Interrupt |
|---|---|---|
| Caused by | the instruction itself (ecall, a bad address, an invalid instruction) | something outside the program: a timer, a device |
| When | at that instruction, every time | between any two instructions, whenever it arrives |
| mcause bit 63 | 0 | 1 |
| mepc | the instruction that trapped | the next instruction, not yet run |
| Can be turned off | no | yes: mie, mstatus.MIE |

Fields: three switches decide whether an interrupt is taken now. All must be on:
- mip bit: the interrupt is pending (the device is asking). Devices set it.
- mie bit: this kind of interrupt is enabled. Software sets it.
- mstatus.MIE: interrupts are enabled at all. Trap entry clears it; mret restores it.
A pending interrupt that isn't enabled just waits in mip until it is. mie mip explains why there are two enable switches, and that taking an interrupt doesn't clear its mip bit.

For:
- the timer: an OS gets control back every few milliseconds, even from a program that never gives up the CPU, and switches to another program.
- devices: xv6 doesn't spin waiting for the UART. It puts the text in a buffer and runs other programs; each time the UART can take a byte, it interrupts and the handler sends the next one. A key press arrives the same way.

Emulator: machine-mode interrupts work: the CLINT drives MTIP (its timer) and MSIP (msip), the hart takes them at instruction boundaries, and Prev steps back over them. The Steps tab marks such a step "interrupted before it ran". External interrupts (MEIP) wait for the PLIC; the UART keeps IER but raises nothing yet. Lesson 21.

Watch out: an interrupt can arrive between any two instructions, so a handler must save and restore every register it uses (mscratch helps), and code that shares data with a handler must turn interrupts off around it, or use atomics.

Related: interrupt-sources, polling, exception, trap, mie mip, mcause, mstatus

## interrupt-sources - Where interrupts come from

*software, timer, external*

Does: each hart has three machine-mode interrupt lines, one bit each in mie and mip:
| Bit | Name | mcause | Comes from |
|---|---|---|---|
| 3 | MSI: software interrupt | 0x8000000000000003 | another hart, writing the CLINT's msip register (multi-core: "wake up", "flush your TLB") |
| 7 | MTI: timer interrupt | 0x8000000000000007 | the CLINT, when its mtime counter reaches mtimecmp |
| 11 | MEI: external interrupt | 0x800000000000000b | the PLIC, which collects many devices (UART, virtio disk) into this one line |

How it works:
- CLINT ("core-local interruptor", at 0x02000000 on QEMU's virt board): a clock (mtime) that keeps counting, and a compare register (mtimecmp) per hart. Software sets mtimecmp to "now + 10 ms"; when mtime passes it, MTI turns on until mtimecmp is set again.
- PLIC ("platform-level interrupt controller", at 0x0c000000): each device has an interrupt number (the UART is 10 on virt). The PLIC raises MEI when an enabled device asks; the handler then reads the PLIC's claim register to learn which device it was, deals with it, and writes the number back to say it is done.

For: the timer is what makes an OS preemptive; the PLIC is how one CPU line serves many devices.

Emulator: the CLINT is there (MSI and MTI work; see clint); the PLIC isn't yet, so MEI never turns on. Supervisor mode adds a second set (SSI, STI, SEI) that machine mode can delegate.

Related: interrupt, clint, mie mip, memory-map, uart

## Instruction_Address_Misaligned - Jump to a misaligned address (cause 0x0)

*exception: a fault*

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

*exception: a fault*

Does: raised when pc points somewhere with no memory to fetch the instruction from.

How it works: mepc = mtval = the bad pc.

For: catching jumps into nowhere, e.g. through a null function pointer.

Related: trap, mtval

## Illegal_Instruction - Not a valid instruction (cause 0x2)

*exception: a fault*

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

*exception: a deliberate trap*

Does: raised by `ebreak`.

How it works: mepc = the `ebreak`, mtval = 0.

For: debuggers replace an instruction with `ebreak` to stop there. In this emulator, with no handler set up, it ends the program: the run stops and a0 is the result.

Watch out: with a handler set, `ebreak` traps to it like any other trap instead of ending the program. That is why lessons 12 to 14 remove their handler (`csrw mtvec, zero`) before the final `ebreak`.

Related: ebreak, trap

## Load_Address_Misaligned Store_Address_Misaligned - Misaligned load or store (causes 0x4 and 0x6)

*exception: a fault*

Does: may be raised by a load or store whose address is not a multiple of its size (e.g. `lw` from an odd address).

Emulator: never raised: misaligned loads and stores just work, as on QEMU. Real CPUs may do either, or trap so software can do the access in pieces.

Related: lb lh lw ld, sb sh sw sd

## Load_Access_Fault Store_Access_Fault - Load or store outside memory (causes 0x5 and 0x7)

*exception: a fault*

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

*exception: a deliberate trap (system call)*

Does: raised by `ecall`. The cause says which level made the call: 0x8 user, 0x9 supervisor, 0xb machine.

How it works: mepc = the `ecall`, mtval = 0. The handler finds the request in registers (by convention a7 = which request, a0..a5 = arguments) and puts the answer in a0.

For: system calls: a user program asking the kernel (cause 0x8), or the kernel asking the firmware (0x9).

Watch out: add 4 to mepc before returning, or the `ecall` runs again (lessons 12 and 13).

Related: system-call, ecall, mret, handler, privilege
