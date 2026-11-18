# Lesson 20: Setting up the UART
# Before printing, a driver sets the UART up, as xv6's uartinit does: interrupts off, the baud rate through the divisor latch (DLAB), 8-bit bytes, FIFOs on.
# Expect: exit 3
# Expect output: UART ready
# Docs: uart, mmio, lbu, sb
#
# Registers this lesson uses (one byte each, at 0x10000000 + offset), in
# the order it uses them:
#
#   +1  IER  write 0x00  no interrupts: nothing to handle them yet (xv6
#                        turns them on once the PLIC can deliver them)
#   +3  LCR  write 0x80  DLAB = 1: offsets 0 and 1 stop being THR / IER
#                        and become the divisor latch
#   +0  DLL  write 0x03  divisor, low byte: 1843200 / (16 * 3) = 38400 baud
#   +1  DLM  write 0x00  divisor, high byte
#   +0  DLL  read        (lbu) still the divisor while DLAB = 1: a0 = 3
#   +3  LCR  write 0x03  8 data bits, no parity, 1 stop bit, DLAB = 0:
#                        offset 0 is THR again
#   +2  FCR  write 0x07  FIFOs on, and empty them (receive and send)
#   +5  LSR  read        bit 5 (THRE) before each byte, as in lesson 19
#   +0  THR  write       the bytes of "UART ready"
#
# Why DLAB matters: the store of 3 to offset 0 goes to the divisor, not
# the screen. Without DLAB it would send a byte 0x03 to the console. And
# if a driver forgot to clear DLAB, everything it "printed" would go into
# the divisor and nothing would appear. The emulator has no wire, so the
# baud rate itself changes nothing here; the order of the stores does.
#
# Not used: RBR (nothing to receive yet), ISR (interrupt status), MCR,
# MSR, SCR.
#
# Watch the Devices tab: after LCR = 0x80, the RBR / THR / IER rows turn
# into DLL and DLM; after LCR = 0x03 they come back, with the divisor
# shown in the LCR line.

    .section .text
    .globl _start
_start:
    li    s0, 0x10000000        # the UART's address

    # 1. No interrupts.
    sb    zero, 1(s0)           # IER = 0

    # 2. The baud rate, through the divisor latch.
    li    t0, 0x80
    sb    t0, 3(s0)             # LCR: DLAB = 1
    li    t0, 3
    sb    t0, 0(s0)             # DLL = 3 (not sent: DLAB is on)
    sb    zero, 1(s0)           # DLM = 0
    lbu   a0, 0(s0)             # read DLL back: 3

    # 3. 8-bit bytes; DLAB off, so offset 0 is THR again.
    li    t0, 0x03
    sb    t0, 3(s0)             # LCR = 8 data bits, DLAB = 0

    # 4. FIFOs on, both emptied.
    li    t0, 0x07
    sb    t0, 2(s0)             # FCR

    # 5. Print, as in lesson 19.
    la    s1, message
next:
    lbu   t0, 0(s1)             # the next character
    beqz  t0, done              # a 0 byte ends the text
wait:
    lbu   t1, 5(s0)             # LSR
    andi  t1, t1, 0x20          # THRE: ready for a byte?
    beqz  t1, wait
    sb    t0, 0(s0)             # THR: send it
    addi  s1, s1, 1
    j     next
done:
    ebreak                      # exit code a0 = the divisor read back (3)

    .section .data
message:
    .asciz "UART ready\n"
