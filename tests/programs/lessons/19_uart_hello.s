# Lesson 19: Printing with the UART
# A program prints by storing bytes to a device, the UART at 0x10000000: wait until it is ready (LSR), store the byte (THR), repeat.
# Expect: exit 13
# Expect output: Hello, UART!
# Docs: uart, mmio, lbu, sb
#
# There is no "print" instruction. Devices sit at addresses of their own
# (here the UART, a serial port), and a program talks to them with the
# same loads and stores it uses for memory: memory-mapped I/O. The UART's
# registers are single bytes:
#
#   0x10000000  THR  store a byte here to send it
#   0x10000005  LSR  bit 5 (THRE) = 1 when it can take the next byte
#
# Real serial ports send slowly, so a program checks LSR before every
# byte. The emulator sends at once (THRE is always 1), but the loop is
# what real drivers (and xv6) do. Watch the Console tab fill up, and the
# Memory tab show the UART's registers when a store goes there.
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
