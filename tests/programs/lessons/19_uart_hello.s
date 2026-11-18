# Lesson 19: Printing with the UART
# A program prints by storing bytes to a device, the UART at 0x10000000: wait until it is ready (LSR), store the byte (THR), repeat.
# Expect: exit 13
# Expect output: Hello, UART!
# Docs: uart, mmio, lbu, sb
#
# There is no "print" instruction. Devices sit at addresses of their own
# (here the UART, a serial port), and a program talks to them with the
# same loads and stores it uses for memory: memory-mapped I/O.
#
# The UART has 8 one-byte registers (see the uart entry in Docs). This
# lesson uses only two of them:
#
#   0x10000005  LSR  read  (lbu t1, 5(s0))  bit 5 (THRE) = 1 when the UART
#                                           can take the next byte
#   0x10000000  THR  write (sb t0, 0(s0))   send this byte
#
# Why LSR first: a real serial port sends slowly. Each byte goes out on
# the wire one bit at a time (a start bit, 8 data bits, a stop bit), so
# at 115200 baud a byte takes about 87 microseconds: ~100,000
# instructions of a fast CPU. A byte stored before the last one has moved
# on is lost, so the program waits.
#
# How it waits: busy-waiting (polling). There is no timer here and the
# program never measures time. The UART keeps time with its own clock: a
# store to THR makes THRE 0 (busy), and the UART sets it back to 1 once
# the byte has moved on. The wait: loop just keeps asking ("is THRE
# 1 yet?") until the answer is yes, perhaps 100,000 times. Receiving
# works the same way with LSR bit 0 (DR: a byte has arrived in RBR).
#
# The cost: while it spins, the CPU does nothing else. Real systems
# avoid most of it:
#   - FIFOs: the 16550 can queue 16 bytes (FCR turns them on, lesson 20),
#     so a program waits only once the queue is full.
#   - Interrupts: xv6 puts the text in a buffer and runs other programs;
#     the UART interrupts (through the PLIC) when it can take more, and
#     the handler sends the next byte. Keys arrive the same way.
# Polling is still what you use when nothing else is set up: early boot,
# a kernel panic message, or a tiny program like this one.
#
# In the emulator there is no wire, so a stored byte appears at once and
# THRE is always 1: the beqz after wait: never jumps back. The loop is
# kept because it is what real code must do (and what xv6 does).
#
# Why THR works without any setup: the emulator's UART (like QEMU's)
# starts ready to send. Real drivers set it up first (lesson 20).
# Not used here: RBR (receiving), IER, ISR / FCR, LCR, MCR, MSR, SCR.
#
# Watch the Console tab fill up a character per sb, the Devices tab
# light LSR, then THR, and the Memory tab jump to the UART's registers.
# a0 = the number of bytes sent: "Hello, UART!" and a newline = 13.

    .section .text
    .globl _start
_start:
    li    s0, 0x10000000        # the UART's address
    la    s1, message           # the text to send
    li    a0, 0                 # bytes sent so far
next:
    lbu   t0, 0(s1)             # the next character
    beqz  t0, done              # a 0 byte ends the text
wait:
    lbu   t1, 5(s0)             # LSR: line status
    andi  t1, t1, 0x20          # bit 5, THRE: ready for a byte?
    beqz  t1, wait              # not yet: ask again
    sb    t0, 0(s0)             # THR: send the character
    addi  s1, s1, 1             # move to the next character
    addi  a0, a0, 1             # count it
    j     next
done:
    ebreak                      # stop; the exit code is a0 (13)

    .section .data
message:
    .asciz "Hello, UART!\n"     # .asciz adds the 0 byte at the end
