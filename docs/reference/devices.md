# Devices

The hardware around the CPU that programs talk to: how they reach it
(memory-mapped I/O), each device the emulator has so far, and the ones
coming next. Same format as instructions.md. The devices copy QEMU's
`virt` board, at the same addresses (see memory-map), so programs
written for QEMU (and later xv6) use them unchanged.

## mmio - Memory-mapped I/O

*how a program talks to a device*

Does: a device's registers sit at addresses of their own, outside RAM. A program reads and writes them with ordinary loads and stores: there are no special I/O instructions in RISC-V.

How it works: the bus looks at every address. RAM addresses go to memory; an address in a device's range goes to that device, which decides what a load returns and what a store does:
```
            load / store at an address
  hart  ------------------------------->  bus
                                           |
          0x80000000 - 0x87ffffff  --------+-->  RAM (128 MiB)
          0x02000000 - 0x0200ffff  --------+-->  CLINT
          0x10000000 - 0x100000ff  --------+-->  UART
          anything else            --------+-->  access fault
```
- a store can make something happen: storing to the UART's THR sends a byte.
- a load can change the device: loading the UART's RBR takes the received byte out of it, so the next load gets the next one.
- some registers mean different things for loads and stores (offset 0 of the UART is RBR to a load, THR to a store).

Emulator: a device decides which access sizes it accepts (the UART only bytes); anything else raises a load or store access fault. Instructions can't be fetched from a device: that raises Instruction_Access_Fault. Atomics (lr, sc, the AMOs) work only on RAM: on a device they raise an access fault. Undo asks the device to put back its own state, so stepping back over a store to THR takes the byte back off the Console instead of sending another.

Watch out: device registers are not memory. Reading back what you wrote may give something else, and reading the same register twice may give two different values. Compilers must not cache or reorder these accesses: C code uses `volatile` for them.

Related: uart, memory-map, lbu, sb

## polling - Polling (busy-waiting)

*asking a device again and again*

Does: the program waits for a device by reading its status register in a loop until a bit says it is ready, then acts. No timer is involved: the device keeps time with its own clock and flips the bit when it is ready; the program only keeps asking.

How it works: lesson 19 waits for the UART like this:
```
wait:
lbu   t1, 5(s0)          # read LSR
andi  t1, t1, 0x20       # THRE: ready for the next byte?
beqz  t1, wait           # not yet: ask again
sb    t0, 0(s0)          # ready: send the byte
```
On real hardware a byte takes about 87 microseconds at 115200 baud, so this loop may run some 100,000 times per byte. Receiving is the same with LSR bit 0 (DR).

For: the simplest way to use a device, and the only one before interrupts are set up: early boot, a kernel's panic message, tiny programs.

Emulator: the UART sends at once, so THRE is always 1 and the loop never repeats. The loop is still needed on real hardware.

Watch out: while it polls, the CPU does nothing else. Real systems poll less with FIFOs (the 16550 queues 16 bytes, turned on through FCR, lesson 20) and not at all with interrupts: the device tells the CPU when it is ready (see interrupt).

Related: interrupt, uart, mmio

## uart - The UART (serial port)

*device at 0x10000000, an NS16550A*

Does: sends and receives bytes, one at a time: the console of a computer without a screen. Everything a program prints goes through it; later, xv6 reads the keyboard through it too.

How it works: 8 one-byte registers, at offsets 0 to 7 from 0x10000000:
| Offset | Load | Store |
|---|---|---|
| 0 | RBR: the next received byte | THR: send a byte |
| 1 | IER: interrupt enable | IER |
| 2 | ISR: interrupt status | FCR: FIFO control |
| 3 | LCR: line control | LCR |
| 4 | MCR: modem control | MCR |
| 5 | LSR: line status | (ignored) |
| 6 | MSR: modem status | (ignored) |
| 7 | SCR: scratch, free to use | SCR |
To print a byte: wait until LSR bit 5 (THRE, "transmit holding register empty") is 1, then store the byte to THR. To read one: wait until LSR bit 0 (DR, "data ready") is 1, then load RBR.

