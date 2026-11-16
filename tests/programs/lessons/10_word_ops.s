# Lesson 10: 32-bit word operations
# addw / addiw compute on the low 32 bits and sign-extend the result, like C's int on a 64-bit machine.
# Expect: exit 3
# Docs: addiw, sign-extension
#
# RV64 adds "word" versions of the arithmetic instructions (the W suffix).
# They use only the low 32 bits of their inputs, and the 32-bit result is
# sign-extended back to 64 bits: bit 31 is copied into bits 63..32.

    .section .text
    .globl _start
_start:
    li    t0, 0x7fffffff    # the largest 32-bit signed number
    addi  t1, t0, 1         # 64-bit add: 0x0000000080000000, just a bigger positive number
    addiw t2, t0, 1         # 32-bit add: wraps to 0x80000000, sign-extended to 0xffffffff80000000 (negative)
    li    t3, 0x100000005   # a value wider than 32 bits
    addw  t4, t3, zero      # addw keeps only the low 32 bits: t4 = 5
    slt   a0, zero, t1      # a0 = 1 if t1 > 0
    slt   t5, t2, zero      # t5 = 1 if t2 < 0
    add   a0, a0, t5
    addi  t6, t4, -5
    seqz  t6, t6            # t6 = 1 if t4 == 5 (seqz = sltiu t6, t6, 1)
    add   a0, a0, t6        # a0 = 3 when all three hold
    ebreak
