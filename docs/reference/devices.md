# Devices

The hardware around the CPU that programs talk to: how they reach it
(memory-mapped I/O) and each device the emulator has so far. Same
format as instructions.md. The devices copy QEMU's `virt` board, at the
same addresses (see memory-map), so programs written for QEMU (and
later xv6) use them unchanged.

## mmio - Memory-mapped I/O

*how a program talks to a device*

Does: a device's registers sit at addresses of their own, outside RAM. A program reads and writes them with ordinary loads and stores: there are no special I/O instructions in RISC-V.

How it works: the bus looks at every address. RAM addresses go to memory; an address in a device's range goes to that device, which decides what a load returns and what a store does:
- a store can make something happen: storing to the UART's THR sends a byte.
- a load can change the device: loading the UART's RBR takes the received byte out of it, so the next load gets the next one.
- some registers mean different things for loads and stores (offset 0 of the UART is RBR to a load, THR to a store).

Emulator: a device decides which access sizes it accepts (the UART only bytes); anything else raises a load or store access fault. Instructions can't be fetched from a device: that raises Instruction_Access_Fault. Undo asks the device to put back its own state, so stepping back over a store to THR takes the byte back off the Console instead of sending another.

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