Fields:
- LSR bit 0, DR: a received byte is waiting in RBR.
- LSR bit 5, THRE: THR can take the next byte.
- LSR bit 6, TEMT: everything has been sent.
- LCR bit 7, DLAB: offsets 0 and 1 become the divisor latch (DLL, DLM), which sets the baud rate. Drivers set it first, then clear DLAB.

Emulator: sending is instant, so THRE is always 1 and the byte appears at once: in the Console tab of the debugger, and on stdout with rvemu. The baud rate changes nothing (there is no wire). Only byte loads and stores are allowed, as on the real chip. Interrupts (IER) are kept but never raised until the PLIC arrives. Received bytes will come from the keyboard when xv6 needs them.

Watch out: a real UART sends slowly (a byte takes about 87 microseconds at 115200 baud), far slower than the CPU. A program that stores to THR without checking THRE loses bytes on real hardware, even though it works here.

Related: mmio, polling, interrupt, memory-map

Example:
```
li    s0, 0x10000000     # the UART
wait:
lbu   t1, 5(s0)          # LSR
andi  t1, t1, 0x20       # THRE?
beqz  t1, wait           # not ready: ask again
li    t0, 'A'
sb    t0, 0(s0)          # THR: send 'A'
```

## clint - The CLINT (timer and software interrupts)

*device at 0x02000000, the core-local interruptor*

Does: gives every hart a clock that keeps counting, an alarm on it ("interrupt me when the clock reaches X"), and a way for one hart to interrupt another. It is the timer of a RISC-V board.

How it works: three kinds of memory-mapped registers, at 0x02000000 + offset:
| Offset | Register | Size | What it does |
|---|---|---|---|
| 0x0000 | msip (one per hart) | 4 bytes | write 1: send that hart a software interrupt (MSI, mip bit 3) |
| 0x4000 | mtimecmp (one per hart) | 8 bytes | the alarm: while mtime >= mtimecmp, a timer interrupt is pending (MTI, mip bit 7) |
| 0xbff8 | mtime | 8 bytes | the clock: counts up at a fixed rate (10 MHz on QEMU), shared by all harts |
A timer interrupt, step by step:
1. The kernel reads mtime and writes mtimecmp = mtime + 1000000 (0.1 s at 10 MHz).
2. It goes on running. The CLINT compares the two on every tick.
3. When mtime reaches mtimecmp, the CLINT sets mip.MTIP. If mie.MTIE and mstatus.MIE are on, the hart traps between two instructions, with mcause 0x8000000000000007.
4. The handler sets the next alarm (mtimecmp += 1000000), which clears MTIP, and returns with `mret`.
MTIP stays 1 for as long as mtime >= mtimecmp: the only way to stop the interrupt is to move the alarm on (or turn MTIE off).
The path from the device to the trap:
```
  CLINT (device)                   hart (CSRs)
  mtime >= mtimecmp  ---wire--->   mip.MTIP      the device asks       \
                                   mie.MTIE      software allows it     > all on?
                                   mstatus.MIE   interrupts are on     /
                                                      |
                                                      | yes: at the next instruction boundary
                                                      v
                                   trap: mepc   = the next instruction (not run yet)
                                         mcause = 0x8000000000000007
                                         pc     = mtvec (vectored: + 4 * 7)
```

For:
- preemptive multitasking: without a timer, a program that never makes a system call keeps the CPU for ever. The timer interrupt gives the kernel control back every few milliseconds, so it can switch to another program. xv6's scheduler and its sleep() depend on it.
- msip: one hart wakes another (multi-core: "wake up", "flush your TLB").

Emulator: msip, mtimecmp and mtime, for one hart; 4- and 8-byte accesses (the 8-byte registers also as two 4-byte halves). mtime counts steps rather than wall-clock time (see emulator-time): it is the step clock plus an offset that writing mtime changes, so a timer interrupt arrives at exactly the same instruction on every run, and Prev steps back over it. mtimecmp starts as all ones (no alarm). The Devices tab shows the three registers and counts down "timer interrupt pending in N steps". Lesson 21.

