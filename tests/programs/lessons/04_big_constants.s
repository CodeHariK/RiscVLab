# Lesson 04: Big constants with lui and addi
# Build a 32-bit value from two instructions, and see the carry trick when the low part looks negative.
# Expect: exit 120
#
# addi only holds 12 bits, so larger constants take two instructions:
#
#   lui  rd, upper     rd = upper << 12        (the top 20 of 32 bits)
#   addi rd, rd, lower rd = rd + lower         (the bottom 12 bits)
#
# addi's immediate is signed: a lower part of 0x800 or more counts as
# negative. To make up for that, the assembler adds 1 to the upper part.
# The "li" shorthand does all of this for you.

    .section .text
    .globl _start
_start:
    lui  t0, 0x12345        # t0 = 0x12345000
    addi t0, t0, 0x678      # t0 = 0x12345678
    lui  t1, 0x12346        # want 0x12345800: lower part 0x800 counts as -0x800...
    addi t1, t1, -0x800     # ...so start one higher: 0x12346000 - 0x800 = 0x12345800
    li   t2, 0x12345800     # the assembler writes the same two instructions for li
    sub  t3, t1, t2         # t3 = 0: they really are equal
    auipc t4, 0             # auipc: t4 = this instruction's own address (pc + 0)
    andi a0, t0, 0xff       # a0 = low byte of 0x12345678 = 0x78 = 120
    ebreak
