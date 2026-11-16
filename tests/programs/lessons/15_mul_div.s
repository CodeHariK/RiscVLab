# Lesson 15: Multiply and divide
# The M extension: mul and its high half (mulh), division that rounds toward zero, and the defined results for divide by zero and overflow.
# Expect: exit 52
# Docs: mul, mulh, div, two's-complement
#
# A 64 x 64-bit product has up to 128 bits: mul gives the low 64, mulh /
# mulhu the high 64 (the part that didn't fit). Division rounds toward
# zero (-7 / 2 = -3), and never traps: divide by zero and -2^63 / -1 have
# defined results. Each result below is checked: a0 = 42 (6 * 7) + 1 for
# each of the 10 checks = 52. Compare the step details with the comments.

    .section .text
    .globl _start
_start:
    # Multiply: the low half
    li    t0, 6
    li    t1, 7
    mul   a0, t0, t1        # a0 = 42 (0x2a)

    # Too big for 64 bits: 2^40 * 2^40 = 2^80
    li    t2, 1
    slli  t2, t2, 40        # t2 = 2^40
    mul   t3, t2, t2        # low half: 0, the product wrapped away
    seqz  t6, t3            # check 1: low half is 0
    add   a0, a0, t6
    mulhu t4, t2, t2        # high half: 2^80 >> 64 = 2^16 = 0x10000
    li    t6, 0x10000
    sub   t6, t4, t6
    seqz  t6, t6            # check 2: high half is 0x10000
    add   a0, a0, t6

    # Signed vs unsigned high half, both operands 0xffffffffffffffff
    li    t5, -1
    mulh  s2, t5, t5        # -1 * -1 = 1: high half 0
    seqz  t6, s2            # check 3
    add   a0, a0, t6
    mulhu s3, t5, t5        # (2^64 - 1)^2: high half 0xfffffffffffffffe
    addi  t6, s3, 2         # -2 + 2 = 0
    seqz  t6, t6            # check 4
    add   a0, a0, t6

    # Division rounds toward zero
    li    t0, -7
    li    t1, 2
    div   s4, t0, t1        # -7 / 2 = -3 (not -4)
    addi  t6, s4, 3
    seqz  t6, t6            # check 5
    add   a0, a0, t6
    rem   s5, t0, t1        # remainder -1: -7 = 2 * -3 + -1
    addi  t6, s5, 1
    seqz  t6, t6            # check 6
    add   a0, a0, t6

    # Divide by zero: no trap, defined results
    divu  s6, t0, zero      # quotient: all ones
    addi  t6, s6, 1
    seqz  t6, t6            # check 7
    add   a0, a0, t6
    rem   s7, t0, zero      # remainder: the dividend, -7
    sub   t6, s7, t0
    seqz  t6, t6            # check 8
    add   a0, a0, t6

    # Overflow: -2^63 / -1
    li    t2, 1
    slli  t2, t2, 63        # t2 = -2^63 = 0x8000000000000000, the smallest i64
    li    t3, -1
    div   s8, t2, t3        # +2^63 doesn't fit: quotient = the dividend
    sub   t6, s8, t2
    seqz  t6, t6            # check 9
    add   a0, a0, t6
    rem   s9, t2, t3        # remainder 0
    seqz  t6, s9            # check 10
    add   a0, a0, t6

    ebreak                  # a0 = 42 + 10 = 52