Watch out: xv6 today doesn't use mtimecmp from its kernel. It uses the Sstc extension: the supervisor-mode kernel sets its own alarm in the stimecmp CSR, and reads the clock with the time CSR (rdtime), which mirrors mtime. Older xv6 set mtimecmp from a small machine-mode handler instead. Either way the clock is the CLINT's mtime.

Related: timebase, emulator-time, interrupt, interrupt-sources, mie mip, mmio, memory-map

## timebase - Where the clock's ticks come from

*a quartz crystal on the board*

Does: drives mtime. The board has a quartz crystal oscillator that ticks at a steady, known rate: the timebase. Common rates are 32.768 kHz (the classic watch crystal), 1 MHz or 10 MHz; QEMU's virt board says 10 MHz.

How it works: inside the CLINT:
1. mtime is a 64-bit counter that adds 1 on every timebase tick. At 10 MHz it would take about 58,000 years to wrap round.
2. A comparator checks mtime >= mtimecmp all the time. Its output is a wire into the hart, and that wire is mip.MTIP: nothing is sent, the bit simply stays 1 while the condition holds.
3. The hart checks for pending interrupts at every instruction boundary. Once MTIP is 1 and the interrupt is enabled, the next boundary becomes a trap.
So the interrupt fires at the time set in mtimecmp, at the first instruction boundary after that tick: a few nanoseconds late, nothing next to a 100 ns tick.

For: keeping time that doesn't depend on the CPU. The timebase is kept separate from the CPU's own clock on purpose: the CPU slows down to save power or speeds up under load, but time must not. Software learns the rate from the device tree (timebase-frequency); xv6 simply assumes "1,000,000 ticks is about 0.1 s on QEMU".

Related: clint, emulator-time

## emulator-time - Time in the emulator: steps or the host clock

*what mtime counts here*

Does: decides what one tick of mtime means in the emulator. A program only ever sees time through mtime (and the time CSR), so it can't tell whether a tick took 100 ns of real time or one instruction. That leaves the emulator a choice.

How it works: two clocks, both feeding the same mtime, so the CLINT itself doesn't care:
- Step clock (the default, and the debugger's): mtime moves on a fixed amount per instruction. Deterministic: an interrupt lands on the same instruction every run, and Prev can step back over it. A ratio (ticks per instruction) can make it roughly match real seconds at the emulator's speed while staying deterministic.
- Host clock (for running xv6 interactively from rvemu): mtime follows the Mac's real time, so `sleep 10` takes 10 real seconds. Runs are no longer identical, but the command line needs no undo.
QEMU has the same idea: its -icount mode ties time to instructions, for runs that can be replayed exactly.

What the step clock changes, compared with real time:
| Situation | With one tick per instruction |
|---|---|
| Scheduling, preemption | works the same: a switch every 1,000,000 instructions instead of every 0.1 s |
| sleep 10 in xv6's shell | over as soon as enough instructions have run: at ~240 MIPS, much faster than real time |
| Debugging | interrupts on the same instruction every run; Prev undoes them |
| Idle (wfi, wait for interrupt) | no instructions run, so mtime would never reach the alarm: wfi must jump mtime forward to mtimecmp (and so wastes no time spinning) |
| Waiting for a key | the hard case: with only the UART left to wait for, the emulator must wait for real input from you, not jump ahead |

Emulator: the step clock, at one tick per step: an instruction, or a trap or interrupt taken into a handler. mtime = the step clock + an offset that writing mtime changes. The step clock is not mcycle itself: they count the same steps, but a program can write mcycle, and on real hardware that doesn't move mtime. It is worked out as mcycle + an offset, and writing mcycle changes the offset by just enough that the step clock carries on as if nothing happened. wfi is a nop for now; the jump forward to the next alarm, and the host clock for xv6's shell in rvemu, come later.

Watch out: with the step clock, "seconds" in a program are only as real as the ratio says. Timing measured inside the emulator (how long a loop takes) tells you about instructions, not about real hardware.

Related: clint, timebase, interrupt
